# Parallel Architectures - CUDA Project

This repository contains the final project for the Parallel Architectures course, focusing on CUDA programming. The goal is to implement and optimize parallel algorithms for solving a problem using CUDA.

## Project Overview

The project consists of implementing a CUDA-based solution to a specific problem, which will be defined in the next section. The implementation will be benchmarked and a report is written to analyze the results and discuss the performance of the solution.

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

## Build System

```bash
make parallel   # Build CUDA implementation
make run        # Run the solver
make clean      # Remove build artifacts
```

## Usage

After building, you will have an executable called `fix`, which can be used to solve 2-SAT instances and find an approximate fix-set.

### Running the solver

```bash
./fix <instance_path.cnf> [heuristic list] [--check-sodd] [--bench] [--bench-file <path>]
```
- `<instance_path.cnf>`: Path to the file containing the 2-SAT instance in CNF format.
- `[heuristic list]`: Optional list of heuristics to apply, e.g. `--heuristics 1,3` to apply heuristics 1 and 3. If not specified, all available heuristics will be applied.
- `--check-sodd`: Option to check if the instance is satisfiable.
- `--bench`: Option to enable performance benchmarking.
- `--bench-file <path>`: Specifies an output file for benchmark results. If not specified, results are saved to `benchmarks.csv`.

### Python Scripts

Two Python scripts are provided for generating 2-SAT instances and running benchmarks automatically. These scripts are located in the `scripts/` folder.

#### Generate 2-SAT Instances

```bash
python scripts/generate_instances.py <num_var_start> <num_var_end> <num_var> <ratio_start> <ratio_end> <num_ratio> <output_dir> [--clingo-timeout <seconds>]
```
- `<num_var_start>`: Minimum number of variables for generated instances.
- `<num_var_end>`: Maximum number of variables for generated instances.
- `<num_var>`: Number of instances (with respect to variable count) to generate.
- `<ratio_start>`: Minimum clause-to-variable ratio for generated instances.
- `<ratio_end>`: Maximum clause-to-variable ratio for generated instances.
- `<num_ratio>`: Number of instances (with respect to clause/variable ratio) to generate.
- `<output_dir>`: Output directory for generated instances.
- `--clingo-timeout <seconds>`: Timeout in seconds for solving the instance with Clingo. If not specified, Clingo is not run.

You can also change the SEED and the method for generating the number of instances inside the file.

#### Run Benchmarks on Multiple Instances

```bash
python scripts/run_benchmark.py <instances_dir> <heuristic list> <out_file> [--check-sodd]
```
- `<instances_dir>`: Directory containing the instances to test.
- `<heuristic list>`: List of heuristics to apply, e.g. `--heuristics 1,3` to apply heuristics 1 and 3.
- `<out_file>`: Output file for benchmark results, e.g. `benchmark_results.csv`.
- `--check-sodd`: Option to check if instances are satisfiable before running the benchmark.

## Compiler Flags

- **CXXFLAGS**: `-std=c++17 -O3 -Wall -Wextra`
- **NVCCFLAGS**: `-std=c++17 -O3 -arch=sm_35 --extended-lambda`

Adjust `-arch=sm_XX` based on your GPU's compute capability.
