#include "../include/common.h"
#include <cuda_runtime.h>

/**
 * CUDA error checking macro
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
 * CUDA kernel for vector addition
 * Each thread computes one element of the result vector
 */
__global__ void vectorAddKernel(const float* a, const float* b, float* c, int n) {
    // Calculate global thread ID
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // Boundary check: ensure we don't access out of bounds
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}

int main() {
    // Problem size
    const int N = MEDIUM_SIZE;
    const size_t bytes = N * sizeof(float);
    
    std::cout << "=== CUDA Vector Addition ===" << std::endl;
    std::cout << "Vector size: " << N << " elements (" 
              << bytes / (1024.0 * 1024.0) << " MB)" << std::endl;
    
    // Query GPU properties
    int device = 0;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device));
    std::cout << "Using GPU: " << prop.name << std::endl;
    std::cout << "Compute capability: " << prop.major << "." << prop.minor << std::endl;
    
    // Allocate memory on host
    float* h_a = new float[N];
    float* h_b = new float[N];
    float* h_c = new float[N];
    
    // Initialize vectors with random values
    std::cout << "\nInitializing vectors..." << std::endl;
    srand(42); // Fixed seed for reproducibility
    initializeVector(h_a, N);
    initializeVector(h_b, N);
    
    // Allocate memory on device
    float *d_a, *d_b, *d_c;
    CUDA_CHECK(cudaMalloc(&d_a, bytes));
    CUDA_CHECK(cudaMalloc(&d_b, bytes));
    CUDA_CHECK(cudaMalloc(&d_c, bytes));
    
    // Create CUDA events for timing
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    
    // Copy data from host to device
    std::cout << "Copying data to GPU..." << std::endl;
    CUDA_CHECK(cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice));
    
    // Configure kernel launch parameters
    int threadsPerBlock = BLOCK_SIZE;
    int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
    
    std::cout << "Launching kernel with " << blocksPerGrid << " blocks and " 
              << threadsPerBlock << " threads per block..." << std::endl;
    
    // Launch kernel and measure time
    CUDA_CHECK(cudaEventRecord(start));
    vectorAddKernel<<<blocksPerGrid, threadsPerBlock>>>(d_a, d_b, d_c, N);
    CUDA_CHECK(cudaEventRecord(stop));
    
    // Wait for kernel to complete
    CUDA_CHECK(cudaEventSynchronize(stop));
    
    // Calculate kernel execution time
    float kernelTime = 0;
    CUDA_CHECK(cudaEventElapsedTime(&kernelTime, start, stop));
    
    // Copy result back to host
    std::cout << "Copying result back to CPU..." << std::endl;
    CUDA_CHECK(cudaMemcpy(h_c, d_c, bytes, cudaMemcpyDeviceToHost));
    
    std::cout << "\n--- Results ---" << std::endl;
    std::cout << "Kernel execution time: " << kernelTime << " ms" << std::endl;
    
    // Calculate throughput (kernel only)
    double throughput = (3.0 * bytes / (1024.0 * 1024.0 * 1024.0)) / (kernelTime / 1000.0);
    std::cout << "Kernel throughput: " << throughput << " GB/s" << std::endl;
    
    // Verify a few results
    std::cout << "\nSample results:" << std::endl;
    for (int i = 0; i < 5; i++) {
        std::cout << h_a[i] << " + " << h_b[i] << " = " << h_c[i] << std::endl;
    }
    
    // Verify correctness (compare with CPU calculation)
    std::cout << "\nVerifying correctness..." << std::endl;
    float* h_verify = new float[N];
    for (int i = 0; i < N; i++) {
        h_verify[i] = h_a[i] + h_b[i];
    }
    
    if (verifyResult(h_c, h_verify, N)) {
        std::cout << "✓ Verification PASSED - Results are correct!" << std::endl;
    } else {
        std::cout << "✗ Verification FAILED - Results are incorrect!" << std::endl;
    }
    
    // Cleanup
    delete[] h_a;
    delete[] h_b;
    delete[] h_c;
    delete[] h_verify;
    
    CUDA_CHECK(cudaFree(d_a));
    CUDA_CHECK(cudaFree(d_b));
    CUDA_CHECK(cudaFree(d_c));
    
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    
    std::cout << "\nCUDA execution completed successfully!" << std::endl;
    
    return 0;
}
