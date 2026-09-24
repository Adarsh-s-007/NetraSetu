function info = netrasetu_setup(varargin)
%NETRASETU_SETUP Put NetraSetu on the path and report which toolboxes are usable.
%
%   netrasetu_setup            adds src/, experiments/, simulink/ and tests/helpers
%   info = netrasetu_setup     also returns a capability struct
%   netrasetu_setup('quiet')   suppresses the capability table
%
%   The classical pipeline (quality, anatomy, lesions, rules, evaluation,
%   district simulation) needs only the Image Processing Toolbox. The CNN
%   branch and Grad-CAM need the Deep Learning Toolbox, the lesion ensemble
%   and Bayesian optimisation need the Statistics and Machine Learning
%   Toolbox, and the telescreening model needs Simulink. Missing toolboxes
%   switch the corresponding branch off; nothing else breaks.
%
%   Under GNU Octave (used for the repository's CI) the Octave shims in
%   tests/octave_shims are added so the same source runs unchanged.

quiet = any(strcmpi(varargin, 'quiet'));
root = fileparts(mfilename('fullpath'));

addpath(fullfile(root, 'src'));
addpath(fullfile(root, 'experiments'));
addpath(fullfile(root, 'simulink'));
addpath(fullfile(root, 'tests', 'helpers'));

isOctave = exist('OCTAVE_VERSION', 'builtin') > 0;
if isOctave
    pkgs = {'image', 'statistics'};
    w = warning('off', 'all');          % statistics shadows core functions noisily
    for k = 1:numel(pkgs)
        try
            pkg('load', pkgs{k});
        catch
            warning(w);
            warning('netra:setup:pkg', 'Octave package "%s" could not be loaded.', pkgs{k});
            w = warning('off', 'all');
        end
    end
    warning(w);
    addpath(fullfile(root, 'tests', 'octave_shims'));
end

info = struct();
info.root = root;
info.isOctave = isOctave;
info.imageProcessing = hasFn('imopen') && hasFn('regionprops');
info.deepLearning = ~isOctave && hasFn('dlnetwork') && hasFn('dlfeval');
info.statistics = ~isOctave && hasFn('fitcensemble');
info.bayesopt = ~isOctave && hasFn('bayesopt');
info.simulink = ~isOctave && hasFn('new_system') && hasFn('sim');
info.computerVision = ~isOctave && hasFn('insertShape');
info.gpu = false;
if info.deepLearning
    try
        info.gpu = gpuDeviceCount > 0;
    catch
        info.gpu = false;
    end
end

if ~quiet
    fprintf('\n  NetraSetu %s  |  root: %s\n', netra.version(), root);
    fprintf('  %-34s %s\n', 'Runtime', ternary(isOctave, 'GNU Octave (CI mode)', 'MATLAB'));
    rows = {
        'Image Processing (core pipeline)', info.imageProcessing
        'Deep Learning (CNN + Grad-CAM)',   info.deepLearning
        'Statistics & ML (lesion model)',   info.statistics
        'Bayesian optimisation (planner)',  info.bayesopt
        'Simulink (telescreening model)',   info.simulink
        'Computer Vision (annotations)',    info.computerVision
        'GPU available',                    info.gpu};
    for k = 1:size(rows, 1)
        fprintf('  %-34s %s\n', rows{k, 1}, ternary(rows{k, 2}, 'yes', '-- (branch disabled)'));
    end
    fprintf('\n');
end
end

function tf = hasFn(name)
tf = exist(name) > 0; %#ok<EXIST> builtins and classes report non-2 codes
end

function out = ternary(cond, a, b)
if cond
    out = a;
else
    out = b;
end
end
