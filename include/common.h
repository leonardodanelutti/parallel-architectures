#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <fstream>
#include <vector>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cmath>
#include <cstring>

/**
 * Common utilities for CUDA educational projects
 * Include this header in both .cpp and .cu files
 */

// Default CUDA block size (threads per block)
#define NumThPerBlock 512
// Default max number of blocks
#define MaxBlocks 80 // SMs * (maxThreadsPerSM / ThreadsPerBlock)

int gridStrideBlocks(int number_of_elements, int threads_per_block = NumThPerBlock, int max_blocks = MaxBlocks) {
    int blocks = (number_of_elements + NumThPerBlock - 1) / NumThPerBlock;
    return (blocks > MaxBlocks) ? MaxBlocks : blocks;
}

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
 * Creates a CSR graph from an edge lists.
 */
CSRGraph createCSRGraph(int num_nodes, int num_edges, const int2* edge_list) {
    CSRGraph csr;
    csr.num_nodes = num_nodes;
    csr.num_edges = num_edges;

    // Allocate Memory
    csr.row_ptr = new int[num_nodes + 1];
    csr.col_ind = new int[num_edges];
    std::memset(csr.row_ptr, 0, sizeof(int) * (num_nodes + 1));

    // Compute histogram
    for (int i = 0; i < num_edges; ++i) {
        int src = edge_list[i].x;
        if (src < num_nodes) {
            csr.row_ptr[src + 1]++;
        }
    }

    // Prefix Sum
    for (int i = 0; i < num_nodes; ++i) {
        csr.row_ptr[i + 1] += csr.row_ptr[i];
    }

    // Fill col_ind
    int* current_offset = new int[num_nodes];
    
    // Initialize current_offset with the starting positions from row_ptr
    for(int i = 0; i < num_nodes; ++i) {
        current_offset[i] = csr.row_ptr[i];
    }

    for (int i = 0; i < num_edges; ++i) {
        int src = edge_list[i].x;
        int dest = edge_list[i].y;

        if (src < num_nodes) {
            // Place the destination in the correct spot
            int write_pos = current_offset[src];
            csr.col_ind[write_pos] = dest;

            // Increment the offset for this specific node so the next edge 
            // from this source goes into the next slot.
            current_offset[src]++;
        }
    }

    // Clean up temporary memory
    delete[] current_offset;

    return csr;
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

            // Start reading clauses and build edge list
            int lit1, lit2, zero;
            std::vector<int2> edges;
            for (int i = 0; i < num_clauses; ++i) {
                file >> lit1 >> lit2 >> zero;
                // Add edges for implications
                int from1 = get_vertex_from_literal(-lit1);
                int to1   = get_vertex_from_literal(lit2);
                int from2 = get_vertex_from_literal(-lit2);
                int to2   = get_vertex_from_literal(lit1);

                edges.emplace_back(int2{from1, to1});
                edges.emplace_back(int2{from2, to2});
            }

            // Create CSR graph using the correct algorithm
            graph = createCSRGraph(num_vars * 2, edges.size(), edges.data());

            break;
        }
    }

}

#endif // COMMON_H
