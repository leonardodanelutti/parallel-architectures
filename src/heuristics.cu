#include "../include/common.h"
#include "../include/cuda_utils.h"

#include <thrust/device_ptr.h>
#include <thrust/execution_policy.h>
#include <thrust/functional.h>
#include <thrust/iterator/transform_iterator.h>
#include <thrust/iterator/zip_iterator.h>
#include <thrust/tuple.h>

typedef enum {
    HEUR_1 = 1,
    HEUR_2 = 2,
    HEUR_3 = 3,
    HEUR_4 = 4,
    HEUR_5 = 5
} HeuristicKind;


// Propagate the deletion of a literal, the target node is assigned true
// and its complement is assigned false.
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

// Assign True to the target literals and all the literals reachable from them.
// The complement literals are assigned False.
void deleteAndPropagate(
    CSRRepr scc_graph,
    int* d_assignments,
    int* d_queue_in,
    int* d_count_out
) {
    int *d_queue_out;
    CUDA_CHECK(cudaMalloc(&d_queue_out, scc_graph.num_nodes * sizeof(int)));

    int queue_size = 0;
    CUDA_CHECK(cudaMemcpy(&queue_size, d_count_out, sizeof(int), cudaMemcpyDeviceToHost));

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

// For each WCC find the node with the maximum property and its value
void getMaxForWCC(
    const int* d_property, CSRRepr wcc_grouped, const int* d_sorted_wcc, // in
    int* d_wcc_prop_nodes, int* d_wcc_prop_val                           // out
) {
    int* d_wcc_keys_out;
    CUDA_CHECK(cudaMalloc(&d_wcc_keys_out, wcc_grouped.num_nodes * sizeof(int)));

    CountLookup lookup{d_property};
    // Lazily map node_id -> reach_count without a temporary buffer.
    auto col_ind_ptr = thrust::device_ptr<int>(wcc_grouped.col_ind);
    auto values_begin = thrust::make_transform_iterator(col_ind_ptr, lookup);
    // Iterator elements are (reach_count, node_id); reducer keeps the tuple with the larger count.
    auto iter_begin = thrust::make_zip_iterator(
        thrust::make_tuple(
            values_begin,
            col_ind_ptr
        )
    );
    auto out_iter_begin = thrust::make_zip_iterator(
        thrust::make_tuple(
            thrust::device_ptr<int>(d_wcc_prop_val),
            thrust::device_ptr<int>(d_wcc_prop_nodes)
        )
    );

    // WCC IDs must be grouped in d_sorted_wcc
    thrust::reduce_by_key(
        thrust::device,
        thrust::device_ptr<const int>(d_sorted_wcc),
        thrust::device_ptr<const int>(d_sorted_wcc + wcc_grouped.num_edges),
        iter_begin,
        thrust::device_ptr<int>(d_wcc_keys_out),
        out_iter_begin,
        cuda::std::equal_to<int>(),
        MaxCountNode()
    );

    CUDA_CHECK(cudaFree(d_wcc_keys_out));
}

// Get the complement of a WCC, there can be 3 scenarios:
// 1) WCC id is -1, then it is a backbone and we set the result -1
// 2) The complement of a literal is in the same WCC, then we just set the same WCC id
// 3) The complement of a literal is in a different WCC, then we set the WCC id of the complement literal
//    and we set -1 to the WCC of the complement literal
__device__ int getWCCComplementKernel(
    int wcc_num,
    const int* const __restrict__ wcc_ids_sorted,
    const int num_wccs
) {
    int wcc_id = wcc_ids_sorted[wcc_num];
    // Backbone is -1 and if we are in case 2 the id is always even
    if (wcc_id % 2 == 0) {
        bool is_diff_wcc = (wcc_num < num_wccs - 1) && (wcc_ids_sorted[wcc_num + 1] == wcc_id+1);
        if (is_diff_wcc) {
            // Complement is in a different WCC
            return wcc_id + 1;
        } else {
            // Complement is in the same WCC
            return wcc_id;
        }
    }
    return -1; // For backbone and odd WCCs
}

__global__ void nodeToEliminate(
    const int* const __restrict__ nodes,
    const int* const __restrict__ max_property,
    const int* const __restrict__ wcc_sorted,
    int num_wcc,
    int* const __restrict__ force_wcc,
    int* const __restrict__ assignments,
    int* const __restrict__ queue_out,
    int* const __restrict__ out_count
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int p = tid; p < num_wcc; p += stride) {
        int dag_1 = p;
        int dag_2 = getWCCComplementKernel(p, wcc_sorted, num_wcc);
        if (dag_2 == -1) {
            continue; // No complement WCC, skip
        }

        int max_dag;
        if (force_wcc) {
            // If we have a forced WCC from the previous iteration, we must choose the other one
            if (force_wcc[p] != -1) {
                max_dag = (force_wcc[p] == 0) ? dag_2 : dag_1;
            } else {
                max_dag = (max_property[dag_1] >= max_property[dag_2]) ? dag_1 : dag_2;
                force_wcc[p] = (max_dag == dag_1) ? 0 : 1; // Store the chosen WCC for the next iteration
            }
        } else {
            max_dag = (max_property[dag_1] >= max_property[dag_2]) ? dag_1 : dag_2;
        }
        int target = nodes[max_dag];

        // Assign target and its complement, then enqueue target.
        if (atomicCAS(&assignments[target], -1, 3) == -1) {
            assignments[target ^ 1] = 2;
            int out_idx = atomicAdd(out_count, 1);
            queue_out[out_idx] = target;
        }
    }
}

__global__ void getSources(
    const int* const __restrict__ row_ptr, 
    const int* const __restrict__ col_ind,
    const int* const __restrict__ assignments,
    int num_nodes,
    int* const __restrict__ is_source
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
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
            // If we find an outgoing edge to a node not assigned, then it's not a sink
            if (assignments[neighbor] == -1) {
                has_outgoing = true;
                break;
            }
        }

        // If no outgoing edges to unassigned nodes, it's a sink
        if (!has_outgoing) {
            // the complement of a sink is a source
            is_source[i^1] = 1;
        }
    }
}

// Count outgoing edges for each node (assigned nodes are set to 0).
__global__ void countOutgoingEdges(
    const int* const __restrict__ row_ptr,
    const int* const __restrict__ col_ind,
    const int* const __restrict__ assignments,
    int num_nodes,
    int* const __restrict__ out_counts
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int i = tid; i < num_nodes; i += stride) {
        if (assignments[i] != -1) {
            out_counts[i] = 0;
            continue;
        }

        int count = 1;
        for (int j = row_ptr[i]; j < row_ptr[i + 1]; ++j) {
            int neighbor = col_ind[j];
            if (assignments[neighbor] == -1) {
                count++;
            }
        }
        out_counts[i] = count;
    }
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
__global__ void accumulateCounts(
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
        accumulateCounts<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
            scc_graph.num_nodes,
            d_reach_bits,
            d_reach_counts
        );
    }

    CUDA_CHECK(cudaFree(d_reach_bits));
}

typedef struct {
    int num_wccs;
    int* d_force_wcc;
} MemoryHeur4;

typedef struct {
    HeuristicKind kind;
    union {
        MemoryHeur4 heur4;
    } m;
} AdditionalMemory;

void freeAdditionalMemory(AdditionalMemory additional_memory) {
    switch (additional_memory.kind) {
        case HEUR_4:
            if (additional_memory.m.heur4.d_force_wcc) {
                CUDA_CHECK(cudaFree(additional_memory.m.heur4.d_force_wcc));
            }
            break;
        default:
            break;
    }
}


void initProperty(
    CSRRepr scc_graph,
    TopoResult topo_result,
    int* d_assignments,
    int* d_property_vals,      // out
    int num_wccs,
    AdditionalMemory& additional_memory,
    HeuristicKind heuristic
) {
    switch (heuristic) {
        case HEUR_1:
            CUDA_CHECK(cudaMemset(d_property_vals, 0, scc_graph.num_nodes * sizeof(int)));
            getSources<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
                scc_graph.row_ptr,
                scc_graph.col_ind,
                d_assignments,
                scc_graph.num_nodes,
                d_property_vals
            );
            break;
        case HEUR_2:
            // Count outgoing edges for all nodes (assigned nodes get 0)
            countOutgoingEdges<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
                scc_graph.row_ptr,
                scc_graph.col_ind,
                d_assignments,
                scc_graph.num_nodes,
                d_property_vals
            );
            break;
        case HEUR_4:
            // Allocate memory for the forced WCC choice in heuristics 4
            int* d_force_wcc;
            CUDA_CHECK(cudaMalloc(&d_force_wcc, num_wccs * sizeof(int)));
            CUDA_CHECK(cudaMemset(d_force_wcc, -1, num_wccs * sizeof(int)));
            additional_memory.m.heur4.d_force_wcc = d_force_wcc;
            additional_memory.m.heur4.num_wccs = num_wccs;

            countReachability(scc_graph, topo_result, d_assignments, d_property_vals);
            break;
        case HEUR_3:
        case HEUR_5:
            countReachability(scc_graph, topo_result, d_assignments, d_property_vals);
            break;
    }
}

// Set d_property_vals to 0 to all nodes that have d_assignments != -1
void mask_values(
    int* d_property_vals,
    int* d_d_assignments,
    int num_nodes
) {
    thrust::device_ptr<int> d_property_vals_ptr(d_property_vals);
    thrust::device_ptr<int> d_assignments_ptr(d_d_assignments);
    thrust::transform(
        d_property_vals_ptr,
        d_property_vals_ptr + num_nodes,
        d_assignments_ptr,
        d_property_vals_ptr,
        [] __device__ (int property, int assignment) {
            return assignment != -1 ? 0 : property;
        }
    );
}

void updateProperty(
    CSRRepr scc_graph,
    TopoResult topo_result,
    int* d_assignments,
    int* d_property_vals,
    AdditionalMemory& additional_memory,
    HeuristicKind heuristic
) {
    switch (heuristic) {
        case HEUR_1:
            CUDA_CHECK(cudaMemset(d_property_vals, 0, scc_graph.num_nodes * sizeof(int)));
            getSources<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
                scc_graph.row_ptr,
                scc_graph.col_ind,
                d_assignments,
                scc_graph.num_nodes,
                d_property_vals
            );
            break;
        case HEUR_2:
            // Count outgoing edges for all nodes (assigned nodes get 0)
            countOutgoingEdges<<<gridStrideBlocks(scc_graph.num_nodes), NumThPerBlock>>>(
                scc_graph.row_ptr,
                scc_graph.col_ind,
                d_assignments,
                scc_graph.num_nodes,
                d_property_vals
            );
            break;
        case HEUR_3:
        {
            mask_values(d_property_vals, d_assignments, scc_graph.num_nodes);
            break;
        }
        case HEUR_4:
        {
            mask_values(d_property_vals, d_assignments, scc_graph.num_nodes);

            // Swap 0s and 1s in the forced WCC choice for the next iteration
            int* d_force_wcc = additional_memory.m.heur4.d_force_wcc;
            thrust::device_ptr<int> d_force_wcc_ptr(d_force_wcc);
            thrust::transform(
                d_force_wcc_ptr,
                d_force_wcc_ptr + additional_memory.m.heur4.num_wccs,
                d_force_wcc_ptr,
                [] __device__ (int choice) {
                    if (choice == -1) return -1; // No forced choice for this WCC
                    return 1 - choice; // Swap 0 and 1
                }
            );
            break;
        }
        case HEUR_5:
            // Count reachability for all nodes
            CUDA_CHECK(cudaMemset(d_property_vals, 0, scc_graph.num_nodes * sizeof(int)));
            countReachability(scc_graph, topo_result, d_assignments, d_property_vals);
            break;
    }
}

void solve(
    CSRRepr scc_graph,
    TopoResult topo_result,
    int* d_assignments,
    CSRRepr wcc_grouped,
    const int* d_sorted_wcc,
    HeuristicKind heuristic
) {
    // Count reachability for all nodes
    int* d_property_vals;
    CUDA_CHECK(cudaMalloc(&d_property_vals, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_property_vals, 0, scc_graph.num_nodes * sizeof(int)));

    // Allocate any additional memory needed for heuristics
    AdditionalMemory additional_memory{};
    additional_memory.kind = heuristic;
    initProperty(scc_graph, topo_result, d_assignments, d_property_vals, wcc_grouped.num_nodes, additional_memory, heuristic);

    // Allocate memory for the max node per WCC and its count
    int* d_max_nodes;
    int* d_max_property;
    CUDA_CHECK(cudaMalloc(&d_max_nodes, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_max_property, wcc_grouped.num_nodes * sizeof(int)));

    // Alloc memory for the queue of nodes to delete
    int* d_queue;
    int* d_queue_count;
    CUDA_CHECK(cudaMalloc(&d_queue, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_count, sizeof(int)));

    while (true) {
        // Get node with max property for each WCC
        getMaxForWCC(d_property_vals, wcc_grouped, d_sorted_wcc, d_max_nodes, d_max_property);

        // Get the nodes to eliminate and put them in the queue
        CUDA_CHECK(cudaMemset(d_queue_count, 0, sizeof(int)));
        int *d_force_wcc = (heuristic == HEUR_4) ? additional_memory.m.heur4.d_force_wcc : nullptr;
        nodeToEliminate<<<gridStrideBlocks(wcc_grouped.num_nodes), NumThPerBlock>>>(
            d_max_nodes,
            d_max_property,
            d_sorted_wcc,
            wcc_grouped.num_nodes,
            d_force_wcc,
            d_assignments,
            d_queue,
            d_queue_count
        );

        int queue_size = 0;
        CUDA_CHECK(cudaMemcpy(&queue_size, d_queue_count, sizeof(int), cudaMemcpyDeviceToHost));
        if (queue_size <= 0) {
            break; // No more nodes to remove
        }

        // Assign the nodes to delete and propagate the assignment
        deleteAndPropagate(
            scc_graph,
            d_assignments,
            d_queue,
            d_queue_count
        );
        
        // Update the property values for the next iteration
        updateProperty(
            scc_graph,
            topo_result,
            d_assignments,
            d_property_vals,
            additional_memory,
            heuristic
        );
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_property_vals));
    CUDA_CHECK(cudaFree(d_max_nodes));
    CUDA_CHECK(cudaFree(d_max_property));
    freeAdditionalMemory(additional_memory);
    CUDA_CHECK(cudaFree(d_queue));
    CUDA_CHECK(cudaFree(d_queue_count));
}
