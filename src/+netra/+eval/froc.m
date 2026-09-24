function f = froc(dets, gts, nImages, fpRates)
%FROC Free-response ROC for lesion detection (Retinopathy Online Challenge).
%
%   f = netra.eval.froc(dets, gts, nImages)
%     dets  struct array: image, x, y, score        (all detections)
%     gts   struct array: image, x, y, radius       (all reference lesions)
%   A detection is a true positive when it falls within max(radius, 2) px
%   of a not-yet-matched reference lesion of the same image. Returns the
%   sensitivity at 1/8, 1/4, 1/2, 1, 2, 4 and 8 false positives per image
%   and their mean - the ROC competition score (Niemeijer et al., IEEE TMI
%   2010) used to compare microaneurysm detectors.
if nargin < 4
    fpRates = [1/8 1/4 1/2 1 2 4 8];
end
[~, order] = sort([dets.score], 'descend');
dets = dets(order);
matched = false(numel(gts), 1);
isTP = false(numel(dets), 1);
gi = [gts.image];
gx = [gts.x];
gy = [gts.y];
gr = max([gts.radius], 2);
for i = 1:numel(dets)
    cand = find(gi == dets(i).image & ~matched');
    if isempty(cand), continue; end
    dd = hypot(gx(cand) - dets(i).x, gy(cand) - dets(i).y);
    [mn, j] = min(dd ./ gr(cand));
    if mn <= 1
        isTP(i) = true;
        matched(cand(j)) = true;
    end
end
sens = cumsum(isTP) / max(numel(gts), 1);
fppi = cumsum(~isTP) / max(nImages, 1);
f = struct('fppi', fppi, 'sensitivity', sens, 'fpRates', fpRates);
f.sensAt = zeros(size(fpRates));
for k = 1:numel(fpRates)
    idx = find(fppi <= fpRates(k), 1, 'last');
    if ~isempty(idx)
        f.sensAt(k) = sens(idx);
    end
end
f.score = mean(f.sensAt);
end
