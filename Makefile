# Makefile for CUDA Vector Addition Educational Project

# Compiler settings
CXX = g++
NVCC = nvcc

# Compiler flags
CXXFLAGS = -std=c++11 -O3 -Wall -Wextra
NVCCFLAGS = -std=c++11 -O3 -arch=sm_35

# Directories
SRC_DIR = src
INC_DIR = include
BUILD_DIR = build

# Include path
INCLUDES = -I$(INC_DIR)

# Targets
TARGETS = vector_add_sequential vector_add_cuda benchmark

# Default target
all: directories $(TARGETS)

# Create build directory
directories:
	@mkdir -p $(BUILD_DIR)

# Sequential version (CPU only)
vector_add_sequential: $(SRC_DIR)/vector_add_sequential.cpp $(INC_DIR)/common.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@
	@echo "Built: $@"

# CUDA version (GPU)
vector_add_cuda: $(SRC_DIR)/vector_add_cuda.cu $(INC_DIR)/common.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
	@echo "Built: $@"

# Benchmark (both CPU and GPU)
benchmark: $(SRC_DIR)/benchmark.cpp $(INC_DIR)/common.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
	@echo "Built: $@"

# Run targets
run-sequential: vector_add_sequential
	@echo "Running sequential version..."
	@./vector_add_sequential

run-cuda: vector_add_cuda
	@echo "Running CUDA version..."
	@./vector_add_cuda

run-benchmark: benchmark
	@echo "Running full benchmark..."
	@./benchmark

# Test all implementations
test: all
	@echo "Testing sequential implementation..."
	@./vector_add_sequential > /dev/null && echo "✓ Sequential test passed" || echo "✗ Sequential test failed"
	@echo "Testing CUDA implementation..."
	@./vector_add_cuda > /dev/null && echo "✓ CUDA test passed" || echo "✗ CUDA test failed"
	@echo "Running comprehensive benchmark..."
	@./benchmark

# Clean build artifacts
clean:
	rm -f $(TARGETS)
	rm -rf $(BUILD_DIR)
	rm -f *.o
	@echo "Cleaned build artifacts"

# Help target
help:
	@echo "CUDA Vector Addition - Educational Project"
	@echo ""
	@echo "Available targets:"
	@echo "  all              - Build all executables (default)"
	@echo "  vector_add_sequential - Build CPU-only version"
	@echo "  vector_add_cuda  - Build GPU version"
	@echo "  benchmark        - Build comprehensive benchmark"
	@echo ""
	@echo "  run-sequential   - Build and run CPU version"
	@echo "  run-cuda         - Build and run GPU version"
	@echo "  run-benchmark    - Build and run full benchmark"
	@echo ""
	@echo "  test             - Build and test all implementations"
	@echo "  clean            - Remove all build artifacts"
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Requirements:"
	@echo "  - NVIDIA CUDA Toolkit (nvcc compiler)"
	@echo "  - C++ compiler with C++11 support (g++)"
	@echo "  - NVIDIA GPU with compute capability 3.5+"

.PHONY: all directories run-sequential run-cuda run-benchmark test clean help
