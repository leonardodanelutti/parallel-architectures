#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "SCC.cu"
#include "topo_sort.cu"
#include "back_bone.cu"
#include "WCC.cu"
#include "heuristics.cu"

std::vector<std::pair<int, int>> compute_assignments(int* d_assignments, int num_nodes);
void printAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, int heuristic);
void printNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, int heuristic);

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename> [heuristic]" << std::endl;
        std::cerr << "  heuristic: 1 | 2 | 3 | 4 | 5 | all (default)" << std::endl;
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

    auto run_heuristic = [&](int which) {
        switch (which) {
            case 1:
                heuristic1(scc_graph, d_backbone_assignments, d_wcc_map);
                break;
            case 2:
                heuristic2(scc_graph, d_backbone_assignments, d_wcc_map);
                break;
            case 3:
                heuristic3(scc_graph, topo_result, d_backbone_assignments, d_wcc_map);
                break;
            case 4:
                heuristic4(scc_graph, topo_result, d_backbone_assignments, d_wcc_map);
                break;
            case 5:
                heuristic5(scc_graph, topo_result, d_backbone_assignments, d_wcc_map);
                break;
            default:
                return false;
        }
        printAssignments(d_backbone_assignments, condensed.d_scc_lookup, scc_graph.num_nodes, d_graph.num_nodes, which);
        return true;
    };

    if (heuristic == "all") {
        int* d_backbone_assignments_base = nullptr;
        CUDA_CHECK(cudaMalloc(&d_backbone_assignments_base, scc_graph.num_nodes * sizeof(int)));
        CUDA_CHECK(cudaMemcpy(
            d_backbone_assignments_base,
            d_backbone_assignments,
            scc_graph.num_nodes * sizeof(int),
            cudaMemcpyDeviceToDevice
        ));

        for (int which = 1; which <= 5; ++which) {
            CUDA_CHECK(cudaMemcpy(
                d_backbone_assignments,
                d_backbone_assignments_base,
                scc_graph.num_nodes * sizeof(int),
                cudaMemcpyDeviceToDevice
            ));
            run_heuristic(which);
        }

        CUDA_CHECK(cudaFree(d_backbone_assignments_base));
    } else {
        int which = std::atoi(heuristic.c_str());
        if (!run_heuristic(which)) {
            std::cerr << "Unknown heuristic: " << heuristic << std::endl;
            std::cerr << "Expected: 1 | 2 | 3 | 4 | 5 | all" << std::endl;
        }
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
    
    // std::cout << "CUDA execution completed!" << std::endl;
    
    return 0;
}

// compute result from the final assignments array
std::vector<std::pair<int, int>> compute_assignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit) {
    int* d_representatives;
    CUDA_CHECK(cudaMalloc(&d_representatives, num_nodes * sizeof(int)));
    // Get the representative for each node
    findRepresentatives(scc_map, num_lit, d_representatives);
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

void printAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, int heuristic) {
    auto var_assignments = compute_assignments(d_assignments, scc_map, num_nodes, num_lit);
    std::cout << "h" << heuristic << ": " << var_assignments.size() << std::endl;
    for (const auto& [var, value] : var_assignments) {
        std::cout << var << value << std::endl;
    }
    std::cout << std::endl;
}

void printNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, int heuristic) {
    auto var_assignments = compute_assignments(d_assignments, scc_map, num_nodes, num_lit);
    std::cout << "h" << heuristic << ": " << var_assignments.size() << std::endl;
}
