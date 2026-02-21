#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "../include/benchmark.h"
#include "SCC.cu"
#include "topo_sort.cu"
#include "back_bone.cu"
#include "WCC.cu"
#include "heuristics.cu"

std::vector<std::pair<int, int>> compute_assignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit);
bool checkSatPairs(int num_vars, int* d_scc_lookup, int& bad_var_idx);
void printAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic);
void printNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic);
int getNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit);

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename> [heuristic] [--check-sodd] [--bench] [--bench-file <path>]" << std::endl;
        std::cerr << "  heuristic: 1 | 2 | 3 | 4 | all (default)" << std::endl;
        return 1;
    }

    std::string filename = argv[1];
    std::string heuristic = "all";
    bool check_sodd = false;
    bool bench_enabled = false;
    std::string bench_path = "benchmarks.csv";
    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--check-sodd") {
            check_sodd = true;
        } else if (arg == "--bench") {
            bench_enabled = true;
        } else if (arg == "--bench-file") {
            if (i + 1 < argc) {
                bench_enabled = true;
                bench_path = argv[++i];
            } else {
                std::cerr << "--bench-file requires a path" << std::endl;
                return 1;
            }
        } else if (arg.rfind("--bench-file=", 0) == 0) {
            bench_enabled = true;
            bench_path = arg.substr(std::string("--bench-file=").size());
        } else {
            heuristic = arg;
        }
    }

    initBenchmark(g_bench, bench_enabled, bench_path, filename, heuristic);
    benchStartTotal(g_bench);

    // read 2SAT instance from file
    int num_vars, num_clauses;
    int lower_bound, upper_bound;
    bool bounds_present;
    CSRRepr graph;
    benchStart(g_bench, BENCH_HOST);
    read2SATInstance(
        filename,
        num_vars,
        num_clauses,
        lower_bound,
        upper_bound,
        bounds_present,
        graph
    );
    benchEnd(g_bench, "read_instance", BENCH_HOST);
    benchSetInstanceInfo(g_bench, num_vars, num_clauses, lower_bound, upper_bound, bounds_present);

    // TODO: Start CUDA event timing

    // Allocate device memory
    CSRRepr d_graph;
    benchStart(g_bench, BENCH_DEVICE);
    CUDA_CHECK(cudaMalloc(&d_graph.row_ptr, (graph.num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_graph.col_ind, graph.num_edges * sizeof(int)));
    
    // Copy data from host to device
    CUDA_CHECK(cudaMemcpy(d_graph.row_ptr, graph.row_ptr, (graph.num_nodes + 1) * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_graph.col_ind, graph.col_ind, graph.num_edges * sizeof(int), cudaMemcpyHostToDevice));
    d_graph.num_nodes = graph.num_nodes;
    d_graph.num_edges = graph.num_edges;
    benchEnd(g_bench, "alloc_graph", BENCH_DEVICE);

    // Compute the condensed graph of SCCs
    benchStart(g_bench, BENCH_DEVICE);
    CondensedGraphResult condensed = computeCondensedGraph(d_graph);
    CSRRepr scc_graph = condensed.graph;
    benchEnd(g_bench, "scc", BENCH_DEVICE);

    int exit_code = 0;
    if (check_sodd) {
        int bad_var_idx = -1;
        benchStart(g_bench, BENCH_HOST);
        if (!checkSatPairs(num_vars, condensed.d_scc_lookup, bad_var_idx)) {
            std::cerr << "SODD check failed: variable " << bad_var_idx
                      << " has literals in the same SCC." << std::endl;
            exit_code = 2;
        }
        benchEnd(g_bench, "sodd_check", BENCH_HOST);
    }

    // Compute topological sort and levels for the condensed graph
    benchStart(g_bench, BENCH_DEVICE);
    TopoResult topo_result = topologicalSort(scc_graph);
    benchEnd(g_bench, "topo_sort", BENCH_DEVICE);

    // Compute the backbone of the condensed graph
    benchStart(g_bench, BENCH_DEVICE);
    int* d_backbone_assignments = computeBackbone(
        scc_graph,
        topo_result
    );
    benchEnd(g_bench, "backbone", BENCH_DEVICE);

    // Compute WCCs of the condensed graph with the backbone assignments
    benchStart(g_bench, BENCH_DEVICE);
    int* d_wcc_map = computeWCC(scc_graph, d_backbone_assignments);
    benchEnd(g_bench, "wcc", BENCH_DEVICE);

    // Get CSR representation of the WCCs grouped
    int* d_sorted_wcc = nullptr;
    CUDA_CHECK(cudaMalloc(&d_sorted_wcc, scc_graph.num_nodes * sizeof(int)));
    benchStart(g_bench, BENCH_DEVICE);
    CSRRepr wcc_grouped = getWCCGrouped(d_wcc_map, d_sorted_wcc, scc_graph.num_nodes);
    benchEnd(g_bench, "wcc_grouped", BENCH_DEVICE);
    benchSetGraphStats(g_bench, scc_graph.num_nodes, wcc_grouped.num_nodes, topo_result.num_levels);

    // Run heuristics
    auto run_heuristic = [&](HeuristicKind which) {
        if (which < HEUR_1 || which > HEUR_4) {
            return false;
        }
        benchStart(g_bench, BENCH_DEVICE);
        solve(scc_graph, topo_result, d_backbone_assignments, wcc_grouped, d_sorted_wcc, which);
        benchEnd(g_bench, "heuristic" + std::to_string(static_cast<int>(which)), BENCH_DEVICE);
        int num_assignments = getNumAssignments(d_backbone_assignments, condensed.d_scc_lookup, scc_graph.num_nodes, graph.num_nodes);
        benchSetLastAssignments(g_bench, num_assignments);
        return true;
    };

    if (exit_code == 0 && heuristic == "all") {
        int* d_backbone_assignments_base = nullptr;
        CUDA_CHECK(cudaMalloc(&d_backbone_assignments_base, scc_graph.num_nodes * sizeof(int)));
        CUDA_CHECK(cudaMemcpy(
            d_backbone_assignments_base,
            d_backbone_assignments,
            scc_graph.num_nodes * sizeof(int),
            cudaMemcpyDeviceToDevice
        ));

        for (int which = HEUR_1; which <= HEUR_4; ++which) {
            CUDA_CHECK(cudaMemcpy(
                d_backbone_assignments,
                d_backbone_assignments_base,
                scc_graph.num_nodes * sizeof(int),
                cudaMemcpyDeviceToDevice
            ));
            run_heuristic(static_cast<HeuristicKind>(which));

            // Check if assignments are correct
            /*
            int* h_backbone_assignments = new int[scc_graph.num_nodes];
            CUDA_CHECK(cudaMemcpy(h_backbone_assignments, d_backbone_assignments, scc_graph.num_nodes * sizeof(int), cudaMemcpyDeviceToHost));
            checkAssignment(scc_graph, h_backbone_assignments);
            free(h_backbone_assignments);
            */
        }

        CUDA_CHECK(cudaFree(d_backbone_assignments_base));
    } else if (exit_code == 0) {
        int which_value = std::atoi(heuristic.c_str());
        HeuristicKind which = static_cast<HeuristicKind>(which_value);
        if (!run_heuristic(which)) {
            std::cerr << "Unknown heuristic: " << heuristic << std::endl;
            std::cerr << "Expected: 1 | 2 | 3 | 4 | all" << std::endl;
        }
    }
    
    // - Free device memory
    benchStart(g_bench, BENCH_DEVICE);
    freeDeviceCSRRepr(scc_graph);
    freeDeviceCSRRepr(d_graph);
    CUDA_CHECK(cudaFree(condensed.d_scc_lookup));
    CUDA_CHECK(cudaFree(topo_result.d_topo_order));
    freeDeviceCSRRepr(wcc_grouped);
    CUDA_CHECK(cudaFree(d_sorted_wcc));
    CUDA_CHECK(cudaFree(d_backbone_assignments));
    CUDA_CHECK(cudaFree(d_wcc_map));
    benchEnd(g_bench, "cleanup_device", BENCH_DEVICE);
    // Free host memory
    freeCSRRepr(graph);

    benchStopTotal(g_bench);
    benchFlush(g_bench);
    
    // std::cout << "CUDA execution completed!" << std::endl;
    
    return exit_code;
}

bool checkSatPairs(int num_vars, int* d_scc_lookup, int& bad_var_idx) {
    const int num_lit = num_vars * 2;
    std::vector<int> h_scc_lookup(num_lit);
    CUDA_CHECK(cudaMemcpy(h_scc_lookup.data(), d_scc_lookup, num_lit * sizeof(int), cudaMemcpyDeviceToHost));

    for (int i = 0; i < num_vars; ++i) {
        const int a = h_scc_lookup[2 * i];
        const int b = h_scc_lookup[2 * i + 1];
        if (a == b) {
            bad_var_idx = i;
            return false;
        }
    }
    return true;
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

void printAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic) {
    auto var_assignments = compute_assignments(d_assignments, scc_map, num_nodes, num_lit);
    std::cout << "h" << static_cast<int>(heuristic) << ": " << var_assignments.size() << std::endl;
    for (const auto& [var, value] : var_assignments) {
        std::cout << var << " " << value << " ";
    }
    std::cout << std::endl;
}

void printNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic) {
    auto var_assignments = compute_assignments(d_assignments, scc_map, num_nodes, num_lit);
    std::cout << "h" << static_cast<int>(heuristic) << ": " << var_assignments.size() << std::endl;
}

int getNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit) {
    auto var_assignments = compute_assignments(d_assignments, scc_map, num_nodes, num_lit);
    return var_assignments.size();
}
