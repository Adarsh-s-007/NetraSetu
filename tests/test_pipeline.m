% Image pipeline on synthetic phantoms with exact ground truth: quality,
% anatomy, sub-pixel microaneurysm localisation and end-to-end screening.
cfg = netra.config();

%% Phantom ground truth is internally consistent
[rgb, gt] = netra.phantom.generate('Grade', 2, 'Seed', 11, 'Size', 768);
assert(isequal(size(rgb), [768 768 3]) && all(rgb(:) >= 0 & rgb(:) <= 1));
assert(gt.grade == 2 && ~isempty(gt.ma) && any(gt.maMask(:)));
assert(all(gt.fov(sub2ind(size(gt.fov), round([gt.ma.y]), round([gt.ma.x])))), 'MAs lie in the FOV');
[~, g2] = netra.phantom.degrade(rgb, gt, struct('blur', 6));
assert(~g2.gradable, 'heavy defocus is ungradable');

%% Quality: sharp is gradable, defocused and underexposed are sent for recapture
[rgb, gt] = netra.phantom.generate('Grade', 0, 'Seed', 3, 'Size', 768);
Q = netra.quality.assess(rgb, cfg);
assert(strcmp(Q.decision, 'GRADABLE'), 'clean phantom judged %s (%.2f)', Q.decision, Q.score);
blurred = netra.phantom.degrade(rgb, gt, struct('blur', 6));
Qb = netra.quality.assess(blurred, cfg);
assert(strcmp(Qb.decision, 'RECAPTURE') && Qb.sub.focus < Q.sub.focus);
assert(~isempty(Qb.feedback), 'the operator is told what to fix');
dark = netra.phantom.degrade(rgb, gt, struct('exposure', 0.25));
Qd = netra.quality.assess(dark, cfg);
assert(~strcmp(Qd.decision, 'GRADABLE') && Qd.sub.illumination < Q.sub.illumination);

%% The aperture circle is recovered even when the top and bottom are cut off
[rgb, gt] = netra.phantom.generate('Grade', 0, 'Seed', 5, 'Size', 768);
crop = rgb(90:680, :, :);
F = netra.quality.fovMask(crop);
assert(F.ok && abs(F.radius - gt.fovRadius) / gt.fovRadius < 0.03, 'radius %.1f vs %.1f', F.radius, gt.fovRadius);
assert(F.clipped.top && F.clipped.bottom);

%% Optic disc and fovea are found on healthy and diseased eyes
for g = [0 3]
    [rgb, gt] = netra.phantom.generate('Grade', g, 'Seed', 20 + g, 'Size', 768);
    pre = netra.eval.prepareImage(rgb, cfg);
    A = netra.anatomy.analyze(pre.S, pre.E, cfg);
    od = netra.quality.toOriginal(pre.S, A.od.centre(:)');
    fv = netra.quality.toOriginal(pre.S, A.fovea.centre(:)');
    dd = gt.pxPerDD;
    assert(hypot(od(1) - gt.od(1), od(2) - gt.od(2)) < 0.25 * dd, 'grade %d: disc off', g);
    assert(hypot(fv(1) - gt.fovea(1), fv(2) - gt.fovea(2)) < 0.5 * dd, 'grade %d: fovea off', g);
end

%% Microaneurysm centres are localised below a tenth of a pixel, near the Cramer-Rao bound
rng(1);
err = zeros(200, 1);
crlb = zeros(200, 1);
[X, Y] = meshgrid(1:15);
for t = 1:200
    x0 = 8 + rand - 0.5; y0 = 8 + rand - 0.5; s = 0.8 + 1.5 * rand; a = 0.15; sn = 0.01;
    P = 0.02 + 0.001 * (X - 8) + a * exp(-((X - x0) .^ 2 + (Y - y0) .^ 2) / (2 * s ^ 2)) + sn * randn(15);
    [~, k] = max(P(:));
    [yi, xi] = ind2sub([15 15], k);
    f = netra.lesions.fitGaussian2D(P, [xi yi 1.2 * s 0.8 * a]);
    err(t) = hypot(f.x0 - x0, f.y0 - y0);
    crlb(t) = f.crlb;
end
rmse = sqrt(mean(err .^ 2));
assert(rmse < 0.1, 'RMSE %.3f px', rmse);
assert(rmse < 3 * sqrt(2) * mean(crlb), 'RMSE %.3f vs radial CRLB %.3f', rmse, sqrt(2) * mean(crlb));

%% End to end: a healthy eye is not referred, a severe one is, and the reports are written
[rgb0, ~] = netra.phantom.generate('Grade', 0, 'Seed', 41, 'Size', 1024);
R0 = netra.screen(rgb0, 'Config', cfg, 'ID', 'test-g0');
assert(any(strcmp(R0.decision.triage, {'ROUTINE', 'HUMAN_REVIEW'})), 'grade 0 -> %s', R0.decision.triage);
[rgb3, ~] = netra.phantom.generate('Grade', 3, 'Seed', 43, 'Size', 1024);
R3 = netra.screen(rgb3, 'Config', cfg, 'ID', 'test-g3');
assert(any(strcmp(R3.decision.triage, {'REFER', 'URGENT'})), 'grade 3 -> %s', R3.decision.triage);
assert(R3.rules.grade >= 2 && ~isempty(R3.rules.evidence));
f = [tempname() '.html'];
netra.xai.reportHTML(R3, f);
html = fileread(f);
assert(~isempty(strfind(html, 'NetraSetu')) && ~isempty(strfind(html, 'data:image/jpeg;base64')));
assert(isequal(size(R3.overlay, 1), size(R3.canvas.rgb, 1)));
