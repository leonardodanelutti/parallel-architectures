#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "SCC.cu"
#include "topo_sort.cu"
#include "back_bone.cu"
#include "WCC.cu"
#include "heuristics.cu"

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename> [heuristic]" << std::endl;
        std::cerr << "  heuristic: 1 | 2 | 3 | 4 | all (default)" << std::endl;
        return 1;
    }

    std::string filename = argv[1];
    std::string heuristic = (argc >= 3) ? argv[2] : "all";
    
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

    int* d_backbone_assignments = computeBackbone(
        scc_graph,
        topo_result
    );

    int* d_wcc_map = computeWCC(scc_graph, d_backbone_assignments);
    
    // 1. Find sinks and put to them to false
    if (heuristic == "1" || heuristic == "all") {
        heuristic1(scc_graph, d_backbone_assignments, d_wcc_map);
    }
    // 2. Find sources and sinks, check witch is less and assign accordingly
    if (heuristic == "2" || heuristic == "all") {
        heuristic2(scc_graph, d_backbone_assignments, d_wcc_map);
    }
    // 3. Compute the number of nodes reachable forwards or backwards. Find the node 
    // that reaches the most nodes, remove it and all the nodes ahead/behind accordingly, and repeat
    if (heuristic == "3" || heuristic == "all") {
        heuristic3(scc_graph, topo_result, d_backbone_assignments, d_wcc_map);
    }
    // 4. Same as 3. but re-compute the reachability counts after each iteration.
    if (heuristic == "4" || heuristic == "all") {
        heuristic4(scc_graph, topo_result, d_backbone_assignments, d_wcc_map);
    }
    if (heuristic != "1" && heuristic != "2" && heuristic != "3" && heuristic != "4" && heuristic != "all") {
        std::cerr << "Unknown heuristic: " << heuristic << std::endl;
        std::cerr << "Expected: 1 | 2 | 3 | 4 | all" << std::endl;
    }
    
    // - Free device memory
    freeDeviceCSRRepr(scc_graph);
    freeDeviceCSRRepr(d_graph);
    CUDA_CHECK(cudaFree(condensed.d_scc_lookup));
    CUDA_CHECK(cudaFree(topo_result.d_topo_order));
    CUDA_CHECK(cudaFree(d_backbone_assignments));
    CUDA_CHECK(cudaFree(d_wcc_map));
    // Free host memory
    freeCSRRepr(graph);
    // - Destroy CUDA events: CUDA_CHECK(cudaEventDestroy(start));
    
    // std::cout << "CUDA execution completed!" << std::endl;
    
    return 0;
}

// compute result from the final assignments array
std::vector<std::pair<int, int>> compute_assignments(int* d_assignments, int num_nodes) {
    int* d_representatives;
    CUDA_CHECK(cudaMalloc(&d_representatives, num_nodes * sizeof(int)));
    // Get the representative for each node
    findRepresentatives(d_assignments, num_nodes, d_representatives);
    int* h_representatives = new int[num_nodes];
    int* h_assignments = new int[num_nodes];
    CUDA_CHECK(cudaMemcpy(h_representatives, d_representatives, num_nodes * sizeof(int), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(h_assignments, d_assignments, num_nodes * sizeof(int), cudaMemcpyDeviceToHost));

    std::vector<std::pair<int, int>> var_assignments;

    for (int i = 0; i < num_nodes; i++) {
        if (h_assignments[i] == 3) {
            int var = h_representatives[i] / 2;
            if (h_representatives[i] % 2 == 0) {
                var_assignments.emplace_back(var, 1);
            } else {
                var_assignments.emplace_back(var, 0);
            }
        }
    }

    CUDA_CHECK(cudaFree(d_representatives));
    free(h_representatives);
    free(h_assignments);

    return var_assignments;
}
