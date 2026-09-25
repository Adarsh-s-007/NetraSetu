%MAKE_FIGURES Regenerate the figures in docs/img (runs in MATLAB and Octave).
%
%   phantoms.jpg      synthetic eyes, ICDR 0-4, and NetraSetu's annotation of each
%   quality.jpg       the quality gate on five capture failures
%   subpixel.png      microaneurysm localisation error vs signal-to-noise,
%                     against the Cramer-Rao bound
%   report.jpg        the one-page screening report of a severe phantom
%   report.html       the bilingual HTML report (screenshot it for the README)
%   simulink_model.svg  the Simulink model's structure
%   dashboard.png     district plan (needs results/exp06 from exp06)
%   Set figs = {'subpixel', ...} before running to redo only some of them.
%   Everything here is synthetic: these figures show what the software
%   does, not how accurate it is on patients (see the validation dossier).

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(which('netra.config'))
    run(fullfile(root, 'netrasetu_setup.m'));
end
out = fullfile(root, 'docs', 'img');
if ~exist(out, 'dir')
    mkdir(out);
end
cfg = netra.config();
pal = netra.util.palette();
if ~exist('figs', 'var')
    figs = {'phantoms', 'quality', 'subpixel', 'report', 'simulink', 'dashboard'};
end

% ------------------------------------------------------------ phantoms
if any(strcmp(figs, 'phantoms'))
    tiles = {};
    ann = {};
    for g = 0:4
        [rgb, gt] = netra.phantom.generate('Grade', g, 'Seed', 900 + g, 'Size', 1024);
        R = netra.screen(rgb, 'Config', cfg, 'ID', sprintf('phantom-%d', g));
        c = R.canvas;
        t1 = netra.util.cropFOV(rgb, gt.fovCentre, gt.fovRadius);
        t2 = netra.util.cropFOV(R.overlay, c.centre, c.radius);
        tiles{end + 1} = netra.util.imscale(t1, 420 / size(t1, 1)); %#ok<SAGROW>
        ann{end + 1} = netra.util.imscale(t2, 420 / size(t2, 1)); %#ok<SAGROW>
        fprintf('phantom grade %d -> %s (rules grade %d)\n', g, R.decision.triage, R.rules.grade);
    end
    imwrite(netra.util.montage([tiles, ann], 5, 10, pal.paper), fullfile(out, 'phantoms.jpg'), 'Quality', 90);
end

% ------------------------------------------------------------- quality
if any(strcmp(figs, 'quality'))
    [rgb, gt] = netra.phantom.generate('Grade', 1, 'Seed', 77, 'Size', 768);
    cases = {struct(), struct('blur', 6), struct('exposure', 0.3), struct('lash', 0.35), ...
        struct('flare', 0.8, 'haze', 0.5)};
    tiles = {};
    for k = 1:numel(cases)
        im = netra.phantom.degrade(rgb, gt, cases{k});
        Q = netra.quality.assess(im, cfg);
        fb = '';
        if ~isempty(Q.feedback)
            fb = Q.feedback(1).en;
        end
        fprintf('quality case %d: %s (%.2f) %s\n', k, Q.decision, Q.score, fb);
        t1 = netra.util.cropFOV(im, gt.fovCentre, gt.fovRadius);
        tiles{end + 1} = netra.util.imscale(t1, 360 / size(t1, 1)); %#ok<SAGROW>
    end
    imwrite(netra.util.montage(tiles, 5, 10, pal.paper), fullfile(out, 'quality.jpg'), 'Quality', 90);
end

% ------------------------------------------------------------ sub-pixel
if any(strcmp(figs, 'subpixel'))
    rng(1);
    snr = [2 3 5 8 12 20 30];
    nT = 300;
    rm = zeros(numel(snr), 3);
    cr = zeros(numel(snr), 1);
    [X, Y] = meshgrid(1:15);
    for i = 1:numel(snr)
        a = 0.15;
        sn = a / snr(i);
        e = zeros(nT, 3);
        c = zeros(nT, 1);
        for t = 1:nT
            x0 = 8 + rand - 0.5; y0 = 8 + rand - 0.5; s = 0.8 + 1.5 * rand;
            P = 0.02 + 0.001 * (X - 8) + a * exp(-((X - x0) .^ 2 + (Y - y0) .^ 2) / (2 * s ^ 2)) + sn * randn(15);
            bg = median([P(1, :), P(end, :), P(:, 1)', P(:, end)']);
            Ps = imgaussfilt(P, 1.2);                  % candidates come from a smoothed response
            [~, k] = max(Ps(:));
            [ys, xs] = ind2sub([15 15], k);
            f = netra.lesions.fitGaussian2D(P, [xs ys 1.5 0.8 * (max(Ps(:)) - bg)]);
            % baselines: centroid of the half-maximum region, and the brightest pixel
            w = max(P - bg, 0) .* (Ps - bg >= 0.5 * (max(Ps(:)) - bg));
            [~, k] = max(P(:));
            [yi, xi] = ind2sub([15 15], k);
            e(t, :) = [hypot(f.x0 - x0, f.y0 - y0), ...
                hypot(sum(X(:) .* w(:)) / sum(w(:)) - x0, sum(Y(:) .* w(:)) / sum(w(:)) - y0), ...
                hypot(xi - x0, yi - y0)];
            c(t) = sqrt(2) * sqrt(2 / pi) * sn / a;
        end
        rm(i, :) = sqrt(mean(e .^ 2, 1));
        cr(i) = mean(c);
    end
    hexc = @(h) [hex2dec(h(2:3)) hex2dec(h(4:5)) hex2dec(h(6:7))] / 255;
    cols = {hexc('#2a78d6'), hexc('#eb6834'), hexc('#1baf7a')};
    font = 'Helvetica';
    if netra.util.isOctave()
        font = 'Noto Sans';
    end
    fig = figure('Color', pal.paper, 'Units', 'pixels', 'Position', [20 20 900 560], 'Visible', 'off', ...
        'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
    % log-log, drawn as log10 values on linear axes so labels can be placed in data space
    lx = log10(snr);
    ly = log10(rm);
    lc = log10(cr);
    ax = axes('Parent', fig, 'Position', [0.09 0.13 0.60 0.76], 'Color', hexc('#fcfcfb'), ...
        'XColor', hexc('#898781'), 'YColor', hexc('#898781'), 'GridColor', hexc('#e1e0d9'), ...
        'GridAlpha', 1, 'Box', 'off', 'TickDir', 'out', 'FontName', font, 'FontSize', 10);
    hold(ax, 'on');
    grid(ax, 'on');
    plot(ax, lx, lc, '--', 'Color', hexc('#898781'), 'LineWidth', 1.5);
    names = {'Gaussian fit (NetraSetu)', 'half-maximum centroid', 'brightest pixel'};
    for k = 3:-1:1
        plot(ax, lx, ly(:, k), '-o', 'Color', cols{k}, 'LineWidth', 2, 'MarkerSize', 5, ...
            'MarkerFaceColor', cols{k}, 'MarkerEdgeColor', hexc('#fcfcfb'));
    end
    yt = [0.03 0.1 0.3 1 3];
    xlim(ax, log10([1.8 33]));
    ylim(ax, log10([0.025 5]));
    set(ax, 'XTick', lx, 'XTickLabel', arrayfun(@num2str, snr, 'UniformOutput', false), ...
        'YTick', log10(yt), 'YTickLabel', arrayfun(@num2str, yt, 'UniformOutput', false));
    xlabel(ax, 'Signal-to-noise ratio (microaneurysm contrast / pixel noise)');
    ylabel(ax, 'Centre error, RMS (pixels)');
    title(ax, 'Sub-pixel microaneurysm localisation', 'FontSize', 13, 'Color', pal.ink, ...
        'FontName', font, 'HorizontalAlignment', 'left', 'Units', 'normalized', 'Position', [0 1.04 0]);
    % legend and note in an overlay axis (plain text: identical in MATLAB and Octave)
    side = axes('Parent', fig, 'Position', [0.72 0.08 0.27 0.84], 'Visible', 'off', ...
        'XLim', [0 1], 'YLim', [0 1]);
    hold(side, 'on');
    items = [names, {'Cramer-Rao bound'}];
    cl = [cols, {hexc('#898781')}];
    st = {'-', '-', '-', '--'};
    for k = 1:4
        y = 0.92 - 0.075 * (k - 1);
        plot(side, [0 0.1], [y y], st{k}, 'Color', cl{k}, 'LineWidth', 2);
        text(side, 0.14, y, items{k}, 'FontName', font, 'FontSize', 10, 'Color', pal.ink, ...
            'VerticalAlignment', 'middle');
    end
    note = {sprintf('%d simulated spots per point,', nT), '0.8-2.3 px wide, on a tilted', ...
        'background. From SNR 8 up the', sprintf('fit sits on the bound (%.2f vs', rm(4, 1)), ...
        sprintf('%.2f px at SNR 8); the brightest', cr(4)), 'pixel stays 0.4-0.7 px off.', '', ...
        'Below SNR ~6 a fit can lock onto', 'noise: the detector keeps only', ...
        'candidates with SNR >= 3.5', 'against the local texture and a', 'fit that explains the spot.'};
    for k = 1:numel(note)
        text(side, 0, 0.56 - 0.042 * (k - 1), note{k}, 'FontName', font, 'FontSize', 9.5, ...
            'Color', pal.inkSoft, 'VerticalAlignment', 'middle');
    end
    % the fit runs on the bound, so the two are labelled together, below them
    text(ax, log10(5.2), log10(0.052), 'Gaussian fit, on the bound', 'FontName', font, ...
        'FontSize', 10, 'Color', pal.ink, 'VerticalAlignment', 'top');
    netra.util.directLabels(ax, {[lx; ly(:, 2)'], [lx; ly(:, 3)'], [lx; lc']}, ...
        {'centroid', 'brightest pixel', 'bound'}, 'FontName', font, 'Color', pal.ink, ...
        'Obstacles', {[lx; ly(:, 1)']});
    print(fig, fullfile(out, 'subpixel.png'), '-dpng', '-r150');
    close(fig);
    fprintf('sub-pixel RMSE at SNR %s: fit %s  centroid %s  peak %s  bound %s\n', mat2str(snr), ...
        mat2str(rm(:, 1)', 2), mat2str(rm(:, 2)', 2), mat2str(rm(:, 3)', 2), mat2str(cr', 2));
end

% --------------------------------------------------------------- report
if any(strcmp(figs, 'report'))
    [rgb, ~] = netra.phantom.generate('Grade', 3, 'Seed', 903, 'Size', 1024);
    R = netra.screen(rgb, 'Config', cfg, 'ID', 'NS-2026-0417-R', 'Eye', 'R', 'Site', 'PHC Ardhapur, Nanded');
    png = fullfile(out, 'report.png');
    netra.xai.reportFigure(R, 'File', png);
    imwrite(imread(png), fullfile(out, 'report.jpg'), 'Quality', 92);
    delete(png);
    netra.xai.reportHTML(R, fullfile(out, 'report.html'));
    close all
end

% -------------------------------------------------------- simulink model
if any(strcmp(figs, 'simulink'))
    netra.sim.diagramSVG(fullfile(out, 'simulink_model.svg'));
end

% ------------------------------------------------------------ dashboard
if any(strcmp(figs, 'dashboard'))
    f6 = fullfile(cfg.paths.results, 'exp06', 'district_plan.mat');
    if exist(f6, 'file')
        S = load(f6);
        netra.sim.plotDashboard(S.R, S.W, 'File', fullfile(out, 'dashboard.png'));
        close all
    end
end

fprintf('Figures written to %s\n', out);
