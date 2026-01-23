#include "../include/common.h"
#include "../include/cuda_utils.h"

/**
 * CUDA Implementation Template
 * 
 * TODO: Implement your CUDA kernel and host code here
 */

/**
 * CUDA Kernel
 */
__global__ void cudaKernel() {
    // Calculate global thread ID
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // TODO: Implement your kernel logic here
}

int main() {
    std::cout << "=== CUDA Implementation ===" << std::endl;
    
    // Print GPU information
    printDeviceInfo();
    std::cout << std::endl;
    
    // TODO: Setup
    
    // TODO: Allocate device memory
    // Example:
    // float* d_data;
    // CUDA_CHECK(cudaMalloc(&d_data, N * sizeof(float)));
    
    // TODO: Copy data from host to device
    // Example:
    // CUDA_CHECK(cudaMemcpy(d_data, h_data, bytes, cudaMemcpyHostToDevice));
    
    // TODO: Configure kernel launch parameters
    // int threadsPerBlock = BLOCK_SIZE;  // Defined in common.h
    // int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
    
    // TODO: Create CUDA events for timing
    // cudaEvent_t start, stop;
    // CUDA_CHECK(cudaEventCreate(&start));
    // CUDA_CHECK(cudaEventCreate(&stop));
    
    // TODO: Launch kernel with timing
    // CUDA_CHECK(cudaEventRecord(start));
    // cudaKernel<<<blocksPerGrid, threadsPerBlock>>>(/* parameters */);
    // CUDA_CHECK(cudaGetLastError()); // Check for launch errors
    // CUDA_CHECK(cudaEventRecord(stop));
    // CUDA_CHECK(cudaEventSynchronize(stop));
    
    // TODO: Calculate elapsed time
    // float milliseconds = 0;
    // CUDA_CHECK(cudaEventElapsedTime(&milliseconds, start, stop));
    // std::cout << "Kernel execution time: " << milliseconds << " ms" << std::endl;
    
    // TODO: Copy results back from device to host
    // CUDA_CHECK(cudaMemcpy(h_result, d_result, bytes, cudaMemcpyDeviceToHost));
    
    // TODO: Verify correctness
    // Compare GPU results with CPU results or known correct output
    
    // TODO: Cleanup
    // - Free device memory: CUDA_CHECK(cudaFree(d_data));
    // - Free host memory: delete[] h_data;
    // - Destroy CUDA events: CUDA_CHECK(cudaEventDestroy(start));
    
    std::cout << "CUDA execution completed!" << std::endl;
    
    return 0;
}
