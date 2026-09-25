function R = optimize(P, varargin)
%OPTIMIZE Cheapest district plan that meets coverage, turnaround and safety targets.
%
%   R = netra.sim.optimize(P)
%   R = netra.sim.optimize(P, 'Method', 'bayesopt', 'Evaluations', 60)
%
%   Decision variables (P.decision holds a starting plan):
%     phcEquipped  18..36   PHCs with camera + trained technician
%     vans          0..4    mobile screening units
%     linkTier      0..4    0 today's mix; k = upgrade every PHC to >= tier k
%     aiMode      edge | cloud
%     graders       1..4    optometrist graders at the reading hub
%     ophthHours    1..4    ophthalmologist tele-reading hours per weekday
%     sensitivity  0.90 0.92 0.94 0.96   AI auto-clear operating point
%   Objective: annual cost (INR crore). Constraints (P.target): screens per
%   year, routine and urgent turnaround (P95), grader and ophthalmologist
%   utilisation, programme sensitivity.
%
%   Methods: 'bayesopt' (Statistics and Machine Learning Toolbox; coupled
%   constraints, deterministic objective thanks to common random numbers)
%   or 'search' (toolbox-free, used under Octave): coverage plans that meet
%   the screening target are ranked analytically by fixed cost, then a
%   simulation-based pattern search tunes the operational variables for the
%   three cheapest. 'auto'
%   picks bayesopt when available.
%
%   R fields: best (decision + kpi), evaluations (struct array), pareto
%   (non-dominated plans by cost and patients reaching treatment),
%   scenario, method.

o = netra.util.opts(struct('Method', 'auto', 'Evaluations', 40, 'Seed', 1, ...
    'Verbose', true, 'Scenario', [], 'Days', P.days), varargin{:});
P.days = o.Days;
S = o.Scenario;
if isempty(S)
    S = netra.sim.scenario(P);
end
space = struct( ...
    'phcEquipped', {{'int', [18 36]}}, ...
    'vans', {{'int', [0 4]}}, ...
    'linkTier', {{'int', [0 4]}}, ...
    'aiMode', {{'cat', {'edge', 'cloud'}}}, ...
    'graders', {{'int', [1 4]}}, ...
    'ophthHours', {{'int', [1 4]}}, ...
    'sensitivity', {{'cat', {0.90, 0.92, 0.94, 0.96}}});
method = o.Method;
if strcmpi(method, 'auto')
    if netra.util.has('bayesopt')
        method = 'bayesopt';
    else
        method = 'search';
    end
end
evals = struct('decision', {}, 'kpi', {}, 'cost', {}, 'feasible', {}, 'violation', {});

    function [f, g, e] = evaluate(D)
        D.reviewMode = P.decision.reviewMode;
        out = netra.sim.runReference(P, D, S);
        K = out.kpi;
        c = normalisedConstraints(K, P);
        f = K.cost.total / 1e7;
        g = -c;                                % bayesopt: <= 0 is feasible
        e = struct('decision', D, 'kpi', K, 'cost', f, 'feasible', all(c >= 0), ...
            'violation', sum(max(-c, 0)));
        evals(end + 1) = e;
        if o.Verbose
            fprintf('  %3d  %-5s phc %2d vans %d tier %d gr %d oh %d se %.2f  ->  Rs %.2f cr  %s\n', ...
                numel(evals), D.aiMode, D.phcEquipped, D.vans, D.linkTier, D.graders, ...
                D.ophthHours, D.sensitivity, f, ternary(e.feasible, 'feasible', ...
                sprintf('violation %.2f', e.violation)));
        end
    end

switch lower(method)
    case 'bayesopt'
        vars = [optimizableVariable('phcEquipped', space.phcEquipped{2}, 'Type', 'integer'), ...
            optimizableVariable('vans', space.vans{2}, 'Type', 'integer'), ...
            optimizableVariable('linkTier', space.linkTier{2}, 'Type', 'integer'), ...
            optimizableVariable('aiMode', space.aiMode{2}, 'Type', 'categorical'), ...
            optimizableVariable('graders', space.graders{2}, 'Type', 'integer'), ...
            optimizableVariable('ophthHours', space.ophthHours{2}, 'Type', 'integer'), ...
            optimizableVariable('sensIdx', [1 4], 'Type', 'integer')];
        sens = cell2mat(space.sensitivity{2});
        fun = @(x) boFun(x);
        bayesopt(fun, vars, 'MaxObjectiveEvaluations', o.Evaluations, ...
            'NumCoupledConstraints', 6, 'IsObjectiveDeterministic', true, ...
            'AcquisitionFunctionName', 'expected-improvement-plus', ...
            'Verbose', 0, 'PlotFcn', [], 'NumSeedPoints', min(10, o.Evaluations));
    otherwise
        searchSpace(space, o);
end

feas = evals([evals.feasible]);
if isempty(feas)
    [~, i] = min([evals.violation]);
    best = evals(i);
else
    [~, i] = min([feas.cost]);
    best = feas(i);
end
R = struct('best', best, 'evaluations', evals, 'pareto', pareto(evals), ...
    'scenario', S, 'method', method, 'params', P);

    function [f, g] = boFun(x)
        D = struct('phcEquipped', x.phcEquipped, 'vans', x.vans, 'linkTier', x.linkTier, ...
            'aiMode', char(x.aiMode), 'graders', x.graders, 'ophthHours', x.ophthHours, ...
            'sensitivity', sens(x.sensIdx));
        [f, g] = evaluate(D);
    end

    function searchSpace(space, o)
        % Two-stage decomposition. Coverage (PHCs equipped, vans) decides the
        % number of screens almost analytically - capture capacity is ample,
        % so screens ~ arrivals, which the scenario already contains - and
        % most of the fixed cost. Stage 1 ranks every coverage plan that
        % meets the screening target by its fixed cost; stage 2 runs a
        % simulation-based pattern search over the operational variables
        % (link tier, AI mode, graders, ophthalmologist hours, operating
        % point) for the cheapest coverage plans.
        rng(o.Seed);
        f = 364 / P.days;
        phcA = f * sum(S.arrivals(:, 1:S.nPHC), 1);
        vanA = f * sum(S.arrivals(:, S.nPHC + 1:end), 1);
        cov = [];
        for n = space.phcEquipped{2}(1):space.phcEquipped{2}(2)
            for v = space.vans{2}(1):space.vans{2}(2)
                screens = sum(phcA(1:n)) + sum(vanA(1:v));
                if screens >= P.target.screensPerYear
                    fixed = n * (P.cost.camera / P.cost.cameraLife + P.cost.camera * P.cost.cameraUpkeep ...
                        + P.cost.technicianPerSite) + v * (P.cost.van + 2 * (P.cost.camera / ...
                        P.cost.cameraLife + P.cost.camera * P.cost.cameraUpkeep));
                    cov(end + 1, :) = [n v fixed screens]; %#ok<AGROW>
                end
            end
        end
        if isempty(cov)
            cov = [space.phcEquipped{2}(2) space.vans{2}(2) 0 0];
        end
        cov = sortrows(cov, 3);
        nCov = min(3, size(cov, 1));
        opNames = {'linkTier', 'aiMode', 'graders', 'ophthHours', 'sensitivity'};
        budgetEach = floor(o.Evaluations / nCov);
        for c = 1:nCov
            start = P.decision;
            start = rmfield(start, 'reviewMode');
            start.phcEquipped = cov(c, 1);
            start.vans = cov(c, 2);
            start.graders = space.graders{2}(1);
            start.ophthHours = space.ophthHours{2}(1);
            stop = numel(evals) + budgetEach;
            if ~seen(start)
                evaluate(start);
            end
            cur = evals(end);
            improved = true;
            while improved && numel(evals) < stop
                improved = false;
                curScore = score(cur);
                for k = 1:numel(opNames)
                    v = space.(opNames{k});
                    if strcmp(v{1}, 'int')
                        cands = num2cell(cur.decision.(opNames{k}) + [-1 1]);
                        cands = cands(cellfun(@(x) x >= v{2}(1) && x <= v{2}(2), cands));
                    else
                        cands = v{2}(~cellfun(@(x) isequal(x, cur.decision.(opNames{k})), v{2}));
                    end
                    for j = 1:numel(cands)
                        if numel(evals) >= stop
                            break
                        end
                        D = rmfield(cur.decision, 'reviewMode');
                        D.(opNames{k}) = cands{j};
                        if seen(D)
                            continue
                        end
                        evaluate(D);
                        if score(evals(end)) < curScore - 1e-9
                            cur = evals(end);
                            curScore = score(cur);
                            improved = true;
                        end
                    end
                end
            end
        end
    end

    function e = incumbent()
        sc = arrayfun(@(x) score(x), evals);
        [~, i] = min(sc);
        e = evals(i);
    end

    function tf = seen(D)
        tf = false;
        for j = 1:numel(evals)
            if isequal(evals(j).decision.phcEquipped, D.phcEquipped) && ...
                    isequal(evals(j).decision.vans, D.vans) && ...
                    isequal(evals(j).decision.linkTier, D.linkTier) && ...
                    strcmp(evals(j).decision.aiMode, D.aiMode) && ...
                    isequal(evals(j).decision.graders, D.graders) && ...
                    isequal(evals(j).decision.ophthHours, D.ophthHours) && ...
                    isequal(evals(j).decision.sensitivity, D.sensitivity)
                tf = true;
                return
            end
        end
    end
end

% ======================================================================
function c = normalisedConstraints(K, P)
t = P.target;
c = [K.constraints.screens / t.screensPerYear, ...
     K.constraints.routineP95 / t.routineP95Hours, ...
     K.constraints.urgentP95 / t.urgentP95Hours, ...
     K.constraints.graderLoad, ...
     K.constraints.ophthLoad, ...
     K.constraints.sensitivity * 10];
end

function s = score(e)
% feasible plans by cost; infeasible ones after all feasible, by violation
if e.feasible
    s = e.cost;
else
    s = 1e3 + 100 * e.violation + e.cost;
end
end

function v = drawVar(spec, n, nTotal)
% stratified draw: cycles through the range so small designs cover it
if strcmp(spec{1}, 'int')
    lo = spec{2}(1); hi = spec{2}(2);
    u = mod((n - 1) / nTotal + rand / nTotal + 0.37 * n, 1);
    v = lo + floor(u * (hi - lo + 1));
    v = min(v, hi);
else
    vals = spec{2};
    v = vals{randi(numel(vals))};
end
end

function F = pareto(evals)
% non-dominated plans: lower cost and more patients reaching treatment
F = evals([]);
feas = evals([evals.feasible]);
for i = 1:numel(feas)
    dominated = false;
    for j = 1:numel(feas)
        a = feas(j).kpi.perYear.reachingTreatment;
        b = feas(i).kpi.perYear.reachingTreatment;
        if j ~= i && feas(j).cost <= feas(i).cost && a >= b && ...
                (feas(j).cost < feas(i).cost || a > b)
            dominated = true;
            break
        end
    end
    if ~dominated
        F(end + 1) = feas(i); %#ok<AGROW>
    end
end
if ~isempty(F)
    [~, order] = sort([F.cost]);
    F = F(order);
end
end

function v = ternary(c, a, b)
if c
    v = a;
else
    v = b;
end
end
