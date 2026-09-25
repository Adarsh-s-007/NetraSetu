function recs = screenDataset(D, varargin)
%SCREENDATASET Run the full screening pipeline over a dataset, resumably.
%
%   recs = netra.eval.screenDataset(D)
%   recs = netra.eval.screenDataset(D, 'Models', M, 'Config', cfg, ...
%              'Cache', 'results/exp04/messidor2.mat', 'Explain', false)
%
%   Every photograph in D (netra.io.*) goes through netra.screen and is
%   reduced to one compact record, so thousands of eyes fit in memory:
%     id, file, ok, error, seconds
%     quality, qualityScore, graded (false when RECAPTURE)
%     P (fused 1 x 5), grade, pReferable, pUrgent, set (conformal 1 x 5)
%     rulesGrade, rulesP, lesionP, cnnP (NaN(1, 5) when a branch is off)
%     triage, referred (REFER or URGENT), dme (0/1/2 from the exudates)
%     features (1 x 32, netra.grading.lesionFeatures), summary (lesion tallies)
%     od, odRadius, fovea (original pixels), anatomyFlags, concordance
%   With 'Cache' the records are saved every 'SaveEvery' images and images
%   already in the cache are skipped - a 1,748-image run can be stopped and
%   resumed. 'Parallel' (false) uses parfor per chunk when the Parallel
%   Computing Toolbox is available. Failures are recorded, never fatal.

o = netra.util.opts(struct('Models', [], 'Config', [], 'Cache', '', 'SaveEvery', 25, ...
    'Explain', false, 'Parallel', false, 'Verbose', true), varargin{:});
cfg = o.Config;
if isempty(cfg)
    cfg = netra.config();
end
M = o.Models;
if isempty(M)
    M = netra.loadModels(cfg);
end
recs = repmat(emptyRecord(), 0, 1);
if ~isempty(o.Cache) && exist(o.Cache, 'file')
    S = load(o.Cache, 'recs');
    recs = S.recs(:);
end
done = ismember(D.id, {recs.id});
todo = find(~done);
if o.Verbose && ~isempty(todo)
    fprintf('%s: screening %d images (%d cached)\n', D.name, numel(todo), nnz(done));
end
par = o.Parallel && ~netra.util.isOctave() && netra.util.has('parfor') && ...
    license('test', 'Distrib_Computing_Toolbox');
t0 = tic;
for c0 = 1:o.SaveEvery:numel(todo)
    chunk = todo(c0:min(c0 + o.SaveEvery - 1, numel(todo)));
    part = repmat(emptyRecord(), numel(chunk), 1);
    files = D.file(chunk);
    ids = D.id(chunk);
    explain = o.Explain;
    if par
        parfor k = 1:numel(chunk)
            part(k) = one(files{k}, ids{k}, M, cfg, explain);
        end
    else
        for k = 1:numel(chunk)
            part(k) = one(files{k}, ids{k}, M, cfg, explain);
        end
    end
    recs = [recs; part]; %#ok<AGROW>
    if ~isempty(o.Cache)
        folder = fileparts(o.Cache);
        if ~isempty(folder) && ~exist(folder, 'dir')
            mkdir(folder);
        end
        save(o.Cache, 'recs', '-v7');
    end
    if o.Verbose
        n = c0 + numel(chunk) - 1;
        el = toc(t0);
        fprintf('  %5d / %d   %.1f s per image, about %.0f min left\n', n, numel(todo), ...
            el / n, el / n * (numel(todo) - n) / 60);
    end
end
% return in the order of D
[tf, loc] = ismember(D.id, {recs.id});
recs = recs(loc(tf));
end

% ======================================================================
function r = one(file, id, M, cfg, explain)
r = emptyRecord();
r.id = id;
r.file = file;
t = tic;
try
    R = netra.screen(file, 'Models', M, 'Config', cfg, 'Explain', explain, 'ID', id);
    r.quality = R.quality.decision;
    r.qualityScore = R.quality.score;
    T = R.decision;
    r.triage = T.triage;
    r.referred = any(strcmp(T.triage, {'REFER', 'URGENT'}));
    r.graded = isfield(R, 'fusion');
    if r.graded
        Fz = R.fusion;
        r.P = Fz.P;
        r.grade = Fz.grade;
        r.pReferable = Fz.pReferable;
        r.pUrgent = Fz.pUrgent;
        r.rulesGrade = R.rules.grade;
        r.dme = R.rules.dme;
        b = Fz.branches;
        if isfield(b, 'rules') && ~isempty(b.rules), r.rulesP = b.rules; end
        if isfield(b, 'lesion') && ~isempty(b.lesion), r.lesionP = b.lesion; end
        if isfield(b, 'cnn') && ~isempty(b.cnn), r.cnnP = b.cnn; end
        if ~isempty(R.conformalSet), r.set = logical(R.conformalSet(:)'); end
        r.features = R.features.values(:)';
        r.summary = R.lesions.summary;
        cs = struct('scale', R.canvas.scale, 'origin', R.canvas.origin);
        r.od = netra.quality.toOriginal(cs, R.anatomy.od.centre(:)');
        r.odRadius = R.anatomy.od.radius / R.canvas.scale;
        r.fovea = netra.quality.toOriginal(cs, R.anatomy.fovea.centre(:)');
        r.anatomyFlags = strjoin(R.anatomy.flags, ',');
        if isfield(R.xai, 'concordance') && isfield(R.xai.concordance, 'score')
            r.concordance = R.xai.concordance.score;
        end
    end
    r.ok = true;
catch err
    r.ok = false;
    r.error = err.message;
end
r.seconds = toc(t);
end

function r = emptyRecord()
n5 = NaN(1, 5);
r = struct('id', '', 'file', '', 'ok', false, 'error', '', 'seconds', NaN, ...
    'quality', '', 'qualityScore', NaN, 'graded', false, 'P', n5, 'grade', NaN, ...
    'pReferable', NaN, 'pUrgent', NaN, 'set', false(1, 5), 'rulesGrade', NaN, ...
    'rulesP', n5, 'lesionP', n5, 'cnnP', n5, 'triage', '', 'referred', false, 'dme', NaN, ...
    'features', NaN(1, 32), 'summary', struct(), 'od', [NaN NaN], 'odRadius', NaN, ...
    'fovea', [NaN NaN], 'anatomyFlags', '', 'concordance', NaN);
end
