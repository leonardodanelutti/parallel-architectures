% Number of variables in A
int: n = 5; 
set of int: VARS = 1..n;

% Decisions: 0 = Unassigned, 1 = False, 2 = True
array[VARS] of var 0..2: x;

% Helper to check if a literal is satisfied
% For a positive literal (a): x[a] == 2
% For a negative literal (not a): x[a] == 1

% Example Clauses: (a1 \/ a2) /\ (not a2 \/ a3)
constraint (x[1] == 2 \/ x[2] == 2);
constraint (x[2] == 1 \/ x[3] == 2);
% ... add all clauses from P here

% Objective: Minimize the number of variables in subset X
% (where x[i] is not 0)
solve minimize sum(i in VARS)(bool2int(x[i] != 0));

output ["Variables in X: "] ++ 
       [show(i) ++ "=" ++ (if fix(x[i])==2 then "T" else "F" endif) ++ " " 
        | i in VARS where fix(x[i]) != 0];