function files = cacheDataset(fileList, cfg, cacheDir, varargin)
%CACHEDATASET Pre-compute network inputs once (quality mask, crop, Graham).
%
%   files = netra.grading.cnn.cacheDataset(fileList, cfg, cacheDir)
%
%   Standardising a 4288 x 2848 photograph takes far longer than a training
%   step, so every image is converted once to a cfg.grading.cnnInputSize
%   PNG in cacheDir (same base name) and training reads the cache. Files
%   that already exist are skipped, so the step is resumable. Returns the
%   cached file names in the order of fileList ('' when an image could not
%   be read or has no detectable field of view).
%   Option 'Parallel' (false) uses parfor when the Parallel Computing
%   Toolbox is available.

o = netra.util.opts(struct('Parallel', false, 'Verbose', true), varargin{:});
if ~exist(cacheDir, 'dir')
    mkdir(cacheDir);
end
n = numel(fileList);
files = repmat({''}, n, 1);
D = cfg.scale.workDiameter;
if o.Parallel && ~netra.util.isOctave() && netra.util.has('parfor')
    parfor i = 1:n
        files{i} = one(fileList{i}, cfg, cacheDir, D);
    end
else
    t0 = tic;
    for i = 1:n
        files{i} = one(fileList{i}, cfg, cacheDir, D);
        if o.Verbose && (mod(i, 100) == 0 || i == n)
            fprintf('  cached %d / %d  (%.1f min)\n', i, n, toc(t0) / 60);
        end
    end
end
end

function out = one(f, cfg, cacheDir, D)
[~, base] = fileparts(f);
out = fullfile(cacheDir, [base '.png']);
if exist(out, 'file')
    return
end
try
    rgb = netra.util.toRGB(imread(f));
    F = netra.quality.fovMask(rgb);
    if ~F.ok
        out = '';
        return
    end
    S = netra.quality.standardize(rgb, F, D);
    X = netra.grading.cnn.preprocess(S, cfg);
    imwrite(uint8(X), out);
catch err
    warning('netra:cache:skip', 'Skipping %s: %s', f, err.message);
    out = '';
end
end
