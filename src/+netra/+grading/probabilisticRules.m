function [P, samples] = probabilisticRules(L, cfg, nSamples)
%PROBABILISTICRULES Grade distribution implied by uncertain lesion evidence.
%
%   P = netra.grading.probabilisticRules(L, cfg) samples every detected
%   lesion as present with its own probability (Monte Carlo, default
%   cfg.grading.mcSamples draws), applies the ICDR rules to each sampled
%   "world" and returns the frequency of each grade, P(1..5) for grades 0..4.
%
%   The deterministic engine answers "what grade do the confident lesions
%   imply?"; this answers "how sure can we be of it?". A case whose 4-2-1
%   criterion is met by 11, 10, 10 and 10 haemorrhages of probability 0.6 is
%   not severe NPDR with certainty, and the distribution says so. It is the
%   rule branch's input to the fusion model and to the conformal set.

if nargin < 3
    nSamples = cfg.grading.mcSamples;
end
r = cfg.rules;
S = nSamples;
% Detector scores are not calibrated probabilities: weak candidates must not
% add up to a lesion. Scores below the floor count as absent, the rest are
% rescaled to [0, 1] before sampling.
fl = r.evidenceFloor;
eff = @(p) max(0, (p(:) - fl) / (1 - fl));
draw = @(p) rand(numel(p), S) < repmat(eff(p), 1, S);

% microaneurysms
if isempty(L.ma.list)
    maAny = false(1, S);
else
    isMA = strcmp({L.ma.list.class}, 'MA');
    p = [L.ma.list(isMA).prob];
    hi = p >= r.maHighProb;
    D = draw(p);
    maAny = sum(D(hi, :), 1) >= r.maMinHigh | sum(D, 1) >= r.maMinCount;
end

% haemorrhages: total and per quadrant
heList = L.he.list;
if isempty(heList)
    heAny = false(1, S);
    he4q = false(1, S);
    prh = false(1, S);
else
    isPre = strcmp({heList.type}, 'preretinal');
    ph = [heList.prob];
    q = [heList.quadrant];
    D = draw(ph);
    intra = ~isPre & q > 0;
    heAny = any(D(intra, :), 1);
    counts = zeros(4, S);
    for k = 1:4
        counts(k, :) = sum(D(intra & q == k, :), 1);
    end
    he4q = sum(counts >= r.hePerQuadrant, 1) >= r.heQuadrants;
    prh = any(D(isPre, :), 1);
    if ~any(isPre)
        prh = false(1, S);
    end
end

% exudates and cotton-wool spots
exAny = anyDraw([L.ex.list.prob], S, fl);
cwsAny = anyDraw([L.ex.cws.prob], S, fl);

% venous beading: soft membership of each vein segment
vbq = false(1, S);
if ~isempty(L.vb.segments)
    seg = L.vb.segments([L.vb.segments.isVein]);
    if ~isempty(seg)
        pv = netra.util.sigmoid([seg.index], cfg.vb.beadingIndex, 0.03) .* ...
             netra.util.sigmoid([seg.acf], cfg.vb.acfPeak, 0.08);
        D = draw(pv);
        qv = [seg.quadrant];
        nq = zeros(1, S);
        for k = 1:4
            nq = nq + any(D(qv == k, :), 1);
        end
        vbq = nq >= r.vbQuadrants;
    end
end

% IRMA-like anomalies
irq = false(1, S);
if ~isempty(L.vb.irma)
    D = draw([L.vb.irma.prob]);
    qi = [L.vb.irma.quadrant];
    nq = zeros(1, S);
    for k = 1:4
        nq = nq + any(D(qi == k, :), 1);
    end
    irq = nq >= r.irmaQuadrants;
end

% neovascularisation
nv = rand(1, S) < eff(L.nv.nvdProb) | rand(1, S) < eff(L.nv.nveProb);

grade = zeros(1, S);
grade(maAny) = 1;
grade(heAny | exAny | cwsAny) = 2;
grade(he4q | vbq | irq) = 3;
grade(nv | prh) = 4;
P = accumarray(grade(:) + 1, 1, [5 1])' / S;
% shrink towards the programme's grade prior so that "no evidence" never
% becomes certainty (the rule engine cannot see everything a grader sees)
P = (1 - r.smoothing) * P + r.smoothing * r.gradePrior(:)';
samples = grade;
end

function a = anyDraw(p, S, fl)
if isempty(p)
    a = false(1, S);
else
    q = max(0, (p(:) - fl) / (1 - fl));
    a = any(rand(numel(p), S) < repmat(q, 1, S), 1);
end
end
