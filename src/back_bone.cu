#include "../include/common.h"
#include "../include/cuda_utils.h"
#include <algorithm>

__global__ void dagSweep(
    const int* __restrict__ row_ptr,
    const int* __restrict__ col_ind,
    const int* __restrict__ sorted_nodes,
    unsigned long long* __restrict__ node_masks,
    int* __restrict__ assign_status,
    const int* __restrict__ level_starts,
    int num_levels,
    int num_nodes,
    int batch_size,
    int num_batches,
    int global_batch_offset
) {
    int batch_idx = blockIdx.x;
    if (batch_idx >= num_batches) return;
    
    // Each block processes a chunk of 64 pairs of nodes.
    int global_batch = global_batch_offset + batch_idx; // Which batch in the global graph this block is responsible for
    int batch_start_pair = global_batch * batch_size;   // The first pair index for this batch

    // Each block gets its own 1D mask array for all nodes (2D grid in memory)
    unsigned long long* batch_masks = node_masks + ((size_t)batch_idx * num_nodes);

    // Traverse the DAG in topological order, level by level
    for (int l = 0; l < num_levels; l++) {
        int start = level_starts[l];
        int end   = level_starts[l+1];
        int count = end - start;
        if (count == 0) continue;

        // Each thread processes a subset of nodes in this level
        for (int idx = threadIdx.x; idx < count; idx += blockDim.x) {
            int u = sorted_nodes[start + idx];

            // Load this node mask for this batch
            unsigned long long my_mask = batch_masks[u];

            // Each batch is responsible for 64 pairs, compute the bit index for this node
            int pair_id = u / 2;
            int bit_idx = pair_id - batch_start_pair;

            // If this node is in the current batch, set/check its bit
            if (bit_idx >= 0 && bit_idx < 64) {
                unsigned long long bit = (1ULL << bit_idx);

                // If my complement is my ancestor, mark assignments
                if (my_mask & bit) {
                    assign_status[u] = 1;
                    assign_status[u^1] = 0;
                }

                // Mark myself as reachable in this batch
                my_mask |= bit;
                batch_masks[u] = my_mask;
            }

            // Propagate my reachability mask to all children
            if (my_mask != 0) {
                for (int i = row_ptr[u]; i < row_ptr[u+1]; i++) {
                    int v = col_ind[i];
                    atomicOr(&batch_masks[v], my_mask);
                }
            }
        }
        // Synchronize all threads before moving to the next level
        __syncthreads();
    }
}

int* computeBackbone(
    const CSRRepr& d_graph,
    const TopoResult& topo_sort
) {
    int num_nodes = d_graph.num_nodes;
    int batch_size = 64;
    int total_batches = (num_nodes / 2 + batch_size - 1) / batch_size;
    
    // To avoid out-of-memory, we process the graph in chunks, each chunk handling several batches (windows of 64 pairs).
    size_t bytes_per_batch = (size_t)num_nodes * sizeof(unsigned long long);
    size_t max_memory = 8ULL * 1024 * 1024 * 1024; // 8GB limit
    int batches_per_chunk = max_memory / bytes_per_batch;
    if (batches_per_chunk == 0) batches_per_chunk = 1; // Always process at least one batch per chunk

    // Allocate enough memory for one chunk of batches
    unsigned long long* d_node_masks;
    CUDA_CHECK(cudaMalloc(&d_node_masks, (size_t)batches_per_chunk * bytes_per_batch));

    // Output: backbone assignment status for each node
    int* d_assign_status;
    CUDA_CHECK(cudaMalloc(&d_assign_status, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_assign_status, -1, num_nodes * sizeof(int)));

    // Copy level start indices to device for topological traversal
    int num_level_starts = topo_sort.num_levels + 1;
    int* d_level_starts;
    CUDA_CHECK(cudaMalloc(&d_level_starts, num_level_starts * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_level_starts, topo_sort.level_starts.data(), num_level_starts * sizeof(int), cudaMemcpyHostToDevice));

    // Process the graph in large chunks to save memory
    for (int chunk_start = 0; chunk_start < total_batches; chunk_start += batches_per_chunk) {
        // How many batches are in this chunk?
        int current_chunk_batches = std::min(batches_per_chunk, total_batches - chunk_start);

        // Zero out only the memory needed for the current chunk
        CUDA_CHECK(cudaMemset(d_node_masks, 0, (size_t)current_chunk_batches * bytes_per_batch));

        // Each block processes a batch
        dagSweep<<<current_chunk_batches, NumThPerBlock>>>(
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
            chunk_start
        );
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_level_starts));
    CUDA_CHECK(cudaFree(d_node_masks));

    return d_assign_status;
}