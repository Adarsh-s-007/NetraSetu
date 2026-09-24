function A = analyze(S, E, cfg)
%ANALYZE Retinal anatomy: vessels, optic disc, fovea and coordinate frame.
%
%   A = netra.anatomy.analyze(S, E, cfg) with S from netra.quality.standardize
%   and E from netra.quality.enhance. A.flags collects anatomy problems that
%   must be shown to the reader (e.g. 'disc-uncertain', 'fovea-uncertain',
%   'geometry-implausible'); any flag routes the case to human review.

V = netra.anatomy.vessels(E.gN, E.mask, cfg);
OD = netra.anatomy.opticDisc(E, V, S, cfg);
FV = netra.anatomy.fovea(E, V, OD, S, cfg);
F = netra.anatomy.frame(OD, FV, size(E.gN, 1), cfg);

flags = {};
if OD.confidence < 0.35
    flags{end + 1} = 'disc-uncertain';
end
if FV.confidence < 0.35
    flags{end + 1} = 'fovea-uncertain';
end
if ~FV.consistent
    flags{end + 1} = 'geometry-implausible';
end
A = struct('vessels', V, 'od', OD, 'fovea', FV, 'frame', F);
A.flags = flags;
A.confidence = min(OD.confidence, FV.confidence);
end
