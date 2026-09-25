function S = scoreMaps(L, D)
%SCOREMAPS Pixel-wise lesion probability maps for precision-recall scoring.
%
%   S = netra.lesions.scoreMaps(L, D) with L from netra.lesions.detectAll on
%   a D x D canvas returns maps in [0, 1] for the four IDRiD lesion types:
%     ma  every microaneurysm candidate painted at its fitted FWHM with its
%         probability (including rejected candidates, so the PR curve spans
%         the full operating range)
%     he  haemorrhage components with their probability, plus the 125-250
%         um red dots from the microaneurysm stage
%     ex  hard-exudate components;  se  cotton-wool spots (IDRiD's "soft
%         exudates")
%   Values are component probabilities, so thresholding a map at t gives
%   exactly the detector's output at operating point t.
S = struct('ma', zeros(D, 'single'), 'he', zeros(D, 'single'), ...
    'ex', zeros(D, 'single'), 'se', zeros(D, 'single'));
[X, Y] = meshgrid(1:D, 1:D);
for i = 1:numel(L.ma.list)
    m = L.ma.list(i);
    r = max(1.1774 * m.sigmaPx, 1.5);
    x0 = max(1, floor(m.x - r)); x1 = min(D, ceil(m.x + r));
    y0 = max(1, floor(m.y - r)); y1 = min(D, ceil(m.y + r));
    if x1 < x0 || y1 < y0
        continue
    end
    in = (X(y0:y1, x0:x1) - m.x) .^ 2 + (Y(y0:y1, x0:x1) - m.y) .^ 2 <= r ^ 2;
    f = 'ma';
    if strcmp(m.class, 'dot')
        f = 'he';
    end
    patch = S.(f)(y0:y1, x0:x1);
    patch(in) = max(patch(in), m.prob);
    S.(f)(y0:y1, x0:x1) = patch;
end
S.he = max(S.he, paint(L.he.mask, L.he.list));
S.ex = paint(L.ex.mask, L.ex.list);
S.se = paint(L.ex.cwsMask, L.ex.cws);
end

function M = paint(mask, list)
M = zeros(size(mask), 'single');
if isempty(list) || ~any(mask(:))
    return
end
lab = bwlabel(mask, 8);
n = max(lab(:));
p = zeros(n, 1);
xy = [[list.x]' [list.y]'];
prob = [list.prob]';
for i = 1:size(xy, 1)
    yi = min(max(round(xy(i, 2)), 1), size(mask, 1));
    xi = min(max(round(xy(i, 1)), 1), size(mask, 2));
    k = lab(yi, xi);
    if k == 0                              % centroid outside a concave component
        [yy, xx] = find(lab > 0);
        [~, j] = min((xx - xy(i, 1)) .^ 2 + (yy - xy(i, 2)) .^ 2);
        k = lab(yy(j), xx(j));
    end
    p(k) = max(p(k), prob(i));
end
M(lab > 0) = p(lab(lab > 0));
end
