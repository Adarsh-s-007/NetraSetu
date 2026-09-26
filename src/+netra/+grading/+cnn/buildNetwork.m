function [net, info] = buildNetwork(backbone, numClasses, inputSize)
%BUILDNETWORK ImageNet-pretrained backbone re-headed for DR grading.
%
%   [net, info] = netra.grading.cnn.buildNetwork('resnet50', 5, 448)
%
%   Loads the pretrained backbone ('resnet50' default; 'resnet18' for
%   laptops without a GPU; 'efficientnetb0'; 'squeezenet', which ships with
%   the Deep Learning Toolbox and needs no support package; any name
%   accepted by imagePretrainedNetwork or available as a function), then
%     - replaces the image input layer by one of inputSize x inputSize x 3,
%       keeping the pretrained normalisation (per-channel mean / std),
%     - replaces the classifier - the last fully connected layer, or the
%       final 1x1 convolution of SqueezeNet-style heads - by one with
%       numClasses outputs and a 10x learning-rate factor,
%     - removes the classification output layer (the network ends in
%       softmax, as trainnet and dlnetwork expect).
%   Layers are located by type, not by name, so the same code works across
%   backbones and MATLAB releases (R2023b+ recommended for trainnet).
%
%   info fields: inputSize, logitLayer (the layer feeding the softmax - the
%   logits used for temperature scaling and Grad-CAM), featureLayer (the
%   activation feeding global pooling - the Grad-CAM target), outputLayer
%   (softmax), backbone.

if nargin < 1 || isempty(backbone), backbone = 'resnet50'; end
if nargin < 2 || isempty(numClasses), numClasses = 5; end
if nargin < 3 || isempty(inputSize), inputSize = 448; end
if netra.util.isOctave()
    error('netra:cnn:octave', 'The CNN branch requires MATLAB with the Deep Learning Toolbox.');
end

% ---------------------------------------------- pretrained layer graph
if exist('imagePretrainedNetwork', 'file') == 2
    base = imagePretrainedNetwork(backbone);           % dlnetwork, R2024a+
else
    base = feval(backbone);                             % DAGNetwork, support package
end
lg = layerGraph(base);
L = lg.Layers;
isType = @(cls) arrayfun(@(l) isa(l, cls), L);

% ------------------------------------------------------- input layer
inIdx = find(isType('nnet.cnn.layer.ImageInputLayer'), 1);
old = L(inIdx);
args = {'Name', old.Name, 'Normalization', old.Normalization};
switch lower(char(old.Normalization))
    case 'zerocenter'
        args = [args, {'Mean', perChannel(old.Mean)}];
    case 'zscore'
        args = [args, {'Mean', perChannel(old.Mean), 'StandardDeviation', perChannel(old.StandardDeviation)}];
    case 'rescale-symmetric'
        args = [args, {'Min', perChannel(old.Min), 'Max', perChannel(old.Max)}];
    case 'rescale-zero-one'
        args = [args, {'Min', perChannel(old.Min), 'Max', perChannel(old.Max)}];
end
lg = replaceLayer(lg, old.Name, imageInputLayer([inputSize inputSize 3], args{:}));

% ------------------------------------------------- classification head
fcIdx = find(isType('nnet.cnn.layer.FullyConnectedLayer'), 1, 'last');
if ~isempty(fcIdx)
    head = 'fc_dr';
    lg = replaceLayer(lg, L(fcIdx).Name, fullyConnectedLayer(numClasses, 'Name', head, ...
        'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10));
else
    % SqueezeNet-style heads classify with a final 1x1 convolution
    cvIdx = find(isType('nnet.cnn.layer.Convolution2DLayer'), 1, 'last');
    if isempty(cvIdx)
        error('netra:cnn:head', 'No classifier layer found in backbone "%s".', backbone);
    end
    head = 'conv_dr';
    lg = replaceLayer(lg, L(cvIdx).Name, convolution2dLayer(1, numClasses, 'Name', head, ...
        'WeightLearnRateFactor', 10, 'BiasLearnRateFactor', 10));
end
outIdx = find(isType('nnet.cnn.layer.ClassificationOutputLayer'));
for k = numel(outIdx):-1:1
    lg = removeLayers(lg, L(outIdx(k)).Name);
end
smIdx = find(isType('nnet.cnn.layer.SoftmaxLayer'), 1, 'last');
if isempty(smIdx)
    if ~strcmp(head, 'fc_dr')
        error('netra:cnn:head', 'Backbone "%s" has a convolutional head but no softmax.', backbone);
    end
    lg = addLayers(lg, softmaxLayer('Name', 'softmax_dr'));
    lg = connectLayers(lg, 'fc_dr', 'softmax_dr');
    smName = 'softmax_dr';
else
    smName = L(smIdx).Name;
end
C = lg.Connections;
dst = regexprep(C.Destination, '/.*$', '');

% --------------------------- logits = whatever feeds the softmax layer
% (the new fully connected layer, or SqueezeNet's global pooling)
logitLayer = regexprep(C.Source{find(strcmp(dst, smName), 1)}, '/.*$', '');

% ------------------------- feature layer = input of the global pooling
gapIdx = find(isType('nnet.cnn.layer.GlobalAveragePooling2DLayer'), 1, 'last');
featureLayer = '';
if ~isempty(gapIdx)
    src = C.Source(strcmp(dst, L(gapIdx).Name));
    if ~isempty(src)
        featureLayer = regexprep(src{1}, '/.*$', '');
    end
end

net = dlnetwork(lg);
info = struct('backbone', backbone, 'inputSize', inputSize, 'logitLayer', logitLayer, ...
    'featureLayer', featureLayer, 'outputLayer', smName, 'numClasses', numClasses);
end

function v = perChannel(x)
% pretrained layers may store full-size mean images; keep one value per channel
if isempty(x)
    v = x;
    return
end
if ndims(x) == 3 && (size(x, 1) > 1 || size(x, 2) > 1)
    v = mean(mean(x, 1), 2);
else
    v = x;
end
end
