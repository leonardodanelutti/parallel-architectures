#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "../include/benchmark.h"
#include "SCC.cu"
#include "topo_sort.cu"
#include "back_bone.cu"
#include "WCC.cu"
#include "heuristics.cu"
#include "parse_args.cpp"

// Forward declarations
std::vector<std::pair<int, int>> compute_assignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit);
bool checkSatPairs(int num_vars, int* d_scc_lookup, int& bad_var_idx);
void printAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic);
void printNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit, HeuristicKind heuristic);
int getNumAssignments(int* d_assignments, int* scc_map, int num_nodes, int num_lit);

int main(int argc, char* argv[]) {
    AppConfig config = parseCommandLine(argc, argv);
    if (!config.success) return 1;

    initBenchmark(g_bench, config.bench_enabled, config.bench_path, config.filename, "all");
    benchStartTotal(g_bench);

    // read 2SAT instance from file
    int num_vars, num_clauses, lower_bound, upper_bound;
    bool bounds_present;
    CSRRepr graph;
    
    benchStart(g_bench, BENCH_HOST);
    read2SATInstance(config.filename, num_vars, num_clauses, lower_bound, upper_bound, bounds_present, graph);
    benchEnd(g_bench, "read_instance", BENCH_HOST);
    benchSetInstanceInfo(g_bench, num_vars, num_clauses, lower_bound, upper_bound, bounds_present);

    // Allocate device memory
    CSRRepr d_graph;
    benchStart(g_bench, BENCH_DEVICE);
    CUDA_CHECK(cudaMalloc(&d_graph.row_ptr, (graph.num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_graph.col_ind, graph.num_edges * sizeof(int)));
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

    if (config.check_sodd) {
        int bad_var_idx = -1;
        benchStart(g_bench, BENCH_HOST);
        if (!checkSatPairs(num_vars, condensed.d_scc_lookup, bad_var_idx)) {
            std::cerr << "SODD check failed: variable " << bad_var_idx << " in same SCC." << std::endl;
            return 1;
        }
        benchEnd(g_bench, "sodd_check", BENCH_HOST);
    }

    // Compute topological sort and levels for the condensed graph
    benchStart(g_bench, BENCH_DEVICE);
    TopoResult topo_result = topologicalSort(scc_graph);
    benchEnd(g_bench, "topo_sort", BENCH_DEVICE);

    // Compute the backbone of the condensed graph
    benchStart(g_bench, BENCH_DEVICE);
    int* d_backbone_assignments = computeBackbone(scc_graph, topo_result);
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

    // --- Heuristic Execution Loop ---
    // Save the backbone state so we can reset it for each heuristic
    int* d_backbone_base = nullptr;
    CUDA_CHECK(cudaMalloc(&d_backbone_base, scc_graph.num_nodes * sizeof(int)));
    CUDA_CHECK(cudaMemcpy(d_backbone_base, d_backbone_assignments, scc_graph.num_nodes * sizeof(int), cudaMemcpyDeviceToDevice));

    for (HeuristicKind h : config.heuristics) {
        // Reset device assignments to baseline
        CUDA_CHECK(cudaMemcpy(d_backbone_assignments, d_backbone_base, scc_graph.num_nodes * sizeof(int), cudaMemcpyDeviceToDevice));

        benchStart(g_bench, BENCH_DEVICE);
        solve(scc_graph, topo_result, d_backbone_assignments, wcc_grouped, d_sorted_wcc, h);
        benchEnd(g_bench, "heuristic" + std::to_string(static_cast<int>(h)), BENCH_DEVICE);
        int num_assignments = getNumAssignments(d_backbone_assignments, condensed.d_scc_lookup, scc_graph.num_nodes, graph.num_nodes);
        benchSetLastAssignments(g_bench, num_assignments);
    }

    // Cleanup
    CUDA_CHECK(cudaFree(d_backbone_base));
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
    return 0;
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
