function fig = reportFigure(R, varargin)
%REPORTFIGURE One-page screening report (A4 landscape) for one eye.
%
%   fig = netra.xai.reportFigure(R)                 R from netra.screen
%   netra.xai.reportFigure(R, 'File', 'report.png') also saves (png / pdf)
%
%   Layout, designed so a reader can confirm or override in under 30 s:
%     band      programme, patient id, eye, time, site
%     banner    triage in its colour, follow-up, patient message (EN + HI)
%     left      annotated fundus: disc, fovea, ETDRS grid, every lesion
%     right     where the network looked (Grad-CAM++) or, without a CNN,
%               where the detectors found disease; grade probabilities with
%               the conformal set; the ICDR criteria with measured values;
%               image quality; how the result was produced
%     footer    disclaimer and the reviewer's sign-off line
%   Drawn with axes, patches and text only, so it renders identically in
%   MATLAB and GNU Octave. Figure text is not shaped for Devanagari, so the
%   Hindi patient message is carried by netra.xai.reportHTML; set
%   cfg.report.hindiInFigure = true to add it here as well (needs a
%   Devanagari font: Nirmala UI, Kohinoor Devanagari or Noto Sans Devanagari).

o = netra.util.opts(struct('File', '', 'Visible', 'off', 'DPI', 150), varargin{:});
P = netra.util.palette();
cfg = R.cfg;
W = 1754; H = 1240;                                   % A4 landscape at 150 dpi
fig = figure('Color', P.paper, 'Units', 'pixels', 'Position', [20 20 W H], ...
    'Visible', o.Visible, 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto', ...
    'MenuBar', 'none', 'NumberTitle', 'off', 'Name', 'NetraSetu report');
base = axes('Parent', fig, 'Position', [0 0 1 1], 'XLim', [0 1], 'YLim', [0 1], ...
    'Visible', 'off');
hold(base, 'on');
fontUI = uiFont();
% Devanagari needs complex-script shaping (pre-base vowel signs, conjuncts)
% that MATLAB/Octave figure text does not perform; unshaped Hindi reads as
% misspelt. Hindi therefore goes to the HTML report (browser shaping) and
% appears here only when explicitly enabled.
fontHi = '';
if isfield(cfg.report, 'hindiInFigure') && cfg.report.hindiInFigure
    fontHi = devanagariFont();
end
T = R.decision;

% ------------------------------------------------------------------ band
box(base, [0 0.915 1 0.085], P.ink);
txt(base, 0.022, 0.962, 'NetraSetu', 30, [1 1 1], 'bold', fontUI);
if ~isempty(fontHi)
    txt(base, 0.132, 0.962, netra.util.i18n('brand', 'hi'), 22, P.saffron, 'normal', fontHi);
end
txt(base, 0.022, 0.93, upper('Diabetic retinopathy screening report'), 11, P.saffron, 'bold', fontUI);
meta = sprintf('%s   |   Eye %s   |   %s   |   %s', valueOr(R.meta.id, 'unnamed'), ...
    valueOr(R.meta.eye, eyeOf(R)), R.meta.time, valueOr(R.meta.site, cfg.report.site));
txt(base, 0.978, 0.962, meta, 13, [1 1 1], 'normal', fontUI, 'right');
txt(base, 0.978, 0.93, cfg.report.programme, 11, [0.78 0.80 0.88], 'normal', fontUI, 'right');

% ---------------------------------------------------------------- banner
box(base, [0.02 0.832 0.96 0.07], T.colour);
label = strrep(T.triage, '_', ' ');
txt(base, 0.035, 0.878, label, 26, [1 1 1], 'bold', fontUI);
txt(base, 0.035, 0.846, T.followUp, 13, [1 1 1], 'normal', fontUI);
txt(base, 0.30, 0.878, T.message.en, 13, [1 1 1], 'normal', fontUI);
if ~isempty(fontHi)
    txt(base, 0.30, 0.849, T.message.hi, 13, [1 1 1], 'normal', fontHi);
end

% ------------------------------------------------------- recapture only
if strcmp(T.triage, 'RECAPTURE')
    ax = axes('Parent', fig, 'Position', [0.02 0.12 0.46 0.68]);
    image(ax, R.thumbnail);
    axis(ax, 'image', 'off');
    txt(base, 0.52, 0.78, 'Why the photograph cannot be graded', 18, P.ink, 'bold', fontUI);
    y = 0.73;
    for k = 1:numel(R.quality.feedback)
        f = R.quality.feedback(k);
        txt(base, 0.52, y, ['- ' f.en], 13, P.ink, 'normal', fontUI);
        if ~isempty(fontHi)
            txt(base, 0.535, y - 0.03, f.hi, 12, P.inkSoft, 'normal', fontHi);
        end
        y = y - 0.08;
    end
    qualityBars(base, R.quality, 0.52, 0.30, 0.40, P, fontUI);
    footer(base, R, P, fontUI);
    export(fig, o);
    return
end

% ------------------------------------------------------ annotated fundus
ax = axes('Parent', fig, 'Position', [0.02 0.115 0.47 0.705]);
image(ax, cropToFOV(R.overlay, R.canvas));
axis(ax, 'image', 'off');
txt(base, 0.022, 0.108, 'Detected lesions', 11, P.inkSoft, 'bold', fontUI);
s = R.lesions.summary;
chips = {
    P.ma,      sprintf('Microaneurysms %d', s.maCount)
    P.blot,    sprintf('Haemorrhages %d', s.heTotal)
    P.exudate, sprintf('Hard exudates %d', s.exCount)
    P.cws,     sprintf('Cotton-wool spots %d', s.cwsCount)
    P.nv,      sprintf('New vessels p=%.2f', max(s.nvdProb, s.nveProb))
    P.vb,      sprintf('Beaded veins %dq', numel(s.vbQuadrants))};
for k = 1:size(chips, 1)
    col = mod(k - 1, 3);
    row = floor((k - 1) / 3);
    x = 0.022 + col * 0.158;
    y = 0.080 - row * 0.03;
    box(base, [x y - 0.008 0.012 0.016], chips{k, 1});
    txt(base, x + 0.018, y, chips{k, 2}, 11, P.ink, 'normal', fontUI);
end

% --------------------------------------------------------- attention map
ax2 = axes('Parent', fig, 'Position', [0.515 0.515 0.215 0.305]);
if ~isempty(R.xai.cam)
    hm = netra.xai.heat(R.canvas.display, R.xai.cam);
    ttl = 'Where the network looked (Grad-CAM++)';
else
    hm = netra.xai.heat(R.canvas.display, R.xai.evidence);
    ttl = 'Where the detectors found disease';
end
image(ax2, cropToFOV(hm, R.canvas));
axis(ax2, 'image', 'off');
txt(base, 0.515, 0.508, ttl, 11, P.inkSoft, 'bold', fontUI);
if isfield(R.xai.concordance, 'score') && ~isnan(R.xai.concordance.score)
    c = R.xai.concordance;
    txt(base, 0.515, 0.488, sprintf('Attention on lesions: %.0f %% of energy, %.0f %% of lesions', ...
        100 * c.energyInLesions, 100 * c.lesionRecall), 10, P.inkSoft, 'normal', fontUI);
end

% ------------------------------------------------- grade probabilities
gradeBars(base, R, 0.755, 0.56, 0.225, 0.25, P, fontUI);

% ------------------------------------------------------ ICDR criteria
txt(base, 0.515, 0.452, 'ICDR criteria (single-field adaptation)', 13, P.ink, 'bold', fontUI);
C = R.rules.criteria;
y = 0.42;
% rows share the space down to the quality block (the DME line is one more)
nRows = numel(C) + double(R.rules.dme > 0);
dy = min(0.029, (0.42 - 0.19) / max(nRows - 1, 1));
for k = 1:numel(C)
    if C(k).met
        dot = P.(ifelse(C(k).level >= 3, 'URGENT', ifelse(C(k).level == 2, 'REFER', 'ROUTINE')));
    else
        dot = P.rule;
    end
    circle(base, 0.522, y, 0.0055, dot);
    t = C(k).text;
    if numel(t) > 88
        t = [t(1:85) '...'];
    end
    txt(base, 0.533, y, t, 10.5, ifelse(C(k).met, P.ink, P.inkSoft), ...
        ifelse(C(k).met, 'bold', 'normal'), fontUI);
    txt(base, 0.975, y, sprintf('level %d', C(k).level), 9.5, P.inkSoft, 'normal', fontUI, 'right');
    y = y - dy;
end
if R.rules.dme > 0
    txt(base, 0.533, y, sprintf('Macular oedema risk %d (nearest exudate %.2f DD from the fovea)', ...
        R.rules.dme, s.exMinDistFoveaDD), 10.5, P.ink, 'bold', fontUI);
end

% ------------------------------------------------ quality + provenance
qualityBars(base, R.quality, 0.515, 0.075, 0.2, P, fontUI);
prov = provenance(R);
txt(base, 0.74, 0.155, 'How this result was produced', 11, P.inkSoft, 'bold', fontUI);
for k = 1:numel(prov)
    txt(base, 0.74, 0.13 - 0.021 * (k - 1), prov{k}, 9.5, P.ink, 'normal', fontUI);
end

footer(base, R, P, fontUI);
export(fig, o);
end

% ======================================================================
function img = cropToFOV(img, cv)
c = cv.centre;
r = cv.radius * 1.01;
D = size(img, 1);
r1 = max(1, round(c(2) - r)); r2 = min(D, round(c(2) + r));
c1 = max(1, round(c(1) - r)); c2 = min(D, round(c(1) + r));
img = img(r1:r2, c1:c2, :);
end

function gradeBars(ax, R, x0, y0, w, h, P, font)
txt(ax, x0, y0 + h + 0.012, 'Severity (ICDR)', 13, P.ink, 'bold', font);
p = R.fusion.P;
bw = w / 5 * 0.62;
names = {'0', '1', '2', '3', '4'};
long = {'none', 'mild', 'moderate', 'severe', 'PDR'};
for k = 1:5
    x = x0 + (k - 0.5) * w / 5 - bw / 2;
    box(ax, [x y0 bw h * 0.78], P.rule);
    box(ax, [x y0 bw max(h * 0.78 * p(k), 0.001)], P.grades(k, :));
    txt(ax, x + bw / 2, y0 + h * 0.78 * p(k) + 0.014, sprintf('%.0f%%', 100 * p(k)), 10, P.ink, ...
        'bold', font, 'center');
    txt(ax, x + bw / 2, y0 - 0.014, names{k}, 12, P.ink, 'bold', font, 'center');
    txt(ax, x + bw / 2, y0 - 0.034, long{k}, 9, P.inkSoft, 'normal', font, 'center');
end
cs = R.conformalSet;
if ~isempty(cs) && any(cs)
    f = find(cs, 1, 'first');
    l = find(cs, 1, 'last');
    xa = x0 + (f - 1) * w / 5 + 0.004;
    xb = x0 + l * w / 5 - 0.004;
    yb = y0 + h * 0.86;
    line(ax, [xa xb], [yb yb], 'Color', P.ink, 'LineWidth', 1.5);
    line(ax, [xa xa], [yb - 0.008 yb], 'Color', P.ink, 'LineWidth', 1.5);
    line(ax, [xb xb], [yb - 0.008 yb], 'Color', P.ink, 'LineWidth', 1.5);
    txt(ax, (xa + xb) / 2, yb + 0.013, sprintf('%.0f %% conformal set', 100 * (1 - R.cfg.grading.conformalAlpha)), ...
        9, P.ink, 'normal', font, 'center');
end
txt(ax, x0, y0 - 0.058, sprintf('P(referable) %.2f   |   grade %d   |   referral threshold %.2f', ...
    R.decision.pReferable, R.fusion.grade, R.cfg.grading.referralThreshold), 10, P.ink, 'normal', font);
end

function qualityBars(ax, Q, x0, y0, w, P, font)
txt(ax, x0, y0 + 0.08, sprintf('Image quality %.2f  (%s)', Q.score, lower(Q.decision)), 11, ...
    P.inkSoft, 'bold', font);
names = {'field', 'focus', 'illumination', 'contrast', 'artifact'};
for k = 1:numel(names)
    y = y0 + 0.055 - (k - 1) * 0.016;
    v = Q.sub.(names{k});
    txt(ax, x0, y, names{k}, 9, P.inkSoft, 'normal', font);
    box(ax, [x0 + 0.06 y - 0.004 w - 0.06 0.008], P.rule);
    col = P.ROUTINE;
    if v < 0.5, col = P.URGENT; elseif v < 0.8, col = P.REFER; end
    box(ax, [x0 + 0.06 y - 0.004 (w - 0.06) * max(v, 0.005) 0.008], col);
end
end

function prov = provenance(R)
m = R.models;
parts = {'rules'};
if m.lesion, parts{end + 1} = 'lesion ensemble'; end
if m.cnn, parts{end + 1} = 'CNN'; end
prov = {sprintf('Grade from: %s (%s)', strjoin(parts, ' + '), R.fusion.method)};
if ~m.cnn && ~m.lesion
    prov{end + 1} = 'No trained models loaded: rule engine only, not clinically validated';
end
if m.calibration
    prov{end + 1} = 'Calibrated: temperature, conformal set, validated operating point';
end
prov{end + 1} = sprintf('Disc-fovea %.2f DD, disc confidence %.2f, fovea %.2f, eye %s', ...
    R.anatomy.fovea.distanceDD, R.anatomy.od.confidence, R.anatomy.fovea.confidence, ...
    R.anatomy.frame.eye);
prov{end + 1} = sprintf('Analysis %.1f s  |  NetraSetu %s', R.timing.total, R.meta.version);
end

function footer(ax, R, P, font)
line(ax, [0.02 0.98], [0.042 0.042], 'Color', P.rule, 'LineWidth', 1);
txt(ax, 0.02, 0.025, R.cfg.report.disclaimer, 9.5, P.inkSoft, 'normal', font);
txt(ax, 0.98, 0.025, 'Reviewer ____________   Agree [ ]   Override grade [  ]   Time ____ s', ...
    10, P.ink, 'normal', font, 'right');
end

function h = txt(ax, x, y, s, sz, col, weight, font, align)
if nargin < 9
    align = 'left';
end
h = text(ax, x, y, s, 'FontSize', sz, 'Color', col, 'FontWeight', weight, ...
    'FontName', font, 'HorizontalAlignment', align, 'VerticalAlignment', 'middle', ...
    'Interpreter', 'none');
end

function box(ax, pos, col)
patch(ax, pos(1) + [0 pos(3) pos(3) 0], pos(2) + [0 0 pos(4) pos(4)], col, ...
    'EdgeColor', 'none');
end

function circle(ax, x, y, r, col)
t = linspace(0, 2 * pi, 24);
ar = 1754 / 1240;
patch(ax, x + r * cos(t), y + r * ar * sin(t), col, 'EdgeColor', 'none');
end

function v = ifelse(c, a, b)
if c
    v = a;
else
    v = b;
end
end

function v = valueOr(v, d)
if isempty(v)
    v = d;
end
end

function e = eyeOf(R)
e = '?';
if isfield(R, 'anatomy')
    e = [R.anatomy.frame.eye ' (inferred)'];
end
end

function f = uiFont()
f = 'Helvetica';
cands = {'Inter', 'Segoe UI', 'Helvetica Neue', 'Noto Sans', 'DejaVu Sans', 'Arial'};
avail = fontsAvailable();
for k = 1:numel(cands)
    if any(strcmpi(avail, cands{k}))
        f = cands{k};
        return
    end
end
end

function f = devanagariFont()
f = '';
cands = {'Nirmala UI', 'Kohinoor Devanagari', 'Noto Sans Devanagari', 'Mangal', 'Lohit Devanagari'};
avail = fontsAvailable();
for k = 1:numel(cands)
    if any(strcmpi(avail, cands{k}))
        f = cands{k};
        return
    end
end
end

function list = fontsAvailable()
persistent cache
if isempty(cache)
    cache = {};
    try
        if netra.util.isOctave()
            [~, out] = system('fc-list : family');
            cache = strtrim(strsplit(out, sprintf('\n')));
            cache = regexprep(cache, ',.*$', '');
        else
            cache = listfonts();
        end
    catch
        cache = {};
    end
end
list = cache;
end

function export(fig, o)
if isempty(o.File)
    return
end
[~, ~, ext] = fileparts(o.File);
if netra.util.has('exportgraphics')
    if strcmpi(ext, '.pdf')
        exportgraphics(fig, o.File, 'ContentType', 'image', 'Resolution', o.DPI);
    else
        exportgraphics(fig, o.File, 'Resolution', o.DPI);
    end
else
    fmt = '-dpng';
    if strcmpi(ext, '.pdf'), fmt = '-dpdf'; end
    print(fig, o.File, fmt, sprintf('-r%d', o.DPI));
end
end
