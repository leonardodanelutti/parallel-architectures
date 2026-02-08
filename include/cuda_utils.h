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

/*
#define CUSPARSE_CHECK(call) \
    do { \
        cusparseStatus_t status = call; \
        if (status != CUSPARSE_STATUS_SUCCESS) { \
            std::cerr << "cuSPARSE error at " << __FILE__ << ":" << __LINE__ << " - " \
                      << cusparseGetErrorString(status) << std::endl; \
            exit(EXIT_FAILURE); \
        } \
    } while(0)
*/

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

// Utility function to free CSR graph memory in the device
void freeDeviceCSRRepr(CSRRepr& graph) {
    CUDA_CHECK(cudaFree(graph.row_ptr));
    CUDA_CHECK(cudaFree(graph.col_ind));

    graph.num_nodes = 0;
    graph.num_edges = 0;
    graph.row_ptr = nullptr;
    graph.col_ind = nullptr;
}

// Convert CSR to CSC format using cuSPARSE
// the input CSR graph is expected to be on the device and the output CSC graph will also be on the device
/*
CSRRepr CSR2CSC(const CSRRepr& d_csr) {
    int *d_csc_col_ptr, *d_csc_row_ind;

    CUDA_CHECK(cudaMalloc(&d_csc_col_ptr, (d_csr.num_nodes + 1) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_csc_row_ind, d_csr.num_edges * sizeof(int)));


    // Set up cuSPARSE
    cusparseHandle_t handle;
    CUSPARSE_CHECK(cusparseCreate(&handle));

    size_t bufferSize = 0;
    void* d_buffer = nullptr;

    // Get buffer size
    CUSPARSE_CHECK(cusparseCsr2cscEx2_bufferSize(
        handle, d_csr.num_nodes, d_csr.num_nodes, d_csr.num_edges,
        nullptr, d_csr.row_ptr, d_csr.col_ind,
        nullptr, d_csc_col_ptr, d_csc_row_ind,
        CUDA_R_32F, CUSPARSE_ACTION_SYMBOLIC,
        CUSPARSE_INDEX_BASE_ZERO, CUSPARSE_CSR2CSC_ALG_DEFAULT, &bufferSize
    ));

    CUDA_CHECK(cudaMalloc(&d_buffer, bufferSize));

    // Perform transpose
    CUSPARSE_CHECK(cusparseCsr2cscEx2(
        handle, d_csr.num_nodes, d_csr.num_nodes, d_csr.num_edges,
        nullptr, d_csr.row_ptr, d_csr.col_ind,
        nullptr, d_csc_col_ptr, d_csc_row_ind,
        CUDA_R_32F, CUSPARSE_ACTION_SYMBOLIC,
        CUSPARSE_INDEX_BASE_ZERO, CUSPARSE_CSR2CSC_ALG_DEFAULT, d_buffer
    ));

    // Clean up
    CUSPARSE_CHECK(cusparseDestroy(handle));
    CUDA_CHECK(cudaFree(d_buffer));

    CSRRepr csc;
    csc.num_nodes = d_csr.num_nodes;
    csc.num_edges = d_csr.num_edges;
    csc.row_ptr = d_csc_col_ptr;
    csc.col_ind = d_csc_row_ind;

    return csc;
}
*/

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