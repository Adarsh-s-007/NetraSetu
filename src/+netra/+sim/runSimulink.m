function out = runSimulink(P, D, S, varargin)
%RUNSIMULINK Run the district model in Simulink and cross-check it.
%
%   out = netra.sim.runSimulink(P)                 P.decision, new scenario
%   out = netra.sim.runSimulink(P, D, S, 'Engine', 'simulink', 'CrossCheck', true)
%
%   Options
%     Engine      'simulink' | 'emulate' | 'auto' (Simulink when installed,
%                 otherwise the block emulator netra.sim.emulateBlocks)
%     Model       model name (default 'NetraSetuTelescreening')
%     Folder      where the .slx lives / is built (default <repo>/simulink)
%     Rebuild     rebuild the .slx even if it exists (default false)
%     CrossCheck  also run netra.sim.runReference on the same inputs and
%                 compare every logged signal and KPI (default true)
%
%   The inputs come from netra.sim.prepare (shared with the reference), are
%   handed to the model as the variable 'nsim' through a
%   Simulink.SimulationInput, and the logged signals are post-processed by
%   netra.sim.fromLogs - the same function the reference uses.
%   out: as netra.sim.runReference, plus out.engine, out.crossCheck,
%   out.seconds (wall-clock time of the model run).

if nargin < 2 || isempty(D)
    D = P.decision;
end
if ~isfield(D, 'reviewMode')
    D.reviewMode = P.decision.reviewMode;
end
if nargin < 3 || isempty(S)
    S = netra.sim.scenario(P);
end
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
o = netra.util.opts(struct('Engine', 'auto', 'Model', 'NetraSetuTelescreening', ...
    'Folder', fullfile(root, 'simulink'), 'Rebuild', false, 'CrossCheck', true, ...
    'Verbose', true), varargin{:});
engine = lower(o.Engine);
if strcmp(engine, 'auto')
    engine = 'emulate';
    if ~netra.util.isOctave() && netra.util.has('sim') && license('test', 'Simulink')
        engine = 'simulink';
    end
end

X = netra.sim.prepare(P, D, S);
nsim = netra.sim.simulinkInputs(X);
M = netra.sim.simulinkBlocks();
tic;
switch engine
    case 'simulink'
        file = fullfile(o.Folder, [o.Model '.slx']);
        if o.Rebuild || ~exist(file, 'file')
            netra.sim.buildSimulink(o.Model, 'Folder', o.Folder);
        end
        load_system(file);
        if exist('Simulink.SimulationInput', 'class')
            in = Simulink.SimulationInput(o.Model);
            in = in.setVariable('nsim', nsim);
            in = in.setModelParameter('StopTime', sprintf('%.17g', nsim.stopTime), ...
                'FixedStep', sprintf('%.17g', nsim.dt));
            so = sim(in);
        else
            assignin('base', 'nsim', nsim);
            so = sim(o.Model, 'ReturnWorkspaceOutputs', 'on');
        end
        L = extractLogs(so, M, nsim);
    case 'emulate'
        L = netra.sim.emulateBlocks(nsim);
    otherwise
        error('netra:sim:engine', 'Unknown engine ''%s''.', o.Engine);
end
seconds = toc;
out = netra.sim.fromLogs(P, D, X, L);
out.engine = engine;
out.seconds = seconds;
if o.CrossCheck
    ref = netra.sim.runReference(P, D, S);
    % compiled Simulink code may round differently in the last bits
    tol = 1e-9;
    if strcmp(engine, 'simulink')
        tol = 1e-6;
    end
    out.crossCheck = netra.sim.crossCheck(ref, out, tol);
    if o.Verbose
        fprintf('Simulink model (%s) vs MATLAB reference:', engine);
        netra.sim.crossCheck(ref, out, tol);
    end
end
end

% ======================================================================
function L = extractLogs(so, M, nsim)
L = struct();
for g = 1:numel(M.logs)
    name = M.logs(g).signal;
    v = so.get(['ns_' name]);
    if isa(v, 'timeseries')
        v = v.Data;
    end
    if strcmp(M.logs(g).mode, 'last')
        v = v(:, :, end);                    % 3-D (2-D signal) or 2-D layout
        if isfield(nsim.x0, name)            % final state has its initial shape
            ref = nsim.x0.(name);
            v = reshape(v(end - numel(ref) + 1:end), size(ref));
        end
        L.(name) = v;
    else
        v = v(:);
        if numel(v) ~= nsim.T
            error('netra:sim:logs', 'Signal %s has %d samples, expected %d.', name, ...
                numel(v), nsim.T);
        end
        L.(name) = v;
    end
end
end
