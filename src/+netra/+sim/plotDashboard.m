function fig = plotDashboard(R, W, varargin)
%PLOTDASHBOARD One-page district planning dashboard.
%
%   fig = netra.sim.plotDashboard(R, W)             R from netra.sim.optimize,
%   netra.sim.plotDashboard(R, W, 'File', f)        W from netra.sim.whatIf
%
%   A  every plan the optimiser tried: annual cost vs referable patients who
%      reach treatment (edge / cloud grading; filled = meets every target)
%   B  turnaround of the chosen plan: time from photograph to result for
%      AI-cleared eyes, confirmed referrals and urgent confirmations
%   C  reviewer load with the explainable console vs plain image review
%   D  upload backlog through the year: edge vs cloud grading on the same
%      links and the same outages
%   Categorical colours follow a fixed, colour-vision-deficiency validated
%   order (blue, orange, aqua) and every series is labelled directly.

o = netra.util.opts(struct('File', '', 'Visible', 'off', 'DPI', 150), varargin{:});
C = struct('s1', hex('#2a78d6'), 's2', hex('#eb6834'), 's3', hex('#1baf7a'), ...
    'ink', hex('#14182E'), 'soft', hex('#52514e'), 'muted', hex('#898781'), ...
    'grid', hex('#e1e0d9'), 'axis', hex('#c3c2b7'), 'paper', hex('#FBF8F3'), ...
    'surface', hex('#fcfcfb'));
font = 'Helvetica';
if netra.util.isOctave()
    font = 'Noto Sans';
end
P = R.params;
b = R.best;
K = b.kpi;
D = b.decision;
fig = figure('Color', C.paper, 'Units', 'pixels', 'Position', [20 20 1600 1000], ...
    'Visible', o.Visible, 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
top = axes('Parent', fig, 'Position', [0 0 1 1], 'Visible', 'off', 'XLim', [0 1], 'YLim', [0 1]);
hold(top, 'on');
t = @(x, y, s, sz, col, w, al) text(top, x, y, s, 'FontSize', sz, 'Color', col, ...
    'FontWeight', w, 'FontName', font, 'HorizontalAlignment', al, 'Interpreter', 'none');
t(0.035, 0.955, 'District plan', 12, C.muted, 'bold', 'left');
t(0.035, 0.918, sprintf('%s grading, %d PHCs, %s, %s, %d h/day ophthalmologist, AI sensitivity %.2f', ...
    upperFirst(D.aiMode), D.phcEquipped, plural(D.vans, 'mobile unit'), plural(D.graders, 'grader'), ...
    D.ophthHours, D.sensitivity), 17, C.ink, 'bold', 'left');
tiles = {sprintf('Rs %.2f crore', b.cost), 'per year', ...
    sprintf('Rs %.0f', K.costPerScreen), 'per eye screened', ...
    sprintf('%s', commas(K.perYear.screened)), 'screens a year', ...
    sprintf('%s', commas(K.perYear.reachingTreatment)), 'referable patients reach treatment', ...
    sprintf('%.0f h', K.turnaround.routineP95), 'routine result, 95th percentile'};
for k = 1:5
    x = 0.035 + (k - 1) * 0.19;
    t(x, 0.855, tiles{2 * k - 1}, 22, C.ink, 'bold', 'left');
    t(x, 0.822, tiles{2 * k}, 11, C.soft, 'normal', 'left');
end

% ------------------------------------------------------------- A: plans
ax = panel(fig, [0.05 0.44 0.40 0.30], C, font);
ev = R.evaluations;
isEdge = strcmp(arrayfun(@(e) e.decision.aiMode, ev, 'UniformOutput', false), 'edge');
feas = [ev.feasible];
cost = [ev.cost];
reach = arrayfun(@(e) e.kpi.perYear.reachingTreatment, ev);
series = {isEdge, C.s1, 'edge grading'; ~isEdge, C.s2, 'cloud grading'};
for k = 1:2
    m = series{k, 1};
    plot(ax, cost(m & feas), reach(m & feas), 'o', 'MarkerSize', 7, 'MarkerFaceColor', series{k, 2}, ...
        'MarkerEdgeColor', C.surface, 'LineWidth', 1);
    plot(ax, cost(m & ~feas), reach(m & ~feas), 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'none', ...
        'MarkerEdgeColor', series{k, 2}, 'LineWidth', 1.3);
end
plot(ax, b.cost, K.perYear.reachingTreatment, 'o', 'MarkerSize', 13, 'MarkerFaceColor', 'none', ...
    'MarkerEdgeColor', C.ink, 'LineWidth', 1.5);
text(ax, b.cost, K.perYear.reachingTreatment, '   chosen plan', 'FontSize', 10, 'Color', C.ink, ...
    'FontName', font, 'VerticalAlignment', 'middle');
xlabel(ax, 'Annual cost (Rs crore)');
ylabel(ax, 'Referable patients reaching treatment / year');
title(ax, 'A   Every plan tried by the optimiser', 'FontSize', 12, 'Color', C.ink, 'FontName', font, ...
    'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.06 0]);
% headroom above the plans keeps the legend clear of the data
yl = ylim(ax);
ylim(ax, [yl(1), yl(2) + 0.42 * diff(yl)]);
legendText(ax, {C.s1, 'edge grading'; C.s2, 'cloud grading'; [], 'filled = meets every target, ring = misses one'}, C, font);

% ---------------------------------------------------------- B: turnaround
ax = panel(fig, [0.55 0.44 0.40 0.30], C, font);
H = W.base.hist;
ages = W.base.ages;
cdf = @(h) cumsum(h) / max(sum(h), eps);
lines = {H.auto, C.s1, 'AI-cleared: result on the spot'; ...
         H.routine, C.s2, 'referral confirmed by grader'; ...
         H.urgentConfirmed, C.s3, 'urgent: ophthalmologist confirms'};
xmax = 120;
for k = 1:3
    y = 100 * cdf(lines{k, 1});
    plot(ax, [0 ages], [0 y], '-', 'Color', lines{k, 2}, 'LineWidth', 2);
end
line(ax, P.target.routineP95Hours * [1 1], [0 100], 'Color', C.muted, 'LineWidth', 1);
tt = text(ax, P.target.routineP95Hours, 50, sprintf(' %d h routine target', P.target.routineP95Hours), ...
    'FontSize', 9.5, 'Color', C.soft, 'FontName', font, 'VerticalAlignment', 'middle');
xlim(ax, [0 xmax]);
ylim(ax, [0 113]);                            % room to label the 100 % plateau
set(ax, 'YTick', 0:20:100);
xlabel(ax, 'Hours from photograph');
ylabel(ax, 'Share of eyes with a result (%)');
title(ax, 'B   Turnaround of the chosen plan', 'FontSize', 12, 'Color', C.ink, 'FontName', font, ...
    'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.06 0]);
lg = legendText(ax, lines(:, [2 3]), C, font, 'bottom-right');
curvesB = cell(1, size(lines, 1));
for k = 1:size(lines, 1)
    curvesB{k} = [[0 ages(:)']; [0 100 * cdf(lines{k, 1}(:)')]];
end
netra.util.directLabels(ax, curvesB, lines(:, 3)', 'FontName', font, 'Color', C.ink, ...
    'Obstacles', {[P.target.routineP95Hours * [1 1]; 0 100]}, 'Taken', [boxOf(tt); lg]);

% ------------------------------------------------------ C: explainability
ax = panel(fig, [0.05 0.07 0.40 0.27], C, font);
u1 = [W.base.kpi.utilisation.graders, W.base.kpi.utilisation.ophthalmologist] * 100;
u2 = [W.plain.kpi.utilisation.graders, W.plain.kpi.utilisation.ophthalmologist] * 100;
cats = {'Optometrist graders', 'Ophthalmologist'};
bw = 0.32;
for k = 1:2
    barRect(ax, k - bw / 2 - 0.02, bw, u1(k), C.s1, C);
    barRect(ax, k + bw / 2 + 0.02, bw, u2(k), C.s2, C);
    text(ax, k - bw / 2 - 0.02, u1(k) + 4, sprintf('%.0f%%', u1(k)), 'HorizontalAlignment', 'center', ...
        'FontSize', 10, 'Color', C.ink, 'FontName', font);
    text(ax, k + bw / 2 + 0.02, min(u2(k), 118) + 4, sprintf('%.0f%%', u2(k)), 'HorizontalAlignment', 'center', ...
        'FontSize', 10, 'Color', C.ink, 'FontName', font);
end
line(ax, [0.4 2.6], 100 * P.target.maxUtilisation * [1 1], 'Color', C.muted, 'LineWidth', 1);
text(ax, 1.5, 100 * P.target.maxUtilisation + 1.5, sprintf('%.0f%% target', 100 * P.target.maxUtilisation), ...
    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 9.5, ...
    'Color', C.soft, 'FontName', font);
set(ax, 'XTick', 1:2, 'XTickLabel', cats, 'XLim', [0.4 2.6], 'YLim', [0 125]);
ylabel(ax, 'Time in use (%)');
title(ax, sprintf('C   Reviewer load: explainable console (%d s) vs plain review (%d s)', ...
    P.review.secondsPerCase.xai, P.review.secondsPerCase.plain), 'FontSize', 12, 'Color', C.ink, ...
    'FontName', font, 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.06 0]);
legendText(ax, {C.s1, sprintf('explainable console: routine P95 %.0f h', W.base.kpi.turnaround.routineP95); ...
    C.s2, sprintf('plain review: routine P95 %.0f h', W.plain.kpi.turnaround.routineP95)}, C, font);

% --------------------------------------------------------------- D: links
ax = panel(fig, [0.55 0.07 0.40 0.27], C, font);
days = (1:numel(W.edge.series.uplinkBacklog))' / 7;
plot(ax, days, W.cloud.series.uplinkBacklog, '-', 'Color', C.s2, 'LineWidth', 2);
plot(ax, days, W.edge.series.uplinkBacklog, '-', 'Color', C.s1, 'LineWidth', 2);
text(ax, days(end), W.cloud.series.uplinkBacklog(end), sprintf(' cloud: %s waiting', ...
    commas(W.cloud.series.uplinkBacklog(end))), 'Color', C.ink, 'FontSize', 10, 'FontName', font, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
text(ax, days(end), W.edge.series.uplinkBacklog(end), sprintf(' edge: %s waiting', ...
    commas(W.edge.series.uplinkBacklog(end))), 'Color', C.ink, 'FontSize', 10, 'FontName', font, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom');
xlim(ax, [0 days(end)]);
xlabel(ax, 'Week of the year');
ylabel(ax, 'Patients whose images are not yet uploaded');
title(ax, 'D   Upload backlog on the same links and outages', 'FontSize', 12, 'Color', C.ink, ...
    'FontName', font, 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.06 0]);
legendText(ax, {C.s1, 'edge grading: only flagged eyes are uploaded'; C.s2, 'cloud grading: every image is uploaded'}, C, font);

if ~isempty(o.File)
    if netra.util.has('exportgraphics')
        exportgraphics(fig, o.File, 'Resolution', o.DPI);
    else
        print(fig, o.File, '-dpng', sprintf('-r%d', o.DPI));
    end
end
end

% ======================================================================
function ax = panel(fig, pos, C, font)
ax = axes('Parent', fig, 'Position', pos, 'Color', C.surface, 'XColor', C.muted, ...
    'YColor', C.muted, 'GridColor', C.grid, 'GridAlpha', 1, 'Box', 'off', 'TickDir', 'out', ...
    'FontName', font, 'FontSize', 10, 'LineWidth', 0.8);
grid(ax, 'on');
hold(ax, 'on');
end

function barRect(ax, x, w, h, col, C)
patch(ax, x + [-w w w -w] / 2, [0 0 h h], col, 'EdgeColor', C.surface, 'LineWidth', 2);
end

function boxes = legendText(ax, items, C, font, corner)
% colour swatch + label per row; an empty colour gives a note line.
% Returns the rows' boxes in data units ([x0 y0 x1 y1]) for label placement.
if nargin < 5
    corner = 'top-left';
end
n = size(items, 1);
boxes = zeros(0, 4);
for k = 1:n
    if strcmp(corner, 'bottom-right')
        x = 0.64;
        y = 0.07 + 0.09 * (n - k);
    else
        x = 0.02;
        y = 1 - 0.09 * (k - 1) - 0.05;
    end
    if ~isempty(items{k, 1})
        text(ax, x, y, '  ', 'Units', 'normalized', 'BackgroundColor', items{k, 1}, 'FontSize', 6, ...
            'FontName', font, 'VerticalAlignment', 'middle', 'Margin', 1);
    end
    h = text(ax, x + 0.03, y, items{k, 2}, 'Units', 'normalized', 'Color', C.soft, 'FontSize', 9.5, ...
        'FontName', font, 'VerticalAlignment', 'middle');
    set(h, 'Units', 'data');
    b = boxOf(h);
    boxes(end + 1, :) = [b(1) - 0.035 * diff(xlim(ax)), b(2), b(3), b(4)]; %#ok<AGROW>
end
end

function b = boxOf(h)
b = netra.util.textBox(h);                    % [x0 y0 x1 y1], data units, as drawn
end

function c = hex(h)
c = [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
end

function s = commas(v)
s = sprintf('%.0f', v);
n = numel(s);
for k = n - 3:-3:1
    s = [s(1:k) ',' s(k + 1:end)];
end
end

function s = plural(n, word)
if n == 1
    s = sprintf('%d %s', n, word);
else
    s = sprintf('%d %ss', n, word);
end
end

function s = upperFirst(s)
s = [upper(s(1)) s(2:end)];
end
