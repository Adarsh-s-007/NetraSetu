function dc = foveaCompensate(d, F, mask)
%FOVEACOMPENSATE Remove the smooth foveal depression from a darkening image.
%   dc = netra.lesions.foveaCompensate(d, F, mask) subtracts the radial
%   profile of d around the fovea (the median over rings 0.05 DD wide, out to
%   1.6 DD). The macular pigment darkening is radially symmetric and wide;
%   haemorrhages near the fovea are small and asymmetric, so a ring median
%   captures the former and ignores the latter. Without this step the fovea
%   itself would be reported as a haemorrhage.
dc = d;
r = F.distFovea;
edges = 0:0.05:1.6;
prof = zeros(1, numel(edges) - 1);
for k = 1:numel(edges) - 1
    ring = mask & r >= edges(k) & r < edges(k + 1);
    if nnz(ring) >= 8
        prof(k) = median(d(ring));
    end
end
outer = mask & r >= 1.6 & r < 2.0;
base = 0;
if any(outer(:))
    base = median(d(outer));
end
prof = max(prof - base, 0);
prof = movmean(prof, 3);
centres = (edges(1:end - 1) + edges(2:end)) / 2;
inside = mask & r < 1.6;
dc(inside) = d(inside) - interp1(centres, prof, min(max(r(inside), centres(1)), centres(end)), 'linear');
end
