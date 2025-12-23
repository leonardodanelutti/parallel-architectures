#include "../include/common.h"
#include <cuda_runtime.h>
#include <iomanip>

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
 * Sequential vector addition on CPU
 */
void vectorAddSequential(const float* a, const float* b, float* c, int size) {
    for (int i = 0; i < size; i++) {
        c[i] = a[i] + b[i];
    }
}

/**
 * CUDA kernel for vector addition
 */
__global__ void vectorAddKernel(const float* a, const float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}

/**
 * Benchmark results structure
 */
struct BenchmarkResult {
    int size;
    double sequentialTime;
    double cudaTotalTime;
    double cudaKernelTime;
    double speedupTotal;
    double speedupKernel;
    bool verified;
};

/**
 * Run benchmark for a specific problem size
 */
BenchmarkResult runBenchmark(int N) {
    BenchmarkResult result;
    result.size = N;
    
    const size_t bytes = N * sizeof(float);
    
    // Allocate host memory
    float* h_a = new float[N];
    float* h_b = new float[N];
    float* h_c_seq = new float[N];
    float* h_c_cuda = new float[N];
    
    // Initialize vectors
    srand(42); // Fixed seed for reproducibility
    initializeVector(h_a, N);
    initializeVector(h_b, N);
    
    // === Sequential benchmark ===
    Timer timer;
    timer.start();
    vectorAddSequential(h_a, h_b, h_c_seq, N);
    result.sequentialTime = timer.stop();
    
    // === CUDA benchmark ===
    
    // Allocate device memory
    float *d_a, *d_b, *d_c;
    CUDA_CHECK(cudaMalloc(&d_a, bytes));
    CUDA_CHECK(cudaMalloc(&d_b, bytes));
    CUDA_CHECK(cudaMalloc(&d_c, bytes));
    
    // Create CUDA events for timing
    cudaEvent_t start, stop, kernelStart, kernelStop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    CUDA_CHECK(cudaEventCreate(&kernelStart));
    CUDA_CHECK(cudaEventCreate(&kernelStop));
    
    // Start total time (including memory transfers)
    CUDA_CHECK(cudaEventRecord(start));
    
    // Copy data to device
    CUDA_CHECK(cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice));
    
    // Configure and launch kernel
    int threadsPerBlock = BLOCK_SIZE;
    int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
    
    CUDA_CHECK(cudaEventRecord(kernelStart));
    vectorAddKernel<<<blocksPerGrid, threadsPerBlock>>>(d_a, d_b, d_c, N);
    CUDA_CHECK(cudaEventRecord(kernelStop));
    
    // Copy result back
    CUDA_CHECK(cudaMemcpy(h_c_cuda, d_c, bytes, cudaMemcpyDeviceToHost));
    
    // Stop total time
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));
    
    // Calculate times
    float totalTime, kernelTime;
    CUDA_CHECK(cudaEventElapsedTime(&totalTime, start, stop));
    CUDA_CHECK(cudaEventElapsedTime(&kernelTime, kernelStart, kernelStop));
    
    result.cudaTotalTime = totalTime;
    result.cudaKernelTime = kernelTime;
    result.speedupTotal = result.sequentialTime / result.cudaTotalTime;
    result.speedupKernel = result.sequentialTime / result.cudaKernelTime;
    
    // Verify correctness
    result.verified = verifyResult(h_c_seq, h_c_cuda, N);
    
    // Cleanup
    delete[] h_a;
    delete[] h_b;
    delete[] h_c_seq;
    delete[] h_c_cuda;
    
    CUDA_CHECK(cudaFree(d_a));
    CUDA_CHECK(cudaFree(d_b));
    CUDA_CHECK(cudaFree(d_c));
    
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    CUDA_CHECK(cudaEventDestroy(kernelStart));
    CUDA_CHECK(cudaEventDestroy(kernelStop));
    
    return result;
}

/**
 * Print formatted benchmark results
 */
void printResults(const BenchmarkResult& result) {
    std::cout << std::fixed << std::setprecision(2);
    std::cout << std::setw(15) << result.size 
              << std::setw(15) << result.sequentialTime
              << std::setw(15) << result.cudaTotalTime
              << std::setw(15) << result.cudaKernelTime
              << std::setw(12) << result.speedupTotal << "x"
              << std::setw(12) << result.speedupKernel << "x"
              << std::setw(12) << (result.verified ? "PASS" : "FAIL")
              << std::endl;
}

int main() {
    std::cout << "=========================================" << std::endl;
    std::cout << "  CUDA vs Sequential Vector Addition" << std::endl;
    std::cout << "         Benchmark Comparison" << std::endl;
    std::cout << "=========================================" << std::endl;
    std::cout << std::endl;
    
    // Query GPU information
    int device = 0;
    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, device));
    
    std::cout << "GPU Information:" << std::endl;
    std::cout << "  Device: " << prop.name << std::endl;
    std::cout << "  Compute capability: " << prop.major << "." << prop.minor << std::endl;
    std::cout << "  Global memory: " << prop.totalGlobalMem / (1024.0 * 1024.0 * 1024.0) 
              << " GB" << std::endl;
    std::cout << "  Multiprocessors: " << prop.multiProcessorCount << std::endl;
    std::cout << "  Max threads per block: " << prop.maxThreadsPerBlock << std::endl;
    std::cout << std::endl;
    
    // Problem sizes to benchmark
    int sizes[] = {
        1 << 20,  // 1M elements   (~4 MB)
        1 << 22,  // 4M elements   (~16 MB)
        1 << 24,  // 16M elements  (~64 MB)
        1 << 26   // 64M elements  (~256 MB)
    };
    int numSizes = sizeof(sizes) / sizeof(sizes[0]);
    
    std::cout << "Running benchmarks for " << numSizes << " different problem sizes..." << std::endl;
    std::cout << "Block size: " << BLOCK_SIZE << " threads" << std::endl;
    std::cout << std::endl;
    
    // Print header
    std::cout << std::setw(15) << "Size (elems)"
              << std::setw(15) << "CPU (ms)"
              << std::setw(15) << "GPU+Mem (ms)"
              << std::setw(15) << "GPU Only (ms)"
              << std::setw(12) << "Speedup"
              << std::setw(12) << "Kernel"
              << std::setw(12) << "Verified"
              << std::endl;
    std::cout << std::string(96, '-') << std::endl;
    
    // Run benchmarks
    for (int i = 0; i < numSizes; i++) {
        BenchmarkResult result = runBenchmark(sizes[i]);
        printResults(result);
    }
    
    std::cout << std::string(96, '-') << std::endl;
    std::cout << std::endl;
    
    std::cout << "Key Observations:" << std::endl;
    std::cout << "  - GPU+Mem includes all memory transfer overhead" << std::endl;
    std::cout << "  - GPU Only shows pure kernel computation time" << std::endl;
    std::cout << "  - Speedup improves with larger problem sizes" << std::endl;
    std::cout << "  - Memory transfers can dominate for small sizes" << std::endl;
    std::cout << std::endl;
    
    std::cout << "Educational Notes:" << std::endl;
    std::cout << "  1. Vector addition is memory-bound (limited by bandwidth)" << std::endl;
    std::cout << "  2. Larger problems amortize memory transfer costs better" << std::endl;
    std::cout << "  3. GPU excels at massively parallel operations" << std::endl;
    std::cout << "  4. Always verify correctness when optimizing!" << std::endl;
    std::cout << std::endl;
    
    std::cout << "Benchmark completed successfully!" << std::endl;
    
    return 0;
}
