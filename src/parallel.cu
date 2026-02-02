#include "../include/common.h"
#include "../include/cuda_utils.h"
#include "SCC.cu"
#include "topo_sort.cu"

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
    CSRGraph graph;
    read2SATInstance(filename, num_vars, num_clauses, asp_result, graph);

    // TODO: Start CUDA event timing

    // Allocate device memory
    CSRGraph d_graph;
    CUDA_CHECK(cudaMalloc(&d_graph.row_ptr, (graph.num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_graph.col_ind, graph.num_edges * sizeof(int)));
    
    // Copy data from host to device
    CUDA_CHECK(cudaMemcpy(d_graph.row_ptr, graph.row_ptr, (graph.num_nodes + 1) * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_graph.col_ind, graph.col_ind, graph.num_edges * sizeof(int), cudaMemcpyHostToDevice));
    d_graph.num_nodes = graph.num_nodes;
    d_graph.num_edges = graph.num_edges;

    // Compute the condensed graph of SCCs
    CSRGraph scc_graph = computeCondensedGraph(d_graph);

    // Khan's algorithm for topological sort on the condensed graph, also check for 2i -> 2i+1

    // Calc WCCs
    // Delete complement WCCs

    // Strategies:
    // 1. put all sources to true
    // 2. put all sinks to false
    // 3. Strategie on a WCC component:
    //    - sources to true or sinks to false based on which is smaller
    //    - choose a node, assign a value and delete all reachable nodes, repeat until all nodes are deleted
    
    // TODO: Copy results back from device to host
    // CUDA_CHECK(cudaMemcpy(h_result, d_result, bytes, cudaMemcpyDeviceToHost));
    
    
    // TODO: Cleanup
    // - Free device memory: CUDA_CHECK(cudaFree(d_data));
    // Free host memory
    freeCSRGraph(graph);
    // - Destroy CUDA events: CUDA_CHECK(cudaEventDestroy(start));
    
    // std::cout << "CUDA execution completed!" << std::endl;
    
    return 0;
}
