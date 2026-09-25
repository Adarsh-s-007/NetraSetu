function file = reportHTML(R, file)
%REPORTHTML Self-contained bilingual HTML screening report for one eye.
%
%   netra.xai.reportHTML(R, 'report.html')
%
%   One file, no external resources (images are embedded as JPEG data
%   URIs, ~0.3 MB in total): it can be sent over a 2G link, opened on the
%   ASHA worker's phone, printed at the PHC, or attached to the referral.
%   Browsers shape Devanagari correctly, so this - not the MATLAB figure -
%   carries the patient message in Hindi. Add a language by adding a column
%   to tools/i18n/strings.tsv.

P = netra.util.palette();
T = R.decision;
hex = @(c) sprintf('#%02X%02X%02X', round(255 * c));
lines = {};
add = @(varargin) sprintf(varargin{:});

title = sprintf('NetraSetu report %s', esc(valueOr(R.meta.id, '')));
lines{end + 1} = '<!doctype html><html lang="en"><head><meta charset="utf-8">';
lines{end + 1} = '<meta name="viewport" content="width=device-width, initial-scale=1">';
lines{end + 1} = ['<title>' title '</title>'];
lines{end + 1} = ['<style>' css(P, hex, T) '</style></head><body>'];

% ------------------------------------------------------------------ band
lines{end + 1} = '<header class="band"><div class="brand">';
lines{end + 1} = ['<span class="word">NetraSetu</span><span class="deva" lang="hi">' ...
    netra.util.i18n('brand', 'hi') '</span>'];
lines{end + 1} = '<span class="kicker">Diabetic retinopathy screening report</span></div>';
eye = valueOr(R.meta.eye, '');
if isempty(eye) && isfield(R, 'anatomy')
    eye = [R.anatomy.frame.eye ' (inferred)'];
end
lines{end + 1} = add(['<div class="meta"><b>%s</b><span>Eye %s</span><span>%s</span>' ...
    '<span>%s</span></div></header>'], esc(valueOr(R.meta.id, 'unnamed')), esc(eye), ...
    esc(R.meta.time), esc(valueOr(R.meta.site, R.cfg.report.site)));

% ---------------------------------------------------------------- banner
lines{end + 1} = add(['<section class="banner"><div class="triage">%s</div>' ...
    '<div class="follow">%s</div></section>'], strrep(T.triage, '_', ' '), esc(T.followUp));
lines{end + 1} = '<section class="patient">';
lines{end + 1} = add('<p lang="en">%s</p>', esc(T.message.en));
lines{end + 1} = add('<p lang="hi" class="hi">%s</p>', T.message.hi);
lines{end + 1} = '</section>';

if strcmp(T.triage, 'RECAPTURE')
    lines{end + 1} = '<main class="grid"><figure class="fundus">';
    lines{end + 1} = add('<img alt="captured photograph" src="%s">', dataURI(R.thumbnail));
    lines{end + 1} = '</figure><aside><h2>Why the photograph cannot be graded</h2><ul>';
    for k = 1:numel(R.quality.feedback)
        f = R.quality.feedback(k);
        lines{end + 1} = add('<li><p>%s</p><p lang="hi" class="hi">%s</p></li>', esc(f.en), f.hi); %#ok<AGROW>
    end
    lines{end + 1} = ['</ul>' qualityHTML(R.quality) '</aside></main>'];
else
    s = R.lesions.summary;
    lines{end + 1} = '<main class="grid"><figure class="fundus">';
    lines{end + 1} = add('<img alt="annotated fundus photograph" src="%s">', ...
        dataURI(crop(R.overlay, R.canvas)));
    chips = {'ma', sprintf('Microaneurysms %d', s.maCount); ...
             'blot', sprintf('Haemorrhages %d', s.heTotal); ...
             'exudate', sprintf('Hard exudates %d', s.exCount); ...
             'cws', sprintf('Cotton-wool spots %d', s.cwsCount); ...
             'nv', sprintf('New vessels p=%.2f', max(s.nvdProb, s.nveProb)); ...
             'vb', sprintf('Beaded veins %dq', numel(s.vbQuadrants))};
    lines{end + 1} = '<figcaption class="chips">';
    for k = 1:size(chips, 1)
        lines{end + 1} = add('<span><i style="background:%s"></i>%s</span>', ...
            hex(P.(chips{k, 1})), chips{k, 2}); %#ok<AGROW>
    end
    lines{end + 1} = '</figcaption></figure><aside>';

    if ~isempty(R.xai.cam)
        map = netra.xai.heat(R.canvas.display, R.xai.cam);
        cap = 'Where the network looked (Grad-CAM++)';
    else
        map = netra.xai.heat(R.canvas.display, R.xai.evidence);
        cap = 'Where the detectors found disease';
    end
    lines{end + 1} = add('<div class="pair"><figure class="attention"><img alt="%s" src="%s"><figcaption>%s', ...
        cap, dataURI(crop(map, R.canvas), 520), cap);
    if isfield(R.xai.concordance, 'score') && ~isnan(R.xai.concordance.score)
        lines{end + 1} = add('<br><small>%.0f %% of attention on detected lesions</small>', ...
            100 * R.xai.concordance.energyInLesions);
    end
    lines{end + 1} = ['</figcaption></figure>' severityHTML(R, P, hex) '</div>'];

    lines{end + 1} = '<h2>ICDR criteria <small>single-field adaptation</small></h2><table class="criteria">';
    C = R.rules.criteria;
    for k = 1:numel(C)
        cls = 'no';
        if C(k).met, cls = sprintf('l%d', C(k).level); end
        lines{end + 1} = add('<tr class="%s"><td><i></i></td><td>%s</td><td>level %d</td></tr>', ...
            cls, esc(C(k).text), C(k).level); %#ok<AGROW>
    end
    if R.rules.dme > 0
        lines{end + 1} = add(['<tr class="l2"><td><i></i></td><td>Macular oedema risk %d: ' ...
            'nearest exudate %.2f DD from the fovea</td><td>DME</td></tr>'], R.rules.dme, s.exMinDistFoveaDD);
    end
    lines{end + 1} = '</table>';
    if ~isempty(T.reasons)
        lines{end + 1} = ['<h2>Why this decision</h2><ul class="reasons"><li>' ...
            strjoin(cellfun(@esc, T.reasons, 'UniformOutput', false), '</li><li>') '</li></ul>'];
    end
    lines{end + 1} = ['<div class="two">' qualityHTML(R.quality) provenanceHTML(R) '</div>'];
    lines{end + 1} = '</aside></main>';
end

lines{end + 1} = add(['<footer><p>%s</p><p class="sign">Reviewer ____________ &nbsp; Agree &#9744; ' ...
    '&nbsp; Override grade ___ &nbsp; Review time ___ s</p><p class="ver">NetraSetu %s</p></footer>'], ...
    esc(R.cfg.report.disclaimer), R.meta.version);
lines{end + 1} = '</body></html>';

html = strjoin(lines, sprintf('\n'));
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0
    error('netra:reportHTML:open', 'Cannot write %s', file);
end
fwrite(fid, html, 'char');
fclose(fid);
end

% ======================================================================
function s = css(P, hex, T)
s = [':root{--ink:' hex(P.ink) ';--soft:' hex(P.inkSoft) ';--paper:' hex(P.paper) ...
    ';--rule:' hex(P.rule) ';--saffron:' hex(P.saffron) ';--tri:' hex(T.colour) ...
    ';--ok:' hex(P.ROUTINE) ';--mid:' hex(P.REFER) ';--hi:' hex(P.URGENT) '}' ...
    '*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);' ...
    'font:15px/1.45 Inter,"Segoe UI","Noto Sans",system-ui,sans-serif}' ...
    '.band{display:flex;justify-content:space-between;align-items:center;gap:16px;' ...
    'flex-wrap:wrap;background:var(--ink);color:#fff;padding:14px 24px}' ...
    '.brand{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}' ...
    '.word{font-size:28px;font-weight:800;letter-spacing:.2px}' ...
    '.deva{font:500 22px "Noto Sans Devanagari","Nirmala UI","Kohinoor Devanagari",sans-serif;color:var(--saffron)}' ...
    '.kicker{flex-basis:100%;font-size:11px;letter-spacing:.14em;text-transform:uppercase;color:var(--saffron)}' ...
    '.meta{display:flex;gap:14px;flex-wrap:wrap;font-size:14px;color:#dfe2ee}.meta b{color:#fff}' ...
    '.banner{display:flex;align-items:baseline;gap:18px;flex-wrap:wrap;background:var(--tri);' ...
    'color:#fff;padding:14px 24px}.triage{font-size:30px;font-weight:800;letter-spacing:.5px}' ...
    '.follow{font-size:17px}.patient{padding:12px 24px;background:#fff;border-bottom:1px solid var(--rule)}' ...
    '.patient p{margin:4px 0;font-size:17px}.hi{font-family:"Noto Sans Devanagari","Nirmala UI",' ...
    '"Kohinoor Devanagari",sans-serif}' ...
    '.grid{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(0,1fr);gap:24px;padding:20px 24px}' ...
    '@media(max-width:900px){.grid{grid-template-columns:1fr}}' ...
    'figure{margin:0}.fundus img{width:100%;border-radius:10px;display:block;background:#000}' ...
    '.chips{display:flex;flex-wrap:wrap;gap:6px 16px;margin-top:10px;font-size:13px}' ...
    '.chips i{display:inline-block;width:12px;height:12px;border-radius:3px;margin-right:6px;vertical-align:-1px}' ...
    '.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px;align-items:start}' ...
    '.attention img{width:100%;border-radius:8px;display:block;background:#000}' ...
    'figcaption{font-size:12px;color:var(--soft);margin-top:6px}' ...
    'h2{font-size:15px;margin:18px 0 8px}h2 small{font-weight:400;color:var(--soft)}' ...
    '.sev{display:flex;align-items:flex-end;gap:8px;height:170px;margin-top:40px;position:relative}' ...
    '.sev>div{flex:1 1 0;min-width:0;text-align:center;font-size:11px;color:var(--soft);white-space:nowrap}' ...
    '.sev .bar{height:120px;background:var(--rule);border-radius:4px;position:relative;overflow:hidden}' ...
    '.sev .fill{position:absolute;bottom:0;left:0;right:0}.sev b{display:block;color:var(--ink);font-size:14px}' ...
    '.sev .pct{color:var(--ink);font-weight:700;font-size:12px}' ...
    '.bracket{position:absolute;top:-30px;height:10px;margin:0;border:2px solid var(--ink);border-bottom:0;' ...
    'font-size:11px;text-align:center;line-height:0;color:var(--ink)}' ...
    '.bracket span{position:relative;top:-8px;background:var(--paper);padding:0 4px}' ...
    '.pref{font-size:13px;margin-top:8px}' ...
    'table.criteria{border-collapse:collapse;width:100%;font-size:13.5px}' ...
    '.criteria td{padding:5px 6px;border-bottom:1px solid var(--rule)}.criteria td:last-child{' ...
    'color:var(--soft);font-size:12px;text-align:right;white-space:nowrap}' ...
    '.criteria i{display:inline-block;width:11px;height:11px;border-radius:50%;background:var(--rule)}' ...
    '.criteria .l1 i{background:var(--ok)}.criteria .l2 i{background:var(--mid)}' ...
    '.criteria .l3 i,.criteria .l4 i{background:var(--hi)}.criteria .no td{color:var(--soft)}' ...
    '.criteria tr:not(.no) td:nth-child(2){font-weight:600}' ...
    '.reasons{margin:0;padding-left:18px}.two{display:grid;grid-template-columns:1fr 1fr;gap:16px}' ...
    '.q{display:grid;grid-template-columns:90px 1fr;gap:4px 10px;font-size:12px;align-items:center}' ...
    '.q .t{height:8px;background:var(--rule);border-radius:4px;overflow:hidden}.q .t i{display:block;height:100%}' ...
    '.prov{font-size:12.5px;color:var(--ink)}.prov p{margin:3px 0}' ...
    'footer{border-top:1px solid var(--rule);margin:8px 24px 0;padding:10px 0 24px;font-size:12px;color:var(--soft)}' ...
    'footer .sign{color:var(--ink);font-size:13px}footer .ver{font-size:11px}' ...
    '@media(max-width:600px){.pair,.two{grid-template-columns:1fr}.triage{font-size:26px}}' ...
    '@media print{body{background:#fff}.grid{grid-template-columns:1.05fr 1fr}}'];
end

function h = severityHTML(R, P, hex)
p = R.fusion.P;
names = {'none', 'mild', 'moderate', 'severe', 'PDR'};   % short enough for a phone column
h = '<div><h2 style="margin-top:0">Severity (ICDR)</h2><div class="sev">';
cs = R.conformalSet;
if ~isempty(cs) && any(cs)
    f = find(cs, 1, 'first') - 1;
    l = find(cs, 1, 'last');
    h = [h sprintf('<p class="bracket" style="left:calc(%.1f%% + 4px);width:calc(%.1f%% - 8px)"><span>%.0f %% set</span></p>', ...
        100 * f / 5, 100 * (l - f) / 5, 100 * (1 - R.cfg.grading.conformalAlpha))];
end
for k = 1:5
    h = [h sprintf(['<div><span class="pct">%.0f%%</span><div class="bar"><i class="fill" ' ...
        'style="height:%.1f%%;background:%s"></i></div><b>%d</b>%s</div>'], ...
        100 * p(k), 100 * p(k), hex(P.grades(k, :)), k - 1, names{k})]; %#ok<AGROW>
end
h = [h sprintf(['</div><p class="pref">P(referable) <b>%.2f</b> &middot; grade <b>%d</b> ' ...
    '&middot; threshold %.2f</p></div>'], R.decision.pReferable, R.fusion.grade, ...
    R.cfg.grading.referralThreshold)];
end

function h = qualityHTML(Q)
names = {'field', 'focus', 'illumination', 'contrast', 'artifact'};
h = sprintf('<div><h2>Image quality %.2f <small>%s</small></h2><div class="q">', Q.score, lower(Q.decision));
for k = 1:numel(names)
    v = Q.sub.(names{k});
    col = 'var(--ok)';
    if v < 0.5, col = 'var(--hi)'; elseif v < 0.8, col = 'var(--mid)'; end
    h = [h sprintf('<span>%s</span><span class="t"><i style="width:%.0f%%;background:%s"></i></span>', ...
        names{k}, 100 * max(v, 0.01), col)]; %#ok<AGROW>
end
h = [h '</div></div>'];
end

function h = provenanceHTML(R)
m = R.models;
parts = {'rule engine'};
if m.lesion, parts{end + 1} = 'lesion ensemble'; end
if m.cnn, parts{end + 1} = 'CNN'; end
h = sprintf('<div class="prov"><h2>How this result was produced</h2><p>Grade from %s (%s).</p>', ...
    strjoin(parts, ' + '), R.fusion.method);
if ~m.cnn && ~m.lesion
    h = [h '<p><b>No trained models loaded:</b> rule engine only, not clinically validated.</p>'];
end
h = [h sprintf('<p>Disc-fovea %.2f DD; eye %s; vessels %.1f %% of the field.</p>', ...
    R.anatomy.fovea.distanceDD, R.anatomy.frame.eye, 100 * R.anatomy.vesselFraction)];
h = [h sprintf('<p>Analysis %.1f s.</p></div>', R.timing.total)];
end

function img = crop(img, cv)
c = cv.centre;
r = cv.radius * 1.01;
D = size(img, 1);
r1 = max(1, round(c(2) - r)); r2 = min(D, round(c(2) + r));
c1 = max(1, round(c(1) - r)); c2 = min(D, round(c(1) + r));
img = img(r1:r2, c1:c2, :);
end

function u = dataURI(img, maxSide)
if nargin < 2
    maxSide = 900;
end
f = maxSide / max(size(img, 1), size(img, 2));
if f < 1
    img = netra.util.imscale(img, f);
end
tmp = [tempname() '.jpg'];
imwrite(im2uint8(min(max(img, 0), 1)), tmp, 'Quality', 88);
fid = fopen(tmp, 'r');
bytes = fread(fid, Inf, '*uint8');
fclose(fid);
delete(tmp);
if netra.util.isOctave()
    b64 = base64_encode(bytes');
else
    b64 = matlab.net.base64encode(bytes');
end
u = ['data:image/jpeg;base64,' b64];
end

function s = esc(s)
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
end

function v = valueOr(v, d)
if isempty(v)
    v = d;
end
end
