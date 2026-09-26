/* ======================================================================
   District model: a line-by-line port of netra.sim from the NetraSetu
   MATLAB repository (defaults, scenario, prepare, operatingCurve, the
   stage functions, ageQueue, runReference and kpis). Same equations,
   its own random stream; it reproduces the repository's figures within
   sampling noise.
   ====================================================================== */
var NetraSim = (function () {
  'use strict';
  function defaults() {
    return {
      dt: 1, days: 364, maxAgeHours: 240, seed: 2026,
      phc: { count: 36, demandPerDay: 11, hours: [9, 16], weekday: [1.25, 1.05, 1.0, 1.0, 0.95, 0.75, 0], holidays: 16 },
      season: [1, 1, 1, 1, 1, 0.95, 0.8, 0.8, 0.85, 1, 1.05, 1.05],
      van: { demandPerCampDay: 55, campDaysPerWeek: 5, hours: [9, 16], uploadHours: [18, 22] },
      capture: { minutesPerPatient: 6, ungradableFirst: 0.12, recaptureSuccess: 0.6, recaptureMinutes: 3, camerasPerPHC: 1 },
      images: { mbPerPatient: 16 },
      link: { mbps: [0.05, 0.5, 4, 20], availability: [0.90, 0.85, 0.80, 0.97], meanOutageHours: [3, 4, 5, 8],
        efficiency: 0.6, hours: [9, 17], baselineMix: [0.25, 0.35, 0.30, 0.10] },
      ai: { cloudPatientsPerHour: 900, edgeSecondsPerPatient: 20, auc: 0.95, sensitivity: 0.92, uncertainShare: 0.06, urgentSensitivity: 0.97 },
      mix: { referable: 0.08, urgent: 0.012 },
      review: { graderHours: [10, 17], graderDays: [1, 2, 3, 4, 5, 6], secondsPerCase: { xai: 30, plain: 150 },
        adjudicate: 0.25, ophthStart: 14, ophthSecondsPerCase: { xai: 60, plain: 180 }, qaShare: 0.05 },
      referral: { uptakeOnSite: 0.65, uptakeDelayed: 0.40, presenceHours: 3, provisionalOnSite: true },
      cost: { camera: 350000, cameraLife: 5, cameraUpkeep: 0.10, technicianPerSite: 60000,
        linkPerSite: [1200, 3000, 6000, 12000], linkUpgradeOnce: [0, 2000, 5000, 30000],
        edgeDevice: 60000, edgeLife: 4, cloudFixed: 250000, cloudPerPatient: 1.0,
        graderFTE: 360000, ophthPerHour: 1500, van: 1500000 },
      target: { screensPerYear: 100000, routineP95Hours: 72, urgentP95Hours: 24, maxUtilisation: 0.85, programmeSensitivity: 0.90 }
    };
  }
  function rng(seed) {
    var a = seed >>> 0;
    function u() {
      a = (a + 0x6D2B79F5) >>> 0;
      var t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    var spare = null;
    function randn() {
      if (spare !== null) { var s = spare; spare = null; return s; }
      var x, y;
      do { x = u(); } while (x <= 0);
      y = u();
      var r = Math.sqrt(-2 * Math.log(x)), th = 2 * Math.PI * y;
      spare = r * Math.sin(th);
      return r * Math.cos(th);
    }
    function poisson(lam) {
      if (!(lam > 0)) { return 0; }
      if (lam < 30) {
        var L = Math.exp(-lam), p = 1, c = 0;
        for (;;) { p *= u(); if (p > L) { c++; } else { return c; } }
      }
      return Math.max(0, Math.round(lam + Math.sqrt(lam) * randn()));
    }
    function perm(n) {
      var arr = [];
      for (var i = 0; i < n; i++) { arr.push(i); }
      for (var j = n - 1; j > 0; j--) { var k = Math.floor(u() * (j + 1)); var t = arr[j]; arr[j] = arr[k]; arr[k] = t; }
      return arr;
    }
    return { u: u, randn: randn, poisson: poisson, perm: perm };
  }
  function erfc(x) {
    var z = Math.abs(x), t = 1 / (1 + 0.5 * z);
    var r = t * Math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
      t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 +
      t * (-0.82215223 + t * 0.17087277)))))))));
    return x >= 0 ? r : 2 - r;
  }
  function phi(z) { return 0.5 * erfc(-z / Math.SQRT2); }
  function phiinv(p) {
    var a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00];
    var b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01];
    var c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00];
    var d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00];
    var q, r;
    if (p < 0.02425) {
      q = Math.sqrt(-2 * Math.log(p));
      return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    }
    if (p > 1 - 0.02425) {
      q = Math.sqrt(-2 * Math.log(1 - p));
      return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    }
    q = p - 0.5; r = q * q;
    return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
  }
  function operatingCurve(P, targetSe) {
    var dd = Math.SQRT2 * phiinv(P.ai.auc);
    return { se: targetSe, sp: phi(dd - phiinv(targetSe)) };
  }
  function scenario(P, maxVans) {
    if (maxVans === undefined) { maxVans = 6; }
    var R = rng(P.seed);
    var dt = P.dt, T = Math.round(P.days * 24 / dt), Np = P.phc.count, N = Np + maxVans;
    var hour = new Float64Array(T), dow = new Uint8Array(T), month = new Uint8Array(T), day = new Int32Array(T);
    var maxDay = 0, k, i;
    for (k = 0; k < T; k++) {
      var t = (k + 0.5) * dt, dd = Math.floor(t / 24);
      day[k] = dd; hour[k] = t - 24 * dd; dow[k] = (dd % 7) + 1;
      month[k] = Math.min(12, Math.floor((dd % 365) / 30.42) + 1);
      if (dd > maxDay) { maxDay = dd; }
    }
    var nDays = maxDay + 1, holiday = new Uint8Array(nDays), cand = [];
    for (i = 0; i < nDays; i++) { if (i % 7 < 6) { cand.push(i); } }
    var nHol = Math.min(Math.round(P.phc.holidays * nDays / 364), cand.length), pm = R.perm(cand.length);
    for (i = 0; i < nHol; i++) { holiday[cand[pm[i]]] = 1; }
    var openPHC = new Uint8Array(T), closePHC = new Uint8Array(T), openVan = new Uint8Array(T), closeVan = new Uint8Array(T);
    var lamPHC = new Float64Array(T), lamVan = new Float64Array(T);
    var graderOn = new Uint8Array(T), ophthOn = new Uint8Array(T), vanUpload = new Uint8Array(T), phcUpload = new Uint8Array(T);
    var hoursOpen = P.phc.hours[1] - P.phc.hours[0], hoursVan = P.van.hours[1] - P.van.hours[0];
    for (k = 0; k < T; k++) {
      var h = hour[k], w = dow[k], hol = holiday[day[k]] === 1;
      openPHC[k] = (h >= P.phc.hours[0] && h < P.phc.hours[1] && w <= 6 && !hol) ? 1 : 0;
      closePHC[k] = (openPHC[k] && h + dt >= P.phc.hours[1]) ? 1 : 0;
      openVan[k] = (h >= P.van.hours[0] && h < P.van.hours[1] && w <= P.van.campDaysPerWeek && !hol) ? 1 : 0;
      closeVan[k] = (openVan[k] && h + dt >= P.van.hours[1]) ? 1 : 0;
      lamPHC[k] = openPHC[k] ? P.phc.demandPerDay / hoursOpen * dt * P.phc.weekday[w - 1] * P.season[month[k] - 1] : 0;
      lamVan[k] = openVan[k] ? P.van.demandPerCampDay / hoursVan * dt * P.season[month[k] - 1] : 0;
      graderOn[k] = (h >= P.review.graderHours[0] && h < P.review.graderHours[1] && P.review.graderDays.indexOf(w) >= 0 && !hol) ? 1 : 0;
      ophthOn[k] = (h >= P.review.ophthStart && w <= 5 && !hol) ? 1 : 0;
      vanUpload[k] = (h >= P.van.uploadHours[0] && h < P.van.uploadHours[1]) ? 1 : 0;
      phcUpload[k] = (h >= P.link.hours[0] && h < P.link.hours[1] && w <= 6) ? 1 : 0;
    }
    var arrivals = new Float64Array(T * N);
    for (i = 0; i < N; i++) {
      var lam = i < Np ? lamPHC : lamVan;
      for (k = 0; k < T; k++) { arrivals[k * N + i] = R.poisson(lam[k]); }
    }
    var linkU = new Float64Array(T * N);
    for (i = 0; i < N; i++) { for (k = 0; k < T; k++) { linkU[k * N + i] = R.u(); } }
    var mix = P.link.baselineMix, tot = mix.reduce(function (s, v) { return s + v; }, 0), counts = [], used = 0;
    for (i = 0; i < mix.length; i++) { counts.push(Math.round(mix[i] / tot * Np)); }
    for (i = 0; i < mix.length - 1; i++) { used += counts[i]; }
    counts[mix.length - 1] = Np - used;
    var tiers = [];
    for (i = 0; i < counts.length; i++) { for (var c = 0; c < counts[i]; c++) { tiers.push(i + 1); } }
    var tp = R.perm(Np), tierOfSite = new Uint8Array(Np);
    for (i = 0; i < Np; i++) { tierOfSite[i] = tiers[tp[i]]; }
    return { T: T, N: N, Np: Np, nVanMax: maxVans, dt: dt, hour: hour, dow: dow,
      openPHC: openPHC, closePHC: closePHC, openVan: openVan, closeVan: closeVan,
      arrivals: arrivals, linkU: linkU, graderOn: graderOn, ophthOn: ophthOn,
      vanUpload: vanUpload, phcUpload: phcUpload, tierOfSite: tierOfSite };
  }
  function Queue(buf) { this.q = buf; this.total = 0; }
  Queue.prototype.step = function (inflow, capacity, served, acc) {
    var q = this.q, B = q.length, b, inTot = 0;
    if (typeof inflow === 'number') { q[0] += inflow; inTot = inflow; }
    else { for (b = 0; b < B; b++) { if (inflow[b] !== 0) { q[b] += inflow[b]; inTot += inflow[b]; } } }
    if (this.total + inTot <= 1e-12) { this.total = 0; return 0; }
    var rem = capacity > 0 ? capacity : 0, out = 0;
    for (b = B - 1; b >= 0 && rem > 0; b--) {
      var v = q[b];
      if (v > 0) {
        var take = v < rem ? v : rem;
        q[b] = v - take; rem -= take; out += take;
        if (acc) { acc[b] += take; } else if (served) { served[b] = take; }
      }
    }
    var last = q[B - 1] + q[B - 2];
    for (b = B - 1; b >= 1; b--) { q[b] = q[b - 1]; }
    q[B - 1] = last; q[0] = 0;
    this.total = this.total + inTot - out;
    return out;
  };
  function quantile(h, ages, pct) {
    var s = 0, b;
    for (b = 0; b < h.length; b++) { s += h[b]; }
    if (s <= 0) { return 0; }
    var c = 0;
    for (b = 0; b < h.length; b++) { c += h[b] / s; if (c >= pct - 1e-12) { return ages[b]; } }
    return ages[h.length - 1];
  }
  function run(P, D, S) {
    var dt = P.dt, B = Math.round(P.maxAgeHours / dt), T = S.T, Np = S.Np, N = S.N, i, k, b;
    var active = new Uint8Array(N), isVan = new Uint8Array(N), tier = new Uint8Array(N);
    var pRepair = new Float64Array(N), pFail = new Float64Array(N), perStep = new Float64Array(N), cams = new Float64Array(N);
    for (i = 0; i < N; i++) {
      isVan[i] = i >= Np ? 1 : 0;
      active[i] = i < Np ? (i < D.phcEquipped ? 1 : 0) : (i - Np < D.vans ? 1 : 0);
      tier[i] = i < Np ? S.tierOfSite[i] : 4;
      if (D.linkTier > 0 && i < Np) { tier[i] = Math.max(tier[i], D.linkTier); }
      var A = P.link.availability[tier[i] - 1];
      pRepair[i] = Math.min(1, dt / P.link.meanOutageHours[tier[i] - 1]);
      pFail[i] = Math.min(1, pRepair[i] * (1 - A) / Math.max(A, 2.2e-16));
      perStep[i] = P.link.mbps[tier[i] - 1] * P.link.efficiency * 3600 * dt / 8 / P.images.mbPerPatient;
      cams[i] = isVan[i] ? 2 : P.capture.camerasPerPHC;
    }
    var mins = P.capture.minutesPerPatient + P.capture.ungradableFirst * P.capture.recaptureMinutes;
    var sec = P.review.secondsPerCase[D.reviewMode], secO = P.review.ophthSecondsPerCase[D.reviewMode];
    var oc = operatingCurve(P, D.sensitivity), se = oc.se, sp = oc.sp;
    var pi = P.mix.referable, piU = P.mix.urgent;
    var ung = P.capture.ungradableFirst * (1 - P.capture.recaptureSuccess), g = 1 - ung;
    var seU = Math.max(P.ai.urgentSensitivity, se);
    var fUrgent = g * piU * seU;
    var tpRoutine = g * Math.max(pi * se - piU * seU, 0);
    var fp = g * (1 - pi) * (1 - sp);
    var unc = g * P.ai.uncertainShare * ((1 - pi) * sp + pi * (1 - se));
    var fRoutine = tpRoutine + fp + unc + ung;
    var fAuto = Math.max(1 - fUrgent - fRoutine, 0);
    var fQA = P.review.qaShare * fAuto;
    var edge = D.aiMode === 'edge';
    var p2 = fUrgent, p3 = fRoutine, p4 = fAuto, p5 = fQA, p6 = P.ai.cloudPatientsPerHour * dt, p7 = P.review.adjudicate;
    var refInRoutine = (tpRoutine + g * P.ai.uncertainShare * pi * (1 - se)) / Math.max(fRoutine, 2.2e-16);
    var wait = new Float64Array(N), up = new Uint8Array(N), upBuf = new Float64Array(N * B), qUp = [];
    for (i = 0; i < N; i++) { up[i] = 1; qUp.push(new Queue(upBuf.subarray(i * B, (i + 1) * B))); }
    var qAI = new Queue(new Float64Array(B)), qU = new Queue(new Float64Array(B)), qR = new Queue(new Float64Array(B)),
      qQ = new Queue(new Float64Array(B)), qOU = new Queue(new Float64Array(B)), qOR = new Queue(new Float64Array(B));
    var H = [new Float64Array(B), new Float64Array(B), new Float64Array(B), new Float64Array(B)];
    var arrived = new Float64Array(B), inU = new Float64Array(B), inR = new Float64Array(B), inQ = new Float64Array(B),
      done = new Float64Array(B), doneU = new Float64Array(B), doneR = new Float64Array(B), doneQ = new Float64Array(B),
      doneOU = new Float64Array(B), doneOR = new Float64Array(B), toOR = new Float64Array(B);
    var totArr = 0, totCap = 0, totBalk = 0, casesG = 0, casesO = 0, sent = 0, gHours = 0, oHours = 0, upCapSum = 0;
    var usedO = 0, share = Math.max(p2 + p3 + p5, 2.2e-16);
    for (k = 0; k < T; k++) {
      var h = S.hour[k];
      if (h < dt) { usedO = 0; }
      var oh = S.ophthOn[k] ? Math.min(dt, Math.max(D.ophthHours - usedO, 0)) : 0;
      usedO += oh;
      var gh = D.graders * S.graderOn[k] * dt;
      gHours += gh; oHours += oh;
      var capG = gh * 3600 / sec, capO = oh * 3600 / secO;
      var sumCap = 0;
      arrived.fill(0);
      for (i = 0; i < N; i++) {
        if (!active[i]) { continue; }
        var open = isVan[i] ? S.openVan[k] : S.openPHC[k];
        var closing = isVan[i] ? S.closeVan[k] : S.closePHC[k];
        var a = S.arrivals[k * N + i];
        totArr += a;
        var w = wait[i] + a;
        var c = open ? Math.min(w, cams[i] * 60 * dt / mins) : 0;
        w -= c;
        if (closing) { totBalk += w; wait[i] = 0; } else { wait[i] = w; }
        sumCap += c;
        var uu = S.linkU[k * N + i];
        up[i] = ((up[i] && uu >= pFail[i]) || (!up[i] && uu < pRepair[i])) ? 1 : 0;
        var win = isVan[i] ? S.vanUpload[k] : S.phcUpload[k];
        var cap = up[i] * win * perStep[i];
        upCapSum += cap;
        var toUp = edge ? c * (p2 + p3 + p5) : c;
        sent += qUp[i].step(toUp, cap, null, arrived);
      }
      totCap += sumCap;
      var autoNow = edge ? sumCap * p4 : 0;
      if (edge) {
        for (b = 0; b < B; b++) { var ab = arrived[b]; inU[b] = ab * p2 / share; inR[b] = ab * p3 / share; inQ[b] = ab * p5 / share; }
      } else {
        done.fill(0);
        qAI.step(arrived, p6, done, null);
        for (b = 0; b < B; b++) { inU[b] = done[b] * p2; inR[b] = done[b] * p3; inQ[b] = done[b] * p5; }
      }
      doneU.fill(0); doneR.fill(0); doneQ.fill(0);
      var nU = qU.step(inU, capG, doneU, null);
      var nR = qR.step(inR, capG - nU, doneR, null);
      var nQ = qQ.step(inQ, capG - nU - nR, doneQ, null);
      casesG += nU + nR + nQ;
      doneOU.fill(0); doneOR.fill(0);
      for (b = 0; b < B; b++) { toOR[b] = doneR[b] * p7; }
      var nOU = qOU.step(doneU, capO, doneOU, null);
      var nOR = qOR.step(toOR, capO - nOU, doneOR, null);
      casesO += nOU + nOR;
      H[0][0] += autoNow;
      for (b = 0; b < B; b++) {
        if (!edge) { H[0][b] += done[b] * p4; }
        H[1][b] += doneR[b] * (1 - p7) + doneOR[b];
        H[2][b] += doneU[b];
        H[3][b] += doneOU[b];
      }
    }
    var ages = new Float64Array(B);
    for (b = 0; b < B; b++) { ages[b] = (b + 0.5) * dt; }
    function sum(hh) { var s = 0; for (var j = 0; j < hh.length; j++) { s += hh[j]; } return s; }
    var K = {};
    K.screened = totCap; K.unserved = totBalk;
    K.turnaround = { routineP50: quantile(H[1], ages, 0.5), routineP95: quantile(H[1], ages, 0.95), urgentP95: quantile(H[2], ages, 0.95) };
    K.urgentNoticeP95 = K.turnaround.urgentP95;
    if (edge && P.referral.provisionalOnSite) { K.urgentNoticeP95 = P.ai.edgeSecondsPerPatient / 3600; }
    K.utilisation = {
      graders: (casesG * sec / 3600) / Math.max(gHours, 2.2e-16),
      ophthalmologist: (casesO * secO / 3600) / Math.max(oHours, 2.2e-16),
      uplink: sent / Math.max(upCapSum, 2.2e-16)
    };
    K.programmeSensitivity = se + (1 - se) * P.review.qaShare;
    K.missedReferable = K.screened * g * pi * (1 - K.programmeSensitivity);
    var uOn = P.referral.uptakeOnSite, uLate = P.referral.uptakeDelayed, uptakeU, uptakeR;
    if (edge && P.referral.provisionalOnSite) { uptakeU = uOn; uptakeR = uOn; }
    else {
      var su = 0, sr = 0;
      for (b = 0; b < B; b++) {
        var wt = uLate + (uOn - uLate) * Math.exp(-ages[b] / P.referral.presenceHours);
        su += H[2][b] * wt; sr += H[1][b] * wt;
      }
      uptakeU = su / Math.max(sum(H[2]), 2.2e-16);
      uptakeR = sr / Math.max(sum(H[1]), 2.2e-16);
    }
    K.reachingTreatment = sum(H[2]) * uptakeU + sum(H[1]) * refInRoutine * uptakeR;
    var f = 364 / P.days;
    K.perYear = { screened: f * K.screened, reachingTreatment: f * K.reachingTreatment, unserved: f * K.unserved };
    var cc = P.cost, nPHC = 0, nVan = 0, links = 0, upgrades = 0;
    for (i = 0; i < N; i++) {
      if (!active[i]) { continue; }
      if (isVan[i]) { nVan++; } else { nPHC++; links += cc.linkPerSite[tier[i] - 1]; upgrades += cc.linkUpgradeOnce[tier[i] - 1]; }
    }
    var camsN = nPHC * P.capture.camerasPerPHC + 2 * nVan;
    var C = {
      cameras: camsN * (cc.camera / cc.cameraLife + cc.camera * cc.cameraUpkeep),
      technicians: nPHC * cc.technicianPerSite,
      links: links + upgrades / 5,
      ai: edge ? (nPHC + nVan) * cc.edgeDevice / cc.edgeLife : cc.cloudFixed + cc.cloudPerPatient * K.screened * f,
      graders: D.graders * cc.graderFTE,
      ophthalmologist: D.ophthHours * 250 * cc.ophthPerHour,
      vans: nVan * cc.van
    };
    C.total = C.cameras + C.technicians + C.links + C.ai + C.graders + C.ophthalmologist + C.vans;
    K.cost = C;
    K.costPerScreen = C.total / Math.max(K.perYear.screened, 1);
    K.constraints = {
      screens: K.perYear.screened - P.target.screensPerYear,
      routineP95: P.target.routineP95Hours - K.turnaround.routineP95,
      urgentP95: P.target.urgentP95Hours - K.urgentNoticeP95,
      graderLoad: P.target.maxUtilisation - K.utilisation.graders,
      ophthLoad: P.target.maxUtilisation - K.utilisation.ophthalmologist,
      sensitivity: K.programmeSensitivity - P.target.programmeSensitivity
    };
    K.feasible = Object.keys(K.constraints).every(function (key) { return K.constraints[key] >= 0; });
    return { kpi: K, maxAge: P.maxAgeHours };
  }
  return { defaults: defaults, scenario: scenario, run: run };
})();
if (typeof module !== 'undefined' && module.exports) { module.exports = NetraSim; }
