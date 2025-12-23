# Quick Start Guide

This guide will help you get started with the CUDA project template in 5 minutes.

## Step 1: Verify Environment

Check that you have CUDA installed:
```bash
nvcc --version
```

Check that you have a CUDA-capable GPU:
```bash
nvidia-smi
```

## Step 2: Test the Templates

Build and run the template examples:
```bash
make templates
```

This creates three executables that show the basic structure.

## Step 3: Choose Your Problem

Pick a problem to implement. Good starting problems:

**Easy:**
- Vector addition
- Vector scaling (multiply by constant)
- Element-wise vector operations

**Medium:**
- Matrix addition
- Vector dot product
- Finding max/min element

**Challenging:**
- Matrix multiplication
- Image convolution
- Histogram calculation

## Step 4: Create Your Implementation

Let's implement vector addition as an example:

```bash
# Copy the template files
cp src/sequential_template.cpp src/vector_add_sequential.cpp
cp src/cuda_template.cu src/vector_add_cuda.cu
cp src/benchmark_template.cpp src/vector_add_benchmark.cpp
```

## Step 5: Implement Sequential Version

Edit `src/vector_add_sequential.cpp`:

```cpp
#include "../include/common.h"

void vectorAddSequential(const float* a, const float* b, float* c, int n) {
    for (int i = 0; i < n; i++) {
        c[i] = a[i] + b[i];
    }
}

int main() {
    const int N = 1000000;  // 1M elements
    
    // Allocate and initialize
    float* a = new float[N];
    float* b = new float[N];
    float* c = new float[N];
    
    for (int i = 0; i < N; i++) {
        a[i] = 1.0f;
        b[i] = 2.0f;
    }
    
    // Time the operation
    Timer timer;
    timer.start();
    vectorAddSequential(a, b, c, N);
    double time = timer.stop();
    
    std::cout << "Time: " << time << " ms" << std::endl;
    std::cout << "Result check: c[0] = " << c[0] << " (should be 3.0)" << std::endl;
    
    // Cleanup
    delete[] a;
    delete[] b;
    delete[] c;
    
    return 0;
}
```

## Step 6: Implement CUDA Version

Edit `src/vector_add_cuda.cu`:

```cpp
#include "../include/common.h"
#include "../include/cuda_utils.h"

__global__ void vectorAddKernel(const float* a, const float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}

int main() {
    const int N = 1000000;
    const size_t bytes = N * sizeof(float);
    
    // Allocate host memory
    float* h_a = new float[N];
    float* h_b = new float[N];
    float* h_c = new float[N];
    
    // Initialize
    for (int i = 0; i < N; i++) {
        h_a[i] = 1.0f;
        h_b[i] = 2.0f;
    }
    
    // Allocate device memory
    float *d_a, *d_b, *d_c;
    CUDA_CHECK(cudaMalloc(&d_a, bytes));
    CUDA_CHECK(cudaMalloc(&d_b, bytes));
    CUDA_CHECK(cudaMalloc(&d_c, bytes));
    
    // Copy to device
    CUDA_CHECK(cudaMemcpy(d_a, h_a, bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_b, h_b, bytes, cudaMemcpyHostToDevice));
    
    // Launch kernel
    int threads = BLOCK_SIZE;
    int blocks = (N + threads - 1) / threads;
    
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    
    CUDA_CHECK(cudaEventRecord(start));
    vectorAddKernel<<<blocks, threads>>>(d_a, d_b, d_c, N);
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));
    
    float time;
    CUDA_CHECK(cudaEventElapsedTime(&time, start, stop));
    
    // Copy back
    CUDA_CHECK(cudaMemcpy(h_c, d_c, bytes, cudaMemcpyDeviceToHost));
    
    std::cout << "Kernel time: " << time << " ms" << std::endl;
    std::cout << "Result check: c[0] = " << h_c[0] << " (should be 3.0)" << std::endl;
    
    // Cleanup
    delete[] h_a;
    delete[] h_b;
    delete[] h_c;
    CUDA_CHECK(cudaFree(d_a));
    CUDA_CHECK(cudaFree(d_b));
    CUDA_CHECK(cudaFree(d_c));
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    
    return 0;
}
```

## Step 7: Add Build Rules

Edit `Makefile` and add these rules after line 54:

```makefile
# Uncomment this line
TARGETS = vector_add_sequential vector_add_cuda vector_add_benchmark

# Add these rules
vector_add_sequential: $(SRC_DIR)/vector_add_sequential.cpp
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@

vector_add_cuda: $(SRC_DIR)/vector_add_cuda.cu
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@

vector_add_benchmark: $(SRC_DIR)/vector_add_benchmark.cpp
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
```

## Step 8: Build and Run

```bash
# Build everything
make build

# Run sequential version
./vector_add_sequential

# Run CUDA version
./vector_add_cuda

# Run benchmark
./vector_add_benchmark
```

## Tips

1. **Start Simple**: Get the sequential version working first
2. **Test Small**: Use small arrays (e.g., 100 elements) during development
3. **Verify Always**: Always check your GPU results match CPU results
4. **Check Errors**: Use CUDA_CHECK() for all CUDA API calls
5. **Profile**: Use different problem sizes to see where GPU wins

## Common Issues

**Kernel doesn't work:**
- Check boundary condition: `if (idx < n)`
- Verify block/grid calculation
- Check for CUDA errors with `CUDA_CHECK(cudaGetLastError())`

**Slow performance:**
- Problem might be too small
- Memory transfers dominating
- Try larger data sizes

**Compilation errors:**
- Check file extensions (.cpp vs .cu)
- Verify nvcc is in PATH
- Check architecture flag matches GPU

## Next Steps

After getting this working:
1. Add command-line arguments for problem size
2. Implement matrix operations (2D indexing)
3. Optimize with shared memory
4. Profile with nvprof or Nsight
5. Try more complex algorithms

---

**You're ready to start! Pick a problem and start coding. 🚀**
