function file = exportCase(R, folder)
%EXPORTCASE Save the slim, reader-facing part of a screening result.
%   file = netra.ui.exportCase(R, folder) writes <folder>/<id>.mat with the
%   images and facts the Reader Console shows (annotated, enhanced and raw
%   canvas crops, attention map, grade distribution, conformal set,
%   criteria, reasons, quality, patient messages) - about 1 MB per eye
%   instead of the full result, so a day's queue fits on a USB stick or can
%   be synced over a slow link.
if ~exist(folder, 'dir')
    mkdir(folder);
end
id = R.meta.id;
if isempty(id)
    id = ['case_' datestr(now, 'yyyymmdd_HHMMSSFFF')];
end
C = struct();
C.id = id;
C.meta = R.meta;
C.decision = R.decision;
C.quality = struct('score', R.quality.score, 'decision', R.quality.decision, ...
    'sub', R.quality.sub, 'feedback', R.quality.feedback);
if isfield(R, 'fusion')
    crop = @(img) cropFOV(img, R.canvas);
    C.images = struct('raw', im2uint8(crop(R.canvas.rgb)), ...
        'enhanced', im2uint8(crop(R.canvas.display)), ...
        'lesions', im2uint8(crop(R.overlay)));
    if ~isempty(R.xai.cam)
        C.images.attention = im2uint8(crop(netra.xai.heat(R.canvas.display, R.xai.cam)));
        C.attentionKind = 'Grad-CAM++';
    else
        C.images.attention = im2uint8(crop(netra.xai.heat(R.canvas.display, R.xai.evidence)));
        C.attentionKind = 'lesion evidence';
    end
    C.P = R.fusion.P;
    C.grade = R.fusion.grade;
    C.conformalSet = R.conformalSet;
    C.criteria = R.rules.criteria;
    C.evidence = R.rules.evidence;
    C.dme = R.rules.dme;
    C.summary = R.lesions.summary;
    C.concordance = R.xai.concordance;
    C.models = R.models;
else
    C.images = struct('raw', im2uint8(R.thumbnail), 'enhanced', im2uint8(R.thumbnail), ...
        'lesions', im2uint8(R.thumbnail), 'attention', im2uint8(R.thumbnail));
    C.attentionKind = '';
    C.P = nan(1, 5);
    C.grade = NaN;
    C.conformalSet = [];
    C.criteria = struct('id', {}, 'level', {}, 'text', {}, 'value', {}, ...
        'threshold', {}, 'met', {}, 'margin', {});
    C.evidence = {};
    C.dme = 0;
    C.summary = struct();
    C.concordance = struct();
    C.models = struct();
end
file = fullfile(folder, [regexprep(id, '[^\w\-]', '_') '.mat']);
save(file, 'C');
end

function img = cropFOV(img, cv)
c = cv.centre;
r = cv.radius * 1.01;
D = size(img, 1);
r1 = max(1, round(c(2) - r)); r2 = min(D, round(c(2) + r));
c1 = max(1, round(c(1) - r)); c2 = min(D, round(c(1) + r));
img = img(r1:r2, c1:c2, :);
end
