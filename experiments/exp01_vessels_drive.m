%EXP01_VESSELS_DRIVE Vessel segmentation on DRIVE: fused detectors vs each one alone.
%
%   Question: does combining three complementary vessel detectors beat
%   each of them used alone, and where does the result sit among published
%   methods?
%
%   1. Learn the logistic fusion of the detector responses on the DRIVE
%      training images (20) -> models/vessel_fusion.mat, which the pipeline
%      loads automatically from then on.
%   2. Score every variant on the test images (20) at DRIVE's native
%      resolution, inside DRIVE's FOV masks: pixel ROC AUC (pooled and per
%      image), and Se / Sp / Acc / F1 at the threshold that maximises
%      accuracy on the TRAINING images (the test set never picks it).
%        hessian   multiscale Frangi vesselness
%        line      multiscale line detector (Nguyen 2013)
%        tophat    supremum of linear openings (Zana & Klein 2001)
%        average   the three, robustly normalised and averaged
%        fusion    the learned logistic fusion (deployed)
%   3. Paired comparison over the test images: fusion minus each single
%      detector, mean AUC difference with a bootstrap 95 % CI and an exact
%      sign test (images are the independent units, not pixels).
%   4. The deployed hysteresis mask, the second human observer, published
%      methods (netra.eval.benchmarks) and an example figure.
%
%   Data: data/DRIVE (or set dataDRIVE = '<folder>' before running).
%   Outputs: results/exp01/{vessels_drive.csv, summary.mat, example.jpg}.
%   Runs in MATLAB and in GNU Octave.

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
cfg = netra.config();
outDir = fullfile(cfg.paths.results, 'exp01');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
if ~exist('dataDRIVE', 'var')
    dataDRIVE = '';
end
D = netra.io.drive(dataDRIVE);
netra.io.describe(D);
hasGT = ~cellfun(@isempty, D.gt);
tr = find(strcmp(D.split, 'train') & hasGT);
te = find(strcmp(D.split, 'test') & hasGT);
note = '';
if isempty(te)
    % the grand-challenge release withholds the test labels
    half = floor(numel(tr) / 2);
    te = tr(half + 1:end);
    tr = tr(1:half);
    note = 'test labels unavailable: trained on half of the training images, tested on the other half';
    warning('netra:exp01:split', '%s', note);
end
keys = {'hessian', 'line', 'tophat', 'average', 'fusion'};
labels = {'Frangi Hessian', 'Line detector', 'Linear top-hat', 'Average of three', 'Learned fusion'};
nV = numel(keys);
rng(1);

% ------------------------------------------ 1. training images: responses
fprintf('\nTraining images: detector responses\n');
Xs = [];
ys = [];
trainStore = cell(numel(tr), 1);
for n = 1:numel(tr)
    i = tr(n);
    pre = netra.eval.prepareImage(D.file{i}, cfg);
    V = netra.anatomy.vessels(pre.E.gN, pre.E.mask, cfg);
    Dv = size(V.prob, 1);
    gt = netra.io.readMask(D.gt{i});
    gtV = imresize(double(netra.quality.warpToCanvas(gt, pre.S)), [Dv Dv], 'bilinear') >= 0.5;
    inV = find(V.fovMask);
    pick = inV(randperm(numel(inV), min(25000, numel(inV))));
    X = [V.response.hessian(pick), V.response.line(pick), V.response.tophat(pick), V.contrast(pick)];
    Xs = [Xs; X]; %#ok<AGROW>
    ys = [ys; gtV(pick)]; %#ok<AGROW>
    if ~isempty(D.fov{i})
        fovO = netra.io.readMask(D.fov{i});
    else
        fovO = pre.F.mask;
    end
    % keep only what the threshold search needs (the canvas images are large)
    trainStore{n} = struct('geom', struct('size', pre.S.size, 'origin', pre.S.origin, ...
        'scale', pre.S.scale), 'Dc', size(pre.E.gN, 1), 'resp', struct('hessian', ...
        single(V.response.hessian), 'line', single(V.response.line), 'tophat', ...
        single(V.response.tophat)), 'contrast', single(V.contrast), 'fov', V.fovMask, ...
        'gt', gt, 'fovO', fovO);
    fprintf('  %s\n', D.id{i});
end
beta = netra.util.logistic('fit', Xs, ys, 1e-4);
model = struct('beta', beta, 'features', {{'hessian', 'line', 'tophat', 'contrast'}}, ...
    'trainedOn', sprintf('DRIVE, %d images', numel(tr)), 'created', datestr(now, 'yyyy-mm-dd'));
save(fullfile(cfg.paths.models, 'vessel_fusion.mat'), 'model', '-v7');
fprintf('Fusion weights (intercept, hessian, line, tophat, contrast): %s\n', mat2str(beta', 3));

% ------------------------------- 2. accuracy-optimal thresholds (training)
Hs = cell(1, nV);
for v = 1:nV
    Hs{v} = netra.eval.countsPR('init', 1000);
end
for n = 1:numel(tr)
    T = trainStore{n};
    P = netra.eval.vesselVariants(T.resp, T.contrast, T.fov, cfg, beta);
    for v = 1:nV
        Po = netra.quality.warpToOriginal(imresize(P.(keys{v}), [T.Dc T.Dc], 'bilinear'), T.geom);
        Hs{v} = netra.eval.countsPR('add', Hs{v}, Po(T.fovO), T.gt(T.fovO));
    end
end
thr = zeros(1, nV);
for v = 1:nV
    tp = flipud(cumsum(flipud(Hs{v}.pos)));      % positives with bin >= k
    tn = cumsum(Hs{v}.neg) - Hs{v}.neg;          % negatives with bin <  k
    acc = (tp + tn) / (sum(Hs{v}.pos) + sum(Hs{v}.neg));
    [~, k] = max(acc);
    thr(v) = (k - 1) / Hs{v}.nBins;
end
clear trainStore

% -------------------------------------------------- 3. test images
fprintf('\nTest images\n');
cfgF = cfg;
cfgF.vessels.model = model;
aucImg = NaN(numel(te), nV);
pooledS = cell(1, nV);
pooledY = [];
conf = zeros(nV, 4);                                % tp fp tn fn at the training threshold
deployed = zeros(1, 4);
observer = zeros(1, 4);
hasObserver = false;
example = [];
for n = 1:numel(te)
    i = te(n);
    pre = netra.eval.prepareImage(D.file{i}, cfg);
    V = netra.anatomy.vessels(pre.E.gN, pre.E.mask, cfgF);
    P = netra.eval.vesselVariants(V.response, V.contrast, V.fovMask, cfg, beta);
    gt = netra.io.readMask(D.gt{i});
    if ~isempty(D.fov{i})
        fov = netra.io.readMask(D.fov{i});
    else
        fov = pre.F.mask;
    end
    y = gt(fov);
    pooledY = [pooledY; y]; %#ok<AGROW>
    maps = cell(1, nV);
    for v = 1:nV
        Po = netra.quality.warpToOriginal(imresize(P.(keys{v}), size(pre.E.gN), 'bilinear'), pre.S);
        maps{v} = Po;
        s = Po(fov);
        r = netra.eval.rocFast(y, s);
        aucImg(n, v) = r.auc;
        pooledS{v} = [pooledS{v}; single(s)];
        b = s >= thr(v);
        conf(v, :) = conf(v, :) + [nnz(b & y), nnz(b & ~y), nnz(~b & ~y), nnz(~b & y)];
    end
    mO = netra.quality.warpToOriginal(V.maskWork, pre.S);
    b = mO(fov);
    deployed = deployed + [nnz(b & y), nnz(b & ~y), nnz(~b & ~y), nnz(~b & y)];
    if ~isempty(D.gt2{i})
        g2 = netra.io.readMask(D.gt2{i});
        b = g2(fov);
        observer = observer + [nnz(b & y), nnz(b & ~y), nnz(~b & ~y), nnz(~b & y)];
        hasObserver = true;
    end
    if isempty(example)
        example = struct('rgb', pre.rgb, 'gt', gt, 'maps', {maps}, 'id', D.id{i});
    end
    fprintf('  %s  AUC fusion %.4f\n', D.id{i}, aucImg(n, nV));
end

% ---------------------------------------------------------- 4. summary
metrics = @(c) struct('se', c(1) / max(c(1) + c(4), 1), 'sp', c(3) / max(c(3) + c(2), 1), ...
    'acc', (c(1) + c(3)) / max(sum(c), 1), 'f1', 2 * c(1) / max(2 * c(1) + c(2) + c(4), 1));
rows = struct('key', keys, 'label', labels);
for v = 1:nV
    r = netra.eval.rocFast(pooledY, double(pooledS{v}));
    m = metrics(conf(v, :));
    d = aucImg(:, nV) - aucImg(:, v);
    rows(v).aucPooled = r.auc;
    rows(v).aucMean = mean(aucImg(:, v));
    rows(v).aucSD = std(aucImg(:, v));
    rows(v).threshold = thr(v);
    rows(v).se = m.se;
    rows(v).sp = m.sp;
    rows(v).acc = m.acc;
    rows(v).f1 = m.f1;
    if v < nV
        ci = netra.eval.bootstrap(@(idx) mean(d(idx)), numel(d), 'B', 2000);
        t = netra.eval.mcnemar(d > 0, d < 0);
        rows(v).dAUC = mean(d);
        rows(v).dCI = ci(1:2);
        rows(v).wins = nnz(d > 0);
        rows(v).p = t.p;
    else
        rows(v).dAUC = 0;
        rows(v).dCI = [0 0];
        rows(v).wins = NaN;
        rows(v).p = NaN;
    end
end
summary = struct('rows', rows, 'nTrain', numel(tr), 'nTest', numel(te), 'note', note, ...
    'deployed', metrics(deployed), 'fusionModel', model);
if hasObserver
    summary.secondObserver = metrics(observer);
end

fprintf('\nDRIVE test set (%d images), pixels inside the FOV\n', numel(te));
fprintf('  %-18s %8s %14s %7s %7s %7s %7s   %s\n', 'detector', 'AUC', 'AUC per image', 'Se', 'Sp', ...
    'Acc', 'F1', 'fusion minus this (mean dAUC, 95% CI, wins, sign test)');
for v = 1:nV
    r = rows(v);
    extra = '';
    if v < nV
        extra = sprintf('%+.4f [%+.4f, %+.4f]  %d/%d  p = %.2g', r.dAUC, r.dCI(1), r.dCI(2), ...
            r.wins, numel(te), r.p);
    end
    fprintf('  %-18s %8.4f %7.4f+-%.4f %7.4f %7.4f %7.4f %7.4f   %s\n', r.label, r.aucPooled, ...
        r.aucMean, r.aucSD, r.se, r.sp, r.acc, r.f1, extra);
end
m = summary.deployed;
fprintf('  %-18s %8s %14s %7.4f %7.4f %7.4f %7.4f   (hysteresis mask used by the pipeline)\n', ...
    'Deployed mask', '', '', m.se, m.sp, m.acc, m.f1);
if hasObserver
    m = summary.secondObserver;
    fprintf('  %-18s %8s %14s %7.4f %7.4f %7.4f %7.4f\n', '2nd observer', '', '', m.se, m.sp, m.acc, m.f1);
end
fprintf('\nPublished results on DRIVE (context; different training protocols):\n');
netra.eval.benchmarks('Task', 'vessels');

fid = fopen(fullfile(outDir, 'vessels_drive.csv'), 'w');
fprintf(fid, 'detector,aucPooled,aucMean,aucSD,threshold,se,sp,acc,f1,dAUC,dLo,dHi,wins,p\n');
for v = 1:nV
    r = rows(v);
    fprintf(fid, '%s,%.5f,%.5f,%.5f,%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%g,%.4g\n', r.key, ...
        r.aucPooled, r.aucMean, r.aucSD, r.threshold, r.se, r.sp, r.acc, r.f1, r.dAUC, ...
        r.dCI(1), r.dCI(2), r.wins, r.p);
end
fclose(fid);
save(fullfile(outDir, 'summary.mat'), 'summary', '-v7');
tiles = [{example.rgb, example.gt}, example.maps([5 1 2 3])];
imwrite(netra.util.montage(tiles, 3), fullfile(outDir, 'example.jpg'), 'Quality', 90);
fprintf('Saved %s\n', outDir);
