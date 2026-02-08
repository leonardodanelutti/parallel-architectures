#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "SCC.cu"
#include "topo_sort.cu"
#include "back_bone.cu"
#include "WCC.cu"
#include "heuristics.cu"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename>" << std::endl;
        return 1;
    }

    std::string filename = argv[1];
    
    // Print GPU information
    printDeviceInfo();
    std::cout << std::endl;

    // read 2SAT instance from file
    int num_vars, num_clauses, asp_result;
    CSRRepr graph;
    read2SATInstance(filename, num_vars, num_clauses, asp_result, graph);

    // TODO: Start CUDA event timing

    // Allocate device memory
    CSRRepr d_graph;
    CUDA_CHECK(cudaMalloc(&d_graph.row_ptr, (graph.num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_graph.col_ind, graph.num_edges * sizeof(int)));
    
    // Copy data from host to device
    CUDA_CHECK(cudaMemcpy(d_graph.row_ptr, graph.row_ptr, (graph.num_nodes + 1) * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_graph.col_ind, graph.col_ind, graph.num_edges * sizeof(int), cudaMemcpyHostToDevice));
    d_graph.num_nodes = graph.num_nodes;
    d_graph.num_edges = graph.num_edges;

    // Compute the condensed graph of SCCs
    CondensedGraphResult condensed = computeCondensedGraph(d_graph);
    CSRRepr scc_graph = condensed.graph;

    // Compute topological sort and levels for the condensed graph
    TopoResult topo_result = topologicalSort(scc_graph);

    int* backbone_assignments = compute_backbone(
        scc_graph,
        topo_result
    );

    int* d_wcc_map = computeWCC(scc_graph, backbone_assignments);


    // 1. Find sinks and put to them to false
    // 2. Find sources and sinks, check witch is less and assign accordingly
    // 3. Compute the number of nodes reachable forwards or backwards. Find the node that reaches the most nodes, remove it and all the nodes ahead/behind accordingly, and repeat
    // 4. Same as 3. but re-compute the reachability counts after each iteration.
    
    
    // TODO: Cleanup
    // - Free device memory
    CUDA_CHECK(cudaFree(d_graph.row_ptr));
    CUDA_CHECK(cudaFree(d_graph.col_ind));
    CUDA_CHECK(cudaFree(scc_graph.row_ptr));
    CUDA_CHECK(cudaFree(scc_graph.col_ind));
    CUDA_CHECK(cudaFree(condensed.d_scc_lookup));
    CUDA_CHECK(cudaFree(topo_result.d_topo_order));
    CUDA_CHECK(cudaFree(backbone_assignments));
    CUDA_CHECK(cudaFree(d_wcc_map));
    // Free host memory
    freeCSRRepr(graph);
    // - Destroy CUDA events: CUDA_CHECK(cudaEventDestroy(start));
    
    // std::cout << "CUDA execution completed!" << std::endl;
    
    return 0;
}
