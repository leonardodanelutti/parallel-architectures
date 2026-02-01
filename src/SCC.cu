#include "../include/common.h"
#include "../include/cuda_utils.h"

#include <thrust/device_ptr.h>
#include <thrust/device_vector.h>
#include <thrust/scan.h>
#include <thrust/sort.h>
#include <thrust/transform.h>
#include <thrust/unique.h>


/**
 * Initialize:
 * - work list by adding all edges
 * - io_max array with (v, max_outgoing_neighbor)
 */
__global__ void globalInit(const CSRGraph g, int2* const __restrict__ wl, int2* const __restrict__ io_max) {
    const int thread = threadIdx.x + blockIdx.x * NumThPerBlock;
    const int threads = gridDim.x * NumThPerBlock;

    for (int i = thread; i < g.num_nodes; i += threads) {
        const int begin = g.row_ptr[i];
        const int end   = g.row_ptr[i + 1];
        int y = i;
        // neighbors of i
        for (int j = begin; j < end; j++) {
            const int w = g.col_ind[j];
            wl[j] = int2{i, w};
            y = max(y, w);
        }
        io_max[i] = int2{i, y};
    }
}


/**
 * After edges are eliminated, re-initialize io_max to (i, i) for all nodes
 * check if any changes were made and set go_again accordingly
 */
__global__ void localInit(const int num_nodes, int2* const __restrict__ io_max, volatile bool* const __restrict__ go_again) {
    const int thread = threadIdx.x + blockIdx.x * NumThPerBlock;
    const int threads = gridDim.x * NumThPerBlock;

    bool again = false;
    for (int i = thread; i < num_nodes; i += threads) {
        const int2 val = io_max[i];
        if (val.x != val.y) {
            io_max[i] = int2{i, i};
            again = true;
        }
    }

    // Check if any thread set again to true
    again = __syncthreads_or(again);
    // if not, computation is done
    if ((thread == 0) && again) {
        *go_again = true;
    }
}


/**
 * Propagate maximum signatures along the edges in the work list
 * call this function until go_again is false
 */
__global__ void propagateMax(const int2* const __restrict__ wl, const int wl_size, int2* const __restrict__ io_max, volatile bool* const __restrict__ go_again) {
    const int thread = threadIdx.x + blockIdx.x * NumThPerBlock;
    const int threads = gridDim.x * NumThPerBlock;

    bool updated, again = false;
    do {
        updated = false;
        
        for (int i = thread; i < wl_size; i += threads) {
            const int2 edge = wl[i];
            const int u = edge.x;
            const int v = edge.y;

            const int2 io_u = io_max[u];
            const int2 io_v = io_max[v];

            int im = io_u.x;
            int om = io_v.y;

            // Path compression

            // Since the signature are initialized with vertex id and can only increase,
            // io_max[im].x >= im and io_max[om].y >= om
            if (im > u) im = io_max[im].x;
            if (om > v) om = io_max[om].y;

            // Update io_max of u and v
            if (io_u.x < im) { io_max[u].x = im; updated = true;}
            if (io_u.y < om) { io_max[u].y = om; updated = true;}
            if (io_v.x < im) { io_max[v].x = im; updated = true;}
            if (io_v.y < om) { io_max[v].y = om; updated = true;}

            // Before overwriting a signature value s in a vertex v with a larger value t,
            // we can check that the signature value in s is less than t, in which case we update it to t.
            if ((io_u.x < om) && (io_max[io_u.x].y < om)) {io_max[io_u.x].y = om; updated = true;}
            if ((io_u.x != io_v.x) && (io_v.x < om) && (io_max[io_v.x].y < om)) {io_max[io_v.x].y = om; updated = true;}
            if ((io_u.y < im) && (io_max[io_u.y].x < im)) {io_max[io_u.y].x = im; updated = true;}
            if ((io_u.y != io_v.y) && (io_v.y < im) && (io_max[io_v.y].x < im)) {io_max[io_v.y].x = im; updated = true;}           

        }
        // If any updates are made we need to run another iteration
        again |= updated;

    } while (__syncthreads_or(updated));

    // If any thread made an update, set go_again to true
    again = __syncthreads_or(again);
    // if not, computation is done
    if ((threadIdx.x == 0) && again) {
        *go_again = true;
    }
}

/**
 * Remove edges that cannot be part of an SCC
 * An edge (u,v) can be part of an SCC only if both endpoints have the same signature.
 * Also edges leading to nodes already in an SCC are removed.
 */
__global__ void removeEdges(const int2* const __restrict__ wl_in, int2* const __restrict__ wl_out, const int wl_size, int* const __restrict__ wl_out_size, const int2* const __restrict__ io_max) {
    const int thread = threadIdx.x + blockIdx.x * NumThPerBlock;
    const int threads = gridDim.x * NumThPerBlock;

    for (int i = thread; i < wl_size; i += threads) {
        const int2 edge = wl_in[i];
        const int u = edge.x;
        const int v = edge.y;

        const int2 io_u = io_max[u];
        const int2 io_v = io_max[v];

        // Keep edge only if both endpoints have the same signature and we are
        // not yet in an SCC (we are when io_v.x == io_v.y)
        if ((io_v.x != io_v.y) && (io_u.x == io_v.x) && (io_u.y == io_v.y)) {
            // atomic append to output work list
            const int pos = atomicAdd(wl_out_size, 1);
            wl_out[pos] = edge;
        }
    }
}

int* computeSCC(const CSRGraph& graph, int blocks) {
    // work lists for edges
    int2 *d_wl1, *d_wl2;
    int wl_size = graph.num_edges;
    int *d_wl_size;
    // signature value for each node
    int2 *d_io_max;

    CUDA_CHECK(cudaMalloc(&d_wl1, graph.num_edges * sizeof(int2)));
    CUDA_CHECK(cudaMalloc(&d_wl2, graph.num_edges * sizeof(int2)));
    CUDA_CHECK(cudaMalloc(&d_wl_size, sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_io_max, graph.num_nodes * sizeof(int2)));

    // initialize work lists and io_max
    globalInit<<<blocks, NumThPerBlock>>>(graph, d_wl1, d_io_max);

    bool go_again = true;
    bool *d_go_again;
    CUDA_CHECK(cudaMalloc(&d_go_again, sizeof(bool)));
    while (go_again) {
        // Propagate max values
        while (go_again) {
            CUDA_CHECK(cudaMemsetAsync(d_go_again, false, sizeof(bool))); // d_go_again = false;
            propagateMax<<<blocks, NumThPerBlock>>>(d_wl1, wl_size, d_io_max, d_go_again);
            // copy back go_again
            CUDA_CHECK(cudaMemcpy(&go_again, d_go_again, sizeof(bool), cudaMemcpyDeviceToHost));
        }

        // Remove edges that cannot be part of an SCC
        CUDA_CHECK(cudaMemsetAsync(d_wl_size, 0, sizeof(int))); // d_wl_size = 0;
        removeEdges<<<blocks, NumThPerBlock>>>(d_wl1, d_wl2, wl_size, d_wl_size, d_io_max);
        // New working list is in d_wl2, swap pointers
        std::swap(d_wl1, d_wl2);
        // copy back new wl_size
        CUDA_CHECK(cudaMemcpyAsync(&wl_size, d_wl_size, sizeof(int), cudaMemcpyDeviceToHost));

        // Local re-initialization
        CUDA_CHECK(cudaMemsetAsync(d_go_again, 0, sizeof(bool))); // d_go_again = false;
        localInit<<<blocks, NumThPerBlock>>>(graph.num_nodes, d_io_max, d_go_again);
        // copy back go_again
        CUDA_CHECK(cudaMemcpy(&go_again, d_go_again, sizeof(bool), cudaMemcpyDeviceToHost));
    }

    // Cleanup work lists and flags
    CUDA_CHECK(cudaFree(d_wl1));
    CUDA_CHECK(cudaFree(d_wl2));
    CUDA_CHECK(cudaFree(d_wl_size));
    CUDA_CHECK(cudaFree(d_go_again));

    // Convert io_max to just one signature value per node
    int *ssc_lookup;
    CUDA_CHECK(cudaMalloc(&ssc_lookup, graph.num_nodes * sizeof(int)));
    thrust::device_ptr<int2> dev_io_max_ptr(d_io_max);
    thrust::device_ptr<int> dev_id_map_ptr(ssc_lookup);
    thrust::transform(dev_io_max_ptr, dev_io_max_ptr + graph.num_nodes, dev_id_map_ptr, [] __device__ (const int2& val) {
        return val.x;
    });
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaFree(d_io_max));

    return ssc_lookup;
}

/**
 * Create a mapping from old SCC IDs to new contiguous SCC IDs, i.e.
 * new_id[i] = id_map_out[old_id[i]]
 */
__global__ void createMapping(const int* const __restrict__ unique_ids, const int num_unique_ids, int* const __restrict__ id_map_out) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_unique_ids) return;

    id_map_out[unique_ids[idx]] = idx;
}

/**
* Remap SCC IDs in id_map_out using id_map_in
*/
__global__ void mapSCCIds(const int* const __restrict__ id_map_in, const int num_nodes, int* const __restrict__ id_map_out) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_nodes) return;
    
    const int old_id = id_map_out[idx];
    id_map_out[idx] = id_map_in[old_id];
}

/**
 * Remap SCC IDs to contiguous range [0, num_sccs-1]
 */
int remapSCCIds(int num_nodes, int* d_ssc_lookup, int blocks) {
    // make it so id_map contains contiguous ids from 0 to num_scc-1
    thrust::device_ptr<int> dev_ssc_lookup_ptr(d_ssc_lookup);
    thrust::device_vector<int> d_unique_ids(dev_ssc_lookup_ptr, dev_ssc_lookup_ptr + num_nodes);
    thrust::sort(d_unique_ids.begin(), d_unique_ids.end());
    auto new_end = thrust::unique(d_unique_ids.begin(), d_unique_ids.end());
    const int h_scc_node_count = new_end - d_unique_ids.begin();
    
    int* d_id_map;
    CUDA_CHECK(cudaMalloc(&d_id_map, num_nodes * sizeof(int)));
    
    int blocks_mapping = (h_scc_node_count + NumThPerBlock - 1) / NumThPerBlock;
    createMapping<<<blocks_mapping, NumThPerBlock>>>(thrust::raw_pointer_cast(d_unique_ids.data()), h_scc_node_count, d_id_map);
    CUDA_CHECK(cudaDeviceSynchronize());
    // d_unique_ids goes out of scope and automatically frees its memory

    int blocks_remap = (num_nodes + NumThPerBlock - 1) / NumThPerBlock;
    mapSCCIds<<<blocks_remap, NumThPerBlock>>>(d_id_map, num_nodes, d_ssc_lookup);
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaFree(d_id_map));
    
    return h_scc_node_count;
}

/**
 * Create edge list for condensed graph of SCCs
 */
__global__ void createEdgeList(const CSRGraph g, const int* const __restrict__ scc_lookup, int2* const __restrict__ scc_edges, int* const __restrict__ scc_edge_count) {
    const int thread = threadIdx.x + blockIdx.x * NumThPerBlock;
    const int threads = gridDim.x * NumThPerBlock;

    for (int i = thread; i < g.num_nodes; i += threads) {
        const int begin = g.row_ptr[i];
        const int end   = g.row_ptr[i + 1];
        const int scc_u = scc_lookup[i];
        for (int j = begin; j < end; j++) {
            const int v = g.col_ind[j];
            const int scc_v = scc_lookup[v];
            if (scc_u != scc_v) {
                // atomic append to scc_edges
                const int pos = atomicAdd(scc_edge_count, 1);
                scc_edges[pos] = int2{scc_u, scc_v};
            }
        }
    }
}

/**
 * Count number of outgoing edges per node to build row_ptr
 */
__global__ void countEdgesPerNode(const int2* const __restrict__ edges, const int num_edges, int* const __restrict__ row_ptr) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= num_edges) return;

    const int2 edge = edges[idx];
    atomicAdd(&row_ptr[edge.x + 1], 1);
}

/**
* Build CSRGraph from edge list
*/
CSRGraph buildCSRFromEdgeList(int2* d_edges, int num_edges, int num_nodes) {
    int* d_row_ptr;
    int* d_col_ind;
    CUDA_CHECK(cudaMalloc(&d_row_ptr, (num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_col_ind, num_edges * sizeof(int)));

    // Sort edge list (required to make CSR rows contiguous)
    thrust::device_ptr<int2> dev_edges_ptr(d_edges);
    thrust::sort(dev_edges_ptr, dev_edges_ptr + num_edges, [] __device__ (const int2& a, const int2& b) {
        return a.x < b.x || (a.x == b.x && a.y < b.y);
    });
    CUDA_CHECK(cudaDeviceSynchronize());

    // Compute the histogram for row_ptr
    int blocks_histogram = (num_edges + NumThPerBlock - 1) / NumThPerBlock;
    countEdgesPerNode<<<blocks_histogram, NumThPerBlock>>>(d_edges, num_edges, d_row_ptr);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Exclusive scan to get row_ptr
    thrust::device_ptr<int> dev_scc_row_ptr_ptr(d_row_ptr);
    thrust::exclusive_scan(dev_scc_row_ptr_ptr, dev_scc_row_ptr_ptr + num_nodes + 1, dev_scc_row_ptr_ptr);
    CUDA_CHECK(cudaDeviceSynchronize());

    // Create col_ind by copying from edge list the second element of each edge
    thrust::device_ptr<int2> dev_scc_edges_ptr(d_edges);
    thrust::device_ptr<int> dev_scc_col_ind_ptr(d_col_ind);
    thrust::transform(dev_scc_edges_ptr, dev_scc_edges_ptr + num_edges, dev_scc_col_ind_ptr, [] __device__ (const int2& edge) {
        return edge.y;
    });
    CUDA_CHECK(cudaDeviceSynchronize());

    CSRGraph csr_graph;
    csr_graph.num_nodes = num_nodes;
    csr_graph.num_edges = num_edges;
    csr_graph.row_ptr = d_row_ptr;
    csr_graph.col_ind = d_col_ind;

    return csr_graph;
}

CSRGraph computeCondensedGraph(const CSRGraph& graph) {
    // allocate GPU memory
    const int blocks = 80; // SMs * (maxThreadsPerSM / ThreadsPerBlock)

    int *ssc_lookup = computeSCC(graph, blocks);

    // Remap sparse SCC IDs to dense range [0, num_sccs-1]
    const int scc_node_count = remapSCCIds(graph.num_nodes, ssc_lookup, blocks);

    // Create new edge list for condensed graph
    int2* d_scc_edges;
    CUDA_CHECK(cudaMalloc(&d_scc_edges, graph.num_edges * sizeof(int2)));
    int* d_scc_edge_count;
    CUDA_CHECK(cudaMalloc(&d_scc_edge_count, sizeof(int)));
    CUDA_CHECK(cudaMemset(d_scc_edge_count, 0, sizeof(int)));

    createEdgeList<<<blocks, NumThPerBlock>>>(graph, ssc_lookup, d_scc_edges, d_scc_edge_count);
    CUDA_CHECK(cudaDeviceSynchronize());
    CUDA_CHECK(cudaFree(ssc_lookup));
    CUDA_CHECK(cudaFree(d_scc_edge_count));

    // Build CSR representation of the condensed graph
    CSRGraph scc_graph = buildCSRFromEdgeList(d_scc_edges, graph.num_edges, scc_node_count);

    // Cleanup
    CUDA_CHECK(cudaFree(d_scc_edges));

    return scc_graph;
}