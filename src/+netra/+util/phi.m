function p = phi(z)
%PHI Standard normal CDF (toolbox-free NORMCDF).
p = 0.5 * erfc(-z ./ sqrt(2));
end
