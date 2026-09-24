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
m.se = tp / max(tp + fn, 1);
m.seCI = netra.eval.wilson(tp, tp + fn);
m.sp = tn / max(tn + fp, 1);
m.spCI = netra.eval.wilson(tn, tn + fp);
m.ppv = tp / max(tp + fp, 1);
m.ppvCI = netra.eval.wilson(tp, tp + fp);
m.npv = tn / max(tn + fn, 1);
m.npvCI = netra.eval.wilson(tn, tn + fn);
m.acc = (tp + tn) / max(numel(truth), 1);
m.f1 = 2 * tp / max(2 * tp + fp + fn, 1);
den = sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn));
m.mcc = (tp * tn - fp * fn) / max(den, eps);
m.youden = m.se + m.sp - 1;
m.lrPos = m.se / max(1 - m.sp, eps);
m.lrNeg = (1 - m.se) / max(m.sp, eps);
end
