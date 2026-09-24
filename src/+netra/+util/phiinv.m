function z = phiinv(p)
%PHIINV Standard normal quantile (toolbox-free NORMINV).
z = -sqrt(2) .* erfcinv(2 .* p);
end
