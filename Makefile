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

# Include path
INCLUDES = -I$(INC_DIR)

all: fix

# Default target
fix: $(SRC_DIR)/main.cu $(SRC_DIR)/benchmark.cu $(INC_DIR)/common.h $(INC_DIR)/cuda_utils.h $(INC_DIR)/benchmark.h
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) $(SRC_DIR)/main.cu $(SRC_DIR)/benchmark.cu -o $@

# Run targets

run: fix
	@./fix

# Clean build artifacts
clean:
	rm -f fix
	rm -f *.o
	@echo "Cleaned build artifacts"

.PHONY: all run clean
