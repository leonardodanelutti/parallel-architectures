#ifndef CUDA_UTILS_H
#define CUDA_UTILS_H

#include <cuda_runtime.h>
#include <iostream>

/**
 * CUDA Error Checking Macro
 * 
 * Usage:
 *   CUDA_CHECK(cudaMalloc(&d_ptr, size));
 *   CUDA_CHECK(cudaMemcpy(d_ptr, h_ptr, size, cudaMemcpyHostToDevice));
 * 
 * This macro will check the return value of any CUDA API call
 * and print an error message with file/line information if it fails.
 */
#define CUDA_CHECK(call) \
    do { \
        cudaError_t error = call; \
        if (error != cudaSuccess) { \
            std::cerr << "CUDA error at " << __FILE__ << ":" << __LINE__ << " - " \
                      << cudaGetErrorString(error) << std::endl; \
            exit(EXIT_FAILURE); \
        } \
    } while(0)

/**
 * Print GPU device properties
 */
inline void printDeviceInfo(int device = 0) {
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device));
    
    std::cout << "========================================" << std::endl;
    std::cout << "GPU Device Information:" << std::endl;
    std::cout << "========================================" << std::endl;
    std::cout << "Device name: " << prop.name << std::endl;
    std::cout << "Compute capability: " << prop.major << "." << prop.minor << std::endl;
    std::cout << "Global memory: " << prop.totalGlobalMem / (1024.0 * 1024.0) << " MB" << std::endl;
    std::cout << "Shared memory per block: " << prop.sharedMemPerBlock / 1024.0 << " KB" << std::endl;
    std::cout << "Registers per block: " << prop.regsPerBlock << std::endl;
    std::cout << "Warp size: " << prop.warpSize << std::endl;
    std::cout << "Max threads per block: " << prop.maxThreadsPerBlock << std::endl;
    std::cout << "Max threads dimensions: [" 
              << prop.maxThreadsDim[0] << ", "
              << prop.maxThreadsDim[1] << ", "
              << prop.maxThreadsDim[2] << "]" << std::endl;
    std::cout << "Max grid dimensions: [" 
              << prop.maxGridSize[0] << ", "
              << prop.maxGridSize[1] << ", "
              << prop.maxGridSize[2] << "]" << std::endl;
    std::cout << "Multiprocessor count: " << prop.multiProcessorCount << std::endl;
    std::cout << "Memory bus width: " << prop.memoryBusWidth << " bits" << std::endl;
    std::cout << "========================================" << std::endl;
}

/*
========================================
GPU Device Information - Colab
========================================
Device name: Tesla T4
Compute capability: 7.5
Global memory: 15095.1 MB
Shared memory per block: 48 KB
Registers per block: 65536
Warp size: 32
Max threads per block: 1024
Max threads dimensions: [1024, 1024, 64]
Max grid dimensions: [2147483647, 65535, 65535]
Multiprocessor count: 40
Memory clock rate: 5001 MHz
Memory bus width: 256 bits
========================================
*/

#endif // CUDA_UTILS_H