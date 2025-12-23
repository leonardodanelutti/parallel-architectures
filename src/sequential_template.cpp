#include "../include/common.h"

/**
 * Sequential (CPU) Implementation Template
 * 
 * This file provides a template for implementing sequential algorithms
 * to serve as a baseline for benchmarking against CUDA implementations.
 * 
 * TODO: Implement your algorithm here
 */

// Add your sequential algorithm implementation here
void sequentialAlgorithm() {
    // Your code here
    std::cout << "Sequential algorithm - implement your solution" << std::endl;
}

int main() {
    std::cout << "=== Sequential Implementation ===" << std::endl;
    
    // TODO: Setup your problem
    // Example:
    // - Allocate memory
    // - Initialize data
    // - Set problem parameters
    
    // TODO: Run and time your algorithm
    Timer timer;
    timer.start();
    
    sequentialAlgorithm();
    
    double elapsed = timer.stop();
    
    // TODO: Display results
    std::cout << "Execution time: " << elapsed << " ms" << std::endl;
    
    // TODO: Cleanup
    // - Free allocated memory
    
    std::cout << "Sequential execution completed!" << std::endl;
    
    return 0;
}
