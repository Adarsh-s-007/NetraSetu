function M = loadModels(cfg)
%LOADMODELS Load whichever trained components exist in cfg.paths.models.
%
%   M = netra.loadModels(cfg) looks for
%     netrasetu_cnn.mat      variable 'model'  (netra.grading.cnn.train)
%     lesion_model.mat       variable 'model'  (netra.grading.lesionModel)
%     fusion.mat             variable 'fusion' (netra.grading.trainFusion)
%     calibration.mat        variable 'calibration': conformal (from
%                            netra.grading.conformal) and operatingPoint
%                            (netra.grading.operatingPoint)
%     vessel_fusion.mat      variable 'model'  (logistic vessel fusion, DRIVE)
%     nv_normative.mat       variable 'normative' (grade-0 NV statistics)
%   Missing files simply switch the corresponding component off; M.status
%   lists what is active so reports can state how the grade was produced.
%   MATLAB-only objects (dlnetwork, ensembles) are skipped under Octave.

M = struct('cnn', [], 'lesion', [], 'fusion', [], 'calibration', [], ...
    'vessel', [], 'nvNormative', '', 'status', struct());
d = cfg.paths.models;
octave = netra.util.isOctave();
M.cnn = tryLoad(fullfile(d, 'netrasetu_cnn.mat'), 'model', ~octave);
M.lesion = tryLoad(fullfile(d, 'lesion_model.mat'), 'model', ~octave);
M.fusion = tryLoad(fullfile(d, 'fusion.mat'), 'fusion', true);
M.calibration = tryLoad(fullfile(d, 'calibration.mat'), 'calibration', true);
M.vessel = tryLoad(fullfile(d, 'vessel_fusion.mat'), 'model', true);
nvf = fullfile(d, 'nv_normative.mat');
if exist(nvf, 'file')
    M.nvNormative = nvf;
end
M.status = struct('cnn', ~isempty(M.cnn), 'lesion', ~isempty(M.lesion), ...
    'fusion', ~isempty(M.fusion), 'calibration', ~isempty(M.calibration), ...
    'vessel', ~isempty(M.vessel), 'nvNormative', ~isempty(M.nvNormative));
end

function v = tryLoad(file, var, allowed)
v = [];
if ~allowed || ~exist(file, 'file')
    return
end
try
    S = load(file, var);
    v = S.(var);
catch err
    warning('netra:loadModels:skip', 'Could not load %s: %s', file, err.message);
end
end
