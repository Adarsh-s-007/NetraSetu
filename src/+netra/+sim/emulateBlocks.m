function L = emulateBlocks(nsim)
%EMULATEBLOCKS Execute the Simulink model's block code without Simulink.
%
%   L = netra.sim.emulateBlocks(nsim) writes the code of every MATLAB
%   Function block (netra.sim.simulinkBlocks) to a temporary function file
%   and runs the blocks in their execution order, one call per time step,
%   exactly as the fixed-step single-rate model does: From Workspace blocks
%   deliver row k of nsim.in.*, Constant blocks their value, and persistent
%   variables carry the queues from one step to the next. L has one field
%   per logged signal, in the layout netra.sim.runSimulink extracts from a
%   Simulink run, so the same post-processing (netra.sim.fromLogs) applies.
%
%   This is how the model's logic is verified where Simulink is not
%   installed (CI runs it under Octave and compares it with
%   netra.sim.runReference); Simulink adds only its scheduler, which for a
%   loop-free, single-rate, direct-feedthrough diagram is the order below.

M = netra.sim.simulinkBlocks();
dir = tempname();
mkdir(dir);
names = cell(1, numel(M.blocks));
for b = 1:numel(M.blocks)
    names{b} = ['nsblk_' lower(M.blocks(b).name)];
    fid = fopen(fullfile(dir, [names{b} '.m']), 'w');
    fprintf(fid, '%s\n', signature(M.blocks(b), names{b}));
    fprintf(fid, '%s\n', M.blocks(b).code{:});
    fprintf(fid, 'end\n');
    fclose(fid);
end
addpath(dir);
cleanup = onCleanup(@() tidy(dir, names));
for b = 1:numel(names)
    clear(names{b});                    % fresh persistent state
end
rehash();

values = struct();
series = {};
for s = 1:numel(M.sources)
    v = eval(M.sources(s).value);       % expressions such as 'nsim.in.arrivals'
    values.(M.sources(s).name) = v;
    if strcmp(M.sources(s).kind, 'series')
        series{end + 1} = M.sources(s).name; %#ok<AGROW>
    end
end
T = nsim.T;
sig = struct();
for s = 1:numel(M.sources)
    if strcmp(M.sources(s).kind, 'constant')
        sig.(M.sources(s).name) = values.(M.sources(s).name);
    end
end
L = struct();
for g = 1:numel(M.logs)
    if strcmp(M.logs(g).mode, 'all')
        L.(M.logs(g).signal) = zeros(T, 1);
    end
end
fns = cellfun(@str2func, names, 'UniformOutput', false);
for k = 1:T
    for s = 1:numel(series)
        v = values.(series{s});
        sig.(series{s}) = v(k, 2:end);
    end
    for b = 1:numel(M.blocks)
        B = M.blocks(b);
        args = cell(1, numel(B.in));
        for j = 1:numel(B.in)
            args{j} = sig.(B.in{j});
        end
        res = cell(1, numel(B.out));
        [res{:}] = fns{b}(args{:});
        for j = 1:numel(B.out)
            sig.(B.out{j}) = res{j};
        end
    end
    for g = 1:numel(M.logs)
        if strcmp(M.logs(g).mode, 'all')
            L.(M.logs(g).signal)(k) = sig.(M.logs(g).signal);
        end
    end
end
for g = 1:numel(M.logs)
    if strcmp(M.logs(g).mode, 'last')
        L.(M.logs(g).signal) = sig.(M.logs(g).signal);
    end
end
clear cleanup
end

% ======================================================================
function s = signature(B, name)
s = sprintf('function [%s] = %s(%s)', strjoin(B.out, ', '), name, strjoin(B.in, ', '));
end

function tidy(dir, names)
for b = 1:numel(names)
    clear(names{b});
end
rmpath(dir);
for b = 1:numel(names)
    f = fullfile(dir, [names{b} '.m']);
    if exist(f, 'file')
        delete(f);
    end
end
rmdir(dir);
end
