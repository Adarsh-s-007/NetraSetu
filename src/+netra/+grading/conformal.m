function out = conformal(action, varargin)
%CONFORMAL Split-conformal prediction sets for the severity grade.
%
%   C    = netra.grading.conformal('calibrate', P, y, alpha)
%   sets = netra.grading.conformal('predict', P, C)
%
%   Calibration uses the score s = 1 - P(true grade) on held-out images and
%   takes its ceil((n + 1)(1 - alpha)) / n empirical quantile (Vovk; Angelopoulos
%   & Bates 2021). Every grade whose probability is at least 1 - qhat is
%   included; for an ordinal scale the set is then closed into a contiguous
%   range (a superset, so coverage is preserved). Under exchangeability the
%   true grade lies in the set for at least 1 - alpha of future images,
%   whatever the underlying model.
%
%   Clinically: a set {1, 2} straddles the referral boundary and triggers
%   human review, a set {0} does not.
%
%   sets is an N x K logical matrix (column k = grade k-1).

switch lower(action)
    case 'calibrate'
        [P, y, alpha] = deal(varargin{:});
        n = numel(y);
        s = 1 - P(sub2ind(size(P), (1:n)', y(:) + 1));
        k = min(n, ceil((n + 1) * (1 - alpha)));
        ss = sort(s);
        out = struct('qhat', ss(k), 'alpha', alpha, 'n', n);
    case 'predict'
        [P, C] = deal(varargin{:});
        sets = P >= 1 - C.qhat;
        [~, am] = max(P, [], 2);
        sets(sub2ind(size(P), (1:size(P, 1))', am)) = true;
        for i = 1:size(sets, 1)
            f = find(sets(i, :), 1, 'first');
            l = find(sets(i, :), 1, 'last');
            sets(i, f:l) = true;
        end
        out = sets;
    otherwise
        error('netra:conformal:action', 'Unknown action "%s".', action);
end
end
