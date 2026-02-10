#include "../include/common.h"
#include "../include/cuda_utils.h"

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/functional.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/tuple.h>

// Assign false to the sinks in odd WCCs, and true to their complements
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
        // Check if node is in an even WCC and not already assigned
        if (wcc_map[i] % 2 == 0 || assignments[i] != -1) {
            continue;
        }

        // Check all outgoing edges
        bool has_outgoing = false;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++) {
            int neighbor = col_ind[j];
            // If we find an outgoing edge to a node not assigned, then it's not a sink
            if (assignments[neighbor] == -1) {
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

// Find sinks and put to them to false
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


// Count the number of sinks for each WCC
__global__ void countSinks(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind,
    const int* const __restrict__ assignments,
    int num_nodes,
    int* const __restrict__ num_sinks,
    bool* const __restrict__ is_sink,
    const int* const __restrict__ wcc_map
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_nodes; i += stride) {
        // Check if node is not already assigned
        if (assignments[i] != -1) {
            continue;
        }

        // Check all outgoing edges
        bool has_outgoing = false;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; j++) {
            int neighbor = col_ind[j];
            // If we find an outgoing edge to a node that is not assigned, then it's not a sink
            if (assignments[neighbor] == -1) {
                has_outgoing = true;
                break;
            }
        }

        // If no outgoing edges to unassigned nodes in WCCs, it's a sink
        if (!has_outgoing) {
            atomicAdd(&num_sinks[wcc_map[i]], 1);
            is_sink[i] = true;
        }
    }
}

// For each pair of nodes, check if one of them is a sink
// If so, assign false to the sink that has less sinks in its WCC, and true to the other one
__global__ void assignMinSinks(
    const int* const __restrict__ num_sinks,
    const bool* const __restrict__ is_sink,
    const int* const __restrict__ wcc_map,
    int num_pairs,
    int* const __restrict__ assignments
) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_pairs; i += stride) {
        int idx0 = 2 * i;
        int idx1 = idx0 + 1;

        if (assignments[idx0] != -1) {
            continue; // Node already assigned
        }

        bool sink0 = is_sink[idx0];
        bool sink1 = is_sink[idx1];
        if (!sink0 && !sink1) {
            continue; // None of the nodes is a sink, skip
        }

        // Quello che è un sink, è nel WCC con meno sink?
        // Se si assegna false a quello, true all'altro. Altrimenti, lascia tutto com'è
        int wcc0 = wcc_map[idx0];
        int wcc1 = wcc_map[idx1];
        int n_sinks0 = num_sinks[wcc0];
        int n_sinks1 = num_sinks[wcc1];
        int has_wcc0_less_sinks = (n_sinks0 < n_sinks1) || (n_sinks0 == n_sinks1 && wcc0 < wcc1);
        
        if (sink0 && has_wcc0_less_sinks) {
            assignments[idx0] = 2; // False
            assignments[idx1] = 3; // True
        } else if (sink1 && !has_wcc0_less_sinks) {
            assignments[idx1] = 2; // False
            assignments[idx0] = 3; // True
        }
    }
}

// Find sources and sinks, check witch is less and assign accordingly
void heuristic2(CSRRepr scc_graph, int* backbone_assignments, int* d_wcc_map) {
    int* d_num_sinks;
    CUDA_CHECK(cudaMalloc(&d_num_sinks, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_num_sinks, 0, scc_graph.num_nodes * sizeof(int)));

    bool* d_is_sink;
    CUDA_CHECK(cudaMalloc(&d_is_sink, scc_graph.num_nodes * sizeof(bool)));
    CUDA_CHECK(cudaMemset(d_is_sink, false, scc_graph.num_nodes * sizeof(bool)));

    int numBlocks = gridStrideBlocks(scc_graph.num_nodes);
    countSinks<<<numBlocks, NumThPerBlock>>>(
        scc_graph.row_ptr,
        scc_graph.col_ind,
        backbone_assignments,
        scc_graph.num_nodes,
        d_num_sinks,
        d_is_sink,
        d_wcc_map
    );

    int num_pairs = scc_graph.num_nodes / 2;
    assignMinSinks<<<gridStrideBlocks(num_pairs), NumThPerBlock>>>(
        d_num_sinks,
        d_is_sink,
        d_wcc_map,
        num_pairs,
        backbone_assignments
    );

    // Cleanup
    CUDA_CHECK(cudaFree(d_num_sinks));
    CUDA_CHECK(cudaFree(d_is_sink));
}


// Propagate the number of nodes reachable forwards by each node in the DAG
// by processing the nodes in reverse topological order (children before parents)
__global__ void propagateReachability(
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

        // Node is already assigned, skip
        if (assignments[u] != -1) {
            reach_bits[u] = 0;
            continue;
        }

        // I can reach myself
        unsigned long long my_bits = 0;
        if (u >= batch_start_idx && u < batch_start_idx + 64) {
            my_bits = (1ULL << (u - batch_start_idx));
        }

        // I can reach all the nodes that my children can reach
        for (int e = row_ptr[u]; e < row_ptr[u+1]; ++e) {
            int v = col_ind[e];
            my_bits |= reach_bits[v];
        }

        reach_bits[u] = my_bits;
    }
}

// Count the number the number of nodes reachable in this batch
__global__ void accumulate_counts(
    int num_nodes, 
    const unsigned long long* const __restrict__ reach_bits, 
    int* const __restrict__ total_reach_counts
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;
    for (int idx = tid; idx < num_nodes; idx += stride) {
        // __popcll counts number of set bits in a 64-bit integer
        total_reach_counts[idx] += __popcll(reach_bits[idx]);
    }
}

// Compute the number of nodes reachable by each node
// TODO: Maybe we can optime this by only computing the number reachability in each WCC
// Also, we only need the count of the sources
void countReachability(CSRRepr scc_graph, TopoResult topo_result, int* assignments, int* d_reach_counts) {
    unsigned long long *d_reach_bits;
    CUDA_CHECK(cudaMalloc(&d_reach_bits, scc_graph.num_nodes * sizeof(unsigned long long)));

    for (int batch_start = 0; batch_start < scc_graph.num_nodes; batch_start += 64) {
        // Initialize reachability bits for this batch
        CUDA_CHECK(cudaMemset(d_reach_bits, 0, scc_graph.num_nodes * sizeof(unsigned long long)));

        // Process levels in reverse topological order (children before parents)
        for (int level = topo_result.num_levels - 1; level >= 0; level--) {
            int level_start = topo_result.level_starts[level];
            int level_end = topo_result.level_starts[level + 1];
            int level_count = level_end - level_start;

            if (level_count == 0) continue;

            propagateReachability<<<gridStrideBlocks(level_count), NumThPerBlock>>>(
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
    }

    CUDA_CHECK(cudaFree(d_reach_bits));
}


// Propagate the deletion of a node in both "complement" DAGs, the target node is assigned true
__global__ void processFrontierDeletion(
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

            // If v in not assigned, assign it to true (and it complement to false) 
            // and add to next frontier
            if (atomicCAS(&assignments[v], -1, 1) == -1) {
                assignments[v ^ 1] = 0;
                int out_idx = atomicAdd(out_count, 1);
                queue_out[out_idx] = v;
            }
        }
    }
}

// For each WCC pair choose to set sinks or sources
__global__ void initTargetFrontier(
    const int* const __restrict__ max_nodes,
    const int* const __restrict__ max_counts,
    int num_pairs,
    int* const __restrict__ assignments,
    int* const __restrict__ queue_out,
    int* const __restrict__ out_count
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int p = tid; p < num_pairs; p += stride) {
        int dag_1 = 1 + (p * 2);
        int dag_2 = dag_1 + 1;
        int max_dag = (max_counts[dag_1] >= max_counts[dag_2]) ? dag_1 : dag_2;
        int target = max_nodes[max_dag];

        if (target == -1 || max_counts[max_dag] <= 0) {
            continue;
        }

        // Assign target and its complement, then enqueue target.
        if (atomicCAS(&assignments[target], -1, 3) == -1) {
            assignments[target ^ 1] = 2;
            int out_idx = atomicAdd(out_count, 1);
            queue_out[out_idx] = target;
        }
    }
}


// Find witch node in each pair of WCC reaches the most nodes, remove it 
// and all the nodes reachable by it and their complements accordingly
bool deleteAndPropagate(
    CSRRepr scc_graph,
    int* d_assignments,
    const int* d_max_nodes,
    const int* d_max_counts,
    int num_wcc_pairs
) {
    int *d_queue_in, *d_queue_out, *d_count_out;
    CUDA_CHECK(cudaMalloc(&d_queue_in, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_out, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_count_out, sizeof(int)));
    CUDA_CHECK(cudaMemset(d_count_out, 0, sizeof(int)));

    // Initialize the frontier with the target nodes to delete (assigned to true)
    initTargetFrontier<<<gridStrideBlocks(num_wcc_pairs), NumThPerBlock>>>(
        d_max_nodes,
        d_max_counts,
        num_wcc_pairs,
        d_assignments,
        d_queue_in,
        d_count_out
    );

    int queue_size = 0;
    CUDA_CHECK(cudaMemcpy(&queue_size, d_count_out, sizeof(int), cudaMemcpyDeviceToHost));
    bool has_targets = queue_size > 0;

    while (queue_size > 0) {
        CUDA_CHECK(cudaMemset(d_count_out, 0, sizeof(int)));

        // Propagate the deletion
        processFrontierDeletion<<<gridStrideBlocks(queue_size), NumThPerBlock>>>(
            scc_graph.row_ptr,
            scc_graph.col_ind,
            d_assignments,
            d_queue_in,
            d_queue_out,
            d_count_out,
            queue_size
        );

        CUDA_CHECK(cudaMemcpy(&queue_size, d_count_out, sizeof(int), cudaMemcpyDeviceToHost));
        std::swap(d_queue_in, d_queue_out);
    }

    CUDA_CHECK(cudaFree(d_queue_in));
    CUDA_CHECK(cudaFree(d_queue_out));
    CUDA_CHECK(cudaFree(d_count_out));

    return has_targets;
}


// Comparison of two pairs (count, node_id) to get the max count
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

// Map node_id to its reachability count
struct CountLookup {
    const int* counts;
    __host__ __device__ int operator()(int node_id) const {
        return counts[node_id];
    }
};

// For each WCC find the node with the maximum reachability count and its count
void getMaxForWCC(
    const int* d_reach_counts, CSRRepr wcc_grouped, const int* d_sorted_wcc, // in
    int* d_wcc_max_nodes, int* d_wcc_max_counts                              // out
) {
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

    // WCC IDs must be grouped in d_sorted_wcc
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
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, d_sorted_wcc, scc_graph.num_nodes);

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

        // Delete all the nodes reachable by the node with max reachability in each WCC pair
        int num_wcc_pairs = (wcc_grouped.num_nodes - 1) / 2;
        bool h_has_change = deleteAndPropagate(
            scc_graph,
            backbone_assignments,
            d_max_nodes,
            d_max_counts,
            num_wcc_pairs
        );

        if (!h_has_change) {
            break; // No more nodes to remove
        }
        
        // Set d_reach_counts to 0 to all nodes that have backbone_assignments != -1
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

// Same has heuristic 3 but go forwards and backwards
void heuristic4(CSRRepr scc_graph, TopoResult topo_result, int* backbone_assignments, int* d_wcc_map) {
    // Get the reverse mapping
    int* d_sorted_wcc;
    CUDA_CHECK(cudaMalloc(&d_sorted_wcc, scc_graph.num_nodes * sizeof(int)));
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, d_sorted_wcc, scc_graph.num_nodes);

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

        // Delete all the nodes reachable by the node with max reachability in each WCC pair
        int num_wcc_pairs = (wcc_grouped.num_nodes - 1) / 2;
        bool h_has_change = deleteAndPropagate(
            scc_graph,
            backbone_assignments,
            d_max_nodes,
            d_max_counts,
            num_wcc_pairs
        );

        if (!h_has_change) {
            break; // No more nodes to remove
        }
        
        // Set d_reach_counts to 0 to all nodes that have backbone_assignments != -1
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
void heuristic5(CSRRepr scc_graph, TopoResult topo_result, int* backbone_assignments, int* d_wcc_map) {
    // Get the reverse mapping
    int* d_sorted_wcc;
    CUDA_CHECK(cudaMalloc(&d_sorted_wcc, scc_graph.num_nodes * sizeof(int)));
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, d_sorted_wcc, scc_graph.num_nodes);

    // Count reachability for all nodes
    int* d_reach_counts;
    CUDA_CHECK(cudaMalloc(&d_reach_counts, scc_graph.num_nodes * sizeof(int)));

    // Allocate memory for the max node per WCC and its count
    int* d_max_nodes;
    int* d_max_counts;
    CUDA_CHECK(cudaMalloc(&d_max_nodes, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_max_counts, wcc_grouped.num_nodes * sizeof(int)));

    while (true) {
        // Count reachability for all nodes
        CUDA_CHECK(cudaMemset(d_reach_counts, 0, scc_graph.num_nodes * sizeof(int)));
        countReachability(scc_graph, topo_result, backbone_assignments, d_reach_counts);

        // Get node with max reachability for each WCC
        getMaxForWCC(d_reach_counts, wcc_grouped, d_sorted_wcc, d_max_nodes, d_max_counts);

        // Delete all the nodes reachable by the node with max reachability in each WCC pair
        int num_wcc_pairs = (wcc_grouped.num_nodes - 1) / 2;
        bool h_has_change = deleteAndPropagate(
            scc_graph,
            backbone_assignments,
            d_max_nodes,
            d_max_counts,
            num_wcc_pairs
        );

        if (!h_has_change) {
            break; // No more nodes to remove
        }
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_sorted_wcc));
    CUDA_CHECK(cudaFree(d_reach_counts));
    CUDA_CHECK(cudaFree(d_max_nodes));
    CUDA_CHECK(cudaFree(d_max_counts));
}
