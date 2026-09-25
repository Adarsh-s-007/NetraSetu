function [qUp, arrived, sent] = stageUplink(qUp, toUpload, upCap)
%STAGEUPLINK Store-and-forward upload queue of every site (FIFO by age).
%   qUp N x B, toUpload N x 1 (new cohorts, age 0), upCap N x 1 patients per
%   step (zero when the link is down or outside upload hours).
%   arrived 1 x B: patients reaching the hub this step, by age since capture.
B = size(qUp, 2);
inflow = [toUpload, zeros(size(toUpload, 1), B - 1)];
[qUp, served, tot] = netra.sim.ageQueue(qUp, inflow, upCap);
arrived = sum(served, 1);
sent = sum(tot);
end
