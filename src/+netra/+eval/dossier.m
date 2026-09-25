function file = dossier(varargin)
%DOSSIER Self-contained HTML validation dossier from the experiment results.
%
%   file = netra.eval.dossier()                        results/validation_dossier.html
%   file = netra.eval.dossier('Results', dir, 'File', f)
%
%   Reads whatever experiments have been run (results/exp0*/summary.mat and
%   their figures) and writes one page a programme officer, an ethics
%   committee or a reviewer can open offline: headline accuracy against
%   the target, every test set with confidence intervals, the ablation
%   that shows what integration adds, vessel / lesion / landmark accuracy,
%   explanation quality, the district plan, the published context and the
%   limitations. Figures are embedded, so the file can be e-mailed.
cfg = netra.config();
o = netra.util.opts(struct('Results', cfg.paths.results, 'File', ''), varargin{:});
file = o.File;
if isempty(file)
    file = fullfile(o.Results, 'validation_dossier.html');
end
P = netra.util.palette();
hex = @(c) sprintf('#%02X%02X%02X', round(255 * c));
M = netra.loadModels(cfg);
target = [0.90 0.85];

h = {};
h{end + 1} = ['<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">' ...
    '<meta name="viewport" content="width=device-width,initial-scale=1">' ...
    '<title>NetraSetu validation dossier</title><style>' css(P, hex) '</style></head><body>'];
h{end + 1} = sprintf(['<header><div class="brand">NetraSetu</div><div class="meta">Validation dossier' ...
    ' &middot; version %s &middot; generated %s</div></header><main>'], netra.version(), ...
    datestr(now, 'dd mmm yyyy HH:MM'));
h{end + 1} = ['<p class="lede">Explainable AI screening for diabetic retinopathy: what was measured, on ' ...
    'which images, with which uncertainty. Every figure on this page was produced by ' ...
    '<code>experiments/run_all.m</code> on this machine; sections without data say which experiment ' ...
    'to run.</p>'];
st = M.status;
h{end + 1} = ['<p class="models">Components in this build: ' chip('rule engine', true) ...
    chip('lesion ensemble', st.lesion) chip('CNN', st.cnn) chip('fusion', st.fusion) ...
    chip('calibration', st.calibration) chip('vessel fusion (DRIVE)', st.vessel) ...
    chip('NV normative model', st.nvNormative) '</p>'];

% ------------------------------------------------------ clinical validation
S4 = loadSummary(o.Results, 'exp04', 'results');
h{end + 1} = '<section><h2>1 &nbsp;Referable diabetic retinopathy</h2>';
if isempty(S4)
    h{end + 1} = missing('experiments/exp04_validate_grading.m (after exp03)');
else
    keys = fieldnames(S4);
    ext = keys{end};
    for k = {'messidor2', 'idrid', 'aptos'}
        if isfield(S4, k{1})
            ext = k{1};
            break
        end
    end
    E = S4.(ext);
    t = E.deployed.triage;
    h{end + 1} = '<div class="tiles">';
    h{end + 1} = tile(sprintf('%.1f%%', 100 * t.se), sprintf('sensitivity, %s (95%% CI %.1f-%.1f)', ...
        E.label, 100 * t.seCI), t.seCI(1) >= target(1), t.se >= target(1));
    h{end + 1} = tile(sprintf('%.1f%%', 100 * t.sp), sprintf('specificity (95%% CI %.1f-%.1f)', ...
        100 * t.spCI), t.spCI(1) >= target(2), t.sp >= target(2));
    h{end + 1} = tile(sprintf('%.3f', E.deployed.auc), sprintf('ROC AUC (%.3f-%.3f)', E.deployed.aucCI), [], []);
    h{end + 1} = tile(sprintf('%.0f%%', 100 * E.deployed.humanReview), 'of eyes routed to a human (uncertain)', [], []);
    h{end + 1} = '</div>';
    h{end + 1} = sprintf(['<p class="note">Target: sensitivity &gt; %.0f %% and specificity &gt; %.0f %% for ' ...
        'referable DR (ICDR grade &ge; 2 or referable DME). A tick needs the whole 95 %% confidence ' ...
        'interval above the target; a point estimate above it with an interval that crosses it is marked ' ...
        '&ldquo;not yet shown&rdquo;. Sensitivity and specificity here are for the triage decision: an eye is ' ...
        'cleared only when the pipeline says ROUTINE.</p>'], 100 * target);
    for k = 1:numel(keys)
        R = S4.(keys{k});
        f = R.flow;
        Dp = R.deployed;
        h{end + 1} = sprintf('<h3>%s</h3><p class="flow">%d images &rarr; %d without a reference grade &rarr; %d sent for recapture &rarr; %d failed &rarr; <b>%d analysed</b> (%d referable, %d not)</p>', ...
            esc(R.label), f.images, f.referenceUngradable, f.recapture, f.failed, f.analysed, ...
            f.referable, f.nonReferable);
        rows = {'Model alone (P &ge; threshold)', Dp.ai; 'Triage: not auto-cleared', Dp.triage; ...
            'Intention to screen (recapture = refer)', Dp.itt};
        if isfield(R, 'patient')
            rows(end + 1, :) = {'Per patient (either eye)', R.patient};
        end
        body = {};
        for r = 1:size(rows, 1)
            m = rows{r, 2};
            body(end + 1, :) = {rows{r, 1}, ci(m.se, m.seCI), ci(m.sp, m.spCI), ...
                sprintf('%d / %d', m.tp, m.nPos), sprintf('%d / %d', m.tn, m.nNeg)}; %#ok<AGROW>
        end
        h{end + 1} = table_({'Decision', 'Sensitivity', 'Specificity', 'Referable found', ...
            'Non-referable cleared'}, body);
        h{end + 1} = sprintf(['<p class="kv">AUC <b>%.3f</b> (%.3f-%.3f) &middot; five-level QWK <b>%.3f</b> ' ...
            '(%.3f-%.3f) &middot; calibration error (ECE) %.3f &middot; Brier %.3f &middot; conformal ' ...
            'coverage %.3f with %.2f grades per set</p>'], Dp.auc, Dp.aucCI, Dp.qwk, Dp.qwkCI(1:2), ...
            Dp.calibration.ece, Dp.calibration.brier, Dp.conformal.coverage, Dp.conformal.meanSize);
        if ~isempty(R.variants)
            body = {};
            for v = 1:numel(R.variants)
                x = R.variants(v);
                pd = '&mdash;';
                pm = '&mdash;';
                if ~isnan(x.pDeLong)
                    pd = pfmt(x.pDeLong);
                    pm = sprintf('%s / %s', pfmt(x.mcnemarSe.p), pfmt(x.mcnemarSp.p));
                end
                body(end + 1, :) = {esc(x.name), sprintf('%.3f (%.3f-%.3f)', x.auc, x.aucCI), pd, ...
                    ci(x.se, x.seCI), ci(x.sp, x.spCI), pm}; %#ok<AGROW>
            end
            h{end + 1} = '<h4>Integration vs each technique alone (same eyes)</h4>';
            h{end + 1} = table_({'Variant', 'AUC (95% CI)', 'DeLong p vs deployed', 'Sensitivity', ...
                'Specificity', 'McNemar p (Se / Sp)'}, body);
        end
        img = fullfile(o.Results, 'exp04', ['roc_' keys{k} '.png']);
        h{end + 1} = figureHTML(img, sprintf('ROC of the deployed pipeline and the single techniques, %s', R.label));
    end
end
h{end + 1} = '</section>';

% ---------------------------------------------------------------- vessels
S1 = loadSummary(o.Results, 'exp01', 'summary');
h{end + 1} = '<section><h2>2 &nbsp;Vessel segmentation (DRIVE)</h2>';
if isempty(S1)
    h{end + 1} = missing('experiments/exp01_vessels_drive.m');
else
    body = {};
    for v = 1:numel(S1.rows)
        r = S1.rows(v);
        d = '&mdash;';
        if ~isnan(r.p)
            d = sprintf('%+.4f (%+.4f to %+.4f), p %s', r.dAUC, r.dCI, pfmt(r.p));
        end
        body(end + 1, :) = {esc(r.label), sprintf('%.4f', r.aucPooled), sprintf('%.4f', r.se), ...
            sprintf('%.4f', r.sp), sprintf('%.4f', r.acc), d}; %#ok<AGROW>
    end
    if isfield(S1, 'secondObserver')
        m = S1.secondObserver;
        body(end + 1, :) = {'Second human observer', '&mdash;', sprintf('%.4f', m.se), ...
            sprintf('%.4f', m.sp), sprintf('%.4f', m.acc), ''};
    end
    h{end + 1} = sprintf('<p class="note">%d test images, pixels inside the FOV; thresholds chosen on the %d training images.</p>', ...
        S1.nTest, S1.nTrain);
    h{end + 1} = table_({'Detector', 'AUC', 'Se', 'Sp', 'Acc', 'Fusion minus this: mean AUC (95% CI)'}, body);
    h{end + 1} = figureHTML(fullfile(o.Results, 'exp01', 'example.png'), ...
        'Photograph, reference, learned fusion, Frangi, line detector, top-hat');
end
h{end + 1} = '</section>';

% ------------------------------------------------------ lesions, landmarks
S2 = loadSummary(o.Results, 'exp02', 'summary');
h{end + 1} = '<section><h2>3 &nbsp;Lesions and landmarks (IDRiD)</h2>';
if isempty(S2)
    h{end + 1} = missing('experiments/exp02_lesions_idrid.m');
else
    B = netra.eval.benchmarks('Task', 'lesion-seg');
    body = {};
    for t = 1:numel(S2.segmentation)
        s = S2.segmentation(t);
        body(end + 1, :) = {s.type, sprintf('%.3f', s.aupr), sprintf('%.3f', B(t).value)}; %#ok<AGROW>
    end
    h{end + 1} = sprintf('<p class="note">%d test images at native resolution. Microaneurysm FROC score %.3f. Optic-disc Jaccard %.3f.</p>', ...
        S2.nSegmentation, S2.froc.score, mean(S2.odJaccard(~isnan(S2.odJaccard))));
    h{end + 1} = table_({'Lesion', 'AUPR (unsupervised detectors)', 'Best challenge entry (deep, trained on IDRiD)'}, body);
    body = {};
    for k = 1:numel(S2.localisation)
        l = S2.localisation(k);
        body(end + 1, :) = {l.landmark, sprintf('%.0f px (%.3f DD)', l.medianPx, l.medianDD), ...
            sprintf('%.0f%%', 100 * l.within8), sprintf('%.0f%%', 100 * l.within4), ...
            sprintf('%.0f%%', 100 * l.within2)}; %#ok<AGROW>
    end
    h{end + 1} = table_({'Landmark', 'Median error', 'within 1/8 DD', 'within 1/4 DD', 'within 1/2 DD'}, body);
    h{end + 1} = figureHTML(fullfile(o.Results, 'exp02', 'example.png'), ...
        'Photograph, reference lesions, NetraSetu annotation');
end
h{end + 1} = '</section>';

% ---------------------------------------------------------- explanations
S5 = loadSummary(o.Results, 'exp05', 'summary');
h{end + 1} = '<section><h2>4 &nbsp;Do the explanations point at the lesions?</h2>';
if isempty(S5)
    h{end + 1} = missing('experiments/exp05_explainability.m');
else
    body = {};
    for k = 1:numel(S5.rows)
        r = S5.rows(k);
        body(end + 1, :) = {r.name, ci(r.pointing, r.pointingCI), sprintf('%.3f', r.energy), ...
            sprintf('%.1f &times;', r.lift)}; %#ok<AGROW>
    end
    h{end + 1} = table_({'Map', 'Pointing game', 'Energy on lesions', 'Lift over a uniform map'}, body);
    if isfield(S5, 'reader')
        rd = S5.reader;
        h{end + 1} = sprintf('<p class="kv">Reader console: %d cases, median <b>%.0f s</b>, %.0f %% within 30 s, %.0f %% agreement with the AI.</p>', ...
            rd.cases, rd.medianSeconds, 100 * rd.under30, 100 * rd.agreement);
    end
    h{end + 1} = figureHTML(fullfile(o.Results, 'exp05', 'examples.png'), ...
        'Enhanced image, reference lesions, lesion evidence map, Grad-CAM++ (when trained)');
end
h{end + 1} = '</section>';

% ---------------------------------------------------------- district plan
S6 = loadSummary(o.Results, 'exp06', '');
h{end + 1} = '<section><h2>5 &nbsp;District programme plan</h2>';
if isempty(S6)
    h{end + 1} = missing('experiments/exp06_district_simulation.m');
else
    h{end + 1} = figureHTML(fullfile(o.Results, 'exp06', 'district_dashboard.png'), ...
        'Cheapest plan meeting every target, and what the explainable console and edge AI change');
end
h{end + 1} = '</section>';

% ------------------------------------------------------- published context
B = netra.eval.benchmarks();
body = {};
for k = 1:numel(B)
    b = B(k);
    if any(strcmp(b.task, {'referable-dr', 'standard'}))
        flag = '';
        if b.verify
            flag = ' <span class="verify">verify</span>';
        end
        body(end + 1, :) = {esc(b.dataset), esc(b.method), upper(b.metric), ...
            sprintf('%.3f', b.value), [esc(b.source) flag]}; %#ok<AGROW>
    end
end
h{end + 1} = ['<section><h2>6 &nbsp;Published context</h2><p class="note">Other datasets, reference ' ...
    'standards and referral definitions: context, not a head-to-head comparison. The strict comparisons ' ...
    'are the paired tests in section 1.</p>'];
h{end + 1} = table_({'Setting', 'Method', 'Metric', 'Value', 'Source'}, body);
h{end + 1} = '</section>';

h{end + 1} = ['<section><h2>7 &nbsp;Limitations</h2><ul class="lim">' ...
    '<li>Retrospective public datasets with their own reference standards; APTOS has no patient ' ...
    'identifiers and contains duplicate images, so its hold-out is optimistic.</li>' ...
    '<li>The single-field adaptation of the 4-2-1 rule is re-fitted on training data; severe NPDR ' ...
    'from one 45&deg; field remains an approximation of seven-field grading.</li>' ...
    '<li>Neovascularisation, venous beading and IRMA detectors are the least mature components; ' ...
    'PDR is caught mainly by the CNN branch and by human review of uncertain cases.</li>' ...
    '<li>Prevalence in a district programme is lower than in these datasets: predictive values ' ...
    'and the human-review share will differ; the calibration should be refreshed on local data.</li>' ...
    '<li>A prospective study with local graders is required before clinical use. NetraSetu is ' ...
    'research software, not a certified medical device.</li></ul></section>'];
h{end + 1} = '</main><footer>NetraSetu &middot; research software &middot; not a medical device</footer></body></html>';
fid = fopen(file, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', h{:});
fclose(fid);
end

% ======================================================================
function S = loadSummary(root, exp, var)
S = [];
f = fullfile(root, exp, 'summary.mat');
if strcmp(exp, 'exp06')
    f = fullfile(root, exp, 'district_plan.mat');
end
if ~exist(f, 'file')
    return
end
if isempty(var)
    S = true;
    return
end
L = load(f);
if isfield(L, var)
    S = L.(var);
end
end

function s = chip(name, on)
if on
    s = ['<span class="chip on">&#10003; ' name '</span>'];
else
    s = ['<span class="chip">&ndash; ' name '</span>'];
end
end

function s = tile(value, label, sure, point)
badge = '';
if ~isempty(sure)
    if sure
        badge = '<span class="st good">&#10003; meets target</span>';
    elseif point
        badge = '<span class="st warn">&#9679; not yet shown</span>';
    else
        badge = '<span class="st bad">&#10005; below target</span>';
    end
end
s = sprintf('<div class="tile"><div class="v">%s</div><div class="l">%s</div>%s</div>', value, esc(label), badge);
end

function s = ci(p, c)
s = sprintf('%.1f%% <small>(%.1f-%.1f)</small>', 100 * p, 100 * c(1), 100 * c(2));
end

function s = pfmt(p)
if p < 0.001
    s = '&lt; 0.001';
else
    s = sprintf('%.3f', p);
end
end

function s = table_(head, body)
s = ['<div class="tw"><table><thead><tr>' sprintf('<th>%s</th>', head{:}) '</tr></thead><tbody>'];
for r = 1:size(body, 1)
    s = [s '<tr>' sprintf('<td>%s</td>', body{r, :}) '</tr>']; %#ok<AGROW>
end
s = [s '</tbody></table></div>'];
end

function s = figureHTML(file, caption)
s = '';
if ~exist(file, 'file')
    return
end
fid = fopen(file, 'r');
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
if netra.util.isOctave()
    b64 = base64_encode(bytes');
else
    b64 = matlab.net.base64encode(bytes');
end
s = sprintf('<figure><img alt="%s" src="data:image/png;base64,%s"><figcaption>%s</figcaption></figure>', ...
    esc(caption), b64, esc(caption));
end

function s = missing(what)
s = sprintf('<p class="missing">Not run yet: <code>%s</code></p>', what);
end

function s = esc(s)
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
end

function s = css(P, hex)
s = [':root{--ink:' hex(P.ink) ';--soft:' hex(P.inkSoft) ';--paper:' hex(P.paper) ';--rule:' hex(P.rule) ...
    ';--accent:' hex(P.saffron) ';--good:' hex(P.ROUTINE) ';--bad:' hex(P.URGENT) ';--warn:' hex(P.REFER) '}' ...
    '*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);' ...
    'font:15px/1.55 "Noto Sans","Segoe UI",Helvetica,Arial,sans-serif}' ...
    'header{background:var(--ink);color:#fff;padding:18px 28px;display:flex;gap:18px;align-items:baseline;flex-wrap:wrap}' ...
    '.brand{font-weight:800;font-size:22px;letter-spacing:.3px}.brand:after{content:"";display:inline-block;' ...
    'width:9px;height:9px;border-radius:50%;background:var(--accent);margin-left:6px}' ...
    '.meta{opacity:.75;font-size:13px}main{max-width:1080px;margin:0 auto;padding:10px 24px 40px}' ...
    '.lede{font-size:17px;max-width:760px}.models{font-size:13px;color:var(--soft)}' ...
    '.chip{display:inline-block;border:1px solid var(--rule);border-radius:12px;padding:1px 9px;margin:2px 4px 2px 0;background:#fff}' ...
    '.chip.on{border-color:var(--good);color:var(--good)}' ...
    'section{margin-top:34px;border-top:1px solid var(--rule);padding-top:8px}h2{font-size:21px;margin:14px 0 6px}' ...
    'h3{font-size:17px;margin:22px 0 4px}h4{font-size:14px;margin:16px 0 4px;color:var(--soft)}' ...
    '.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:14px 0}' ...
    '.tile{background:#fff;border:1px solid var(--rule);border-radius:10px;padding:14px 16px}' ...
    '.tile .v{font-size:30px;font-weight:800;line-height:1.1}.tile .l{font-size:13px;color:var(--soft);margin-top:4px}' ...
    '.st{display:inline-block;margin-top:8px;font-size:12px;font-weight:700;padding:2px 8px;border-radius:10px;background:#fff}' ...
    '.st.good{color:var(--good);border:1px solid var(--good)}.st.bad{color:var(--bad);border:1px solid var(--bad)}' ...
    '.st.warn{color:var(--warn);border:1px solid var(--warn)}' ...
    '.note,.flow,.kv{font-size:13.5px;color:var(--soft);max-width:860px}.flow b,.kv b{color:var(--ink)}' ...
    '.tw{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:13.5px;margin:6px 0 4px;background:#fff}' ...
    'th{text-align:left;font-weight:700;border-bottom:2px solid var(--ink);padding:7px 10px;white-space:nowrap}' ...
    'td{border-bottom:1px solid var(--rule);padding:6px 10px;vertical-align:top}small{color:var(--soft)}' ...
    'figure{margin:14px 0}figure img{max-width:100%;border:1px solid var(--rule);border-radius:6px;background:#fff}' ...
    'figcaption{font-size:12.5px;color:var(--soft);margin-top:4px}.missing{color:var(--soft);font-style:italic}' ...
    '.verify{font-size:11px;border:1px solid var(--warn);color:var(--warn);border-radius:8px;padding:0 6px}' ...
    '.lim li{margin:6px 0;max-width:860px}code{background:#fff;border:1px solid var(--rule);border-radius:4px;padding:0 4px;font-size:13px}' ...
    'footer{text-align:center;color:var(--soft);font-size:12px;padding:24px}' ...
    '@media(max-width:600px){main{padding:8px 16px 30px}.tile .v{font-size:24px}header{padding:14px 16px}}'];
end
