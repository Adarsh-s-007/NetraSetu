function L = detectAll(E, A, cfg)
%DETECTALL Run every lesion detector and tally the clinical evidence.
%
%   L = netra.lesions.detectAll(E, A, cfg) returns the individual detector
%   outputs (ma, he, ex, nv, vb) and L.summary, the quantities the ICDR
%   criteria are written in:
%     maCount, maHighCount        MAs with prob >= 0.5 / >= cfg.rules.maHighProb
%     heCounts                    dot / blot / flame / preretinal
%     hePerQuadrant               intraretinal haemorrhages per quadrant
%     exCount, exAreaDD2, dme, centreInvolved, cwsCount
%     vbQuadrants, irmaQuadrants  beaded-vein and IRMA-like quadrants
%     nvdProb, nveProb, preretinalCount
%   and L.masks, the lesion masks on the canvas used for overlays and for
%   the attention-evidence concordance check.

t = tic;
MA = netra.lesions.microaneurysms(E, A, cfg);
HE = netra.lesions.hemorrhages(E, A, MA, cfg);
EX = netra.lesions.exudates(E, A, cfg);
NV = netra.lesions.neovascularization(E, A, cfg);
VB = netra.lesions.venousBeading(E, A, HE, NV, cfg);

s = struct();
if isempty(MA.list)
    s.maCount = 0;
    s.maHighCount = 0;
else
    isMA = strcmp({MA.list.class}, 'MA');
    p = [MA.list.prob];
    s.maCount = nnz(isMA & p >= 0.5);
    s.maHighCount = nnz(isMA & p >= cfg.rules.maHighProb);
end
s.heCounts = HE.counts;
s.heTotal = HE.counts.dot + HE.counts.blot + HE.counts.flame;
s.hePerQuadrant = HE.perQuadrant;
s.preretinalCount = HE.counts.preretinal;
s.exCount = EX.count;
s.exAreaDD2 = EX.areaDD2;
s.exMinDistFoveaDD = EX.minDistFoveaDD;
s.dme = EX.dme;
s.centreInvolved = EX.centreInvolved;
s.cwsCount = EX.cwsCount;
s.vbQuadrants = VB.quadrants;
s.vbMaxIndex = VB.maxIndex;
s.irmaQuadrants = VB.irmaQuadrants;
s.nvdProb = NV.nvdProb;
s.nveProb = NV.nveProb;
s.nvdScore = NV.nvdScore;
s.nveScore = NV.nveScore;

L = struct('ma', MA, 'he', HE, 'ex', EX, 'nv', NV, 'vb', VB, 'summary', s);
L.masks = struct('ma', MA.mask, 'he', HE.mask, 'ex', EX.mask, 'cws', EX.cwsMask, ...
    'nv', NV.scoreMap > cfg.nv.threshold);
L.seconds = toc(t);
end
