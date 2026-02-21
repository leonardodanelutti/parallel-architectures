#include <iostream>
#include <vector>
#include <string>
#include <sstream>

struct AppConfig {
    std::string filename;
    std::vector<HeuristicKind> heuristics;
    bool check_sodd = false;
    bool bench_enabled = false;
    std::string bench_path = "benchmarks.csv";
    bool success = true;
};

AppConfig parseCommandLine(int argc, char* argv[]) {
    AppConfig config;
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <filename> [heuristic list] [--check-sodd] [--bench] [--bench-file <path>]" << std::endl;
        std::cerr << "  heuristic list: e.g., 1,3 | all (default)" << std::endl;
        config.success = false;
        return config;
    }

    config.filename = argv[1];
    std::string heuristic_raw = "all";

    for (int i = 2; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--check-sodd") {
            config.check_sodd = true;
        } else if (arg == "--bench") {
            config.bench_enabled = true;
        } else if (arg == "--bench-file") {
            if (i + 1 < argc) {
                config.bench_enabled = true;
                config.bench_path = argv[++i];
            } else {
                std::cerr << "Error: --bench-file requires a path" << std::endl;
                config.success = false;
                return config;
            }
        } else if (arg.rfind("--bench-file=", 0) == 0) {
            config.bench_enabled = true;
            config.bench_path = arg.substr(13);
        } else {
            // Assume any other non-flag argument is the heuristic list
            heuristic_raw = arg;
        }
    }

    // Process the heuristic string into the vector
    if (heuristic_raw == "all") {
        for (int i = HEUR_1; i <= HEUR_4; ++i) 
            config.heuristics.push_back(static_cast<HeuristicKind>(i));
    } else {
        std::stringstream ss(heuristic_raw);
        std::string segment;
        while (std::getline(ss, segment, ',')) {
            try {
                int val = std::stoi(segment);
                if (val >= 1 && val <= 4) {
                    config.heuristics.push_back(static_cast<HeuristicKind>(val));
                }
            } catch (...) { /* Skip invalid numeric inputs */ }
        }
    }

    if (config.heuristics.empty()) {
        std::cerr << "Error: No valid heuristics (1-4) provided." << std::endl;
        config.success = false;
    }

    return config;
}