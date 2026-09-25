function normative = trainNVNormative(files, cfg, outFile)
%TRAINNVNORMATIVE Population statistics of vessel texture from eyes without DR.
%
%   normative = netra.lesions.trainNVNormative(files, cfg)
%   netra.lesions.trainNVNormative(files, cfg, 'models/nv_normative.mat')
%
%   The neovascularisation detector scores each window by how far its
%   fine-vessel texture (branching density, orientation entropy,
%   tortuosity, loops, vessel length) lies above normal. Without a model,
%   "normal" is the rest of the same eye - robust, but an eye with
%   widespread new vessels partly normalises itself. This function measures
%   normal once, on grade-0 photographs (the exp03 training set), separately
%   for the peripapillary zone and the rest of the retina, as the median
%   and 1.4826 x MAD of every feature at the detector's own sampling
%   points. netra.lesions.neovascularization then uses these population
%   values (cfg.nv.normativeModel, loaded automatically by netra.loadModels).
names = {'branch', 'entropy', 'tortuous', 'loops', 'length'};
vals = {cell(1, numel(names)), cell(1, numel(names))};
used = 0;
for i = 1:numel(files)
    try
        rgb = netra.io.readFundus(files{i});
        F = netra.quality.fovMask(rgb);
        if ~F.ok
            continue
        end
        Q = netra.quality.assess(rgb, cfg, F);
        if strcmp(Q.decision, 'RECAPTURE')
            continue
        end
        S = netra.quality.standardize(rgb, F, cfg.scale.workDiameter);
        E = netra.quality.enhance(S, cfg, Q);
        A = netra.anatomy.analyze(S, E, cfg);
        c = cfg;
        c.nv.normativeModel = '';
        NV = netra.lesions.neovascularization(E, A, c);
        for z = 1:2
            if z == 1
                ref = NV.reference & NV.discZone;
            else
                ref = NV.reference & ~NV.discZone;
            end
            for k = 1:numel(names)
                f = NV.features.(names{k});
                vals{z}{k} = [vals{z}{k}; f(ref)];
            end
        end
        used = used + 1;
    catch err
        warning('netra:nv:normative', 'Skipped %s: %s', files{i}, err.message);
    end
end
if used == 0
    error('netra:nv:normative', 'No usable grade-0 image.');
end
med = zeros(2, numel(names));
sc = zeros(2, numel(names));
for z = 1:2
    for k = 1:numel(names)
        [med(z, k), sc(z, k)] = netra.util.robustStats(vals{z}{k});
    end
end
normative = struct('median', med, 'scale', sc, 'features', {names}, ...
    'zones', {{'disc', 'retina'}}, 'images', used, 'created', datestr(now, 'yyyy-mm-dd'));
if nargin >= 3 && ~isempty(outFile)
    save(outFile, 'normative', '-v7');
end
end
