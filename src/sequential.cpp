#include "../include/common.h"

/**
 * Sequential (CPU) Implementation
 * 
 * TODO: Implement your algorithm here
 */

// Add your sequential algorithm implementation here
void sequentialAlgorithm() {
    std::cout << "Sequential algorithm - implement your solution" << std::endl;
}

int main() {
    std::cout << "=== Sequential Implementation ===" << std::endl;
    
    // TODO: Setup
    
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
