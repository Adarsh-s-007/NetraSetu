% District simulation: queue mechanics, conservation, the Simulink block
% code (executed by the emulator) against the MATLAB reference, KPIs.
P = netra.sim.defaults();
P.days = 14;
S = netra.sim.scenario(P);

%% Age-structured FIFO queue serves the oldest first and conserves patients
q = [5 0 3 2];                       % ages 1..4 (column 4 = oldest)
[q2, served, tot] = netra.sim.ageQueue(q, [1 0 0 0], 4);
assert(tot == 4 && isequal(served, [0 0 2 2]), 'served %s', mat2str(served));
assert(abs(sum(q) + 1 - tot - sum(q2)) < 1e-12);
assert(isequal(q2, [0 6 0 1]), 'remaining cohorts age by one step: %s', mat2str(q2));

%% Photography: arrivals are captured, wait, or go home at closing time
[w, c, b] = netra.sim.stepCapture([2; 0], [5; 1], [4; 3], [0; 1]);
assert(isequal(c, [4; 1]) && isequal(w, [3; 0]) && isequal(b, [0; 0]));
[w, c, b] = netra.sim.stepCapture([3; 0], [0; 0], [1; 0], [1; 0]);
assert(isequal(c, [1; 0]) && isequal(b, [2; 0]) && isequal(w, [0; 0]));

%% Every arriving patient is captured, sent home or still waiting
out = netra.sim.runReference(P, P.decision, S);
L = out.logs;
assert(sum(L.nArrived) > 1000, 'a two-week horizon must still have clinic days');
assert(abs(sum(L.nArrived) - sum(L.nCaptured) - sum(L.nBalked) - L.waiting(end)) < 1e-6);
assert(out.kpi.screened <= out.kpi.demand + 1e-9);

%% The Simulink block code reproduces the reference exactly (edge and cloud)
for mode = {'edge', 'cloud'}
    D = P.decision;
    D.aiMode = mode{1};
    ref = netra.sim.runReference(P, D, S);
    em = netra.sim.runSimulink(P, D, S, 'Engine', 'emulate', 'CrossCheck', false);
    C = netra.sim.crossCheck(ref, em);
    assert(C.pass && C.maxRelative == 0, '%s: largest difference %.3g in %s', mode{1}, ...
        C.maxRelative, C.worst);
end

%% The cross-check notices a model that drifts from the reference
ref = netra.sim.runReference(P, P.decision, S);
bad = ref;
bad.logs.casesG(100) = bad.logs.casesG(100) + 0.5;
C = netra.sim.crossCheck(ref, bad);
assert(~C.pass && strcmp(C.worst, 'casesG'));

%% Common random numbers: more reviewers never slow the result down
D = P.decision;
D.aiMode = 'cloud';
D.graders = 1;
a = netra.sim.runReference(P, D, S);
D.graders = 3;
b = netra.sim.runReference(P, D, S);
assert(b.kpi.turnaround.routineP95 <= a.kpi.turnaround.routineP95 + 1e-9);
assert(b.kpi.utilisation.graders < a.kpi.utilisation.graders);

%% Explainable review needs fewer reviewer hours than plain review
D = P.decision;
x = netra.sim.runReference(P, D, S);
D.reviewMode = 'plain';
y = netra.sim.runReference(P, D, S);
assert(x.kpi.utilisation.graders < y.kpi.utilisation.graders);

%% Binormal operating curve: higher sensitivity costs specificity
[se1, sp1] = netra.sim.operatingCurve(P, 0.90);
[se2, sp2] = netra.sim.operatingCurve(P, 0.96);
assert(se1 == 0.90 && se2 == 0.96 && sp2 < sp1 && sp1 < 1);

%% The Simulink model description is internally consistent
M = netra.sim.simulinkBlocks();
assert(numel(M.blocks) == 7 && any(strcmp({M.logs.signal}, 'H')));
