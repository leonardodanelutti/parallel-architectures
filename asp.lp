% Define your variables
variable(1..5).

% Constraints: Represent clauses as "It cannot be that both literals are absent"
% Example Clause: (v1 OR not v2)
:- not val(1,t), not val(2,f).
% Example Clause: (v2 OR v3)
:- not val(2,t), not val(3,t).
% Example Clause: (not v1 OR not v4)
:- not val(1,f), not val(4,f).

% 2. Choice: For each variable V, it is either True, False, or neither.
% { val(V,t); val(V,f) } <= 1 means we pick at most one value.
{ val(V,t); val(V,f) } <= 1 :- variable(V).

% 4. Optimization: Minimize the count of variables assigned a value
#minimize { 1,V : val(V,_) }.

% 5. Output
#show val/2.