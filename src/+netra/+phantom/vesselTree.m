function T = vesselTree(geom, varargin)
%VESSELTREE Procedural retinal vascular tree grown from the optic disc.
%
%   T = netra.phantom.vesselTree(geom) returns centre-line samples of an
%   anatomically plausible tree: four artery/vein pairs (superotemporal and
%   inferotemporal arcades that arch around the fovea, superonasal and
%   inferonasal trunks), recursive side branches whose calibres follow
%   Murray's law (w_parent^3 = sum w_child^3), and fine macular twigs that
%   stop at the foveal avascular zone.
%
%   geom fields: od, fovea, fovCentre ([x y]), fovRadius, pxPerDD.
%
%   T fields (one row per centre-line sample, 1 px apart):
%     x, y      position (px)
%     w         local calibre (px)
%     type      1 = artery, 2 = vein
%     id        vessel index into T.vessels (parent, type, quadrant, isMajor)
%
%   Options: 'MinWidth' (px, default 1.0), 'Step' (px, default 1.0),
%            'Tortuosity' (curvature innovation, default 8e-4)

o = netra.util.opts(struct('MinWidth', 1.0, 'Step', 1.0, 'Tortuosity', 8e-4), varargin{:});
DD = geom.pxPerDD;
[e1, e2] = localFrame(geom);

cap = 600000;
T.x = zeros(cap, 1); T.y = zeros(cap, 1); T.w = zeros(cap, 1);
T.type = zeros(cap, 1); T.id = zeros(cap, 1);
T.vessels = struct('parent', {}, 'type', {}, 'quadrant', {}, 'isMajor', {}, ...
    'first', {}, 'last', {});
n = 0;

% trunks: mode, sign (+1 superior / -1 inferior), type, calibre (DD), angle (deg)
trunks = {
    'arcade',  +1, 2, 0.085,   78
    'arcade',  +1, 1, 0.066,   66
    'arcade',  -1, 2, 0.085,  -78
    'arcade',  -1, 1, 0.066,  -66
    'nasal',   +1, 2, 0.060,  118
    'nasal',   +1, 1, 0.048,  106
    'nasal',   -1, 2, 0.060, -118
    'nasal',   -1, 1, 0.048, -106
    'twig',    +1, 1, 0.026,  172
    'twig',    -1, 2, 0.028, -168
    'macular', +1, 1, 0.022,   12
    'macular', -1, 2, 0.024,  -14};
stack = repmat(item([0 0], 0, 0, 0, 0, 0, '', 0, 0, false, 2.1), 0, 1);
for k = 1:size(trunks, 1)
    ang = trunks{k, 5} + 5 * randn;
    off = 0.08 * DD * [cosd(ang) sind(ang)];
    p0 = geom.od + off(1) * e1 + off(2) * e2;
    isMajor = any(strcmp(trunks{k, 1}, {'arcade', 'nasal'}));
    b = 1.95 + 0.35 * (trunks{k, 3} == 2) + 0.10 * randn;   % veins run outside arteries
    stack(end + 1) = item(p0, deg2rad(ang), trunks{k, 4} * DD, trunks{k, 3}, ...
        12 * DD, 0, trunks{k, 1}, trunks{k, 2}, 0, isMajor, b); %#ok<AGROW>
end

while ~isempty(stack)
    v = stack(end);
    stack(end) = [];
    [pts, ws, branches] = growOne(v, geom, e1, e2, o);
    m = size(pts, 1);
    if m < 4 || n + m > cap
        continue
    end
    vid = numel(T.vessels) + 1;
    idx = n + (1:m);
    T.x(idx) = pts(:, 1);
    T.y(idx) = pts(:, 2);
    T.w(idx) = ws;
    T.type(idx) = v.type;
    T.id(idx) = vid;
    T.vessels(vid) = struct('parent', v.parent, 'type', v.type, ...
        'quadrant', quadrantOf(pts(round(m / 2), :), geom, e1, e2), ...
        'isMajor', v.isMajor, 'first', n + 1, 'last', n + m);
    n = n + m;
    for b = 1:numel(branches)
        br = branches(b);
        stack(end + 1) = item(br.p, br.heading, br.w, v.type, br.budget, ... %#ok<AGROW>
            v.depth + 1, br.mode, v.sign, vid, false, v.b);
    end
end
T.x = T.x(1:n); T.y = T.y(1:n); T.w = T.w(1:n);
T.type = T.type(1:n); T.id = T.id(1:n);
end

% ======================================================================
function s = item(p, heading, w, type, budget, depth, mode, sgn, parent, isMajor, b)
s = struct('p', p, 'heading', heading, 'w', w, 'type', type, 'budget', budget, ...
    'depth', depth, 'mode', mode, 'sign', sgn, 'parent', parent, 'isMajor', isMajor, 'b', b);
end

function [e1, e2] = localFrame(geom)
e1 = geom.fovea - geom.od;            % temporal direction (disc -> fovea)
e1 = e1 / norm(e1);
e2 = [e1(2), -e1(1)];                 % superior direction (up in the image)
if e2(2) > 0
    e2 = -e2;
end
end

function [pts, ws, branches] = growOne(v, geom, e1, e2, o)
% Grow one vessel by a correlated random walk steered by anatomy:
%   arcades follow a heading profile that arches around the fovea,
%   free branches drift radially away from the disc, macular twigs aim at
%   the fovea and stop at the avascular zone, and no vessel crosses the
%   horizontal raphe temporal to the fovea.
DD = geom.pxPerDD;
od = geom.od;
fv = geom.fovea;
fc = geom.fovCentre;
rMax2 = (0.985 * geom.fovRadius) ^ 2;
faz2 = (0.30 * DD) ^ 2;
step = o.Step;
maxSteps = ceil(v.budget / step);
pts = zeros(maxSteps, 2);
ws = zeros(maxSteps, 1);
branches = struct('p', {}, 'heading', {}, 'w', {}, 'budget', {}, 'mode', {});
px = v.p(1); py = v.p(2);
h = v.heading;
w = v.w;
mode = v.mode;
sgn = v.sign;
kappa = 0;
taper = 1 - (0.00035 + 0.0012 * strcmp(mode, 'free')) * step;
nextBranch = (0.30 + 0.40 * rand) * DD;
side = 1 - 2 * (rand < 0.5);
e1x = e1(1); e1y = e1(2); e2x = e2(1); e2y = e2(2);
s = 0;
m = 0;
for it = 1:maxSteps
    dx = px - od(1); dy = py - od(2);
    u = (dx * e1x + dy * e1y) / DD;             % temporal progress from the disc
    vv = ((px - fv(1)) * e2x + (py - fv(2)) * e2y) / DD;   % superior offset from fovea
    switch mode
        case 'arcade'
            % follow elliptical streamlines centred on the fovea (a = 2.6,
            % b = 2.1 DD) until past the fovea, then run gently toward the raphe
            xf = ((px - fv(1)) * e1x + (py - fv(2)) * e1y) / DD;   % temporal
            if xf < 0.3
                target = atan2(-sgn * xf / 2.6 ^ 2, sgn * vv / v.b ^ 2);
            else
                target = -sgn * 12 * pi / 180;
            end
            rate = 0.020;
        case 'nasal'
            target = sgn * 128 * pi / 180;
            rate = 0.004;
        case 'macular'
            gx = fv(1) - px; gy = fv(2) - py;
            target = atan2(gx * e2x + gy * e2y, gx * e1x + gy * e1y);
            rate = 0.012;
        otherwise                                % free: drift away from the disc
            target = atan2(dx * e2x + dy * e2y, dx * e1x + dy * e1y);
            rate = 0.0035;
    end
    kappa = 0.97 * kappa + o.Tortuosity * randn;
    h = h + kappa + rate * (mod(target - h + pi, 2 * pi) - pi);
    ch = cos(h); sh = sin(h);
    nx = px + step * (ch * e1x + sh * e2x);
    ny = py + step * (ch * e1y + sh * e2y);
    s = s + step;
    w = w * taper;
    vNew = ((nx - fv(1)) * e2x + (ny - fv(2)) * e2y) / DD;
    crossesRaphe = u > 2.6 && sign(vNew) ~= sign(vv) && vv ~= 0;
    if (nx - fc(1)) ^ 2 + (ny - fc(2)) ^ 2 > rMax2 || w < o.MinWidth || ...
            (nx - fv(1)) ^ 2 + (ny - fv(2)) ^ 2 < faz2 || crossesRaphe
        break
    end
    px = nx; py = ny;
    m = m + 1;
    pts(m, 1) = px;
    pts(m, 2) = py;
    ws(m) = w;
    if s >= nextBranch && w > 1.6 * o.MinWidth && v.depth < 5
        if v.isMajor
            ratio = 0.28 + 0.27 * rand;         % trunks give off small branches
        else
            ratio = 0.50 + 0.25 * rand;
        end
        wc = ratio * w;
        bmode = 'free';
        if strcmp(mode, 'arcade') && side == -sgn && u > 0.6
            bmode = 'macular';                  % inward branch toward the macula
            wc = min(wc, 0.028 * DD);
        end
        budget = (0.5 + 1.1 * rand) * DD * sqrt(wc / (0.03 * DD));
        branches(end + 1) = struct('p', [px py], 'heading', h + side * deg2rad(30 + 30 * rand), ...
            'w', wc, 'budget', budget, 'mode', bmode); %#ok<AGROW>
        w = max(w ^ 3 - wc ^ 3, (0.55 * w) ^ 3) ^ (1 / 3);   % Murray's law
        side = -side;
        if v.isMajor
            nextBranch = s + (0.22 + 0.30 * rand) * DD;
        else
            nextBranch = s + (0.30 + 0.45 * rand) * DD * max(0.35, w / (0.06 * DD));
        end
    end
end
pts = pts(1:m, :);
ws = ws(1:m);
end

function q = quadrantOf(p, geom, e1, e2)
d = p - geom.fovea;
uu = d * (-e1');                        % nasal positive
vv = d * e2';                           % superior positive
if uu < 0 && vv >= 0
    q = 1;                              % superotemporal
elseif uu >= 0 && vv >= 0
    q = 2;                              % superonasal
elseif uu >= 0
    q = 3;                              % inferonasal
else
    q = 4;                              % inferotemporal
end
end
