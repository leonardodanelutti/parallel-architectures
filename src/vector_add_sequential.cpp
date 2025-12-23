#include "../include/common.h"

/**
 * Sequential vector addition on CPU
 * C[i] = A[i] + B[i] for all i
 */
void vectorAddSequential(const float* a, const float* b, float* c, int size) {
    for (int i = 0; i < size; i++) {
        c[i] = a[i] + b[i];
    }
}

int main() {
    // Problem size
    const int N = MEDIUM_SIZE;
    const size_t bytes = N * sizeof(float);
    
    std::cout << "=== Sequential Vector Addition ===" << std::endl;
    std::cout << "Vector size: " << N << " elements (" 
              << bytes / (1024.0 * 1024.0) << " MB)" << std::endl;
    
    // Allocate memory on host
    float* h_a = new float[N];
    float* h_b = new float[N];
    float* h_c = new float[N];
    
    // Initialize vectors with random values
    std::cout << "Initializing vectors..." << std::endl;
    srand(42); // Fixed seed for reproducibility
    initializeVector(h_a, N);
    initializeVector(h_b, N);
    
    // Perform vector addition and measure time
    Timer timer;
    std::cout << "Computing vector addition..." << std::endl;
    timer.start();
    vectorAddSequential(h_a, h_b, h_c, N);
    double elapsed = timer.stop();
    
    std::cout << "\n--- Results ---" << std::endl;
    std::cout << "Execution time: " << elapsed << " ms" << std::endl;
    
    // Calculate throughput
    double throughput = (3.0 * bytes / (1024.0 * 1024.0 * 1024.0)) / (elapsed / 1000.0);
    std::cout << "Throughput: " << throughput << " GB/s" << std::endl;
    
    // Verify a few results
    std::cout << "\nSample results:" << std::endl;
    for (int i = 0; i < 5; i++) {
        std::cout << h_a[i] << " + " << h_b[i] << " = " << h_c[i] << std::endl;
    }
    
    // Cleanup
    delete[] h_a;
    delete[] h_b;
    delete[] h_c;
    
    std::cout << "\nSequential execution completed successfully!" << std::endl;
    
    return 0;
}
