# GPU heuristics for 2-SAT fix-set minimization

A CUDA solver that, given a satisfiable 2-SAT formula, looks for a **small set of variables (a
"fix-set") whose assignment leaves exactly one satisfying assignment**. Finding a minimum fix-set is
hard, so the project designs greedy heuristics, runs the whole graph pipeline on the GPU, and
measures both solution quality and scalability.

Final project for the *Programming on Parallel Architectures* course, M.Sc. in Computer Science,
University of Udine.

## Results at a glance

- **Scales to 10⁶ variables.** Reachability queries are split into memory-bounded chunks, so instances
  larger than GPU memory still run.
- **Near-linear runtime.** Log–log slopes of runtime against instance size are about 1.06–1.14 while
  one chunk fits in memory, rising to 1.7–1.8 once queries are chunked (still sub-quadratic).
- **Close to optimal.** Results were compared with exact optima from the ASP solver Clingo on 410
  instances (500 variables, clause/variable ratio 0.5–4.5). The best heuristic stays within **1.25×** of the
  optimum on average and approaches 1× on denser instances.
- **Quality versus speed.** The most accurate heuristic is about 100× slower than the others,
  which is measured and discussed in the report.

## How it works

A 2-SAT formula becomes an **implication graph** with two nodes per variable. The pipeline runs on
the GPU:

1. **Strongly connected components** of the implication graph, then condensation to a DAG.
2. **Topological levels** of the condensed DAG.
3. **Backbone detection.** Reachability is propagated in topological order. A literal that reaches its own
   complement is forced, so its variable is removed from the search.
4. **Weakly connected components.** The remaining graph splits into independent subproblems.
5. **Greedy search.** In each round a heuristic picks one literal per pair of complementary components.
   The literal is added to the fix-set, and its consequences are propagated forwards (everything it implies) and
   backwards (everything that implies its complement).

Heuristics:

| # | Picks the literal with… | Notes |
|---|---|---|
| 1 | source status in the remaining DAG | fastest, least accurate |
| 2 | highest out-degree towards unassigned nodes | fastest overall |
| 3 | largest reachable set (computed once, then masked) | good speed/quality trade-off |
| 4 | largest reachable set, recomputed each round | most accurate, ~100× slower |

## Build

Requires the CUDA Toolkit, a C++17 compiler and an NVIDIA GPU. Set `-arch=sm_XX` in the `Makefile`
to match your GPU (default `sm_75`).

```bash
make        # builds ./fix
make clean
```

## Usage

```bash
./fix <instance.cnf> [--heuristics 1,3] [--check-sodd] [--bench] [--bench-file <path>]
```

- `<instance.cnf>`: 2-SAT instance in CNF format.
- `--heuristics`: comma-separated list of heuristics to run (default: all).
- `--check-sodd`: check whether the instance is satisfiable first.
- `--bench`, `--bench-file`: record timings (default output `benchmarks.csv`).

### Reproducing the experiments

```bash
# Generate random instances (optionally solved exactly with Clingo for comparison)
python scripts/generate_instances.py <n_start> <n_end> <n_count> <ratio_start> <ratio_end> <ratio_count> <out_dir> [--clingo-timeout <s>]

# Run a heuristic sweep over a directory of instances
python scripts/run_benchmark.py <instances_dir> <heuristic_list> <out.csv> [--check-sodd]
```

`asp.lp` contains the exact ASP encoding used with Clingo. The full write-up, with algorithms,
figures and analysis, is in [`report.pdf`](report.pdf) (in Italian).

## References

- G. Alabandi, W. Sands, G. Biros, M. Burtscher. *A GPU Algorithm for Detecting Strongly Connected Components.* SC '23.
- J. Soman, K. Kishore, P. J. Narayanan. *A fast GPU algorithm for graph connectivity.* IPDPSW 2010.
