/* =========================================================================
   NetraSetu engine
   A JavaScript port of NetraSetu's classical screening pipeline, so a fundus
   photograph can be checked on the device that took it, with no upload:

     netra.quality.fovMask / standardize / assess / enhance / background
     netra.anatomy.vessels / opticDisc / fovea / frame
     netra.lesions.microaneurysms (+ fitGaussian2D) / hemorrhages / exudates /
       neovascularization (+ netra.util.skeletonSegments)
     netra.grading.probabilisticRules / icdrRules / fuse / decide
     netra.xai.evidenceMap, and the overlay as switchable layers

   Same parameters as netra.config. Not ported: the trained CNN and lesion
   ensemble (no trained weights exist yet), venous beading and IRMA-like
   anomalies. The grade therefore rests on the ICDR rule engine, exactly as
   netra.screen does in MATLAB when no trained models are loaded.

   Images are row-major Float32Arrays (index y * w + x), 0-based pixel
   centres. Runs as a Web Worker (postMessage) or under Node (require).
   ========================================================================= */
(function (root) {
  'use strict';

  var CFG = {
    scale: { workDiameter: 1024, vesselDiameter: 560, anatomyDiameter: 512, umPerDD: 1500, ddPerFOV: 0.14, ddTolerance: 0.35 },
    quality: {
      gradable: 0.60, recapture: 0.35, minCoverage: 0.55,
      weights: { field: 1.0, focus: 1.5, illumination: 1.0, contrast: 1.0, artifact: 0.75 },
      focusCenter: 0.55, focusWidth: 0.06, contrastCenter: 0.090, contrastWidth: 0.020,
      lumaCenter: 0.14, lumaWidth: 0.035, noiseCenter: 0.025, noiseWidth: 0.004,
      darkMaxFrac: 0.25, brightMaxFrac: 0.08, darkLevel: 0.35, saturation: 0.98, noiseHigh: 0.010,
      uniformityMin: 0.65, uniformityWidth: 0.05, shadowMax: 0.12, minSubscore: 0.50, failSubscore: 0.15
    },
    enhance: { claheClip: 0.010, claheTiles: 8, backgroundDD: 0.55, targetRGB: [0.72, 0.36, 0.16] },
    vessels: {
      hessianSigmas: [1, 1.5, 2, 3, 4], frangiBeta: 0.5, frangiC: 0.5, lineWindow: 15,
      lineScales: [1, 3, 5, 7, 9, 11, 13, 15], lineAngles: 12, tophatLengths: [7, 11, 15],
      weights: { hessian: 0.40, line: 0.40, tophat: 0.20 }, highFraction: 0.075, lowFraction: 0.125,
      minAreaDD2: 0.004, thickWidthDD: 0.055
    },
    od: { wBrightness: 1.0, wThickVessels: 0.8, wVertical: 0.8, wConvergence: 1.0, maxRadiusFOV: 0.92, refineWindowDD: 1.7 },
    fovea: { distanceDD: 2.5, belowDD: 0.30, searchRadiusDD: 1.1, priorSigmaDD: 0.6 },
    ma: {
      maxMAUm: 125, maxDotUm: 250, minUm: 15, sigmaUm: [9, 13, 19, 28, 42, 63], openingDD: 0.20,
      openingAngles: 12, thresholdK: 4.0, minContrast: 0.020, minAmplitude: 0.050, maxCandidates: 600,
      fitRadius: 3.0, minSNR: 3.5, minR2: 0.40, minRoundness: 0.55, maxExit: 0.35, maxIter: 30
    },
    he: { minDarkening: 0.08, thresholdK: 3.5, openRadiusUm: 60, minAreaUm2: 125 * 125, flameEcc: 0.88, flameAlign: 0.70, flameMinLenUm: 200, preretinalDA: 1.0 },
    ex: {
      minBrightening: 0.08, thresholdK: 4.5, sharpEdge: 0.55, minYellow: 2.0, cwsMinDD: 0.08, cwsMaxDD: 0.60,
      cwsMaxEcc: 0.88, cwsMinSolidity: 0.60, dmeRadiusDD: 1.0, centreRadiusDD: 1 / 3, odExclusion: 1.80
    },
    nv: { windowDD: 0.50, strideDD: 0.25, discZoneDD: 1.50, threshold: 8.5, zCap: 3.0, minWindows: 2 },
    rules: { maHighProb: 0.80, maMinHigh: 1, maMinCount: 4, hePerQuadrant: 10, heQuadrants: 4, nvProb: 0.50, evidenceFloor: 0.30, smoothing: 0.10, gradePrior: [0.62, 0.12, 0.16, 0.05, 0.05] },
    grading: { referralThreshold: 0.50, urgentThreshold: 0.35, mcSamples: 256 }
  };

  /* ================================================================ basics */
  var EPS = 2.220446049250313e-16;
  function mround(x) { return x < 0 ? -Math.round(-x) : Math.round(x); }   // MATLAB round
  function sigmoid(x, c, w) { if (c !== undefined) { x = (x - c) / w; } return 1 / (1 + Math.exp(-x)); }
  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
  function sortedCopy(values) { var s = Float64Array.from(values); s.sort(); return s; }
  function pctSorted(s, p) {                              // netra.util.pct
    var n = s.length;
    if (!n) { return NaN; }
    if (n === 1) { return s[0]; }
    var pos = (n - 1) * clamp(p, 0, 100) / 100, lo = Math.floor(pos), hi = Math.min(lo + 1, n - 1), w = pos - lo;
    return s[lo] * (1 - w) + s[hi] * w;
  }
  function pct(values, p) { return pctSorted(sortedCopy(values), p); }
  function select(a, k) {                                // k-th smallest (0-based), in place, O(n)
    var lo = 0, hi = a.length - 1;
    while (hi > lo) {
      var mid = (lo + hi) >> 1, pv = a[mid], i = lo, j = hi, t;
      if (a[lo] > pv) { t = a[lo]; a[lo] = a[mid]; a[mid] = t; pv = a[mid]; }
      while (i <= j) {
        while (a[i] < pv) { i++; }
        while (a[j] > pv) { j--; }
        if (i <= j) { t = a[i]; a[i] = a[j]; a[j] = t; i++; j--; }
      }
      if (k <= j) { hi = j; } else if (k >= i) { lo = i; } else { return a[k]; }
    }
    return a[k];
  }
  function median(values) {                              // same value as pct(values, 50)
    var n = values.length;
    if (!n) { return NaN; }
    var a = Float64Array.from(values);
    if (n % 2) { return select(a, (n - 1) / 2); }
    var hiV = select(a, n / 2), loV = -Infinity;
    for (var i = 0; i < n / 2; i++) { if (a[i] > loV) { loV = a[i]; } }
    return (loV + hiV) / 2;
  }
  function robustStats(values) {                         // netra.util.robustStats
    var v = [];
    for (var i = 0; i < values.length; i++) { if (isFinite(values[i])) { v.push(values[i]); } }
    if (!v.length) { return [NaN, NaN]; }
    var med = median(v), dev = new Float64Array(v.length);
    for (i = 0; i < v.length; i++) { dev[i] = Math.abs(v[i] - med); }
    var sigma = 1.4826 * median(dev);
    if (!(sigma > 0)) {
      var m = 0, s2 = 0;
      for (i = 0; i < v.length; i++) { m += v[i]; }
      m /= v.length;
      for (i = 0; i < v.length; i++) { s2 += (v[i] - m) * (v[i] - m); }
      sigma = v.length > 1 ? Math.sqrt(s2 / (v.length - 1)) : 0;
    }
    if (!(sigma > 0)) { sigma = EPS; }
    return [med, sigma];
  }
  function pick(img, mask) {                             // img(mask) as a plain array
    var out = [];
    for (var i = 0; i < img.length; i++) { if (mask[i]) { out.push(img[i]); } }
    return out;
  }
  function meanOf(img, mask) {
    var s = 0, n = 0;
    for (var i = 0; i < img.length; i++) { if (mask[i]) { s += img[i]; n++; } }
    return n ? s / n : NaN;
  }
  function otsu(values, nbins) {                         // netra.util.otsu (values in [0,1])
    nbins = nbins || 256;
    var hist = new Float64Array(nbins), n = 0;
    for (var i = 0; i < values.length; i++) {
      var v = values[i];
      if (!isFinite(v)) { continue; }
      v = clamp(v, 0, 1);
      hist[Math.min(Math.floor(v * nbins), nbins - 1)]++;
      n++;
    }
    if (!n) { return 0.5; }
    var omega = 0, mu = 0, muT = 0, k;
    for (k = 0; k < nbins; k++) { muT += (hist[k] / n) * (k + 1); }
    var best = -1, bestK = 0;
    for (k = 0; k < nbins; k++) {
      omega += hist[k] / n;
      mu += (hist[k] / n) * (k + 1);
      var sb = Math.pow(muT * omega - mu, 2) / Math.max(omega * (1 - omega), EPS);
      if (sb > best) { best = sb; bestK = k; }
    }
    return (bestK + 0.5) / nbins;
  }

  /* ============================================================ filtering */
  function gaussKernel(s) {
    if (s <= 0) { return new Float64Array([1]); }
    var h = Math.ceil(3 * s), k = new Float64Array(2 * h + 1), sum = 0;
    for (var x = -h; x <= h; x++) { k[x + h] = Math.exp(-x * x / (2 * s * s)); sum += k[x + h]; }
    for (x = 0; x < k.length; x++) { k[x] /= sum; }
    return k;
  }
  // correlate rows with kx and columns with ky, replicated borders. Rows use
  // the kernel's symmetry (Gaussian and its derivatives are even or odd);
  // columns are accumulated a whole row at a time for cache locality.
  function symmetryOf(k) {
    var r = (k.length - 1) >> 1, even = true, odd = true;
    for (var i = 1; i <= r; i++) {
      if (Math.abs(k[r + i] - k[r - i]) > 1e-12 * Math.abs(k[r])) { even = false; }
      if (Math.abs(k[r + i] + k[r - i]) > 1e-15) { odd = false; }
    }
    return even ? 1 : odd && Math.abs(k[r]) < 1e-15 ? -1 : 0;
  }
  function sepFilter(src, w, h, ky, kx) {
    var tmp = new Float32Array(w * h), out = new Float32Array(w * h), rx = (kx.length - 1) >> 1, ry = (ky.length - 1) >> 1;
    var x, y, k, s, p, row, sym = symmetryOf(kx), kxf = Float64Array.from(kx);
    var xa = Math.min(rx, w), xb = Math.max(xa, w - rx);  // [xa, xb) needs no border clamping
    for (y = 0; y < h; y++) {
      row = y * w;
      for (x = 0; x < xa; x++) {
        s = 0;
        for (k = -rx; k <= rx; k++) { s += kxf[k + rx] * src[row + clamp(x + k, 0, w - 1)]; }
        tmp[row + x] = s;
      }
      if (sym === 1) {
        for (p = row + xa; p < row + xb; p++) { s = kxf[rx] * src[p]; for (k = 1; k <= rx; k++) { s += kxf[rx + k] * (src[p + k] + src[p - k]); } tmp[p] = s; }
      } else if (sym === -1) {
        for (p = row + xa; p < row + xb; p++) { s = 0; for (k = 1; k <= rx; k++) { s += kxf[rx + k] * (src[p + k] - src[p - k]); } tmp[p] = s; }
      } else {
        for (p = row + xa; p < row + xb; p++) { s = 0; for (k = -rx; k <= rx; k++) { s += kxf[k + rx] * src[p + k]; } tmp[p] = s; }
      }
      for (x = xb; x < w; x++) {
        s = 0;
        for (k = -rx; k <= rx; k++) { s += kxf[k + rx] * src[row + clamp(x + k, 0, w - 1)]; }
        tmp[row + x] = s;
      }
    }
    // columns: whole rows at a time; an even or odd kernel pairs rows y - k and y + k
    var symY = symmetryOf(ky), kyf = Float64Array.from(ky);
    for (y = 0; y < h; y++) {
      row = y * w;
      if (symY !== 0) {
        var c0 = kyf[ry], r0 = row;
        if (c0 !== 0) { for (x = 0; x < w; x++) { out[row + x] = c0 * tmp[r0 + x]; } }
        for (k = 1; k <= ry; k++) {
          var ck = kyf[ry + k], ra = clamp(y - k, 0, h - 1) * w, rb = clamp(y + k, 0, h - 1) * w;
          if (ck === 0) { continue; }
          if (symY === 1) { for (x = 0; x < w; x++) { out[row + x] += ck * (tmp[rb + x] + tmp[ra + x]); } }
          else { for (x = 0; x < w; x++) { out[row + x] += ck * (tmp[rb + x] - tmp[ra + x]); } }
        }
      } else {
        for (k = -ry; k <= ry; k++) {
          var c = kyf[k + ry], srow = clamp(y + k, 0, h - 1) * w;
          if (c === 0) { continue; }
          for (x = 0; x < w; x++) { out[row + x] += c * tmp[srow + x]; }
        }
      }
    }
    return out;
  }
  // resize(gauss(src, w, h, s), w, h, W2, H2) evaluated only at the pixels
  // the bilinear resampling reads: exact, and a large prefilter becomes cheap
  function gaussResize(src, w, h, s, W2, H2) {
    var k = gaussKernel(s), r = (k.length - 1) >> 1, x, y, j, t, acc;
    function taps(n, N) {                                  // resize's source pixels and weights
      var i0 = new Int32Array(N), i1 = new Int32Array(N), fr = new Float64Array(N), need = new Int32Array(n).fill(-1), list = [];
      for (var q = 0; q < N; q++) {
        var qs = clamp((q + 0.5) * n / N - 0.5, 0, n - 1), qa = Math.floor(qs);
        i0[q] = qa; i1[q] = Math.min(qa + 1, n - 1); fr[q] = qs - qa;
        [i0[q], i1[q]].forEach(function (v) { if (need[v] < 0) { need[v] = list.length; list.push(v); } });
      }
      return { i0: i0, i1: i1, fr: fr, slot: need, list: list };
    }
    var TX = taps(w, W2), TY = taps(h, H2), nc = TX.list.length, nr = TY.list.length;
    var rowF = new Float64Array(h * nc);                  // rows filtered, at the needed columns only
    for (y = 0; y < h; y++) {
      for (j = 0; j < nc; j++) {
        x = TX.list[j]; acc = 0;
        for (t = -r; t <= r; t++) { acc += k[t + r] * src[y * w + clamp(x + t, 0, w - 1)]; }
        rowF[y * nc + j] = acc;
      }
    }
    var both = new Float64Array(nr * nc);                 // then columns, at the needed rows only
    for (var q = 0; q < nr; q++) {
      y = TY.list[q];
      for (j = 0; j < nc; j++) {
        acc = 0;
        for (t = -r; t <= r; t++) { acc += k[t + r] * rowF[clamp(y + t, 0, h - 1) * nc + j]; }
        both[q * nc + j] = acc;
      }
    }
    var out = new Float32Array(W2 * H2);
    for (y = 0; y < H2; y++) {
      var ya = TY.slot[TY.i0[y]] * nc, yb = TY.slot[TY.i1[y]] * nc, fy = TY.fr[y];
      for (x = 0; x < W2; x++) {
        var xa = TX.slot[TX.i0[x]], xb = TX.slot[TX.i1[x]], fx = TX.fr[x];
        out[y * W2 + x] = (1 - fy) * ((1 - fx) * both[ya + xa] + fx * both[ya + xb]) + fy * ((1 - fx) * both[yb + xa] + fx * both[yb + xb]);
      }
    }
    return out;
  }
  function gauss(src, w, h, s) { if (s <= 0) { return Float32Array.from(src); } var k = gaussKernel(s); return sepFilter(src, w, h, k, k); }
  function gauss2(src, w, h, sy, sx) {                   // netra.util.gauss2
    if (Math.min(sy, sx) >= 6 && w % 2 === 0 && h % 2 === 0) {
      // both widths large: filter the 2 x 2 block average and interpolate
      // back; the block adds 1/4 px^2 of variance, taken off the kernel
      var b = boxDown(src, w, h, 2);
      return resize(sepFilter(b.d, b.w, b.h, gaussKernel(Math.sqrt(sy * sy - 0.25) / 2), gaussKernel(Math.sqrt(sx * sx - 0.25) / 2)), b.w, b.h, w, h);
    }
    return sepFilter(src, w, h, gaussKernel(sy), gaussKernel(sx));
  }
  function boxMean(src, w, h, win) {                     // imfilter(ones(win)/win^2, 'replicate')
    var k = new Float64Array(win).fill(1 / win);
    return sepFilter(src, w, h, k, k);
  }
  // imresize(..., 'bilinear') without antialiasing, MATLAB pixel-centre convention
  function resize(src, w, h, W2, H2) {
    var out = new Float32Array(W2 * H2), sx = w / W2, sy = h / H2, x, y;
    var x0s = new Int32Array(W2), x1s = new Int32Array(W2), fxs = new Float64Array(W2);
    for (x = 0; x < W2; x++) {
      var xs = clamp((x + 0.5) * sx - 0.5, 0, w - 1), xa = Math.floor(xs);
      x0s[x] = xa; x1s[x] = Math.min(xa + 1, w - 1); fxs[x] = xs - xa;
    }
    for (y = 0; y < H2; y++) {
      var ys = clamp((y + 0.5) * sy - 0.5, 0, h - 1), ya = Math.floor(ys), yb = Math.min(ya + 1, h - 1), fy = ys - ya;
      var ra = ya * w, rb = yb * w, ro = y * W2;
      for (x = 0; x < W2; x++) {
        var fx = fxs[x];
        out[ro + x] = (1 - fy) * ((1 - fx) * src[ra + x0s[x]] + fx * src[ra + x1s[x]]) + fy * ((1 - fx) * src[rb + x0s[x]] + fx * src[rb + x1s[x]]);
      }
    }
    return out;
  }
  function imscale(src, w, h, W2, H2) {                  // netra.util.imscale: Gaussian pre-filter when shrinking
    var f = Math.min(W2 / w, H2 / h);
    if (f < 0.999) { src = gauss(src, w, h, 0.45 / f); }
    return resize(src, w, h, W2, H2);
  }
  function resizeNearest(src, w, h, W2, H2) {
    var out = new (src.constructor)(W2 * H2);
    for (var y = 0; y < H2; y++) {
      var ys = Math.min(Math.floor((y + 0.5) * h / H2), h - 1);
      for (var x = 0; x < W2; x++) { out[y * W2 + x] = src[ys * w + Math.min(Math.floor((x + 0.5) * w / W2), w - 1)]; }
    }
    return out;
  }
  function resizeMask(mask, w, h, W2, H2) {              // imresize(double(m), 'bilinear') >= 0.5
    var f = new Float32Array(mask.length);
    for (var i = 0; i < mask.length; i++) { f[i] = mask[i] ? 1 : 0; }
    var r = resize(f, w, h, W2, H2), out = new Uint8Array(W2 * H2);
    for (i = 0; i < r.length; i++) { out[i] = r[i] >= 0.5 ? 1 : 0; }
    return out;
  }
  function smooth(src, w, h, sigma) {                    // netra.util.smooth
    if (sigma <= 6) { return gauss(src, w, h, sigma); }
    var f = Math.floor(sigma / 3), hs = Math.max(4, Math.ceil(h / f)), ws = Math.max(4, Math.ceil(w / f));
    var small = gaussResize(src, w, h, 0.5 * f, ws, hs);
    small = gauss(small, ws, hs, Math.sqrt(Math.max(sigma * sigma - 0.25 * f * f, 1)) * hs / h);
    return resize(small, ws, hs, w, h);
  }
  function maskedSmooth(src, weight, w, h, sigma) {      // netra.util.maskedSmooth
    var n = src.length, iw = new Float32Array(n), wf = new Float32Array(n), i;
    for (i = 0; i < n; i++) { wf[i] = weight[i] ? 1 : 0; iw[i] = src[i] * wf[i]; }
    var num = smooth(iw, w, h, sigma), den = smooth(wf, w, h, sigma), out = new Float32Array(n), plain = null;
    for (i = 0; i < n; i++) {
      if (den[i] < 1e-3) { if (!plain) { plain = smooth(src, w, h, sigma); } out[i] = plain[i]; }
      else { out[i] = num[i] / Math.max(den[i], 1e-6); }
    }
    return out;
  }
  // median filter, symmetric borders, sliding histogram over 256 levels
  function medianFilter(src, w, h, k) {
    var r = (k - 1) >> 1, lo = Infinity, hi = -Infinity, i;
    for (i = 0; i < src.length; i++) { if (src[i] < lo) { lo = src[i]; } if (src[i] > hi) { hi = src[i]; } }
    var out = new Float32Array(w * h);
    if (!(hi > lo)) { out.fill(lo); return out; }
    var q = new Uint8Array(src.length), scale = 255 / (hi - lo);
    for (i = 0; i < src.length; i++) { q[i] = Math.round((src[i] - lo) * scale); }
    function sym(v, n) { while (v < 0 || v >= n) { v = v < 0 ? -v - 1 : 2 * n - v - 1; } return v; }
    var half = (k * k + 1) >> 1, hist = new Int32Array(256);
    for (var y = 0; y < h; y++) {
      hist.fill(0);
      for (var dy = -r; dy <= r; dy++) {
        var row = sym(y + dy, h) * w;
        for (var dx = -r; dx <= r; dx++) { hist[q[row + sym(dx, w)]]++; }
      }
      for (var x = 0; x < w; x++) {
        if (x > 0) {
          var xo = sym(x - r - 1, w), xn = sym(x + r, w);
          for (dy = -r; dy <= r; dy++) { var rr = sym(y + dy, h) * w; hist[q[rr + xo]]--; hist[q[rr + xn]]++; }
        }
        var c = 0, b = 0;
        for (b = 0; b < 256; b++) { c += hist[b]; if (c >= half) { break; } }
        out[y * w + x] = lo + b / scale;
      }
    }
    return out;
  }

  /* ========================================================= morphology */
  // squared Euclidean distance transform (Felzenszwalb & Huttenlocher) with
  // the index of the nearest feature pixel: dist to nearest pixel where fg=1
  function edt(fg, w, h) {
    var INF = 1e20, n = w * h, d1 = new Float64Array(n), ny = new Int32Array(n);
    var f = new Float64Array(Math.max(w, h)), v = new Int32Array(Math.max(w, h)), z = new Float64Array(Math.max(w, h) + 1);
    var x, y, q, k, s, p, near = new Int32Array(w).fill(-1);
    // columns: the input is binary, so this pass is the distance to the
    // nearest feature pixel above or below, found by two row-major sweeps
    // (ties go to the pixel above, as the lower envelope would choose)
    for (p = 0, y = 0; y < h; y++) { for (x = 0; x < w; x++, p++) { if (fg[p]) { near[x] = y; } ny[p] = near[x]; } }
    near.fill(-1);
    for (y = h - 1; y >= 0; y--) {
      for (p = y * w, x = 0; x < w; x++, p++) {
        if (fg[p]) { near[x] = y; }
        var up = ny[p], dn = near[x], b = up >= 0 && (dn < 0 || y - up <= dn - y) ? up : dn;
        ny[p] = b; d1[p] = b < 0 ? INF : (y - b) * (y - b);
      }
    }
    var d2 = new Float64Array(n), idx = new Int32Array(n);
    for (y = 0; y < h; y++) {                            // rows
      for (x = 0; x < w; x++) { f[x] = d1[y * w + x]; }
      k = 0; v[0] = 0; z[0] = -INF; z[1] = INF;
      for (q = 1; q < w; q++) {
        s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
        while (s <= z[k]) { k--; s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]); }
        k++; v[k] = q; z[k] = s; z[k + 1] = INF;
      }
      k = 0;
      for (q = 0; q < w; q++) {
        while (z[k + 1] < q) { k++; }
        d2[y * w + q] = (q - v[k]) * (q - v[k]) + f[v[k]];
        var nyv = ny[y * w + v[k]];
        idx[y * w + q] = nyv < 0 ? -1 : nyv * w + v[k];
      }
    }
    return { d2: d2, idx: idx };
  }
  function any(m) { for (var i = 0; i < m.length; i++) { if (m[i]) { return true; } } return false; }
  function count(m) { var c = 0; for (var i = 0; i < m.length; i++) { if (m[i]) { c++; } } return c; }
  function erodeDisk(m, w, h, r) {                       // imerode(m, strel('disk', r, 0))
    if (!any(m)) { return new Uint8Array(m.length); }
    var bg = new Uint8Array(m.length);
    for (var i = 0; i < m.length; i++) { bg[i] = m[i] ? 0 : 1; }
    if (!any(bg)) { return Uint8Array.from(m); }
    var d = edt(bg, w, h).d2, out = new Uint8Array(m.length), r2 = r * r;
    for (i = 0; i < m.length; i++) { out[i] = m[i] && d[i] > r2 ? 1 : 0; }
    return out;
  }
  function dilateDisk(m, w, h, r) {
    if (!any(m)) { return new Uint8Array(m.length); }
    var d = edt(m, w, h).d2, out = new Uint8Array(m.length), r2 = r * r;
    for (var i = 0; i < m.length; i++) { out[i] = d[i] <= r2 ? 1 : 0; }
    return out;
  }
  function maskErode(E, r) {                             // erodeDisk(E.mask, D, D, r) on one shared transform
    if (E.bgD2 === undefined) {
      var bg = new Uint8Array(E.mask.length), i;
      for (i = 0; i < bg.length; i++) { bg[i] = E.mask[i] ? 0 : 1; }
      E.bgD2 = any(bg) ? edt(bg, E.D, E.D).d2 : null;
    }
    if (!E.bgD2) { return Uint8Array.from(E.mask); }
    var out = new Uint8Array(E.mask.length), r2 = r * r, d = E.bgD2;
    for (var j = 0; j < out.length; j++) { out[j] = E.mask[j] && d[j] > r2 ? 1 : 0; }
    return out;
  }
  function openDisk(m, w, h, r) { return dilateDisk(erodeDisk(m, w, h, r), w, h, r); }
  function closeDisk(m, w, h, r) { return erodeDisk(dilateDisk(m, w, h, r), w, h, r); }
  function dilate3(m, w, h) {                            // imdilate(m, true(3))
    var out = new Uint8Array(m.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!m[y * w + x]) { continue; }
        for (var dy = -1; dy <= 1; dy++) {
          var yy = y + dy;
          if (yy < 0 || yy >= h) { continue; }
          for (var dx = -1; dx <= 1; dx++) { var xx = x + dx; if (xx >= 0 && xx < w) { out[yy * w + xx] = 1; } }
        }
      }
    }
    return out;
  }
  function diskOffsets(r) {
    var o = [];
    for (var dy = -r; dy <= r; dy++) { for (var dx = -r; dx <= r; dx++) { if (dx * dx + dy * dy <= r * r) { o.push([dx, dy]); } } }
    return o;
  }
  function lineOffsets(len, deg) {                       // netra.util.lineSE
    var hh = Math.floor(Math.max(len, 1) / 2), seen = {}, o = [];
    for (var t = -hh; t <= hh; t++) {
      var dx = mround(t * Math.cos(deg * Math.PI / 180)), dy = mround(-t * Math.sin(deg * Math.PI / 180)), key = dx + ',' + dy;
      if (!seen[key]) { seen[key] = 1; o.push([dx, dy]); }
    }
    return o;
  }
  // grey-level erosion/dilation over an offset set; out-of-image samples
  // are ignored (MATLAB pads erosion with +Inf and dilation with -Inf)
  function greyMorph(src, w, h, offs, isMax) {
    var out = new Float32Array(w * h), n = offs.length, k, x, y;
    var lin = new Int32Array(n), dxs = new Int32Array(n), dys = new Int32Array(n), mnx = 0, mxx = 0, mny = 0, mxy = 0;
    for (k = 0; k < n; k++) {
      dxs[k] = offs[k][0]; dys[k] = offs[k][1]; lin[k] = dys[k] * w + dxs[k];
      mnx = Math.min(mnx, dxs[k]); mxx = Math.max(mxx, dxs[k]); mny = Math.min(mny, dys[k]); mxy = Math.max(mxy, dys[k]);
    }
    var x0 = -mnx, x1 = w - 1 - mxx, y0 = -mny, y1 = h - 1 - mxy;
    for (y = 0; y < h; y++) {
      var row = y * w, inY = y >= y0 && y <= y1;
      for (x = 0; x < w; x++) {
        var p = row + x, best, v;
        if (inY && x >= x0 && x <= x1) {
          best = src[p + lin[0]];
          if (isMax) { for (k = 1; k < n; k++) { v = src[p + lin[k]]; if (v > best) { best = v; } } }
          else { for (k = 1; k < n; k++) { v = src[p + lin[k]]; if (v < best) { best = v; } } }
        } else {
          best = isMax ? -Infinity : Infinity;
          for (k = 0; k < n; k++) {
            var xx = x + dxs[k], yy = y + dys[k];
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) { continue; }
            v = src[yy * w + xx];
            if (isMax ? v > best : v < best) { best = v; }
          }
        }
        out[p] = best;
      }
    }
    return out;
  }
  function greyOpen(src, w, h, offs) { return greyMorph(greyMorph(src, w, h, offs, false), w, h, offs, true); }
  // Openings by straight line segments of several lengths at one angle
  // (`deg` degrees, x right and y up, like netra.util.lineSE), folded into
  // sups[j] = max(sups[j], opening by lens[j]). O(1) per pixel whatever the
  // length: the image is partitioned into translated copies of one digital
  // line and running minima, then maxima, are taken along each (Soille,
  // Breen & Jones, IEEE PAMI 1996). Every pixel lies on exactly one of the
  // lines, so an opening's erosion and dilation share one gathered line.
  function lineOpenInto(src, w, h, lens, deg, sups) {
    var th = deg * Math.PI / 180, dx = Math.cos(th), dy = -Math.sin(th), big = Math.max(Math.abs(dx), Math.abs(dy));
    var alongX = Math.abs(dx) >= Math.abs(dy), n = alongX ? w : h, m = alongX ? h : w, s = alongX ? dy / dx : dx / dy;
    var off = new Int32Array(n), k, j, v;
    for (k = 0; k < n; k++) { off[k] = mround(s * k); }
    // |s| <= 1, so off moves by at most one per step and takes every value
    // in [lo, hi]; first / final hold the first and last k with each value
    var last = off[n - 1], lo = Math.min(0, last), hi = Math.max(0, last), rise = last >= 0;
    var first = new Int32Array(hi - lo + 1).fill(-1), final = new Int32Array(hi - lo + 1);
    for (k = 0; k < n; k++) { v = off[k] - lo; if (first[v] < 0) { first[v] = k; } final[v] = k; }
    var rs = lens.map(function (len) { return mround((Math.max(len, 1) - 1) / 2 * big); }), rmax = Math.max.apply(null, rs);
    var seq = new Float32Array(n), idx = new Int32Array(n), ero = new Float32Array(n), res = new Float32Array(n),
      g = new Float32Array(n + 2 * rmax + 1), hh = new Float32Array(n + 2 * rmax + 1), pad = new Float32Array(n + 2 * rmax + 1);
    for (var c0 = -hi; c0 <= m - 1 - lo; c0++) {
      var vA = -c0, vB = m - 1 - c0, k1, k2;               // the samples with vA <= off[k] <= vB
      if (rise) { k1 = vA <= lo ? 0 : first[vA - lo]; k2 = vB >= hi ? n - 1 : final[vB - lo]; }
      else { k1 = vB >= hi ? 0 : first[vB - lo]; k2 = vA <= lo ? n - 1 : final[vA - lo]; }
      if (k1 < 0 || k2 < k1) { continue; }
      var cnt = 0;
      for (k = k1; k <= k2; k++) {
        var c = c0 + off[k], p = alongX ? c * w + k : k * w + c;
        idx[cnt] = p; seq[cnt] = src[p]; cnt++;
      }
      for (j = 0; j < rs.length; j++) {
        runMin(seq, cnt, rs[j], ero, g, hh, pad);
        runMax(ero, cnt, rs[j], res, g, hh, pad);
        var sj = sups[j];
        for (k = 0; k < cnt; k++) { var q = idx[k]; if (res[k] > sj[q]) { sj[q] = res[k]; } }
      }
    }
  }
  function lineOpen(src, w, h, len, deg) {               // imopen(src, netra.util.lineSE(len, deg))
    var out = new Float32Array(w * h).fill(-Infinity);
    lineOpenInto(src, w, h, [len], deg, [out]);
    return out;
  }
  // running max / min over [i - r, i + r], clipped at the ends: van Herk /
  // Gil-Werman, three comparisons per sample whatever r. g, hh and pad hold
  // at least n + 2r values.
  function runMax(line, n, r, out, g, hh, pad) {
    var m = n + 2 * r, len = 2 * r + 1, i, j, e, v;
    if (r <= 0) { for (i = 0; i < n; i++) { out[i] = line[i]; } return; }
    for (j = 0; j < r; j++) { pad[j] = -Infinity; pad[n + r + j] = -Infinity; }
    for (j = 0; j < n; j++) { pad[j + r] = line[j]; }
    for (var b = 0; b < m; b += len) {
      e = b + len < m ? b + len : m;
      v = pad[b]; g[b] = v;
      for (j = b + 1; j < e; j++) { if (pad[j] > v) { v = pad[j]; } g[j] = v; }
      v = pad[e - 1]; hh[e - 1] = v;
      for (j = e - 2; j >= b; j--) { if (pad[j] > v) { v = pad[j]; } hh[j] = v; }
    }
    for (i = 0; i < n; i++) { var a = hh[i], c = g[i + 2 * r]; out[i] = a > c ? a : c; }
  }
  function runMin(line, n, r, out, g, hh, pad) {
    var m = n + 2 * r, len = 2 * r + 1, i, j, e, v;
    if (r <= 0) { for (i = 0; i < n; i++) { out[i] = line[i]; } return; }
    for (j = 0; j < r; j++) { pad[j] = Infinity; pad[n + r + j] = Infinity; }
    for (j = 0; j < n; j++) { pad[j + r] = line[j]; }
    for (var b = 0; b < m; b += len) {
      e = b + len < m ? b + len : m;
      v = pad[b]; g[b] = v;
      for (j = b + 1; j < e; j++) { if (pad[j] < v) { v = pad[j]; } g[j] = v; }
      v = pad[e - 1]; hh[e - 1] = v;
      for (j = e - 2; j >= b; j--) { if (pad[j] < v) { v = pad[j]; } hh[j] = v; }
    }
    for (i = 0; i < n; i++) { var a = hh[i], c = g[i + 2 * r]; out[i] = a < c ? a : c; }
  }
  // exact grey dilation (erosion) by the disk dx^2 + dy^2 <= r^2: the max
  // (min) over the disk's rows of horizontal running maxima (minima). Rows
  // of equal half-width, dy and -dy at least, share one running image.
  function greyDisk(src, w, h, r, isMax) {
    var out = new Float32Array(w * h).fill(isMax ? -Infinity : Infinity), H = new Float32Array(w * h), row = new Float32Array(w), buf = new Float32Array(w),
      g = new Float32Array(w + 2 * r + 1), hh = new Float32Array(w + 2 * r + 1), pad = new Float32Array(w + 2 * r + 1);
    var widths = [], rowsOf = [], dy, y, x, gi, o, s0;
    for (dy = -r; dy <= r; dy++) {
      var hw = Math.floor(Math.sqrt(r * r - dy * dy));
      gi = widths.indexOf(hw);
      if (gi < 0) { gi = widths.length; widths.push(hw); rowsOf.push([]); }
      rowsOf[gi].push(dy);
    }
    for (gi = 0; gi < widths.length; gi++) {
      for (y = 0; y < h; y++) {
        o = y * w;
        for (x = 0; x < w; x++) { row[x] = src[o + x]; }
        if (isMax) { runMax(row, w, widths[gi], buf, g, hh, pad); } else { runMin(row, w, widths[gi], buf, g, hh, pad); }
        for (x = 0; x < w; x++) { H[o + x] = buf[x]; }
      }
      for (var t = 0; t < rowsOf[gi].length; t++) {
        dy = rowsOf[gi][t];
        for (y = Math.max(0, -dy); y < Math.min(h, h - dy); y++) {
          o = y * w; s0 = (y + dy) * w;
          if (isMax) { for (x = 0; x < w; x++) { if (H[s0 + x] > out[o + x]) { out[o + x] = H[s0 + x]; } } }
          else { for (x = 0; x < w; x++) { if (H[s0 + x] < out[o + x]) { out[o + x] = H[s0 + x]; } } }
        }
      }
    }
    return out;
  }
  function greyCloseDisk(src, w, h, r) { return greyDisk(greyDisk(src, w, h, r, true), w, h, r, false); }

  /* ================================================== binary components */
  function label(m, w, h) {                              // bwlabel(m, 8)
    var lab = new Int32Array(w * h), n = 0, stack = new Int32Array(w * h), comps = [];
    for (var i = 0; i < m.length; i++) {
      if (!m[i] || lab[i]) { continue; }
      n++;
      var sp = 0, pix = [];
      stack[sp++] = i; lab[i] = n;
      while (sp) {
        var p = stack[--sp], py = (p / w) | 0, px = p - py * w;
        pix.push(p);
        for (var dy = -1; dy <= 1; dy++) {
          var yy = py + dy;
          if (yy < 0 || yy >= h) { continue; }
          for (var dx = -1; dx <= 1; dx++) {
            var xx = px + dx;
            if (xx < 0 || xx >= w) { continue; }
            var q = yy * w + xx;
            if (m[q] && !lab[q]) { lab[q] = n; stack[sp++] = q; }
          }
        }
      }
      comps.push(pix);
    }
    return { lab: lab, n: n, comps: comps };
  }
  function areaOpen(m, w, h, minArea) {                  // bwareaopen
    var L = label(m, w, h), out = new Uint8Array(m.length);
    L.comps.forEach(function (pix) { if (pix.length >= minArea) { pix.forEach(function (p) { out[p] = 1; }); } });
    return out;
  }
  function reconstruct(strong, weak, w, h) {             // imreconstruct(strong, weak), binary
    var out = new Uint8Array(weak.length), stack = [], i;
    for (i = 0; i < weak.length; i++) { if (strong[i] && weak[i] && !out[i]) { out[i] = 1; stack.push(i); } }
    while (stack.length) {
      var p = stack.pop(), py = (p / w) | 0, px = p - py * w;
      for (var dy = -1; dy <= 1; dy++) {
        var yy = py + dy;
        if (yy < 0 || yy >= h) { continue; }
        for (var dx = -1; dx <= 1; dx++) {
          var xx = px + dx;
          if (xx < 0 || xx >= w) { continue; }
          var q = yy * w + xx;
          if (weak[q] && !out[q]) { out[q] = 1; stack.push(q); }
        }
      }
    }
    return out;
  }
  function fillHoles(m, w, h) {                          // imfill(m, 'holes')
    var outside = new Uint8Array(m.length), stack = [], x, y;
    function seed(p) { if (!m[p] && !outside[p]) { outside[p] = 1; stack.push(p); } }
    for (x = 0; x < w; x++) { seed(x); seed((h - 1) * w + x); }
    for (y = 0; y < h; y++) { seed(y * w); seed(y * w + w - 1); }
    while (stack.length) {
      var p = stack.pop(), py = (p / w) | 0, px = p - py * w;
      if (px > 0) { seed(p - 1); }
      if (px < w - 1) { seed(p + 1); }
      if (py > 0) { seed(p - w); }
      if (py < h - 1) { seed(p + w); }
    }
    var out = new Uint8Array(m.length);
    for (var i = 0; i < m.length; i++) { out[i] = outside[i] ? 0 : 1; }
    return out;
  }
  function perimeter(m, w, h) {                          // bwperim, 4-connected
    var out = new Uint8Array(m.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var p = y * w + x;
        if (!m[p]) { continue; }
        if (x === 0 || y === 0 || x === w - 1 || y === h - 1 || !m[p - 1] || !m[p + 1] || !m[p - w] || !m[p + w]) { out[p] = 1; }
      }
    }
    return out;
  }
  function largest(m, w, h) {
    var L = label(m, w, h), best = null, out = new Uint8Array(m.length);
    L.comps.forEach(function (pix) { if (!best || pix.length > best.length) { best = pix; } });
    if (best) { best.forEach(function (p) { out[p] = 1; }); }
    return out;
  }
  function thin(m, w, h) {                               // bwmorph(m, 'thin', Inf) - Zhang & Suen
    // padded copy so neighbours never leave the array; only foreground pixels are visited
    var W = w + 2, img = new Uint8Array(W * (h + 2)), live = [], x, y, i;
    for (y = 0; y < h; y++) { for (x = 0; x < w; x++) { if (m[y * w + x]) { img[(y + 1) * W + x + 1] = 1; live.push((y + 1) * W + x + 1); } } }
    var changed = true, del = [];
    while (changed) {
      changed = false;
      for (var pass = 0; pass < 2; pass++) {
        del.length = 0;
        for (i = 0; i < live.length; i++) {
          var p = live[i];
          if (!img[p]) { continue; }
          var p2 = img[p - W], p3 = img[p - W + 1], p4 = img[p + 1], p5 = img[p + W + 1], p6 = img[p + W], p7 = img[p + W - 1], p8 = img[p - 1], p9 = img[p - W - 1];
          var B = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9;
          if (B < 2 || B > 6) { continue; }
          var A = (!p2 && p3) + (!p3 && p4) + (!p4 && p5) + (!p5 && p6) + (!p6 && p7) + (!p7 && p8) + (!p8 && p9) + (!p9 && p2);
          if (A !== 1) { continue; }
          if (pass === 0 ? (p2 * p4 * p6 === 0 && p4 * p6 * p8 === 0) : (p2 * p4 * p8 === 0 && p2 * p6 * p8 === 0)) { del.push(p); }
        }
        if (del.length) { changed = true; for (i = 0; i < del.length; i++) { img[del[i]] = 0; } }
      }
      if (changed) { live = live.filter(function (q) { return img[q]; }); }
    }
    var out = new Uint8Array(w * h);
    for (i = 0; i < live.length; i++) { var q = live[i], yy = ((q / W) | 0) - 1, xx = q % W - 1; out[yy * w + xx] = 1; }
    return out;
  }
  function convexArea(pix, w) {                          // area of the convex hull of the pixel squares
    var pts = [];
    pix.forEach(function (p) {
      var y = (p / w) | 0, x = p - y * w;
      pts.push([x - 0.5, y - 0.5], [x + 0.5, y - 0.5], [x - 0.5, y + 0.5], [x + 0.5, y + 0.5]);
    });
    pts.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
    function cross(o, a, b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
    var lower = [], upper = [], i;
    for (i = 0; i < pts.length; i++) { while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], pts[i]) <= 0) { lower.pop(); } lower.push(pts[i]); }
    for (i = pts.length - 1; i >= 0; i--) { while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], pts[i]) <= 0) { upper.pop(); } upper.push(pts[i]); }
    var hull = lower.slice(0, -1).concat(upper.slice(0, -1)), a = 0;
    for (i = 0; i < hull.length; i++) { var j = (i + 1) % hull.length; a += hull[i][0] * hull[j][1] - hull[j][0] * hull[i][1]; }
    return Math.abs(a) / 2;
  }
  function regionProps(pix, w) {                         // regionprops: Area, Centroid, Eccentricity, axes, Solidity
    var n = pix.length, mx = 0, my = 0, i, x, y;
    for (i = 0; i < n; i++) { y = (pix[i] / w) | 0; x = pix[i] - y * w; mx += x; my += y; }
    mx /= n; my /= n;
    var uxx = 0, uyy = 0, uxy = 0;
    for (i = 0; i < n; i++) { y = (pix[i] / w) | 0; x = pix[i] - y * w; uxx += (x - mx) * (x - mx); uyy += (y - my) * (y - my); uxy += (x - mx) * (y - my); }
    uxx = uxx / n + 1 / 12; uyy = uyy / n + 1 / 12; uxy /= n;
    var common = Math.sqrt((uxx - uyy) * (uxx - uyy) + 4 * uxy * uxy);
    var major = 2 * Math.SQRT2 * Math.sqrt(uxx + uyy + common), minor = 2 * Math.SQRT2 * Math.sqrt(Math.max(uxx + uyy - common, 0));
    var ecc = major > 0 ? 2 * Math.sqrt(Math.max((major / 2) * (major / 2) - (minor / 2) * (minor / 2), 0)) / major : 0;
    return { area: n, cx: mx, cy: my, major: major, minor: minor, ecc: ecc, solidity: n / Math.max(convexArea(pix, w), 1) };
  }
  function circleFit(xs, ys, nIter) {                    // netra.util.circleFit (robust Kasa)
    nIter = nIter || 4;
    var n = xs.length, inl = new Uint8Array(n).fill(1), c = [NaN, NaN], r = NaN;
    for (var it = 0; it < nIter; it++) {
      var S = [[0, 0, 0], [0, 0, 0], [0, 0, 0]], b = [0, 0, 0], m = 0, i;
      for (i = 0; i < n; i++) {
        if (!inl[i]) { continue; }
        var row = [xs[i], ys[i], 1], rhs = -(xs[i] * xs[i] + ys[i] * ys[i]);
        for (var a = 0; a < 3; a++) { b[a] += row[a] * rhs; for (var q = 0; q < 3; q++) { S[a][q] += row[a] * row[q]; } }
        m++;
      }
      if (m < 3) { break; }
      var p = solve(S, b);
      if (!p) { break; }
      c = [-p[0] / 2, -p[1] / 2];
      r = Math.sqrt(Math.max(c[0] * c[0] + c[1] * c[1] - p[2], 0));
      var res = [], all = new Float64Array(n);
      for (i = 0; i < n; i++) { all[i] = Math.abs(Math.hypot(xs[i] - c[0], ys[i] - c[1]) - r); if (inl[i]) { res.push(all[i]); } }
      var s = robustStats(res)[1], lim = Math.max(3 * s, 1.0), same = true;
      for (i = 0; i < n; i++) { var ni = all[i] <= lim ? 1 : 0; if (ni !== inl[i]) { same = false; inl[i] = ni; } }
      if (same) { break; }
    }
    return { c: c, r: r };
  }
  function solve(A, b) {                                 // Gaussian elimination, partial pivoting
    var n = b.length, M = [], i, j, k;
    for (i = 0; i < n; i++) { M.push(A[i].slice()); M[i].push(b[i]); }
    for (k = 0; k < n; k++) {
      var piv = k;
      for (i = k + 1; i < n; i++) { if (Math.abs(M[i][k]) > Math.abs(M[piv][k])) { piv = i; } }
      if (Math.abs(M[piv][k]) < 1e-300) { return null; }
      var t = M[k]; M[k] = M[piv]; M[piv] = t;
      for (i = k + 1; i < n; i++) {
        var f = M[i][k] / M[k][k];
        for (j = k; j <= n; j++) { M[i][j] -= f * M[k][j]; }
      }
    }
    var x = new Array(n);
    for (i = n - 1; i >= 0; i--) { var s = M[i][n]; for (j = i + 1; j < n; j++) { s -= M[i][j] * x[j]; } x[i] = s / M[i][i]; }
    return x;
  }
  function invert(A) {
    var n = A.length, inv = [];
    for (var c = 0; c < n; c++) {
      var e = new Array(n).fill(0); e[c] = 1;
      var col = solve(A, e);
      if (!col) { return null; }
      inv.push(col);
    }
    return inv;                                          // inv[c][r] = (A^-1)[r][c]
  }

  /* ======================================================= geometry fill */
  function fillOutside(plane, mask, w, h, smoothSigma, nearest) { // netra.util.fillOutside
    var inside = true, i;
    for (i = 0; i < mask.length; i++) { if (!mask[i]) { inside = false; break; } }
    if (inside) { return Float32Array.from(plane); }
    var idx = nearest || edt(mask, w, h).idx, out = Float32Array.from(plane);
    for (i = 0; i < mask.length; i++) { if (!mask[i]) { out[i] = plane[idx[i]]; } }
    if (smoothSigma > 0) {
      var sm = gauss(out, w, h, smoothSigma);
      for (i = 0; i < mask.length; i++) { if (!mask[i]) { out[i] = sm[i]; } }
    }
    return out;
  }
  function background(ch, mask, w, h, sigma, nearest) {  // netra.quality.background
    var f = 4, ws = Math.max(1, Math.round(w / f)), hs = Math.max(1, Math.round(h / f)), i;
    var filled = fillOutside(ch, mask, w, h, 0, nearest), mf = new Float32Array(mask.length), small, ms;
    for (i = 0; i < mask.length; i++) { mf[i] = mask[i] ? 1 : 0; }
    if (w % f === 0 && h % f === 0) {
      // a 4 x 4 block average is the anti-aliasing filter here; the estimate
      // is smoothed far more heavily below
      small = boxDown(filled, w, h, f).d; ms = boxDown(mf, w, h, f).d;
    } else {
      small = imscale(filled, w, h, ws, hs); ms = imscale(mf, w, h, ws, hs);
    }
    var msm = new Uint8Array(ws * hs), anyIn = false;
    for (i = 0; i < ms.length; i++) { msm[i] = ms[i] > 0.5 ? 1 : 0; if (msm[i]) { anyIn = true; } }
    var out = new Float32Array(w * h);
    if (!anyIn) { out.fill(Math.max(meanOf(ch, mask) || 0, EPS)); return out; }
    var s = Math.max(sigma / f, 2), k = 2 * mround(0.75 * s) + 1;
    var B1 = medianFilter(small, ws, hs, k), rel = new Float32Array(ws * hs);
    for (i = 0; i < rel.length; i++) { rel[i] = small[i] / Math.max(B1[i], 1e-3) - 1; }
    var rs = robustStats(pick(rel, msm))[1], wgt = new Uint8Array(ws * hs), lim = 2.5 * Math.max(rs, 0.01);
    for (i = 0; i < wgt.length; i++) { wgt[i] = msm[i] && Math.abs(rel[i]) < lim ? 1 : 0; }
    var B2 = maskedSmooth(small, wgt, ws, hs, s), B = resize(B2, ws, hs, w, h);
    for (i = 0; i < B.length; i++) { B[i] = Math.max(B[i], 1e-3); }
    return B;
  }
  function noiseSigma(img, mask, w, h) {                 // netra.quality.noiseSigma (Immerkaer, median)
    var inner = erodeSquare(mask, w, h, 2), v = [];
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        var p = y * w + x;
        if (!inner[p]) { continue; }
        var r = img[p - w - 1] - 2 * img[p - w] + img[p - w + 1] - 2 * img[p - 1] + 4 * img[p] - 2 * img[p + 1] + img[p + w - 1] - 2 * img[p + w] + img[p + w + 1];
        v.push(Math.abs(r));
      }
    }
    return v.length ? median(v) / (0.6745 * 6) : NaN;
  }
  function erodeSquare(m, w, h, r) {                     // imerode(m, true(2r+1))
    var out = new Uint8Array(m.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var ok = 1;
        for (var dy = -r; dy <= r && ok; dy++) {
          var yy = y + dy;
          if (yy < 0 || yy >= h) { continue; }
          for (var dx = -r; dx <= r; dx++) { var xx = x + dx; if (xx >= 0 && xx < w && !m[yy * w + xx]) { ok = 0; break; } }
        }
        out[y * w + x] = ok && m[y * w + x] ? 1 : 0;
      }
    }
    return out;
  }

  /* ===================================================== FOV and canvas */
  function toPlanes(img) {                               // RGBA bytes -> float planes in [0,1]
    var n = img.width * img.height, r = new Float32Array(n), g = new Float32Array(n), b = new Float32Array(n), d = img.data;
    for (var i = 0; i < n; i++) { r[i] = d[4 * i] / 255; g[i] = d[4 * i + 1] / 255; b[i] = d[4 * i + 2] / 255; }
    return { w: img.width, h: img.height, r: r, g: g, b: b };
  }
  function boxDown(src, w, h, k) {                       // area average by an integer factor
    var W2 = Math.floor(w / k), H2 = Math.floor(h / k), out = new Float32Array(W2 * H2), inv = 1 / (k * k);
    for (var y = 0; y < H2; y++) {
      for (var x = 0; x < W2; x++) {
        var s = 0;
        for (var dy = 0; dy < k; dy++) { var row = (y * k + dy) * w + x * k; for (var dx = 0; dx < k; dx++) { s += src[row + dx]; } }
        out[y * W2 + x] = s * inv;
      }
    }
    return { d: out, w: W2, h: H2 };
  }
  function fovMask(P) {                                  // netra.quality.fovMask
    var W = P.w, H = P.h, s = Math.min(1, 512 / Math.max(H, W)), ws = Math.max(1, Math.round(W * s)), hs = Math.max(1, Math.round(H * s));
    var mx = new Float32Array(W * H);
    for (var i = 0; i < mx.length; i++) { mx[i] = Math.max(P.r[i], P.g[i], P.b[i]); }
    var v = imscale(mx, W, H, ws, hs);
    v = medianFilter(v, ws, hs, 5);
    var sv = sortedCopy(v), floorLvl = pctSorted(sv, 3), p10 = pctSorted(sv, 10), low = [];
    for (i = 0; i < v.length; i++) { if (v[i] <= p10) { low.push(v[i]); } }
    var bgSigma = robustStats(low)[1], t = otsu(v);
    var thr = Math.max(0.35 * t, floorLvl + 6 * bgSigma, 0.02), m = new Uint8Array(v.length);
    for (i = 0; i < v.length; i++) { m[i] = v[i] > thr ? 1 : 0; }
    m = openDisk(m, ws, hs, 2);
    m = fillHoles(m, ws, hs);
    m = largest(m, ws, hs);
    var F = { ok: false, s: s, ws: ws, hs: hs, small: m, centre: [(W - 1) / 2, (H - 1) / 2], radius: Math.min(H, W) / 2, coverage: 0, W: W, H: H };
    if (count(m) < 0.05 * m.length) { return F; }
    var per = perimeter(m, ws, hs), xs = [], ys = [];
    for (var y = 0; y < hs; y++) {
      for (var x = 0; x < ws; x++) {
        if (per[y * ws + x] && x > 1 && y > 1 && x < ws - 2 && y < hs - 2) { xs.push(x); ys.push(y); }
      }
    }
    var c, r;
    if (xs.length >= 40) {
      var fit = circleFit(xs, ys);
      c = fit.c; r = fit.r;
    } else {
      var x0 = ws, x1 = -1, y0 = hs, y1 = -1;
      for (y = 0; y < hs; y++) { for (x = 0; x < ws; x++) { if (m[y * ws + x]) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); } } }
      c = [(x0 + x1) / 2, (y0 + y1) / 2]; r = Math.max(x1 - x0 + 1, y1 - y0 + 1) / 2;
    }
    if (!isFinite(r) || !isFinite(c[0])) { return F; }
    var inside = 0;
    for (y = 0; y < hs; y++) { for (x = 0; x < ws; x++) { if (m[y * ws + x] && Math.hypot(x - c[0], y - c[1]) <= 0.995 * r) { inside++; } } }
    F.centre = [(c[0] + 0.5) / s - 0.5, (c[1] + 0.5) / s - 0.5];
    F.radius = r / s;
    F.coverage = inside / (Math.PI * r * r);
    F.ok = F.radius > 0.2 * Math.min(H, W) && F.coverage > 0.2;
    return F;
  }
  // netra.quality.standardize: aperture circle -> D x D canvas, 2 % margin
  function standardize(P, F, D) {
    var margin = 1.02, scale = D / (2 * F.radius * margin), half = F.radius * margin;
    var planes = [P.r, P.g, P.b], w = P.w, h = P.h, k = 1, cx = F.centre[0], cy = F.centre[1];
    if (scale < 1) {
      k = Math.max(1, Math.floor(1 / scale));
      if (k > 1) {
        planes = planes.map(function (pl) { return boxDown(pl, P.w, P.h, k).d; });
        w = Math.floor(P.w / k); h = Math.floor(P.h / k);
      }
      var sc = scale * k;
      if (sc < 0.999) { planes = planes.map(function (pl) { return gauss(pl, w, h, 0.45 / sc); }); }
    }
    var out = [new Float32Array(D * D), new Float32Array(D * D), new Float32Array(D * D)];
    var vis = new Uint8Array(D * D), inFrame = new Uint8Array(D * D), circle = new Uint8Array(D * D);
    var ctr = (D - 1) / 2, rad = F.radius * scale, fs = F.s;
    for (var j = 0; j < D; j++) {
      var yo = cy - half + (j + 0.5) / scale;             // original 0-based coordinates
      for (var i = 0; i < D; i++) {
        var xo = cx - half + (i + 0.5) / scale, p = j * D + i;
        if ((i - ctr) * (i - ctr) + (j - ctr) * (j - ctr) <= rad * rad) { circle[p] = 1; }
        if (xo < -0.5 || yo < -0.5 || xo > P.w - 0.5 || yo > P.h - 0.5) { continue; }
        inFrame[p] = 1;
        var xk = (xo + 0.5) / k - 0.5, yk = (yo + 0.5) / k - 0.5;
        var xa = Math.floor(clamp(xk, 0, w - 1)), ya = Math.floor(clamp(yk, 0, h - 1));
        var xb = Math.min(xa + 1, w - 1), yb = Math.min(ya + 1, h - 1), fx = clamp(xk - xa, 0, 1), fy = clamp(yk - ya, 0, 1);
        for (var c = 0; c < 3; c++) {
          var pl = planes[c];
          out[c][p] = clamp((1 - fy) * ((1 - fx) * pl[ya * w + xa] + fx * pl[ya * w + xb]) + fy * ((1 - fx) * pl[yb * w + xa] + fx * pl[yb * w + xb]), 0, 1);
        }
        var sxm = Math.min(Math.max(Math.floor((xo + 0.5) * fs), 0), F.ws - 1), sym = Math.min(Math.max(Math.floor((yo + 0.5) * fs), 0), F.hs - 1);
        vis[p] = F.small[sym * F.ws + sxm];
      }
    }
    var mask = new Uint8Array(D * D), nm = 0, nc = 0;
    for (p = 0; p < mask.length; p++) { mask[p] = vis[p] && circle[p] ? 1 : 0; nm += mask[p]; nc += circle[p]; }
    return { D: D, r: out[0], g: out[1], b: out[2], mask: mask, circle: circle, inFrame: inFrame,
      centre: [ctr, ctr], radius: rad, coverage: nm / Math.max(nc, 1) };
  }

  /* ========================================================= image quality */
  function assessCanvas(S, fovCoverage) {                // netra.quality.assess on a standardised canvas
    var q = CFG.quality, D = S.D, n = D * D, mask = new Uint8Array(n), inner = new Uint8Array(n), i, x, y;
    var L = new Float32Array(n), rr = new Float32Array(n);
    for (y = 0; y < D; y++) {
      for (x = 0; x < D; x++) {
        i = y * D + x;
        rr[i] = Math.hypot(x - S.centre[0], y - S.centre[1]) / S.radius;
        mask[i] = S.mask[i] && rr[i] <= 0.97 ? 1 : 0;
        inner[i] = mask[i] && rr[i] <= 0.90 ? 1 : 0;
        L[i] = 0.299 * S.r[i] + 0.587 * S.g[i] + 0.114 * S.b[i];
      }
    }
    var M = {};
    var BL = maskedSmooth(L, mask, D, D, 0.08 * D), blv = pick(BL, mask), medBL = median(blv);
    M.meanLuma = meanOf(L, mask);
    var dark = 0, bright = 0, nm = 0, darkLvl = Math.max(0.045, q.darkLevel * medBL);
    for (i = 0; i < n; i++) {
      if (!mask[i]) { continue; }
      nm++;
      if (BL[i] < darkLvl) { dark++; }
      if (S.g[i] >= q.saturation || L[i] >= 0.95) { bright++; }
    }
    M.darkFrac = dark / Math.max(nm, 1);
    M.brightFrac = bright / Math.max(nm, 1);
    var sbl = sortedCopy(blv), p10 = pctSorted(sbl, 10), p90 = pctSorted(sbl, 90);
    M.uniformity = 1 - (p90 - p10) / Math.max(p90 + p10, EPS);
    var BG = background(S.g, mask, D, D, CFG.enhance.backgroundDD * CFG.scale.ddPerFOV * 2 * S.radius);
    var gN = new Float32Array(n);
    for (i = 0; i < n; i++) { gN[i] = S.g[i] / BG[i]; }
    var g1 = gauss(gN, D, D, 1.0), dk = new Float32Array(n);
    for (i = 0; i < n; i++) { dk[i] = 1 - g1[i]; }
    var sdk = sortedCopy(pick(dk, mask));
    M.contrast = pctSorted(sdk, 97) - pctSorted(sdk, 50);
    var g2 = gauss(gN, D, D, 2.0), e1 = 0, e2 = 0;
    for (y = 1; y < D - 1; y++) {
      for (x = 1; x < D - 1; x++) {
        i = y * D + x;
        if (!inner[i]) { continue; }
        var l1 = g1[i - 1] + g1[i + 1] + g1[i - D] + g1[i + D] - 4 * g1[i], l2 = g2[i - 1] + g2[i + 1] + g2[i - D] + g2[i + D] - 4 * g2[i];
        e1 += l1 * l1; e2 += l2 * l2;
      }
    }
    var ratio = Math.sqrt(e1 / Math.max(e2, EPS));
    M.focusRatio = ratio;
    M.focusIndex = clamp((ratio - 1) / 1.4, 0, 1);
    M.noise = noiseSigma(gN, inner, D, D);
    var top = 0, topDark = 0, bot = 0, botDark = 0, ring = [], ringVals = [];
    for (y = 0; y < D; y++) {
      for (x = 0; x < D; x++) {
        i = y * D + x;
        if (!mask[i]) { continue; }
        var dy = y - S.centre[1];
        if (dy < -0.45 * S.radius) { top++; if (BL[i] < 0.45 * medBL) { topDark++; } }
        if (dy > 0.45 * S.radius) { bot++; if (BL[i] < 0.45 * medBL) { botDark++; } }
        if (rr[i] > 0.78) { ring.push(i); ringVals.push(BL[i]); }
      }
    }
    M.lashFrac = Math.max(top ? topDark / top : 0, bot ? botDark / bot : 0);
    if (ring.length) {
      var rmed = median(ringVals), fl = 0;
      for (i = 0; i < ringVals.length; i++) { if (ringVals[i] > 1.35 * rmed) { fl++; } }
      M.flareFrac = fl / ringVals.length;
    } else { M.flareFrac = 0; }
    var inF = 0, circ = 0, shadow = 0;
    for (i = 0; i < n; i++) {
      if (!S.circle[i]) { continue; }
      circ++;
      if (S.inFrame[i]) { inF++; if (!S.mask[i]) { shadow++; } }
    }
    M.frameCoverage = inF / Math.max(circ, 1);
    M.shadowFrac = shadow / Math.max(circ, 1);
    M.coverage = Math.min(fovCoverage, 1);

    var sub = {};
    sub.field = sigmoid(M.frameCoverage, q.minCoverage + 0.05, 0.05);
    var noiseTerm = sigmoid(q.noiseCenter - M.noise, 0, q.noiseWidth);
    sub.focus = sigmoid(M.focusIndex, q.focusCenter, q.focusWidth) * noiseTerm;
    var lumaTerm = sigmoid(M.meanLuma, q.lumaCenter, q.lumaWidth), darkTerm = sigmoid(q.darkMaxFrac - M.darkFrac, 0, 0.06),
      brightTerm = sigmoid(q.brightMaxFrac - M.brightFrac, 0, 0.02), unifTerm = sigmoid(M.uniformity, q.uniformityMin, q.uniformityWidth);
    sub.illumination = lumaTerm * darkTerm * brightTerm * unifTerm;
    sub.contrast = sigmoid(M.contrast, q.contrastCenter, q.contrastWidth);
    sub.artifact = sigmoid(0.18 - M.lashFrac, 0, 0.05) * sigmoid(0.10 - M.flareFrac, 0, 0.035) * sigmoid(q.shadowMax - M.shadowFrac, 0, 0.035);
    var num = 0, den = 0;
    Object.keys(q.weights).forEach(function (k) { num += q.weights[k] * Math.log(Math.max(sub[k], 1e-3)); den += q.weights[k]; });
    var score = Math.exp(num / den), worst = Math.min(sub.field, sub.focus, sub.illumination, sub.contrast, sub.artifact), decision;
    if (score >= q.gradable && worst >= q.minSubscore) { decision = 'GRADABLE'; }
    else if (score >= q.recapture && worst >= q.failSubscore) { decision = 'ENHANCE'; }
    else { decision = 'RECAPTURE'; }
    if (M.coverage < q.minCoverage) { decision = 'RECAPTURE'; }
    var fb = [];
    function add(key, sev) { fb.push({ key: key, severity: sev }); }
    if (sub.field < 0.5) { add('fb.field', 1 - sub.field); }
    if (sub.focus < 0.5) { add(noiseTerm < 0.5 && lumaTerm < 0.5 ? 'fb.dark' : 'fb.blur', 1 - sub.focus); }
    if (sub.illumination < 0.5) { add(brightTerm < Math.min(lumaTerm, darkTerm, unifTerm) ? 'fb.bright' : 'fb.dark', 1 - sub.illumination); }
    if (sub.contrast < 0.5) { add('fb.contrast', 1 - sub.contrast); }
    if (sub.artifact < 0.5) { add('fb.artifact', 1 - sub.artifact); }
    fb.sort(function (a, b) { return b.severity - a.severity; });
    var seen = {}, feedback = [];
    fb.forEach(function (f) { if (!seen[f.key]) { seen[f.key] = 1; feedback.push(f); } });
    return { score: score, decision: decision, worst: worst, sub: sub, metrics: M, feedback: feedback };
  }

  /* ========================================================== enhancement */
  var LIN = (function () {                               // sRGB decoding table, 4096 steps
    var t = new Float64Array(4097);
    for (var i = 0; i <= 4096; i++) { var c = i / 4096; t[i] = c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
    return t;
  })();
  function lin(c) { var p = clamp(c, 0, 1) * 4096, i = Math.floor(p); return i >= 4096 ? LIN[4096] : LIN[i] + (LIN[i + 1] - LIN[i]) * (p - i); }
  function rgb2lab(r, g, b) {                            // sRGB (D65) -> CIE Lab
    var R = lin(r), G = lin(g), B = lin(b);
    var X = (0.4124564 * R + 0.3575761 * G + 0.1804375 * B) / 0.95047, Y = 0.2126729 * R + 0.7151522 * G + 0.0721750 * B, Z = (0.0193339 * R + 0.1191920 * G + 0.9503041 * B) / 1.08883;
    function f(t) { return t > 0.008856451679 ? Math.cbrt(t) : 7.787037037 * t + 16 / 116; }
    var fx = f(X), fy = f(Y), fz = f(Z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }
  function clahe(Lp, w, h, tiles, clip) {                // adapthisteq(L, NumTiles, ClipLimit), uniform
    var nb = 256, th = Math.ceil(h / tiles), tw = Math.ceil(w / tiles), maps = [], i, x, y;
    for (var ty = 0; ty < tiles; ty++) {
      for (var tx = 0; tx < tiles; tx++) {
        var hist = new Float64Array(nb), npx = 0;
        for (y = ty * th; y < Math.min(h, (ty + 1) * th); y++) {
          for (x = tx * tw; x < Math.min(w, (tx + 1) * tw); x++) { hist[Math.min(nb - 1, Math.floor(clamp(Lp[y * w + x], 0, 1) * nb))]++; npx++; }
        }
        var minClip = Math.ceil(npx / nb), lim = minClip + Math.round(clip * (npx - minClip)), excess = 0;
        for (i = 0; i < nb; i++) { if (hist[i] > lim) { excess += hist[i] - lim; hist[i] = lim; } }
        var add = excess / nb, map = new Float32Array(nb), c = 0;
        for (i = 0; i < nb; i++) { hist[i] += add; }
        for (i = 0; i < nb; i++) { c += hist[i]; map[i] = npx ? c / npx : i / (nb - 1); }
        maps.push(map);
      }
    }
    var out = new Float32Array(w * h);
    for (y = 0; y < h; y++) {
      var gy = (y + 0.5) / th - 0.5, y0 = clamp(Math.floor(gy), 0, tiles - 1), y1 = Math.min(y0 + 1, tiles - 1), fy = clamp(gy - y0, 0, 1);
      for (x = 0; x < w; x++) {
        var gx = (x + 0.5) / tw - 0.5, x0 = clamp(Math.floor(gx), 0, tiles - 1), x1 = Math.min(x0 + 1, tiles - 1), fx = clamp(gx - x0, 0, 1);
        var bin = Math.min(nb - 1, Math.floor(clamp(Lp[y * w + x], 0, 1) * nb));
        out[y * w + x] = (1 - fy) * ((1 - fx) * maps[y0 * tiles + x0][bin] + fx * maps[y0 * tiles + x1][bin]) +
          fy * ((1 - fx) * maps[y1 * tiles + x0][bin] + fx * maps[y1 * tiles + x1][bin]);
      }
    }
    return out;
  }
  function enhance(S, Q) {                               // netra.quality.enhance
    var D = S.D, n = D * D, mask = S.mask, DDpx = CFG.scale.ddPerFOV * 2 * S.radius, sigmaBG = CFG.enhance.backgroundDD * DDpx, i;
    var near = edt(mask, D, D).idx;
    var rgb = [fillOutside(S.r, mask, D, D, 2, near), fillOutside(S.g, mask, D, D, 2, near), fillOutside(S.b, mask, D, D, 2, near)];
    var BG = background(rgb[1], mask, D, D, sigmaBG, near), ratio = new Float32Array(n);
    for (i = 0; i < n; i++) { ratio[i] = rgb[1][i] / BG[i]; }
    var noise = noiseSigma(ratio, mask, D, D), denoised = false;
    if (noise > 1.5 * CFG.quality.noiseHigh) {
      rgb = rgb.map(function (ch) { return gauss(ch, D, D, 0.8); });
      BG = background(rgb[1], mask, D, D, sigmaBG, near);
      denoised = true;
    }
    var target = CFG.enhance.targetRGB, rgbN = [], c;
    for (c = 0; c < 3; c++) {
      var Bk = c === 1 ? BG : background(rgb[c], mask, D, D, sigmaBG, near), plane = new Float32Array(n);
      for (i = 0; i < n; i++) { plane[i] = mask[i] ? Math.min(rgb[c][i] / Bk[i] * target[c], 1) : 0; }
      rgbN.push(plane);
    }
    var gN = new Float32Array(n);
    for (i = 0; i < n; i++) { gN[i] = mask[i] ? rgb[1][i] / BG[i] : 1; }
    var clip = CFG.enhance.claheClip;
    if (Q && Q.metrics && Q.metrics.contrast) { clip *= clamp(CFG.quality.contrastCenter * 2 / Math.max(Q.metrics.contrast, EPS), 0.6, 2.5); }
    var Lp = new Float32Array(n), Lab = new Float32Array(n * 3);
    for (i = 0; i < n; i++) {
      var lab = rgb2lab(rgbN[0][i], rgbN[1][i], rgbN[2][i]);
      Lab[3 * i] = lab[0]; Lab[3 * i + 1] = lab[1]; Lab[3 * i + 2] = lab[2];
      Lp[i] = clamp(lab[0] / 100, 0, 1);
    }
    var Lc = clahe(Lp, D, D, CFG.enhance.claheTiles, clip), display = new Uint8ClampedArray(n * 4);
    for (i = 0; i < n; i++) {
      var gain = Lp[i] > 1e-3 ? Lc[i] / Lp[i] : 1, a = mask[i] ? 1 : 0;
      display[4 * i] = 255 * clamp(rgbN[0][i] * gain, 0, 1) * a;
      display[4 * i + 1] = 255 * clamp(rgbN[1][i] * gain, 0, 1) * a;
      display[4 * i + 2] = 255 * clamp(rgbN[2][i] * gain, 0, 1) * a;
      display[4 * i + 3] = 255;
    }
    return { D: D, gN: gN, rgbN: rgbN, lab: Lab, display: display, noise: noise, denoised: denoised, mask: mask, clip: clip };
  }

  /* ================================================================ Hessian */
  function hessian(I, w, h, sigma, noTheta) {            // netra.anatomy.hessian
    var hh = Math.ceil(3 * sigma), n = 2 * hh + 1, g = new Float64Array(n), g1 = new Float64Array(n), g2 = new Float64Array(n), sum = 0, x;
    for (x = -hh; x <= hh; x++) { g[x + hh] = Math.exp(-x * x / (2 * sigma * sigma)); sum += g[x + hh]; }
    for (x = -hh; x <= hh; x++) {
      g[x + hh] /= sum;
      g1[x + hh] = -x / (sigma * sigma) * g[x + hh];
      g2[x + hh] = (x * x / Math.pow(sigma, 4) - 1 / (sigma * sigma)) * g[x + hh];
    }
    var s2 = sigma * sigma;
    var Hxx = sepFilter(I, w, h, g, g2), Hyy = sepFilter(I, w, h, g2, g), Hxy = sepFilter(I, w, h, g1, g1);
    var N = w * h, l1 = new Float32Array(N), l2 = new Float32Array(N), theta = noTheta ? null : new Float32Array(N);
    for (var i = 0; i < N; i++) {
      var a = s2 * Hxx[i], c = s2 * Hyy[i], b = s2 * Hxy[i], tmp = Math.sqrt((a - c) * (a - c) + 4 * b * b);
      var mu1 = 0.5 * (a + c + tmp), mu2 = 0.5 * (a + c - tmp);
      if (Math.abs(mu1) > Math.abs(mu2)) { l1[i] = mu2; l2[i] = mu1; } else { l1[i] = mu1; l2[i] = mu2; }
      if (theta) { theta[i] = 0.5 * Math.atan2(2 * b, a - c); }
    }
    return { l1: l1, l2: l2, theta: theta };
  }

  /* ================================================================ vessels */
  function vessels(E) {                                  // netra.anatomy.vessels
    var vc = CFG.vessels, D = E.D, Dv = mround(D * CFG.scale.vesselDiameter / (D / 1.02)), n = Dv * Dv, i, k;
    var g = imscale(E.gN, D, D, Dv, Dv), m = resizeNearest(E.mask, D, D, Dv, Dv), mIn = erodeDisk(m, Dv, Dv, 2);
    var c = new Float32Array(n);
    for (i = 0; i < n; i++) { c[i] = m[i] ? Math.max(1 - g[i], -0.2) : 0; }
    // Frangi vesselness, also the orientation map
    var best = new Float32Array(n), theta = new Float32Array(n);
    vc.hessianSigmas.forEach(function (s) {
      var H = hessian(c, Dv, Dv, s), mx = 0, S2 = new Float32Array(n);
      for (i = 0; i < n; i++) { S2[i] = H.l1[i] * H.l1[i] + H.l2[i] * H.l2[i]; if (mIn[i] && S2[i] > mx) { mx = S2[i]; } }
      var cc = vc.frangiC * Math.sqrt(mx), beta2 = 2 * vc.frangiBeta * vc.frangiBeta;
      for (i = 0; i < n; i++) {
        if (H.l2[i] >= 0) { continue; }
        var Rb = H.l1[i] / (H.l2[i] - EPS), v = Math.exp(-Rb * Rb / beta2) * (1 - Math.exp(-S2[i] / (2 * cc * cc + EPS)));
        if (v > best[i]) { best[i] = v; theta[i] = H.theta[i]; }
      }
    });
    function normalise(x) {
      var s = sortedCopy(pick(x, mIn)), p50 = pctSorted(s, 50), p99 = pctSorted(s, 99), out = new Float32Array(n), d = Math.max(p99 - p50, EPS);
      for (var j = 0; j < n; j++) { out[j] = clamp((x[j] - p50) / d, 0, 1.25) / 1.25; }
      return out;
    }
    function standardise(x) {
      var v = pick(x, m), mu = 0, sd = 0, j;
      for (j = 0; j < v.length; j++) { mu += v[j]; }
      mu /= Math.max(v.length, 1);
      for (j = 0; j < v.length; j++) { sd += (v[j] - mu) * (v[j] - mu); }
      sd = Math.max(Math.sqrt(sd / Math.max(v.length - 1, 1)), EPS);
      var out = new Float32Array(n);
      for (j = 0; j < n; j++) { out[j] = (x[j] - mu) / sd; }
      return out;
    }
    var hess = normalise(best);
    // multiscale line detector (Nguyen et al. 2013)
    var W = vc.lineWindow, avgW = boxMean(c, Dv, Dv, W), Ls = vc.lineScales, halfL = (Ls[Ls.length - 1] - 1) / 2, nAng = vc.lineAngles;
    var bestL = Ls.map(function () { return new Float32Array(n).fill(-Infinity); }), acc = new Float32Array(n);
    for (var a = 0; a < nAng; a++) {
      var ang = a * Math.PI / nAng;
      acc.set(c);
      for (var t = 1; t <= halfL; t++) {
        var dx = mround(t * Math.cos(ang)), dy = mround(-t * Math.sin(ang)), adx = Math.abs(dx);
        for (var y = 0; y < Dv; y++) {
          var ya = clamp(y - dy, 0, Dv - 1) * Dv, yb = clamp(y + dy, 0, Dv - 1) * Dv, row = y * Dv, x = 0;
          // replicated borders only matter within |dx| of the left/right edge
          for (; x < adx && x < Dv; x++) { acc[row + x] += c[ya + clamp(x - dx, 0, Dv - 1)] + c[yb + clamp(x + dx, 0, Dv - 1)]; }
          var xe = Dv - adx;
          for (; x < xe; x++) { acc[row + x] += c[ya + x - dx] + c[yb + x + dx]; }
          for (; x < Dv; x++) { acc[row + x] += c[ya + clamp(x - dx, 0, Dv - 1)] + c[yb + clamp(x + dx, 0, Dv - 1)]; }
        }
        var j = Ls.indexOf(2 * t + 1);
        if (j >= 0) { var bj = bestL[j], L = 2 * t + 1; for (i = 0; i < n; i++) { var av = acc[i] / L; if (av > bj[i]) { bj[i] = av; } } }
      }
    }
    var j1 = Ls.indexOf(1);
    if (j1 >= 0) { for (i = 0; i < n; i++) { if (c[i] > bestL[j1][i]) { bestL[j1][i] = c[i]; } } }
    var R = new Float32Array(n);
    for (k = 0; k < Ls.length; k++) {
      var r = new Float32Array(n);
      for (i = 0; i < n; i++) { r[i] = bestL[k][i] - avgW[i]; }
      var z = standardise(r);
      for (i = 0; i < n; i++) { R[i] += z[i]; }
    }
    var zc = standardise(c);
    for (i = 0; i < n; i++) { R[i] = (R[i] + zc[i]) / (Ls.length + 1); }
    var line = normalise(R);
    // morphological top-hat: supremum of linear openings (Zana & Klein)
    var tacc = new Float32Array(n), sups = vc.tophatLengths.map(function () { return new Float32Array(n); });
    for (var tdeg = 0; tdeg < 180; tdeg += 15) { lineOpenInto(c, Dv, Dv, vc.tophatLengths, tdeg, sups); }
    for (k = 0; k < sups.length; k++) { for (i = 0; i < n; i++) { tacc[i] += sups[k][i]; } }
    for (i = 0; i < n; i++) { tacc[i] /= vc.tophatLengths.length; }
    var top = normalise(tacc), P = new Float32Array(n), wv = vc.weights, wsum = wv.hessian + wv.line + wv.tophat;
    for (i = 0; i < n; i++) { P[i] = m[i] ? clamp((wv.hessian * hess[i] + wv.line * line[i] + wv.tophat * top[i]) / wsum, 0, 1) : 0; }
    // hysteresis threshold
    var sP = sortedCopy(pick(P, mIn)), tHigh = pctSorted(sP, 100 * (1 - vc.highFraction)), tLow = pctSorted(sP, 100 * (1 - vc.lowFraction));
    var strong = new Uint8Array(n), weak = new Uint8Array(n);
    for (i = 0; i < n; i++) { strong[i] = P[i] >= tHigh && m[i] ? 1 : 0; weak[i] = P[i] >= tLow && m[i] ? 1 : 0; }
    var B = reconstruct(strong, weak, Dv, Dv), DDv = CFG.scale.ddPerFOV * 2 * (Dv / 2 / 1.02);
    B = areaOpen(B, Dv, Dv, Math.max(4, mround(vc.minAreaDD2 * DDv * DDv)));
    var lab = label(B, Dv, Dv);
    lab.comps.forEach(function (pix) {
      var st = regionProps(pix, Dv);
      if (st.solidity > 0.70 && st.ecc < 0.95 && st.minor > 0.12 * DDv) { pix.forEach(function (p) { B[p] = 0; }); }
    });
    var skel = thin(B, Dv, Dv), bgB = new Uint8Array(n);
    for (i = 0; i < n; i++) { bgB[i] = B[i] ? 0 : 1; }
    var dist = edt(bgB, Dv, Dv).d2, width = new Float32Array(n);
    for (i = 0; i < n; i++) { width[i] = skel[i] ? 2 * Math.sqrt(dist[i]) - 1 : 0; }
    var thick = openDisk(B, Dv, Dv, Math.max(1, mround(0.5 * vc.thickWidthDD * DDv)));
    for (i = 0; i < n; i++) { thick[i] = thick[i] && B[i] ? 1 : 0; }
    label(thick, Dv, Dv).comps.forEach(function (pix) {
      if (regionProps(pix, Dv).major < 0.35 * DDv) { pix.forEach(function (p) { thick[p] = 0; }); }
    });
    var frac = count(B) / Math.max(count(m), 1);
    return {
      Dv: Dv, prob: P, mask: B, theta: theta, skeleton: skel, width: width, thick: thick, fraction: frac,
      maskWork: resizeMask(B, Dv, Dv, D, D), thickWork: resizeMask(thick, Dv, Dv, D, D), thetaWork: resizeNearest(theta, Dv, Dv, D, D)
    };
  }

  /* ============================================================ optic disc */
  function robustZ(x, valid) {
    var st = robustStats(pick(x, valid)), out = new Float32Array(x.length);
    for (var i = 0; i < x.length; i++) { out[i] = (x[i] - st[0]) / st[1]; }
    return out;
  }
  function opticDisc(E, V, S) {                          // netra.anatomy.opticDisc
    var D = E.D, Da = mround(CFG.scale.anatomyDiameter * 1.02), f = Da / D, DDprior = CFG.scale.ddPerFOV * 2 * S.radius, DDa = DDprior * f, n = Da * Da, i, x, y;
    var R = imscale(E.rgbN[0], D, D, Da, Da), G = imscale(E.rgbN[1], D, D, Da, Da), Bl = imscale(E.rgbN[2], D, D, Da, Da);
    var m = resizeNearest(E.mask, D, D, Da, Da), ca = [(S.centre[0] + 0.5) * f - 0.5, (S.centre[1] + 0.5) * f - 0.5], ra = S.radius * f;
    var valid = new Uint8Array(n), lum = new Float32Array(n);
    for (y = 0; y < Da; y++) { for (x = 0; x < Da; x++) { i = y * Da + x; valid[i] = m[i] && Math.hypot(x - ca[0], y - ca[1]) / ra <= CFG.od.maxRadiusFOV ? 1 : 0; lum[i] = 0.30 * R[i] + 0.59 * G[i] + 0.11 * Bl[i]; } }
    var lumF = fillOutside(lum, m, Da, Da, 2), s1m = smooth(lumF, Da, Da, DDa / 8), s2m = smooth(lumF, Da, Da, DDa), bright = new Float32Array(n);
    for (i = 0; i < n; i++) { bright[i] = s1m[i] - s2m[i]; }
    var vm = new Float32Array(V.mask.length), vt = new Float32Array(V.mask.length);
    for (i = 0; i < vm.length; i++) { vm[i] = V.mask[i]; vt[i] = V.thick[i]; }
    var vmask = resize(vm, V.Dv, V.Dv, Da, Da), vthick = resize(vt, V.Dv, V.Dv, Da, Da), th = resizeNearest(V.theta, V.Dv, V.Dv, Da, Da);
    var calibre = smooth(vthick, Da, Da, DDa / 3), vin = new Float32Array(n);
    for (i = 0; i < n; i++) { vin[i] = vmask[i] * Math.abs(Math.sin(th[i])); }
    var vertical = gauss2(vin, Da, Da, 0.55 * DDa, 0.12 * DDa), converge = convergence(V, Da, DDa);
    var zb = robustZ(bright, valid), zc = robustZ(calibre, valid), zv = robustZ(vertical, valid), zg = robustZ(converge, valid);
    var score = new Float32Array(n), best = -Infinity, bi = -1, co = CFG.od;
    for (y = 0; y < Da; y++) {
      for (x = 0; x < Da; x++) {
        i = y * Da + x;
        if (!valid[i]) { score[i] = -Infinity; continue; }
        var prior = -0.5 * Math.pow((y - ca[1]) / (0.45 * ra), 2), gate = sigmoid(zb[i], 0.5, 0.5);
        score[i] = co.wBrightness * Math.min(zb[i], 5) + gate * (co.wThickVessels * Math.min(zc[i], 5) + co.wVertical * Math.min(zv[i], 5) + co.wConvergence * Math.min(zg[i], 5)) + prior;
        if (score[i] > best) { best = score[i]; bi = i; }
      }
    }
    var y1 = (bi / Da) | 0, x1 = bi - y1 * Da, s2 = -Infinity;
    for (y = 0; y < Da; y++) { for (x = 0; x < Da; x++) { i = y * Da + x; if (valid[i] && Math.hypot(x - x1, y - y1) > 1.5 * DDa && score[i] > s2) { s2 = score[i]; } } }
    if (!isFinite(s2)) { s2 = best - 3; }
    var ref = refineDisc(lum, m, Da, [x1, y1], DDa), radiusPrior = DDa / 2, centreA, radiusA, measured;
    if (ref.ok && ref.r > (1 - CFG.scale.ddTolerance) * radiusPrior && ref.r < (1 + CFG.scale.ddTolerance) * radiusPrior && Math.hypot(ref.c[0] - x1, ref.c[1] - y1) < 0.6 * DDa) {
      centreA = ref.c; radiusA = ref.r; measured = true;
    } else { centreA = [x1, y1]; radiusA = radiusPrior; measured = false; }
    var conf = sigmoid(best - s2, 1.0, 0.5) * sigmoid(best, 6.0, 1.2);
    if (!measured) { conf *= 0.8; }
    var centre = [(centreA[0] + 0.5) / f - 0.5, (centreA[1] + 0.5) / f - 0.5], radius = radiusA / f, wgt = 0.7 * conf * (measured ? 1 : 0);
    return { centre: centre, radius: radius, pxPerDD: Math.exp(wgt * Math.log(2 * radius) + (1 - wgt) * Math.log(DDprior)), confidence: conf, measured: measured, score: best, margin: best - s2 };
  }
  function convergence(V, Da, DDa) {
    var Dv = V.Dv, DDv = DDa * Dv / Da, pts = [], i;
    for (i = 0; i < V.skeleton.length; i++) { if (V.skeleton[i] && V.width[i] >= 0.035 * DDv) { pts.push(i); } }
    var A = new Float32Array(Da * Da);
    if (pts.length < 10) { return A; }
    if (pts.length > 4000) {
      var keep = [];
      for (i = 0; i < 4000; i++) { keep.push(pts[mround(i * (pts.length - 1) / 3999)]); }
      pts = keep;
    }
    var f = Da / Dv, steps = 90;
    pts.forEach(function (p) {
      var yy = (p / Dv) | 0, xx = p - yy * Dv, th = V.theta[p], cx = (xx + 0.5) * f - 0.5, cy = (yy + 0.5) * f - 0.5, ct = Math.cos(th), st = Math.sin(th);
      for (var k = 0; k < steps; k++) {
        var t = -2.2 * DDa + k * 4.4 * DDa / (steps - 1), X = mround(cx + ct * t), Y = mround(cy + st * t);
        if (X >= 0 && Y >= 0 && X < Da && Y < Da) { A[Y * Da + X] += 1; }
      }
    });
    return smooth(A, Da, Da, 0.25 * DDa);
  }
  function refineDisc(lum, m, Da, p, DDa) {
    var half = mround(CFG.od.refineWindowDD * DDa / 2), r1 = Math.max(0, mround(p[1]) - half), r2 = Math.min(Da - 1, mround(p[1]) + half),
      c1 = Math.max(0, mround(p[0]) - half), c2 = Math.min(Da - 1, mround(p[0]) + half), ww = c2 - c1 + 1, wh = r2 - r1 + 1, n = ww * wh, i, x, y;
    var win = new Float32Array(n), mw = new Uint8Array(n);
    for (y = 0; y < wh; y++) { for (x = 0; x < ww; x++) { win[y * ww + x] = lum[(y + r1) * Da + x + c1]; mw[y * ww + x] = m[(y + r1) * Da + x + c1]; } }
    var fail = { ok: false, c: p, r: NaN };
    if (count(mw) < 0.5 * n) { return fail; }
    var closed = greyCloseDisk(win, ww, wh, Math.max(2, mround(0.12 * DDa)));
    closed = gauss(closed, ww, wh, Math.max(1, 0.04 * DDa));
    var v = pick(closed, mw), lo = Infinity, hi = -Infinity;
    v.forEach(function (a) { if (a < lo) { lo = a; } if (a > hi) { hi = a; } });
    if (hi - lo < EPS) { return fail; }
    var t = otsu(v.map(function (a) { return (a - lo) / (hi - lo); })) * (hi - lo) + lo, B = new Uint8Array(n);
    for (i = 0; i < n; i++) { B[i] = closed[i] > t && mw[i] ? 1 : 0; }
    B = openDisk(B, ww, wh, Math.max(1, mround(0.06 * DDa)));
    var L = label(B, ww, wh);
    if (!L.n) { return fail; }
    var px = clamp(mround(p[0]) - c1, 0, ww - 1), py = clamp(mround(p[1]) - r1, 0, wh - 1), k = L.lab[py * ww + px];
    if (!k) {
      var bestD = Infinity;
      L.comps.forEach(function (pix, idx) {
        var st = regionProps(pix, ww), d = Math.hypot(st.cx - px, st.cy - py);
        if (d < bestD) { bestD = d; k = idx + 1; }
      });
    }
    var blob = new Uint8Array(n);
    L.comps[k - 1].forEach(function (q) { blob[q] = 1; });
    blob = fillHoles(blob, ww, wh);
    var per = perimeter(blob, ww, wh), xs = [], ys = [], pix = [];
    for (i = 0; i < n; i++) { if (blob[i]) { pix.push(i); } if (per[i]) { ys.push((i / ww) | 0); xs.push(i % ww); } }
    if (xs.length < 12) { return fail; }
    var fit = circleFit(xs, ys);
    if (regionProps(pix, ww).solidity < 0.75) { return fail; }
    return { ok: isFinite(fit.r), c: [fit.c[0] + c1, fit.c[1] + r1], r: fit.r };
  }

  /* ================================================================= fovea */
  function fovea(E, V, OD, S) {                          // netra.anatomy.fovea
    var D = E.D, Da = mround(CFG.scale.anatomyDiameter * 1.02), f = Da / D, DDa = OD.pxPerDD * f, n = Da * Da, i, x, y, fc = CFG.fovea;
    var odA = [(OD.centre[0] + 0.5) * f - 0.5, (OD.centre[1] + 0.5) * f - 0.5], cA = [(S.centre[0] + 0.5) * f - 0.5, (S.centre[1] + 0.5) * f - 0.5];
    var G = imscale(E.rgbN[1], D, D, Da, Da), m = resizeNearest(E.mask, D, D, Da, Da), Gf = fillOutside(G, m, Da, Da, 2);
    var side = Math.sign(cA[0] - odA[0]) || 1, expected = [odA[0] + DDa * side * fc.distanceDD, odA[1] + DDa * fc.belowDD];
    if (OD.confidence < 0.35) { expected = cA.slice(); }
    // a grey-level closing erases dark structures narrower than ~0.35 DD
    // (vessels, haemorrhages) while the broad foveal depression survives
    var Gc = greyCloseDisk(Gf, Da, Da, Math.max(2, mround(0.18 * DDa)));
    var num = smooth(Gc, Da, Da, DDa / 4), den = smooth(Gf, Da, Da, 2 * DDa), dark = new Float32Array(n);
    for (i = 0; i < n; i++) { dark[i] = num[i] / Math.max(den[i], 1e-3); }
    var sk = new Float32Array(V.skeleton.length);
    for (i = 0; i < sk.length; i++) { sk[i] = V.skeleton[i]; }
    var vd = smooth(resize(sk, V.Dv, V.Dv, Da, Da), Da, Da, 0.3 * DDa);
    var dE = new Float32Array(n), search = new Uint8Array(n), ns = 0;
    for (y = 0; y < Da; y++) {
      for (x = 0; x < Da; x++) {
        i = y * Da + x;
        dE[i] = Math.hypot(x - expected[0], y - expected[1]) / DDa;
        search[i] = m[i] && dE[i] <= fc.searchRadiusDD && Math.hypot(x - odA[0], y - odA[1]) > 1.2 * DDa ? 1 : 0;
        ns += search[i];
      }
    }
    if (ns < 20) { for (i = 0; i < n; i++) { search[i] = m[i] && dE[i] <= 2 * fc.searchRadiusDD ? 1 : 0; } }
    var sd = robustStats(pick(dark, search)), sv = robustStats(pick(vd, search)), best = -Infinity, bi = -1;
    for (i = 0; i < n; i++) {
      if (!search[i]) { continue; }
      var sc = -(dark[i] - sd[0]) / sd[1] - 0.4 * (vd[i] - sv[0]) / Math.max(sv[1], 1e-3) - 0.5 * Math.pow(dE[i] / fc.priorSigmaDD, 2);
      if (sc > best) { best = sc; bi = i; }
    }
    if (bi < 0) { bi = mround(cA[1]) * Da + mround(cA[0]); }
    var fy = (bi / Da) | 0, fx = bi - fy * Da, ringSum = 0, ringN = 0;
    for (y = 0; y < Da; y++) {
      for (x = 0; x < Da; x++) {
        var dd = Math.hypot(x - fx, y - fy);
        if (m[y * Da + x] && dd > 0.6 * DDa && dd < 1.2 * DDa) { ringSum += dark[y * Da + x]; ringN++; }
      }
    }
    var depth = ringN ? ringSum / ringN - dark[bi] : 0, distDD = Math.hypot(fx - odA[0], fy - odA[1]) / DDa, consistent = distDD >= 1.8 && distDD <= 3.3;
    return { centre: [(fx + 0.5) / f - 0.5, (fy + 0.5) / f - 0.5], confidence: sigmoid(depth, 0.03, 0.012) * (0.4 + 0.6 * (consistent ? 1 : 0)),
      depth: depth, distanceDD: distDD, consistent: consistent };
  }

  /* ================================================================= frame */
  function frame(OD, FV, D) {                            // netra.anatomy.frame
    var F = { pxPerDD: OD.pxPerDD, umPerPx: CFG.scale.umPerDD / OD.pxPerDD, od: OD.centre, odRadius: OD.radius, fovea: FV.centre, D: D };
    var nasal = [OD.centre[0] - FV.centre[0], OD.centre[1] - FV.centre[1]], nn = Math.hypot(nasal[0], nasal[1]);
    nasal = nn < EPS ? [1, 0] : [nasal[0] / nn, nasal[1] / nn];
    var sup = [nasal[1], -nasal[0]];
    if (sup[1] > 0) { sup = [-sup[0], -sup[1]]; }
    F.nasal = nasal; F.superior = sup; F.eye = OD.centre[0] >= FV.centre[0] ? 'R' : 'L';
    var n = D * D, distF = new Float32Array(n), distD = new Float32Array(n), quad = new Uint8Array(n);
    for (var y = 0; y < D; y++) {
      for (var x = 0; x < D; x++) {
        var i = y * D + x, dx = x - FV.centre[0], dy = y - FV.centre[1];
        distF[i] = Math.hypot(dx, dy) / F.pxPerDD;
        distD[i] = Math.hypot(x - OD.centre[0], y - OD.centre[1]) / F.pxPerDD;
        var u = dx * nasal[0] + dy * nasal[1], v = dx * sup[0] + dy * sup[1];
        quad[i] = u < 0 ? (v >= 0 ? 1 : 4) : (v >= 0 ? 2 : 3);
      }
    }
    F.distFovea = distF; F.distDisc = distD; F.quadrant = quad;
    return F;
  }

  /* ======================================================== microaneurysms */
  function fitGaussian2D(P, pw, ph, init, Wt, sigmaMax, maxIter) {   // netra.lesions.fitGaussian2D (1-based patch coords)
    var xc = (pw + 1) / 2, yc = (ph + 1) / 2, xs = [], ys = [], ds = [], ws = [], i;
    for (var r = 0; r < ph; r++) {
      for (var c = 0; c < pw; c++) {
        if (Wt[r * pw + c] > 0) { xs.push(c + 1); ys.push(r + 1); ds.push(P[r * pw + c]); ws.push(Wt[r * pw + c]); }
      }
    }
    var border = [];
    for (c = 0; c < pw; c++) { border.push(P[c], P[(ph - 1) * pw + c]); }
    for (r = 0; r < ph; r++) { border.push(P[r * pw], P[r * pw + pw - 1]); }
    var th = [init[0], init[1], Math.max(init[2], 0.5), Math.max(init[3], 1e-3), median(border), 0, 0], x0i = [init[0], init[1]];
    function evaluate(t) {
      var n = xs.length, res = new Float64Array(n), J = new Array(n), s2 = t[2] * t[2];
      for (var k = 0; k < n; k++) {
        var dx = xs[k] - t[0], dy = ys[k] - t[1], g = Math.exp(-(dx * dx + dy * dy) / (2 * s2));
        res[k] = t[4] + t[5] * (xs[k] - xc) + t[6] * (ys[k] - yc) + t[3] * g - ds[k];
        J[k] = [t[3] * g * dx / s2, t[3] * g * dy / s2, t[3] * g * (dx * dx + dy * dy) / (s2 * t[2]), g, 1, xs[k] - xc, ys[k] - yc];
      }
      return { r: res, J: J };
    }
    function project(t) {
      var sh = [t[0] - x0i[0], t[1] - x0i[1]], nr = Math.hypot(sh[0], sh[1]);
      if (nr > 2.5) { t[0] = x0i[0] + sh[0] * 2.5 / nr; t[1] = x0i[1] + sh[1] * 2.5 / nr; }
      t[2] = clamp(t[2], 0.4, sigmaMax); t[3] = Math.max(t[3], 1e-4);
      return t;
    }
    function normal(ev) {
      var A = [], g = new Array(7).fill(0), a, b, k;
      for (a = 0; a < 7; a++) { A.push(new Array(7).fill(0)); }
      for (k = 0; k < xs.length; k++) {
        var Jk = ev.J[k], wk = ws[k];
        for (a = 0; a < 7; a++) { g[a] += Jk[a] * wk * ev.r[k]; for (b = a; b < 7; b++) { A[a][b] += Jk[a] * wk * Jk[b]; } }
      }
      for (a = 0; a < 7; a++) { for (b = 0; b < a; b++) { A[a][b] = A[b][a]; } }
      return { A: A, g: g };
    }
    function costOf(ev) { var s = 0; for (var k = 0; k < xs.length; k++) { s += ws[k] * ev.r[k] * ev.r[k]; } return s; }
    var ev = evaluate(th), cost = costOf(ev), lambda = 1e-2, it = 0;
    for (it = 1; it <= maxIter; it++) {
      var NE = normal(ev), maxD = 0, a;
      for (a = 0; a < 7; a++) { maxD = Math.max(maxD, NE.A[a][a]); }
      var Ad = NE.A.map(function (row) { return row.slice(); });
      for (a = 0; a < 7; a++) { Ad[a][a] += lambda * Math.max(NE.A[a][a], 1e-9 * maxD + 1e-12); }
      var step = solve(Ad, NE.g.map(function (v) { return -v; }));
      if (!step) { lambda *= 4; if (lambda > 1e7) { break; } continue; }
      var cand = project(th.map(function (v, idx) { return v + step[idx]; })), evc = evaluate(cand), cc = costOf(evc);
      if (cc < cost) {
        var rel = (cost - cc) / Math.max(cost, EPS);
        th = cand; ev = evc; cost = cc;
        lambda = Math.max(lambda / 3, 1e-7);
        if (rel < 1e-7 || Math.hypot(step[0], step[1], step[2]) < 1e-4) { break; }
      } else {
        lambda *= 4;
        if (lambda > 1e7) { break; }
      }
    }
    var nEff = ds.length, dof = Math.max(nEff - 7, 1), wsum = 0, dw = 0;
    for (i = 0; i < nEff; i++) { wsum += ws[i]; dw += ws[i] * ds[i]; }
    dw /= Math.max(wsum, EPS);
    var ssTot = 0;
    for (i = 0; i < nEff; i++) { ssTot += ws[i] * (ds[i] - dw) * (ds[i] - dw); }
    var resSigma = Math.sqrt(cost / Math.max(wsum, EPS) * nEff / dof), NEf = normal(ev), inv = invert(NEf.A), seXY = NaN;
    if (inv) { seXY = Math.sqrt(Math.max(resSigma * resSigma * (inv[0][0] + inv[1][1]), 0) / 2); }
    return { x0: th[0], y0: th[1], s: th[2], a: th[3], b: [th[4], th[5], th[6]], r2: 1 - cost / Math.max(ssTot, EPS),
      resSigma: resSigma, seXY: seXY, crlb: Math.sqrt(2 / Math.PI) * resSigma / Math.max(th[3], EPS) };
  }
  function bilinear(I, w, h, x, y, fill) {               // netra.util.bilinear with 0-based coords
    var x0 = Math.floor(x), y0 = Math.floor(y);
    if (x0 < 0 || y0 < 0 || x0 >= w - 1 || y0 >= h - 1) { return fill; }
    var fx = x - x0, fy = y - y0, i = y0 * w + x0;
    return (1 - fx) * (1 - fy) * I[i] + fx * (1 - fy) * I[i + 1] + (1 - fx) * fy * I[i + w] + fx * fy * I[i + w + 1];
  }
  function microaneurysms(E, V, F) {                     // netra.lesions.microaneurysms
    var mc = CFG.ma, D = E.D, n = D * D, DD = F.pxPerDD, umPx = F.umPerPx, i, x, y, k;
    var d0 = new Float32Array(n);
    for (i = 0; i < n; i++) { d0[i] = E.mask[i] ? 1 - E.gN[i] : 0; }
    var d = gauss(d0, D, D, 0.5);
    var len = 2 * Math.floor(mc.openingDD * DD / 2) + 1, sup = new Float32Array(n);
    for (var deg = 0; deg < 179.99; deg += 180 / mc.openingAngles) { lineOpenInto(d, D, D, [len], deg, [sup]); }
    var r = new Float32Array(n);
    for (i = 0; i < n; i++) { r[i] = Math.max(d[i] - sup[i], 0); }
    var sig = mc.sigmaUm.map(function (s) { return s / umPx; }).filter(function (s) { return s >= 0.6 && s <= 0.12 * DD; });
    if (!sig.length) { sig = [1]; }
    var B = new Float32Array(n), S = new Float32Array(n).fill(1), Rnd = new Float32Array(n), half = null;
    sig.forEach(function (s) {
      var resp, ratio, j;
      if (s > 2.5 && D % 2 === 0) {
        // coarse scales on a half-resolution level: scale-normalised Hessian
        // responses are resolution-independent, and the Gaussian fit below
        // re-localises every candidate at full resolution
        if (!half) { half = boxDown(r, D, D, 2).d; }
        var Hh = hessian(half, D / 2, D / 2, s / 2, true), rh = new Float32Array(Hh.l1.length), qh = new Float32Array(Hh.l1.length);
        for (j = 0; j < rh.length; j++) { rh[j] = -(Hh.l1[j] + Hh.l2[j]); qh[j] = Hh.l1[j] / Math.min(Hh.l2[j], -EPS); }
        resp = resize(rh, D / 2, D / 2, D, D); ratio = resize(qh, D / 2, D / 2, D, D);
      } else {
        var H = hessian(r, D, D, s, true);
        resp = new Float32Array(n); ratio = new Float32Array(n);
        for (j = 0; j < n; j++) { resp[j] = -(H.l1[j] + H.l2[j]); ratio[j] = H.l1[j] / Math.min(H.l2[j], -EPS); }
      }
      for (j = 0; j < n; j++) { if (resp[j] > B[j]) { B[j] = resp[j]; S[j] = s; Rnd[j] = ratio[j]; } }
    });
    var inner = maskErode(E, Math.max(2, mround(0.08 * DD))), valid = new Uint8Array(n);
    for (i = 0; i < n; i++) { valid[i] = E.mask[i] && F.distDisc[i] > 0.6 && !V.thickWork[i] && inner[i] ? 1 : 0; }
    var st = robustStats(pick(B, valid)), rs = Math.max(st[1], 0.35 * Math.max(E.noise, 1e-3)), bmin = Math.max(0.5 * mc.minContrast, 0.3 * mc.minAmplitude), cand = [];
    for (y = 1; y < D - 1; y++) {
      for (x = 1; x < D - 1; x++) {
        i = y * D + x;
        if (!valid[i] || B[i] <= bmin || (B[i] - st[0]) / rs <= mc.thresholdK) { continue; }
        var v = B[i], peak = true;
        for (var dy = -1; dy <= 1 && peak; dy++) { for (var dx = -1; dx <= 1; dx++) { if ((dx || dy) && B[i + dy * D + dx] > v) { peak = false; break; } } }
        if (peak) { cand.push(i); }
      }
    }
    cand.sort(function (a, b) { return B[b] - B[a]; });
    cand = cand.slice(0, mc.maxCandidates);
    var vmask = V.maskWork, noiseD = Math.max(E.noise, 1e-3), taken = new Uint8Array(n), list = [], t = CFG.enhance.targetRGB;
    cand.forEach(function (idx) {
      if (taken[idx]) { return; }
      var py = (idx / D) | 0, px = idx - py * D, s0 = S[idx], rad = Math.ceil(mc.fitRadius * s0 + 2);
      var r1 = py - rad, r2 = py + rad, c1 = px - rad, c2 = px + rad;
      if (r1 < 0 || c1 < 0 || r2 >= D || c2 >= D) { return; }
      var pw = c2 - c1 + 1, ph = r2 - r1 + 1, P = new Float32Array(pw * ph), W = new Float32Array(pw * ph);
      for (var yy = 0; yy < ph; yy++) {
        for (var xx = 0; xx < pw; xx++) {
          var q = (yy + r1) * D + xx + c1;
          P[yy * pw + xx] = d[q];
          W[yy * pw + xx] = vmask[q] && Math.hypot(xx + c1 - px, yy + r1 - py) > 1.5 * s0 + 1 ? 0 : 1;
        }
      }
      // separable parabola through the 3 x 3 maximum of the blob response
      var dxq = (B[idx + 1] - B[idx - 1]) / 2, dxx = B[idx + 1] - 2 * B[idx] + B[idx - 1], dyq = (B[idx + D] - B[idx - D]) / 2, dyy = B[idx + D] - 2 * B[idx] + B[idx - D];
      var ox = dxx < 0 ? clamp(-dxq / dxx, -0.5, 0.5) : 0, oy = dyy < 0 ? clamp(-dyq / dyy, -0.5, 0.5) : 0;
      var fit = fitGaussian2D(P, pw, ph, [rad + 1 + ox, rad + 1 + oy, s0, Math.max(r[idx], 0.01)], W, 0.15 * DD, mc.maxIter);
      var ex = c1 + fit.x0 - 1, ey = r1 + fit.y0 - 1;          // 0-based canvas coordinates
      if (ex < 0 || ey < 0 || ex > D - 1 || ey > D - 1) { return; }
      var xi = clamp(mround(ex), 0, D - 1), yi = clamp(mround(ey), 0, D - 1), e = { x: ex, y: ey, sigmaPx: fit.s };
      e.diameterUm = 2.3548 * fit.s * umPx;
      e.amplitude = fit.a;
      e.snr = fit.a / Math.max(noiseD, fit.resSigma, localTexture(d, vmask, D, xi, yi, fit.s));
      e.r2 = fit.r2;
      e.roundness = Rnd[idx];
      e.seXY = fit.seXY;
      e.crlb = fit.crlb;
      e.onVessel = onVessel(vmask, D, xi, yi, 2.3548 * fit.s);
      e.exitRatio = exitRatio(d, D, ex, ey, fit.s, fit.a, fit.b[0]);
      e.redness = redness(E.rgbN, D, xi, yi, Math.max(1, mround(fit.s)), t);
      e.quadrant = F.quadrant[yi * D + xi];
      e.distFoveaDD = F.distFovea[yi * D + xi];
      e.prob = maScore(e, mc);
      e.cls = e.diameterUm > mc.maxMAUm ? 'dot' : 'MA';
      list.push(e);
      var rr = Math.max(1, mround(1.5 * fit.s));
      for (yy = Math.max(0, yi - rr); yy <= Math.min(D - 1, yi + rr); yy++) { for (xx = Math.max(0, xi - rr); xx <= Math.min(D - 1, xi + rr); xx++) { taken[yy * D + xx] = 1; } }
    });
    return { list: list, candidates: cand.length };
  }
  function localTexture(d, vmask, D, x, y, s) {
    var R = Math.max(6, Math.ceil(5 * s)), v = [];
    for (var yy = Math.max(0, y - R); yy <= Math.min(D - 1, y + R); yy++) {
      for (var xx = Math.max(0, x - R); xx <= Math.min(D - 1, x + R); xx++) {
        var dist = Math.hypot(xx - x, yy - y);
        if (dist >= Math.max(2.5 * s, 3) && dist <= R && !vmask[yy * D + xx]) { v.push(d[yy * D + xx]); }
      }
    }
    return v.length < 10 ? 0 : robustStats(v)[1];
  }
  function exitRatio(d, D, x, y, s, a, base) {
    var prof = new Float64Array(32), rads = [Math.max(2.5 * s, 2.5), Math.max(3.25 * s, 3.5), Math.max(4 * s, 4.5)], k;
    for (k = 0; k < 32; k++) {
      var ang = k * 2 * Math.PI / 32, sum = 0;
      rads.forEach(function (rr) { sum += bilinear(d, D, D, x + rr * Math.cos(ang), y + rr * Math.sin(ang), base); });
      prof[k] = sum / rads.length;
    }
    var sm = new Float64Array(32);
    for (k = 0; k < 32; k++) { sm[k] = (prof[k] + prof[(k + 31) % 32] + prof[(k + 1) % 32]) / 3; }
    var mx = -Infinity;
    for (k = 0; k < 32; k++) { mx = Math.max(mx, sm[k]); }
    return (mx - median(Array.from(sm))) / Math.max(a, EPS);
  }
  function onVessel(vmask, D, x, y, fwhm) {
    if (!vmask[y * D + x]) { return false; }
    var R = Math.max(3, Math.ceil(3 * fwhm)), on = 0, all = 0;
    for (var yy = Math.max(0, y - R); yy <= Math.min(D - 1, y + R); yy++) {
      for (var xx = Math.max(0, x - R); xx <= Math.min(D - 1, x + R); xx++) {
        var dist = Math.hypot(xx - x, yy - y);
        if (dist >= Math.max(1.5 * fwhm, 2) && dist <= R) { all++; on += vmask[yy * D + xx]; }
      }
    }
    return all > 0 && on / all > 0.2;
  }
  function redness(rgbN, D, x, y, rad, t) {
    function meanBox(pl, r1, r2, c1, c2) { var s = 0, n = 0; for (var yy = r1; yy <= r2; yy++) { for (var xx = c1; xx <= c2; xx++) { s += pl[yy * D + xx]; n++; } } return s / n; }
    function medBox(pl, r1, r2, c1, c2) { var v = []; for (var yy = r1; yy <= r2; yy++) { for (var xx = c1; xx <= c2; xx++) { v.push(pl[yy * D + xx]); } } return median(v); }
    var r1 = Math.max(0, y - rad), r2 = Math.min(D - 1, y + rad), c1 = Math.max(0, x - rad), c2 = Math.min(D - 1, x + rad);
    var R1 = Math.max(0, y - 4 * rad - 3), R2 = Math.min(D - 1, y + 4 * rad + 3), C1 = Math.max(0, x - 4 * rad - 3), C2 = Math.min(D - 1, x + 4 * rad + 3);
    var inR = meanBox(rgbN[0], r1, r2, c1, c2) / t[0], inG = meanBox(rgbN[1], r1, r2, c1, c2) / t[1];
    var bgR = medBox(rgbN[0], R1, R2, C1, C2) / t[0], bgG = medBox(rgbN[1], R1, R2, C1, C2) / t[1];
    return Math.min(Math.max(bgR - inR, 0) / Math.max(bgG - inG, 1e-3), 2);
  }
  function maScore(e, m) {
    var sizeTerm = 1;
    if (e.diameterUm < m.minUm) { sizeTerm = Math.exp(-Math.pow((m.minUm - e.diameterUm) / 10, 2)); }
    else if (e.diameterUm > m.maxDotUm) { sizeTerm = Math.exp(-Math.pow((e.diameterUm - m.maxDotUm) / 40, 2)); }
    var p = sigmoid(e.snr, m.minSNR + 1, 0.8) * sigmoid(e.r2, m.minR2 + 0.05, 0.08) * sizeTerm * sigmoid(e.roundness, m.minRoundness, 0.07) *
      sigmoid(0.8 - e.redness, 0, 0.12) * sigmoid(e.amplitude, m.minAmplitude, 0.012) * sigmoid(m.maxExit - e.exitRatio, 0, 0.06);
    return e.onVessel ? 0.7 * p : p;
  }

  /* ========================================================== haemorrhages */
  function foveaCompensate(d, F, mask, D) {              // netra.lesions.foveaCompensate
    var nb = 32, rings = [], k, i;
    for (k = 0; k < nb; k++) { rings.push([]); }
    var outer = [];
    for (i = 0; i < d.length; i++) {
      if (!mask[i]) { continue; }
      var r = F.distFovea[i];
      if (r < 1.6) { rings[Math.min(Math.floor(r / 0.05), nb - 1)].push(d[i]); }
      else if (r < 2.0) { outer.push(d[i]); }
    }
    var base = outer.length ? median(outer) : 0, prof = new Float64Array(nb);
    for (k = 0; k < nb; k++) { prof[k] = rings[k].length >= 8 ? Math.max(median(rings[k]) - base, 0) : Math.max(0 - base, 0); }
    var sm = new Float64Array(nb);
    for (k = 0; k < nb; k++) {
      var s = 0, c = 0;
      for (var j = Math.max(0, k - 1); j <= Math.min(nb - 1, k + 1); j++) { s += prof[j]; c++; }
      sm[k] = s / c;
    }
    var out = Float32Array.from(d);
    for (i = 0; i < d.length; i++) {
      if (!mask[i] || F.distFovea[i] >= 1.6) { continue; }
      var pos = clamp(F.distFovea[i], 0.025, 1.575) / 0.05 - 0.5, a = Math.floor(pos), b = Math.min(a + 1, nb - 1), w = pos - a;
      out[i] = d[i] - (sm[a] * (1 - w) + sm[b] * w);
    }
    return out;
  }
  function hemorrhages(E, V, F, MA) {                    // netra.lesions.hemorrhages
    var hc = CFG.he, D = E.D, n = D * D, DD = F.pxPerDD, umPx = F.umPerPx, i;
    var inner = maskErode(E, Math.max(2, mround(0.06 * DD))), mask = new Uint8Array(n);
    for (i = 0; i < n; i++) { mask[i] = E.mask[i] && F.distDisc[i] > 0.65 && inner[i] ? 1 : 0; }
    var d0 = new Float32Array(n);
    for (i = 0; i < n; i++) { d0[i] = E.mask[i] ? 1 - E.gN[i] : 0; }
    var d = foveaCompensate(gauss(d0, D, D, 0.7), F, E.mask, D), bgv = [];
    for (i = 0; i < n; i++) { if (mask[i] && !V.maskWork[i]) { bgv.push(d[i]); } }
    var st = robustStats(bgv), T = Math.max(hc.minDarkening, st[0] + hc.thresholdK * st[1]), C = new Uint8Array(n);
    for (i = 0; i < n; i++) { C[i] = d[i] > T && mask[i] ? 1 : 0; }
    var rOpen = Math.max(1, mround(hc.openRadiusUm / umPx));
    C = openDisk(C, D, D, rOpen);
    var thickD = dilate3(V.thickWork, D, D);
    for (i = 0; i < n; i++) { if (thickD[i]) { C[i] = 0; } }
    C = openDisk(C, D, D, Math.max(1, rOpen - 1));
    C = areaOpen(C, D, D, Math.max(6, mround(Math.PI / 4 * Math.pow(Math.sqrt(hc.minAreaUm2) / umPx, 2) * 0.8)));
    var L = label(C, D, D), DA = Math.PI / 4 * DD * DD, t = CFG.enhance.targetRGB, list = [];
    L.comps.forEach(function (pix, ci) {
      var p = regionProps(pix, D), e = { x: p.cx, y: p.cy, pix: pix };
      e.areaPx = p.area; e.areaDA = p.area / DA; e.eqDiamUm = 2 * Math.sqrt(p.area / Math.PI) * umPx; e.majorUm = p.major * umPx;
      e.ecc = p.ecc; e.solidity = p.solidity;
      var mu20 = 0, mu02 = 0, mu11 = 0, contrast = 0, sR = 0, sG = 0;
      pix.forEach(function (q) {
        var y = (q / D) | 0, x = q - y * D;
        mu20 += (x - p.cx) * (x - p.cx); mu02 += (y - p.cy) * (y - p.cy); mu11 += (x - p.cx) * (y - p.cy);
        contrast += d[q]; sR += E.rgbN[0][q] / t[0]; sG += E.rgbN[1][q] / t[1];
      });
      var theta = 0.5 * Math.atan2(2 * mu11 / pix.length, (mu20 - mu02) / pix.length), radial = Math.atan2(p.cy - F.od[1], p.cx - F.od[0]);
      e.alignment = Math.abs(Math.cos(theta - radial));
      e.contrast = contrast / pix.length;
      var ring = ringPixels(L.lab, ci + 1, pix, D), rv = [], gv = [];
      ring.forEach(function (q) { rv.push(E.rgbN[0][q] / t[0]); gv.push(E.rgbN[1][q] / t[1]); });
      var dR = Math.max(median(rv) - sR / pix.length, 0), dG = Math.max(median(gv) - sG / pix.length, 1e-3);
      e.redness = Math.min(dR / dG, 2);
      var yi = clamp(mround(p.cy), 0, D - 1), xi = clamp(mround(p.cx), 0, D - 1);
      e.quadrant = F.quadrant[yi * D + xi]; e.distFoveaDD = F.distFovea[yi * D + xi];
      if (e.areaDA >= hc.preretinalDA && e.contrast > 0.25) { e.type = 'preretinal'; }
      else if (e.ecc >= hc.flameEcc && e.alignment >= hc.flameAlign && e.majorUm >= hc.flameMinLenUm) { e.type = 'flame'; }
      else if (e.eqDiamUm <= 250 && e.ecc < 0.85) { e.type = 'dot'; }
      else { e.type = 'blot'; }
      e.prob = sigmoid((e.contrast - T) / Math.max(st[1], 1e-3), 1.5, 0.8) * sigmoid(0.85 - e.redness, 0, 0.12) * sigmoid(e.solidity, 0.45, 0.08);
      list.push(e);
    });
    MA.list.forEach(function (m) {
      if (m.cls !== 'dot' || m.prob < 0.5) { return; }
      var yi = clamp(mround(m.y), 0, D - 1), xi = clamp(mround(m.x), 0, D - 1);
      if (L.lab[yi * D + xi]) { return; }
      var area = Math.PI * Math.pow(1.1774 * m.sigmaPx, 2);
      list.push({ x: m.x, y: m.y, areaPx: area, areaDA: area / DA, eqDiamUm: m.diameterUm, majorUm: m.diameterUm, ecc: 0, solidity: 1, alignment: 0,
        contrast: m.amplitude, redness: m.redness, quadrant: m.quadrant, distFoveaDD: m.distFoveaDD, type: 'dot', prob: m.prob, radius: 1.1774 * m.sigmaPx });
    });
    var counts = { dot: 0, blot: 0, flame: 0, preretinal: 0 }, perQuadrant = [0, 0, 0, 0];
    list.forEach(function (e) {
      if (e.prob < 0.5) { return; }
      counts[e.type]++;
      if (e.type !== 'preretinal' && e.quadrant > 0) { perQuadrant[e.quadrant - 1]++; }
    });
    return { list: list, threshold: T, counts: counts, perQuadrant: perQuadrant, mask: C };
  }
  function ringPixels(lab, k, pix, D) {                  // 3-px band around one component
    var y0 = Infinity, y1 = -Infinity, x0 = Infinity, x1 = -Infinity;   // bounding box (no apply: components can be huge)
    pix.forEach(function (q) { var yy = (q / D) | 0, xx = q - yy * D; if (yy < y0) { y0 = yy; } if (yy > y1) { y1 = yy; } if (xx < x0) { x0 = xx; } if (xx > x1) { x1 = xx; } });
    var pad = 6, r1 = Math.max(0, y0 - pad), r2 = Math.min(D - 1, y1 + pad),
      c1 = Math.max(0, x0 - pad), c2 = Math.min(D - 1, x1 + pad), ww = c2 - c1 + 1, wh = r2 - r1 + 1;
    var sub = new Uint8Array(ww * wh);
    pix.forEach(function (q) { var y = ((q / D) | 0) - r1, x = (q % D) - c1; sub[y * ww + x] = 1; });
    var outer = dilateDisk(sub, ww, wh, 4), innerB = dilateDisk(sub, ww, wh, 1), ring = [];
    for (var y = 0; y < wh; y++) {
      for (var x = 0; x < ww; x++) {
        var i = y * ww + x, q = (y + r1) * D + x + c1;
        if (outer[i] && !innerB[i] && lab[q] === 0) { ring.push(q); }
      }
    }
    return ring.length ? ring : pix;
  }

  /* ===================================================== exudates and CWS */
  function exudates(E, V, F) {                           // netra.lesions.exudates
    var xc = CFG.ex, D = E.D, n = D * D, DD = F.pxPerDD, i;
    var inner = maskErode(E, Math.max(2, mround(0.08 * DD))), mask = new Uint8Array(n);
    for (i = 0; i < n; i++) { mask[i] = E.mask[i] && F.distDisc[i] * DD > xc.odExclusion * F.odRadius && inner[i] ? 1 : 0; }
    var vess = dilate3(V.maskWork, D, D), b0 = new Float32Array(n);
    for (i = 0; i < n; i++) { b0[i] = E.mask[i] ? E.gN[i] - 1 : 0; }
    var b = gauss(b0, D, D, 0.7), bgv = [];
    for (i = 0; i < n; i++) { if (mask[i] && !vess[i]) { bgv.push(b[i]); } }
    var st = robustStats(bgv), T = Math.max(xc.minBrightening, st[0] + xc.thresholdK * st[1]), strong = new Uint8Array(n), weak = new Uint8Array(n);
    for (i = 0; i < n; i++) {
      var ok = mask[i] && !vess[i];
      strong[i] = ok && b[i] > 1.5 * T ? 1 : 0;
      weak[i] = ok && b[i] > T ? 1 : 0;
    }
    var C = areaOpen(reconstruct(strong, weak, D, D), D, D, 3);
    var tr = edt(V.maskWork, D, D), bstarBgV = [];
    for (i = 0; i < n; i++) { if (mask[i] && !vess[i] && !C[i]) { bstarBgV.push(E.lab[3 * i + 2]); } }
    var bstarBg = median(bstarBgV), gs = gauss(E.gN, D, D, 0.8), per = perimeter(C, D, D);
    function gmag(q) {
      var y = (q / D) | 0, x = q - y * D;
      var gx = x === 0 ? gs[q + 1] - gs[q] : x === D - 1 ? gs[q] - gs[q - 1] : (gs[q + 1] - gs[q - 1]) / 2;
      var gy = y === 0 ? gs[q + D] - gs[q] : y === D - 1 ? gs[q] - gs[q - D] : (gs[q + D] - gs[q - D]) / 2;
      return Math.hypot(gx, gy);
    }
    var ex = [], cws = [];
    label(C, D, D).comps.forEach(function (pix) {
      var p = regionProps(pix, D), e = { x: p.cx, y: p.cy, pix: pix, areaPx: p.area, eqDiamDD: 2 * Math.sqrt(p.area / Math.PI) / DD };
      var contrast = 0, yel = 0, gsum = 0, gn = 0, mu20 = 0, mu02 = 0, mu11 = 0, minD = Infinity;
      pix.forEach(function (q) {
        var y = (q / D) | 0, x = q - y * D;
        contrast += b[q]; yel += E.lab[3 * q + 2];
        if (per[q]) { gsum += gmag(q); gn++; }
        mu20 += (x - p.cx) * (x - p.cx); mu02 += (y - p.cy) * (y - p.cy); mu11 += (x - p.cx) * (y - p.cy);
        minD = Math.min(minD, Math.hypot(x - F.fovea[0], y - F.fovea[1]));
      });
      e.contrast = contrast / pix.length;
      if (!gn) { pix.forEach(function (q) { gsum += gmag(q); }); gn = pix.length; }
      e.sharpness = gsum / gn / Math.max(e.contrast, EPS);
      e.yellowness = yel / pix.length - bstarBg;
      e.ecc = p.ecc;
      var thinPiece = p.ecc > 0.97 && p.minor < 0.03 * DD;
      var th = 0.5 * Math.atan2(2 * mu11 / pix.length, (mu20 - mu02) / pix.length), ci = clamp(mround(p.cy), 0, D - 1) * D + clamp(mround(p.cx), 0, D - 1);
      var parallel = Math.abs(Math.cos(th - V.thetaWork[tr.idx[ci]])) > 0.9, reflex = p.ecc > 0.85 && parallel && Math.sqrt(tr.d2[ci]) < 0.12 * DD;
      var yi = clamp(mround(e.y), 0, D - 1), xi = clamp(mround(e.x), 0, D - 1);
      e.quadrant = F.quadrant[yi * D + xi];
      e.distFoveaDD = minD / DD;
      if (thinPiece || reflex) { return; }
      var isCWS = e.eqDiamDD >= xc.cwsMinDD && e.eqDiamDD <= xc.cwsMaxDD && e.sharpness < xc.sharpEdge && e.yellowness < 2 * xc.minYellow &&
        e.ecc < xc.cwsMaxEcc && p.solidity >= xc.cwsMinSolidity;
      if (isCWS) {
        e.type = 'CWS';
        e.prob = sigmoid(e.contrast, T, 0.25 * T) * sigmoid(xc.sharpEdge - e.sharpness, 0, 0.08);
        cws.push(e);
      } else if (e.yellowness >= xc.minYellow || e.sharpness >= xc.sharpEdge) {
        e.type = 'EX';
        e.prob = sigmoid(e.contrast, T, 0.25 * T) * Math.max(sigmoid(e.yellowness, xc.minYellow, 1.0), sigmoid(e.sharpness, xc.sharpEdge, 0.08));
        ex.push(e);
      }
    });
    var good = ex.filter(function (e) { return e.prob >= 0.5; }), out = { list: ex, cws: cws, threshold: T, count: good.length,
      cwsCount: cws.filter(function (e) { return e.prob >= 0.5; }).length };
    if (!good.length) { out.minDistFoveaDD = Infinity; out.areaDD2 = 0; out.dme = 0; out.centreInvolved = false; }
    else {
      out.minDistFoveaDD = good.reduce(function (m, e) { return Math.min(m, e.distFoveaDD); }, Infinity);
      out.areaDD2 = good.reduce(function (s, e) { return s + e.areaPx; }, 0) / (DD * DD);
      out.dme = 1 + (out.minDistFoveaDD <= xc.dmeRadiusDD ? 1 : 0);
      out.centreInvolved = out.minDistFoveaDD <= xc.centreRadiusDD;
    }
    return out;
  }

  /* ===================================================== neovascularisation */
  function boxMean0(src, w, h, win) {                    // netra.util.boxMean: win x win mean, zero padding, 'same'
    var r = (win - 1) >> 1, tmp = new Float32Array(w * h), out = new Float32Array(w * h), x, y, s, inv = 1 / (win * win);
    for (y = 0; y < h; y++) {
      var o = y * w;
      s = 0;
      for (x = 0; x <= r && x < w; x++) { s += src[o + x]; }
      for (x = 0; x < w; x++) {
        tmp[o + x] = s;
        if (x + r + 1 < w) { s += src[o + x + r + 1]; }
        if (x - r >= 0) { s -= src[o + x - r]; }
      }
    }
    var col = new Float64Array(w);
    for (y = 0; y <= r && y < h; y++) { for (x = 0; x < w; x++) { col[x] += tmp[y * w + x]; } }
    for (y = 0; y < h; y++) {
      var oy = y * w;
      for (x = 0; x < w; x++) { out[oy + x] = col[x] * inv; }
      if (y + r + 1 < h) { var oa = (y + r + 1) * w; for (x = 0; x < w; x++) { col[x] += tmp[oa + x]; } }
      if (y - r >= 0) { var ob = (y - r) * w; for (x = 0; x < w; x++) { col[x] -= tmp[ob + x]; } }
    }
    return out;
  }
  function skeletonSegments(skel, w, h, minLen) {        // netra.util.skeletonSegments (paths between junctions)
    var W = w + 2, H = h + 2, P = new Uint8Array(W * H), x, y, i, k;
    for (y = 0; y < h; y++) { for (x = 0; x < w; x++) { P[(y + 1) * W + x + 1] = skel[y * w + x]; } }
    // neighbour order of the MATLAB walk: up, down, left, right, then the diagonals
    var off = [-W, W, -1, 1, -W - 1, W - 1, -W + 1, W + 1], step = [1, 1, 1, 1, Math.SQRT2, Math.SQRT2, Math.SQRT2, Math.SQRT2];
    var branch = new Uint8Array(W * H);
    for (i = W; i < W * H - W; i++) {
      if (!P[i]) { continue; }
      var nb = 0;
      for (k = 0; k < 8; k++) { nb += P[i + off[k]]; }
      if (nb >= 3) { branch[i] = 1; }
    }
    var near = dilate3(branch, W, H), cut = new Uint8Array(W * H);
    for (i = 0; i < cut.length; i++) { cut[i] = P[i] && !near[i] ? 1 : 0; }
    var L = label(cut, W, H), mark = Int32Array.from(L.lab), segs = [];
    L.comps.forEach(function (pix, ci) {
      var id = ci + 1, np = pix.length, t;
      if (np < minLen) { return; }
      var s0 = -1;
      for (t = 0; t < np && s0 < 0; t++) {
        var deg = 0;
        for (k = 0; k < 8; k++) { if (mark[pix[t] + off[k]] === id) { deg++; } }
        if (deg <= 1) { s0 = t; }
      }
      if (s0 < 0) { s0 = 0; }                                 // closed loop: start anywhere
      var cur = pix[s0], order = [cur], len = 0;
      mark[cur] = -id;
      for (t = 1; t < np; t++) {
        var hit = -1;
        for (k = 0; k < 8; k++) { if (mark[cur + off[k]] === id) { hit = k; break; } }
        if (hit < 0) { break; }
        cur += off[hit]; len += step[hit];
        mark[cur] = -id; order.push(cur);
      }
      var a = order[0], b = order[order.length - 1], chord = Math.hypot(((b / W) | 0) - ((a / W) | 0), (b % W) - (a % W));
      segs.push({ idx: order.map(function (q) { return (((q / W) | 0) - 1) * w + (q % W) - 1; }), length: len, chord: chord, tortuosity: len / Math.max(chord, 1) });
    });
    return segs;
  }
  // New vessels are fine, tortuous, randomly oriented and loop back on
  // themselves; over a 0.5-DD window the detector measures branching,
  // orientation entropy, tortuosity, loops and skeleton length, each as a
  // one-sided, capped robust z-score against the rest of the same image,
  // separately inside the disc zone and outside it.
  function neovascularization(E, V, F) {                 // netra.lesions.neovascularization
    var nc = CFG.nv, D = E.D, n = D * D, DD = F.pxPerDD, i, k, x, y;
    var m = maskErode(E, Math.max(2, mround(0.1 * DD))), c = new Float32Array(n);
    for (i = 0; i < n; i++) { c[i] = E.mask[i] ? 1 - E.gN[i] : 0; }
    // fine-vessel map at canvas resolution (new vessels are 20-50 um wide)
    var fineV = new Float32Array(n), theta = new Float32Array(n);
    [1.0, 1.6].forEach(function (sg) {
      var H = hessian(c, D, D, sg), mx = 0, j, S2 = new Float32Array(n);
      for (j = 0; j < n; j++) { S2[j] = H.l1[j] * H.l1[j] + H.l2[j] * H.l2[j]; if (m[j] && S2[j] > mx) { mx = S2[j]; } }
      var cc = 0.5 * Math.sqrt(mx);
      for (j = 0; j < n; j++) {
        if (H.l2[j] >= 0) { continue; }
        var Rb = H.l1[j] / (H.l2[j] - EPS), v = Math.exp(-Rb * Rb / 0.5) * (1 - Math.exp(-S2[j] / (2 * cc * cc + EPS)));
        if (v > fineV[j]) { fineV[j] = v; theta[j] = H.theta[j]; }
      }
    });
    var t85 = pct(pick(fineV, m), 85), B = new Uint8Array(n);
    for (i = 0; i < n; i++) { B[i] = m[i] && (fineV[i] > t85 || V.maskWork[i]) ? 1 : 0; }
    B = areaOpen(B, D, D, 10);
    var skel = thin(B, D, D), w = Math.max(5, 2 * mround(nc.windowDD * DD / 2) + 1), w2 = w * w;
    var mf = new Float32Array(n), sk = new Float32Array(n);
    for (i = 0; i < n; i++) { mf[i] = m[i]; sk[i] = skel[i]; }
    var fm = boxMean0(mf, D, D, w), skd = boxMean0(sk, D, D, w), skdN = new Float32Array(n);
    for (i = 0; i < n; i++) { skdN[i] = skd[i] / Math.max(fm[i], 1e-3); }
    // branch points per unit skeleton length
    var br = new Float32Array(n);
    for (y = 1; y < D - 1; y++) {
      for (x = 1; x < D - 1; x++) {
        i = y * D + x;
        if (skel[i] && skel[i - D - 1] + skel[i - D] + skel[i - D + 1] + skel[i - 1] + skel[i + 1] + skel[i + D - 1] + skel[i + D] + skel[i + D + 1] >= 3) { br[i] = 1; }
      }
    }
    var brn = boxMean0(br, D, D, w);
    for (i = 0; i < n; i++) { brn[i] /= Math.max(skd[i], 1 / w2); }
    // entropy of skeleton orientations in 6 bins
    var bins = [], ent = new Float32Array(n);
    for (k = 0; k < 6; k++) { bins.push(new Float32Array(n)); }
    for (i = 0; i < n; i++) {
      if (!skel[i]) { continue; }
      var th = theta[i] % Math.PI;
      if (th < 0) { th += Math.PI; }
      bins[Math.min(Math.floor(th / (Math.PI / 6)), 5)][i] = 1;
    }
    for (k = 0; k < 6; k++) {
      var pk = boxMean0(bins[k], D, D, w);
      for (i = 0; i < n; i++) { var pp = pk[i] / Math.max(skd[i], EPS); ent[i] -= pp * Math.log(pp + EPS); }
    }
    for (i = 0; i < n; i++) { ent[i] /= Math.log(6); }
    // tortuosity of the skeleton segments, painted on their pixels
    var tmap = new Float32Array(n);
    skeletonSegments(skel, D, D, 6).forEach(function (sg) { var v = Math.min(sg.tortuosity - 1, 2); sg.idx.forEach(function (q) { tmap[q] = v; }); });
    var tor = boxMean0(tmap, D, D, w);
    for (i = 0; i < n; i++) { tor[i] /= Math.max(skd[i], EPS); }
    // loops: small holes enclosed by vessels
    var filled = fillHoles(B, D, D), holes = new Uint8Array(n);
    for (i = 0; i < n; i++) { holes[i] = filled[i] && !B[i] ? 1 : 0; }
    var big = areaOpen(holes, D, D, Math.max(4, mround(Math.pow(0.3 * DD, 2))));
    for (i = 0; i < n; i++) { if (big[i]) { holes[i] = 0; } }
    var hc = new Float32Array(n);
    label(holes, D, D).comps.forEach(function (pix) {
      var sx = 0, sy = 0;
      pix.forEach(function (q) { var qy = (q / D) | 0; sy += qy; sx += q - qy * D; });
      hc[mround(sy / pix.length) * D + mround(sx / pix.length)] = 1;
    });
    var loops = boxMean0(hc, D, D, w);
    for (i = 0; i < n; i++) { loops[i] *= w2; }
    // share of fine vessels (<= 0.03 DD wide) in the skeleton
    var notB = new Uint8Array(n);
    for (i = 0; i < n; i++) { notB[i] = B[i] ? 0 : 1; }
    var d2 = edt(notB, D, D).d2, fineSk = new Float32Array(n);
    for (i = 0; i < n; i++) { if (skel[i] && 2 * Math.sqrt(d2[i]) - 1 <= 0.03 * DD) { fineSk[i] = 1; } }
    var fine = boxMean0(fineSk, D, D, w);
    for (i = 0; i < n; i++) { fine[i] /= Math.max(skd[i], EPS); }
    // zone-wise robust z-scores, one-sided and capped
    var zone = new Uint8Array(n), inside = new Uint8Array(n), grid = new Uint8Array(n), stride = Math.max(1, mround(nc.strideDD * DD / 2));
    for (y = 0; y < D; y += stride) { for (x = 0; x < D; x += stride) { grid[y * D + x] = 1; } }
    for (i = 0; i < n; i++) { zone[i] = F.distDisc[i] <= nc.discZoneDD ? 1 : 0; inside[i] = m[i] && fm[i] > 0.7 && skd[i] > 0 ? 1 : 0; }
    var feats = [brn, ent, tor, loops, skdN], wts = [1, 1, 1, 1, 0.5], S = new Float32Array(n);
    [1, 0].forEach(function (z) {
      var ref = [];
      for (var j = 0; j < n; j++) { if (inside[j] && grid[j] && zone[j] === z) { ref.push(j); } }
      if (!ref.length) { return; }
      feats.forEach(function (f, fk) {
        var st = robustStats(ref.map(function (q) { return f[q]; })), med = st[0], sd = Math.max(st[1], 1e-3 + 0.05 * Math.abs(med));
        for (var q = 0; q < n; q++) { if (zone[q] === z) { S[q] += wts[fk] * Math.min(nc.zCap, Math.max(0, (f[q] - med) / sd)); } }
      });
    });
    // gates: new vessels add fine vessel length
    var lens = [];
    for (i = 0; i < n; i++) { if (inside[i] && grid[i]) { lens.push(skdN[i]); } }
    var gl = lens.length ? robustStats(lens) : [0, 1], medL = gl[0], sdL = Math.max(gl[1], 1e-3);
    for (i = 0; i < n; i++) { S[i] = inside[i] ? S[i] * sigmoid(skdN[i], medL, sdL) * sigmoid(fine[i], 0.55, 0.06) : 0; }
    // candidate regions
    var Cm = new Uint8Array(n);
    for (i = 0; i < n; i++) { Cm[i] = S[i] > nc.threshold ? 1 : 0; }
    var nvMask = Uint8Array.from(Cm), cand = [];
    Cm = areaOpen(Cm, D, D, Math.max(4, mround(nc.minWindows * Math.pow(nc.strideDD * DD, 2) / 4)));
    label(Cm, D, D).comps.forEach(function (pix) {
      var sx = 0, sy = 0, sc = 0, x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
      pix.forEach(function (q) {
        var qy = (q / D) | 0, qx = q - qy * D;
        sx += qx; sy += qy; if (S[q] > sc) { sc = S[q]; }
        if (qx < x0) { x0 = qx; } if (qx > x1) { x1 = qx; } if (qy < y0) { y0 = qy; } if (qy > y1) { y1 = qy; }
      });
      var cx = sx / pix.length, cy = sy / pix.length, dd = Math.hypot(cx - F.od[0], cy - F.od[1]) / F.pxPerDD;
      cand.push({ type: dd <= nc.discZoneDD ? 'NVD' : 'NVE', x: cx, y: cy, bbox: [x0, y0, x1 - x0 + 1, y1 - y0 + 1], score: sc, prob: sigmoid(sc, nc.threshold + 1, 1.0) });
    });
    var nvd = 0, nve = 0;
    for (i = 0; i < n; i++) {
      if (!inside[i]) { continue; }
      if (zone[i]) { if (S[i] > nvd) { nvd = S[i]; } } else if (S[i] > nve) { nve = S[i]; }
    }
    return { nvdScore: nvd, nveScore: nve, nvdProb: sigmoid(nvd, nc.threshold + 1, 1.0), nveProb: sigmoid(nve, nc.threshold + 1, 1.0),
      candidates: cand, scoreMap: S, mask: nvMask, window: w };
  }

  /* ======================================================= explanation maps */
  // where the detectors found disease, weighted by clinical weight
  // (MA 1, haemorrhage 2, exudate 1.5, cotton-wool spot 1.5, new vessels 4)
  // and smoothed at 0.15 DD; scaled to 0-255
  function evidenceMap(E, F, L) {                        // netra.xai.evidenceMap
    var D = E.D, n = D * D, Wt = new Float32Array(n), i;
    L.ma.list.forEach(function (e) {
      if (e.prob < 0.5) { return; }
      var rad = Math.max(1, 1.1774 * e.sigmaPx), r2 = rad * rad;
      for (var y = Math.max(0, Math.floor(e.y - rad - 1)); y <= Math.min(D - 1, Math.ceil(e.y + rad + 1)); y++) {
        for (var x = Math.max(0, Math.floor(e.x - rad - 1)); x <= Math.min(D - 1, Math.ceil(e.x + rad + 1)); x++) {
          if ((x - e.x) * (x - e.x) + (y - e.y) * (y - e.y) <= r2) { Wt[y * D + x] = 1; }
        }
      }
    });
    for (i = 0; i < n; i++) { if (L.he.mask[i]) { Wt[i] += 2; } if (L.nv.mask[i]) { Wt[i] += 4; } }
    L.ex.list.forEach(function (e) { e.pix.forEach(function (q) { Wt[q] += 1.5; }); });
    L.ex.cws.forEach(function (e) { e.pix.forEach(function (q) { Wt[q] += 1.5; }); });
    var M = smooth(Wt, D, D, 0.15 * F.pxPerDD), mx = 0, out = new Uint8Array(n);
    for (i = 0; i < n; i++) { if (M[i] > mx) { mx = M[i]; } }
    if (mx > 0) { for (i = 0; i < n; i++) { out[i] = Math.round(255 * Math.max(M[i], 0) / mx); } }
    return out;
  }
  // One 16-bit word per canvas pixel saying which overlay layers cover it,
  // so the page can switch layers without running the engine again.
  var LAYER = { vessels: 0, disc: 1, fovea: 2, grid: 3, ma: 4, he: 5, flame: 6, preretinal: 7, ex: 8, cws: 9, nv: 10 };
  function layerBits(E, A, L) {
    var D = E.D, n = D * D, bits = new Uint16Array(n), F = A.frame, DD = F.pxPerDD, lw = Math.max(1, D / 700), own = new Int32Array(n), tag = 0, i;
    function set(x, y, b) { if (x >= 0 && y >= 0 && x < D && y < D) { bits[y * D + x] |= 1 << b; } }
    function ring(c, r, width, b, dashed) {
      var R = r + width + 1, h = width / 2;
      for (var y = Math.floor(c[1] - R); y <= Math.ceil(c[1] + R); y++) {
        for (var x = Math.floor(c[0] - R); x <= Math.ceil(c[0] + R); x++) {
          if (Math.abs(Math.hypot(x - c[0], y - c[1]) - r) > h) { continue; }
          if (dashed && Math.floor((Math.atan2(y - c[1], x - c[0]) + Math.PI) / (Math.PI / 12)) % 2) { continue; }
          set(x, y, b);
        }
      }
    }
    function segment(p, q, width, b) {
      var len = Math.hypot(q[0] - p[0], q[1] - p[1]), steps = Math.max(1, Math.ceil(len * 2)), h = width / 2;
      for (var s = 0; s <= steps; s++) {
        var cx = p[0] + (q[0] - p[0]) * s / steps, cy = p[1] + (q[1] - p[1]) * s / steps;
        for (var y = Math.floor(cy - h); y <= Math.ceil(cy + h); y++) {
          for (var x = Math.floor(cx - h); x <= Math.ceil(cx + h); x++) { if (Math.hypot(x - cx, y - cy) <= h + 0.25) { set(x, y, b); } }
        }
      }
    }
    function outline(pix, b) {                            // the component's edge, drawn 3 px wide
      tag++;
      pix.forEach(function (q) { own[q] = tag; });
      pix.forEach(function (q) {
        if (own[q - 1] === tag && own[q + 1] === tag && own[q - D] === tag && own[q + D] === tag) { return; }
        var y = (q / D) | 0, x = q - y * D;
        for (var dy = -1; dy <= 1; dy++) { for (var dx = -1; dx <= 1; dx++) { set(x + dx, y + dy, b); } }
      });
    }
    var core = maskErode(E, Math.max(3, mround(0.03 * DD)));    // the detector's response to the rim of the field is not a vessel
    for (i = 0; i < n; i++) { if (A.vessels.maskWork[i] && core[i]) { bits[i] |= 1; } }
    [1 / 3, 1, 2].forEach(function (rDD) { ring(F.fovea, rDD * DD, 1.3 * lw, LAYER.grid, false); });
    [F.nasal, F.superior].forEach(function (ax) {
      segment([F.fovea[0] - 2 * DD * ax[0], F.fovea[1] - 2 * DD * ax[1]], [F.fovea[0] - DD / 3 * ax[0], F.fovea[1] - DD / 3 * ax[1]], 1.1 * lw, LAYER.grid);
      segment([F.fovea[0] + DD / 3 * ax[0], F.fovea[1] + DD / 3 * ax[1]], [F.fovea[0] + 2 * DD * ax[0], F.fovea[1] + 2 * DD * ax[1]], 1.1 * lw, LAYER.grid);
    });
    ring(A.od.centre, A.od.radius, 1.8 * lw, LAYER.disc, true);
    segment([F.fovea[0] - 7 * lw, F.fovea[1]], [F.fovea[0] + 7 * lw, F.fovea[1]], 1.5 * lw, LAYER.fovea);
    segment([F.fovea[0], F.fovea[1] - 7 * lw], [F.fovea[0], F.fovea[1] + 7 * lw], 1.5 * lw, LAYER.fovea);
    L.he.list.forEach(function (e) {
      if (e.prob < 0.5) { return; }
      var b = e.type === 'flame' ? LAYER.flame : e.type === 'preretinal' ? LAYER.preretinal : LAYER.he;
      if (e.pix) { outline(e.pix, b); } else { ring([e.x, e.y], Math.max(2.5 * lw, 1.6 * e.radius), 1.6 * lw, b, false); }
    });
    L.ex.list.forEach(function (e) { if (e.prob >= 0.5) { outline(e.pix, LAYER.ex); } });
    L.ex.cws.forEach(function (e) { if (e.prob >= 0.5) { outline(e.pix, LAYER.cws); } });
    L.ma.list.forEach(function (e) {
      if (e.cls === 'MA' && e.prob >= 0.5) { ring([e.x, e.y], Math.max(4 * lw, 2.8 * e.sigmaPx), 1.6 * lw, LAYER.ma, false); }
    });
    L.nv.candidates.forEach(function (cv) {
      if (cv.prob < 0.5) { return; }
      var bx = cv.bbox, x0 = bx[0] - 3, y0 = bx[1] - 3, x1 = bx[0] + bx[2] + 2, y1 = bx[1] + bx[3] + 2;
      segment([x0, y0], [x1, y0], 2 * lw, LAYER.nv); segment([x1, y0], [x1, y1], 2 * lw, LAYER.nv);
      segment([x1, y1], [x0, y1], 2 * lw, LAYER.nv); segment([x0, y1], [x0, y0], 2 * lw, LAYER.nv);
    });
    return bits;
  }
  function rgbaOf(planes, mask, D) {                     // float planes in [0,1] -> RGBA bytes
    var n = D * D, out = new Uint8ClampedArray(4 * n);
    for (var i = 0; i < n; i++) {
      var a = mask && !mask[i] ? 0 : 255;
      out[4 * i] = a && 255 * planes[0][i]; out[4 * i + 1] = a && 255 * planes[1][i]; out[4 * i + 2] = a && 255 * planes[2][i]; out[4 * i + 3] = 255;
    }
    return out;
  }

  /* ============================================================== grading */
  function rng(seed) {
    var a = seed >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function probabilisticRules(L) {                       // netra.grading.probabilisticRules (no venous beading / IRMA)
    var r = CFG.rules, S = CFG.grading.mcSamples, u = rng(20260925), fl = r.evidenceFloor;
    function eff(p) { return Math.max(0, (p - fl) / (1 - fl)); }
    var counts = [0, 0, 0, 0, 0];
    var mas = L.ma.list.filter(function (e) { return e.cls === 'MA'; }), he = L.he.list;
    for (var s = 0; s < S; s++) {
      var nMA = 0, nHigh = 0;
      mas.forEach(function (e) { if (u() < eff(e.prob)) { nMA++; if (e.prob >= r.maHighProb) { nHigh++; } } });
      var maAny = nHigh >= r.maMinHigh || nMA >= r.maMinCount, heAny = false, prh = false, q = [0, 0, 0, 0];
      he.forEach(function (e) {
        if (u() < eff(e.prob)) {
          if (e.type === 'preretinal') { prh = true; }
          else if (e.quadrant > 0) { heAny = true; q[e.quadrant - 1]++; }
        }
      });
      var he4q = q.filter(function (c) { return c >= r.hePerQuadrant; }).length >= r.heQuadrants;
      var exAny = L.ex.list.some(function (e) { return u() < eff(e.prob); }), cwsAny = L.ex.cws.some(function (e) { return u() < eff(e.prob); });
      var nv = u() < eff(L.nv.nvdProb) || u() < eff(L.nv.nveProb);
      var g = 0;
      if (maAny) { g = 1; }
      if (heAny || exAny || cwsAny) { g = 2; }
      if (he4q) { g = 3; }
      if (nv || prh) { g = 4; }
      counts[g]++;
    }
    return counts.map(function (c, k) { return (1 - r.smoothing) * c / S + r.smoothing * r.gradePrior[k]; });
  }
  function icdrRules(s) {                                // netra.grading.icdrRules (criteria the web version measures)
    var r = CFG.rules, C = [];
    function crit(id, level, value, threshold, met) { C.push({ id: id, level: level, value: value, threshold: threshold, met: !!met }); }
    crit('ma', 1, s.maCount, r.maMinCount, s.maHighCount >= r.maMinHigh || s.maCount >= r.maMinCount);
    crit('he', 2, s.heTotal, 1, s.heTotal >= 1);
    crit('ex', 2, s.exCount, 1, s.exCount >= 1);
    crit('cws', 2, s.cwsCount, 1, s.cwsCount >= 1);
    var nQ = s.hePerQuadrant.filter(function (c) { return c >= r.hePerQuadrant; }).length;
    crit('he4q', 3, nQ, r.heQuadrants, nQ >= r.heQuadrants);
    var pNV = Math.max(s.nvdProb, s.nveProb);
    crit('nv', 4, pNV, r.nvProb, pNV >= r.nvProb);
    C[C.length - 1].where = s.nvdProb >= s.nveProb ? 'NVD' : 'NVE';
    crit('prh', 4, s.preretinalCount, 1, s.preretinalCount >= 1);
    var grade = 0;
    C.forEach(function (c) { if (c.met && c.level > grade) { grade = c.level; } });
    return { grade: grade, dme: s.dme, centreInvolved: s.centreInvolved, referable: grade >= 2 || s.dme >= 2, criteria: C };
  }
  function decide(Q, R, Fz, flags) {                     // netra.grading.decide (rules branch only)
    var g = CFG.grading, reasons = [], triage = 'ROUTINE', pRef = Fz.pReferable;
    if (R.dme >= 2) { pRef = 1 - (1 - pRef) * 0.1; }
    if (Q.decision === 'RECAPTURE') {
      triage = 'RECAPTURE';
      Q.feedback.forEach(function (f) { reasons.push({ key: f.key }); });
      if (!reasons.length) { reasons.push({ key: 'r.quality', score: Q.score }); }
    } else {
      var prh = R.criteria.some(function (c) { return (c.id === 'prh' || c.id === 'nv') && c.met; });
      if (Fz.pUrgent >= g.urgentThreshold || prh || R.centreInvolved) {
        triage = 'URGENT';
        if (prh) { reasons.push({ key: 'r.nvprh' }); }
        if (R.centreInvolved) { reasons.push({ key: 'r.centre' }); }
        if (Fz.pUrgent >= g.urgentThreshold && !prh) { reasons.push({ key: 'r.pUrgent', value: Fz.pUrgent }); }
      } else if (pRef >= g.referralThreshold || R.dme >= 2) {
        triage = 'REFER';
        reasons.push({ key: 'r.pRef', value: pRef, threshold: g.referralThreshold });
        if (R.dme >= 2) { reasons.push({ key: 'r.dme' }); }
      } else {
        var review = [];
        if (Q.decision !== 'GRADABLE') { review.push({ key: 'r.borderline', score: Q.score }); }
        flags.forEach(function (f) { review.push({ key: 'r.anatomy', flag: f }); });
        if (review.length) { triage = 'HUMAN_REVIEW'; reasons = review; }
        else { reasons.push({ key: 'r.low', value: pRef, threshold: g.referralThreshold, grade: Fz.grade }); }
      }
    }
    var key = triage === 'REFER' && R.dme >= 2 ? 'REFER_DME' : triage;
    return { triage: triage, key: key, grade: Fz.grade, pReferable: pRef, pUrgent: Fz.pUrgent, dme: R.dme, reasons: reasons };
  }

  /* ============================================================== overlay */
  function drawOverlay(E, A, L) {                        // netra.xai.overlay (raster version)
    var D = E.D, img = Uint8ClampedArray.from(E.display), lw = Math.max(1, D / 700), F = A.frame, DD = F.pxPerDD;
    function blend(x, y, col, a) {
      if (x < 0 || y < 0 || x >= D || y >= D || a <= 0) { return; }
      var i = 4 * (y * D + x);
      img[i] = img[i] * (1 - a) + col[0] * a; img[i + 1] = img[i + 1] * (1 - a) + col[1] * a; img[i + 2] = img[i + 2] * (1 - a) + col[2] * a;
    }
    function ring(c, r, col, alpha, width, dashed) {
      var R = r + width + 1;
      for (var y = Math.floor(c[1] - R); y <= Math.ceil(c[1] + R); y++) {
        for (var x = Math.floor(c[0] - R); x <= Math.ceil(c[0] + R); x++) {
          var d = Math.hypot(x - c[0], y - c[1]), a = alpha * clamp(1 - Math.abs(d - r) / (width / 2 + 0.5) + 0.5, 0, 1);
          if (a <= 0) { continue; }
          if (dashed && Math.floor((Math.atan2(y - c[1], x - c[0]) + Math.PI) / (Math.PI / 12)) % 2) { continue; }
          blend(x, y, col, a);
        }
      }
    }
    function segment(p, q, col, alpha, width) {
      var len = Math.hypot(q[0] - p[0], q[1] - p[1]), steps = Math.max(1, Math.ceil(len * 2));
      for (var s = 0; s <= steps; s++) {
        var x = p[0] + (q[0] - p[0]) * s / steps, y = p[1] + (q[1] - p[1]) * s / steps;
        for (var dy = -Math.ceil(width); dy <= Math.ceil(width); dy++) {
          for (var dx = -Math.ceil(width); dx <= Math.ceil(width); dx++) {
            var a = alpha * clamp(1 - (Math.hypot(dx, dy) - width / 2), 0, 1);
            blend(mround(x) + dx, mround(y) + dy, col, a * 0.5);
          }
        }
      }
    }
    function outline(pix, col, alpha) {
      var set = {};
      pix.forEach(function (q) { set[q] = 1; });
      pix.forEach(function (q) {
        var y = (q / D) | 0, x = q - y * D;
        if (set[q - 1] && set[q + 1] && set[q - D] && set[q + D]) { return; }
        for (var dy = -1; dy <= 1; dy++) { for (var dx = -1; dx <= 1; dx++) { blend(x + dx, y + dy, col, alpha); } }
      });
    }
    var white = [255, 255, 255];
    [1 / 3, 1, 2].forEach(function (rDD) { ring(F.fovea, rDD * DD, white, 0.35, 0.8 * lw, false); });
    [F.nasal, F.superior].forEach(function (ax) {
      segment([F.fovea[0] - 2 * DD * ax[0], F.fovea[1] - 2 * DD * ax[1]], [F.fovea[0] - DD / 3 * ax[0], F.fovea[1] - DD / 3 * ax[1]], white, 0.3, 0.8 * lw);
      segment([F.fovea[0] + DD / 3 * ax[0], F.fovea[1] + DD / 3 * ax[1]], [F.fovea[0] + 2 * DD * ax[0], F.fovea[1] + 2 * DD * ax[1]], white, 0.3, 0.8 * lw);
    });
    ring(A.od.centre, A.od.radius, white, 0.85, 1.2 * lw, true);
    var fc = [224, 242, 255];
    segment([F.fovea[0] - 6 * lw, F.fovea[1]], [F.fovea[0] + 6 * lw, F.fovea[1]], fc, 0.9, lw);
    segment([F.fovea[0], F.fovea[1] - 6 * lw], [F.fovea[0], F.fovea[1] + 6 * lw], fc, 0.9, lw);
    var cols = { blot: [184, 61, 186], dot: [184, 61, 186], flame: [123, 77, 255], preretinal: [91, 26, 140] };
    L.he.list.forEach(function (e) {
      if (e.prob < 0.5) { return; }
      if (e.pix) { outline(e.pix, cols[e.type], 0.95); } else { ring([e.x, e.y], Math.max(2.5 * lw, 1.6 * e.radius), cols.dot, 0.95, 1.2 * lw, false); }
    });
    L.ex.list.forEach(function (e) { if (e.prob >= 0.5) { outline(e.pix, [255, 212, 59], 0.95); } });
    L.ex.cws.forEach(function (e) { if (e.prob >= 0.5) { outline(e.pix, [155, 231, 255], 0.95); } });
    L.ma.list.forEach(function (e) {
      if (e.cls === 'MA' && e.prob >= 0.5) { ring([e.x, e.y], Math.max(4 * lw, 2.8 * e.sigmaPx), [255, 59, 92], 0.95, 1.1 * lw, false); }
    });
    L.nv.candidates.forEach(function (c) {
      if (c.prob < 0.5) { return; }
      var b = c.bbox, p = [[b[0] - 3, b[1] - 3], [b[0] + b[2] + 2, b[1] - 3], [b[0] + b[2] + 2, b[1] + b[3] + 2], [b[0] - 3, b[1] + b[3] + 2]];
      for (var k = 0; k < 4; k++) { segment(p[k], p[(k + 1) % 4], [124, 252, 90], 0.95, 1.4 * lw); }
    });
    return img;
  }

  /* ================================================================ screen */
  // opts.annotated: also return the overlay burnt into one RGBA image
  function screen(input, onProgress, opts) {
    opts = opts || {};
    var t0 = Date.now(), timing = {}, tick = Date.now();
    function step(k, name) { timing[name] = Date.now() - tick; tick = Date.now(); if (onProgress) { onProgress(k); } }
    var P = toPlanes(input), F = fovMask(P), res = { version: '1.0', input: { width: P.w, height: P.h } };
    if (!F.ok) {
      res.quality = { score: 0, decision: 'RECAPTURE', sub: { field: 0, focus: 0, illumination: 0, contrast: 0, artifact: 0 }, feedback: [{ key: 'fb.field', severity: 1 }], noFundus: true };
      res.decision = decide(res.quality, { criteria: [], dme: 0 }, { pReferable: NaN, pUrgent: NaN, grade: NaN }, []);
      res.seconds = (Date.now() - t0) / 1000;
      return res;
    }
    var Sq = standardize(P, F, CFG.scale.anatomyDiameter), Q = assessCanvas(Sq, F.coverage);
    step(1, 'quality');
    res.quality = Q;
    var S = standardize(P, F, CFG.scale.workDiameter);
    res.canvas = { D: S.D, raw: rgbaOf([S.r, S.g, S.b], null, S.D), radius: S.radius, centre: S.centre };
    if (Q.decision === 'RECAPTURE') {
      res.decision = decide(Q, { criteria: [], dme: 0 }, { pReferable: NaN, pUrgent: NaN, grade: NaN }, []);
      res.seconds = (Date.now() - t0) / 1000;
      return res;
    }
    var E = enhance(S, Q);
    if (Q.decision === 'ENHANCE') {                      // re-assess the enhanced image
      var D2 = CFG.scale.anatomyDiameter, sm = {
        D: D2, r: resize(E.rgbN[0], S.D, S.D, D2, D2), g: resize(E.rgbN[1], S.D, S.D, D2, D2), b: resize(E.rgbN[2], S.D, S.D, D2, D2),
        mask: resizeNearest(S.mask, S.D, S.D, D2, D2), circle: resizeNearest(S.circle, S.D, S.D, D2, D2), inFrame: resizeNearest(S.inFrame, S.D, S.D, D2, D2),
        centre: [(D2 - 1) / 2, (D2 - 1) / 2], radius: S.radius * D2 / S.D
      };
      var Q2 = assessCanvas(sm, F.coverage);
      Q.afterEnhancement = { score: Q2.score, decision: Q2.decision };
      Q.enhanced = true;
      if (Q2.decision === 'RECAPTURE') {
        res.decision = decide(Q, { criteria: [], dme: 0 }, { pReferable: NaN, pUrgent: NaN, grade: NaN }, []);
        res.seconds = (Date.now() - t0) / 1000;
        return res;
      }
      if (Q2.decision === 'GRADABLE') { Q.decision = 'GRADABLE'; Q.note = 'gradable-after-enhancement'; }
    }
    res.canvas.normalised = rgbaOf(E.rgbN, E.mask, S.D);
    res.canvas.display = E.display;
    res.enhancement = { noise: E.noise, denoised: E.denoised, clip: E.clip, backgroundSigmaPx: CFG.enhance.backgroundDD * CFG.scale.ddPerFOV * 2 * S.radius,
      claheTiles: CFG.enhance.claheTiles };
    var V = vessels(E), OD = opticDisc(E, V, S), FV = fovea(E, V, OD, S), FR = frame(OD, FV, S.D), flags = [];
    if (OD.confidence < 0.35) { flags.push('disc-uncertain'); }
    if (FV.confidence < 0.35) { flags.push('fovea-uncertain'); }
    if (!FV.consistent) { flags.push('geometry-implausible'); }
    var A = { vessels: V, od: OD, fovea: FV, frame: FR, flags: flags };
    step(2, 'anatomy');
    var MA = microaneurysms(E, V, FR), HE = hemorrhages(E, V, FR, MA), EX = exudates(E, V, FR), NV = neovascularization(E, V, FR);
    var s = {
      maCount: MA.list.filter(function (e) { return e.cls === 'MA' && e.prob >= 0.5; }).length,
      maHighCount: MA.list.filter(function (e) { return e.cls === 'MA' && e.prob >= CFG.rules.maHighProb; }).length,
      heCounts: HE.counts, heTotal: HE.counts.dot + HE.counts.blot + HE.counts.flame, hePerQuadrant: HE.perQuadrant,
      preretinalCount: HE.counts.preretinal, exCount: EX.count, exAreaDD2: EX.areaDD2, exMinDistFoveaDD: EX.minDistFoveaDD,
      dme: EX.dme, centreInvolved: EX.centreInvolved, cwsCount: EX.cwsCount,
      nvdProb: NV.nvdProb, nveProb: NV.nveProb, nvdScore: NV.nvdScore, nveScore: NV.nveScore,
      nvCount: NV.candidates.filter(function (c) { return c.prob >= 0.5; }).length
    };
    var L = { ma: MA, he: HE, ex: EX, nv: NV, summary: s };
    step(3, 'lesions');
    var P5 = probabilisticRules(L), cum = 0, grade = 4;
    for (var k = 0; k < 5; k++) { cum += P5[k]; if (cum >= 0.5) { grade = k; break; } }
    var Fz = { P: P5, grade: grade, pReferable: P5[2] + P5[3] + P5[4], pUrgent: P5[4] };
    var R = icdrRules(s), T = decide(Q, R, Fz, flags);
    res.rules = R;
    res.fusion = Fz;
    res.decision = T;
    step(4, 'grading');
    res.layers = { bits: layerBits(E, A, L), evidence: evidenceMap(E, FR, L) };
    if (opts.annotated) { res.annotated = drawOverlay(E, A, L); }
    res.anatomy = { od: { x: OD.centre[0], y: OD.centre[1], r: OD.radius, confidence: OD.confidence, measured: OD.measured },
      fovea: { x: FV.centre[0], y: FV.centre[1], confidence: FV.confidence, distanceDD: FV.distanceDD, consistent: FV.consistent },
      pxPerDD: FR.pxPerDD, umPerPx: FR.umPerPx, eye: FR.eye, flags: flags, vesselFraction: V.fraction };
    function slim(e) {
      var o = { x: e.x, y: e.y, prob: e.prob, quadrant: e.quadrant, type: e.type || e.cls, distFoveaDD: e.distFoveaDD };
      ['diameterUm', 'eqDiamUm', 'areaPx', 'sigmaPx', 'snr', 'seXY', 'crlb', 'amplitude', 'r2'].forEach(function (k) { if (e[k] !== undefined) { o[k] = e[k]; } });
      return o;
    }
    res.lesions = { summary: s, ma: MA.list.filter(function (e) { return e.cls === 'MA' && e.prob >= 0.5; }).map(slim),
      he: HE.list.filter(function (e) { return e.prob >= 0.5; }).map(slim), ex: EX.list.filter(function (e) { return e.prob >= 0.5; }).map(slim),
      cws: EX.cws.filter(function (e) { return e.prob >= 0.5; }).map(slim),
      nv: NV.candidates.map(function (c) { return { type: c.type, x: c.x, y: c.y, bbox: c.bbox, score: c.score, prob: c.prob }; }),
      candidates: MA.candidates };
    step(5, 'explanation');
    res.timing = timing;
    res.seconds = (Date.now() - t0) / 1000;
    return res;
  }

  var api = { screen: screen, config: CFG, _internals: { fovMask: fovMask, standardize: standardize, assessCanvas: assessCanvas, enhance: enhance, vessels: vessels, opticDisc: opticDisc, fovea: fovea, frame: frame, microaneurysms: microaneurysms, hemorrhages: hemorrhages, exudates: exudates, toPlanes: toPlanes, edt: edt, otsu: otsu, pct: pct, medianFilter: medianFilter, circleFit: circleFit, regionProps: regionProps, fitGaussian2D: fitGaussian2D,
    greyOpen: greyOpen, greyCloseDisk: greyCloseDisk, lineOffsets: lineOffsets, hessian: hessian, gauss: gauss, erodeDisk: erodeDisk, robustStats: robustStats,
    sepFilter: sepFilter, gaussResize: gaussResize, resize: resize, smooth: smooth, lineOpen: lineOpen, greyDisk: greyDisk, dilateDisk: dilateDisk,
    neovascularization: neovascularization, skeletonSegments: skeletonSegments, boxMean0: boxMean0, evidenceMap: evidenceMap, layerBits: layerBits }, LAYER: LAYER };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; }
  else { root.NetraEngine = api; }
  // Web Worker entry point
  if (typeof WorkerGlobalScope !== 'undefined' && root instanceof WorkerGlobalScope) {
    root.onmessage = function (ev) {
      var msg = ev.data;
      if (!msg || msg.cmd !== 'screen') { return; }
      try {
        var out = screen(msg.image, function (k) { root.postMessage({ progress: k, id: msg.id }); }, msg.opts);
        var transfer = [];
        if (out.annotated) { transfer.push(out.annotated.buffer); }
        if (out.canvas) { ['raw', 'normalised', 'display'].forEach(function (k) { if (out.canvas[k]) { transfer.push(out.canvas[k].buffer); } }); }
        if (out.layers) { transfer.push(out.layers.bits.buffer, out.layers.evidence.buffer); }
        root.postMessage({ result: out, id: msg.id }, transfer);
      } catch (err) {
        root.postMessage({ error: String(err && err.stack || err), id: msg.id });
      }
    };
  }
})(typeof self !== 'undefined' ? self : this);
