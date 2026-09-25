%EXP06_DISTRICT_SIMULATION Plan a district programme for 100,000+ screens a year.
%
%   1. one simulated year of an illustrative district (netra.sim.defaults:
%      36 PHCs, mobile camps, 2G-to-fibre links with outages, a reading hub)
%   2. the cheapest plan that meets every target - screens per year,
%      routine and urgent turnaround, reviewer load, programme sensitivity
%      (netra.sim.optimize: bayesopt when available, otherwise a two-stage
%      search that runs anywhere, Octave included)
%   3. what-if runs of that plan on the same patients: review without the
%      explainable console, cloud instead of edge grading
%   4. the planning dashboard and CSV tables in results/exp06
%   5. the chosen plan re-run in the Simulink model (or, without Simulink,
%      in its block emulator) and compared with the MATLAB reference
%
%   When exp04 has written a measured ROC (results/exp04/roc_referable.csv),
%   the simulation uses it instead of the binormal AUC assumption, so the
%   plan reflects the validated model. Every other number is an editable
%   assumption in netra.sim.defaults - replace it with local data.

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.sim.defaults'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
outDir = fullfile(root, 'results', 'exp06');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

P = netra.sim.defaults();
rocFile = fullfile(root, 'results', 'exp04', 'roc_referable.csv');
if exist(rocFile, 'file')
    r = csvread(rocFile, 1, 0);          % columns: threshold, fpr, tpr
    P.ai.roc = struct('fpr', r(:, 2), 'tpr', r(:, 3));
    fprintf('Using the measured ROC from %s\n', rocFile);
else
    fprintf('No measured ROC yet - binormal ROC with AUC %.2f (run exp04 first to use yours)\n', P.ai.auc);
end

% ---------------------------------------------------------- optimise
tic;
R = netra.sim.optimize(P, 'Method', 'auto', 'Evaluations', 42, 'Days', 182);
fprintf('Optimisation (%s, %d plans) took %.0f s\n', R.method, numel(R.evaluations), toc);
b = R.best;
D = b.decision;

% ------------------------------------------------ full year + what-if
S = netra.sim.scenario(P);
W = netra.sim.whatIf(P, D, S);
R.best.kpi = W.base.kpi;
K = W.base.kpi;
fprintf(['\nChosen plan: %s grading, %d PHCs, %d mobile unit(s), link tier %d, %d grader(s), ' ...
    '%d h/day ophthalmologist, AI sensitivity %.2f\n'], D.aiMode, D.phcEquipped, D.vans, ...
    D.linkTier, D.graders, D.ophthHours, D.sensitivity);
fprintf(['  %.0f screens/yr   routine P95 %.1f h   urgent notice P95 %.2f h   ' ...
    'reaching treatment %.0f/yr   Rs %.2f crore/yr   feasible %d\n'], K.perYear.screened, ...
    K.turnaround.routineP95, K.urgentNoticeP95, K.perYear.reachingTreatment, ...
    K.cost.total / 1e7, K.feasible);
names = {'base', 'plain', 'cloud', 'edge'};
fprintf('\n  %-7s %10s %10s %10s %10s %12s %10s\n', 'run', 'grader', 'ophth', 'routine', ...
    'urgent', 'reaching', 'cost');
for i = 1:numel(names)
    k = W.(names{i}).kpi;
    fprintf('  %-7s %9.0f%% %9.0f%% %9.1fh %9.2fh %12.0f %9.2fcr\n', names{i}, ...
        100 * k.utilisation.graders, 100 * k.utilisation.ophthalmologist, ...
        k.turnaround.routineP95, k.urgentNoticeP95, k.perYear.reachingTreatment, k.cost.total / 1e7);
end

% ------------------------------------------------------------ outputs
netra.sim.plotDashboard(R, W, 'File', fullfile(outDir, 'district_dashboard.png'));
fid = fopen(fullfile(outDir, 'plans.csv'), 'w');
fprintf(fid, ['aiMode,phcEquipped,vans,linkTier,graders,ophthHours,sensitivity,costCrore,' ...
    'screensPerYear,routineP95h,urgentNoticeP95h,graderLoad,ophthLoad,reachingPerYear,feasible\n']);
for i = 1:numel(R.evaluations)
    e = R.evaluations(i);
    d = e.decision;
    k = e.kpi;
    fprintf(fid, '%s,%d,%d,%d,%d,%d,%.2f,%.4f,%.0f,%.1f,%.2f,%.3f,%.3f,%.0f,%d\n', d.aiMode, ...
        d.phcEquipped, d.vans, d.linkTier, d.graders, d.ophthHours, d.sensitivity, e.cost, ...
        k.perYear.screened, k.turnaround.routineP95, k.urgentNoticeP95, k.utilisation.graders, ...
        k.utilisation.ophthalmologist, k.perYear.reachingTreatment, e.feasible);
end
fclose(fid);
save(fullfile(outDir, 'district_plan.mat'), 'R', 'W', 'P', '-v7');

% ------------------------------------------- Simulink cross-check
out = netra.sim.runSimulink(P, D, S, 'Engine', 'auto', 'Verbose', false);
verdict = 'matches the reference';
if ~out.crossCheck.pass
    verdict = 'DIFFERS from the reference';
end
fprintf('Simulink model (%s engine) %s: largest relative difference %.2g over %d signals and %d KPIs\n', ...
    out.engine, verdict, out.crossCheck.maxRelative, numel(out.crossCheck.signals), ...
    numel(out.crossCheck.kpis));
