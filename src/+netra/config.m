function cfg = config(varargin)
%CONFIG Default parameters for the NetraSetu screening pipeline.
%
%   cfg = netra.config()                         defaults
%   cfg = netra.config('site.json')              defaults merged with a JSON file
%   cfg = netra.config('grading.referralThreshold', 0.32, ...)
%                                                 dotted-path overrides
%
%   Every length is expressed in optic-disc diameters (DD) or micrometres and
%   converted to pixels per image once the disc has been measured. This keeps
%   one parameter set valid for a 565-px DRIVE image, a 4288-px IDRiD image
%   and a smartphone capture alike. 1 DD is taken as 1500 um, the ETDRS
%   convention (a disc area of 1.77 mm^2).

root = fileparts(fileparts(fileparts(mfilename('fullpath'))));

cfg = struct();
cfg.version = netra.version();

% ---------------------------------------------------------------- scale
cfg.scale.workDiameter    = 1024;  % FOV diameter (px) for lesion analysis
cfg.scale.vesselDiameter  = 560;   % FOV diameter for vessel segmentation (DRIVE-like)
cfg.scale.anatomyDiameter = 512;   % FOV diameter for disc / fovea search
cfg.scale.umPerDD         = 1500;  % ETDRS standard disc diameter
cfg.scale.ddPerFOV        = 0.14;  % prior disc diameter / FOV diameter (45-50 deg cameras)
cfg.scale.ddTolerance     = 0.35;  % accepted relative deviation of the measured disc

% -------------------------------------------------------------- quality
q = struct();
q.gradable       = 0.60;   % Q >= gradable (and every sub-score >= minSubscore)
q.recapture      = 0.35;   % Q <  recapture (or any sub-score < failSubscore)
                           % in between: enhance, re-assess, human if still borderline
q.minCoverage    = 0.55;   % visible fraction of the FOV disc
q.weights = struct('field', 1.0, 'focus', 1.5, 'illumination', 1.0, ...
                   'contrast', 1.0, 'artifact', 0.75);
% logistic maps from raw metric to sub-score: s = 1 ./ (1 + exp(-(m - c) / w))
q.focusCenter    = 0.55;  q.focusWidth    = 0.06;   % LoG energy-ratio sharpness index
q.contrastCenter = 0.090; q.contrastWidth = 0.020;  % vessel contrast of normalised green
q.lumaCenter     = 0.14;  q.lumaWidth     = 0.035;  % mean FOV luminance
q.noiseCenter    = 0.025; q.noiseWidth    = 0.004;  % relative noise that makes grading unsafe
q.darkMaxFrac    = 0.25;  % fraction of FOV allowed to be under-exposed
q.brightMaxFrac  = 0.08;  % fraction allowed to be saturated (green channel)
q.darkLevel      = 0.35;  % local luminance / median luminance counted as "dark"
q.saturation     = 0.98;
q.noiseHigh      = 0.010; % relative noise above which enhancement denoises
q.uniformityMin  = 0.65;  q.uniformityWidth = 0.05;
q.shadowMax      = 0.12;  % in-frame part of the aperture lost to lid/lash shadow
q.minSubscore    = 0.50;  % every criterion must pass for GRADABLE
q.failSubscore   = 0.15;  % any criterion below this forces RECAPTURE
cfg.quality = q;

% ------------------------------------------------------------ enhancement
e = struct();
e.claheClip      = 0.010;  % base CLAHE clip limit, adapted to measured contrast
e.claheTiles     = [8 8];
e.backgroundDD   = 0.55;   % scale of the illumination (background) estimate
e.denoise        = true;
e.targetRGB      = [0.72 0.36 0.16]; % colour the background is normalised to
cfg.enhance = e;

% --------------------------------------------------------------- vessels
v = struct();
v.hessianSigmas  = [1 1.5 2 3 4];   % px at vesselDiameter
v.frangiBeta     = 0.5;
v.frangiC        = 0.5;             % fraction of the max Hessian norm
v.lineWindow     = 15;              % Nguyen et al. 2013 window W
v.lineScales     = 1:2:15;
v.lineAngles     = 12;
v.tophatLengths  = [7 11 15];
v.weights        = struct('hessian', 0.40, 'line', 0.40, 'tophat', 0.20);
v.highFraction   = 0.075;           % hysteresis seeds: top 7.5 % of FOV pixels
v.lowFraction    = 0.125;           % grow into the top 12.5 %
v.minAreaDD2     = 0.004;           % smallest kept component (DD^2)
v.thickWidthDD   = 0.055;           % "major vessel" calibre (~80 um)
cfg.vessels = v;

% ------------------------------------------------------------ optic disc
o = struct();
o.wBrightness    = 1.0;
o.wThickVessels  = 0.8;
o.wVertical      = 0.8;
o.wConvergence   = 1.0;
o.maxRadiusFOV   = 0.92;            % disc centre allowed up to 0.92 R from FOV centre
o.refineWindowDD = 1.7;
cfg.od = o;

% ----------------------------------------------------------------- fovea
f = struct();
f.distanceDD     = 2.5;             % disc-to-fovea distance
f.belowDD        = 0.30;            % fovea lies slightly below the disc centre
f.searchRadiusDD = 1.1;
f.priorSigmaDD   = 0.6;
f.fazRadiusDD    = 0.25;
cfg.fovea = f;

% ------------------------------------------------------- microaneurysms
m = struct();
m.maxMAUm        = 125;             % clinical upper bound for an MA
m.maxDotUm       = 250;             % larger round red dots are dot haemorrhages
m.minUm          = 15;
m.sigmaUm        = [9 13 19 28 42 63];  % LoG scales (sigma, um)
m.openingDD      = 0.20;            % length of the linear SEs that keep vessels
m.openingAngles  = 12;
m.thresholdK     = 4.0;             % robust z of the blob response
m.minContrast    = 0.020;           % candidate floor (fractional darkening)
m.minAmplitude   = 0.050;           % fitted darkening a grader can see (~5 %)
m.maxCandidates  = 600;
m.fitRadius      = 3.0;             % fit window = fitRadius * sigma + 2 px
m.minSNR         = 3.5;             % amplitude / local background texture
m.minR2          = 0.40;
m.minRoundness   = 0.55;            % Hessian eigenvalue ratio l1/l2 (1 = circular)
m.maxExit        = 0.35;            % ring-profile peak / amplitude (vessel leaving the dot)
m.maxIter        = 30;
cfg.ma = m;

% ------------------------------------------------------------ haemorrhages
h = struct();
h.minDarkening   = 0.08;
h.thresholdK     = 3.5;
h.openRadiusUm   = 60;              % removes vessels narrower than ~120 um
h.minAreaUm2     = 125^2;
h.flameEcc       = 0.88;
h.flameAlign     = 0.70;            % |cos| between long axis and disc-radial direction
h.flameMinLenUm  = 200;
h.preretinalDA   = 1.0;             % area (disc areas) of a pre-retinal bleed
cfg.he = h;

% ---------------------------------------------------- exudates and CWS
x = struct();
x.minBrightening = 0.08;
x.thresholdK     = 4.5;
x.sharpEdge      = 0.55;            % boundary sharpness separating EX from CWS
x.minYellow      = 2.0;             % Lab b* excess over background (EX are yellow)
x.cwsMinDD       = 0.08;            % CWS equivalent diameter range (DD)
x.cwsMaxDD       = 0.60;
x.cwsMaxEcc      = 0.88;            % CWS are roundish, sheen is streaky
x.cwsMinSolidity = 0.60;            % ... and compact, not ragged
x.dmeRadiusDD    = 1.0;             % IDRiD DME grade 2: exudate within 1 DD of fovea
x.centreRadiusDD = 1 / 3;           % ~500 um: centre-involving surrogate
x.odExclusion    = 1.80;            % disc radii masked out (peripapillary atrophy)
cfg.ex = x;

% ------------------------------------------------------ neovascularisation
n = struct();
n.windowDD       = 0.50;
n.strideDD       = 0.25;
n.discZoneDD     = 1.50;            % "on or within 1 DD of the disc" (radius from centre)
n.threshold      = 8.5;             % summed, capped one-sided robust z
n.zCap           = 3.0;             % per-feature cap (needs >= 3 features raised)
n.minWindows     = 2;
n.normativeModel = '';              % optional population model (see trainNVNormative)
cfg.nv = n;

% ------------------------------------------------------ venous calibre
b = struct();
b.minSegmentDD   = 0.45;
b.minWidthDD     = 0.040;
b.beadingIndex   = 0.18;            % std of detrended calibre / mean calibre
b.acfPeak        = 0.40;            % periodicity of the calibre oscillation
b.minBeadedSegs  = 1;               % beaded vein segments needed per quadrant
cfg.vb = b;

% ---------------------------------------------------------------- rules
r = struct();
r.maHighProb     = 0.80;
r.maMinHigh      = 1;               % >= 1 confident MA, or
r.maMinCount     = 4;               % >= 4 probable MAs  -> MA present
r.hePerQuadrant  = 10;              % single-field adaptation of ">20 per quadrant"
r.heQuadrants    = 4;
r.vbQuadrants    = 2;
r.irmaQuadrants  = 1;
r.nvProb         = 0.50;
r.irmaProb       = 0.50;
r.lesionProb     = 0.50;
r.evidenceFloor  = 0.30;            % detector scores below this count as absent
r.smoothing      = 0.10;            % shrinkage of the rule distribution to the prior
r.gradePrior     = [0.62 0.12 0.16 0.05 0.05];  % typical screening case-mix, grades 0-4
cfg.rules = r;

% --------------------------------------------------------------- grading
g = struct();
g.referralThreshold = 0.50;         % replaced by the validated operating point
g.urgentThreshold   = 0.35;         % P(PDR)
g.conformalAlpha    = 0.10;
g.disagreement      = 2;            % branch disagreement (grades) forcing review
g.mcSamples         = 256;
g.tta               = 4;
g.cnnInputSize      = 448;
g.cnnBackbone       = 'resnet50';
g.useCNN            = true;
g.useLesionModel    = true;
g.qaSampleRate      = 0.05;         % share of auto-cleared eyes sent for audit
% follow-up intervals shown on the report; set them to the local programme
% protocol (the defaults follow the spirit of the ICO Guidelines for Diabetic
% Eye Care for low-resource settings - verify before deployment)
g.followUp = struct('ROUTINE', 'Re-screen in 12 months', ...
    'REFER', 'Ophthalmologist within 4 weeks', ...
    'URGENT', 'Ophthalmologist within 1 week', ...
    'HUMAN_REVIEW', 'Specialist review of the images within 48 hours', ...
    'RECAPTURE', 'Retake the photograph now');
cfg.grading = g;

% --------------------------------------------------------- explainability
cfg.xai.method          = 'gradcam++';
cfg.xai.layer           = '';        % empty: last convolutional block
cfg.xai.concordanceMin  = 0.35;

% ---------------------------------------------------------------- report
cfg.report.programme  = 'District Diabetic Retinopathy Screening Programme';
cfg.report.site       = 'Primary Health Centre';
cfg.report.languages  = {'en', 'hi'};
cfg.report.disclaimer = ['AI-assisted screening result. Not a diagnosis. ', ...
    'A qualified grader or ophthalmologist confirms every referral.'];

% ---------------------------------------------------------------- paths
cfg.paths.root    = root;
cfg.paths.models  = fullfile(root, 'models');
cfg.paths.results = fullfile(root, 'results');

cfg.verbose = false;

% ------------------------------------------------------------ overrides
if isempty(varargin)
    return
end
if numel(varargin) == 1 && ischar(varargin{1})
    txt = fileread(varargin{1});
    cfg = mergeStruct(cfg, jsondecode(txt));
    return
end
if numel(varargin) == 1 && isstruct(varargin{1})
    cfg = mergeStruct(cfg, varargin{1});
    return
end
if mod(numel(varargin), 2) ~= 0
    error('netra:config:pairs', 'Overrides must be dotted-path/value pairs.');
end
for k = 1:2:numel(varargin)
    cfg = setPath(cfg, char(varargin{k}), varargin{k + 1});
end
end

function s = mergeStruct(s, o)
f = fieldnames(o);
for k = 1:numel(f)
    if isfield(s, f{k}) && isstruct(s.(f{k})) && isstruct(o.(f{k}))
        s.(f{k}) = mergeStruct(s.(f{k}), o.(f{k}));
    else
        s.(f{k}) = o.(f{k});
    end
end
end

function s = setPath(s, path, value)
parts = strsplit(path, '.');
if numel(parts) == 1
    if ~isfield(s, parts{1})
        error('netra:config:unknown', 'Unknown configuration field "%s".', path);
    end
    s.(parts{1}) = value;
    return
end
if ~isfield(s, parts{1}) || ~isstruct(s.(parts{1}))
    error('netra:config:unknown', 'Unknown configuration group "%s".', parts{1});
end
s.(parts{1}) = setPath(s.(parts{1}), strjoin(parts(2:end), '.'), value);
end
