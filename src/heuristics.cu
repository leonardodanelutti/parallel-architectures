#include "../include/common.h"
#include "../include/cuda_utils.h"

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/functional.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/tuple.h>

__global__ void assignSinks(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind, 
    int num_nodes,
    const int* const __restrict__ wcc_map,
    int* const __restrict__ assignments
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_nodes; i += stride) {
        // Check if node is in an odd WCC and not already assigned
        if (wcc_map[i] % 2 == 0 || assignments[i] != -1) {
            continue;
        }

        // Check all outgoing edges
        bool has_outgoing = false;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++) {
            int neighbor = col_ind[j];
            // If we find an outgoing edge to a node in an odd WCC that is not assigned, then it's not a sink
            if (wcc_map[neighbor] % 2 == 1 && assignments[neighbor] == -1) {
                has_outgoing = true;
                break;
            }
        }

        // If no outgoing edges to unassigned nodes in odd WCCs, it's a sink
        if (!has_outgoing) {
            assignments[i] = 2;
            assignments[i ^ 1] = 3;
        }
    }
}

// Find sinks and put to false all sinks in odd wcc
void heuristic1(CSRRepr scc_graph, int* backbone_assignments, int* d_wcc_map) {
    int numBlocks = gridStrideBlocks(scc_graph.num_nodes);

    assignSinks<<<numBlocks, NumThPerBlock>>>(
        scc_graph.row_ptr, 
        scc_graph.col_ind, 
        scc_graph.num_nodes, 
        d_wcc_map, 
        backbone_assignments
    );
}

__global__ void countSinks(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind,
    const int* const __restrict__ assignments,
    int num_nodes,
    int* const __restrict__ num_sinks,
    const int* const __restrict__ wcc_map
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_nodes; i += stride) {
        // Check if node is in an odd WCC and not already assigned
        if (assignments[i] != -1) {
            continue;
        }

        // Check all outgoing edges
        bool has_outgoing = false;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++) {
            int neighbor = col_ind[j];
            // If we find an outgoing edge to a node in an odd WCC that is not assigned, then it's not a sink
            if (assignments[neighbor] == -1) {
                has_outgoing = true;
                break;
            }
        }

        // If no outgoing edges to unassigned nodes in odd WCCs, it's a sink
        if (!has_outgoing) {
            atomicAdd(&num_sinks[wcc_map[i]], 1);
        }
    }
}

__global__ void assignMinSinks(
    const int* const __restrict__ num_sinks,
    const int* const __restrict__ wcc_map,
    int num_pairs,
    int* const __restrict__ assignments
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_pairs; i += stride) {
        if (assignments[2*i] != -1) {
            continue;
        }

        if (num_sinks[wcc_map[2*i]] <= num_sinks[wcc_map[2*i+1]]) {
            assignments[2*i] = 2;
            assignments[2*i+1] = 3;
        } else {
            assignments[2*i] = 3;
            assignments[2*i+1] = 2;
        }
    }
}

// Find sources and sinks, check witch is less and assign accordingly
void heuristic2(CSRRepr scc_graph, int* backbone_assignments, int* d_wcc_map) {

    int* d_sorted_wcc;
    CUDA_CHECK(cudaMalloc(&d_sorted_wcc, scc_graph.num_nodes * sizeof(int)));
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, d_sorted_wcc, scc_graph.num_nodes);

    int numBlocks = gridStrideBlocks(scc_graph.num_nodes);
    int* d_num_sinks;
    CUDA_CHECK(cudaMalloc(&d_num_sinks, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_num_sinks, 0, wcc_grouped.num_nodes * sizeof(int)));

    countSinks<<<numBlocks, NumThPerBlock>>>(
        wcc_grouped.row_ptr, 
        wcc_grouped.col_ind,
        backbone_assignments,
        wcc_grouped.num_nodes, 
        d_num_sinks, 
        d_wcc_map
    );

    int num_pairs = scc_graph.num_nodes / 2;
    assignMinSinks<<<gridStrideBlocks(num_pairs), NumThPerBlock>>>(
        d_num_sinks,
        d_wcc_map,
        num_pairs,
        backbone_assignments
    );

    // TODO: syncro?

    // Cleanup
    CUDA_CHECK(cudaFree(d_num_sinks));
    CUDA_CHECK(cudaFree(d_sorted_wcc));
}

__global__ void propagate_reachability(
    int num_nodes,
    const int* const __restrict__ row_ptr,
    const int* const __restrict__ col_ind,
    const int* const __restrict__ nodes_in_level,      // Array of node IDs in this level
    int level_size,                 // How many nodes in this level
    const int* const __restrict__ assignments,
    unsigned long long* const __restrict__ reach_bits, // The bitset state (N x 1)
    int batch_start_idx             // The global index where this batch starts
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int idx = tid; idx < level_size; idx += stride) {
        int u = nodes_in_level[idx];

        // If node is ignored, it breaks the path (acts as having no edges)
        // And it doesn't count itself.
        if (assignments[u] != -1) {
            reach_bits[u] = 0;
            return;
        }

        // Initialize with self-reachability
        // If u is within the current batch range [batch_start, batch_end), set its bit
        unsigned long long my_bits = 0;
        if (u >= batch_start_idx && u < batch_start_idx + 64) {
            my_bits = (1ULL << (u - batch_start_idx));
        }

        // Union with children
        int start_edge = row_ptr[u];
        int end_edge = row_ptr[u+1];

        for (int e = start_edge; e < end_edge; ++e) {
            int v = col_ind[e];
            my_bits |= reach_bits[v];
        }

        reach_bits[u] = my_bits;
    }
}

__global__ void accumulate_counts(
    int num_nodes, 
    const unsigned long long* reach_bits, 
    int* total_reach_counts
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int idx = tid; idx < num_nodes; idx += stride) {
        // __popcll counts number of set bits in a 64-bit integer
        total_reach_counts[idx] += __popcll(reach_bits[idx]);
    }
}

void countReachability(CSRRepr scc_graph, TopoResult topo_result, int* assignments, int* d_reach_counts) {
    unsigned long long *d_reach_bits;
    CUDA_CHECK(cudaMalloc(&d_reach_bits, scc_graph.num_nodes * sizeof(unsigned long long)));

    for (int batch_start = 0; batch_start < scc_graph.num_nodes; batch_start += 64) {
        // Initialize reachability bits for this batch
        CUDA_CHECK(cudaMemset(d_reach_bits, 0, scc_graph.num_nodes * sizeof(unsigned long long)));

        // Process levels in topological order
        for (int level = 0; level < topo_result.num_levels; level++) {
            int level_start = topo_result.level_starts[level];
            int level_end = topo_result.level_starts[level + 1];
            int level_count = level_end - level_start;

            if (level_count == 0) continue;

            propagate_reachability<<<gridStrideBlocks(level_end - level_start), NumThPerBlock>>>(
                scc_graph.num_nodes,
                scc_graph.row_ptr,
                scc_graph.col_ind,
                topo_result.d_topo_order + level_start,
                level_count,
                assignments,
                d_reach_bits,
                batch_start
            );
        }

        // After processing all levels, accumulate reachability counts
        accumulate_counts<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
            scc_graph.num_nodes,
            d_reach_bits,
            d_reach_counts
        );

        CUDA_CHECK(cudaFree(d_reach_bits));
    }
}

__global__ void processFrontier(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind, 
    int* const __restrict__ assignments, 
    const int* const __restrict__ queue_in,
    int* const __restrict__ queue_out,
    int* const __restrict__ out_count,
    int frontier_size
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int idx = tid; idx < frontier_size; idx += stride) {
        int u = queue_in[idx];

        // Propagate assignment to neighbors
        for (int i = row_ptr[u]; i < row_ptr[u+1]; ++i) {
            int v = col_ind[i];

            if (atomicCAS(&assignments[v], -1, 1) == -1) {
                assignments[v ^ 1] = 0;
                int out_idx = atomicAdd(out_count, 1);
                queue_out[out_idx] = v;
            }
        }
    }
}

// Propagate deletion of a node in both "complement" DAGs
void propagateDeletion(CSRRepr scc_graph, int* d_assignments, int target_node) {
    int *d_queue_in, *d_queue_out, *d_count_out;
    CUDA_CHECK(cudaMalloc(&d_queue_in, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_out, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_count_out, sizeof(int)));

    // Initialize queue with the target node
    int two = 2;
    int three = 3;
    cudaMemcpy(&d_assignments[target_node^1], &two, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(&d_assignments[target_node], &three, sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_queue_in, &target_node, sizeof(int), cudaMemcpyHostToDevice);
    int queue_size = 1;

    while (queue_size > 0) {
        // reset output count
        CUDA_CHECK(cudaMemset(d_count_out, 0, sizeof(int)));
        
        // Process the current frontier
        processFrontier<<<gridStrideBlocks(queue_size), NumThPerBlock>>>(
            scc_graph.row_ptr,
            scc_graph.col_ind,
            d_assignments,
            d_queue_in,
            d_queue_out,
            d_count_out,
            queue_size
        );

        // Get the size of the next frontier
        CUDA_CHECK(cudaMemcpy(&queue_size, d_count_out, sizeof(int), cudaMemcpyDeviceToHost));

        // Swap queues
        std::swap(d_queue_in, d_queue_out);
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_queue_in));
    CUDA_CHECK(cudaFree(d_queue_out));
    CUDA_CHECK(cudaFree(d_count_out));
}

struct MaxCountNode {
    __host__ __device__ thrust::tuple<int, int> operator()(
        const thrust::tuple<int, int>& a,
        const thrust::tuple<int, int>& b
    ) const {
        if (thrust::get<0>(a) >= thrust::get<0>(b)) {
            return a;
        }
        return b;
    }
};

struct CountLookup {
    const int* counts;
    __host__ __device__ int operator()(int node_id) const {
        return counts[node_id];
    }
};

void getMaxForWCC(const int* d_reach_counts, CSRRepr wcc_grouped, const int* d_sorted_wcc, int* d_wcc_max_nodes, int* d_wcc_max_counts) {
    int* d_wcc_keys_out;
    CUDA_CHECK(cudaMalloc(&d_wcc_keys_out, wcc_grouped.num_nodes * sizeof(int)));

    CountLookup lookup{d_reach_counts};
    // Lazily map node_id -> reach_count without a temporary buffer.
    auto col_ind_ptr = thrust::device_ptr<int>(wcc_grouped.col_ind);
    auto counts_begin = thrust::make_transform_iterator(col_ind_ptr, lookup);
    // Values are (reach_count, node_id); reducer keeps the tuple with the larger count.
    auto values_begin = thrust::make_zip_iterator(
        thrust::make_tuple(
            counts_begin,
            col_ind_ptr
        )
    );
    auto out_values_begin = thrust::make_zip_iterator(
        thrust::make_tuple(
            thrust::device_ptr<int>(d_wcc_max_counts),
            thrust::device_ptr<int>(d_wcc_max_nodes)
        )
    );

    // WCC IDs must be grouped in d_sorted_wcc (same order as wcc_grouped.col_ind).
    thrust::reduce_by_key(
        thrust::device,
        thrust::device_ptr<const int>(d_sorted_wcc),
        thrust::device_ptr<const int>(d_sorted_wcc + wcc_grouped.num_edges),
        values_begin,
        thrust::device_ptr<int>(d_wcc_keys_out),
        out_values_begin,
        cuda::std::equal_to<int>(),
        MaxCountNode()
    );

    CUDA_CHECK(cudaFree(d_wcc_keys_out));
}


// Compute the number of nodes reachable forwards or backwards. Find the node that reaches the most nodes, remove it and all the nodes ahead/behind accordingly, and repeat
void heuristic3(CSRRepr scc_graph, TopoResult topo_result, int* backbone_assignments, int* d_wcc_map) {
    // Get the reverse mapping
    int* d_sorted_wcc;
    CUDA_CHECK(cudaMalloc(&d_sorted_wcc, scc_graph.num_nodes * sizeof(int)));
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, nullptr, scc_graph.num_nodes);

    // Count reachability for all nodes
    int* d_reach_counts;
    CUDA_CHECK(cudaMalloc(&d_reach_counts, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_reach_counts, 0, scc_graph.num_nodes * sizeof(int)));

    countReachability(scc_graph, topo_result, backbone_assignments, d_reach_counts);

    // Allocate memory for the max node per WCC and its count
    int* d_max_nodes;
    int* d_max_counts;
    CUDA_CHECK(cudaMalloc(&d_max_nodes, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_max_counts, wcc_grouped.num_nodes * sizeof(int)));

    while (true) {
        // Get node with max reachability for each WCC
        getMaxForWCC(d_reach_counts, wcc_grouped, d_sorted_wcc, d_max_nodes, d_max_counts);

        // Propagate the deletion of the chosen node and all the nodes ahead accordingly
        bool h_has_change = false;
        for (int i = 0; i < wcc_grouped.num_nodes; i=i+2) {
            // DAGs are shifted by 1, the first node corresponds to backbones
            int dag_1 = i+1;
            // The "complement"  DAG
            int dag_2 = (i^1)+1;
            int max_dag = d_max_counts[dag_1] >= d_max_counts[dag_2] ? dag_1 : dag_2;
            int target_node = d_max_nodes[max_dag];
            if (target_node == -1 || d_max_counts[max_dag] <= 0) continue;
            h_has_change = true;

            // Assign the target and propagate in both DAGs
            propagateDeletion(scc_graph, backbone_assignments, target_node);
        }

        if (!h_has_change) {
            break; // No more nodes to remove
        }
        
        // Update max: all nodes that have backbone_assignments != -1 should have their d_reach_counts set to 0
        thrust::device_ptr<int> d_reach_counts_ptr(d_reach_counts);
        thrust::device_ptr<int> d_assignments_ptr(backbone_assignments);
        thrust::transform(
            d_reach_counts_ptr,
            d_reach_counts_ptr + scc_graph.num_nodes,
            d_assignments_ptr,
            d_reach_counts_ptr,
            [] __device__ (int count, int assignment) {
                return assignment != -1 ? 0 : count;
            }
        );
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_sorted_wcc));
    CUDA_CHECK(cudaFree(d_reach_counts));
    CUDA_CHECK(cudaFree(d_max_nodes));
    CUDA_CHECK(cudaFree(d_max_counts));
}

// Same as heuristic3 but re-compute the reachability counts after each iteration.
void heuristic4(CSRRepr scc_graph, int* backbone_assignments, int* d_wcc_map) {
    // Compute transpose of the graph
}
