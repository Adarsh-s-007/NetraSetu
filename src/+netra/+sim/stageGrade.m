function [qAI, inU, inR, inQ, autoByAge, graded] = stageGrade(qAI, arrived, p)
%STAGEGRADE Central AI grading (cloud mode) and triage into review queues.
%   Cloud (p(1) = 0): arrivals queue for the GPU server (p(6) patients per
%   step), then split into urgent / routine-flagged / audit / auto-cleared.
%   Edge (p(1) = 1): the eyes were graded on the device; the upload holds
%   flagged and audit eyes only and is split in proportion.
%   p = [edge fUrgent fRoutine fAuto fQA cloudCap adjudicate]
B = numel(arrived);
if p(1) > 0.5
    share = max(p(2) + p(3) + p(5), eps);
    inU = arrived * p(2) / share;
    inR = arrived * p(3) / share;
    inQ = arrived * p(5) / share;
    autoByAge = zeros(1, B);
    graded = 0;
else
    [qAI, done, n] = netra.sim.ageQueue(qAI, arrived, p(6));
    inU = done * p(2);
    inR = done * p(3);
    inQ = done * p(5);
    autoByAge = done * p(4);
    graded = n;
end
end
