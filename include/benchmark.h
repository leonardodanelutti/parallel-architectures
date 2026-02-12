#ifndef BENCHMARK_H
#define BENCHMARK_H

#include "common.h"
#include "cuda_utils.h"

#include <string>

struct BenchmarkRow {
    std::string phase;
    double wall_ms;
    float gpu_ms;
    size_t used_bytes;
    size_t free_bytes;
    size_t total_bytes;
};

class BenchmarkLogger {
public:
    void enable(const std::string& path, const std::string& filename, const std::string& heuristic);
    void setInstanceInfo(int num_vars, int num_clauses, int lower_bound, int upper_bound, bool bounds_present);
    bool enabled() const;
    void record(const std::string& phase, double wall_ms, float gpu_ms);
    void flush() const;

private:
    bool enabled_ = false;
    std::string out_path_;
    std::string filename_;
    std::string heuristic_;
    int num_vars_ = -1;
    int num_clauses_ = -1;
    int lower_bound_ = -1;
    int upper_bound_ = -1;
    bool bounds_present_ = false;
    std::vector<BenchmarkRow> rows_;
};

class GpuTimer {
public:
    GpuTimer();
    ~GpuTimer();
    void start();
    float stop();

private:
    cudaEvent_t start_{};
    cudaEvent_t stop_{};
};

double nowMs();

enum BenchMode {
    BENCH_HOST,
    BENCH_DEVICE
};

struct BenchmarkState {
    BenchmarkLogger logger;
    GpuTimer gpu_timer;
    double host_start_ms = 0.0;
    double total_start_ms = 0.0;
    bool enabled = false;
};

void initBenchmark(
    BenchmarkState& state,
    bool enabled,
    const std::string& path,
    const std::string& filename,
    const std::string& heuristic
);
void benchStart(BenchmarkState& state, BenchMode mode);
void benchEnd(BenchmarkState& state, const std::string& phase, BenchMode mode);
void benchStartTotal(BenchmarkState& state);
void benchStopTotal(BenchmarkState& state);
void benchFlush(BenchmarkState& state);
void benchSetInstanceInfo(
    BenchmarkState& state,
    int num_vars,
    int num_clauses,
    int lower_bound,
    int upper_bound,
    bool bounds_present
);

extern BenchmarkState g_bench;

#endif // BENCHMARK_H
