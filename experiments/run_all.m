%RUN_ALL Run every experiment in order, then write the validation dossier.
%
%   >> netrasetu_setup
%   >> run experiments/run_all
%
%   exp01  vessels on DRIVE (and the learned detector fusion)
%   exp02  lesions and landmarks on IDRiD
%   exp03  training and calibration (APTOS + IDRiD train)
%   exp04  clinical validation (APTOS hold-out, IDRiD test, Messidor-2)
%   exp05  explanation quality (IDRiD lesion masks, reader logs)
%   exp06  district programme plan (uses the exp04 ROC)
%   A step that fails (e.g. a dataset that is not downloaded) is reported
%   and the rest continue. Results: results/validation_dossier.html.
%   Expect hours, not minutes, on the full datasets: every step caches its
%   per-image results and resumes where it stopped.

runAll_ = struct('here', fileparts(mfilename('fullpath')), 'steps', {{ ...
    'exp01_vessels_drive', 'exp02_lesions_idrid', 'exp03_train_grader', ...
    'exp04_validate_grading', 'exp05_explainability', 'exp06_district_simulation'}}, ...
    'status', {{}}, 't0', tic);
if isempty(which('netra.config'))
    run(fullfile(fileparts(runAll_.here), 'netrasetu_setup.m'));
end
for runAllStep_ = 1:numel(runAll_.steps)
    fprintf('\n################ %s\n', runAll_.steps{runAllStep_});
    runAllT_ = tic;
    try
        run(fullfile(runAll_.here, [runAll_.steps{runAllStep_} '.m']));
        runAll_.status{runAllStep_} = sprintf('done in %.0f min', toc(runAllT_) / 60);
    catch runAllErr_
        runAll_.status{runAllStep_} = ['FAILED: ' runAllErr_.message];
    end
    close all
end
fprintf('\n################ summary (%.1f h)\n', toc(runAll_.t0) / 3600);
for runAllStep_ = 1:numel(runAll_.steps)
    fprintf('  %-28s %s\n', runAll_.steps{runAllStep_}, runAll_.status{runAllStep_});
end
fprintf('Validation dossier: %s\n', netra.eval.dossier());
