function F = frame(OD, FV, D, cfg)
%FRAME Retinal coordinate frame anchored on the fovea and the optic disc.
%
%   F = netra.anatomy.frame(OD, FV, D, cfg) defines, for a D x D canvas,
%     unit      disc diameters: F.pxPerDD, F.umPerPx (1 DD = cfg.scale.umPerDD)
%     axes      nasal (fovea -> disc) and superior unit vectors
%     eye       'R' when the disc lies to the right of the fovea (standard,
%               non-inverted fundus photographs), else 'L'
%     maps      distFovea, distDisc (DD), quadrant (1 ST, 2 SN, 3 IN, 4 IT)
%     zones     ETDRS centre (<= 1/3 DD ~ 500 um), inner (<= 1 DD),
%               outer (<= 2 DD) subfields around the fovea; disc zone
%               (within cfg.nv.discZoneDD of the disc centre)
%   Quadrants are split by the disc-fovea axis and its perpendicular
%   through the fovea: the single-field analogue of the four mid-peripheral
%   ETDRS fields used by the 4-2-1 rule.

F = struct();
F.pxPerDD = OD.pxPerDD;
F.umPerPx = cfg.scale.umPerDD / OD.pxPerDD;
F.od = OD.centre;
F.odRadius = OD.radius;
F.fovea = FV.centre;
nasal = OD.centre - FV.centre;
if norm(nasal) < eps
    nasal = [1 0];
end
nasal = nasal / norm(nasal);
sup = [nasal(2), -nasal(1)];
if sup(2) > 0
    sup = -sup;
end
F.nasal = nasal;
F.superior = sup;
if OD.centre(1) >= FV.centre(1)
    F.eye = 'R';
else
    F.eye = 'L';
end
[X, Y] = meshgrid(1:D, 1:D);
dx = X - FV.centre(1);
dy = Y - FV.centre(2);
F.distFovea = hypot(dx, dy) / F.pxPerDD;
F.distDisc = hypot(X - OD.centre(1), Y - OD.centre(2)) / F.pxPerDD;
u = dx * nasal(1) + dy * nasal(2);
v = dx * sup(1) + dy * sup(2);
Q = zeros(D);
Q(u < 0 & v >= 0) = 1;
Q(u >= 0 & v >= 0) = 2;
Q(u >= 0 & v < 0) = 3;
Q(u < 0 & v < 0) = 4;
F.quadrant = Q;
F.quadrantNames = {'superotemporal', 'superonasal', 'inferonasal', 'inferotemporal'};
F.zone.centre = F.distFovea <= cfg.ex.centreRadiusDD;
F.zone.inner = F.distFovea <= 1;
F.zone.outer = F.distFovea <= 2;
F.zone.disc = F.distDisc <= cfg.nv.discZoneDD;
end
