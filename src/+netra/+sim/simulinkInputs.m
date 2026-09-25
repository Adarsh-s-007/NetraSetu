function nsim = simulinkInputs(X)
%SIMULINKINPUTS Workspace struct 'nsim' that the Simulink model reads.
%
%   nsim = netra.sim.simulinkInputs(X)   X from netra.sim.prepare
%   nsim = netra.sim.simulinkInputs()    default district, decision and year
%
%   nsim.in.*   From Workspace matrices [t, values] (one row per step)
%   nsim.p      stage parameters;  nsim.x0 initial queue states
%   nsim.dt, nsim.stopTime, nsim.T
%   The model's InitFcn calls this without arguments when 'nsim' is missing,
%   so the .slx also runs straight from the Simulink toolstrip.

if nargin < 1
    P = netra.sim.defaults();
    X = netra.sim.prepare(P, P.decision, netra.sim.scenario(P));
end
t = (0:X.T - 1)' * X.dt;
nsim = struct();
nsim.dt = X.dt;
nsim.T = X.T;
nsim.stopTime = (X.T - 1) * X.dt;
nsim.in = struct('arrivals', [t, X.arrivals], 'capCapture', [t, X.capCapture], ...
    'closing', [t, double(X.closing)], 'upCap', [t, X.upCap], ...
    'graderCap', [t, X.graderCap], 'ophthCap', [t, X.ophthCap]);
nsim.p = X.p;
nsim.x0 = X.x0;
end
