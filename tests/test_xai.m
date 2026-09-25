% Explainability primitives: CAM arithmetic, the ordinal loss, maps and
% overlays (the Grad-CAM forward/backward pass itself needs MATLAB's Deep
% Learning Toolbox and is exercised by exp05).

%% Grad-CAM weights channels by their mean gradient and keeps positive evidence
A = zeros(4, 4, 2);
A(1, 1, 1) = 1;                      % channel 1 fires top-left
A(4, 4, 2) = 1;                      % channel 2 fires bottom-right
G = cat(3, ones(4), -ones(4));       % only channel 1 supports the target
cam = netra.xai.camFromGradients(A, G, 'gradcam');
assert(cam(1, 1) == 1 && cam(4, 4) == 0 && all(cam(:) >= 0 & cam(:) <= 1));

%% Grad-CAM++ spreads credit over several positive regions of one channel
A = zeros(6, 6, 1);
A(1, 1) = 1; A(6, 6) = 0.5;
G = ones(6, 6, 1);
cam = netra.xai.camFromGradients(A, G, 'gradcam++');
assert(cam(1, 1) == 1 && abs(cam(6, 6) - 0.5) < 1e-12);
cam0 = netra.xai.camFromGradients(A, -G, 'gradcam++');
assert(all(cam0(:) == 0), 'no positive evidence, no map');

%% Ordinal loss: farther mistakes cost more, perfect answers cost least
T = zeros(5, 1); T(3) = 1;                      % truth: grade 2
near = [0.05 0.05 0.1 0.75 0.05]';              % mostly grade 3
far = [0.75 0.05 0.1 0.05 0.05]';               % mostly grade 0
cost = ((repmat((0:4)', 1, 5) - repmat(0:4, 5, 1)) / 4) .^ 2;
w = ones(5, 1);
lNear = netra.grading.cnn.lossFcn(near, T, w, 0.5, cost);
lFar = netra.grading.cnn.lossFcn(far, T, w, 0.5, cost);
lGood = netra.grading.cnn.lossFcn([0.02 0.03 0.9 0.03 0.02]', T, w, 0.5, cost);
assert(lGood < lNear && lNear < lFar, 'losses %.3f %.3f %.3f', lGood, lNear, lFar);
lCE = netra.grading.cnn.lossFcn(far, T, w, 0, cost);
assert(abs(lCE - (-log(0.1))) < 1e-5, 'lambda 0 is plain cross-entropy');

%% Heat overlay keeps the retina visible where the map is low
base = 0.5 * ones(32, 32, 3);
map = zeros(32);
map(10:20, 10:20) = 1;
img = netra.xai.heat(base, map);
assert(isequal(size(img), size(base)) && all(img(:) >= 0 & img(:) <= 1));
assert(max(abs(reshape(img(1:5, 1:5, :) - base(1:5, 1:5, :), 1, []))) < 1e-12);
assert(max(abs(reshape(img(15, 15, :) - base(15, 15, :), 1, []))) > 0.1);

%% Attention-evidence concordance rewards attention on the lesions
cfg = netra.config();
fov = true(64);
masks = struct('ma', false(64), 'he', false(64), 'ex', false(64), 'cws', false(64), 'nv', false(64));
masks.he(20:26, 20:26) = true;
[X, Y] = meshgrid(1:64, 1:64);
on = exp(-((X - 23) .^ 2 + (Y - 23) .^ 2) / (2 * 4 ^ 2));      % attention on the haemorrhage
off = exp(-((X - 52) .^ 2 + (Y - 52) .^ 2) / (2 * 4 ^ 2));     % attention elsewhere
off(off < 0.05) = 0;
c1 = netra.xai.concordance(on, masks, fov, cfg);
c2 = netra.xai.concordance(off, masks, fov, cfg);
assert(c1.score > c2.score && c1.pointingHit && ~c2.pointingHit && c2.flag);

%% Every patient-facing string exists in English and Hindi
keys = {'triage.ROUTINE', 'triage.REFER', 'triage.REFER_DME', 'triage.URGENT', 'triage.HUMAN_REVIEW', ...
    'triage.RECAPTURE', 'dme', 'grade.0', 'grade.4', 'fb.blur', 'fb.dark', 'brand'};
for k = 1:numel(keys)
    assert(~isempty(netra.util.i18n(keys{k}, 'en')) && ~isempty(netra.util.i18n(keys{k}, 'hi')), keys{k});
end
