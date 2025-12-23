#ifndef COMMON_H
#define COMMON_H

#include <iostream>
#include <chrono>
#include <cstdlib>
#include <cmath>

// Default problem sizes for benchmarking
#define SMALL_SIZE   (1 << 20)  // 1M elements
#define MEDIUM_SIZE  (1 << 24)  // 16M elements
#define LARGE_SIZE   (1 << 26)  // 64M elements

// CUDA block size (threads per block)
#define BLOCK_SIZE 256

/**
 * Initialize a vector with random values
 */
inline void initializeVector(float* vec, int size) {
    for (int i = 0; i < size; i++) {
        vec[i] = static_cast<float>(rand()) / RAND_MAX;
    }
}

/**
 * Verify that two vectors are equal (within tolerance)
 */
inline bool verifyResult(const float* a, const float* b, int size, float tolerance = 1e-5f) {
    for (int i = 0; i < size; i++) {
        if (fabs(a[i] - b[i]) > tolerance) {
            std::cerr << "Mismatch at index " << i << ": " 
                      << a[i] << " != " << b[i] << std::endl;
            return false;
        }
    }
    return true;
}

/**
 * Timer class for benchmarking
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
