function [se, sp] = operatingCurve(P, targetSe)
%OPERATINGCURVE Specificity of the AI at a chosen sensitivity.
%   [se, sp] = netra.sim.operatingCurve(P, targetSe) uses the measured ROC
%   in P.ai.roc (struct with fpr, tpr - written by the validation
%   experiment) when available, otherwise a binormal ROC with area P.ai.auc:
%   negatives ~ N(0, 1), positives ~ N(d, 1), d = sqrt(2) * PhiInv(AUC),
%   so Sp = Phi(d - PhiInv(Se)). This is how the clinical validation feeds
%   the district plan: a better model means fewer false referrals to review.
se = targetSe;
if isstruct(P.ai.roc) && isfield(P.ai.roc, 'tpr') && ~isempty(P.ai.roc.tpr)
    tpr = P.ai.roc.tpr(:);
    fpr = P.ai.roc.fpr(:);
    [tpr, i] = unique(tpr);
    fpr = fpr(i);
    sp = 1 - interp1(tpr, fpr, min(max(targetSe, tpr(1)), tpr(end)), 'linear');
else
    d = sqrt(2) * netra.util.phiinv(P.ai.auc);
    sp = netra.util.phi(d - netra.util.phiinv(targetSe));
end
end
