function xy = toOriginal(S, xy)
%TOORIGINAL Map canvas coordinates [x y] (rows of XY) back to the photograph.
xy = (xy - 1) / S.scale + S.origin;
end
