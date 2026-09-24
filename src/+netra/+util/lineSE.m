function se = lineSE(len, deg)
%LINESE Flat linear structuring element of odd length LEN at angle DEG.
%   se = netra.util.lineSE(len, deg) rasterises the segment symmetrically
%   about the origin (x right, y up for positive angles, like STREL('line')).
%   Built explicitly so MATLAB and Octave use identical neighbourhoods.
h = floor(max(len, 1) / 2);
t = -h:h;
dx = round(t * cosd(deg));
dy = round(-t * sind(deg));
r = max(abs([dx dy]));
nh = false(2 * r + 1);
nh(sub2ind(size(nh), dy + r + 1, dx + r + 1)) = true;
se = strel('arbitrary', nh);
end
