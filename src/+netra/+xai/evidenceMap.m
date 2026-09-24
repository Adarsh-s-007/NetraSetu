function M = evidenceMap(L, A)
%EVIDENCEMAP Where the classical detectors found disease, as a smooth map.
%   M = netra.xai.evidenceMap(L, A) sums the lesion masks weighted by their
%   clinical weight (MA 1, haemorrhage 2, exudate 1.5, CWS 1.5, NV 4) and
%   smooths at 0.15 DD. Shown instead of Grad-CAM when no CNN is loaded, and
%   the reference for the attention-evidence concordance check.
k = L.masks;
W = 1 * double(k.ma) + 2 * double(k.he) + 1.5 * double(k.ex) + 1.5 * double(k.cws) + ...
    4 * double(k.nv);
M = netra.util.smooth(W, 0.15 * A.frame.pxPerDD);
if max(M(:)) > 0
    M = M / max(M(:));
end
end
