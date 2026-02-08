#include "../include/common.h"
#include "../include/cuda_utils.h"

__global__ void dagSweep(
    const int* const __restrict__ row_ptr,
    const int* const __restrict__ col_ind,
    const int* const __restrict__ sorted_nodes,
    unsigned long long* const __restrict__ node_masks, // volatile??
    int* const __restrict__ assign_status,       // volatile??
    int level_start, int level_end,
    int batch_start_pair
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int idx = level_start + tid; idx < level_end; idx += stride) {
        int u = sorted_nodes[idx];

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
                if (u % 2 == 0) {
                    assign_status[u]   = 1;
                    assign_status[u+1] = 0;
                } else {
                    assign_status[u]   = 0;
                    assign_status[u-1] = 1;
                }
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
}


int* computeBackbone(
    const CSRRepr& d_graph,
    const TopoResult& topo_sort
) {
    int num_nodes = d_graph.num_nodes;
    // Bit i of d_node_masks[j] indicates whether the node j is reachable
    // from node 2*i or node 2*i+1
    unsigned long long* d_node_masks;
    // Status flags for original variables, 0 = FALSE, 1 = TRUE
    int* d_assign_status;
    CUDA_CHECK(cudaMalloc(&d_node_masks, d_graph.num_nodes * sizeof(unsigned long long)));
    CUDA_CHECK(cudaMalloc(&d_assign_status, d_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_assign_status, -1, d_graph.num_nodes * sizeof(int)));

    // Loop over all pairs of literals in chunks of 64
    for (int batch = 0; batch < num_nodes/2; batch += 64) {
        
        // Reset masks to 0 for this batch
        cudaMemset(d_node_masks, 0, d_graph.num_nodes * sizeof(unsigned long long));

        // Propagate reachability information through the DAG in topological order
        for (size_t i = 0; i < topo_sort.num_levels; i++) {
            int start = topo_sort.level_starts[i];
            int end   = topo_sort.level_starts[i+1];
            int count = end - start;

            if (count == 0) continue;

            // Propagate reachability for this level
            int blocks = gridStrideBlocks(count);
            dagSweep<<<blocks, NumThPerBlock>>>(
                d_graph.row_ptr,
                d_graph.col_ind,
                topo_sort.d_topo_order,
                d_node_masks,
                d_assign_status,
                start,
                end,
                batch
            );
        }
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_node_masks));

    return d_assign_status;
}