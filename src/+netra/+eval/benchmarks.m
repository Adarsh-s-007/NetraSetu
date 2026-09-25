function B = benchmarks(varargin)
%BENCHMARKS Published results the validation experiments are compared with.
%
%   B = netra.eval.benchmarks()                                  all entries
%   B = netra.eval.benchmarks('Task', 'referable-dr', 'Dataset', 'Messidor-2')
%   netra.eval.benchmarks('Task', 'vessels')                     prints a table
%
%   Fields: task, dataset, method, metric, value, ci ([lo hi] or []), n,
%   source, verify, note.
%     task     'referable-dr'  moderate NPDR or worse and/or referable DME
%              'dr-grading'    five-level ICDR agreement
%              'vessels'       DRIVE test set, pixels inside the FOV
%              'lesion-seg'    IDRiD sub-challenge 1, area under PR curve
%              'standard'      screening accuracy standards and targets
%   Values are transcribed from the cited papers (abstracts or results
%   tables). Entries with verify = true were transcribed with less
%   certainty or from secondary tabulations: check them against the source
%   before quoting them in a publication. Results on different datasets,
%   reference standards or referral definitions are context, not
%   head-to-head comparisons - the only strict comparisons in this project
%   are the paired ones computed on the same images (DeLong, McNemar).

o = netra.util.opts(struct('Task', '', 'Dataset', '', 'Metric', ''), varargin{:});
e = @(task, dataset, method, metric, value, ci, n, source, verify, note) struct( ...
    'task', task, 'dataset', dataset, 'method', method, 'metric', metric, ...
    'value', value, 'ci', ci, 'n', n, 'source', source, 'verify', verify, 'note', note);
G16 = 'Gulshan V et al. JAMA 2016;316(22):2402-10';
A16 = 'Abramoff MD et al. Invest Ophthalmol Vis Sci 2016;57(13):5200-6';
A13 = 'Abramoff MD et al. JAMA Ophthalmol 2013;131(3):351-7';
V19 = 'Voets M, Mollersen K, Bongo LA. PLoS One 2019;14(6):e0217541';
G19 = 'Gulshan V et al. JAMA Ophthalmol 2019;137(9):987-93';
T17 = 'Ting DSW et al. JAMA 2017;318(22):2211-23';
A18 = 'Abramoff MD et al. NPJ Digit Med 2018;1:39';
R18 = 'Rajalakshmi R et al. Eye 2018;32(6):1138-44';
N19 = 'Natarajan S et al. JAMA Ophthalmol 2019;137(10):1182-8';
F12 = 'Fraz MM et al. IEEE Trans Biomed Eng 2012;59(9):2538-48';
N04 = 'Niemeijer M et al. Proc SPIE Medical Imaging 2004;5370:648-56';
P20 = 'Porwal P et al. Med Image Anal 2020;59:101561';

B = [ ...
 e('referable-dr', 'Messidor-2', 'Deep learning (Google), high-sensitivity point', 'se', 0.961, [], 1748, G16, false, 'rDR = moderate NPDR+ or referable DME')
 e('referable-dr', 'Messidor-2', 'Deep learning (Google), high-sensitivity point', 'sp', 0.939, [], 1748, G16, false, '')
 e('referable-dr', 'Messidor-2', 'Deep learning (Google), high-specificity point', 'se', 0.870, [0.811 0.910], 1748, G16, false, '')
 e('referable-dr', 'Messidor-2', 'Deep learning (Google), high-specificity point', 'sp', 0.985, [0.977 0.991], 1748, G16, false, '')
 e('referable-dr', 'Messidor-2', 'Deep learning (Google)', 'auc', 0.990, [0.986 0.995], 1748, G16, false, '')
 e('referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion)', 'se', 0.968, [0.933 0.988], 874, A16, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion)', 'sp', 0.870, [0.842 0.894], 874, A16, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion)', 'auc', 0.980, [0.968 0.992], 874, A16, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors)', 'se', 0.968, [0.944 0.993], 874, A13, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors)', 'sp', 0.594, [0.557 0.630], 874, A13, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors)', 'auc', 0.937, [0.916 0.959], 874, A13, false, 'per patient')
 e('referable-dr', 'Messidor-2', 'Independent re-implementation of the 2016 deep learning method', 'auc', 0.853, [], 1748, V19, false, 'same method trained on public data only')
 e('referable-dr', 'Aravind, India', 'Deep learning (Google)', 'se', 0.889, [0.858 0.915], [], G19, false, 'prospective, Indian primary-care population')
 e('referable-dr', 'Aravind, India', 'Deep learning (Google)', 'sp', 0.922, [0.903 0.938], [], G19, false, '')
 e('referable-dr', 'Sankara Nethralaya, India', 'Deep learning (Google)', 'se', 0.921, [0.901 0.938], [], G19, false, '')
 e('referable-dr', 'Sankara Nethralaya, India', 'Deep learning (Google)', 'sp', 0.952, [0.942 0.961], [], G19, false, '')
 e('referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'se', 0.905, [0.873 0.930], [], T17, false, '')
 e('referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'sp', 0.916, [0.910 0.922], [], T17, false, '')
 e('referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'auc', 0.936, [0.925 0.943], [], T17, false, '')
 e('referable-dr', 'US primary care (pivotal trial)', 'IDx-DR (autonomous)', 'se', 0.872, [0.818 0.912], 819, A18, false, 'more-than-mild DR; imageability 96.1 %')
 e('referable-dr', 'US primary care (pivotal trial)', 'IDx-DR (autonomous)', 'sp', 0.907, [0.883 0.927], 819, A18, false, '')
 e('referable-dr', 'Chennai, India (smartphone camera)', 'EyeArt on Remidio Fundus-on-Phone', 'se', 0.991, [], 296, R18, true, 'sight-threatening DR')
 e('referable-dr', 'Chennai, India (smartphone camera)', 'EyeArt on Remidio Fundus-on-Phone', 'sp', 0.804, [], 296, R18, true, 'sight-threatening DR')
 e('referable-dr', 'Mumbai, India (smartphone camera)', 'Medios offline AI', 'se', 1.000, [0.782 1.000], 213, N19, true, 'on-device, no internet')
 e('referable-dr', 'Mumbai, India (smartphone camera)', 'Medios offline AI', 'sp', 0.884, [0.832 0.925], 213, N19, true, '')
 e('dr-grading', 'APTOS 2019 (private test)', 'Competition winner (ensemble of CNNs)', 'qwk', 0.936, [], [], 'Kaggle APTOS 2019 Blindness Detection, private leaderboard', false, 'hidden labels: an internal hold-out QWK is not directly comparable')
 e('vessels', 'DRIVE', 'Second human observer', 'se', 0.776, [], 20, F12, false, 'values differ slightly between tabulations')
 e('vessels', 'DRIVE', 'Second human observer', 'sp', 0.972, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Second human observer', 'acc', 0.947, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Matched filter (Chaudhuri 1989)', 'acc', 0.8773, [], 20, N04, false, 'single classical technique')
 e('vessels', 'DRIVE', 'Matched filter (Chaudhuri 1989)', 'auc', 0.7878, [], 20, N04, false, '')
 e('vessels', 'DRIVE', 'Morphology + curvature (Zana & Klein 2001)', 'acc', 0.9377, [], 20, N04, false, 'single classical technique')
 e('vessels', 'DRIVE', 'Morphology + curvature (Zana & Klein 2001)', 'auc', 0.8984, [], 20, N04, false, '')
 e('vessels', 'DRIVE', 'Ridge features + kNN (Staal 2004)', 'acc', 0.9441, [], 20, N04, false, 'supervised')
 e('vessels', 'DRIVE', 'Ridge features + kNN (Staal 2004)', 'auc', 0.9520, [], 20, N04, false, '')
 e('vessels', 'DRIVE', 'Gabor wavelet + GMM (Soares 2006)', 'acc', 0.9466, [], 20, F12, false, 'supervised')
 e('vessels', 'DRIVE', 'Gabor wavelet + GMM (Soares 2006)', 'auc', 0.9614, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Multiscale line detector (Nguyen 2013)', 'acc', 0.9407, [], 20, 'Nguyen UTV et al. Pattern Recognit 2013;46(3):703-15', true, 'single classical technique')
 e('vessels', 'DRIVE', 'Gray-level + moment features, NN (Marin 2011)', 'acc', 0.9452, [], 20, F12, false, 'supervised')
 e('vessels', 'DRIVE', 'Gray-level + moment features, NN (Marin 2011)', 'auc', 0.9588, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'se', 0.7406, [], 20, F12, false, 'supervised ensemble')
 e('vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'sp', 0.9807, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'acc', 0.9480, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'auc', 0.9747, [], 20, F12, false, '')
 e('vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015)', 'se', 0.7655, [], 20, 'Azzopardi G et al. Med Image Anal 2015;19(1):46-57', false, 'unsupervised')
 e('vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015)', 'sp', 0.9704, [], 20, 'Azzopardi G et al. Med Image Anal 2015;19(1):46-57', false, '')
 e('vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015)', 'acc', 0.9442, [], 20, 'Azzopardi G et al. Med Image Anal 2015;19(1):46-57', false, '')
 e('vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015)', 'auc', 0.9614, [], 20, 'Azzopardi G et al. Med Image Anal 2015;19(1):46-57', false, '')
 e('vessels', 'DRIVE', 'Deep CNN (Liskowski & Krawiec 2016)', 'acc', 0.9535, [], 20, 'Liskowski P, Krawiec K. IEEE Trans Med Imaging 2016;35(11):2369-80', true, 'deep learning')
 e('vessels', 'DRIVE', 'Deep CNN (Liskowski & Krawiec 2016)', 'auc', 0.9790, [], 20, 'Liskowski P, Krawiec K. IEEE Trans Med Imaging 2016;35(11):2369-80', true, '')
 e('lesion-seg', 'IDRiD', 'Best challenge entry, microaneurysms', 'aupr', 0.5017, [], 27, P20, true, 'deep segmentation networks')
 e('lesion-seg', 'IDRiD', 'Best challenge entry, haemorrhages', 'aupr', 0.6490, [], 27, P20, true, '')
 e('lesion-seg', 'IDRiD', 'Best challenge entry, hard exudates', 'aupr', 0.8850, [], 27, P20, true, '')
 e('lesion-seg', 'IDRiD', 'Best challenge entry, soft exudates', 'aupr', 0.6977, [], 27, P20, true, '')
 e('standard', 'any', 'British Diabetic Association / Exeter standard', 'se', 0.80, [], [], 'British Diabetic Association, 1997', false, 'minimum for sight-threatening DR')
 e('standard', 'any', 'British Diabetic Association / Exeter standard', 'sp', 0.95, [], [], 'British Diabetic Association, 1997', false, '')
 e('standard', 'any', 'FDA pivotal-trial endpoints (IDx-DR)', 'se', 0.85, [], [], A18, false, 'pre-specified superiority endpoint')
 e('standard', 'any', 'FDA pivotal-trial endpoints (IDx-DR)', 'sp', 0.825, [], [], A18, false, '')
 e('standard', 'any', 'NetraSetu target (this project)', 'se', 0.90, [], [], 'Project brief', false, 'referable DR, level 2+')
 e('standard', 'any', 'NetraSetu target (this project)', 'sp', 0.85, [], [], 'Project brief', false, '')
];
B = B(:);
keep = true(numel(B), 1);
if ~isempty(o.Task)
    keep = keep & strcmpi({B.task}', o.Task);
end
if ~isempty(o.Dataset)
    keep = keep & strcmpi({B.dataset}', o.Dataset);
end
if ~isempty(o.Metric)
    keep = keep & strcmpi({B.metric}', o.Metric);
end
B = B(keep);
if nargout == 0
    fprintf('\n  %-26s %-58s %-5s %7s  %s\n', 'dataset', 'method', 'metric', 'value', 'source');
    for i = 1:numel(B)
        flag = '';
        if B(i).verify
            flag = ' (verify)';
        end
        fprintf('  %-26s %-58s %-5s %7.4g  %s%s\n', B(i).dataset, B(i).method, B(i).metric, ...
            B(i).value, B(i).source, flag);
    end
    fprintf('\n');
    clear B
end
end
