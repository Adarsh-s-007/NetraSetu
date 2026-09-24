function x = stackFeatures(branches, names)
%STACKFEATURES Cumulative logits of each branch, the input of the fusion model.
%   x = netra.grading.stackFeatures(branches, {'cnn', 'lesion', 'rules'})
%   returns [logit P_b(grade >= 1..4) for each branch b], 4 values per
%   branch. branches.(b) may be 1 x 5 or N x 5 (one row per eye).
x = [];
for k = 1:numel(names)
    p = branches.(names{k});
    p = max(min(p, 1 - 1e-4), 1e-4);
    p = p ./ sum(p, 2);
    tail = fliplr(cumsum(fliplr(p), 2));           % P(grade >= g), g = 0..4
    t = min(max(tail(:, 2:5), 1e-4), 1 - 1e-4);
    x = [x, log(t ./ (1 - t))]; %#ok<AGROW>
end
end
