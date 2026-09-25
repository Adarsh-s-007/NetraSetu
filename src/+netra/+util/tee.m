function tee(fid, varargin)
%TEE Print to the console and to an open log file at once.
%   netra.util.tee(fid, fmt, args...) - fid from fopen; 0 or -1 = console only.
fprintf(varargin{:});
if fid > 2
    fprintf(fid, varargin{:});
end
end
