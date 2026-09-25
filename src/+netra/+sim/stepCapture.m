function [wait, captured, balked] = stepCapture(wait, arrivals, capacity, closing)
%STEPCAPTURE One step of photography at every site.
%   [wait, captured, balked] = netra.sim.stepCapture(wait, arrivals, capacity, closing)
%   wait, arrivals, capacity, closing are N x 1 (closing = 1 in the last open
%   step of a site's day). Patients still waiting at closing time go home
%   unscreened ("balked") - the demand a programme loses to queues.
w = wait + arrivals;
captured = min(w, max(capacity, 0));
w = w - captured;
balked = w .* closing;
wait = w .* (1 - closing);
end
