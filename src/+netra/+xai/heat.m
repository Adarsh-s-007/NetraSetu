function img = heat(base, map, varargin)
%HEAT Blend a [0,1] attention or evidence map over an image.
%   img = netra.xai.heat(base, map) uses a perceptually ordered
%   dark-violet -> magenta -> amber -> pale-yellow ramp (an "inferno"-like
%   scale built from anchor colours, no toolbox needed); transparency follows
%   the map so low values leave the retina visible.
%   Options: 'Alpha' (0.65), 'Floor' (0.15: values below are not drawn).
o = netra.util.opts(struct('Alpha', 0.65, 'Floor', 0.15), varargin{:});
anchors = [0.00 0.00 0.02 0.10
           0.25 0.34 0.06 0.43
           0.50 0.73 0.21 0.33
           0.75 0.98 0.55 0.04
           1.00 0.99 0.99 0.64];
m = min(max(map, 0), 1);
img = base;
a = o.Alpha * min(1, max(0, (m - o.Floor) / max(1 - o.Floor, eps))) .^ 0.8;
for k = 1:3
    ck = interp1(anchors(:, 1), anchors(:, k + 1), m);
    img(:, :, k) = base(:, :, k) .* (1 - a) + ck .* a;
end
end
