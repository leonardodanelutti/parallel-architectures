#include "../include/common.h"
#include "../include/cuda_utils.h"
#include <algorithm> // For std::min

// Kernel to process a massive chunk of batches in parallel
__global__ void dagSweep_multiBatch(
    const int* __restrict__ row_ptr,
    const int* __restrict__ col_ind,
    const int* __restrict__ sorted_nodes,
    unsigned long long* __restrict__ node_masks, // Now a 2D Grid
    int* __restrict__ assign_status,
    const int* __restrict__ level_starts,
    int num_levels,
    int num_nodes,
    int batch_size,
    int num_batches,
    int global_batch_offset // Tells the block which chunk of the graph it handles
) {
    int batch_idx = blockIdx.x;
    if (batch_idx >= num_batches) return;
    
    // Calculate the true global batch ID and the starting pair for this block
    int global_batch = global_batch_offset + batch_idx;
    int batch_start_pair = global_batch * batch_size;
    
    // Give this block its own isolated 1D array from the 2D grid
    unsigned long long* batch_masks = node_masks + ((size_t)batch_idx * num_nodes);

    // Propagate reachability information through the DAG in topological order
    for (int l = 0; l < num_levels; l++) {
        int start = level_starts[l];
        int end   = level_starts[l+1];
        int count = end - start;
        
        if (count == 0) continue;

        for (int idx = threadIdx.x; idx < count; idx += blockDim.x) {
            int u = sorted_nodes[start + idx];

            // Read from this block's specific mask
            unsigned long long my_mask = batch_masks[u]; 

            int pair_id = u / 2;
            int bit_idx = pair_id - batch_start_pair;

            // If the node belongs to the 64-pair target of this specific block
            if (bit_idx >= 0 && bit_idx < 64) {
                unsigned long long bit = (1ULL << bit_idx);

                // If bit is set, it means my "complement" is my ancestor.
                if (my_mask & bit) {
                    assign_status[u] = 1;
                    assign_status[u^1] = 0;
                }

                my_mask |= bit;
                batch_masks[u] = my_mask; // Save updated mask to block's memory
            }

            // Propagate to children
            if (my_mask != 0) {
                for (int i = row_ptr[u]; i < row_ptr[u+1]; i++) {
                    int v = col_ind[i];
                    atomicOr(&batch_masks[v], my_mask); // Write to block's memory
                }
            }
        }
        __syncthreads(); // Wait for all threads to finish the level before moving on
    }
}

int* computeBackbone(
    const CSRRepr& d_graph,
    const TopoResult& topo_sort
) {
    int num_nodes = d_graph.num_nodes;
    int batch_size = 64;
    int total_batches = (num_nodes / 2 + batch_size - 1) / batch_size;
    
    // --- VRAM Protection (Chunking) ---
    // Cap the maximum memory used by the 2D bitset grid to ~500 MB to prevent OOM.
    size_t bytes_per_batch = (size_t)num_nodes * sizeof(unsigned long long);
    size_t max_memory = 500ULL * 1024 * 1024; // 500 MB limit
    int batches_per_chunk = max_memory / bytes_per_batch;
    if (batches_per_chunk == 0) batches_per_chunk = 1; // Ensure we run at least 1 batch
    
    unsigned long long* d_node_masks;
    // Allocate only enough memory for one massive chunk
    CUDA_CHECK(cudaMalloc(&d_node_masks, (size_t)batches_per_chunk * bytes_per_batch));

    int* d_assign_status;
    CUDA_CHECK(cudaMalloc(&d_assign_status, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_assign_status, -1, num_nodes * sizeof(int)));

    int num_level_starts = topo_sort.num_levels + 1;
    int* d_level_starts;
    CUDA_CHECK(cudaMalloc(&d_level_starts, num_level_starts * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_level_starts, topo_sort.level_starts.data(), num_level_starts * sizeof(int), cudaMemcpyHostToDevice));

    // Process the graph in large chunks
    for (int chunk_start = 0; chunk_start < total_batches; chunk_start += batches_per_chunk) {
        
        // Calculate how many batches are in this specific chunk
        int current_chunk_batches = std::min(batches_per_chunk, total_batches - chunk_start);
        
        // Zero out only the memory needed for the current chunk
        CUDA_CHECK(cudaMemset(d_node_masks, 0, (size_t)current_chunk_batches * bytes_per_batch));

        // Use 256 threads per block for better GPU occupancy
        dagSweep_multiBatch<<<current_chunk_batches, 256>>>(
            d_graph.row_ptr,
            d_graph.col_ind,
            topo_sort.d_topo_order,
            d_node_masks,
            d_assign_status,
            d_level_starts,
            topo_sort.num_levels,
            num_nodes,
            batch_size,
            current_chunk_batches,
            chunk_start // Pass the global offset so the kernel targets the right nodes
        );
    }

    CUDA_CHECK(cudaFree(d_level_starts));
    CUDA_CHECK(cudaFree(d_node_masks));

    return d_assign_status;
}