#include "../include/common.h"
#include "../include/cuda_utils.h"

/**
 * Initialize each node to be its own parent
 */
__global__ void initParent(
    int* const __restrict__ parent, 
    const int* const __restrict__ assign_status, 
    const int num_nodes
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < num_nodes; i += stride) {
        if (assign_status && assign_status[i] != 0) {
            parent[i] = -1;
            continue;
        }
        parent[i] = i;
    }
}

/*
 * For each edge (u,v), attempt to hook the higher ID root to the lower ID root.
 */
__global__ void hook(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind, 
    const int* const __restrict__ assign_status, 
    int* const __restrict__ parent, 
    volatile bool* const __restrict__ d_changed, 
    const int num_nodes
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int u = tid; u < num_nodes; u += stride) {
        if (assign_status && assign_status[u] != 0) {
            continue;
        }
        int start_edge = row_ptr[u];
        int end_edge = row_ptr[u + 1];

        int root_u = parent[u];

        for (int e = start_edge; e < end_edge; ++e) {
            int v = col_ind[e];
            if (assign_status && assign_status[v] != 0) {
                continue;
            }
            int root_v = parent[v];

            if (root_u != root_v) {
                // We want to attach the node with the Higher ID to the Lower ID
                int high = (root_u > root_v) ? root_u : root_v;
                int low  = (root_u > root_v) ? root_v : root_u;

                // Change the parent of the higher ID root to be the lower ID root
                int old = atomicMin(&parent[high], low);

                // If the parent actually changed, we must flag for another iteration
                if (old != low) {
                    *d_changed = true;
                    // Update root_u for potential subsequent edges
                    if (root_u == high) root_u = low; 
                }
            }
        }
    }
}

/*
 * Compress the trees by making each node point to its grandparent
 */
__global__ void compress(
    int* const __restrict__ parent, 
    const int* const __restrict__ assign_status, 
    const int num_nodes, 
    volatile bool* const __restrict__ d_changed
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < num_nodes; i += stride) {
        if (assign_status && assign_status[i] != 0) {
            continue;
        }
        int p = parent[i];
        int gp = parent[p];

        if (p != gp) {
            parent[i] = gp;
            *d_changed = true;
        }
    }
}

/*
* Flatten the trees by making each node point to its grandparent until convergence
*/
__global__ void finalFlatten(
    int* const __restrict__ parent, 
    const int* const __restrict__ assign_status, 
    const int num_nodes
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int i = tid; i < num_nodes; i += stride) {
        if (assign_status && assign_status[i] != 0) {
            continue;
        }
        int p = parent[i];
        while (p != parent[p]) {
            p = parent[p];
        }
        parent[i] = p;
    }
}

int* computeWCC(CSRGraph& graph, const int* assign_status) {
    // Allocate device memory
    int* d_parent;
    bool* d_changed;
    int num_nodes = graph.num_nodes;
    CUDA_CHECK(cudaMalloc(&d_parent, num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_changed, sizeof(bool)));

    // Initialize Parents
    int blocks = gridStrideBlocks(num_nodes);
    initParent<<<blocks, NumThPerBlock>>>(d_parent, assign_status, num_nodes);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Hook and Compress until convergence
    bool h_changed = true;

    while (h_changed) {
        h_changed = false;
        CUDA_CHECK(cudaMemcpy(d_changed, &h_changed, sizeof(bool), cudaMemcpyHostToDevice));

        // Hook
        hook<<<blocks, NumThPerBlock>>>(graph.row_ptr, graph.col_ind, assign_status, d_parent, d_changed, num_nodes);
        // Compress
        compress<<<blocks, NumThPerBlock>>>(d_parent, assign_status, num_nodes, d_changed);
        
        CUDA_CHECK(cudaDeviceSynchronize());
        
        // Check convergence flag
        CUDA_CHECK(cudaMemcpy(&h_changed, d_changed, sizeof(bool), cudaMemcpyDeviceToHost));
    }

    // Final Flattening
    finalFlatten<<<blocks, NumThPerBlock>>>(d_parent, assign_status, num_nodes);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Cleanup
    CUDA_CHECK(cudaFree(d_changed));

    return d_parent;
}
