#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <chrono>
#include <cstdlib>
#include <cmath>

/**
 * Common utilities for CUDA educational projects
 * Include this header in both .cpp and .cu files
 */

// Default CUDA block size (threads per block)
// Adjust based on your problem and GPU architecture
#define BLOCK_SIZE 256

/**
 * Timer class for performance benchmarking
 * Usage:
 *   Timer timer;
 *   timer.start();
 *   // ... code to benchmark ...
 *   double elapsed_ms = timer.stop();
 */
class Timer {
private:
    std::chrono::high_resolution_clock::time_point start_time;
    
public:
    void start() {
        start_time = std::chrono::high_resolution_clock::now();
    }
    
    double stop() {
        auto end_time = std::chrono::high_resolution_clock::now();
        std::chrono::duration<double, std::milli> duration = end_time - start_time;
        return duration.count();
    }
};

#endif // COMMON_H
