% --- Input Representation ---
% Define vars: var(a). var(b). var(c).
% Define clauses: clause(id, lit1, lit2). 
% Literals are pos(a) or neg(a).

% Example Input
%var(1..6).
%clause(1, neg(1), pos(4)).
%clause(2, neg(2), pos(4)). 
%clause(3, neg(2), pos(5)). 
%clause(4, neg(3), pos(5)). 
%clause(5, neg(3), pos(6)).

% Import instance data
% #include "./instance_1000v_1000c.lp".

% Define duals for propagation: dual of pos(1) is neg(1)
dual(pos(A), neg(A)) :- var(A).
dual(neg(A), pos(A)) :- var(A).

% 1. Generate the Subset X
% Choose which vars are fixed, then choose a value only for fixed vars.
{ fix(A) } :- var(A).
1 { fixed(A, true); fixed(A, false) } 1 :- fix(A).

% Optimization: Find the minimum number of fixed variables.
#minimize { 1,A : fix(A) }.

% 2. Unit propagation guarantees to cover all variables.

% Base case: If we fix a variable, it is satisfied.
satisfied(pos(A)) :- fixed(A, true).
satisfied(neg(A)) :- fixed(A, false).

% Propagation rules:
% If the dual of L1 is satisfied, then L2 must be satisfied.
% If the dual of L2 is satisfied, then L1 must be satisfied.
satisfied(L2) :- clause(_, L1, L2), dual(L1, D1), satisfied(D1).
satisfied(L1) :- clause(_, L1, L2), dual(L2, D2), satisfied(D2).

% A variable cannot be satisfied to both true and false.
:- satisfied(pos(A)), satisfied(neg(A)).

% Every variable must be satisfied to at least one value.
:- var(A), not satisfied(pos(A)), not satisfied(neg(A)).

% --- Output ---
#show fixed/2.