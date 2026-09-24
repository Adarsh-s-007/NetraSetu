function say(cfg, fmt, varargin)
%SAY Progress message printed only when cfg.verbose is true.
if isstruct(cfg) && isfield(cfg, 'verbose') && cfg.verbose
    fprintf(['  [netra] ' fmt '\n'], varargin{:});
end
end
