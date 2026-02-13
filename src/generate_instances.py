import argparse
from pathlib import Path
import random
import clingo
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


def run_clingo(num_vars, clauses, timeout=10):
    asp_content = cnf_to_asp(num_vars, clauses)
    # asp_filename = filename.with_suffix('.lp')
    # save_asp_file(asp_content, asp_filename)

    asp_program_path = Path(__file__).parent.parent / 'asp.lp'
    
    ctl = clingo.Control(arguments=["--parallel-mode=4"])
    ctl.load(str(asp_program_path))
    ctl.add("base", [], asp_content)
    ctl.ground([("base", [])])

    unsat = None
    with ctl.solve(async_=True) as handle:
        handle.wait(timeout)
        handle.cancel()
        unsat = handle.get().unsatisfiable
    lower_bound = ctl.statistics["summary"]["lower"][0]
    upper_bound = ctl.statistics["summary"]["costs"][0]
    # print(ctl.statistics["summary"]["times"]["total"])
                
    return lower_bound, upper_bound, unsat


def generate_instance(num_vars, num_clauses, filename, run_solver=True, solver_timeout=10):
    assignment = [random.choice([True, False]) for _ in range(num_vars + 1)]
    clauses = []
    
    for _ in range(num_clauses):
        var1, var2 = random.randint(1, num_vars), random.randint(1, num_vars)
        
        lit1 = var1 if assignment[var1] else -var1
        lit2 = var2 if random.choice([True, False]) else -var2

        # remove self-loops in the implication graph
        if lit1 == -lit2:
            lit2 = -lit2

        # TODO: remove duplicate clauses

        if random.choice([True, False]):
            lit1, lit2 = lit2, lit1
        
        clauses.append((lit1, lit2))
    
    if run_solver:
        lower_bound, upper_bound, unsat = run_clingo(num_vars, clauses, timeout=solver_timeout)
    else:
        lower_bound = upper_bound = None
        unsat = None

    with open(filename, 'w') as f:
        if unsat is None:
            f.write(f"c NF\n")
        elif unsat:
            f.write(f"c UNSAT\n")
            print(f"Instance {filename} is UNSAT. Skipping.")
            exit(1)
        else:
            f.write(f"c bounds {int(lower_bound)} {int(upper_bound)}\n")
        f.write(f"p cnf {num_vars} {num_clauses}\n")
        for lit1, lit2 in clauses:
            f.write(f"{lit1} {lit2} 0\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('num_vars_start', type=int, nargs='?', default=10)
    parser.add_argument('num_vars_end', type=int, nargs='?', default=10)
    parser.add_argument('vars_num', type=int, nargs='?', default=10)
    parser.add_argument('ratio_start', type=float, nargs='?', default=2.0)
    parser.add_argument('ratio_end', type=float, nargs='?', default=2.0)
    parser.add_argument('ratios_num', type=int, nargs='?', default=10)
    parser.add_argument('folder', nargs='?', default='./instances/')
    parser.add_argument('--clingo-timeout', type=float, default=None,
                        help='Run clingo with a timeout in seconds; omit to skip clingo.')
    
    args = parser.parse_args()
    
    Path(args.folder).mkdir(mode=0o755, parents=True, exist_ok=True)
    
    total_instances = args.vars_num * args.ratios_num
    
    with tqdm(total=total_instances, desc="Generating instances") as pbar:
        for v in range(args.vars_num):
            num_vars = args.num_vars_start if args.vars_num == 1 else \
                       args.num_vars_start + v * (args.num_vars_end - args.num_vars_start) // (args.vars_num - 1)
            
            for r in range(args.ratios_num):
                ratio = args.ratio_start if args.ratios_num == 1 else \
                        args.ratio_start + r * (args.ratio_end - args.ratio_start) / (args.ratios_num - 1)

                num_clauses = int(round(ratio * num_vars))
                ratio_label = f"{ratio:.2f}".rstrip('0').rstrip('.')
                output_file = Path(args.folder) / f"instance_{num_vars}v{v}_{ratio_label}r{r}.cnf"
                generate_instance(
                    num_vars,
                    num_clauses,
                    output_file,
                    run_solver=args.clingo_timeout is not None,
                    solver_timeout=args.clingo_timeout or 10,
                )
                pbar.update(1)
    
    print("Instance generation completed.")


if __name__ == "__main__":
    # python3 src/generate_instances.py 100 1000 20 0.5 3.5 30 ./instances_grid/ --clingo-timeout 10
    main()