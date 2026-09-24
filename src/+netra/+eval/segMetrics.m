function m = segMetrics(pred, gt, mask, score)
%SEGMETRICS Pixel-level segmentation metrics inside a field-of-view mask.
%   m = netra.eval.segMetrics(pred, gt, mask) - Se, Sp, Acc, Dice (F1),
%   IoU, MCC, as reported for DRIVE. With a continuous SCORE map the ROC AUC
%   and the area under the precision-recall curve (IDRiD's metric) are added.
if nargin < 3 || isempty(mask)
    mask = true(size(gt));
end
p = logical(pred(mask));
g = logical(gt(mask));
b = netra.eval.binaryMetrics(g, p);
m = struct('se', b.se, 'sp', b.sp, 'acc', b.acc, 'dice', b.f1, ...
    'iou', b.tp / max(b.tp + b.fp + b.fn, 1), 'mcc', b.mcc);
if nargin >= 4 && ~isempty(score)
    s = score(mask);
    r = netra.eval.rocFast(g, s);
    m.auc = r.auc;
    pr = netra.eval.prCurve(g, s);
    m.aupr = pr.aupr;
end
end
