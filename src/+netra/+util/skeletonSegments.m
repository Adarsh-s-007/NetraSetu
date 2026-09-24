function [segs, branchPts, endPts] = skeletonSegments(skel, minLen)
%SKELETONSEGMENTS Split a one-pixel skeleton into ordered vessel segments.
%   [segs, branchPts, endPts] = netra.util.skeletonSegments(skel, minLen)
%   removes junction neighbourhoods, labels the remaining simple paths and
%   walks each path from one end to the other. Each element of SEGS has
%     idx         ordered linear indices into SKEL
%     r, c        ordered row / column coordinates
%     length      arc length in pixels (1 or sqrt(2) per step)
%     chord       end-to-end distance
%     tortuosity  length / chord (1 = straight)
%   branchPts and endPts are logical maps of junctions and terminals.
if nargin < 2
    minLen = 3;
end
skel = logical(skel);
[H, W] = size(skel);
% pad so that neighbour offsets never leave the array
P = false(H + 2, W + 2);
P(2:end - 1, 2:end - 1) = skel;
Hp = H + 2;
nb = conv2(double(P), [1 1 1; 1 0 1; 1 1 1], 'same') .* P;
branch = P & nb >= 3;
ends = P & nb == 1;
cut = P & ~imdilate(branch, true(3));
L = bwlabel(cut, 8);
stats = regionprops(L, 'PixelIdxList');
off = [-1, 1, -Hp, Hp, -Hp - 1, -Hp + 1, Hp - 1, Hp + 1];
step = [1 1 1 1 sqrt(2) sqrt(2) sqrt(2) sqrt(2)];
mark = L;
segs = repmat(struct('idx', [], 'r', [], 'c', [], 'length', 0, ...
    'chord', 0, 'tortuosity', 1), 0, 1);
for k = 1:numel(stats)
    p = stats(k).PixelIdxList;
    n = numel(p);
    if n < minLen
        continue
    end
    nbIdx = bsxfun(@plus, p, off);
    deg = sum(mark(nbIdx) == k, 2);
    s0 = find(deg <= 1, 1);
    if isempty(s0)
        s0 = 1;                    % closed loop: start anywhere
    end
    order = zeros(n, 1);
    len = 0;
    cur = p(s0);
    order(1) = cur;
    mark(cur) = -k;
    m = 1;
    for t = 2:n
        cand = cur + off;
        hit = find(mark(cand) == k, 1);
        if isempty(hit)
            break
        end
        cur = cand(hit);
        len = len + step(hit);
        mark(cur) = -k;
        m = m + 1;
        order(m) = cur;
    end
    order = order(1:m);
    [rr, cc] = ind2sub([Hp, W + 2], order);
    rr = rr - 1;
    cc = cc - 1;
    seg.idx = sub2ind([H, W], rr, cc);
    seg.r = rr;
    seg.c = cc;
    seg.length = len;
    seg.chord = hypot(rr(end) - rr(1), cc(end) - cc(1));
    seg.tortuosity = len / max(seg.chord, 1);
    segs(end + 1, 1) = seg; %#ok<AGROW>
end
branchPts = branch(2:end - 1, 2:end - 1);
endPts = ends(2:end - 1, 2:end - 1);
end
