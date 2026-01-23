#include "../include/common.h"
#include "../include/cuda_utils.h"

/**
 * Benchmark Template
 * 
 * This file provides a template for comparing sequential and CUDA implementations.
 * It runs both versions and compares their performance.
 * 
 * TODO: Implement sequential and CUDA algorithms, then benchmark them
 */

// TODO: Sequential algorithm
void sequentialImplementation() {
    // Your sequential code here
}

// TODO: CUDA kernel
__global__ void cudaKernel() {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    // Your CUDA kernel code here
}

// TODO: CUDA version
void cudaImplementation() {
    // Your CUDA setup, kernel launch, and cleanup here
}

int main() {
    std::cout << "=========================================" << std::endl;
    std::cout << "  Sequential vs CUDA Benchmark" << std::endl;
    std::cout << "=========================================" << std::endl;
    std::cout << std::endl;
    
    // Print GPU information
    printDeviceInfo();
    std::cout << std::endl;
    
    // TODO: Setup problem
    // - Define problem size(s)
    // - Allocate and initialize data
    
    // === Sequential Benchmark ===
    std::cout << "Running sequential implementation..." << std::endl;
    Timer seqTimer;
    seqTimer.start();
    
    sequentialImplementation();
    
    double seqTime = seqTimer.stop();
    std::cout << "Sequential time: " << seqTime << " ms" << std::endl;
    std::cout << std::endl;
    
    // === CUDA Benchmark ===
    std::cout << "Running CUDA implementation..." << std::endl;
    Timer cudaTimer;
    cudaTimer.start();
    
    cudaImplementation();
    
    double cudaTime = cudaTimer.stop();
    std::cout << "CUDA time: " << cudaTime << " ms" << std::endl;
    std::cout << std::endl;
    
    // === Results Comparison ===
    std::cout << "=========================================" << std::endl;
    std::cout << "Performance Comparison:" << std::endl;
    std::cout << "=========================================" << std::endl;
    std::cout << "Sequential: " << seqTime << " ms" << std::endl;
    std::cout << "CUDA:       " << cudaTime << " ms" << std::endl;
    std::cout << "Speedup:    " << (seqTime / cudaTime) << "x" << std::endl;
    std::cout << "=========================================" << std::endl;
    std::cout << std::endl;
    
    // TODO: Verify correctness
    // Compare results from both implementations
    
    // TODO: Cleanup
    // Free all allocated memory
    
    std::cout << "Benchmark completed!" << std::endl;
    
    return 0;
}
