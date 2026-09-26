function loss = lossFcn(Y, T, classWeights, lambda, cost)
%LOSSFCN Class-weighted cross-entropy plus an expected ordinal-cost penalty.
%
%   loss = netra.grading.cnn.lossFcn(Y, T, w, lambda, cost)
%     Y     K x B softmax outputs (dlarray 'CB' during training)
%     T     K x B one-hot targets
%     w     K x 1 class weights (sqrt inverse frequency by default)
%     cost  K x K cost(k, j) of predicting k when the truth is j;
%           ((k - j) / (K - 1))^2 mirrors the quadratic weighted kappa
%
%       loss = CE_w(Y, T) + lambda * mean_b sum_k Y(k, b) * cost(k, y_b)
%
%   The second term makes "moderate predicted as proliferative" cost more
%   than "moderate predicted as severe", which plain cross-entropy ignores.
%   trainnet passes formatted 'CB' dlarrays, and matrix multiplication is
%   not defined for formatted dlarrays, so the labels are stripped first
%   (for 'CB' the stored layout already is K x B). The same code runs on
%   ordinary arrays in the unit tests.
if isa(Y, 'dlarray')
    Y = stripdims(Y);
end
if isa(T, 'dlarray')
    T = stripdims(T);
end
wT = classWeights(:) .* T;
ce = -sum(sum(wT .* log(Y + 1e-7), 1), 2) / max(sum(sum(wT, 1), 2), 1e-7);
expCost = sum(Y .* (cost * T), 1);
loss = ce + lambda * mean(expCost, 2);
end
