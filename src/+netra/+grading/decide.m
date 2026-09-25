function T = decide(Q, R, Fz, sets, A, X, cfg)
%DECIDE Turn grades, evidence and uncertainty into one triage decision.
%
%   T = netra.grading.decide(Q, R, Fz, sets, A, X, cfg)
%     Q     quality (netra.quality.assess, possibly after enhancement)
%     R     rule engine (netra.grading.icdrRules)
%     Fz    fused distribution (netra.grading.fuse)
%     sets  1 x 5 logical conformal set (netra.grading.conformal), or []
%     A     anatomy (flags), X explainability (concordance), or []
%
%   Order of precedence (first match wins):
%     RECAPTURE     the photograph cannot be graded
%     URGENT        P(PDR) >= cfg.grading.urgentThreshold, neovascularisation
%                   or pre-retinal haemorrhage in the evidence, or exudates
%                   within ~500 um of the fovea (centre-involving DME)
%     REFER         P(referable) >= cfg.grading.referralThreshold, or DME 2
%     HUMAN_REVIEW  anything that makes an automatic "normal" unsafe:
%                   conformal set straddling the referral boundary, branches
%                   disagreeing by >= cfg.grading.disagreement grades,
%                   borderline quality, anatomy not found, or a CNN that
%                   looked away from the lesions (low concordance)
%     ROUTINE       otherwise
%   REFER and URGENT cases are always confirmed by a person in the
%   programme workflow; HUMAN_REVIEW catches the uncertain "normals".
%
%   T fields: triage, grade, pReferable, pUrgent, dme, reasons (cellstr),
%   followUp, message.en / message.hi (patient text), colour.

g = cfg.grading;
reasons = {};
triage = 'ROUTINE';
pRef = Fz.pReferable;
if R.dme >= 2
    pRef = 1 - (1 - pRef) * (1 - 0.9);
end

if strcmp(Q.decision, 'RECAPTURE')
    triage = 'RECAPTURE';
    for k = 1:numel(Q.feedback)
        reasons{end + 1} = Q.feedback(k).en; %#ok<AGROW>
    end
    if isempty(reasons)
        reasons{end + 1} = sprintf('Image quality %.2f below the gradable threshold', Q.score);
    end
else
    urgentEvidence = any(strcmp({R.criteria([R.criteria.met]).id}, 'nv')) || ...
        any(strcmp({R.criteria([R.criteria.met]).id}, 'prh'));
    if Fz.pUrgent >= g.urgentThreshold || urgentEvidence || R.centreInvolved
        triage = 'URGENT';
        if Fz.pUrgent >= g.urgentThreshold
            reasons{end + 1} = sprintf('P(proliferative DR) = %.2f', Fz.pUrgent);
        end
        if urgentEvidence
            reasons{end + 1} = 'Neovascularisation or pre-retinal haemorrhage in the lesion evidence';
        end
        if R.centreInvolved
            reasons{end + 1} = 'Exudates within 500 um of the foveal centre';
        end
    elseif pRef >= g.referralThreshold || R.dme >= 2
        triage = 'REFER';
        reasons{end + 1} = sprintf('P(referable DR or DME) = %.2f (threshold %.2f)', pRef, g.referralThreshold);
        if R.dme >= 2
            reasons{end + 1} = 'Hard exudates within 1 DD of the fovea (macular oedema risk)';
        end
    else
        review = {};
        if ~isempty(sets) && any(sets(1:2)) && any(sets(3:5))
            review{end + 1} = sprintf('Uncertain: plausible grades %s span the referral boundary', ...
                setText(sets));
        end
        if Fz.disagreement >= g.disagreement
            review{end + 1} = sprintf('Branches disagree by %d grades (%s)', Fz.disagreement, ...
                branchText(Fz));
        end
        if ~strcmp(Q.decision, 'GRADABLE')
            review{end + 1} = sprintf('Borderline image quality (%.2f)', Q.score);
        end
        if ~isempty(A) && ~isempty(A.flags)
            review{end + 1} = ['Anatomy: ' strjoin(A.flags, ', ')];
        end
        if ~isempty(X) && isfield(X, 'concordance') && isfield(X.concordance, 'flag') && ...
                X.concordance.flag
            review{end + 1} = 'Network attention does not coincide with detected lesions';
        end
        if ~isempty(review)
            triage = 'HUMAN_REVIEW';
            reasons = review;
        else
            reasons{end + 1} = sprintf('P(referable) = %.2f, below %.2f; grade %d', ...
                pRef, g.referralThreshold, Fz.grade);
        end
    end
end

P = netra.util.palette();
T = struct();
T.triage = triage;
T.grade = Fz.grade;
T.pReferable = pRef;
T.pUrgent = Fz.pUrgent;
T.dme = R.dme;
T.reasons = reasons;
key = triage;
if R.dme >= 2 && strcmp(triage, 'REFER')
    key = 'REFER_DME';                   % macular oedema risk: sooner, and said once
end
T.followUp = g.followUp.(key);
T.message = struct('en', netra.util.i18n(['triage.' key], 'en'), ...
                   'hi', netra.util.i18n(['triage.' key], 'hi'));
if R.dme >= 2 && strcmp(triage, 'URGENT')
    T.message.en = [T.message.en ' ' netra.util.i18n('dme', 'en')];
    T.message.hi = [T.message.hi ' ' netra.util.i18n('dme', 'hi')];
end
T.colour = P.(triage);
end

function s = setText(sets)
g = find(sets) - 1;
s = ['{' strjoin(arrayfun(@num2str, g, 'UniformOutput', false), ', ') '}'];
end

function s = branchText(Fz)
parts = cell(1, numel(Fz.branchNames));
for k = 1:numel(Fz.branchNames)
    parts{k} = sprintf('%s %d', Fz.branchNames{k}, Fz.branchGrades(k));
end
s = strjoin(parts, ', ');
end
