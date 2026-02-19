#include "../include/common.h"
#include "../include/cuda_utils.h"

// Propagate rachability information through the DAG in topological order. 
// Each thread block processes one batch of variable pairs (2*i, 2*i+1).
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
    int num_batches
) {
    int batch_idx = blockIdx.x;
    if (batch_idx >= num_batches) return;
    int batch_start_pair = batch_idx * batch_size;

    // Reset masks to 0 for this batch
    for (int i = threadIdx.x; i < num_nodes; i += blockDim.x) {
        node_masks[i] = 0ULL;
    }
    __syncthreads();

    // Propagate reachability information through the DAG in topological order
    for (int l = 0; l < num_levels; l++) {
        int start = level_starts[l];
        int end   = level_starts[l+1];
        int count = end - start;
        if (count == 0) continue;

        // Each thread processes multiple nodes in this level
        for (int idx = threadIdx.x; idx < count; idx += blockDim.x) {
            int u = sorted_nodes[start + idx];

            // Bits propagated from parents
            unsigned long long my_mask = node_masks[u];

            int pair_id = u / 2;
            int bit_idx = pair_id - batch_start_pair;

            // u is in the batch
            if (bit_idx >= 0 && bit_idx < 64) {
                unsigned long long bit = (1ULL << bit_idx);

                // If bit is set, it means my "complement" is my ancestor. 
                // Since it's a DAG, I can't reach myself, so it must be them.
                if (my_mask & bit) {
                    assign_status[u] = 1;
                    assign_status[u^1] = 0;
                }

                // Next nodes are reachable by me
                my_mask |= bit;
                node_masks[u] = my_mask;
            }

            // Propagate to children
            if (my_mask != 0) {
                for (int i = row_ptr[u]; i < row_ptr[u+1]; i++) {
                    int v = col_ind[i];
                    atomicOr(&node_masks[v], my_mask);
                }
            }
        }
        __syncthreads();
    }
}



int* computeBackbone(
    const CSRRepr& d_graph,
    const TopoResult& topo_sort
) {
    int num_nodes = d_graph.num_nodes;
    int batch_size = 64;
    int num_batches = (num_nodes/2 + batch_size - 1) / batch_size;
    // Bit i of d_node_masks[j] indicates whether the node j is reachable
    // from node 2*i or node 2*i+1
    unsigned long long* d_node_masks;
    // Status flags for original variables, 0 = FALSE, 1 = TRUE
    int* d_assign_status;
    CUDA_CHECK(cudaMalloc(&d_node_masks, d_graph.num_nodes * sizeof(unsigned long long)));
    CUDA_CHECK(cudaMalloc(&d_assign_status, d_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_assign_status, -1, d_graph.num_nodes * sizeof(int)));

    // Allocate and copy level_starts to device
    int num_level_starts = topo_sort.num_levels + 1;
    int* d_level_starts;
    CUDA_CHECK(cudaMalloc(&d_level_starts, num_level_starts * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_level_starts, topo_sort.level_starts.data(), num_level_starts * sizeof(int), cudaMemcpyHostToDevice));

    // Launch one block per batch, each block processes one batch
    dagSweep<<<num_batches, 64>>>(
        d_graph.row_ptr,
        d_graph.col_ind,
        topo_sort.d_topo_order,
        d_node_masks,
        d_assign_status,
        d_level_starts,
        topo_sort.num_levels,
        num_nodes,
        batch_size,
        num_batches
    );

    CUDA_CHECK(cudaFree(d_level_starts));
    CUDA_CHECK(cudaFree(d_node_masks));

    return d_assign_status;
}