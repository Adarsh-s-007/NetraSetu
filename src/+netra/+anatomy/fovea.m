function FV = fovea(E, V, OD, S, cfg)
%FOVEA Locate the foveal centre.
%
%   FV = netra.anatomy.fovea(E, V, OD, S, cfg) searches around the position
%   predicted from the disc - 2.5 DD temporal (towards the FOV centre) and
%   0.3 DD below the disc centre - for the point that is simultaneously
%     dark      macular pigment: minimum of the green channel relative to a
%               2-DD background, after a closing that removes vessels and
%               haemorrhages, smoothed at DD/4
%     avascular the foveal avascular zone: lowest vessel density
%   with a Gaussian prior (sigma 0.6 DD) around the prediction. When the
%   disc was found with low confidence, a macula-centred capture is assumed
%   and the search is centred on the FOV instead.
%
%   FV fields: centre [x y] (canvas px), confidence, expected [x y],
%   distanceDD (disc-fovea distance in disc diameters), consistent (the
%   distance is anatomically plausible: 1.8-3.3 DD).

D = size(E.gN, 1);
Da = round(cfg.scale.anatomyDiameter * 1.02);
f = Da / D;
DDa = OD.pxPerDD * f;
odA = (OD.centre - 0.5) * f + 0.5;
cA = (S.centre - 0.5) * f + 0.5;

G = netra.util.imscale(E.rgbN(:, :, 2), [Da Da]);
m = imresize(E.mask, [Da Da], 'nearest');
Gf = netra.util.fillOutside(G, m, 2);
% a grey-level closing erases dark structures narrower than ~0.35 DD
% (vessels, haemorrhages) while the broad foveal depression survives
Gc = imclose(Gf, strel('disk', max(2, round(0.18 * DDa)), 0));
dark = netra.util.smooth(Gc, DDa / 4) ./ max(netra.util.smooth(Gf, 2 * DDa), 1e-3);
% density of vessel centre-lines (thin and thick alike, blobs excluded)
vd = netra.util.smooth(imresize(double(bwmorph(V.mask, 'thin', Inf)), [Da Da], 'bilinear'), 0.3 * DDa);

side = sign(cA(1) - odA(1));
if side == 0
    side = 1;
end
expected = odA + DDa * [side * cfg.fovea.distanceDD, cfg.fovea.belowDD];
if OD.confidence < 0.35
    expected = cA;
end
[Xa, Ya] = meshgrid(1:Da, 1:Da);
dE = hypot(Xa - expected(1), Ya - expected(2)) / DDa;
search = m & dE <= cfg.fovea.searchRadiusDD & ...
    hypot(Xa - odA(1), Ya - odA(2)) > 1.2 * DDa;
if nnz(search) < 20
    search = m & dE <= 2 * cfg.fovea.searchRadiusDD;
end
[md, sd] = netra.util.robustStats(dark(search));
[mv, sv] = netra.util.robustStats(vd(search));
score = -(dark - md) / sd - 0.4 * (vd - mv) / max(sv, 1e-3) - ...
    0.5 * (dE / cfg.fovea.priorSigmaDD) .^ 2;
score(~search) = -Inf;
[best, i] = max(score(:));
[y, x] = ind2sub([Da Da], i);

% confidence: how much darker than the surrounding macula, and how close
ring = m & hypot(Xa - x, Ya - y) > 0.6 * DDa & hypot(Xa - x, Ya - y) < 1.2 * DDa;
depth = mean(dark(ring)) - dark(y, x);
distDD = hypot(x - odA(1), y - odA(2)) / DDa;
consistent = distDD >= 1.8 && distDD <= 3.3;
conf = netra.util.sigmoid(depth, 0.03, 0.012) * (0.4 + 0.6 * consistent);

FV = struct();
FV.centre = ([x y] - 0.5) / f + 0.5;
FV.expected = (expected - 0.5) / f + 0.5;
FV.confidence = conf;
FV.depth = depth;
FV.distanceDD = distDD;
FV.consistent = consistent;
FV.score = best;
end
