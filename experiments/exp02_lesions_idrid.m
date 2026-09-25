%EXP02_LESIONS_IDRID Lesion segmentation and anatomical landmarks on IDRiD.
%
%   Question: how well do the interpretable lesion detectors - the evidence
%   the grade and the report are built on - find each lesion, and how
%   accurately are the optic disc and fovea located (they anchor the
%   quadrants of the 4-2-1 rule and the 1-DD macular-oedema zone)?
%
%   A. Segmentation test set (27 images, 4288 x 2848): pixel-level area
%      under the precision-recall curve for microaneurysms (MA),
%      haemorrhages (HE), hard exudates (EX) and soft exudates (SE =
%      cotton-wool spots) - IDRiD sub-challenge 1's metric, computed over
%      all pixels of all test images at native resolution
%      (netra.eval.countsPR); microaneurysm FROC (lesion level,
%      netra.eval.froc); optic-disc Jaccard index.
%   B. Localisation test set (103 images): optic-disc and fovea centre
%      error in pixels and in disc diameters (DD), and the share of eyes
%      located within 1/8, 1/4 and 1/2 DD.
%
%   The detectors are unsupervised and were NOT tuned on IDRiD; the
%   challenge entries they are listed next to are deep networks trained
%   on its training set. The comparison shows what transparency costs in
%   pixel accuracy, and the grading experiments (exp04) show whether that
%   matters for the referral decision.
%
%   Data: data/IDRiD (or set dataIDRiD before running). 'MaxImages' style
%   quick runs: set maxImages = 5 before running.
%   Outputs: results/exp02/{lesions_idrid.csv, localisation_idrid.csv,
%   summary.mat, example.png}.  Runs in MATLAB and in GNU Octave.

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
M = netra.loadModels(netra.config());
cfg = netra.config();
if ~isempty(M.vessel)
    cfg.vessels.model = M.vessel;               % DRIVE-trained fusion from exp01
end
outDir = fullfile(cfg.paths.results, 'exp02');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
if ~exist('dataIDRiD', 'var')
    dataIDRiD = '';
end
if ~exist('maxImages', 'var')
    maxImages = Inf;
end
summary = struct();

% ============================================ A. lesion segmentation
Dseg = netra.io.idrid(dataIDRiD, 'segmentation');
te = find(strcmp(Dseg.split, 'test'));
if isempty(te)
    te = (1:Dseg.n)';
end
te = te(1:min(numel(te), maxImages));
types = {'MA', 'HE', 'EX', 'SE'};
fields = {'ma', 'he', 'ex', 'se'};
H = cell(1, 4);
for t = 1:4
    H{t} = netra.eval.countsPR('init', 1000);
end
dets = struct('image', {}, 'x', {}, 'y', {}, 'score', {});
gts = struct('image', {}, 'x', {}, 'y', {}, 'radius', {});
odJ = NaN(numel(te), 1);
odErr = NaN(numel(te), 1);
example = [];
fprintf('\nIDRiD segmentation set: %d test images\n', numel(te));
for n = 1:numel(te)
    i = te(n);
    t0 = tic;
    pre = netra.eval.prepareImage(Dseg.file{i}, cfg);
    A = netra.anatomy.analyze(pre.S, pre.E, cfg);
    L = netra.lesions.detectAll(pre.E, A, cfg);
    Dc = size(pre.E.gN, 1);
    SM = netra.lesions.scoreMaps(L, Dc);
    sz = size(pre.rgb(:, :, 1));
    gtAll = struct();
    for t = 1:4
        f = Dseg.masks.(types{t}){i};
        if isempty(f)
            g = false(sz);
        else
            g = netra.io.readMask(f);
        end
        gtAll.(fields{t}) = g;
        s = netra.quality.warpToOriginal(double(SM.(fields{t})), pre.S);
        H{t} = netra.eval.countsPR('add', H{t}, s, g);
    end
    % microaneurysm FROC: reference lesions are the connected components
    lab = bwlabel(gtAll.ma, 8);
    if max(lab(:)) > 0
        st = regionprops(lab, 'Centroid', 'Area');
        for k = 1:numel(st)
            gts(end + 1) = struct('image', n, 'x', st(k).Centroid(1), 'y', st(k).Centroid(2), ...
                'radius', max(2, sqrt(st(k).Area / pi))); %#ok<SAGROW>
        end
    end
    for k = 1:numel(L.ma.list)
        m = L.ma.list(k);
        if strcmp(m.class, 'MA')
            xy = netra.quality.toOriginal(pre.S, [m.x m.y]);
            dets(end + 1) = struct('image', n, 'x', xy(1), 'y', xy(2), 'score', m.prob); %#ok<SAGROW>
        end
    end
    % optic disc: Jaccard and centre error against the OD mask
    if ~isempty(Dseg.masks.OD{i})
        god = netra.io.readMask(Dseg.masks.OD{i});
        pod = netra.quality.warpToOriginal(A.od.mask, pre.S);
        odJ(n) = nnz(god & pod) / max(nnz(god | pod), 1);
        [yy, xx] = find(god);
        c = netra.quality.toOriginal(pre.S, A.od.centre(:)');
        odErr(n) = hypot(c(1) - mean(xx), c(2) - mean(yy));
    end
    if isempty(example) && nnz(gtAll.ma | gtAll.he | gtAll.ex) > 0
        example = struct('rgb', pre.rgb, 'gt', gtAll, 'overlay', netra.xai.overlay(pre.E.display, A, L), ...
            'S', pre.S, 'id', Dseg.id{i});
    end
    fprintf('  %-10s %5.1f s   MA %3d  HE %2d  EX %3d  CWS %d\n', Dseg.id{i}, toc(t0), ...
        L.summary.maCount, L.summary.heTotal, L.summary.exCount, L.summary.cwsCount);
end
seg = struct('type', types, 'aupr', NaN, 'auc', NaN, 'nPos', NaN);
for t = 1:4
    m = netra.eval.countsPR('metrics', H{t});
    seg(t).aupr = m.aupr;
    seg(t).auc = m.auc;
    seg(t).nPos = m.nPos;
end
fr = netra.eval.froc(dets, gts, numel(te));
summary.segmentation = seg;
summary.froc = fr;
summary.odJaccard = odJ;
summary.odCentreErrorPx = odErr;
summary.nSegmentation = numel(te);

fprintf('\nPixel-level AUPR on the IDRiD test images (all pixels, native resolution)\n');
fprintf('  %-4s %8s %8s %12s\n', 'type', 'AUPR', 'ROC AUC', 'lesion px');
for t = 1:4
    fprintf('  %-4s %8.4f %8.4f %12d\n', seg(t).type, seg(t).aupr, seg(t).auc, seg(t).nPos);
end
fprintf('Microaneurysm FROC: mean sensitivity %.3f over 1/8..8 false positives per image\n', fr.score);
fprintf('Optic disc: Jaccard %.3f (median %.3f), centre error median %.0f px\n', ...
    mean(odJ, 'omitnan'), median(odJ(~isnan(odJ))), median(odErr(~isnan(odErr))));
fprintf('\nBest challenge entries (deep networks trained on IDRiD; context):\n');
netra.eval.benchmarks('Task', 'lesion-seg');

% ============================================= B. landmark localisation
Dloc = netra.io.idrid(dataIDRiD, 'localization');
te = find(strcmp(Dloc.split, 'test') & ~isnan(Dloc.od(:, 1)));
if isempty(te)
    te = find(~isnan(Dloc.od(:, 1)));
end
te = te(1:min(numel(te), maxImages));
eOD = NaN(numel(te), 1);
eFv = NaN(numel(te), 1);
dd = NaN(numel(te), 1);
fprintf('\nIDRiD localisation set: %d test images\n', numel(te));
for n = 1:numel(te)
    i = te(n);
    pre = netra.eval.prepareImage(Dloc.file{i}, cfg);
    A = netra.anatomy.analyze(pre.S, pre.E, cfg);
    od = netra.quality.toOriginal(pre.S, A.od.centre(:)');
    fv = netra.quality.toOriginal(pre.S, A.fovea.centre(:)');
    dd(n) = cfg.scale.ddPerFOV * 2 * pre.F.radius;       % one disc diameter, original px
    eOD(n) = hypot(od(1) - Dloc.od(i, 1), od(2) - Dloc.od(i, 2));
    eFv(n) = hypot(fv(1) - Dloc.fovea(i, 1), fv(2) - Dloc.fovea(i, 2));
end
within = @(e, f) mean(e(~isnan(e)) <= f * dd(~isnan(e)));
loc = struct('landmark', {'optic disc', 'fovea'}, 'medianPx', {median(eOD(~isnan(eOD))), ...
    median(eFv(~isnan(eFv)))}, 'meanPx', {mean(eOD, 'omitnan'), mean(eFv, 'omitnan')}, ...
    'medianDD', {median(eOD(~isnan(eOD)) ./ dd(~isnan(eOD))), median(eFv(~isnan(eFv)) ./ dd(~isnan(eFv)))}, ...
    'within8', {within(eOD, 1 / 8), within(eFv, 1 / 8)}, 'within4', {within(eOD, 1 / 4), within(eFv, 1 / 4)}, ...
    'within2', {within(eOD, 1 / 2), within(eFv, 1 / 2)});
summary.localisation = loc;
summary.nLocalisation = numel(te);
fprintf('  %-10s %10s %10s %10s %9s %9s %9s\n', 'landmark', 'median px', 'mean px', 'median DD', ...
    '<1/8 DD', '<1/4 DD', '<1/2 DD');
for k = 1:2
    l = loc(k);
    fprintf('  %-10s %10.1f %10.1f %10.3f %8.0f%% %8.0f%% %8.0f%%\n', l.landmark, l.medianPx, ...
        l.meanPx, l.medianDD, 100 * l.within8, 100 * l.within4, 100 * l.within2);
end

% ------------------------------------------------------------ outputs
fid = fopen(fullfile(outDir, 'lesions_idrid.csv'), 'w');
fprintf(fid, 'type,aupr,auc,lesionPixels\n');
for t = 1:4
    fprintf(fid, '%s,%.5f,%.5f,%d\n', seg(t).type, seg(t).aupr, seg(t).auc, seg(t).nPos);
end
fprintf(fid, 'MA_FROC,%.5f,,\n', fr.score);
fprintf(fid, 'OD_Jaccard,%.5f,,\n', mean(odJ, 'omitnan'));
fclose(fid);
fid = fopen(fullfile(outDir, 'localisation_idrid.csv'), 'w');
fprintf(fid, 'landmark,medianPx,meanPx,medianDD,within8,within4,within2\n');
for k = 1:2
    l = loc(k);
    fprintf(fid, '%s,%.2f,%.2f,%.4f,%.4f,%.4f,%.4f\n', l.landmark, l.medianPx, l.meanPx, ...
        l.medianDD, l.within8, l.within4, l.within2);
end
fclose(fid);
save(fullfile(outDir, 'summary.mat'), 'summary', '-v7');
if ~isempty(example)
    pal = netra.util.palette();
    g = example.gt;
    ref = repmat(reshape(pal.ink, 1, 1, 3), size(g.ma));
    order = {'se', 'cws'; 'ex', 'exudate'; 'he', 'blot'; 'ma', 'ma'};
    for k = 1:size(order, 1)
        mk = imdilate(g.(order{k, 1}), strel('disk', 2, 0));
        for c = 1:3
            ch = ref(:, :, c);
            ch(mk) = pal.(order{k, 2})(c);
            ref(:, :, c) = ch;
        end
    end
    ov = netra.quality.warpToOriginal(example.overlay, example.S);
    imwrite(netra.util.montage({example.rgb, ref, ov}, 3), fullfile(outDir, 'example.png'));
end
fprintf('Saved %s\n', outDir);
