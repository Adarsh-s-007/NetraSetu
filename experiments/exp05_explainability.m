%EXP05_EXPLAINABILITY Do the explanations point where a clinician would look?
%
%   An explanation is only clinically useful if it lands on the lesions.
%   IDRiD's pixel-level lesion masks (microaneurysms, haemorrhages, hard
%   and soft exudates) say where the disease is, so each explanation map is
%   scored against them on the segmentation test images:
%     pointing game   the map's maximum lies on a reference lesion (dilated
%                     by 0.1 disc diameter for the coarse CNN grid)
%     energy share    fraction of the map's mass inside the dilated lesions
%     lift            energy share / area share of those lesions - how many
%                     times better than a map spread uniformly over the retina
%   Maps compared on the same eyes (exact McNemar on pointing hits):
%     evidence        lesion evidence map of the classical detectors (the
%                     explanation shown when no CNN is loaded)
%     Grad-CAM++      and Grad-CAM, for the referable-DR log-odds of the CNN
%                     (MATLAB with a trained CNN, exp03)
%   plus the attention-evidence concordance the pipeline uses to flag a CNN
%   that looks elsewhere.
%
%   Reader time: when Reader Console logs exist (results/reader/*.csv, see
%   netra.ui.ReaderConsole), their median review time, share under 30 s
%   and agreement with the AI are summarised as well.
%
%   Outputs: results/exp05/{explainability.csv, summary.mat, examples.png}.

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
cfg = netra.config();
M = netra.loadModels(cfg);
if ~isempty(M.vessel)
    cfg.vessels.model = M.vessel;
end
outDir = fullfile(cfg.paths.results, 'exp05');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
if ~exist('dataIDRiD', 'var'), dataIDRiD = ''; end
if ~exist('maxImages', 'var'), maxImages = Inf; end

Dseg = netra.io.idrid(dataIDRiD, 'segmentation');
te = find(strcmp(Dseg.split, 'test'));
if isempty(te)
    te = (1:Dseg.n)';
end
te = te(1:min(numel(te), maxImages));
maps = {'evidence'};
if ~isempty(M.cnn)
    maps = [maps, {'gradcampp', 'gradcam'}];
end
nM = numel(maps);
hit = false(numel(te), nM);
energy = NaN(numel(te), nM);
lift = NaN(numel(te), nM);
concord = NaN(numel(te), 1);
examples = {};
fprintf('\nExplainability on %d IDRiD test images (%s)\n', numel(te), strjoin(maps, ', '));
for n = 1:numel(te)
    i = te(n);
    pre = netra.eval.prepareImage(Dseg.file{i}, cfg);
    A = netra.anatomy.analyze(pre.S, pre.E, cfg);
    L = netra.lesions.detectAll(pre.E, A, cfg);
    fov = pre.E.mask;
    % reference lesions on the canvas, dilated by 0.1 DD
    ref = false(size(fov));
    for t = {'MA', 'HE', 'EX', 'SE'}
        f = Dseg.masks.(t{1}){i};
        if ~isempty(f)
            ref = ref | netra.quality.warpToCanvas(netra.io.readMask(f), pre.S);
        end
    end
    tol = max(1, round(0.1 * A.od.pxPerDD));
    refD = imdilate(ref, strel('disk', tol, 0)) & fov;
    areaShare = nnz(refD) / max(nnz(fov), 1);
    mp = cell(1, nM);
    mp{1} = netra.xai.evidenceMap(L, A);
    if nM > 1
        X = netra.grading.cnn.preprocess(pre.S, cfg);
        c1 = netra.xai.gradcam(M.cnn, X, 'Method', 'gradcam++');
        c2 = netra.xai.gradcam(M.cnn, X, 'Method', 'gradcam');
        mp{2} = imresize(c1, size(fov), 'bilinear') .* fov;
        mp{3} = imresize(c2, size(fov), 'bilinear') .* fov;
        C = netra.xai.concordance(mp{2}, L.masks, fov, cfg);
        concord(n) = C.score;
    end
    for k = 1:nM
        m = max(mp{k}, 0) .* fov;
        if ~any(m(:))
            continue
        end
        [~, j] = max(m(:));
        hit(n, k) = refD(j);
        energy(n, k) = sum(m(refD)) / sum(m(:));
        lift(n, k) = energy(n, k) / max(areaShare, eps);
    end
    if numel(examples) < 4
        row = {pre.E.display, netra.xai.heat(pre.E.display, double(ref)), ...
            netra.xai.heat(pre.E.display, mp{1} / max(max(mp{1}(:)), eps))};
        if nM > 1
            row{end + 1} = netra.xai.heat(pre.E.display, mp{2}); %#ok<SAGROW>
        end
        examples = [examples, row]; %#ok<AGROW>
    end
    fprintf('  %-10s pointing %s  energy %s\n', Dseg.id{i}, mat2str(hit(n, :)), ...
        mat2str(round(100 * energy(n, :)) / 100));
end

names = struct('evidence', 'Lesion evidence map', 'gradcampp', 'Grad-CAM++', 'gradcam', 'Grad-CAM');
rows = struct('map', maps, 'name', '', 'pointing', NaN, 'pointingCI', [], 'energy', NaN, ...
    'lift', NaN, 'mcnemarVsEvidence', []);
fprintf('\n  %-20s %22s %14s %8s\n', 'map', 'pointing game (95% CI)', 'energy share', 'lift');
for k = 1:nM
    ok = ~isnan(energy(:, k));
    rows(k).name = names.(maps{k});
    rows(k).pointing = mean(hit(ok, k));
    rows(k).pointingCI = netra.eval.wilson(nnz(hit(ok, k)), nnz(ok));
    rows(k).energy = mean(energy(ok, k));
    rows(k).lift = mean(lift(ok, k));
    if k > 1
        rows(k).mcnemarVsEvidence = netra.eval.mcnemar(hit(:, k), hit(:, 1));
    end
    fprintf('  %-20s %6.1f%% (%4.1f-%4.1f)   %13.3f %8.2f\n', rows(k).name, 100 * rows(k).pointing, ...
        100 * rows(k).pointingCI, rows(k).energy, rows(k).lift);
end
summary = struct('rows', rows, 'n', numel(te), 'concordance', mean(concord(~isnan(concord))));
if nM > 1
    fprintf('  attention-evidence concordance (Grad-CAM++ vs detectors): mean %.2f\n', summary.concordance);
end

% ------------------------------------------------------ reader study logs
logs = netra.io.findFiles(fullfile(cfg.paths.results, 'reader'), '\.csv$', 1);
if ~isempty(logs)
    secs = [];
    agree = [];
    for k = 1:numel(logs)
        T = netra.io.readCSV(logs{k});
        s = netra.io.column(T, {'seconds', 'reviewSeconds'}, 'num');
        a = netra.io.column(T, {'agreed', 'agree'});
        a = double(strcmpi(a, 'true') | strcmp(a, '1'));    % logical written as 1/0 or true/false
        secs = [secs; s(:)]; %#ok<AGROW>
        agree = [agree; a(:)]; %#ok<AGROW>
    end
    secs = secs(~isnan(secs));
    summary.reader = struct('cases', numel(secs), 'medianSeconds', median(secs), ...
        'under30', mean(secs <= 30), 'agreement', mean(agree(~isnan(agree))));
    fprintf('Reader console: %d cases, median %.0f s, %.0f%% within 30 s, %.0f%% agreed with the AI\n', ...
        numel(secs), median(secs), 100 * mean(secs <= 30), 100 * summary.reader.agreement);
end

fid = fopen(fullfile(outDir, 'explainability.csv'), 'w');
fprintf(fid, 'map,pointing,pointingLo,pointingHi,energyShare,lift,mcnemarP\n');
for k = 1:nM
    p = NaN;
    if ~isempty(rows(k).mcnemarVsEvidence)
        p = rows(k).mcnemarVsEvidence.p;
    end
    fprintf(fid, '%s,%.4f,%.4f,%.4f,%.4f,%.3f,%.4g\n', maps{k}, rows(k).pointing, ...
        rows(k).pointingCI, rows(k).energy, rows(k).lift, p);
end
fclose(fid);
save(fullfile(outDir, 'summary.mat'), 'summary', '-v7');
if ~isempty(examples)
    imwrite(netra.util.montage(examples, 3 + (nM > 1)), fullfile(outDir, 'examples.png'));
end
fprintf('Saved %s\n', outDir);
