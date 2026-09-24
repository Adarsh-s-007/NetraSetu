function C = concordance(cam, masks, fov, cfg)
%CONCORDANCE Does the network's attention fall on the detected lesions?
%
%   C = netra.xai.concordance(cam, masks, fov, cfg) compares a Grad-CAM map
%   (canvas resolution, [0, 1]) with the union of lesion masks from the
%   classical detectors (netra.lesions.detectAll(...).masks), dilated by
%   0.1 DD-equivalent pixels to allow for the coarse CAM grid.
%
%     energyInLesions   share of CAM energy inside the dilated lesions
%                       (energy-based pointing game, Wang et al. 2020)
%     lesionRecall      share of lesion components whose peak CAM exceeds
%                       the 80th percentile of the map
%     pointingHit       the CAM maximum lies on a lesion (pointing game)
%     score             harmonic mean of energy share and recall
%     flag              true when lesions exist but score < cfg.xai.concordanceMin:
%                       the CNN may be relying on something else (an
%                       artefact, the disc, a camera mark) - send to a human.
%
%   Two independent techniques agreeing is the explanation; one of them
%   alone is only a picture.

L = masks.ma | masks.he | masks.ex | masks.cws | masks.nv;
D = size(cam, 1);
r = max(2, round(0.015 * D));
Ld = imdilate(L, strel('disk', r, 0)) & fov;
C = struct('energyInLesions', NaN, 'lesionRecall', NaN, 'pointingHit', false, ...
    'score', NaN, 'flag', false, 'hasLesions', any(L(:)));
if ~any(cam(:) > 0)
    C.flag = C.hasLesions;
    return
end
e = cam .* fov;
if any(Ld(:))
    C.energyInLesions = sum(e(Ld)) / max(sum(e(:)), eps);
    [~, i] = max(e(:));
    C.pointingHit = Ld(i);
    lab = bwlabel(Ld, 8);
    t = netra.util.pct(e(fov), 80);
    n = max(lab(:));
    hit = 0;
    for k = 1:n
        hit = hit + (max(e(lab == k)) >= t);
    end
    C.lesionRecall = hit / max(n, 1);
    C.score = 2 * C.energyInLesions * C.lesionRecall / max(C.energyInLesions + C.lesionRecall, eps);
    C.flag = C.score < cfg.xai.concordanceMin;
end
end
