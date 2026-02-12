import argparse
import subprocess
from pathlib import Path
import sys


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run the parallel solver on all .cnf files in a folder with benchmarking."
    )
    parser.add_argument("folder", help="Folder containing .cnf files")
    parser.add_argument("output", help="Benchmark output CSV file")
    parser.add_argument("--check-sodd", action="store_true", default=False)
    return parser.parse_args()


def resolve_executable():
    exe = Path("./parallel")
    if not exe.exists():
        print("Error: ./parallel not found. Build the binary or adjust the script.")
        sys.exit(1)
    if not exe.is_file() or not exe.stat().st_mode & 0o111:
        print("Error: ./parallel is not executable.")
        sys.exit(1)
    return str(exe)


def run_instance(exe, cnf_path, output_path, check_sodd):
    cmd = [
        exe,
        str(cnf_path),
        "all",
        "--bench",
        "--bench-file",
        str(output_path),
    ]
    if check_sodd:
        cmd.append("--check-sodd")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"Error: command failed with exit code {result.returncode}")
        sys.exit(result.returncode)


def main():
    args = parse_args()
    exe = resolve_executable()

    folder = Path(args.folder)
    if not folder.exists() or not folder.is_dir():
        print(f"Error: folder not found: {folder}")
        sys.exit(1)

    cnf_files = sorted(folder.glob("*.cnf"))
    if not cnf_files:
        print(f"Error: no .cnf files found in {folder}")
        sys.exit(1)

    output_path = Path(args.output)
    for cnf_path in cnf_files:
        run_instance(exe, cnf_path, output_path, args.check_sodd)


if __name__ == "__main__":
    main()
