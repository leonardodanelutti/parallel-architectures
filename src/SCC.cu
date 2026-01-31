#include "../include/common.h"
#include "../include/cuda_utils.h"


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


void calcSCC(const CSRGraph& graph) {
    // allocate GPU memory

    // work lists for edges
    int2 *d_wl1, *d_wl2;
    int wl_size = graph.num_edges;
    int *d_wl_size;
    // signature value for each node
    int2 *d_io_max;
    
    cudaMalloc(&d_wl1, graph.num_edges * sizeof(int2));
    cudaMalloc(&d_wl2, graph.num_edges * sizeof(int2));
    cudaMalloc(&d_wl_size, sizeof(int));
    cudaMalloc(&d_io_max, graph.num_nodes * sizeof(int2));

    const int blocks = 80; // SMs * (maxThreadsPerSM / ThreadsPerBlock)

    // initialize work lists and iomax
    globalInit<<<blocks, NumThPerBlock>>>(graph, d_wl1, d_io_max);

    bool go_again = true;
    bool *d_go_again;
    cudaMalloc(&d_go_again, sizeof(bool));
    while (go_again) {
        // TODO: why async?

        // Propagate max values
        while (go_again) {
            cudaMemsetAsync(d_go_again, false, sizeof(bool)); // d_goagain = false; 
            propagateMax<<<blocks, NumThPerBlock>>>(d_wl1, wl_size, d_io_max, d_go_again);
            // copy back go_again
            cudaMemcpy(&go_again, d_go_again, sizeof(bool), cudaMemcpyDeviceToHost);
        }

        // Remove edges that cannot be part of an SCC
        cudaMemsetAsync(d_wl_size, 0, sizeof(int)); // d_wl_size = 0;
        removeEdges<<<blocks, NumThPerBlock>>>(d_wl1, d_wl2, wl_size, d_wl_size, d_io_max);
        // New working list is in d_wl2, swap pointers
        std::swap(d_wl1, d_wl2);
        // copy back new wl_size
        cudaMemcpyAsync(&wl_size, d_wl_size, sizeof(int), cudaMemcpyDeviceToHost);


        // Local re-initialization
        cudaMemsetAsync(d_go_again, 0, sizeof(bool)); // d_goagain = false;
        localInit<<<blocks, NumThPerBlock>>>(graph.num_nodes, d_io_max, d_go_again);
        // copy back go_again
        cudaMemcpy(&go_again, d_go_again, sizeof(bool), cudaMemcpyDeviceToHost);
    }

    // Cleanup
    cudaFree(d_wl1);
    cudaFree(d_wl2);
    cudaFree(d_wl_size);
    cudaFree(d_go_again);

    // TODO: think how to return the SCC results
}