// Compute the topological sort of a DAG represented in CSR format
#include "../include/common.h"
#include "../include/cuda_utils.h"

// Compute in-degrees of each node
__global__ void computeInDegrees(
    const int* const __restrict__ col_ind, 
    int* const __restrict__ in_degree, 
    int num_edges
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;

    if (tid < num_edges) {
        int target_node = col_ind[tid];
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

    if (tid < num_nodes) {
        if (in_degree[tid] == 0) {
            // Reserve a spot in the queue
            int idx = atomicAdd(queue_count, 1);
            queue[idx] = tid;
        }
    }
}

__global__ void processFrontier(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind, 
    int* const __restrict__ in_degree, 
    const int* const __restrict__ queue_in,
    const int queue_in_size,
    int* const __restrict__ queue_out,
    int* const __restrict__ queue_out_size,
    int* const __restrict__ topo_order,
    int* const __restrict__ topo_order_size
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;

    if (tid < queue_in_size) {
        // take element from input queue
        int u = queue_in[tid];

        // Add to topological order
        int order_idx = atomicAdd(topo_order_size, 1);
        topo_order[order_idx] = u;

        // "Remove" the node by decreasing in-degrees of its neighbors
        for (int edge_idx = row_ptr[u]; edge_idx < row_ptr[u + 1]; edge_idx++) {
            int v = col_ind[edge_idx];
            int new_in_degree = atomicSub(&in_degree[v], 1) - 1;
            if (new_in_degree == 0) {
                // Add to output queue
                int out_idx = atomicAdd(queue_out_size, 1);
                queue_out[out_idx] = v;
            }
        }
    }
}

int* topologicalSort(const CSRGraph& d_graph) {
    int num_nodes = d_graph.num_nodes;
    int num_edges = d_graph.num_edges;

    // Allocate device memory for topological order and its size
    int* d_topo_order;
    CUDA_CHECK(cudaMalloc(&d_topo_order, num_nodes * sizeof(int)));
    int* d_topo_order_size;
    CUDA_CHECK(cudaMalloc(&d_topo_order_size, sizeof(int)));
    CUDA_CHECK(cudaMemset(d_topo_order_size, 0, sizeof(int)));

    // Allocate device memory for in-degrees and queue
    int* d_in_degree;
    CUDA_CHECK(cudaMalloc(&d_in_degree, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_in_degree, 0, num_nodes * sizeof(int)));

    int* d_queue_in;
    int* d_queue_out;
    CUDA_CHECK(cudaMalloc(&d_queue_in, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_out, num_nodes * sizeof(int)));
    int* d_queue_size;
    CUDA_CHECK(cudaMalloc(&d_queue_size, sizeof(int)));
    CUDA_CHECK(cudaMemset(d_queue_size, 0, sizeof(int)));

    // Compute in-degrees
    int blockSize = 256;
    int numBlocksEdges = (num_edges + blockSize - 1) / blockSize;
    computeInDegrees<<<numBlocksEdges, blockSize>>>(d_graph.col_ind, d_in_degree, num_edges);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Find initial zero in-degree nodes
    int numBlocksNodes = (num_nodes + blockSize - 1) / blockSize;
    findZeros<<<numBlocksNodes, blockSize>>>(d_in_degree, num_nodes, d_queue_in, d_queue_size);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Process the queue
    int h_queue_size;
    CUDA_CHECK(cudaMemcpy(&h_queue_size, d_queue_size, sizeof(int), cudaMemcpyDeviceToHost));

    while (h_queue_size > 0) {

        int blockSize = 256;
        int numBlocksQueue = (h_queue_size + blockSize - 1) / blockSize;

        CUDA_CHECK(cudaMemset(d_queue_size, 0, sizeof(int)));
        
        processFrontier<<<numBlocksQueue, blockSize>>>(
            d_graph.row_ptr, 
            d_graph.col_ind, 
            d_in_degree, 
            d_queue_in,
            h_queue_size,
            d_queue_out,
            d_queue_size,
            d_topo_order,
            d_topo_order_size
        );
        CUDA_CHECK(cudaDeviceSynchronize());

        CUDA_CHECK(cudaMemcpy(&h_queue_size, d_queue_size, sizeof(int), cudaMemcpyDeviceToHost));

        // Swap queues
        std::swap(d_queue_in, d_queue_out);
    }

    // Clean up
    CUDA_CHECK(cudaFree(d_in_degree));
    CUDA_CHECK(cudaFree(d_queue_in));
    CUDA_CHECK(cudaFree(d_queue_out));
    CUDA_CHECK(cudaFree(d_queue_size));
    CUDA_CHECK(cudaFree(d_topo_order_size));

    return d_topo_order;
}