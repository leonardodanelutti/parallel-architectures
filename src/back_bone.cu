#include "../include/common.h"
#include "../include/cuda_utils.h"

__global__ void map_batch(
    const int* scc_ids,            // Original Node -> DAG Node
    unsigned int* d_dag_var_masks, // Output map
    int* d_assign_status,          // Output status for pairs
    int num_pairs,
    int batch_start_idx
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int pair_idx = batch_start_idx + tid;

    if (pair_idx >= num_pairs || tid >= 32) return;

    int u_orig = 2 * pair_idx;
    int v_orig = 2 * pair_idx + 1;

    int u_dag = scc_ids[u_orig];
    int v_dag = scc_ids[v_orig];

    // If they are in the same component, mark as UNSAT
    if (u_dag == v_dag) {
        d_assign_status[u_orig] = -1;
        d_assign_status[v_orig] = -1;
        return;
    }

    unsigned int bit = (1u << tid);

    // Set the tid-h bit in both DAG nodes to true
    atomicOr(&d_dag_var_masks[u_dag], bit);
    atomicOr(&d_dag_var_masks[v_dag], bit);
}

__global__ void dag_sweep(
    const int* row_ptr, const int* col_ind, // DAG CSR
    const int* sorted_nodes,                // DAG Topological Sort
    unsigned int* node_masks,               // Propagation masks
    const unsigned int* injection_masks,    // Input from previous map
    int level_start, int level_end
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;

    for (int idx = level_start + tid; idx < level_end; idx += stride) {
        int u = sorted_nodes[idx];

        // Bits propagated from parents
        unsigned int incoming = node_masks[u];
        // Add bits that correspond to literals present in this node
        unsigned int to_propagate = incoming | injection_masks[u];

        // Update and propagate to children
        if (to_propagate != 0) {
            for (int i = row_ptr[u]; i < row_ptr[u+1]; i++) {
                int v = col_ind[i];
                atomicOr(&node_masks[v], to_propagate);
            }
        }
    }
}

__global__ void resolve_reachability_batch(
    const int* scc_ids,                 // Mapping
    const unsigned int* dag_node_masks, // Result of sweep
    int* d_assign_status,               // Output
    int num_pairs,
    int batch_start_idx
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    int pair_idx = batch_start_idx + tid;

    if (pair_idx >= num_pairs || tid >= 32) return;

    int u_orig = 2 * pair_idx;
    int v_orig = 2 * pair_idx + 1;

    // TODO: return an error
    if (d_assign_status[u_orig] == -1) return;

    int u_dag = scc_ids[u_orig];
    int v_dag = scc_ids[v_orig];
    unsigned int bit = (1u << tid);

    // node u in the DAG receive the bit? If yes, it must have come from 
    // node v in the DAG
    if (dag_node_masks[u_dag] & bit) {
        d_assign_status[u_dag] = 2;
        d_assign_status[v_dag] = 1;
    } else if (dag_node_masks[v_dag] & bit) {
        d_assign_status[u_dag] = 1;
        d_assign_status[v_dag] = 2;
    }
}


int* compute_backbone(
    const CSRGraph& d_graph,
    const int* d_scc_lookup,
    const int num_vars,
    const TopoResult& topo_sort
) {
    // Bit i of d_dag_node_masks[j] indicates whether in the current batch
    // the DAG node j is reachable from the i-th literal pair's nodes
    unsigned int* d_dag_node_masks;
    // Bit i of d_dag_var_masks[j] indicates that in the current batch the
    // literal pair i is present in the component represented by DAG node j
    unsigned int* d_dag_var_masks;
    // Status flags for original variables, 0 = unassigned, 1 = FALSE, 2 = TRUE, -1 = UNSAT
    int* d_assign_status;
    CUDA_CHECK(cudaMalloc(&d_dag_node_masks, d_graph.num_nodes * sizeof(unsigned int)));
    CUDA_CHECK(cudaMalloc(&d_dag_var_masks, d_graph.num_nodes * sizeof(unsigned int)));
    CUDA_CHECK(cudaMalloc(&d_assign_status, d_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemset(d_assign_status, 0, d_graph.num_nodes * sizeof(int)));


    // Loop over all pairs of literals in chunks of 32
    for (int batch_start = 0; batch_start < num_vars; batch_start += 32) {
        
        // Reset masks to 0 for this batch
        cudaMemset(d_dag_node_masks, 0, d_graph.num_nodes * sizeof(unsigned int));
        cudaMemset(d_dag_var_masks, 0, d_graph.num_nodes * sizeof(unsigned int));

        // Compute what pairs of literals map to which DAG nodes
        map_batch<<<1, 32>>>(
                d_scc_lookup,
                d_dag_var_masks,
                d_assign_status,
                num_vars,
                batch_start
            );

        // Propagate reachability information through the DAG in topological order
        for (size_t i = 0; i < topo_sort.num_levels; i++) {
            int start = topo_sort.level_starts[i];
            int end   = topo_sort.level_starts[i+1];
            int count = end - start;

            if (count == 0) continue;

            // Propagate reachability for this level
            int blocks = gridStrideBlocks(count);
            dag_sweep<<<blocks, NumThPerBlock>>>(
                d_graph.row_ptr,
                d_graph.col_ind,
                topo_sort.d_topo_order,
                d_dag_node_masks,
                d_dag_var_masks,
                start,
                end
            );
        }

        // Check if literals have reached each other
        resolve_reachability_batch<<<1, 32>>>(
            d_scc_lookup,
            d_dag_node_masks,
            d_assign_status,
            num_vars,
            batch_start
        );
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_dag_node_masks));
    CUDA_CHECK(cudaFree(d_dag_var_masks));

    return d_assign_status;
}