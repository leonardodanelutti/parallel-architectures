# Makefile for CUDA Educational Project
# Generic template for CUDA development with benchmarking

# Compiler settings
CXX = g++
NVCC = nvcc

# Compiler flags
CXXFLAGS = -std=c++11 -O3 -Wall -Wextra
NVCCFLAGS = -std=c++11 -O3 -arch=compute_80

# Directories
SRC_DIR = src
INC_DIR = include
BUILD_DIR = build

# Include path
INCLUDES = -I$(INC_DIR)

# Targets
TARGETS = sequential parallel benchmarks

# Default target
all: $(TARGETS)
	@echo "======================================"
	@echo "Build complete!"
	@echo "======================================"
	@echo "Available executables:"
	@echo "  ./sequential  - Sequential CPU implementation"
	@echo "  ./parallel    - CUDA GPU implementation"
	@echo "  ./benchmarks  - Performance benchmarks"
	@echo "======================================"

# Create build directory
directories:
	@mkdir -p $(BUILD_DIR)

# Sequential implementation
sequential: $(SRC_DIR)/sequential.cpp $(INC_DIR)/common.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@

# CUDA parallel implementation
parallel: $(SRC_DIR)/parallel.cu $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@

# Benchmarks
benchmarks: $(SRC_DIR)/benchmarks.cpp $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@

# Build all targets
build: directories $(TARGETS)

# Run targets
run-sequential: sequential
	@echo "Running sequential implementation..."
	@./sequential

run-parallel: parallel
	@echo "Running parallel implementation..."
	@./parallel

run-benchmarks: benchmarks
	@echo "Running benchmarks..."
	@./benchmarks

# Run all
run-all: run-sequential run-parallel run-benchmarks

# Clean build artifacts
clean:
	rm -f $(TARGETS)
	rm -rf $(BUILD_DIR)
	rm -f *.o
	@echo "Cleaned build artifacts"

# Help target
help:
	@echo "======================================"
	@echo "Parallel Architectures Project"
	@echo "======================================"
	@echo "Available targets:"
	@echo "  make               - Build all targets"
	@echo "  make sequential    - Build sequential implementation"
	@echo "  make parallel      - Build CUDA parallel implementation"
	@echo "  make benchmarks    - Build benchmark suite"
	@echo "  make build         - Build all targets"
	@echo "  make run-sequential - Run sequential version"
	@echo "  make run-parallel   - Run parallel version"
	@echo "  make run-benchmarks - Run benchmarks"
	@echo "  make run-all        - Run all implementations"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make help          - Show this help"
	@echo "======================================"
	@echo "CUDA Educational Project - Makefile"
	@echo "======================================"
	@echo ""
	@echo "This Makefile provides a template for building CUDA projects"
	@echo "with both sequential and parallel implementations."
	@echo ""
	@echo "Getting Started:"
	@echo "  1. Copy template files to create your implementation"
	@echo "  2. Edit the templates with your algorithm"
	@echo "  3. Add build rules to this Makefile"
	@echo "  4. Run 'make build' to compile"
	@echo ""
	@echo "Available targets:"
	@echo "  all              - Show usage information (default)"
	@echo "  templates        - Build template examples"
	@echo "  build            - Build your implementations"
	@echo "  test-templates   - Build and run templates"
	@echo ""
	@echo "  clean            - Remove all build artifacts"
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Template files:"
	@echo "  src/sequential_template.cpp  - CPU implementation template"
	@echo "  src/cuda_template.cu         - GPU kernel template"
	@echo "  src/benchmark_template.cpp   - Benchmarking template"
	@echo ""
	@echo "Include files:"
	@echo "  include/common.h       - Common utilities (Timer, etc.)"
	@echo "  include/cuda_utils.h   - CUDA helpers (error checking, etc.)"
	@echo ""
	@echo "Requirements:"
	@echo "  - NVIDIA CUDA Toolkit (nvcc compiler)"
	@echo "  - C++ compiler with C++11 support (g++)"
	@echo "  - NVIDIA GPU with compute capability 3.5+"
	@echo ""
	@echo "======================================"

.PHONY: all directories templates build run-sequential run-cuda run-benchmark test-templates clean help
