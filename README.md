# Parallel Architectures - CUDA Project Template

This repository provides a structured template for educational CUDA projects with benchmarking capabilities against sequential implementations.

## Project Overview

This template helps you:
- **Learn CUDA programming** with a clear project structure
- **Implement parallel algorithms** with GPU acceleration
- **Benchmark performance** comparing CPU vs GPU implementations
- **Follow best practices** for CUDA development

## Project Structure

```
.
├── README.md                          # This file
├── Makefile                           # Build system
├── src/
│   ├── sequential_template.cpp       # Template for CPU implementation
│   ├── cuda_template.cu              # Template for GPU kernel
│   └── benchmark_template.cpp        # Template for benchmarking
└── include/
    ├── common.h                       # Common utilities (Timer, etc.)
    └── cuda_utils.h                   # CUDA helpers (error checking, GPU info)
```

## Getting Started

### Prerequisites

- **CUDA Toolkit** (10.0 or higher) - [Download](https://developer.nvidia.com/cuda-downloads)
- **C++ Compiler** with C++11 support (g++ or clang++)
- **NVIDIA GPU** with compute capability 3.0 or higher

### Quick Start

1. **Clone this repository**
   ```bash
   git clone <repository-url>
   cd parallel-architectures
   ```

2. **Test the templates**
   ```bash
   make templates
   ```

3. **Copy templates for your problem**
   ```bash
   cp src/sequential_template.cpp src/my_problem_sequential.cpp
   cp src/cuda_template.cu src/my_problem_cuda.cu
   cp src/benchmark_template.cpp src/my_benchmark.cpp
   ```

4. **Implement your algorithm**
   - Edit the sequential version in `my_problem_sequential.cpp`
   - Edit the CUDA version in `my_problem_cuda.cu`
   - Edit the benchmark in `my_benchmark.cpp`

5. **Add build rules to Makefile**
   ```makefile
   # Uncomment and modify TARGETS in Makefile
   TARGETS = my_problem_sequential my_problem_cuda my_benchmark
   
   # Add build rules
   my_problem_sequential: $(SRC_DIR)/my_problem_sequential.cpp
       $(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@
   
   my_problem_cuda: $(SRC_DIR)/my_problem_cuda.cu
       $(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
   
   my_benchmark: $(SRC_DIR)/my_benchmark.cpp
       $(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
   ```

6. **Build and run**
   ```bash
   make build
   ./my_problem_sequential
   ./my_problem_cuda
   ./my_benchmark
   ```

## Template Files

### sequential_template.cpp
Template for CPU implementation:
- Basic structure for sequential algorithms
- Includes timing utilities
- Memory management examples

### cuda_template.cu
Template for GPU implementation:
- CUDA kernel structure with proper indexing
- Memory allocation/transfer patterns
- GPU timing with CUDA events
- Error checking best practices

### benchmark_template.cpp
Template for performance comparison:
- Runs both CPU and GPU versions
- Measures execution time
- Calculates speedup
- Verifies correctness

## Included Utilities

### common.h
- **Timer class**: High-precision timing for benchmarking
- **BLOCK_SIZE**: Default CUDA block size (256 threads)
- Common includes and definitions

### cuda_utils.h
- **CUDA_CHECK macro**: Automatic error checking for CUDA calls
- **printDeviceInfo()**: Display GPU properties and capabilities
- Helper functions for CUDA development

## Example Problems to Implement

Here are some suggested problems for learning (in increasing difficulty):

1. **Vector Addition** - Add two arrays element-wise
   - Simplest parallel operation
   - Learn basic kernel structure
   - Understand thread indexing

2. **Matrix Addition** - Add two matrices
   - Introduction to 2D indexing
   - Learn about 2D grid/block configuration

3. **Vector Dot Product** - Compute dot product of two vectors
   - Learn reduction operations
   - Understand atomic operations or reduction patterns

4. **Matrix Multiplication** - Multiply two matrices
   - Learn shared memory usage
   - Understand tiling and memory coalescing
   - Optimize for performance

5. **Image Processing** - Apply filters to images
   - Work with 2D data
   - Learn boundary handling
   - Practical application

## Build System

### Makefile Targets

```bash
make all            # Show usage information
make templates      # Build template examples
make build          # Build your implementations (after adding rules)
make test-templates # Build and run template examples
make clean          # Remove build artifacts
make help           # Show detailed help
```

### Compiler Flags

- **CXXFLAGS**: `-std=c++11 -O3 -Wall -Wextra`
- **NVCCFLAGS**: `-std=c++11 -O3 -arch=sm_35`

Adjust `-arch=sm_XX` based on your GPU's compute capability.

## CUDA Programming Best Practices

This template encourages:

1. **Error Checking**: Always check CUDA API calls
2. **Memory Management**: Proper allocation and deallocation
3. **Timing**: Separate kernel time from memory transfer time
4. **Verification**: Always verify GPU results against CPU
5. **Documentation**: Comment your code clearly
6. **Optimization**: Start simple, then optimize

## Learning Resources

- [CUDA C Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
- [CUDA Best Practices Guide](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/)
- CUDA by Example (book)
- Professional CUDA C Programming (book)

## Common Issues and Solutions

### "nvcc: command not found"
- Install CUDA Toolkit
- Add CUDA to PATH: `export PATH=/usr/local/cuda/bin:$PATH`

### "No CUDA-capable device detected"
- Ensure you have an NVIDIA GPU
- Install proper drivers
- Check with: `nvidia-smi`

### "Compute capability mismatch"
- Adjust `-arch=sm_XX` in Makefile
- Find your GPU's capability: [CUDA GPUs](https://developer.nvidia.com/cuda-gpus)

## Project Ideas

Use this template to implement:
- **Scientific Computing**: Numerical simulations, linear algebra
- **Image Processing**: Filters, transformations, computer vision
- **Data Analysis**: Sorting, searching, statistical operations
- **Machine Learning**: Basic neural network operations
- **Physics Simulations**: N-body problems, fluid dynamics

## Contributing

This is an educational template. Feel free to:
- Add your own examples
- Improve documentation
- Share your implementations
- Report issues

## License

This template is provided for educational purposes.

---

**Happy CUDA Programming! 🚀**