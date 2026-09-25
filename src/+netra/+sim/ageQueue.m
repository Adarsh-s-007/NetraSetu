function [q, served, total] = ageQueue(q, inflow, capacity)
%AGEQUEUE One step of an age-structured first-in-first-out fluid queue.
%
%   [q, served, total] = netra.sim.ageQueue(q, inflow, capacity)
%     q         N x B  patients waiting per site, by age since capture
%               (column 1 = youngest; column B also holds everything older)
%     inflow    N x B  patients arriving this step, carrying their age
%     capacity  N x 1  patients that can be served this step
%     served    N x B  patients served this step, by age at service
%     total     N x 1  row sums of served
%
%   Oldest cohorts are served first; what remains then ages by one bin.
%   Because cohorts keep their age from capture through every downstream
%   queue, the age at which a cohort leaves the last queue IS its
%   end-to-end turnaround - no patient-level simulation is needed and the
%   same function runs in the MATLAB reference model and inside the
%   Simulink MATLAB Function blocks (it is code-generation compatible).
q = q + inflow;
B = size(q, 2);
rev = q(:, B:-1:1);
cum = cumsum(rev, 2);
lim = min(cum, repmat(max(capacity, 0), 1, B));
servedRev = [lim(:, 1), lim(:, 2:B) - lim(:, 1:B - 1)];
served = servedRev(:, B:-1:1);
total = sum(served, 2);
rem = q - served;
q = [zeros(size(q, 1), 1), rem(:, 1:B - 1)];
q(:, B) = q(:, B) + rem(:, B);
end
