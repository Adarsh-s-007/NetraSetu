%BUILD_NETRASETU_MODEL Build the Simulink tele-screening model, run it, check it.
%
%   >> netrasetu_setup
%   >> run simulink/build_netrasetu_model
%
%   1. draws simulink/NetraSetuTelescreening.slx from the model description
%      in netra.sim.simulinkBlocks (seven MATLAB Function stages, From
%      Workspace inputs, To Workspace logs, Scopes)
%   2. simulates one year of the default district plan (netra.sim.defaults)
%   3. compares every logged signal, at every hour, and every indicator with
%      the MATLAB reference simulator. Both read the same prepared inputs and
%      call the same stage functions, so they must agree to rounding; a
%      mismatch means the model and the reference have diverged.
%
%   Afterwards the model can be run from the Simulink toolstrip: its InitFcn
%   builds default inputs ('nsim') when none are in the workspace. To study
%   another plan, change P or D below, or call netra.sim.runSimulink(P, D).

here = fileparts(mfilename('fullpath'));
if isempty(which('netra.sim.defaults'))
    run(fullfile(here, '..', 'netrasetu_setup.m'));
end

model = netra.sim.buildSimulink('NetraSetuTelescreening', 'Folder', here, 'Open', true);
fprintf('Built %s\n', fullfile(here, [model '.slx']));

P = netra.sim.defaults();
D = P.decision;
S = netra.sim.scenario(P);
out = netra.sim.runSimulink(P, D, S, 'Engine', 'simulink', 'Folder', here, 'Model', model);

K = out.kpi;
fprintf(['\nOne simulated year: %s grading, %d PHCs, %d mobile unit(s), %d grader(s)\n' ...
    '  screened %.0f   routine result P95 %.1f h   urgent notice P95 %.1f h\n' ...
    '  grader load %.0f%%   ophthalmologist load %.0f%%   patients reaching treatment %.0f\n' ...
    '  cost Rs %.2f crore (Rs %.0f per screen)   Simulink run %.1f s\n'], ...
    D.aiMode, D.phcEquipped, D.vans, D.graders, K.screened, K.turnaround.routineP95, ...
    K.urgentNoticeP95, 100 * K.utilisation.graders, 100 * K.utilisation.ophthalmologist, ...
    K.reachingTreatment, K.cost.total / 1e7, K.costPerScreen, out.seconds);
if ~out.crossCheck.pass
    warning('netra:sim:crossCheck', ['The Simulink model and the MATLAB reference differ ' ...
        '(largest relative difference %.2g in %s).'], out.crossCheck.maxRelative, ...
        out.crossCheck.worst);
end
