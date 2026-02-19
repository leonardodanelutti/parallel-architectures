# Makefile for CUDA Educational Project
# Generic template for CUDA development with benchmarking

# Compiler settings
CXX = g++
NVCC = nvcc

# Compiler flags
CXXFLAGS = -std=c++17 -O3 -Wall -Wextra
NVCCFLAGS = -std=c++17 -O3 -arch=sm_75 --extended-lambda

# Directories
SRC_DIR = src
INC_DIR = include
BUILD_DIR = build

# Include path
INCLUDES = -I$(INC_DIR)

# Targets
TARGETS = parallel

# Default target
all: $(TARGETS)
	@echo "======================================"
	@echo "Build complete!"
	@echo "======================================"
	@echo "Available executables:"
	@echo "  ./parallel    - CUDA GPU implementation"
	@echo "======================================"

# Create build directory
directories:
	@mkdir -p $(BUILD_DIR)

	$(CXX) $(CXXFLAGS) $(INCLUDES) $< -o $@

# CUDA parallel implementation
parallel: $(SRC_DIR)/parallel.cu $(SRC_DIR)/benchmark.cu $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h $(INC_DIR)/benchmark.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $(SRC_DIR)/parallel.cu $(SRC_DIR)/benchmark.cu -o $@

build: directories $(TARGETS)

# Run targets

run-parallel: parallel
	@echo "Running parallel implementation..."
	@./parallel

# Run all
run-all: run-parallel

# Clean build artifacts
clean:
	rm -f $(TARGETS)
	rm -rf $(BUILD_DIR)
	rm -f *.o
	@echo "Cleaned build artifacts"

# Help target
	@echo "======================================"
	@echo "Parallel Architectures Project"
	@echo "======================================"
	@echo "Available targets:"
	@echo "  make               - Build all targets"
	@echo "  make parallel      - Build CUDA parallel implementation"
	@echo "  make build         - Build all targets"
	@echo "  make run-parallel   - Run parallel version"
	@echo "  make run-all        - Run all implementations"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make help          - Show this help"
	@echo "======================================"
	@echo "CUDA Educational Project - Makefile"
	@echo "======================================"
	@echo ""
	@echo "Benchmarking is now run via Python:"
	@echo "  python src/run_benchmarks.py <folder> <output.csv>"
	@echo ""
	@echo "This Makefile provides a template for building CUDA projects"
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
	@echo "  src/cuda_template.cu         - GPU kernel template"
	@echo ""
	@echo "Include files:"
	@echo "  include/common.h       - Common utilities (Timer, etc.)"
	@echo "  include/cuda_utils.h   - CUDA helpers (error checking, etc.)"
	@echo ""
	@echo "Requirements:"
	@echo "  - NVIDIA CUDA Toolkit (nvcc compiler)"
	@echo "  - C++ compiler with C++17 support (g++)"
	@echo "  - NVIDIA GPU with compute capability 3.5+"
	@echo ""
	@echo "======================================"

.PHONY: all directories templates build run-cuda test-templates clean help
