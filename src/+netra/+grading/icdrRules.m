function R = icdrRules(s, cfg)
%ICDRRULES International Clinical DR severity scale as an explicit rule engine.
%
%   R = netra.grading.icdrRules(summary, cfg) grades one eye from the
%   lesion tallies in netra.lesions.detectAll(...).summary and returns, for
%   every criterion, the measured value, the threshold, whether it is met
%   and a sentence a grader can verify on the annotated image.
%
%   ICDR (Wilkinson et al., Ophthalmology 2003):
%     0  no apparent retinopathy       no abnormalities
%     1  mild NPDR                     microaneurysms only
%     2  moderate NPDR                 more than just microaneurysms, less than severe
%     3  severe NPDR                   any of: > 20 intraretinal haemorrhages in each
%                                      of 4 quadrants; definite venous beading in
%                                      >= 2 quadrants; prominent IRMA in >= 1
%                                      quadrant (the 4-2-1 rule); no signs of PDR
%     4  PDR                           neovascularisation and/or vitreous or
%                                      pre-retinal haemorrhage
%
%   The 4-2-1 rule was written for seven-field photography. A single 45-50
%   degree field shows roughly half of each mid-peripheral quadrant, so the
%   haemorrhage count per quadrant is scaled (cfg.rules.hePerQuadrant,
%   default 10) and meant to be re-fitted on local data
%   (experiments/exp03_train_grader.m does this).
%
%   R fields: grade, dme (0/1/2), centreInvolved, referableDR (grade >= 2),
%   referable (referableDR or DME grade 2), criteria (struct array: id,
%   level, text, value, threshold, met, margin), evidence (cellstr of the
%   criteria that are met, highest level first).

r = cfg.rules;
C = struct('id', {}, 'level', {}, 'text', {}, 'value', {}, 'threshold', {}, ...
    'met', {}, 'margin', {});

maMet = s.maHighCount >= r.maMinHigh || s.maCount >= r.maMinCount;
C(end + 1) = crit('ma', 1, sprintf('Microaneurysms: %d probable, %d confident', ...
    s.maCount, s.maHighCount), s.maCount, r.maMinCount, maMet, ...
    max(s.maCount / r.maMinCount, s.maHighCount / max(r.maMinHigh, 1)));
C(end + 1) = crit('he', 2, sprintf('Intraretinal haemorrhages: %d (dot %d, blot %d, flame %d)', ...
    s.heTotal, s.heCounts.dot, s.heCounts.blot, s.heCounts.flame), s.heTotal, 1, ...
    s.heTotal >= 1, s.heTotal);
C(end + 1) = crit('ex', 2, sprintf('Hard exudates: %d (%.3f DD^2)', s.exCount, s.exAreaDD2), ...
    s.exCount, 1, s.exCount >= 1, s.exCount);
C(end + 1) = crit('cws', 2, sprintf('Cotton-wool spots: %d', s.cwsCount), s.cwsCount, 1, ...
    s.cwsCount >= 1, s.cwsCount);
minQ = min(s.hePerQuadrant);
nQ = nnz(s.hePerQuadrant >= r.hePerQuadrant);
C(end + 1) = crit('he4q', 3, sprintf(['Haemorrhages >= %d in %d of 4 quadrants ', ...
    '(per quadrant ST/SN/IN/IT: %s)'], r.hePerQuadrant, nQ, mat2str(s.hePerQuadrant)), ...
    minQ, r.hePerQuadrant, nQ >= r.heQuadrants, minQ / r.hePerQuadrant);
nVB = numel(s.vbQuadrants);
C(end + 1) = crit('vb', 3, sprintf('Venous beading in %d quadrant(s) (max index %.2f)', ...
    nVB, s.vbMaxIndex), nVB, r.vbQuadrants, nVB >= r.vbQuadrants, nVB / r.vbQuadrants);
nIR = numel(s.irmaQuadrants);
C(end + 1) = crit('irma', 3, sprintf('IRMA-like microvascular anomaly in %d quadrant(s)', nIR), ...
    nIR, r.irmaQuadrants, nIR >= r.irmaQuadrants, nIR / r.irmaQuadrants);
pNV = max(s.nvdProb, s.nveProb);
if s.nvdProb >= s.nveProb
    where = 'on the disc (NVD)';
else
    where = 'elsewhere (NVE)';
end
C(end + 1) = crit('nv', 4, sprintf('Neovascularisation %s: p = %.2f', where, pNV), ...
    pNV, r.nvProb, pNV >= r.nvProb, pNV / r.nvProb);
C(end + 1) = crit('prh', 4, sprintf('Pre-retinal haemorrhage: %d', s.preretinalCount), ...
    s.preretinalCount, 1, s.preretinalCount >= 1, s.preretinalCount);

met = [C.met];
lv = [C.level];
grade = 0;
if any(met)
    grade = max(lv(met));
end

R = struct();
R.grade = grade;
R.dme = s.dme;
R.centreInvolved = s.centreInvolved;
R.referableDR = grade >= 2;
R.referable = R.referableDR || s.dme >= 2;
R.criteria = C;
[~, order] = sort(lv .* met, 'descend');
ev = {};
for k = order
    if C(k).met
        ev{end + 1} = C(k).text; %#ok<AGROW>
    end
end
if s.dme >= 1
    ev{end + 1} = sprintf('Macular oedema risk %d: nearest exudate %.2f DD from the fovea', ...
        s.dme, s.exMinDistFoveaDD);
end
R.evidence = ev;
end

function c = crit(id, level, text, value, threshold, met, margin)
c = struct('id', id, 'level', level, 'text', text, 'value', value, ...
    'threshold', threshold, 'met', logical(met), 'margin', margin);
end
