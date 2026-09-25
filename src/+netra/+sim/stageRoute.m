function [toUpload, autoNow] = stageRoute(captured, p)
%STAGEROUTE Which captured patients must be uploaded.
%   With edge grading (p(1) = 1) the PHC laptop grades every eye at once:
%   AI-cleared patients get their result on the spot (autoNow, counted at
%   age 0) and only flagged eyes plus the audit sample are uploaded. With
%   cloud grading (p(1) = 0) every patient's images are uploaded.
%   p = [edge fUrgent fRoutine fAuto fQA cloudCap adjudicate]
if p(1) > 0.5
    toUpload = captured * (p(2) + p(3) + p(5));
    autoNow = sum(captured) * p(4);
else
    toUpload = captured;
    autoNow = 0;
end
end
