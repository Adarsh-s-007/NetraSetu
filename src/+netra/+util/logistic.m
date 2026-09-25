function out = logistic(action, varargin)
%LOGISTIC Small L2-regularised logistic regression (Newton / IRLS).
%   beta = netra.util.logistic('fit', X, y)            intercept first
%   beta = netra.util.logistic('fit', X, y, lambda, w)
%   p    = netra.util.logistic('predict', beta, X)
%   Used for the DRIVE-trained vessel detector fusion, where X has four
%   columns and millions of pixels do not need a toolbox. The intercept is
%   not penalised.
switch lower(action)
    case 'fit'
        X = varargin{1};
        y = double(varargin{2}(:));
        lambda = 1e-4;
        if numel(varargin) >= 3 && ~isempty(varargin{3})
            lambda = varargin{3};
        end
        n = size(X, 1);
        w = ones(n, 1);
        if numel(varargin) >= 4 && ~isempty(varargin{4})
            w = varargin{4}(:);
        end
        A = [ones(n, 1), X];
        d = size(A, 2);
        R = lambda * sum(w) * diag([0, ones(1, d - 1)]);
        beta = zeros(d, 1);
        for it = 1:50
            p = 1 ./ (1 + exp(-A * beta));
            g = A' * (w .* (p - y)) + R * beta;
            Hs = A' * (A .* repmat(w .* p .* (1 - p), 1, d)) + R;
            step = Hs \ g;
            beta = beta - step;
            if max(abs(step)) < 1e-8
                break
            end
        end
        out = beta;
    case 'predict'
        beta = varargin{1};
        X = varargin{2};
        out = 1 ./ (1 + exp(-[ones(size(X, 1), 1), X] * beta(:)));
    otherwise
        error('netra:util:logistic', 'Unknown action %s.', action);
end
end
