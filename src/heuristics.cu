#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "../include/benchmark.h"

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
    HEUR_4 = 4
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
    int* d_count_out,
    int* d_queue_out
) {
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
    int* d_wcc_prop_nodes, int* d_wcc_prop_val, int* d_wcc_keys_out      // out
) {
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
}

// Get the complement of a WCC, there can be 3 scenarios:
// 1) WCC id is -1, then it is a backbone and we set the result -1
// 2) The complement of a literal is in the same WCC, then we just set the same WCC id
// 3) The complement of a literal is in a different WCC, then we set the WCC id of the complement literal
//    and we set -1 to the WCC of the complement literal
__host__ __device__ inline int getWCCComplementKernel(
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
            return wcc_num + 1;
        } else {
            // Complement is in the same WCC
            return wcc_num;
        }
    }
    return -1; // For backbone and odd WCCs
}

// For each WCC-pair choose the node with the maximum property value and assign it to True (and its complement to False).
__global__ void nodeToEliminate(
    const int* const __restrict__ nodes,
    const int* const __restrict__ max_property,
    const int* const __restrict__ wcc_sorted,
    int num_wcc,
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

        int max_dag = (max_property[dag_1] >= max_property[dag_2]) ? dag_1 : dag_2;
        int target = nodes[max_dag];

        // Assign target and its complement, then enqueue target.
        if (atomicCAS(&assignments[target], -1, 3) == -1) {
            assignments[target ^ 1] = 2;
            int out_idx = atomicAdd(out_count, 1);
            queue_out[out_idx] = target;
        }
    }
}

// Set to 1 the nodes that are sources (the complement of sinks)
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

// Propagates reachability using bitsets. 
// We use a "reverse topological" approach: by starting at the leaves and 
// working up to the roots, each parent simply ORs the bitsets of its children.
__global__ void propagateReachability_chunked(
    const int* __restrict__ row_ptr,
    const int* __restrict__ col_ind,
    const int* __restrict__ topo_order,
    const int* __restrict__ level_starts,
    int num_levels,
    const int* __restrict__ assignments,
    int batch_size,
    int chunk_batches, 
    int global_batch_offset,
    int num_nodes,
    unsigned long long* __restrict__ reach_bits,
    int* __restrict__ d_reach_counts
) {
    int batch_idx = blockIdx.x;
    if (batch_idx >= chunk_batches) return;
    
    // Each CUDA block handles one specific "batch" of 64 nodes
    int global_batch = global_batch_offset + batch_idx;
    int batch_start = global_batch * batch_size;
    
    // Offset our pointer so this block works on its own slice of the bitset memory
    unsigned long long* batch_reach_bits = reach_bits + ((size_t)batch_idx * num_nodes);

    // Traverse the DAG in topological order, level by level
    for (int level = num_levels - 1; level >= 0; --level) {
        int level_start = level_starts[level];
        int level_end = level_starts[level + 1];
        int count = level_end - level_start;
        
        if (count == 0) continue;

        // Threads in the block split the nodes available at this topological level
        for (int idx = threadIdx.x; idx < count; idx += blockDim.x) {
            int u = topo_order[level_start + idx];

            // If the node is already "claimed" or filtered out, ignore it
            if (assignments[u] != -1) {
                batch_reach_bits[u] = 0ULL;
                continue;
            }

            unsigned long long my_bits = 0ULL;
            
            // If this node falls within our current 64-node window, mark its own bit
            if (u >= batch_start && u < batch_start + batch_size) {
                my_bits = (1ULL << (u - batch_start));
            }

            // I can reach everything my children can reach
            for (int e = row_ptr[u]; e < row_ptr[u+1]; ++e) {
                int v = col_ind[e];
                my_bits |= batch_reach_bits[v]; 
            }

            batch_reach_bits[u] = my_bits;
        }
        
        // Ensure all children at this level are written 
        // before the parents in the next level try to read them.
        __syncthreads();
    }

    // Convert the bitsets into actual integers (counts) and add to global results
    for (int i = threadIdx.x; i < num_nodes; i += blockDim.x) {
        unsigned long long final_bits = batch_reach_bits[i];
        if (final_bits != 0ULL) {
            atomicAdd(&d_reach_counts[i], __popcll(final_bits));
        }
    }
}

void countReachability(CSRRepr scc_graph, TopoResult topo_result, int* assignments, int* d_reach_counts) {
    const int BITS_IN_ULL = 64; 
    int total_batches = (scc_graph.num_nodes + BITS_IN_ULL - 1) / BITS_IN_ULL;
    
    // Bitset matrices can consume a lot of memory, so we allocate a large chunk and divide it into "batches" of 64 nodes each.
    size_t bytes_per_batch = (size_t)scc_graph.num_nodes * sizeof(unsigned long long);
    size_t max_memory = 500ULL * 1024 * 1024; 
    int batches_per_chunk = max_memory / bytes_per_batch;
    if (batches_per_chunk == 0) batches_per_chunk = 1; 
    
    unsigned long long* d_reach_bits;
    CUDA_CHECK(cudaMalloc(&d_reach_bits, (size_t)batches_per_chunk * bytes_per_batch));

    // Move topological data to the GPU
    int num_level_starts = topo_result.level_starts.size();
    int* d_level_starts;
    CUDA_CHECK(cudaMalloc(&d_level_starts, num_level_starts * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_level_starts, topo_result.level_starts.data(), num_level_starts * sizeof(int), cudaMemcpyHostToDevice));

    // Chunking Loop: Process as many bit-batches as fit in our memory budget
    for (int chunk_start = 0; chunk_start < total_batches; chunk_start += batches_per_chunk) {
        
        int current_chunk_batches = std::min(batches_per_chunk, total_batches - chunk_start);
        
        // Clear the workspace for this chunk
        CUDA_CHECK(cudaMemset(d_reach_bits, 0, (size_t)current_chunk_batches * bytes_per_batch));

        // Launch the kernel. Each block handles one batch of 64 bits.
        propagateReachability_chunked<<<current_chunk_batches, NumThPerBlock>>>(
            scc_graph.row_ptr,
            scc_graph.col_ind,
            topo_result.d_topo_order,
            d_level_starts,
            topo_result.num_levels,
            assignments,
            BITS_IN_ULL,
            current_chunk_batches,
            chunk_start, 
            scc_graph.num_nodes,
            d_reach_bits,
            d_reach_counts
        );
    }

    // Clean up
    CUDA_CHECK(cudaFree(d_level_starts));
    CUDA_CHECK(cudaFree(d_reach_bits));
}


void initProperty(
    CSRRepr scc_graph,
    TopoResult topo_result,
    int* d_assignments,
    int* d_property_vals,
    int num_wccs,
    HeuristicKind heuristic
) {
    switch (heuristic) {
        case HEUR_1:
            // Set to 1 the nodes that are sources (the complement of sinks)
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
        case HEUR_4:
            // Count reachability for all nodes
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
    HeuristicKind heuristic
) {
    switch (heuristic) {
        case HEUR_1:
            // Set to 1 the nodes that are sources (the complement of sinks)
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
            // Set to 0 the rechability counts of the nodes that are assigned (they should not be considered in the next iteration)
            mask_values(d_property_vals, d_assignments, scc_graph.num_nodes);
            break;
        case HEUR_4:
            // Re-compute reachability for all nodes
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

    // Initialize the property values based on the heuristic
    initProperty(scc_graph, topo_result, d_assignments, d_property_vals, wcc_grouped.num_nodes, heuristic);

    // Allocate memory for the max node per WCC and its count
    int* d_max_nodes;
    int* d_max_property;
    int* d_wcc_keys_out;
    CUDA_CHECK(cudaMalloc(&d_max_nodes, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_max_property, wcc_grouped.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_wcc_keys_out, wcc_grouped.num_nodes * sizeof(int)));

    // Alloc memory for the queue of nodes to delete
    int* d_queue;
    int* d_queue_count;
    int* d_queue_out;
    CUDA_CHECK(cudaMalloc(&d_queue, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_count, sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_queue_out, scc_graph.num_nodes * sizeof(int)));

    // Get the sorted unique WCC ids
    int* d_unique_wcc_ids;
    CUDA_CHECK(cudaMalloc(&d_unique_wcc_ids, wcc_grouped.num_nodes * sizeof(int)));
    thrust::device_ptr<const int> d_sorted_wcc_ptr(d_sorted_wcc);
    thrust::device_ptr<int> d_unique_wcc_ids_ptr(d_unique_wcc_ids);
    thrust::unique_copy(
        thrust::device,
        d_sorted_wcc_ptr,
        d_sorted_wcc_ptr + wcc_grouped.num_edges,
        d_unique_wcc_ids_ptr
    );

    int num_loops = 0;
    while (true) {
        num_loops++;
        // Get node with max property for each WCC
        getMaxForWCC(d_property_vals, wcc_grouped, d_sorted_wcc, d_max_nodes, d_max_property, d_wcc_keys_out);

        // Get the nodes to eliminate and put them in the queue
        CUDA_CHECK(cudaMemset(d_queue_count, 0, sizeof(int)));
        nodeToEliminate<<<gridStrideBlocks(wcc_grouped.num_nodes), NumThPerBlock>>>(
            d_max_nodes,
            d_max_property,
            d_unique_wcc_ids,
            wcc_grouped.num_nodes,
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
            d_queue_count,
            d_queue_out
        );
        
        // Update the property values for the next iteration
        updateProperty(
            scc_graph,
            topo_result,
            d_assignments,
            d_property_vals,
            heuristic
        );
    }
    benchSetNumLoops(g_bench, num_loops);

    // Cleanup
    CUDA_CHECK(cudaFree(d_property_vals));
    CUDA_CHECK(cudaFree(d_max_nodes));
    CUDA_CHECK(cudaFree(d_max_property));
    CUDA_CHECK(cudaFree(d_wcc_keys_out));
    CUDA_CHECK(cudaFree(d_queue));
    CUDA_CHECK(cudaFree(d_queue_count));
    CUDA_CHECK(cudaFree(d_queue_out));
}
