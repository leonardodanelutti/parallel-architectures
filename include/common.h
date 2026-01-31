#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cmath>

/**
 * Common utilities for CUDA educational projects
 * Include this header in both .cpp and .cu files
 */

// Default CUDA block size (threads per block)
#define NumThPerBlock 512

/**
 * Timer class for performance benchmarking
 * Usage:
 *   Timer timer;
 *   timer.start();
 *   // ... code to benchmark ...
 *   double elapsed_ms = timer.stop();
 */
class Timer {
private:
    std::chrono::high_resolution_clock::time_point start_time;
    
public:
    void start() {
        start_time = std::chrono::high_resolution_clock::now();
    }
    
    double stop() {
        auto end_time = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double, std::milli> duration = end_time - start_time;
        return duration.count();
    }
};


/**
 * Simple CSR Graph structure
 */
struct CSRGraph {
    int num_nodes;
    int num_edges;
    int* row_ptr;
    int* col_ind;
};

void freeCSRGraph(CSRGraph& graph) {
    delete[] graph.row_ptr;
    delete[] graph.col_ind;

    graph.num_nodes = 0;
    graph.num_edges = 0;
    graph.row_ptr = nullptr;
    graph.col_ind = nullptr;
}

int get_vertex_from_literal(int lit) {
    return (lit > 0) ? 2 * lit - 2 : 2 * (-lit) - 1;
}


/**
 * Reads a 2SAT instance from a DIMACS CNF file and constructs its implication graph in CSR format.
 */

void read2SATInstance(const std::string& filename, int& num_vars, int& num_clauses, int& asp_result, CSRGraph& graph) {
    std::ifstream file(filename);
    if (!file) {
        std::cerr << "Error opening file: " << filename << std::endl;
        exit(EXIT_FAILURE);
    }

    std::string token;
    while (file >> token) {
        // read fixed variables
        // c fixed-timeout: 154
        if (token == "c") {
            if (file >> token && (token == "fixed-timeout:" || token == "fixed:")) {
                file >> asp_result;
            }
        }

        if (token == "p") {
            // p cnf num_vars num_clauses
            file >> token;
            if (token != "cnf") {
                std::cerr << "Unsupported format: " << token << std::endl;
                exit(EXIT_FAILURE);
            }
            file >> num_vars;
            file >> num_clauses;

            // Initialize graph structure
            graph.num_nodes = num_vars * 2; // each variable has pos and neg
            graph.num_edges = num_clauses * 2; // each clause adds two implications
            graph.row_ptr = new int[graph.num_nodes + 1];
            graph.col_ind = new int[graph.num_edges];
            
            // Start reading clauses
            int lit1, lit2, zero;
            std::vector<std::pair<int, int>> edges;
            for (int i = 0; i < num_clauses; ++i) {
                file >> lit1 >> lit2 >> zero;
                // Add edges for implications
                int from1 = get_vertex_from_literal(-lit1);
                int to1   = get_vertex_from_literal(lit2);
                int from2 = get_vertex_from_literal(-lit2);
                int to2   = get_vertex_from_literal(lit1);

                edges.emplace_back(from1, to1);
                edges.emplace_back(from2, to2);
            }

            // Build CSR representation
            std::sort(edges.begin(), edges.end());
            std::fill(graph.row_ptr, graph.row_ptr + graph.num_nodes + 1, 0);

            int edge_count = graph.num_edges;
            for (const auto& edge : edges) {
                graph.row_ptr[edge.first + 1]++;
                graph.col_ind[--edge_count] = edge.second;
            }

            for (int i = 1; i <= graph.num_nodes; ++i) {
                graph.row_ptr[i] += graph.row_ptr[i - 1];
            }

            break;
        }
    }

}

#endif // COMMON_H
