function out = countsPR(action, varargin)
%COUNTSPR Precision-recall and ROC from score histograms (full-resolution images).
%
%   H = netra.eval.countsPR('init', nBins)             nBins score bins on [0, 1]
%   H = netra.eval.countsPR('add', H, score, truth)     accumulate one image
%   m = netra.eval.countsPR('metrics', H)               aupr, auc, curves
%
%   IDRiD scores lesion segmentation by the area under the precision-recall
%   curve over every pixel of every test image - 27 images of 4288 x 2848,
%   330 million pixels. Holding and sorting them all is impractical, so
%   positives and negatives are counted per score bin instead. With scores
%   that are component probabilities the curve is exact up to the bin
%   width (default 1000 bins). The AUPR is the step-wise sum
%   sum_k (R_k - R_(k-1)) P_k, as in netra.eval.prCurve.
switch lower(action)
    case 'init'
        n = 1000;
        if ~isempty(varargin)
            n = varargin{1};
        end
        out = struct('pos', zeros(n + 1, 1), 'neg', zeros(n + 1, 1), 'nBins', n);
    case 'add'
        H = varargin{1};
        s = double(varargin{2}(:));
        t = logical(varargin{3}(:));
        b = min(max(round(s * H.nBins), 0), H.nBins) + 1;
        H.pos = H.pos + accumarray(b(t), 1, [H.nBins + 1, 1]);
        H.neg = H.neg + accumarray(b(~t), 1, [H.nBins + 1, 1]);
        out = H;
    case 'metrics'
        H = varargin{1};
        % thresholds from high to low: predicted positive = score bin >= k
        tp = cumsum(flipud(H.pos));
        fp = cumsum(flipud(H.neg));
        P = sum(H.pos);
        N = sum(H.neg);
        recall = tp / max(P, 1);
        precision = tp ./ max(tp + fp, 1);
        keep = (tp + fp) > 0;
        r = [0; recall(keep)];
        pr = precision(keep);
        aupr = sum(diff(r) .* pr);
        fpr = [0; fp / max(N, 1)];
        tpr = [0; recall];
        auc = trapz(fpr, tpr);
        out = struct('aupr', aupr, 'auc', auc, 'recall', recall(keep), ...
            'precision', pr, 'fpr', fpr, 'tpr', tpr, 'nPos', P, 'nNeg', N);
    otherwise
        error('netra:eval:countsPR', 'Unknown action %s.', action);
end
end
