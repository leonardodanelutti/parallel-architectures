#include "../include/benchmark.h"

BenchmarkState g_bench;

void BenchmarkLogger::enable(const std::string& path, const std::string& filename, const std::string& heuristic) {
    enabled_ = true;
    out_path_ = path;
    filename_ = filename;
    heuristic_ = heuristic;
}

void BenchmarkLogger::setInstanceInfo(
    int num_vars,
    int num_clauses,
    int lower_bound,
    int upper_bound,
    bool bounds_present
) {
    if (!enabled_) return;
    num_vars_ = num_vars;
    num_clauses_ = num_clauses;
    lower_bound_ = lower_bound;
    upper_bound_ = upper_bound;
    bounds_present_ = bounds_present;
}

bool BenchmarkLogger::enabled() const { return enabled_; }

void BenchmarkLogger::record(const std::string& phase, double wall_ms, float gpu_ms, int num_assignments) {
    if (!enabled_) return;
    size_t free_bytes = 0;
    size_t total_bytes = 0;
    CUDA_CHECK(cudaMemGetInfo(&free_bytes, &total_bytes));
    rows_.push_back(BenchmarkRow{
        phase,
        wall_ms,
        gpu_ms,
        num_assignments,
        total_bytes - free_bytes,
        free_bytes,
        total_bytes
    });
}

void BenchmarkLogger::setLastAssignments(int num_assignments) {
    if (!enabled_ || rows_.empty()) return;
    rows_.back().num_assignments = num_assignments;
}

void BenchmarkLogger::flush() const {
    if (!enabled_) return;

    bool write_header = false;
    {
        std::ifstream in(out_path_);
        write_header = !in.good();
    }

    std::ofstream out(out_path_, std::ios::app);
    if (!out) {
        std::cerr << "Failed to open benchmark output: " << out_path_ << std::endl;
        return;
    }

    if (write_header) {
        out << "filename,heuristic,num_vars,num_clauses,lower_bound,upper_bound,bounds_present,"
               "phase,wall_ms,gpu_ms,used_bytes,free_bytes,total_bytes,num_assignments"
            << std::endl;
    }

    for (const auto& row : rows_) {
        out << filename_ << ','
            << heuristic_ << ','
            << num_vars_ << ','
            << num_clauses_ << ','
            << lower_bound_ << ','
            << upper_bound_ << ','
            << (bounds_present_ ? 1 : 0) << ','
            << row.phase << ','
            << row.wall_ms << ','
            << row.gpu_ms << ','
            << row.used_bytes << ','
            << row.free_bytes << ','
            << row.total_bytes << ','
            << row.num_assignments << std::endl;
    }
}

GpuTimer::GpuTimer() {
    CUDA_CHECK(cudaEventCreate(&start_));
    CUDA_CHECK(cudaEventCreate(&stop_));
}

GpuTimer::~GpuTimer() {
    cudaEventDestroy(start_);
    cudaEventDestroy(stop_);
}

void GpuTimer::start() { CUDA_CHECK(cudaEventRecord(start_)); }

float GpuTimer::stop() {
    CUDA_CHECK(cudaEventRecord(stop_));
    CUDA_CHECK(cudaEventSynchronize(stop_));
    float ms = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&ms, start_, stop_));
    return ms;
}

double nowMs() {
    auto now = std::chrono::high_resolution_clock::now();
    std::chrono::duration<double, std::milli> duration = now.time_since_epoch();
    return duration.count();
}

void initBenchmark(
    BenchmarkState& state,
    bool enabled,
    const std::string& path,
    const std::string& filename,
    const std::string& heuristic
) {
    state.enabled = enabled;
    if (enabled) {
        state.logger.enable(path, filename, heuristic);
    }
}

void benchStart(BenchmarkState& state, BenchMode mode) {
    if (!state.enabled) return;
    state.host_start_ms = nowMs();
    if (mode == BENCH_DEVICE) {
        state.gpu_timer.start();
    }
}

void benchEnd(BenchmarkState& state, const std::string& phase, BenchMode mode) {
    if (!state.enabled) return;
    const double wall_ms = nowMs() - state.host_start_ms;
    if (mode == BENCH_DEVICE) {
        const float gpu_ms = state.gpu_timer.stop();
        state.logger.record(phase, wall_ms, gpu_ms);
        return;
    }
    state.logger.record(phase, wall_ms, -1.0f);
}

void benchStartTotal(BenchmarkState& state) {
    if (!state.enabled) return;
    state.total_start_ms = nowMs();
}

void benchStopTotal(BenchmarkState& state) {
    if (!state.enabled) return;
    const double wall_ms = nowMs() - state.total_start_ms;
    state.logger.record("total", wall_ms, -1.0f);
}

void benchFlush(BenchmarkState& state) {
    if (!state.enabled) return;
    state.logger.flush();
}

void benchSetLastAssignments(BenchmarkState& state, int num_assignments) {
    if (!state.enabled) return;
    state.logger.setLastAssignments(num_assignments);
}

void benchSetInstanceInfo(
    BenchmarkState& state,
    int num_vars,
    int num_clauses,
    int lower_bound,
    int upper_bound,
    bool bounds_present
) {
    if (!state.enabled) return;
    state.logger.setInstanceInfo(num_vars, num_clauses, lower_bound, upper_bound, bounds_present);
}
