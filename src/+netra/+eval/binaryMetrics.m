function m = binaryMetrics(truth, pred)
%BINARYMETRICS Diagnostic accuracy of a binary decision, with 95 % CIs.
%   m = netra.eval.binaryMetrics(truth, pred) - logical vectors.
%   Fields: tp fp tn fn, se seCI, sp spCI, ppv ppvCI, npv npvCI, acc,
%   f1, mcc, youden, lrPos, lrNeg, nPos, nNeg (STARD reporting set).
truth = logical(truth(:));
pred = logical(pred(:));
tp = nnz(truth & pred);
fn = nnz(truth & ~pred);
tn = nnz(~truth & ~pred);
fp = nnz(~truth & pred);
m = struct('tp', tp, 'fp', fp, 'tn', tn, 'fn', fn);
m.nPos = tp + fn;
m.nNeg = tn + fp;
% a proportion with an empty denominator is undefined, not zero
[m.se, m.seCI] = prop(tp, tp + fn);
[m.sp, m.spCI] = prop(tn, tn + fp);
[m.ppv, m.ppvCI] = prop(tp, tp + fp);
[m.npv, m.npvCI] = prop(tn, tn + fn);
m.acc = (tp + tn) / max(numel(truth), 1);
m.f1 = 2 * tp / max(2 * tp + fp + fn, 1);
den = sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn));
m.mcc = (tp * tn - fp * fn) / max(den, eps);
m.youden = m.se + m.sp - 1;
m.lrPos = m.se / max(1 - m.sp, eps);
m.lrNeg = (1 - m.se) / max(m.sp, eps);
end

function [p, ci] = prop(k, n)
if n == 0
    p = NaN;
    ci = [NaN NaN];
else
    p = k / n;
    ci = netra.eval.wilson(k, n);
end
end
