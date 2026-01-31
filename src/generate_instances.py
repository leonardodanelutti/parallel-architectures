import argparse
from pathlib import Path
import random
import time
import clingo
import threading
from tqdm import tqdm


def cnf_to_asp(num_vars, clauses):
    asp_lines = [f"var(1..{num_vars})."]
    for i, (lit1, lit2) in enumerate(clauses, 1):
        l1 = f"pos({abs(lit1)})" if lit1 > 0 else f"neg({abs(lit1)})"
        l2 = f"pos({abs(lit2)})" if lit2 > 0 else f"neg({abs(lit2)})"
        asp_lines.append(f"clause({i}, {l1}, {l2}).")
    return '\n'.join(asp_lines)


def save_asp_file(asp_content, filename):
    with open(filename, 'w') as f:
        f.write(asp_content)


def run_clingo(asp_content, timeout=15):
    asp_program_path = Path(__file__).parent.parent / 'asp.lp'
    
    ctl = clingo.Control(arguments=["--parallel-mode=4"])
    ctl.load(str(asp_program_path))
    ctl.add("base", [], asp_content)
    ctl.ground([("base", [])])
    
    fixed_count = None
    
    def solve():
        nonlocal fixed_count
        with ctl.solve(yield_=True) as handle:
            for model in handle:
                fixed_count = sum(1 for atom in model.symbols(shown=True) if atom.name == "fixed")
                if model.optimality_proven:
                    break
    
    thread = threading.Thread(target=solve, daemon=True)
    thread.start()
    thread.join(timeout=timeout)
    
    timeout_reached = thread.is_alive()
                
    return fixed_count, timeout_reached


def generate_instance(num_vars, num_clauses, filename):
    assignment = [random.choice([True, False]) for _ in range(num_vars + 1)]
    clauses = []
    
    for _ in range(num_clauses):
        var1, var2 = random.randint(1, num_vars), random.randint(1, num_vars)
        
        lit1 = var1 if assignment[var1] else -var1
        lit2 = var2 if random.choice([True, False]) else -var2
        
        if random.choice([True, False]):
            lit1, lit2 = lit2, lit1
        
        clauses.append((lit1, lit2))
    
    asp_content = cnf_to_asp(num_vars, clauses)
    # asp_filename = filename.with_suffix('.lp')
    # save_asp_file(asp_content, asp_filename)
    
    fixed_count, timeout_reached = run_clingo(asp_content)

    with open(filename, 'w') as f:
        if timeout_reached:
            f.write(f"c fixed-timeout: {fixed_count}\n")
        elif fixed_count is not None:
            f.write(f"c fixed: {fixed_count}\n")
        else:
            f.write(f"c no solution\n")
        f.write(f"p cnf {num_vars} {num_clauses}\n")
        for lit1, lit2 in clauses:
            f.write(f"{lit1} {lit2} 0\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('num_vars_start', type=int, nargs='?', default=10)
    parser.add_argument('num_vars_end', type=int, nargs='?', default=10)
    parser.add_argument('vars_num', type=int, nargs='?', default=10)
    parser.add_argument('num_clauses_start', type=int, nargs='?', default=20)
    parser.add_argument('num_clauses_end', type=int, nargs='?', default=20)
    parser.add_argument('clauses_num', type=int, nargs='?', default=10)
    parser.add_argument('folder', nargs='?', default='./instances/')
    
    args = parser.parse_args()
    
    Path(args.folder).mkdir(mode=0o755, parents=True, exist_ok=True)
    
    total_instances = args.vars_num * args.clauses_num
    
    with tqdm(total=total_instances, desc="Generating instances") as pbar:
        for v in range(args.vars_num):
            num_vars = args.num_vars_start if args.vars_num == 1 else \
                       args.num_vars_start + v * (args.num_vars_end - args.num_vars_start) // (args.vars_num - 1)
            
            for c in range(args.clauses_num):
                num_clauses = args.num_clauses_start if args.clauses_num == 1 else \
                             args.num_clauses_start + c * (args.num_clauses_end - args.num_clauses_start) // (args.clauses_num - 1)
                
                output_file = Path(args.folder) / f"instance_{num_vars}v_{num_clauses}c.cnf"
                generate_instance(num_vars, num_clauses, output_file)
                pbar.update(1)
    
    print("Instance generation completed.")


if __name__ == "__main__":
    main()
