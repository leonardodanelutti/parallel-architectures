// Compute the topological sort of a DAG represented in CSR format
#include "../include/common.h"
#include "../include/cuda_utils.h"

#include <vector>

struct TopoResult {
    int* d_topo_order;
    std::vector<int> level_starts;
    int num_levels;
};

// Compute in-degrees of each node
__global__ void computeInDegrees(
    const int* const __restrict__ col_ind, 
    int* const __restrict__ in_degree, 
    int num_edges
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_edges; i += stride) {
        int target_node = col_ind[i];
        atomicAdd(&in_degree[target_node], 1);
    }
}

__global__ void findZeros(
    const int* const __restrict__ in_degree,
    int num_nodes,
    int* const __restrict__ queue,
    int* const __restrict__ queue_count
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_nodes; i += stride) {
        if (in_degree[i] == 0) {
            // Reserve a spot in the queue
            int idx = atomicAdd(queue_count, 1);
            queue[idx] = i;
        }
    }
}

__global__ void processFrontier(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind, 
    int* const __restrict__ in_degree, 
    int* const __restrict__ topo_order,
    int* const __restrict__ global_counter,
    int current_level_start,
    int current_level_end
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int idx = current_level_start + tid; idx < current_level_end; idx += stride) {
        // take element from input queue
        int u = topo_order[idx];
        
        // "Remove" the node by decreasing in-degrees of its neighbors
        for (int edge_idx = row_ptr[u]; edge_idx < row_ptr[u + 1]; edge_idx++) {
            int v = col_ind[edge_idx];
            
            int old_in_degree = atomicSub(&in_degree[v], 1);
            if (old_in_degree == 1) {
                // Add to output queue
                int out_idx = atomicAdd(global_counter, 1);
                topo_order[out_idx] = v;
            }
        }
    }
}

TopoResult topologicalSort(const CSRRepr& d_graph) {
    TopoResult result{};
    int num_nodes = d_graph.num_nodes;
    int num_edges = d_graph.num_edges;

    // Allocate device memory for topological order
    int* d_topo_order;
    CUDA_CHECK(cudaMalloc(&d_topo_order, num_nodes * sizeof(int)));

    // Counter for the back of the topo order queue
    int* d_counter;
    CUDA_CHECK(cudaMalloc(&d_counter, sizeof(int)));
    CUDA_CHECK(cudaMemset(d_counter, 0, sizeof(int)));

    result.d_topo_order = d_topo_order;

    // Prepare host memory for level starts
    result.level_starts.clear();
    result.level_starts.reserve(num_nodes + 1);

    // Allocate device memory for in-degrees and queue
    int* d_in_degree;
    CUDA_CHECK(cudaMalloc(&d_in_degree, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_in_degree, 0, num_nodes * sizeof(int)));

    // Compute in-degrees
    int numBlocksEdges = gridStrideBlocks(num_edges);
    computeInDegrees<<<numBlocksEdges, NumThPerBlock>>>(d_graph.col_ind, d_in_degree, num_edges);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Find initial zero in-degree nodes
    int numBlocksNodes = gridStrideBlocks(num_nodes);
    findZeros<<<numBlocksNodes, NumThPerBlock>>>(d_in_degree, num_nodes, d_topo_order, d_counter);
    CUDA_CHECK(cudaDeviceSynchronize());

    result.level_starts.push_back(0);

    while (true) {
        int processed_count;
        CUDA_CHECK(cudaMemcpy(&processed_count, d_counter, sizeof(int), cudaMemcpyDeviceToHost));

        int prev_level_start = result.level_starts.back();
        int current_level_count = processed_count - prev_level_start;

        if (current_level_count == 0) break; // No more nodes to process

        result.level_starts.push_back(processed_count);

        // Process current level
        int numBlocksLevel = gridStrideBlocks(current_level_count);
        processFrontier<<<numBlocksLevel, NumThPerBlock>>>(
            d_graph.row_ptr,
            d_graph.col_ind,
            d_in_degree,
            d_topo_order,
            d_counter,
            prev_level_start,
            processed_count
        );
        CUDA_CHECK(cudaGetLastError());
        CUDA_CHECK(cudaDeviceSynchronize());
    }

    // Clean up
    CUDA_CHECK(cudaFree(d_in_degree));
    CUDA_CHECK(cudaFree(d_counter));

    result.num_levels = result.level_starts.size() - 1;
    return result;
}