function [x, names] = lesionFeatures(L, A, Q)
%LESIONFEATURES Fixed-length, clinically named feature vector for one eye.
%
%   [x, names] = netra.grading.lesionFeatures(L, A, Q) turns the lesion
%   detections (netra.lesions.detectAll), anatomy (netra.anatomy.analyze)
%   and image quality (netra.quality.assess) into 32 numbers with names a
%   clinician recognises. They feed the lesion ensemble and are what its
%   Shapley explanations refer to.

s = L.summary;
maP = [];
if ~isempty(L.ma.list)
    isMA = strcmp({L.ma.list.class}, 'MA');
    maP = [L.ma.list(isMA).prob];
end
heP = [];
heA = 0;
if ~isempty(L.he.list)
    heP = [L.he.list.prob];
    heA = sum([L.he.list([L.he.list.prob] >= 0.5).areaDA]);
end
irmaP = 0;
if ~isempty(L.vb.irma)
    irmaP = max([L.vb.irma.prob]);
end
qScore = NaN; focus = NaN;
if nargin >= 3 && isstruct(Q) && isfield(Q, 'score')
    qScore = Q.score;
    if isfield(Q.sub, 'focus'), focus = Q.sub.focus; end
end
F = {
    'maCount',            s.maCount
    'maHighCount',        s.maHighCount
    'maSoftCount',        sum(maP)
    'heDot',              s.heCounts.dot
    'heBlot',             s.heCounts.blot
    'heFlame',            s.heCounts.flame
    'hePreretinal',       s.preretinalCount
    'heTotal',            s.heTotal
    'heSoftCount',        sum(heP)
    'heQuadrantsAny',     nnz(s.hePerQuadrant > 0)
    'heMinPerQuadrant',   min(s.hePerQuadrant)
    'heMaxPerQuadrant',   max(s.hePerQuadrant)
    'heAreaDA',           heA
    'exCount',            s.exCount
    'exAreaDD2',          s.exAreaDD2
    'exMinDistFoveaDD',   min(s.exMinDistFoveaDD, 5)
    'dme',                s.dme
    'centreInvolved',     double(s.centreInvolved)
    'cwsCount',           s.cwsCount
    'vbQuadrants',        numel(s.vbQuadrants)
    'vbMaxIndex',         s.vbMaxIndex
    'irmaQuadrants',      numel(s.irmaQuadrants)
    'irmaMaxProb',        irmaP
    'nvdProb',            s.nvdProb
    'nveProb',            s.nveProb
    'nvdScore',           s.nvdScore
    'nveScore',           s.nveScore
    'vesselFraction',     A.vessels.fraction
    'qualityScore',       qScore
    'qualityFocus',       focus
    'discConfidence',     A.od.confidence
    'foveaConfidence',    A.fovea.confidence};
names = F(:, 1)';
x = cell2mat(F(:, 2)');
end
