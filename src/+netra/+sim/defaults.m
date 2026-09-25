function P = defaults()
%DEFAULTS Parameters of an illustrative district DR tele-screening programme.
%
%   P = netra.sim.defaults() describes a rural district of ~2.5 million
%   people with 36 primary health centres (PHCs), the unit at which Indian
%   NCD programmes run diabetes clinics. Every number is an editable
%   assumption, grouped so a programme manager can replace it with local
%   data; costs are indicative 2025 Indian rupee figures, not quotations.
%
%   Time runs in hours; the simulation step P.dt is 1 hour and patient
%   cohorts are tracked by their age since image capture for up to
%   P.maxAgeHours (older cohorts are pooled in the last bin).

P = struct();
P.name = 'Illustrative rural district, 36 PHCs';
P.dt = 1;                          % h
P.days = 364;                      % 52 weeks
P.maxAgeHours = 240;               % 10 days of turnaround resolution
P.seed = 2026;

% ------------------------------------------------------------- demand
P.phc.count = 36;                  % PHCs in the district
P.phc.demandPerDay = 11;           % diabetics presenting per open day (NCD clinic)
P.phc.hours = [9 16];              % screening hours
P.phc.weekday = [1.25 1.05 1.0 1.0 0.95 0.75 0];   % Mon..Sun demand multipliers
P.phc.holidays = 16;               % closed days a year
P.season = [1 1 1 1 1 0.95 0.8 0.8 0.85 1 1.05 1.05]; % Jan..Dec (monsoon dip)

P.van.demandPerCampDay = 55;       % mobile camp in a village, ASHA-mobilised
P.van.campDaysPerWeek = 5;
P.van.hours = [9 16];
P.van.uploadHours = [18 22];       % store-and-forward from the CHC's fibre link

% ------------------------------------------------------------ capture
P.capture.minutesPerPatient = 6;   % both eyes, macula + disc fields, data entry
P.capture.ungradableFirst = 0.12;  % non-mydriatic portable camera, first attempt
P.capture.recaptureSuccess = 0.6;
P.capture.recaptureMinutes = 3;
P.capture.camerasPerPHC = 1;

% ------------------------------------------------------------- images
P.images.mbPerPatient = 16;        % 4 images x ~4 MB (5-12 MP portable cameras)

% -------------------------------------------------------------- links
P.link.names = {'2G', '3G', '4G', 'fibre'};
P.link.mbps = [0.05 0.5 4 20];     % effective rural throughput, not the brochure figure
P.link.availability = [0.90 0.85 0.80 0.97];
P.link.meanOutageHours = [3 4 5 8];
P.link.efficiency = 0.6;           % goodput / nominal
P.link.hours = [9 17];             % the PHC laptop uploads while the clinic is staffed
P.link.baselineMix = [0.25 0.35 0.30 0.10];   % share of PHCs on each tier today

% ----------------------------------------------------------------- AI
P.ai.mode = 'edge';                % 'edge' (on the PHC laptop) or 'cloud'
P.ai.cloudPatientsPerHour = 900;
P.ai.edgeSecondsPerPatient = 20;
P.ai.auc = 0.95;                   % referable-DR AUC (binormal) unless P.ai.roc is set
P.ai.roc = [];                     % measured ROC from validation: struct(fpr, tpr)
P.ai.sensitivity = 0.92;           % operating point (auto-clear threshold)
P.ai.uncertainShare = 0.06;        % AI negatives routed to HUMAN_REVIEW
P.ai.urgentSensitivity = 0.97;

% ------------------------------------------------------------ case mix
P.mix.referable = 0.08;            % referable DR or DME among screened diabetics
P.mix.urgent = 0.012;              % PDR / centre-involving DME

% -------------------------------------------------------- human review
P.review.mode = 'xai';             % 'xai' (NetraSetu console) or 'plain'
P.review.graders = 2;              % optometrist graders at the reading hub
P.review.graderHours = [10 17];
P.review.graderDays = 1:6;
P.review.secondsPerCase = struct('xai', 30, 'plain', 150);
P.review.adjudicate = 0.25;        % share of grader-confirmed cases sent to the ophthalmologist
P.review.ophthHoursPerDay = 2;     % tele-reading block, weekdays
P.review.ophthStart = 14;
P.review.ophthSecondsPerCase = struct('xai', 60, 'plain', 180);
P.review.qaShare = 0.05;           % audit sample of auto-cleared eyes

% ---------------------------------------------------------- referral
P.referral.uptakeOnSite = 0.65;    % counselled while still at the PHC
P.referral.uptakeDelayed = 0.40;   % informed later by phone / ASHA
P.referral.presenceHours = 3;      % patients leave the PHC within ~3 h
P.referral.provisionalOnSite = true;  % edge AI: urgent/referable eyes are counselled
                                      % at the PHC, confirmation follows remotely

% --------------------------------------------------------- costs (INR)
P.cost.camera = 350000;            P.cost.cameraLife = 5;   P.cost.cameraUpkeep = 0.10;
P.cost.technicianPerSite = 60000;  % incremental allowance + training per year
P.cost.linkPerSite = [1200 3000 6000 12000];
P.cost.linkUpgradeOnce = [0 2000 5000 30000];
P.cost.edgeDevice = 60000;         P.cost.edgeLife = 4;
P.cost.cloudFixed = 250000;        P.cost.cloudPerPatient = 1.0;
P.cost.graderFTE = 360000;
P.cost.ophthPerHour = 1500;
P.cost.van = 1500000;

% --------------------------------------------------------- targets
P.target.screensPerYear = 100000;
P.target.routineP95Hours = 72;
P.target.urgentP95Hours = 24;
P.target.maxUtilisation = 0.85;
P.target.programmeSensitivity = 0.90;

% ------------------------------------------------ default decisions
P.decision = struct('phcEquipped', 36, 'vans', 1, 'linkTier', 0, 'aiMode', 'edge', ...
    'graders', 2, 'ophthHours', 2, 'sensitivity', 0.92, 'reviewMode', 'xai');
end
