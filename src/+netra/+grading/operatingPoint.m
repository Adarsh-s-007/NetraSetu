function op = operatingPoint(score, label, varargin)
%OPERATINGPOINT Referral threshold with a guaranteed sensitivity.
%
%   op = netra.grading.operatingPoint(pReferable, isReferable) returns the
%   highest threshold whose sensitivity on the calibration set is at least
%   'Target' (default 0.90) - not as a point estimate but as the lower bound
%   of its 95 % Wilson interval ('Guarantee', 'wilson', the default) - and
%   therefore the best specificity compatible with that guarantee.
%   'Guarantee', 'point' uses the point estimate instead.
%
%   op fields: threshold, se, seCI, sp, spCI, ppv, npv, nPos, nNeg, target.
%   A validation set with few referable eyes pays for the guarantee with a
%   lower threshold; that is the correct clinical trade-off.

o = netra.util.opts(struct('Target', 0.90, 'Guarantee', 'wilson', 'Alpha', 0.05), varargin{:});
score = score(:);
label = logical(label(:));
pos = score(label);
neg = score(~label);
cand = sort(unique(score), 'descend');
best = [];
for t = cand'
    tp = nnz(pos >= t);
    se = tp / max(numel(pos), 1);
    ci = netra.eval.wilson(tp, numel(pos), o.Alpha);
    ok = se >= o.Target;
    if strcmpi(o.Guarantee, 'wilson')
        ok = ci(1) >= o.Target;
    end
    if ok
        best = t;
        break
    end
end
if isempty(best)
    best = min(score);
end
op = netra.eval.binaryMetrics(label, score >= best);
op.threshold = best;
op.target = o.Target;
op.guarantee = o.Guarantee;
end
