function F = trainFusion(branchProbs, y, varargin)
%TRAINFUSION Learn the ordinal stacking model that fuses the three branches.
%
%   F = netra.grading.trainFusion(branchProbs, y) with branchProbs a struct
%   whose fields ('cnn', 'lesion', 'rules') are N x 5 OUT-OF-FOLD probability
%   matrices (predictions for each training eye from a model that never saw
%   it - cross-fitting avoids the optimism of stacking in-sample outputs)
%   and y the reference grades 0..4.
%
%   Options: 'Branches' (default: all fields present), 'Lambda' (1e-2),
%   'Weights' (per-eye weights, e.g. inverse class frequency).
%
%   F fields: model (netra.grading.ordinalLogit), branches, featureNames,
%   and slopes - a table-like struct showing how strongly each branch moves
%   each severity boundary (reported in the validation dossier).

o = netra.util.opts(struct('Branches', {fieldnames(branchProbs)'}, 'Lambda', 1e-2, ...
    'Weights', []), varargin{:});
X = netra.grading.stackFeatures(branchProbs, o.Branches);
model = netra.grading.ordinalLogit('fit', X, y(:), 'Lambda', o.Lambda, 'Weights', o.Weights, 'K', 5);
names = {};
for k = 1:numel(o.Branches)
    for g = 1:4
        names{end + 1} = sprintf('%s: logit P(grade >= %d)', o.Branches{k}, g); %#ok<AGROW>
    end
end
F = struct('model', model, 'branches', {o.Branches}, 'featureNames', {names});
F.slopes = struct('feature', names, 'standardisedSlope', num2cell(model.beta(:)'));
end
