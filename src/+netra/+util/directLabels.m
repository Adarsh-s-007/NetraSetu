function h = directLabels(ax, curves, labels, varargin)
%DIRECTLABELS Label each curve right next to it, touching no other line or text.
%
%   h = netra.util.directLabels(ax, curves, labels)
%   h = netra.util.directLabels(ax, curves, labels, 'Obstacles', lines, 'Taken', boxes)
%
%     curves     cell array of 2 x n polylines [x; y] in data units, as drawn
%     labels     cellstr, one per curve
%     Obstacles  further polylines to keep clear of (reference lines ...)
%     Taken      k x 4 boxes [x0 y0 x1 y1] already occupied (legends, notes)
%     FontSize (9.5), FontName, Color (ink)
%     Mode       'curves' (default) or 'points': each "curve" is a single
%                marker [x; y], labelled on whichever side is free
%     Gap        offset multiplier (default 1)
%
%   Candidate spots are spread along each curve by arc length, on all four
%   diagonals of the curve; the text's measured extent must not cross any
%   curve (exact segment-rectangle test, so vertical ROC steps count), any
%   obstacle or any label already placed, and must not sit where another
%   curve runs within a few percent of this one (ambiguous). Of the free
%   spots the one farthest from the other curves wins. A curve without a
%   free spot gets no label (h = NaN) and is identified by the legend.
o = netra.util.opts(struct('Obstacles', {{}}, 'Taken', zeros(0, 4), 'FontSize', 9.5, ...
    'FontName', get(ax, 'FontName'), 'Color', [0.078 0.094 0.18], 'Anchors', 60, ...
    'Mode', 'curves', 'Gap', 1), varargin{:});
points = strcmpi(o.Mode, 'points');
xl = xlim(ax);
yl = ylim(ax);
sx = diff(xl);
sy = diff(yl);
gx = 0.010 * sx * o.Gap;
gy = 0.012 * sy * o.Gap;
taken = o.Taken;
h = NaN(1, numel(curves));
if strcmpi(o.Mode, 'points')
    % labels must not cover any of the markers either
    for k = 1:numel(curves)
        c = curves{k}(:, 1);
        taken(end + 1, :) = [c(1) - 0.008 * sx, c(2) - 0.008 * sy, c(1) + 0.008 * sx, ...
            c(2) + 0.008 * sy]; %#ok<AGROW>
    end
end
place = {[1 -1], 'left', 'top'; [1 1], 'left', 'bottom'; [-1 1], 'right', 'bottom'; ...
    [-1 -1], 'right', 'top'};
if points
    % a marker can be labelled on any side; straight right reads best
    place = [{[1.4 0], 'left', 'middle'; [-1.4 0], 'right', 'middle'; [0 1.6], 'center', 'bottom'; ...
        [0 -1.6], 'center', 'top'}; place];
end
for k = 1:numel(curves)
    t = text(ax, 0, 0, labels{k}, 'FontSize', o.FontSize, 'FontName', o.FontName, ...
        'Color', o.Color);
    others = curves([1:k - 1, k + 1:end]);
    dense = cloud(others, sx, sy, 300);
    anchors = along(curves{k}, sx, sy, o.Anchors);
    best = [];
    bestScore = -Inf;
    for a = 1:size(anchors, 2)
        p = anchors(:, a);
        if ~points && ~isempty(dense) && minDist(p', dense, sx, sy) < 0.035
            continue                                % another curve runs alongside
        end
        for c = 1:size(place, 1)
            d = place{c, 1};
            set(t, 'Position', [p(1) + d(1) * gx, p(2) + d(2) * gy, 0], ...
                'HorizontalAlignment', place{c, 2}, 'VerticalAlignment', place{c, 3});
            b = netra.util.textBox(t);
            if b(1) < xl(1) || b(3) > xl(2) || b(2) < yl(1) || b(4) > yl(2)
                continue
            end
            bp = b + [-gx / 2, -gy / 2, gx / 2, gy / 2];
            if hitsAny(bp, curves) || hitsAny(bp, o.Obstacles) || overlaps(bp, taken)
                continue
            end
            score = Inf;
            if points
                obst = cloud(o.Obstacles, sx, sy, 300);
                if ~isempty(obst)
                    score = boxDist(b, obst, sx, sy);
                end
                score = min(score, 0.06) - 0.001 * c;                % prefer the first sides
            else
                if ~isempty(dense)
                    score = boxDist(b, dense, sx, sy);
                end
                score = min(score, 0.25) - 0.02 * a / size(anchors, 2);   % prefer early spots on ties
            end
            if score > bestScore
                bestScore = score;
                best = {get(t, 'Position'), place{c, 2}, place{c, 3}, b};
            end
        end
    end
    if isempty(best)
        delete(t);
    else
        set(t, 'Position', best{1}, 'HorizontalAlignment', best{2}, 'VerticalAlignment', best{3});
        taken(end + 1, :) = best{4}; %#ok<AGROW>
        h(k) = t;
    end
end
end

% ======================================================================
function pts = along(c, sx, sy, n)
% n points evenly spaced by arc length (axis-normalised units) on polyline c
pts = c;
if size(c, 2) < 2
    return
end
d = hypot(diff(c(1, :)) / sx, diff(c(2, :)) / sy);
s = [0 cumsum(d)];
[s, iu] = unique(s);
c = c(:, iu);
if numel(s) < 2
    pts = c;
    return
end
q = linspace(s(1), s(end), n);
pts = [interp1(s, c(1, :), q); interp1(s, c(2, :), q)];
end

function pts = cloud(curves, sx, sy, n)
pts = zeros(2, 0);
for k = 1:numel(curves)
    pts = [pts, along(curves{k}, sx, sy, n)]; %#ok<AGROW>
end
end

function d = minDist(p, pts, sx, sy)
d = min(hypot((pts(1, :) - p(1)) / sx, (pts(2, :) - p(2)) / sy));
end

function d = boxDist(b, pts, sx, sy)
dx = max([b(1) - pts(1, :); zeros(1, size(pts, 2)); pts(1, :) - b(3)], [], 1) / sx;
dy = max([b(2) - pts(2, :); zeros(1, size(pts, 2)); pts(2, :) - b(4)], [], 1) / sy;
d = min(hypot(dx, dy));
end

function tf = hitsAny(b, curves)
tf = false;
for k = 1:numel(curves)
    c = curves{k};
    if size(c, 2) < 2
        continue
    end
    x1 = c(1, 1:end - 1); y1 = c(2, 1:end - 1);
    x2 = c(1, 2:end);     y2 = c(2, 2:end);
    near = ~(max(x1, x2) < b(1) | min(x1, x2) > b(3) | max(y1, y2) < b(2) | min(y1, y2) > b(4));
    if ~any(near)
        continue
    end
    x1 = x1(near); y1 = y1(near); x2 = x2(near); y2 = y2(near);
    % the segment's line separates the box corners unless all lie on one side
    cx = [b(1) b(3) b(3) b(1)];
    cy = [b(2) b(2) b(4) b(4)];
    f = zeros(numel(x1), 4);
    for j = 1:4
        f(:, j) = (x2 - x1)' .* (cy(j) - y1)' - (y2 - y1)' .* (cx(j) - x1)';
    end
    if any(~(all(f > 0, 2) | all(f < 0, 2)))
        tf = true;
        return
    end
end
end

function tf = overlaps(b, boxes)
tf = any(boxes(:, 1) <= b(3) & boxes(:, 3) >= b(1) & boxes(:, 2) <= b(4) & boxes(:, 4) >= b(2));
end
