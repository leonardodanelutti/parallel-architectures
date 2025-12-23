# Parallel Architectures - CUDA Educational Project

This repository contains an educational implementation of parallel computing using CUDA, benchmarked against a sequential implementation.

## Project Overview

This project demonstrates the performance benefits of GPU acceleration using CUDA by implementing a vector addition algorithm in both sequential (CPU) and parallel (GPU) versions.

### Problem: Vector Addition

Vector addition is a fundamental operation in parallel computing where two vectors are added element-wise:
```
C[i] = A[i] + B[i] for all i
```

This is an ideal first problem for learning CUDA because:
- Each element operation is independent (embarrassingly parallel)
- Simple to understand and implement
- Clearly demonstrates GPU speedup
- Shows memory transfer overhead considerations

## Project Structure

```
.
├── README.md
├── Makefile
├── src/
│   ├── vector_add_sequential.cpp  # CPU implementation
│   ├── vector_add_cuda.cu         # GPU implementation
│   └── benchmark.cpp              # Main benchmark driver
└── include/
    └── common.h                   # Common definitions
```

## Requirements

- CUDA Toolkit (10.0 or higher)
- C++ compiler with C++11 support
- NVIDIA GPU with compute capability 3.0 or higher

## Building

```bash
make all
```

This will compile both the sequential and CUDA versions.

## Running

### Sequential Version
```bash
./vector_add_sequential
```

### CUDA Version
```bash
./vector_add_cuda
```

### Full Benchmark
```bash
./benchmark
```

The benchmark will run both implementations with various problem sizes and compare their performance.

## Expected Output

The benchmark will display:
- Problem size (number of elements)
- Sequential execution time
- CUDA execution time (including memory transfers)
- CUDA computation time (kernel only)
- Speedup factor
- Verification of correctness

## Learning Objectives

This project teaches:
1. **CUDA Basics**: Kernel functions, thread organization, memory management
2. **Performance Analysis**: Understanding GPU speedup and overhead
3. **Memory Transfers**: Impact of host-device data movement
4. **Benchmarking**: Proper timing and performance comparison
5. **Error Handling**: CUDA error checking best practices

## Implementation Details

### Sequential Implementation
- Simple CPU loop
- High-precision timing using chrono
- Baseline for comparison

### CUDA Implementation
- 1D grid and block configuration
- Optimized thread-per-element mapping
- Proper memory allocation and transfer
- CUDA events for accurate GPU timing
- Error checking for all CUDA calls

## Performance Considerations

- **Memory Bandwidth**: Vector addition is memory-bound
- **Transfer Overhead**: PCIe transfers can dominate small problem sizes
- **Optimal Block Size**: Typically 256 or 512 threads per block
- **Problem Size**: GPU advantage increases with larger vectors

## Cleaning Up

```bash
make clean
```

## Educational Use

This code is designed for learning. Key educational features:
- Well-commented code explaining each step
- Error messages for common mistakes
- Multiple problem sizes to show scaling
- Clear separation of concerns
- Comprehensive output for analysis

## License

This is educational code intended for learning purposes.