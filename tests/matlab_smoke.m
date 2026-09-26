function summary = matlab_smoke(groups)
%MATLAB_SMOKE Five-minute check of everything the Octave CI cannot run.
%
%   >> netrasetu_setup
%   >> matlab_smoke                     all groups
%   >> matlab_smoke({'cnn', 'simulink'})
%
%   The CI runs the test suite in GNU Octave, which has no Deep Learning
%   Toolbox, no Statistics and Machine Learning ensembles, no Simulink and
%   no uifigure. This script exercises exactly those paths on synthetic
%   eyes. It needs no dataset, no GPU and no support package - the CNN
%   check uses SqueezeNet, which ships with the Deep Learning Toolbox.
%
%     cnn       build a network, train one epoch, fit the temperature,
%               infer with test-time augmentation, Grad-CAM++, and screen
%               an eye end to end with the CNN branch switched on
%     lesion    bagged-tree lesion ensemble: train, out-of-fold posteriors,
%               predict, Shapley explanation
%     simulink  build the .slx, simulate two weeks, compare every logged
%               signal with the MATLAB reference simulator
%     report    screen a phantom; A4 figure and bilingual HTML report
%     console   open the Reader Console on that eye and close it
%     app       open the Screening App, check a phantom, save its report
%
%   Each group runs on its own; a failure prints its error and the others
%   still run. Run it once after installing, before the experiments.

known = {'cnn', 'lesion', 'simulink', 'report', 'console', 'app'};
if nargin < 1 || isempty(groups)
    groups = known;
end
groups = cellstr(groups);
if netra.util.isOctave()
    error('netra:smoke:octave', 'matlab_smoke checks MATLAB-only branches; in Octave run tests/run_tests.');
end
tmp = fullfile(tempdir, 'netrasetu_smoke');
if exist(tmp, 'dir')
    rmdir(tmp, 's');
end
mkdir(tmp);
fprintf('\nNetraSetu MATLAB smoke test  (MATLAB %s, scratch folder %s)\n', version('-release'), tmp);
fprintf('%s\n', repmat('-', 1, 72));

summary = struct('group', {}, 'passed', {}, 'skipped', {}, 'message', {}, 'seconds', {});
shared = struct('R', []);
for k = 1:numel(groups)
    g = groups{k};
    t0 = tic;
    passed = false;
    skipped = false;
    msg = '';
    try
        switch g
            case 'cnn'
                [skipped, msg] = checkCnn(tmp);
            case 'lesion'
                [skipped, msg] = checkLesion();
            case 'simulink'
                [skipped, msg] = checkSimulink(tmp);
            case 'report'
                [shared.R, msg] = checkReport(tmp);
            case 'console'
                [skipped, msg] = checkConsole(tmp, shared.R);
            case 'app'
                [skipped, msg] = checkApp(tmp);
            otherwise
                error('netra:smoke:group', 'Unknown group "%s" (use %s).', g, strjoin(known, ', '));
        end
        passed = ~skipped;
    catch err
        msg = sprintf('%s  [%s line %d]', err.message, stackName(err), stackLine(err));
    end
    dt = toc(t0);
    summary(end + 1) = struct('group', g, 'passed', passed, 'skipped', skipped, ... %#ok<AGROW>
        'message', msg, 'seconds', dt);
    if skipped
        state = 'SKIP';
    elseif passed
        state = 'PASS';
    else
        state = 'FAIL';
    end
    fprintf('  %s  %-9s %6.1fs  %s\n', state, g, dt, msg);
end
fprintf('%s\n%d passed, %d skipped, %d failed\n\n', repmat('-', 1, 72), ...
    nnz([summary.passed]), nnz([summary.skipped]), ...
    nnz(~[summary.passed] & ~[summary.skipped]));
end

% ======================================================================
function [skipped, msg] = checkCnn(tmp)
skipped = ~netra.util.has('trainnet');
msg = 'needs the Deep Learning Toolbox (R2023b+)';
if skipped
    return
end
cfg = netra.config();
cfg.grading.cnnInputSize = 227;                 % SqueezeNet's native size
cfg.grading.cnnBackbone = 'squeezenet';
n = 20;
files = cell(n, 1);
grades = mod((0:n - 1)', 5);
for k = 1:n
    rgb = netra.phantom.generate('Grade', grades(k), 'Seed', 100 + k, 'Size', 512);
    files{k} = fullfile(tmp, sprintf('eye_%02d.png', k));
    imwrite(rgb, files{k});
end
cached = netra.grading.cnn.cacheDataset(files, cfg, fullfile(tmp, 'cnn_cache'), 'Verbose', false);
assert(all(~cellfun(@isempty, cached)), 'caching failed for some phantoms');
tr = 1:15;
va = 16:20;
model = netra.grading.cnn.train(cached(tr), grades(tr), cached(va), grades(va), cfg, ...
    'Backbone', 'squeezenet', 'Epochs', 1, 'BatchSize', 5);
assert(isfinite(model.temperature) && model.temperature > 0, 'temperature not fitted');
assert(isequal(size(model.valLogits), [numel(va) 5]), 'validation logits have the wrong shape');

X = single(imread(cached{va(1)}));
out = netra.grading.cnn.infer(model, X, cfg);
assert(numel(out.P) == 5 && abs(sum(out.P) - 1) < 1e-6, 'CNN probabilities do not sum to 1');
cam = netra.xai.gradcam(model, X);
assert(isequal(size(cam), [227 227]) && all(isfinite(cam(:))) && max(cam(:)) <= 1 + 1e-9, ...
    'Grad-CAM map has the wrong size or range');

% the CNN branch inside the full pipeline, with its explanation
M = netra.loadModels(struct('paths', struct('models', fullfile(tmp, 'no_models'))));
M.cnn = model;
M.status.cnn = true;
rgb = netra.phantom.generate('Grade', 3, 'Seed', 7, 'Size', 768);
R = netra.screen(rgb, 'Models', M, 'Config', cfg, 'ID', 'SMOKE-CNN');
assert(isfield(R, 'cnn') && ~isempty(R.cnn), 'the CNN branch did not run inside netra.screen');
assert(~isempty(R.xai.cam), 'no attention map in the screening result');
msg = sprintf('SqueezeNet 1 epoch, T = %.2f, P(ref) = %.2f, concordance fields: %s', ...
    model.temperature, sum(out.P(3:5)), strjoin(fieldnames(R.xai.concordance)', ', '));
end

function [skipped, msg] = checkLesion()
skipped = ~netra.util.has('fitcensemble');
msg = 'needs the Statistics and Machine Learning Toolbox';
if skipped
    return
end
[~, names] = netra.grading.lesionFeatures();
rng(3);
y = mod((0:149)', 5);
X = randn(150, numel(names)) + 0.8 * y;          % separable enough to learn
model = netra.grading.lesionModel('train', X, y, names, 'KFold', 3, 'Trees', 40);
assert(isequal(size(model.oof), [150 5]), 'out-of-fold posteriors have the wrong shape');
P = netra.grading.lesionModel('predict', model, X(1:5, :));
assert(isequal(size(P), [5 5]) && all(abs(sum(P, 2) - 1) < 1e-9), 'posteriors do not sum to 1');
phi = netra.grading.lesionModel('explain', model, X(end, :));
if isempty(phi)
    msg = 'ensemble OK; Shapley explanation unavailable (needs R2021a+)';
else
    msg = sprintf('ensemble OK; top Shapley feature: %s', phi(1).feature);
end
end

function [skipped, msg] = checkSimulink(tmp)
skipped = ~netra.util.has('new_system') || ~license('test', 'Simulink');
msg = 'needs Simulink';
if skipped
    return
end
P = netra.sim.defaults();
P.days = 14;
S = netra.sim.scenario(P);
model = 'NetraSetuSmoke';
cleaner = onCleanup(@() closeModel(model));
out = netra.sim.runSimulink(P, P.decision, S, 'Engine', 'simulink', 'Folder', tmp, ...
    'Model', model, 'Rebuild', true, 'Verbose', false);
assert(out.crossCheck.pass, 'Simulink differs from the MATLAB reference (%.3g in %s)', ...
    out.crossCheck.maxRelative, out.crossCheck.worst);
msg = sprintf('two simulated weeks in %.1f s, identical to the reference (max rel. diff %.2g)', ...
    out.seconds, out.crossCheck.maxRelative);
end

function [R, msg] = checkReport(tmp)
rgb = netra.phantom.generate('Grade', 3, 'Seed', 11, 'Size', 768);
R = netra.screen(rgb, 'ID', 'SMOKE-001', 'Site', 'Smoke test');
png = fullfile(tmp, 'report.png');
fig = netra.xai.reportFigure(R, 'File', png);
close(fig);
html = fullfile(tmp, 'report.html');
netra.xai.reportHTML(R, html);
assert(isfile(png) && isfile(html), 'report files were not written');
d = dir(html);
msg = sprintf('%s, grade %d; report.png and report.html (%.0f kB)', R.decision.triage, ...
    R.decision.grade, d.bytes / 1024);
end

function [skipped, msg] = checkConsole(tmp, R)
skipped = ~netra.util.has('uifigure');
msg = 'needs uifigure (R2021a+)';
if skipped
    return
end
if isempty(R)
    rgb = netra.phantom.generate('Grade', 2, 'Seed', 12, 'Size', 768);
    R = netra.screen(rgb, 'ID', 'SMOKE-002');
end
queue = fullfile(tmp, 'queue');
netra.ui.exportCase(R, queue);
app = netra.ui.ReaderConsole(queue, 'Reader', 'smoke', 'Log', fullfile(tmp, 'review_log.csv'));
drawnow;
pause(0.5);
ok = isvalid(app);
S = app.summary();
delete(app);
assert(ok && S.cases == 0, 'the Reader Console did not open cleanly');
msg = 'opened on one exported case and closed';
end

function [skipped, msg] = checkApp(tmp)
skipped = ~netra.util.has('uifigure');
msg = 'needs uifigure (R2021a+)';
if skipped
    return
end
app = netra.ui.ScreeningApp();
cleaner = onCleanup(@() delete(app));
rgb = netra.phantom.generate('Grade', 3, 'Seed', 21, 'Size', 768);
app.screenImage(rgb, 'SMOKE-APP');
drawnow;
R = app.Result;
assert(~isempty(R) && isfield(R, 'decision'), 'the Screening App did not screen the eye');
files = app.saveReport(fullfile(tmp, 'app_report.html'));
assert(numel(files) == 2 && all(cellfun(@isfile, files)), 'the Screening App did not save its report');
msg = sprintf('checked a grade-3 phantom (%s) and saved the HTML and PNG report', R.decision.triage);
end

% ======================================================================
function closeModel(model)
if bdIsLoaded(model)
    close_system(model, 0);
end
end

function s = stackName(err)
s = '?';
if ~isempty(err.stack)
    s = err.stack(1).name;
end
end

function n = stackLine(err)
n = 0;
if ~isempty(err.stack)
    n = err.stack(1).line;
end
end
