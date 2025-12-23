# Makefile for CUDA Educational Project
# Generic template for CUDA development with benchmarking

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

# Template targets (for reference)
TEMPLATES = sequential_template cuda_template benchmark_template

# Your actual implementation targets
# TODO: Add your own targets here
# TARGETS = my_sequential my_cuda my_benchmark

# Default target
all: directories
	@echo "======================================"
	@echo "CUDA Project Template"
	@echo "======================================"
	@echo ""
	@echo "This is a template project structure."
	@echo "To use this template:"
	@echo ""
	@echo "1. Copy the template files:"
	@echo "   cp src/sequential_template.cpp src/my_problem.cpp"
	@echo "   cp src/cuda_template.cu src/my_problem.cu"
	@echo "   cp src/benchmark_template.cpp src/my_benchmark.cpp"
	@echo ""
	@echo "2. Implement your algorithm in the copied files"
	@echo ""
	@echo "3. Add build rules to this Makefile:"
	@echo "   TARGETS = my_problem_seq my_problem_cuda my_benchmark"
	@echo ""
	@echo "4. Build with: make build"
	@echo ""
	@echo "Available commands:"
	@echo "  make templates  - Build template examples"
	@echo "  make build      - Build your implementations"
	@echo "  make clean      - Remove build artifacts"
	@echo "  make help       - Show detailed help"
	@echo "======================================"

# Create build directory
directories:
	@mkdir -p $(BUILD_DIR)

# Build template examples
templates: directories $(TEMPLATES)

# Template builds (for reference/testing)
sequential_template: $(SRC_DIR)/sequential_template.cpp $(INC_DIR)/common.h
	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@
	@echo "Built template: $@"

cuda_template: $(SRC_DIR)/cuda_template.cu $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
	@echo "Built template: $@"

benchmark_template: $(SRC_DIR)/benchmark_template.cpp $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
	@echo "Built template: $@"

# TODO: Add your own build rules here
# Example:
# my_sequential: $(SRC_DIR)/my_problem.cpp $(INC_DIR)/common.h
# 	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@
#
# my_cuda: $(SRC_DIR)/my_problem.cu $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
# 	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@
#
# my_benchmark: $(SRC_DIR)/my_benchmark.cpp $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h
# 	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $< -o $@

# Build your actual implementations
build: directories
	@echo "TODO: Implement your build rules in the Makefile"
	@echo "Add your source files and uncomment the TARGETS variable"
	# make $(TARGETS)

# Run targets (examples - modify for your implementations)
run-sequential:
	@echo "Build your sequential implementation first"

run-cuda:
	@echo "Build your CUDA implementation first"

run-benchmark:
	@echo "Build your benchmark first"

# Test templates
test-templates: templates
	@echo "Testing template builds..."
	@./sequential_template
	@echo ""
	@./cuda_template
	@echo ""
	@./benchmark_template

# Clean build artifacts
clean:
	rm -f $(TEMPLATES)
	rm -rf $(BUILD_DIR)
	rm -f *.o
	@echo "Cleaned build artifacts"

# Help target
help:
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
