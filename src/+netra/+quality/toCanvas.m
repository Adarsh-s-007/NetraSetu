function xy = toCanvas(S, xy)
%TOCANVAS Map photograph coordinates [x y] (rows of XY) onto the canvas.
xy = (xy - S.origin) * S.scale + 1;
end
