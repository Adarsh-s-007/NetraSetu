%DEMO_NETRASETU Five-minute tour, no dataset needed (MATLAB or GNU Octave).
%
%   >> demo_netrasetu
%
%   1. makes three synthetic eyes (healthy, moderate NPDR, severe NPDR) and a
%      defocused photograph, with exact ground truth
%   2. screens each one end to end and prints the triage with its reasons
%   3. writes the A4 report and the bilingual HTML report of the severe eye
%      to results/demo/
%   4. simulates four weeks of the default district programme, compares the
%      explainable console with plain image review on the same patients,
%      and checks that the Simulink block code reproduces the simulation
%   5. in MATLAB with a display, opens the Reader Console on these cases
%   Synthetic eyes show what the software does, not how accurate it is on
%   patients: for that, run experiments/run_all.m on the public datasets.

here = fileparts(mfilename('fullpath'));
if isempty(which('netra.config'))
    run(fullfile(here, 'netrasetu_setup.m'));
end
cfg = netra.config();
out = fullfile(cfg.paths.results, 'demo');
if ~exist(out, 'dir')
    mkdir(out);
end
fprintf('\nNetraSetu %s - demo\n\n', netra.version());

% ------------------------------------------------------- 1-2 screening
cases = {'healthy eye', 0, struct(); 'moderate NPDR', 2, struct(); ...
    'severe NPDR', 3, struct(); 'defocused photograph', 1, struct('blur', 6)};
results = cell(size(cases, 1), 1);
for k = 1:size(cases, 1)
    [rgb, gt] = netra.phantom.generate('Grade', cases{k, 2}, 'Seed', 40 + k, 'Size', 1024, ...
        'Degrade', cases{k, 3});
    R = netra.screen(rgb, 'Config', cfg, 'ID', sprintf('DEMO-%02d', k), 'Eye', 'R', ...
        'Site', 'PHC (synthetic)');
    results{k} = R;
    T = R.decision;
    fprintf('%-22s truth ICDR %d  ->  %-12s (%.1f s)\n', cases{k, 1}, gt.grade, T.triage, R.timing.total);
    for r = 1:numel(T.reasons)
        fprintf('%24s- %s\n', '', T.reasons{r});
    end
    if isfield(R, 'rules')
        for e = 1:min(3, numel(R.rules.evidence))
            fprintf('%24s  evidence: %s\n', '', R.rules.evidence{e});
        end
    end
end

% ------------------------------------------------------------ 3 reports
R = results{3};
fig = netra.xai.reportFigure(R, 'File', fullfile(out, 'report_severe.png'));
if ishandle(fig)
    close(fig);
end
netra.xai.reportHTML(R, fullfile(out, 'report_severe.html'));
fprintf('\nReports: %s\n', out);

% ----------------------------------------------------------- 4 district
P = netra.sim.defaults();
P.days = 28;
S = netra.sim.scenario(P);
D = P.decision;
a = netra.sim.runReference(P, D, S);
D.reviewMode = 'plain';
b = netra.sim.runReference(P, D, S);
fprintf(['\nFour weeks of the default district plan (%d PHCs, %s grading), same patients:\n' ...
    '  %-26s grader load %3.0f%%, ophthalmologist %3.0f%%, routine result P95 %5.1f h\n' ...
    '  %-26s grader load %3.0f%%, ophthalmologist %3.0f%%, routine result P95 %5.1f h\n'], ...
    P.decision.phcEquipped, P.decision.aiMode, 'explainable console (30 s)', ...
    100 * a.kpi.utilisation.graders, 100 * a.kpi.utilisation.ophthalmologist, ...
    a.kpi.turnaround.routineP95, 'plain image review (150 s)', 100 * b.kpi.utilisation.graders, ...
    100 * b.kpi.utilisation.ophthalmologist, b.kpi.turnaround.routineP95);
e = netra.sim.runSimulink(P, P.decision, S, 'Engine', 'emulate', 'CrossCheck', false);
C = netra.sim.crossCheck(a, e);
verdict = 'match';
if ~C.pass
    verdict = 'MISMATCH';
end
fprintf('  Simulink block code vs reference: largest relative difference %.2g (%s)\n', ...
    C.maxRelative, verdict);

% --------------------------------------------------------- 5 console
if ~netra.util.isOctave() && usejava('desktop')
    queue = fullfile(out, 'queue');
    if ~exist(queue, 'dir')
        mkdir(queue);
    end
    for k = 1:numel(results)
        netra.ui.exportCase(results{k}, queue);
    end
    netra.ui.ReaderConsole(queue, 'Log', fullfile(out, 'reader_log.csv'));
    fprintf('\nReader Console opened: Enter agrees, 0-4 overrides the grade, R/E/L/A switch views.\n');
end
fprintf('\nNext: run experiments/run_all.m with the datasets in data/ (see data/README.md).\n\n');
