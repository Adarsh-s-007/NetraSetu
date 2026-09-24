function model = train(trainFiles, trainGrades, valFiles, valGrades, cfg, varargin)
%TRAIN Fine-tune the DR grading CNN with an ordinal-aware loss.
%
%   model = netra.grading.cnn.train(trainFiles, trainGrades, valFiles, valGrades, cfg)
%
%   trainFiles / valFiles are CACHED inputs (netra.grading.cnn.cacheDataset);
%   grades are 0..4. Options:
%     'Backbone'   cfg.grading.cnnBackbone ('resnet50')
%     'Epochs'     15            'BatchSize'  16
%     'LearnRate'  3e-4          'Lambda'     0.5  (ordinal-cost weight)
%     'Checkpoint' ''            folder for per-epoch checkpoints
%     'Plots'      'none'        or 'training-progress'
%
%   Training: Adam, piecewise learning-rate drop, L2 1e-4, early stopping
%   on validation loss (patience 4), best-validation network kept.
%   Augmentation: random rotation (0-360 deg - fundus photographs have no
%   canonical orientation for the network), flips, brightness/contrast
%   jitter of +-10 %, re-blanked rim.
%   After training the softmax temperature is fitted on the validation set.
%
%   model fields: net (dlnetwork), info (buildNetwork), temperature,
%   classWeights, valLogits, valGrades, trained, cfgVersion.
%   Requires MATLAB R2023b+ with the Deep Learning Toolbox (trainnet).

o = netra.util.opts(struct('Backbone', cfg.grading.cnnBackbone, 'Epochs', 15, ...
    'BatchSize', 16, 'LearnRate', 3e-4, 'Lambda', 0.5, 'Checkpoint', '', ...
    'Plots', 'none', 'Seed', 3), varargin{:});
if netra.util.isOctave() || ~netra.util.has('trainnet')
    error('netra:cnn:trainnet', 'CNN training needs MATLAB R2023b+ (trainnet).');
end
rng(o.Seed);
K = 5;
S = cfg.grading.cnnInputSize;
[net, info] = netra.grading.cnn.buildNetwork(o.Backbone, K, S);

trainGrades = trainGrades(:);
valGrades = valGrades(:);
cnt = accumarray(trainGrades + 1, 1, [K 1]);
classW = sqrt(numel(trainGrades) ./ (K * max(cnt, 1)));
classW = classW / mean(classW);
[i, j] = ndgrid(1:K, 1:K);
cost = ((i - j) / (K - 1)) .^ 2;

cats = categorical(0:K - 1);
tdsTrain = combine(transform(imageDatastore(trainFiles), @(x) augment(x, S)), ...
    arrayDatastore(cats(trainGrades + 1)'));
tdsVal = combine(transform(imageDatastore(valFiles), @(x) single(x)), ...
    arrayDatastore(cats(valGrades + 1)'));

itersPerEpoch = max(1, floor(numel(trainGrades) / o.BatchSize));
opts = trainingOptions('adam', ...
    'InitialLearnRate', o.LearnRate, ...
    'MaxEpochs', o.Epochs, ...
    'MiniBatchSize', o.BatchSize, ...
    'Shuffle', 'every-epoch', ...
    'L2Regularization', 1e-4, ...
    'LearnRateSchedule', 'piecewise', ...
    'LearnRateDropPeriod', 5, ...
    'LearnRateDropFactor', 0.3, ...
    'ValidationData', tdsVal, ...
    'ValidationFrequency', itersPerEpoch, ...
    'ValidationPatience', 4, ...
    'OutputNetwork', 'best-validation', ...
    'Verbose', true, ...
    'VerboseFrequency', max(1, floor(itersPerEpoch / 4)), ...
    'Plots', o.Plots, ...
    'ExecutionEnvironment', 'auto');
if ~isempty(o.Checkpoint)
    if ~exist(o.Checkpoint, 'dir'), mkdir(o.Checkpoint); end
    opts.CheckpointPath = o.Checkpoint;
end

loss = @(Y, T) netra.grading.cnn.lossFcn(Y, T, classW, o.Lambda, cost);
net = trainnet(tdsTrain, net, loss, opts);

% ------------------------------------------- temperature on validation
valLogits = logitsOf(net, info, valFiles, o.BatchSize);
T = netra.grading.temperatureScale(valLogits, valGrades);

model = struct('net', net, 'info', info, 'temperature', T, 'classWeights', classW, ...
    'valLogits', valLogits, 'valGrades', valGrades, ...
    'trained', datestr(now, 'yyyy-mm-dd HH:MM'), 'cfgVersion', cfg.version, ...
    'options', o);
end

% ======================================================================
function X = augment(X, S)
X = single(X);
if rand < 0.5, X = fliplr(X); end
if rand < 0.5, X = flipud(X); end
X = imrotate(X, 360 * rand, 'bilinear', 'crop');
gain = 1 + 0.2 * (rand - 0.5);
contrast = 1 + 0.2 * (rand - 0.5);
X = 128 + contrast * (X * gain - 128);
[xx, yy] = meshgrid(1:S, 1:S);
rim = hypot(xx - (S + 1) / 2, yy - (S + 1) / 2) > 0.95 * S / 2 / 1.02;
X(repmat(rim, [1 1 3])) = 128;
X = min(max(X, 0), 255);
end

function L = logitsOf(net, info, files, bs)
n = numel(files);
L = zeros(n, info.numClasses);
for s = 1:bs:n
    idx = s:min(n, s + bs - 1);
    batch = zeros(info.inputSize, info.inputSize, 3, numel(idx), 'single');
    for k = 1:numel(idx)
        batch(:, :, :, k) = single(imread(files{idx(k)}));
    end
    dlX = dlarray(batch, 'SSCB');
    if canUseGPU
        dlX = gpuArray(dlX);
    end
    z = predict(net, dlX, 'Outputs', info.logitLayer);
    L(idx, :) = gather(extractdata(z))';
end
end
