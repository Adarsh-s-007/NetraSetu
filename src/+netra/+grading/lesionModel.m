function out = lesionModel(action, varargin)
%LESIONMODEL Interpretable ensemble on clinically named lesion features.
%
%   model = netra.grading.lesionModel('train', X, y, names)
%   model = netra.grading.lesionModel('train', X, y, names, 'KFold', 5, 'Trees', 300)
%   P     = netra.grading.lesionModel('predict', model, X)
%   phi   = netra.grading.lesionModel('explain', model, x)
%
%   Bagged decision trees (random forest, fitcensemble) on the 32 features
%   of netra.grading.lesionFeatures, with class-balanced weights. Training
%   also returns out-of-fold posteriors (model.oof) for the fusion model.
%   'explain' returns Shapley values of P(referable) = P(2) + P(3) + P(4) for
%   one eye (Statistics and Machine Learning Toolbox, R2021a or later):
%   the report lists the features that pushed this eye towards referral.
%
%   Requires MATLAB with the Statistics and Machine Learning Toolbox; under
%   GNU Octave 'predict' returns [] and the pipeline falls back to the rule
%   engine and CNN.

switch lower(action)
    case 'train'
        out = train(varargin{:});
    case 'predict'
        model = varargin{1};
        X = varargin{2};
        out = [];
        if isempty(model) || netra.util.isOctave()
            return
        end
        [~, score] = predict(model.mdl, X);
        out = score ./ sum(score, 2);
    case 'explain'
        out = explain(varargin{:});
    otherwise
        error('netra:lesionModel:action', 'Unknown action "%s".', action);
end
end

function model = train(X, y, names, varargin)
o = netra.util.opts(struct('KFold', 5, 'Trees', 300, 'MaxNumSplits', 40, ...
    'MinLeafSize', 3, 'Seed', 11), varargin{:});
if netra.util.isOctave() || ~netra.util.has('fitcensemble')
    error('netra:lesionModel:toolbox', ...
        'Training the lesion ensemble needs the Statistics and Machine Learning Toolbox.');
end
rng(o.Seed);
y = y(:);
X(~isfinite(X)) = 0;
cnt = accumarray(y + 1, 1, [5 1]);
w = 1 ./ max(cnt(y + 1), 1);
w = w / mean(w);
t = templateTree('MaxNumSplits', o.MaxNumSplits, 'MinLeafSize', o.MinLeafSize, ...
    'Reproducible', true);
mdl = fitcensemble(X, y, 'Method', 'Bag', 'NumLearningCycles', o.Trees, ...
    'Learners', t, 'ClassNames', 0:4, 'Weights', w, 'PredictorNames', names);
cvm = crossval(mdl, 'KFold', o.KFold);
[~, oof] = kfoldPredict(cvm);
oof = oof ./ sum(oof, 2);
nb = min(200, size(X, 1));
bg = X(randperm(size(X, 1), nb), :);
model = struct('type', 'lesionEnsemble', 'mdl', compact(mdl), 'names', {names}, ...
    'oof', oof, 'background', bg, 'importance', predictorImportance(mdl), ...
    'trained', datestr(now, 'yyyy-mm-dd HH:MM'));
end

function phi = explain(model, x)
% Shapley values of P(referable) for one eye; [] when unavailable.
phi = [];
if isempty(model) || netra.util.isOctave() || ~netra.util.has('shapley')
    return
end
try
    f = @(Z) referable(model, Z);
    ex = shapley(f, model.background, 'QueryPoint', x);
    v = ex.ShapleyValues;
    vals = v{:, end};
    [~, order] = sort(abs(vals), 'descend');
    phi = struct('feature', model.names(order), 'value', num2cell(x(order)), ...
        'shapley', num2cell(vals(order)'));
catch err
    warning('netra:lesionModel:shapley', 'Shapley explanation skipped: %s', err.message);
end
end

function p = referable(model, Z)
[~, s] = predict(model.mdl, Z);
s = s ./ sum(s, 2);
p = sum(s(:, 3:5), 2);
end
