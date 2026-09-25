function fig = plotROC(curves, varargin)
%PLOTROC Referable-DR ROC curves of the ablation, zoomed on the screening corner.
%
%   fig = netra.eval.plotROC(curves, 'Title', t, 'File', f, 'Operating', op, ...
%                            'Benchmarks', B, 'Target', [0.90 0.85])
%     curves      struct array: name, fpr, tpr, auc, aucCI - drawn in the
%                 fixed categorical order blue, orange, aqua, then muted
%                 grey (at most four; the first is the integrated pipeline)
%     Operating   [fpr tpr] of the deployed operating point (ringed)
%     Benchmarks  struct array: name, se, sp - published points, drawn as
%                 small hollow markers for context (not head-to-head)
%     Target      [sensitivity specificity] - the shaded corner meets both
%     Zoom        [xmax ymin] of the plotted window (default [0.5 0.5])
%   The legend (with AUC and DeLong 95 % CI) sits under the plot; every
%   curve and marker is also labelled directly where there is room.
o = netra.util.opts(struct('Title', '', 'File', '', 'Operating', [], 'Benchmarks', [], ...
    'Target', [0.90 0.85], 'Zoom', [0.5 0.5], 'Visible', 'off', 'DPI', 150), varargin{:});
hex = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
cols = {hex('#2a78d6'), hex('#eb6834'), hex('#1baf7a'), hex('#898781')};
C = struct('ink', hex('#14182E'), 'soft', hex('#52514e'), 'muted', hex('#898781'), ...
    'grid', hex('#e1e0d9'), 'paper', hex('#FBF8F3'), 'surface', hex('#fcfcfb'), ...
    'target', hex('#e6f0fb'));
font = 'Helvetica';
if netra.util.isOctave()
    font = 'Noto Sans';
end
curves = curves(1:min(4, numel(curves)));
nC = numel(curves);
fig = figure('Color', C.paper, 'Units', 'pixels', 'Position', [20 20 860 820], ...
    'Visible', o.Visible, 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
legH = 0.035 * nC + 0.02;
ax = axes('Parent', fig, 'Position', [0.11 0.10 + legH + 0.04, 0.84, 0.80 - legH - 0.06], ...
    'Color', C.surface, 'XColor', C.muted, 'YColor', C.muted, 'GridColor', C.grid, ...
    'GridAlpha', 1, 'Box', 'off', 'TickDir', 'out', 'FontName', font, 'FontSize', 10, 'LineWidth', 0.8);
hold(ax, 'on');
grid(ax, 'on');
xl = [0 o.Zoom(1)];
yl = [o.Zoom(2) 1.005];
fx = 1 - o.Target(2);
patch(ax, [0 fx fx 0], [o.Target(1) o.Target(1) 1 1], C.target, 'EdgeColor', 'none');
plot(ax, [0 1], [0 1], '-', 'Color', C.grid, 'LineWidth', 1);
xy = cell(1, nC);
for k = nC:-1:1
    lw = 2;
    if k == 1
        lw = 2.6;
    end
    xy{k} = [curves(k).fpr(:)'; curves(k).tpr(:)'];
    plot(ax, xy{k}(1, :), xy{k}(2, :), '-', 'Color', cols{k}, 'LineWidth', lw);
end
xlim(ax, xl);
ylim(ax, yl);
% point annotations: operating point, published points, the target corner
pts = {};
lab = {};
if ~isempty(o.Benchmarks)
    for k = 1:numel(o.Benchmarks)
        b = o.Benchmarks(k);
        if 1 - b.sp <= xl(2) && b.se >= yl(1)
            plot(ax, 1 - b.sp, b.se, 'o', 'MarkerSize', 6, 'MarkerFaceColor', C.surface, ...
                'MarkerEdgeColor', C.ink, 'LineWidth', 1);
            pts{end + 1} = [1 - b.sp; b.se]; %#ok<AGROW>
            lab{end + 1} = b.name; %#ok<AGROW>
        end
    end
end
if ~isempty(o.Operating)
    plot(ax, o.Operating(1), o.Operating(2), 'o', 'MarkerSize', 12, 'MarkerFaceColor', 'none', ...
        'MarkerEdgeColor', C.ink, 'LineWidth', 1.6);
    pts{end + 1} = o.Operating(:);
    lab{end + 1} = sprintf('operating point: Se %.1f%%, Sp %.1f%%', 100 * o.Operating(2), ...
        100 * (1 - o.Operating(1)));
end
pts{end + 1} = [fx; o.Target(1)];
lab{end + 1} = 'target';
netra.util.directLabels(ax, pts, lab, 'Mode', 'points', 'FontName', font, 'FontSize', 9, ...
    'Color', C.soft, 'Obstacles', xy);
taken = zeros(0, 4);
for h = findobj(ax, 'Type', 'text')'
    taken(end + 1, :) = netra.util.textBox(h); %#ok<AGROW>
end
netra.util.directLabels(ax, xy, {curves.name}, 'FontName', font, 'Color', C.ink, ...
    'Taken', taken, 'Obstacles', {[0 1; 0 1]});
xlabel(ax, '1 - specificity (non-referable eyes flagged)');
ylabel(ax, 'Sensitivity (referable eyes flagged)');
title(ax, o.Title, 'FontSize', 13, 'Color', C.ink, 'FontName', font, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.035 0]);
% legend under the plot
lg = axes('Parent', fig, 'Position', [0.11 0.02 0.84 legH], 'Visible', 'off', ...
    'XLim', [0 1], 'YLim', [0 1]);
for k = 1:nC
    y = 1 - (k - 0.5) / nC;
    text(lg, 0, y, '   ', 'BackgroundColor', cols{k}, 'FontSize', 5, 'Margin', 1, ...
        'VerticalAlignment', 'middle');
    ci = '';
    if isfield(curves, 'aucCI') && numel(curves(k).aucCI) == 2
        ci = sprintf('  (95%% CI %.3f-%.3f)', curves(k).aucCI(1), curves(k).aucCI(2));
    end
    text(lg, 0.035, y, sprintf('%s:  AUC %.3f%s', curves(k).name, curves(k).auc, ci), ...
        'FontSize', 10, 'Color', C.soft, 'FontName', font, 'VerticalAlignment', 'middle');
end
text(lg, 1, 1 - 0.5 / nC, sprintf('shaded target: Se >= %.0f%%, Sp >= %.0f%%', 100 * o.Target(1), ...
    100 * o.Target(2)), 'FontSize', 9, 'Color', C.muted, 'FontName', font, ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
text(lg, 1, 1 - 1.5 / nC, sprintf('zoomed: 1 - Sp 0-%.1f, Se %.1f-1', xl(2), yl(1)), ...
    'FontSize', 9, 'Color', C.muted, 'FontName', font, 'HorizontalAlignment', 'right', ...
    'VerticalAlignment', 'middle');
if ~isempty(o.File)
    if netra.util.has('exportgraphics')
        exportgraphics(fig, o.File, 'Resolution', o.DPI);
    else
        print(fig, o.File, '-dpng', sprintf('-r%d', o.DPI));
    end
end
end
