# Parallel Architectures - CUDA Project

This repository contains the final project for the Parallel Architectures course, focusing on CUDA programming. The goal is to implement and optimize parallel algorithms for solving a problem using CUDA.

## Project Overview

The project is divided into three main parts:
2. **CUDA Implementation**: A parallel version of the algorithm using CUDA to leverage GPU acceleration.
2. **Benchmarking**: A benchmarking suite to compare the performance of CUDA implementations.

## The Problem

Let P be an instance of 2-SAT, i.e. a set of clauses, each containing exactly two literals, and A the set of variables appearing in P. The goal is to find a subset of variables X ⊆ A of minimum cardinality, and an assignment of truth values to the variables in X, such that there is only one satisfying assignment for P.

The goal is to find a good heuristic to get a small set X.

### Example

Given the clauses:
- (¬x1 ∨ x2)
- (¬x2 ∨ x3)
- (¬x3 ∨ x1)

A possible solution is to select the variable set X = {x1, x2} and assign truth values x1 = true, x2 = false, which satisfies all clauses.

## Solution Approach

// TODO:

## Getting Started

### Prerequisites

- **CUDA Toolkit** (10.0 or higher) - [Download](https://developer.nvidia.com/cuda-downloads)
- **C++ Compiler** with C++11 support (g++ or clang++)
- **NVIDIA GPU** with compute capability 3.0 or higher

### Quick Start
```bash
   make
   ./parallel
```

## Build System

### Makefile Targets

```bash
make parallel   # Build CUDA implementation
make run-all    # Run parallel and benchmarks
make clean      # Remove build artifacts
make help       # Show detailed help
```

### Compiler Flags

- **CXXFLAGS**: `-std=c++11 -O3 -Wall -Wextra`
- **NVCCFLAGS**: `-std=c++11 -O3 -arch=sm_35`

Adjust `-arch=sm_XX` based on your GPU's compute capability.
