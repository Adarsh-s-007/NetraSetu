/* =========================================================================
   NetraSetu screening app: patient intake and fundus photograph, the
   on-device check (engine.js, run in a Web Worker), the diagnostic
   workstation, the review queue with the 30-second review, the district
   planner (sim.js) and the evidence tab. The preloaded example study is
   case.js with its images in img/case/.
   ========================================================================= */
(function () {
  'use strict';

  function $(s, r) { return (r || document).querySelector(s); }
  function $$(s, r) { return Array.prototype.slice.call((r || document).querySelectorAll(s)); }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) { e.className = cls; }
    if (text !== undefined && text !== null) { e.textContent = text; }
    return e;
  }
  function btn(cls, text, onClick) {
    var b = el('button', cls, text);
    b.type = 'button';
    if (onClick) { b.addEventListener('click', onClick); }
    return b;
  }
  var SVGNS = 'http://www.w3.org/2000/svg';
  function svg(tag, attrs) {
    var e = document.createElementNS(SVGNS, tag);
    Object.keys(attrs || {}).forEach(function (k) { e.setAttribute(k, attrs[k]); });
    return e;
  }
  function icon(id) { var s = svg('svg', { class: 'ico', 'aria-hidden': 'true' }); s.append(svg('use', { href: '#' + id })); return s; }
  function canvasOf(w, h) { var c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }
  function pad(n, k) { var s = String(n); while (s.length < k) { s = '0' + s; } return s; }
  function txt(s) { return document.createTextNode(s); }

  /* ================================================================ words */
  // Hindi for every element marked data-t; English stays in the markup.
  var HI = {
    'app.sub': 'स्वास्थ्य केंद्र पर डायबिटिक रेटिनोपैथी स्क्रीनिंग',
    'tab.screen': 'स्क्रीनिंग', 'tab.review': 'समीक्षा कतार', 'tab.district': 'ज़िला योजना', 'tab.evidence': 'प्रमाण',
    'tab.screenS': 'स्क्रीनिंग', 'tab.reviewS': 'समीक्षा', 'tab.districtS': 'ज़िला', 'tab.evidenceS': 'प्रमाण',
    'app.local': 'इसी डिवाइस पर · कोई अपलोड नहीं',
    'scr.title': 'मरीज़ की जाँच करें', 'scr.sub': 'मरीज़ का विवरण दर्ज करें, फ़ंडस फ़ोटो जोड़ें और जाँचें।', 'scr.credit': 'अरविंद आई केयर सिस्टम।',
    'pt.title': 'मरीज़ का रिकॉर्ड', 'pt.example': 'उदाहरण मरीज़', 'pt.id': 'मरीज़ आईडी', 'pt.age': 'आयु (वर्ष)', 'pt.sex': 'लिंग',
    'pt.f': 'महिला', 'pt.m': 'पुरुष', 'pt.o': 'अन्य', 'pt.eye': 'किस आँख की फ़ोटो', 'pt.od': 'दाईं आँख (OD)', 'pt.os': 'बाईं आँख (OS)',
    'pt.dm': 'डायबिटीज़ (वर्ष)', 'pt.a1c': 'HbA1c (%)', 'pt.phc': 'स्वास्थ्य केंद्र',
    'acq.title': 'फ़ंडस फ़ोटो', 'acq.mod': 'रंगीन फ़ंडस · 45°', 'acq.drop': 'फ़ंडस फ़ोटो यहाँ छोड़ें, या चुनने के लिए टैप करें',
    'acq.hint': 'JPEG, PNG या WebP। जाँच इसी डिवाइस पर होती है; कुछ भी अपलोड नहीं होता।', 'acq.replace': 'बदलने के लिए टैप करें',
    'acq.tests': 'परीक्षण छवियाँ (कृत्रिम)', 'acq.go': 'गुणवत्ता जाँचें और स्क्रीन करें', 'acq.ready': 'फ़ोटो लोड हुई',
    'step.1': 'गुणवत्ता', 'step.2': 'शरीर-रचना', 'step.3': 'घाव', 'step.4': 'ग्रेडिंग', 'step.5': 'व्याख्या',
    'ws.title': 'निदान वर्कस्टेशन', 'sum.title': 'स्वचालित निष्कर्ष', 'prob.title': 'ICDR ग्रेड की संभावनाएँ', 'prob.tag': 'घाव-प्रमाण के 256 नमूने',
    'fl.title': 'खोजें', 'fl.tag': 'स्थान देखने के लिए टैप करें', 'fu.title': 'आगे की देखभाल',
    'rv.h': 'समीक्षा कतार', 'rv.sub': 'हर जाँची गई आँख यहाँ ग्रेडर की प्रतीक्षा करती है। लक्ष्य: हर एक 30 सेकंड से कम में।',
    'rv.c1': 'अध्ययन', 'rv.c2': 'मरीज़', 'rv.c3': 'केंद्र', 'rv.c4': 'AI ट्राइएज', 'rv.c5': 'ICDR', 'rv.c6': 'स्थिति', 'rv.c7': 'समीक्षा समय',
    'd.credit': 'स्क्रीनिंग वैन के अंदर फ़ंडस जाँच, भारत। फ़ोटो: आर. डी. रविंद्रन,', 'd.h': 'ज़िला योजना', 'd.sub': '36 स्वास्थ्य केंद्रों के लिए एक सिम्युलेटेड साल। संसाधन बदलें; हर लक्ष्य जाँचा जाता है।',
    'm.g1': 'फ़ोटो लेना', 'm.phc': 'कैमरे वाले स्वास्थ्य केंद्र', 'm.vans': 'मोबाइल स्क्रीनिंग वैन', 'm.g2': 'बैंडविड्थ', 'm.l0': 'आज का मिश्रण', 'm.l4': 'ब्रॉडबैंड',
    'm.g3': 'प्रोसेसिंग', 'm.edge': 'केंद्र पर', 'm.cloud': 'क्लाउड', 'm.g4': 'समीक्षा-क्षमता', 'm.graders': 'ग्रेडर', 'm.oph': 'नेत्र-चिकित्सक, घंटे प्रतिदिन',
    'm.xaiY': 'व्याख्या वाली रिपोर्ट: 30 सेकंड', 'm.xaiN': 'सादी: 150 सेकंड', 'm.g5': 'योजनाएँ', 'm.sl': 'Simulink मॉडल',
    'm.v': 'Simulink ब्लॉक-कोड एक सिम्युलेटेड साल में MATLAB संदर्भ से बिट-दर-बिट मेल खाता है; यह ब्राउज़र संस्करण MATLAB योजना को सैंपलिंग-शोर के भीतर दोहराता है।',
    'e.h': 'प्रमाण', 'e.sub': 'बेंचमार्क, क्या सत्यापित है, और डेटासेट क्या मापेंगे।',
    'e.pending': '<b>क्लिनिकल सटीकता अभी मापी नहीं गई है।</b> इसके लिए लाइसेंस वाले डेटासेट (Messidor-2, IDRiD, APTOS, DRIVE) और MATLAB प्रयोग चाहिए।',
    'e.chart': 'लक्ष्य के सामने प्रकाशित प्रणालियाँ', 'e.lgT': 'लक्ष्य: Se &gt; 90%, Sp &gt; 85%', 'e.lgS': 'स्क्रीनिंग मानक', 'e.lgV': 'स्रोत से जाँचना है',
    'e.brief': 'समस्या-विवरण की पूर्ति', 'e.b1': 'गुणवत्ता और सुधार', 'e.b1w': 'गुणवत्ता कार्ड, दोबारा फ़ोटो की सलाह, सुधारा गया दृश्य',
    'e.b2': 'संरचनाएँ और घाव', 'e.b2w': 'मार्कर, रूपरेखा, नसें, ग्रिड, खोजें', 'e.b3': 'ICDR ग्रेडिंग', 'e.b3w': 'ग्रेड की संभावनाएँ, रेफ़रल फ़ैसला',
    'e.b4': 'व्याख्या', 'e.b4w': 'प्रमाण-मानचित्र, रिपोर्ट, 30 सेकंड की समीक्षा', 'e.b5': 'Simulink योजना', 'e.b5w': 'ज़िला योजना', 'e.b6': 'सत्यापन', 'e.b6w': 'यह पृष्ठ',
    'e.v1': '50/50 स्वचालित परीक्षण पास', 'e.v1r': 'GNU Octave में, हर बदलाव पर', 'e.v2': 'माइक्रोएन्यूरिज़्म के केंद्र क्रैमर–राव सीमा पर', 'e.v2r': 'SNR 8 पर 0.15 px',
    'e.v3': 'Simulink अपने MATLAB संदर्भ से हूबहू मेल खाता है', 'e.v3r': '8,736 घंटेवार चरण, 48 KPI',
    'e.proto': 'सत्यापन प्रोटोकॉल', 'e.x1': 'प्रयोग', 'e.x2': 'मापता है',
    'e.p1': 'DRIVE पर नसें: जुड़े डिटेक्टर बनाम हर अकेला', 'e.p2': 'IDRiD पर घाव, ऑप्टिक डिस्क और फ़ोविया', 'e.p3': 'APTOS पर प्रशिक्षण और कैलिब्रेशन',
    'e.p4': 'IDRiD और Messidor-2 पर Se, Sp, AUC; पूरी पाइपलाइन बनाम अकेली तकनीक (DeLong, McNemar)', 'e.p5': 'क्या व्याख्याएँ घावों की ओर इशारा करती हैं?',
    'e.p6': 'हर लक्ष्य पूरा करने वाली सबसे सस्ती ज़िला योजना', 'e.pub': 'सभी 70 प्रकाशित परिणाम',
    'foot.1': 'शोध-सॉफ़्टवेयर, चिकित्सा उपकरण नहीं। हर रेफ़रल की पुष्टि प्रशिक्षित ग्रेडर करते हैं। परीक्षण छवियाँ कृत्रिम हैं; उदाहरण मरीज़ काल्पनिक है।',
    'foot.2': 'MATLAB · Simulink · डिवाइस पर इंजन'
  };

  // strings built by script
  var W = {
    en: {
      'ts.eye': 'ICDR {g}', 'ts.defocus': 'Blurry', 'ts.dark': 'Dark', 'ts.lashes': 'Eyelash', 'ts.flare': 'Flare',
      'in.eye': 'Practice eye, made at ICDR {g}', 'in.cap': 'Practice photo: {name}', 'in.synth': 'synthetic', 'in.px': '{w} × {h} px',
      'cap.sharp': 'well exposed', 'cap.defocus': 'out of focus', 'cap.dark': 'under-exposed', 'cap.lashes': 'eyelash shadow', 'cap.flare': 'flare at the rim',
      'err.engine': 'The check could not be completed. Try again, or use another photograph.',
      'err.file': 'This file could not be opened as an image. Use a JPEG, PNG or WebP photograph.',
      'tri.ROUTINE': 'ROUTINE', 'tri.REFER': 'REFER', 'tri.REFER_DME': 'REFER · MACULA', 'tri.URGENT': 'URGENT', 'tri.HUMAN_REVIEW': 'SPECIALIST REVIEW', 'tri.RECAPTURE': 'RETAKE',
      'fu.ROUTINE': 'Re-screen in 12 months', 'fu.REFER': 'Ophthalmologist within 4 weeks', 'fu.REFER_DME': 'Ophthalmologist within 2 weeks (macular oedema risk)',
      'fu.URGENT': 'Ophthalmologist within 1 week', 'fu.HUMAN_REVIEW': 'Specialist review of the images within 48 hours', 'fu.RECAPTURE': 'Retake the photograph now',
      'rs.pRef': 'P(referable) {v} ≥ {t}', 'rs.low': 'P(referable) {v} < {t}', 'rs.dme': 'Exudate within 1 DD of the fovea', 'rs.centre': 'Exudate near the foveal centre',
      'rs.nvprh': 'New vessels or pre-retinal haemorrhage', 'rs.pUrgent': 'P(proliferative) {v}', 'rs.borderline': 'Borderline quality {v}', 'rs.quality': 'Quality {v}',
      'flag.disc-uncertain': 'Optic disc uncertain', 'flag.fovea-uncertain': 'Fovea uncertain', 'flag.geometry-implausible': 'Disc–fovea distance implausible',
      'fs.blur': 'Out of focus', 'fs.dark': 'Too dark', 'fs.bright': 'Over-exposed', 'fs.field': 'Retina not fully in view', 'fs.contrast': 'Low contrast',
      'fs.artifact': 'Shadow or reflection at the edge', 'fs.none': 'Not a fundus photograph',
      'act.review': 'Open in review queue', 'act.new': 'New patient', 'act.retake': 'Choose another photo',
      'eye.R': 'right', 'eye.L': 'left', 'Eye.R': 'Right', 'Eye.L': 'Left', 'side.R': 'on the right', 'side.L': 'on the left',
      'mm.text': 'The optic disc is {side} of the image, which suggests the {eye} eye; the record says {rec} eye.', 'mm.fix': 'Record as {eye} eye',
      'ws.example': 'example',
      'vw.raw': 'Colour', 'vw.redfree': 'Red-free', 'vw.enhanced': 'Enhanced',
      'tg.evidence': 'Evidence map', 'tg.markers': 'Markers', 'tg.outlines': 'Outlines', 'tg.vessels': 'Vessels', 'tg.anatomy': 'Disc and grid', 'tg.opacity': 'Evidence map opacity',
      'zm.in': 'Zoom in', 'zm.out': 'Zoom out', 'zm.fit': 'Fit to view',
      'hud.mod': 'Colour fundus · 45°', 'hud.age': '{a} y', 'hud.quad': 'Lesions by quadrant', 'hud.um': '{v} µm/px',
      'sx.F': 'F', 'sx.M': 'M', 'sx.O': 'Other',
      'lt.ma': 'Microaneurysm', 'lt.he': 'Haemorrhage', 'lt.ex': 'Hard exudate', 'lt.cws': 'Cotton-wool spot', 'lt.nv': 'New vessels',
      'hs.dot': 'dot', 'hs.blot': 'blot', 'hs.flame': 'flame', 'hs.preretinal': 'pre-retinal', 'nvs.NVD': 'on the disc (NVD)', 'nvs.NVE': 'elsewhere (NVE)',
      'qd.1': 'superior temporal', 'qd.2': 'superior nasal', 'qd.3': 'inferior nasal', 'qd.4': 'inferior temporal',
      'tp.conf': 'confidence {v}', 'tp.dist': '{d} DD from the fovea', 'tp.score': 'score {v}', 'tp.quad': '{q} quadrant',
      'lg.hint': 'Double-click or + to zoom · drag to move',
      'ws.notGraded': 'Not graded: retake the photograph',
      'sm.who': '{Eye} eye of a {age}-year-old {sexw}', 'sm.eye': '{Eye} eye', 'sm.dm': ', diabetic for {n} years', 'sm.a1c': ', HbA1c {v}%', 'sm.end': '.',
      'sxw.F': 'woman', 'sxw.M': 'man', 'sxw.O': 'person',
      'sm.q': 'Image quality {v} ({d}).', 'sm.found': 'Found {list}.', 'sm.nothing': 'No lesion was found.',
      'sm.where': 'Most lesions are in the {q} quadrant.', 'sm.ex': 'The nearest hard exudate is {d} disc diameters from the fovea.',
      'sm.grade': 'Most likely ICDR level {g}, {name} ({p}); chance of referable DR {r}.',
      'sm.retake': 'The photograph could not be graded: {why}.', 'sm.and': ' and ', 'sm.comma': ', ',
      'l.ma': '{n} microaneurysms', 'l.ma1': '1 microaneurysm', 'l.he': '{n} haemorrhages ({parts})', 'l.he1': '1 haemorrhage ({parts})',
      'l.ex': '{n} hard exudates', 'l.ex1': '1 hard exudate', 'l.cws': '{n} cotton-wool spots', 'l.cws1': '1 cotton-wool spot',
      'l.nv': '{n} new-vessel regions', 'l.nv1': '1 new-vessel region',
      'hp.dot': '{n} dot', 'hp.blot': '{n} blot', 'hp.flame': '{n} flame', 'hp.preretinal': '{n} pre-retinal',
      'qc.title': 'Image quality', 'q.GRADABLE': 'Gradable', 'q.ENHANCE': 'Borderline', 'q.RECAPTURE': 'Retake', 'q.after': 'Gradable after enhancement',
      'q.sub.field': 'Field of view', 'q.sub.focus': 'Focus', 'q.sub.illumination': 'Illumination', 'q.sub.contrast': 'Contrast', 'q.sub.artifact': 'Artefacts',
      'qc.enh': 'Enhanced before grading: {a} → {b}', 'qc.rule': 'Weighted mean of five checks. Gradable at 0.60, with every check at 0.50 or more.',
      'qc.retake': 'Retake the photograph', 'qc.noField': 'No circular fundus field was found.',
      'fb.blur': 'Out of focus: clean the lens, ask the patient to keep still, refocus on the vessels at the disc.',
      'fb.dark': 'Too dark: dim the room lights, let the pupil enlarge, or increase the flash.',
      'fb.bright': 'Over-exposed or glare: reduce the flash and realign the camera with the pupil centre.',
      'fb.field': 'Retina not fully in view: centre the pupil and ask the patient to look at the fixation light.',
      'fb.contrast': 'Low contrast (dirty lens or possible cataract): clean the lens and retake; if it persists, refer for a dilated eye examination.',
      'fb.artifact': 'Shadow or reflection at the edge: ask the patient to open the eye wide and hold the camera steady.',
      'fb.none': 'No circular fundus field was found. This does not appear to be a fundus photograph.',
      'lv.0': 'No apparent retinopathy', 'lv.1': 'Mild NPDR', 'lv.2': 'Moderate NPDR', 'lv.3': 'Severe NPDR', 'lv.4': 'Proliferative DR',
      'lv.s0': 'None', 'lv.s1': 'Mild', 'lv.s2': 'Moderate', 'lv.s3': 'Severe', 'lv.s4': 'Proliferative',
      'pb.ref': 'Chance of referable DR', 'pb.thr': 'referral threshold {v}',
      'fl.none': 'No lesion found in this image.',
      'fd.due': 'Due {d}', 'fd.today': 'Today', 'ad.a1c': 'HbA1c {v}% is above the 7% target: review diabetes control with the doctor.',
      'msg.title': 'Message for the patient', 'msg.copy': 'Copy', 'msg.copied': 'Copied', 'msg.sel': 'Selected: press Ctrl+C',
      'pm.ROUTINE': 'No referable diabetic retinopathy found. Re-screen in 12 months and keep blood sugar under control.',
      'pm.REFER': 'Referable diabetic retinopathy suspected. Please see an eye specialist within 4 weeks.',
      'pm.REFER_DME': 'Diabetic eye changes close to the centre of vision (macula) suspected. Please see an eye specialist within 2 weeks.',
      'pm.URGENT': 'Signs of advanced (proliferative) diabetic retinopathy. See an eye specialist within 1 week.',
      'pm.HUMAN_REVIEW': 'Your photograph is being checked by an eye specialist. You will be contacted within 48 hours.',
      'pm.RECAPTURE': 'The photograph was not clear enough. A new photograph is needed.', 'pm.by': 'Please come by {d}.',
      'st.n': 'Studies', 'st.wait': 'Awaiting review', 'st.med': 'Median review time', 'st.u30': 'Reviewed within 30 s',
      'ss.wait': 'Awaiting review', 'ss.ok': 'Confirmed', 'ss.chg': 'Changed to {g}', 'ss.ungr': 'Ungradable',
      'rp.title': '30-second review', 'rp.none': 'Screen a patient to add a study.', 'rp.ai': 'ICDR {g} · {p} referable',
      'rp.start': 'Start review', 'rp.confirm': 'Confirm: {d}', 'rp.set': 'Or set the ICDR level', 'rp.ungr': 'Ungradable: retake',
      'rp.ok': 'Confirmed in {s} s.', 'rp.chg': 'Changed to level {g} in {s} s.', 'rp.ungrD': 'Marked ungradable in {s} s.', 'rp.again': 'Review again',
      'rp.keys': 'Keys: Enter confirms, 0–4 sets the level, U marks ungradable.',
      'rp.console': 'The MATLAB Reader Console (netra.ui.ReaderConsole) does the same with keyboard shortcuts and writes an audit log.',
      'r.head': 'Diabetic retinopathy screening report', 'r.study': 'Study {id}', 'r.device': 'Screened on device', 'r.p': 'Probability of each ICDR level', 'r.find': 'Findings',
      'r.count': 'Count', 'r.qual': 'Image quality', 'r.crit': 'Criteria met', 'r.none': 'No criterion met',
      'r.disc': 'Research software, not a medical device. A trained grader or ophthalmologist confirms every referral.',
      'r.sign': 'Reviewed by', 'r.ma': 'Microaneurysms', 'r.he': 'Haemorrhages', 'r.ex': 'Hard exudates', 'r.cws': 'Cotton-wool spots',
      'r.nv': 'New-vessel regions', 'r.lm': 'Landmarks', 'r.lmV': 'disc {d}, fovea {f}', 'r.q': '{s} · {d}',
      'r.pid': 'Patient {id}', 'r.age': '{a} y', 'r.dm': 'diabetes {n} y', 'r.a1c': 'HbA1c {v}%', 'r.eyeRec': '{e} eye', 'r.done': 'Grader review: {what}',
      'cr.ma': 'Microaneurysms', 'cr.he': 'Intraretinal haemorrhages', 'cr.ex': 'Hard exudates', 'cr.cws': 'Cotton-wool spots', 'cr.he4q': 'Quadrants with 10 or more haemorrhages',
      'cr.nv': 'New vessels, probability ({w})', 'cr.prh': 'Pre-retinal haemorrhage',
      'sim.ok': 'This plan meets every target', 'sim.no': 'This plan misses {n} of 6 targets',
      'k.screened': 'People screened per year', 'k.routine': 'Routine reports ready (95th percentile)', 'k.urgent': 'Urgent cases notified (95th percentile)',
      'k.graders': 'Grader workload', 'k.oph': 'Ophthalmologist workload', 'k.sens': 'Programme sensitivity', 'k.uplink': 'Upload link use', 'k.treat': 'People reaching treatment per year',
      'k.missed': 'Referable cases missed per year', 'k.cost': 'Cost per person screened', 'k.total': 'Annual cost', 'k.target': 'target {v}',
      'h': 'h', 'onsite': 'At capture',
      'c.title': 'Where the money goes', 'c.cameras': 'Cameras', 'c.technicians': 'Technicians', 'c.links': 'Network links', 'c.ai': 'AI (devices or cloud)', 'c.graders': 'Graders',
      'c.ophthalmologist': 'Ophthalmologist', 'c.vans': 'Vans', 'c.lakh': '₹{v} lakh',
      'sim.note': 'Each plan is one simulated year with the same patients, about 0.2 s per run. Assumptions are in netra.sim.defaults and can be replaced with local data.',
      'p.best': 'Optimised plan', 'p.noxai': 'Without explained reports', 'p.cloud': 'Cloud grading', 'p.g2': '2G links, cloud grading', 'p.all': 'Every centre, more staff',
      'bm.tab.referable-dr': 'Referable DR', 'bm.tab.vessels': 'Vessels (DRIVE)', 'bm.tab.lesion-seg': 'Lesions (IDRiD)', 'bm.tab.landmarks': 'Landmarks (IDRiD)',
      'bm.tab.dr-grading': 'Five-level grading', 'bm.tab.standard': 'Standards and targets',
      'bm.no': '#', 'bm.ds': 'Dataset', 'bm.me': 'Method', 'bm.n': 'n', 'bm.src': 'Source', 'bm.verify': 'check against source',
      'ch.x': 'Specificity', 'ch.y': 'Sensitivity', 'ch.bda1': 'BDA / Exeter', 'ch.bda2': 'minimum', 'ch.fda': 'FDA pivotal endpoints'
    },
    hi: {
      'ts.eye': 'ICDR {g}', 'ts.defocus': 'धुंधली', 'ts.dark': 'गहरी', 'ts.lashes': 'बरौनी', 'ts.flare': 'चमक',
      'in.eye': 'अभ्यास आँख, ICDR {g} पर बनाई गई', 'in.cap': 'अभ्यास फ़ोटो: {name}', 'in.synth': 'कृत्रिम', 'in.px': '{w} × {h} px',
      'cap.sharp': 'सही रोशनी', 'cap.defocus': 'फ़ोकस से बाहर', 'cap.dark': 'कम रोशनी', 'cap.lashes': 'बरौनियों की छाया', 'cap.flare': 'किनारे पर चमक',
      'err.engine': 'जाँच पूरी नहीं हो सकी। फिर कोशिश करें, या दूसरी फ़ोटो लें।',
      'err.file': 'यह फ़ाइल छवि के रूप में नहीं खुली। JPEG, PNG या WebP फ़ोटो लें।',
      'tri.ROUTINE': 'नियमित', 'tri.REFER': 'रेफ़र', 'tri.REFER_DME': 'रेफ़र · मैक्युला', 'tri.URGENT': 'तत्काल', 'tri.HUMAN_REVIEW': 'विशेषज्ञ समीक्षा', 'tri.RECAPTURE': 'दोबारा फ़ोटो',
      'fu.ROUTINE': '12 महीने बाद फिर जाँच', 'fu.REFER': '4 सप्ताह के भीतर नेत्र-चिकित्सक', 'fu.REFER_DME': '2 सप्ताह के भीतर नेत्र-चिकित्सक (मैक्युलर एडिमा का जोखिम)',
      'fu.URGENT': '1 सप्ताह के भीतर नेत्र-चिकित्सक', 'fu.HUMAN_REVIEW': '48 घंटे के भीतर विशेषज्ञ द्वारा छवियों की समीक्षा', 'fu.RECAPTURE': 'अभी दोबारा फ़ोटो लें',
      'rs.pRef': 'P(रेफ़र करने योग्य) {v} ≥ {t}', 'rs.low': 'P(रेफ़र करने योग्य) {v} < {t}', 'rs.dme': 'फ़ोविया के 1 DD के भीतर एक्सयूडेट', 'rs.centre': 'फ़ोविया के केंद्र के पास एक्सयूडेट',
      'rs.nvprh': 'नई नलिकाएँ या प्री-रेटिनल रक्तस्राव', 'rs.pUrgent': 'P(प्रोलिफ़ेरेटिव) {v}', 'rs.borderline': 'सीमांत गुणवत्ता {v}', 'rs.quality': 'गुणवत्ता {v}',
      'flag.disc-uncertain': 'ऑप्टिक डिस्क अनिश्चित', 'flag.fovea-uncertain': 'फ़ोविया अनिश्चित', 'flag.geometry-implausible': 'डिस्क–फ़ोविया दूरी असंभव',
      'fs.blur': 'फ़ोकस से बाहर', 'fs.dark': 'बहुत गहरी', 'fs.bright': 'बहुत ज़्यादा रोशनी', 'fs.field': 'रेटिना पूरा नहीं दिखता', 'fs.contrast': 'कम कंट्रास्ट',
      'fs.artifact': 'किनारे पर छाया या चमक', 'fs.none': 'फ़ंडस फ़ोटो नहीं',
      'act.review': 'समीक्षा कतार में खोलें', 'act.new': 'नया मरीज़', 'act.retake': 'दूसरी फ़ोटो चुनें',
      'eye.R': 'दाईं', 'eye.L': 'बाईं', 'Eye.R': 'दाईं', 'Eye.L': 'बाईं', 'side.R': 'दाईं ओर', 'side.L': 'बाईं ओर',
      'mm.text': 'ऑप्टिक डिस्क छवि में {side} है, जो {eye} आँख का संकेत है; रिकॉर्ड में {rec} आँख दर्ज है।', 'mm.fix': '{eye} आँख दर्ज करें',
      'ws.example': 'उदाहरण',
      'vw.raw': 'रंगीन', 'vw.redfree': 'रेड-फ़्री', 'vw.enhanced': 'सुधारी गई',
      'tg.evidence': 'प्रमाण-मानचित्र', 'tg.markers': 'मार्कर', 'tg.outlines': 'रूपरेखा', 'tg.vessels': 'नसें', 'tg.anatomy': 'डिस्क और ग्रिड', 'tg.opacity': 'प्रमाण-मानचित्र की पारदर्शिता',
      'zm.in': 'ज़ूम इन', 'zm.out': 'ज़ूम आउट', 'zm.fit': 'पूरा दिखाएँ',
      'hud.mod': 'रंगीन फ़ंडस · 45°', 'hud.age': '{a} वर्ष', 'hud.quad': 'चतुर्थांश अनुसार घाव', 'hud.um': '{v} µm/px',
      'sx.F': 'महिला', 'sx.M': 'पुरुष', 'sx.O': 'अन्य',
      'lt.ma': 'माइक्रोएन्यूरिज़्म', 'lt.he': 'रक्तस्राव', 'lt.ex': 'हार्ड एक्सयूडेट', 'lt.cws': 'कॉटन-वूल धब्बा', 'lt.nv': 'नई नलिकाएँ',
      'hs.dot': 'डॉट', 'hs.blot': 'ब्लॉट', 'hs.flame': 'फ़्लेम', 'hs.preretinal': 'प्री-रेटिनल', 'nvs.NVD': 'डिस्क पर (NVD)', 'nvs.NVE': 'अन्यत्र (NVE)',
      'qd.1': 'ऊपरी टेम्पोरल', 'qd.2': 'ऊपरी नेज़ल', 'qd.3': 'निचला नेज़ल', 'qd.4': 'निचला टेम्पोरल',
      'tp.conf': 'विश्वास {v}', 'tp.dist': 'फ़ोविया से {d} DD', 'tp.score': 'अंक {v}', 'tp.quad': '{q} चतुर्थांश',
      'lg.hint': 'ज़ूम के लिए डबल-क्लिक या + · खिसकाने के लिए खींचें',
      'ws.notGraded': 'ग्रेड नहीं हुई: फ़ोटो दोबारा लें',
      'sm.who': '{age} वर्षीय {sexw} की {eye} आँख', 'sm.eye': '{eye} आँख', 'sm.dm': ', {n} वर्ष से डायबिटीज़', 'sm.a1c': ', HbA1c {v}%', 'sm.end': '।',
      'sxw.F': 'महिला', 'sxw.M': 'पुरुष', 'sxw.O': 'व्यक्ति',
      'sm.q': 'छवि गुणवत्ता {v} ({d})।', 'sm.found': 'मिले: {list}।', 'sm.nothing': 'कोई घाव नहीं मिला।',
      'sm.where': 'अधिकतर घाव {q} चतुर्थांश में हैं।', 'sm.ex': 'निकटतम हार्ड एक्सयूडेट फ़ोविया से {d} डिस्क-व्यास दूर है।',
      'sm.grade': 'सबसे संभावित ICDR स्तर {g}, {name} ({p}); रेफ़र करने योग्य DR की संभावना {r}।',
      'sm.retake': 'फ़ोटो ग्रेड नहीं हो सकी: {why}।', 'sm.and': ' और ', 'sm.comma': ', ',
      'l.ma': '{n} माइक्रोएन्यूरिज़्म', 'l.ma1': '1 माइक्रोएन्यूरिज़्म', 'l.he': '{n} रक्तस्राव ({parts})', 'l.he1': '1 रक्तस्राव ({parts})',
      'l.ex': '{n} हार्ड एक्सयूडेट', 'l.ex1': '1 हार्ड एक्सयूडेट', 'l.cws': '{n} कॉटन-वूल धब्बे', 'l.cws1': '1 कॉटन-वूल धब्बा',
      'l.nv': '{n} नई-नलिका क्षेत्र', 'l.nv1': '1 नई-नलिका क्षेत्र',
      'hp.dot': '{n} डॉट', 'hp.blot': '{n} ब्लॉट', 'hp.flame': '{n} फ़्लेम', 'hp.preretinal': '{n} प्री-रेटिनल',
      'qc.title': 'छवि गुणवत्ता', 'q.GRADABLE': 'ग्रेड-योग्य', 'q.ENHANCE': 'सीमांत', 'q.RECAPTURE': 'दोबारा फ़ोटो', 'q.after': 'सुधार के बाद ग्रेड-योग्य',
      'q.sub.field': 'दृश्य-क्षेत्र', 'q.sub.focus': 'फ़ोकस', 'q.sub.illumination': 'रोशनी', 'q.sub.contrast': 'कंट्रास्ट', 'q.sub.artifact': 'आर्टिफ़ैक्ट',
      'qc.enh': 'ग्रेडिंग से पहले सुधारी गई: {a} → {b}', 'qc.rule': 'पाँच जाँचों का भारित माध्य। 0.60 पर ग्रेड-योग्य, जब हर जाँच 0.50 या अधिक हो।',
      'qc.retake': 'फ़ोटो दोबारा लें', 'qc.noField': 'कोई गोल फ़ंडस क्षेत्र नहीं मिला।',
      'fb.blur': 'फ़ोकस नहीं है: लेंस साफ़ करें, मरीज़ को स्थिर रहने को कहें, डिस्क की नसों पर दोबारा फ़ोकस करें।',
      'fb.dark': 'फ़ोटो बहुत गहरी है: कमरे की रोशनी कम करें, पुतली फैलने दें, या फ़्लैश बढ़ाएँ।',
      'fb.bright': 'बहुत ज़्यादा रोशनी या चमक: फ़्लैश कम करें और कैमरे को पुतली के केंद्र पर सीधा करें।',
      'fb.field': 'रेटिना पूरा दिखाई नहीं दे रहा: पुतली को बीच में रखें और मरीज़ को फ़िक्सेशन लाइट देखने को कहें।',
      'fb.contrast': 'कम कंट्रास्ट (गंदा लेंस या मोतियाबिंद हो सकता है): लेंस साफ़ करके फिर से फ़ोटो लें; बार-बार ऐसा हो तो पुतली फैलाकर जाँच के लिए रेफ़र करें।',
      'fb.artifact': 'किनारे पर छाया या चमक: मरीज़ को आँख पूरी खोलने को कहें और कैमरा स्थिर रखें।',
      'fb.none': 'कोई गोल फ़ंडस क्षेत्र नहीं मिला। यह फ़ंडस फ़ोटो नहीं लगती।',
      'lv.0': 'कोई स्पष्ट रेटिनोपैथी नहीं', 'lv.1': 'हल्की NPDR', 'lv.2': 'मध्यम NPDR', 'lv.3': 'गंभीर NPDR', 'lv.4': 'प्रोलिफ़ेरेटिव DR',
      'lv.s0': 'कोई नहीं', 'lv.s1': 'हल्की', 'lv.s2': 'मध्यम', 'lv.s3': 'गंभीर', 'lv.s4': 'प्रोलिफ़ेरेटिव',
      'pb.ref': 'रेफ़र करने योग्य DR की संभावना', 'pb.thr': 'रेफ़रल सीमा {v}',
      'fl.none': 'इस छवि में कोई घाव नहीं मिला।',
      'fd.due': '{d} तक', 'fd.today': 'आज ही', 'ad.a1c': 'HbA1c {v}% है, 7% के लक्ष्य से ऊपर: डॉक्टर के साथ डायबिटीज़ नियंत्रण की समीक्षा करें।',
      'msg.title': 'मरीज़ के लिए संदेश', 'msg.copy': 'कॉपी करें', 'msg.copied': 'कॉपी हो गया', 'msg.sel': 'चुना गया: Ctrl+C दबाएँ',
      'pm.ROUTINE': 'रेफ़र करने योग्य डायबिटिक रेटिनोपैथी नहीं मिली। 12 महीने बाद फिर से जाँच कराएँ और शुगर नियंत्रण में रखें।',
      'pm.REFER': 'रेफ़र करने योग्य डायबिटिक रेटिनोपैथी की आशंका है। कृपया 4 सप्ताह के भीतर नेत्र विशेषज्ञ को दिखाएँ।',
      'pm.REFER_DME': 'दृष्टि के केंद्र (मैक्युला) के पास डायबिटिक नेत्र रोग के बदलाव की आशंका है। कृपया 2 सप्ताह के भीतर नेत्र विशेषज्ञ को दिखाएँ।',
      'pm.URGENT': 'उन्नत (प्रोलिफ़ेरेटिव) डायबिटिक रेटिनोपैथी के लक्षण। 1 सप्ताह के भीतर नेत्र विशेषज्ञ को दिखाएँ।',
      'pm.HUMAN_REVIEW': 'आपकी फ़ोटो की जाँच नेत्र विशेषज्ञ कर रहे हैं। 48 घंटे के भीतर आपसे संपर्क किया जाएगा।',
      'pm.RECAPTURE': 'फ़ोटो पर्याप्त साफ़ नहीं थी। नई फ़ोटो लेनी होगी।', 'pm.by': 'कृपया {d} तक आएँ।',
      'st.n': 'अध्ययन', 'st.wait': 'समीक्षा बाकी', 'st.med': 'मध्यिका समीक्षा समय', 'st.u30': '30 सेकंड के भीतर समीक्षा',
      'ss.wait': 'समीक्षा बाकी', 'ss.ok': 'पुष्टि हुई', 'ss.chg': '{g} में बदला', 'ss.ungr': 'अपठनीय',
      'rp.title': '30 सेकंड की समीक्षा', 'rp.none': 'अध्ययन जोड़ने के लिए किसी मरीज़ की जाँच करें।', 'rp.ai': 'ICDR {g} · {p} रेफ़र करने योग्य',
      'rp.start': 'समीक्षा शुरू करें', 'rp.confirm': 'पुष्टि करें: {d}', 'rp.set': 'या ICDR स्तर स्वयं तय करें', 'rp.ungr': 'अपठनीय: दोबारा फ़ोटो',
      'rp.ok': '{s} सेकंड में पुष्टि।', 'rp.chg': '{s} सेकंड में स्तर {g} में बदला।', 'rp.ungrD': '{s} सेकंड में अपठनीय चिह्नित।', 'rp.again': 'फिर से समीक्षा करें',
      'rp.keys': 'कुंजियाँ: Enter पुष्टि करता है, 0–4 स्तर तय करते हैं, U अपठनीय चिह्नित करता है।',
      'rp.console': 'MATLAB का रीडर कंसोल (netra.ui.ReaderConsole) यही काम कीबोर्ड शॉर्टकट से करता है और ऑडिट लॉग लिखता है।',
      'r.head': 'डायबिटिक रेटिनोपैथी स्क्रीनिंग रिपोर्ट', 'r.study': 'अध्ययन {id}', 'r.device': 'डिवाइस पर जाँच', 'r.p': 'हर ICDR स्तर की संभावना', 'r.find': 'खोजें',
      'r.count': 'संख्या', 'r.qual': 'छवि गुणवत्ता', 'r.crit': 'पूरे हुए मानदंड', 'r.none': 'कोई मानदंड पूरा नहीं',
      'r.disc': 'शोध-सॉफ़्टवेयर, चिकित्सा उपकरण नहीं। हर रेफ़रल की पुष्टि प्रशिक्षित ग्रेडर या नेत्र-चिकित्सक करते हैं।',
      'r.sign': 'समीक्षक', 'r.ma': 'माइक्रोएन्यूरिज़्म', 'r.he': 'रक्तस्राव', 'r.ex': 'हार्ड एक्सयूडेट', 'r.cws': 'कॉटन-वूल धब्बे',
      'r.nv': 'नई-नलिका क्षेत्र', 'r.lm': 'स्थल-चिह्न', 'r.lmV': 'डिस्क {d}, फ़ोविया {f}', 'r.q': '{s} · {d}',
      'r.pid': 'मरीज़ {id}', 'r.age': '{a} वर्ष', 'r.dm': 'डायबिटीज़ {n} वर्ष', 'r.a1c': 'HbA1c {v}%', 'r.eyeRec': '{e} आँख', 'r.done': 'ग्रेडर समीक्षा: {what}',
      'cr.ma': 'माइक्रोएन्यूरिज़्म', 'cr.he': 'इंट्रारेटिनल रक्तस्राव', 'cr.ex': 'हार्ड एक्सयूडेट', 'cr.cws': 'कॉटन-वूल धब्बे', 'cr.he4q': '10 या अधिक रक्तस्राव वाले चतुर्थांश',
      'cr.nv': 'नई नलिकाएँ, संभावना ({w})', 'cr.prh': 'प्री-रेटिनल रक्तस्राव',
      'sim.ok': 'यह योजना हर लक्ष्य पूरा करती है', 'sim.no': 'यह योजना 6 में से {n} लक्ष्य चूकती है',
      'k.screened': 'प्रति वर्ष जाँचे गए लोग', 'k.routine': 'नियमित रिपोर्ट तैयार (95वाँ प्रतिशतक)', 'k.urgent': 'तत्काल मामलों की सूचना (95वाँ प्रतिशतक)',
      'k.graders': 'ग्रेडर का कार्यभार', 'k.oph': 'नेत्र-चिकित्सक का कार्यभार', 'k.sens': 'कार्यक्रम की संवेदनशीलता', 'k.uplink': 'अपलोड लिंक का उपयोग', 'k.treat': 'प्रति वर्ष इलाज तक पहुँचे लोग',
      'k.missed': 'प्रति वर्ष छूटे रेफ़र करने योग्य मामले', 'k.cost': 'प्रति व्यक्ति जाँच ख़र्च', 'k.total': 'वार्षिक ख़र्च', 'k.target': 'लक्ष्य {v}',
      'h': 'घंटे', 'onsite': 'फ़ोटो के समय',
      'c.title': 'पैसा कहाँ जाता है', 'c.cameras': 'कैमरे', 'c.technicians': 'तकनीशियन', 'c.links': 'नेटवर्क लिंक', 'c.ai': 'AI (उपकरण या क्लाउड)', 'c.graders': 'ग्रेडर',
      'c.ophthalmologist': 'नेत्र-चिकित्सक', 'c.vans': 'वैन', 'c.lakh': '₹{v} लाख',
      'sim.note': 'हर योजना उन्हीं मरीज़ों के साथ एक सिम्युलेटेड साल है, हर रन लगभग 0.2 सेकंड। मान्यताएँ netra.sim.defaults में हैं और स्थानीय डेटा से बदली जा सकती हैं।',
      'p.best': 'अनुकूलित योजना', 'p.noxai': 'व्याख्या वाली रिपोर्ट के बिना', 'p.cloud': 'क्लाउड ग्रेडिंग', 'p.g2': '2G लिंक, क्लाउड ग्रेडिंग', 'p.all': 'हर केंद्र, अधिक स्टाफ़',
      'bm.tab.referable-dr': 'रेफ़र करने योग्य DR', 'bm.tab.vessels': 'नसें (DRIVE)', 'bm.tab.lesion-seg': 'घाव (IDRiD)', 'bm.tab.landmarks': 'स्थल-चिह्न (IDRiD)',
      'bm.tab.dr-grading': 'पाँच-स्तरीय ग्रेडिंग', 'bm.tab.standard': 'मानक और लक्ष्य',
      'bm.no': '#', 'bm.ds': 'डेटासेट', 'bm.me': 'विधि', 'bm.n': 'n', 'bm.src': 'स्रोत', 'bm.verify': 'स्रोत से जाँचें',
      'ch.x': 'विशिष्टता', 'ch.y': 'संवेदनशीलता', 'ch.bda1': 'BDA / Exeter', 'ch.bda2': 'न्यूनतम', 'ch.fda': 'FDA पिवोटल लक्ष्य'
    }
  };
  var lang = 'en';
  function t(k, vars) {
    var s = (W[lang] && W[lang][k]) || W.en[k] || k;
    if (vars) { Object.keys(vars).forEach(function (v) { s = s.split('{' + v + '}').join(vars[v]); }); }
    return s;
  }
  function nf(v, d) {
    d = d || 0;
    return new Intl.NumberFormat(lang === 'hi' ? 'hi-IN' : 'en-IN', { maximumFractionDigits: d, minimumFractionDigits: d }).format(v);
  }
  function pct(p, d) { return p > 0 && p < 0.01 && !d ? '<1%' : nf(100 * p, d || 0) + '%'; }
  function loc() { return lang === 'hi' ? 'hi-IN' : 'en-IN'; }
  function fmtDate(ms) { return new Date(ms).toLocaleDateString(loc(), { day: 'numeric', month: 'short', year: 'numeric' }); }
  function fmtTime(ms) { return new Date(ms).toLocaleTimeString(loc(), { hour: 'numeric', minute: '2-digit' }); }
  function fmtMs(ms) { return ms >= 1000 ? nf(ms / 1000, 1) + ' s' : nf(ms) + ' ms'; }
  function joinList(a) { return a.length < 2 ? a.join('') : a.slice(0, -1).join(t('sm.comma')) + t('sm.and') + a[a.length - 1]; }
  function count(key, n, vars) { vars = vars || {}; vars.n = nf(n); return t(n === 1 ? key + '1' : key, vars); }

  function applyStatic() {
    document.documentElement.lang = lang;
    $$('[data-t]').forEach(function (e) {
      if (e.dataset.en === undefined) { e.dataset.en = e.innerHTML; }
      e.innerHTML = lang === 'hi' && HI[e.dataset.t] ? HI[e.dataset.t] : e.dataset.en;
    });
    var lab = $('#lang-label');
    lab.textContent = lang === 'hi' ? 'English' : 'हिन्दी';
    lab.lang = lang === 'hi' ? 'en' : 'hi';
  }
  $('#lang-btn').addEventListener('click', function () {
    lang = lang === 'hi' ? 'en' : 'hi';
    try { localStorage.setItem('netrasetu-lang', lang); } catch (err) { /* storage unavailable */ }
    applyStatic();
    renderAll();
  });

  /* ================================================================ routing */
  var VIEWS = ['screen', 'review', 'district', 'evidence'], current = '';
  function route() {
    var id = location.hash.slice(1);
    if (VIEWS.indexOf(id) < 0) { id = 'screen'; }
    var changed = id !== current;
    current = id;
    VIEWS.forEach(function (v) { $('#view-' + v).hidden = v !== id; });   // ids differ from the hash words, so the browser never jumps
    $$('.tabs a').forEach(function (a) {
      var on = a.getAttribute('href') === '#' + id;
      a.setAttribute('aria-selected', String(on));
      if (on) { a.setAttribute('aria-current', 'page'); } else { a.removeAttribute('aria-current'); }
    });
    if (changed) { window.scrollTo(0, 0); }
    if (id === 'screen') { applyView(); }
    if (id === 'review') { renderQueue(); }
    if (id === 'district' && !simResult) { requestSim(); }
    if (id === 'evidence' && !benchDone) { renderBenchmarks(); }
  }
  window.addEventListener('hashchange', route);
  function go(id) { if (location.hash === '#' + id) { route(); } else { location.hash = id; } }
  function smooth() { return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'; }
  function scrollToEl(e) {
    var bar = $('.appbar'), off = bar ? bar.getBoundingClientRect().height : 0;
    window.scrollTo({ top: e.getBoundingClientRect().top + window.pageYOffset - off - 12, behavior: smooth() });
  }

  /* ================================================================ patient */
  var YEAR = new Date().getFullYear(), seqPatient = 1, formEye = 'R';
  var EXAMPLE = { id: 'NS-' + YEAR + '-0001', age: 54, sex: 'F', eye: 'R', dm: 8, a1c: 7.6, phc: 'PHC-07' };
  function setFormEye(v) {
    formEye = v;
    $$('#f-eye button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.v === v)); });
  }
  $$('#f-eye button').forEach(function (b) { b.addEventListener('click', function () { setFormEye(b.dataset.v); }); });
  function fillPatient(p) {
    $('#f-id').value = p.id;
    $('#f-age').value = p.age === null || p.age === undefined ? '' : p.age;
    $('#f-sex').value = p.sex || 'F';
    $('#f-dm').value = p.dm === null || p.dm === undefined ? '' : p.dm;
    $('#f-a1c').value = p.a1c === null || p.a1c === undefined ? '' : p.a1c;
    $('#f-phc').value = p.phc || '';
    setFormEye(p.eye || 'R');
  }
  function num(v, lo, hi) { var x = parseFloat(v); return isFinite(x) && x >= lo && x <= hi ? x : null; }
  function readPatient() {
    return { id: $('#f-id').value.trim() || 'NS-' + YEAR + '-' + pad(seqPatient, 4), age: num($('#f-age').value, 1, 120), sex: $('#f-sex').value,
      eye: formEye, dm: num($('#f-dm').value, 0, 80), a1c: num($('#f-a1c').value, 3, 20), phc: $('#f-phc').value.trim() };
  }
  function newPatient() {
    seqPatient++;
    fillPatient({ id: 'NS-' + YEAR + '-' + pad(seqPatient, 4), age: null, sex: 'F', eye: 'R', dm: null, a1c: null, phc: $('#f-phc').value.trim() });
    $('[data-t="pt.example"]').hidden = true;
    setInput(null, false);
    window.scrollTo({ top: 0, behavior: smooth() });
    $('#f-age').focus({ preventScroll: true });
  }

  /* ================================================================ images */
  function rgbaCanvas(rgba, D) {
    var c = canvasOf(D, D);
    c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(rgba.buffer, rgba.byteOffset, rgba.byteLength), D, D), 0, 0);
    return c;
  }
  function bitmap(url) {                                   // decoded pixels, exact for PNG
    if (window.fetch && window.createImageBitmap) {
      return fetch(url).then(function (r) { if (!r.ok) { throw new Error(url); } return r.blob(); })
        .then(function (b) { return createImageBitmap(b, { colorSpaceConversion: 'none', premultiplyAlpha: 'none' }); })
        .catch(function () { return viaImg(url); });
    }
    return viaImg(url);
  }
  function viaImg(url) { return new Promise(function (ok, no) { var im = new Image(); im.onload = function () { ok(im); }; im.onerror = no; im.src = url; }); }
  function toCanvas(img, sx, sy, sw, sh, D) {
    var c = canvasOf(D, D), x = c.getContext('2d');
    x.imageSmoothingQuality = 'high';
    x.drawImage(img, sx, sy, sw, sh, 0, 0, D, D);
    return c;
  }
  function containCanvas(src, w, h) {
    var D = 1024, c = canvasOf(D, D), x = c.getContext('2d'), s = D / Math.max(w, h);
    x.fillStyle = '#000'; x.fillRect(0, 0, D, D);
    x.imageSmoothingQuality = 'high';
    x.drawImage(src, (D - w * s) / 2, (D - h * s) / 2, w * s, h * s);
    return c;
  }
  var SRC = {};
  function sourceImage(name) { if (!SRC[name]) { SRC[name] = bitmap('img/' + name).catch(function (e) { SRC[name] = null; throw e; }); } return SRC[name]; }

  /* ================================================================ the photograph */
  var state = { input: null, study: null, running: false, job: 0, steps: -1, timing: null, error: '' };
  var TESTS = [{ kind: 'eye', n: 1 }, { kind: 'eye', n: 2 }, { kind: 'eye', n: 3 }, { kind: 'eye', n: 4 }, { kind: 'eye', n: 5 },
    { kind: 'capture', name: 'defocus' }, { kind: 'capture', name: 'dark' }, { kind: 'capture', name: 'lashes' }, { kind: 'capture', name: 'flare' }];
  function capByName(name) { return (window.NETRA_SAMPLE ? window.NETRA_SAMPLE.capture : []).filter(function (c) { return c.name === name; })[0]; }
  function rectOf(tt) {
    if (tt.kind === 'eye') { return [10 + 430 * (tt.n - 1), 10, 420]; }
    var cap = capByName(tt.name);
    return cap ? [cap.x, 10, 360] : null;
  }
  function sameInput(a, b) { return !!a && !!b && a.kind === b.kind && (a.kind === 'eye' ? a.n === b.n : a.kind === 'capture' ? a.name === b.name : a === b); }
  function renderTests() {
    var box = $('#tests');
    box.innerHTML = '';
    TESTS.forEach(function (tt) {
      var r = rectOf(tt);
      if (!r) { return; }
      var b = btn('', null, function () { pickTest(tt); }), cv = canvasOf(76, 76);
      b.setAttribute('aria-pressed', String(sameInput(tt, state.input)));
      b.title = tt.kind === 'eye' ? t('in.eye', { g: tt.n - 1 }) : t('in.cap', { name: t('cap.' + tt.name) });
      b.append(cv, el('span', '', tt.kind === 'eye' ? t('ts.eye', { g: tt.n - 1 }) : t('ts.' + tt.name)));
      box.append(b);
      sourceImage(tt.kind === 'eye' ? 'phantoms.jpg' : 'quality.jpg').then(function (im) {
        cv.getContext('2d').drawImage(im, r[0], r[1], r[2], r[2], 0, 0, 76, 76);
      }).catch(function () { /* thumbnail unavailable */ });
    });
  }
  function pickTest(tt, keep) {
    var r = rectOf(tt);
    return sourceImage(tt.kind === 'eye' ? 'phantoms.jpg' : 'quality.jpg').then(function (im) {
      var w = r[2], cv = toCanvas(im, r[0], r[1], w, w, w);
      var inp = { kind: tt.kind, n: tt.n, name: tt.name, w: w, h: w, img: { width: w, height: w, data: cv.getContext('2d').getImageData(0, 0, w, w).data },
        preview: toCanvas(im, r[0], r[1], w, w, 1024) };
      setInput(inp, keep);
      return inp;
    }).catch(function () { state.error = 'err.file'; renderInput(); });
  }
  function openFile(file) {
    if (!file) { return; }
    if (file.type && !/^image\//.test(file.type)) { state.error = 'err.file'; renderInput(); return; }
    var dec = window.createImageBitmap ? createImageBitmap(file) : viaImg(URL.createObjectURL(file));
    dec.then(function (bmp) {
      var w0 = bmp.width, h0 = bmp.height, s = Math.min(1, 1600 / Math.max(w0, h0)), w = Math.max(1, Math.round(w0 * s)), h = Math.max(1, Math.round(h0 * s));
      var cv = canvasOf(w, h), x = cv.getContext('2d');
      x.imageSmoothingQuality = 'high';
      x.drawImage(bmp, 0, 0, w, h);
      if (bmp.close) { bmp.close(); }
      var d = x.getImageData(0, 0, w, h);
      setInput({ kind: 'upload', name: file.name || '', bytes: file.size, w: w0, h: h0, img: { width: w, height: h, data: d.data }, preview: containCanvas(cv, w, h) }, false);
    }).catch(function () { state.error = 'err.file'; renderInput(); });
    if (current !== 'screen') { go('screen'); }
  }
  function inputName(inp) {
    if (inp.kind === 'eye') { return t('in.eye', { g: inp.n - 1 }); }
    if (inp.kind === 'capture') { return t('in.cap', { name: t('cap.' + inp.name) }); }
    return inp.name;
  }
  function bytes(n) { return n >= 1048576 ? nf(n / 1048576, 1) + ' MB' : nf(Math.max(1, Math.round(n / 1024))) + ' KB'; }
  function inputSize(inp) {
    var px = t('in.px', { w: nf(inp.w), h: nf(inp.h) });
    return inp.kind === 'upload' ? bytes(inp.bytes) + ' · ' + px : px + ' · ' + t('in.synth');
  }
  var acqMsg = el('p', 'warnline');
  acqMsg.hidden = true;
  $('#go').after(acqMsg);
  function setInput(inp, keep) {
    state.input = inp;
    state.error = '';
    renderInput();
    renderTests();
    if (!keep && !state.running) { $('#out').hidden = true; $('#steps').hidden = true; state.steps = -1; }
  }
  function renderInput() {
    var d = $('#drop'), inp = state.input, has = !!inp;
    d.classList.toggle('has', has);
    $('.empty', d).hidden = has;
    $('.has-in', d).hidden = !has;
    if (has) {
      var cv = $('.has-in canvas', d), x = cv.getContext('2d');
      x.fillStyle = '#000'; x.fillRect(0, 0, cv.width, cv.height);
      x.imageSmoothingQuality = 'high';
      x.drawImage(inp.preview, 0, 0, cv.width, cv.height);
      $('#file-name').textContent = inputName(inp);
      $('#file-size').textContent = inputSize(inp);
    }
    $('#go').disabled = !has || state.running;
    acqMsg.innerHTML = '';
    acqMsg.hidden = !state.error;
    if (state.error) { acqMsg.append(icon('i-alert'), el('span', '', t(state.error))); }
  }
  var drop = $('#drop'), fileIn = $('#file');
  drop.addEventListener('click', function () { fileIn.click(); });
  drop.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileIn.click(); } });
  fileIn.addEventListener('change', function () { openFile(fileIn.files && fileIn.files[0]); fileIn.value = ''; });
  ['dragenter', 'dragover'].forEach(function (ev) { drop.addEventListener(ev, function (e) { e.preventDefault(); drop.classList.add('over'); }); });
  ['dragleave', 'dragend'].forEach(function (ev) { drop.addEventListener(ev, function (e) { if (!drop.contains(e.relatedTarget)) { drop.classList.remove('over'); } }); });
  drop.addEventListener('drop', function (e) {
    e.preventDefault();
    drop.classList.remove('over');
    var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
    if (f) { openFile(f); }
  });
  document.addEventListener('dragover', function (e) { e.preventDefault(); });
  document.addEventListener('drop', function (e) { e.preventDefault(); });
  document.addEventListener('paste', function (e) {
    var files = (e.clipboardData && e.clipboardData.files) || [];
    if (files.length && /^image\//.test(files[0].type)) { openFile(files[0]); }
  });
  $('#go').addEventListener('click', screenNow);

  /* ================================================================ engine */
  var worker = null, canWorker = typeof Worker !== 'undefined';
  function runEngine(img, onProgress, onDone) {
    if (worker) { worker.terminate(); worker = null; }
    if (canWorker) {
      try {
        var w = new Worker('engine.js');
        worker = w;
        w.onmessage = function (ev) {
          if (w !== worker) { return; }
          var m = ev.data || {};
          if (m.progress) { onProgress(m.progress); return; }
          w.terminate(); worker = null;
          onDone(m.result || null, m.error || '');
        };
        w.onerror = function (ev) {
          if (ev && ev.preventDefault) { ev.preventDefault(); }
          if (w !== worker) { return; }
          w.terminate(); worker = null; canWorker = false;
          runEngine(img, onProgress, onDone);
        };
        w.postMessage({ cmd: 'screen', image: img, id: 1, opts: {} });
        return;
      } catch (err) { canWorker = false; worker = null; }
    }
    setTimeout(function () {
      var out = null, msg = '';
      try { out = window.NetraEngine.screen(img, onProgress); } catch (err) { msg = String(err && err.message || err); }
      onDone(out, msg);
    }, 60);
  }
  var STEP_KEYS = ['quality', 'anatomy', 'lesions', 'grading', 'explanation'];
  function setSteps(k, timing) {                           // k: stages finished; -1 idle; -2 stopped at quality
    state.steps = k;
    if (timing !== undefined) { state.timing = timing; }
    $$('#steps li').forEach(function (li, j) {
      li.classList.toggle('done', k >= 0 && j < k);
      li.classList.toggle('now', state.running && j === k);
      li.classList.toggle('fail', k === -2 && j === 0);
      var ms = state.timing && state.timing[STEP_KEYS[j]];
      $('span', li).textContent = ms !== undefined && ms !== null && (k >= 0 ? j < k : j === 0) ? fmtMs(ms) : '';
    });
  }
  function caseFromResult(res, inp) {
    var D = res.canvas ? res.canvas.D : 1024, c = { res: res, D: D, images: {}, ov: {}, bits: null, evidence: null, input: inp };
    if (res.canvas) {
      c.images.raw = rgbaCanvas(res.canvas.raw, D);
      if (res.canvas.normalised) { c.images.normalised = rgbaCanvas(res.canvas.normalised, D); }
      if (res.canvas.display) { c.images.enhanced = rgbaCanvas(res.canvas.display, D); }
      c.centre = res.canvas.centre; c.radius = res.canvas.radius;
      res.canvas = { D: D, radius: res.canvas.radius, centre: res.canvas.centre };   // the canvases hold the pixels now
    } else {
      c.images.raw = inp.preview;
      c.centre = [D / 2 - 0.5, D / 2 - 0.5]; c.radius = D / 2;
    }
    if (res.layers) { c.bits = res.layers.bits; c.evidence = res.layers.evidence; delete res.layers; }
    return c;
  }
  function loadSample() {
    var S = window.NETRA_SAMPLE;
    if (!S) { return Promise.reject(new Error('no sample')); }
    return Promise.all(['raw.jpg', 'normalised.jpg', 'enhanced.jpg', 'layers.png'].map(function (f) { return bitmap('img/case/' + f); })).then(function (im) {
      var r = S.result, D = r.canvas.D, c = { res: r, D: D, images: {}, ov: {}, centre: r.canvas.centre, radius: r.canvas.radius };
      c.images.raw = toCanvas(im[0], 0, 0, D, D, D);
      c.images.normalised = toCanvas(im[1], 0, 0, D, D, D);
      c.images.enhanced = toCanvas(im[2], 0, 0, D, D, D);
      var lc = toCanvas(im[3], 0, 0, D, D, D), px = lc.getContext('2d').getImageData(0, 0, D, D).data, n = D * D;
      c.bits = new Uint16Array(n); c.evidence = new Uint8Array(n);
      for (var i = 0; i < n; i++) { c.bits[i] = px[4 * i] | (px[4 * i + 1] << 8); c.evidence[i] = px[4 * i + 2]; }
      r.when = Date.now();
      return c;
    });
  }
  function screenNow() {
    var inp = state.input;
    if (!inp || state.running) { return; }
    var patient = readPatient(), job = ++state.job, t0 = performance.now(), steps = $('#steps');
    state.running = true; state.error = '';
    renderInput();
    $('#out').hidden = true;
    steps.hidden = false;
    setSteps(0, null);
    scrollToEl(steps);
    runEngine(inp.img, function (k) { if (job === state.job) { setSteps(k); } }, function (res, err) {
      if (job !== state.job) { return; }
      state.running = false;
      if (!res) {
        state.error = 'err.engine';
        if (err && window.console) { console.error(err); }
        steps.hidden = true;
        setSteps(-1, null);
        renderInput();
        return;
      }
      res.ms = performance.now() - t0; res.when = Date.now();
      var st = makeStudy(patient, caseFromResult(res, inp), false);
      setSteps(res.decision.triage === 'RECAPTURE' ? -2 : 5, res.timing || null);
      renderInput();
      showStudy(st);
      renderQueue();
    });
  }

  /* ================================================================ studies */
  var studies = [], seqStudy = 0;
  function makeStudy(patient, c, example) {
    var st = { id: 'S-' + pad(++seqStudy, 4), patient: Object.assign({}, patient), c: c, when: c.res.when || Date.now(), status: 'wait', review: null, example: !!example };
    st.queued = c.res.decision.triage !== 'RECAPTURE';
    if (st.queued) { studies.push(st); }
    return st;
  }
  function keyOf(st) { var d = st.c.res.decision; return d.key || d.triage; }
  function graded(r) { return !!(r && r.fusion && r.decision.triage !== 'RECAPTURE'); }
  function aiGrade(r) { var P = r.fusion.P, g = 0; P.forEach(function (p, k) { if (p > P[g]) { g = k; } }); return g; }
  function hasLayers(c) { return !!(c && c.bits); }
  var TRI_CLS = { ROUTINE: 'ok', REFER: 'warn', REFER_DME: 'warn', URGENT: 'bad', HUMAN_REVIEW: 'info', RECAPTURE: 'mute' };
  var TRI_COL = { ROUTINE: '#0F8A7E', REFER: '#C27400', REFER_DME: '#C27400', URGENT: '#C8213A', HUMAN_REVIEW: '#3D4DB7', RECAPTURE: '#5B6272' };
  var GCOL = ['var(--g0)', 'var(--g1)', 'var(--g2)', 'var(--g3)', 'var(--g4)'];
  var GHEX = ['#0F8A7E', '#6FA35A', '#D8B228', '#E07B0B', '#C8213A'];
  var LCOL = { ma: '#FF4D6A', he: '#D656DB', ex: '#F5C518', cws: '#7FD8F6', nv: '#6BE675' };
  var LINK = { ma: '#FFFFFF', he: '#FFFFFF', ex: '#10131F', cws: '#10131F', nv: '#10131F' };
  var QN = { 1: 'ST', 2: 'SN', 3: 'IN', 4: 'IT' };
  var KINDS = ['nv', 'he', 'ex', 'cws', 'ma'];
  function statusChip(cls, text) { return el('span', 'status ' + cls, text); }
  function sexAge(p) {
    var a = [];
    if (p.sex) { a.push(t('sx.' + p.sex)); }
    if (p.age !== null && p.age !== undefined) { a.push(t('hud.age', { a: nf(p.age) })); }
    return a.join(' · ');
  }
  function odos(e) { return e === 'L' ? 'OS' : 'OD'; }

  // every lesion the engine kept, in reading order: most severe kind first, then by confidence
  function findingsOf(c) {
    if (c.findings) { return c.findings; }
    var L = c.res.lesions, out = [], um = c.res.anatomy ? c.res.anatomy.umPerPx : 0;
    if (!L || !graded(c.res)) { c.findings = out; return out; }
    function eqd(area) { return um ? 2 * Math.sqrt(area / Math.PI) * um : 0; }
    var HEORDER = { preretinal: 0, blot: 1, flame: 2, dot: 3 };
    (L.nv || []).forEach(function (e) { if (e.prob >= 0.5) { out.push({ k: 'nv', sub: e.type, x: e.x, y: e.y, prob: e.prob, score: e.score }); } });
    L.he.forEach(function (e) { out.push({ k: 'he', sub: e.type, x: e.x, y: e.y, prob: e.prob, q: e.quadrant, d: e.distFoveaDD, um: e.eqDiamUm || (e.areaPx ? eqd(e.areaPx) : 0), o: HEORDER[e.type] || 0 }); });
    L.ex.forEach(function (e) { out.push({ k: 'ex', x: e.x, y: e.y, prob: e.prob, q: e.quadrant, d: e.distFoveaDD, um: eqd(e.areaPx || 0) }); });
    L.cws.forEach(function (e) { out.push({ k: 'cws', x: e.x, y: e.y, prob: e.prob, q: e.quadrant, d: e.distFoveaDD, um: eqd(e.areaPx || 0) }); });
    L.ma.forEach(function (e) { out.push({ k: 'ma', x: e.x, y: e.y, prob: e.prob, q: e.quadrant, d: e.distFoveaDD, um: e.diameterUm }); });
    out.sort(function (a, b) { return KINDS.indexOf(a.k) - KINDS.indexOf(b.k) || (a.o || 0) - (b.o || 0) || b.prob - a.prob; });
    c.findings = out;
    return out;
  }
  function countsOf(c) {
    var n = { ma: 0, he: 0, ex: 0, cws: 0, nv: 0 };
    findingsOf(c).forEach(function (f) { n[f.k]++; });
    return n;
  }
  function subName(f) { return f.k === 'he' ? t('hs.' + f.sub) : f.k === 'nv' ? t('nvs.' + f.sub) : ''; }

  /* ================================================================ layers */
  // layer groups -> bits of the engine's layer word (see LAYER in engine.js)
  var GROUP = { anatomy: [1, 2, 3], vessels: [0], ma: [4], he: [5, 6, 7], ex: [8], cws: [9], nv: [10] };
  var PAINT = [0, 3, 5, 6, 7, 8, 9, 4, 10, 1, 2];
  var COL = { 0: [70, 200, 255, 0.55], 1: [255, 255, 255, 0.95], 2: [226, 242, 255, 0.95], 3: [255, 255, 255, 0.42], 4: [255, 77, 106, 1], 5: [214, 86, 219, 1], 6: [150, 110, 255, 1],
    7: [236, 140, 255, 1], 8: [245, 197, 24, 1], 9: [127, 216, 246, 1], 10: [107, 230, 117, 1] };
  function overlayOf(c, layers) {
    if (!c.bits || !layers.length) { return null; }
    var key = layers.slice().sort().join(',');
    if (c.ov[key] !== undefined) { return c.ov[key]; }
    var want = 0, order = [];
    layers.forEach(function (l) { (GROUP[l] || []).forEach(function (b) { want |= 1 << b; }); });
    PAINT.forEach(function (b) { if (want >> b & 1) { order.push(b); } });
    var D = c.D, cv = canvasOf(D, D), x = cv.getContext('2d'), img = x.createImageData(D, D), d = img.data, bits = c.bits;
    for (var i = 0, n = D * D; i < n; i++) {
      var w = bits[i] & want;
      if (!w) { continue; }
      var r = 0, g = 0, b = 0, a = 0;
      for (var k = 0; k < order.length; k++) {
        if (!(w >> order[k] & 1)) { continue; }
        var col = COL[order[k]], al = col[3];
        r = col[0] * al + r * (1 - al); g = col[1] * al + g * (1 - al); b = col[2] * al + b * (1 - al); a = al + a * (1 - al);
      }
      d[4 * i] = r / a; d[4 * i + 1] = g / a; d[4 * i + 2] = b / a; d[4 * i + 3] = 255 * a;
    }
    x.putImageData(img, 0, 0);
    c.ov[key] = cv;
    return cv;
  }
  var HEAT = (function () {                               // dark violet -> magenta -> orange -> pale yellow
    var stops = [[0, 40, 11, 84], [0.3, 120, 28, 109], [0.55, 205, 54, 80], [0.8, 247, 142, 32], [1, 252, 245, 180]], lut = [];
    for (var i = 0; i < 256; i++) {
      var v = i / 255, k = 1;
      while (k < stops.length - 1 && v > stops[k][0]) { k++; }
      var a = stops[k - 1], b = stops[k], f = (v - a[0]) / (b[0] - a[0]);
      lut.push([a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2]), a[3] + f * (b[3] - a[3])]);
    }
    return lut;
  })();
  function heatOf(c) {
    if (c.heat) { return c.heat; }
    var D = c.D, cv = canvasOf(D, D), x = cv.getContext('2d'), img = x.createImageData(D, D), d = img.data, ev = c.evidence;
    for (var i = 0, n = D * D; i < n; i++) {
      var v = ev[i];
      if (v < 10) { continue; }
      var col = HEAT[v];
      d[4 * i] = col[0]; d[4 * i + 1] = col[1]; d[4 * i + 2] = col[2]; d[4 * i + 3] = Math.min(235, 60 + 1.4 * v);
    }
    x.putImageData(img, 0, 0);
    c.heat = cv;
    return cv;
  }
  // red-free: the green channel of the illumination-corrected image, stretched inside the field of view
  function redfreeOf(c) {
    if (c.redfree) { return c.redfree; }
    var src = c.images.normalised || c.images.raw, D = c.D, cv = canvasOf(D, D), x = cv.getContext('2d');
    x.drawImage(src, 0, 0, D, D);
    var img = x.getImageData(0, 0, D, D), d = img.data, n = D * D, hist = new Uint32Array(256), inside = new Uint8Array(n), m = 0, i, y, xx;
    var cx = c.centre[0], cy = c.centre[1], R2 = Math.pow(0.985 * c.radius, 2);
    for (y = 0; y < D; y++) {
      for (xx = 0; xx < D; xx++) {
        i = y * D + xx;
        if ((xx - cx) * (xx - cx) + (y - cy) * (y - cy) <= R2) { inside[i] = 1; hist[d[4 * i + 1]]++; m++; }
      }
    }
    function q(p) { var acc = 0, k = 0; while (k < 255 && acc + hist[k] < p * m) { acc += hist[k]; k++; } return k; }
    var lo = q(0.01), hi = Math.max(lo + 1, q(0.995)), s = 255 / (hi - lo);
    for (i = 0; i < n; i++) {
      var v = inside[i] ? clamp((d[4 * i + 1] - lo) * s, 0, 255) : 0;
      d[4 * i] = d[4 * i + 1] = d[4 * i + 2] = v; d[4 * i + 3] = 255;
    }
    x.putImageData(img, 0, 0);
    c.redfree = cv;
    return cv;
  }
  function dropCaches(keep) {
    studies.concat(state.study ? [state.study] : []).forEach(function (s) {
      if (s.c !== keep) { s.c.ov = {}; s.c.heat = null; s.c.redfree = null; }
    });
  }

  /* ================================================================ workstation */
  var ws = { view: 'raw', evidence: false, opacity: 0.7, markers: true, outlines: true, vessels: false, anatomy: true, z: 1, cx: 512, cy: 512, sel: -1, hover: -1 };
  var vp = $('#viewport'), stage = $('#stage'), pinsSvg = $('#pins'), tip = $('#tip'), pinEls = [];
  vp.tabIndex = 0;
  var busy = $('#busy');
  if (busy) { busy.remove(); }
  function showStudy(st) {
    dropCaches(st.c);
    state.study = st;
    ws.z = 1; ws.cx = st.c.D / 2; ws.cy = st.c.D / 2; ws.sel = -1; ws.hover = -1;
    if (ws.view === 'enhanced' && !st.c.images.enhanced) { ws.view = 'raw'; }
    $('#out').hidden = false;
    renderStudy();
  }
  function renderStudy() {
    var st = state.study;
    if (!st) { return; }
    renderDecision(st);
    $('#ws-study').textContent = st.id + ' · ' + odos(st.patient.eye) + (st.example ? ' · ' + t('ws.example') : '');
    renderTools();
    drawStage();
    renderPins();
    renderHud();
    renderLegend();
    renderSummary(st);
    renderQuality(st);
    renderProbCard(st);
    renderFindings();
    renderFollowup(st);
    applyView();
  }
  function renderTools() {
    var box = $('#ws-tools'), st = state.study, c = st.c, on = hasLayers(c);
    box.innerHTML = '';
    var seg = el('div', 'wseg');
    seg.setAttribute('role', 'group');
    [['raw', 'vw.raw'], ['redfree', 'vw.redfree'], ['enhanced', 'vw.enhanced']].forEach(function (m) {
      if (m[0] === 'enhanced' && !c.images.enhanced) { return; }
      var b = btn('', t(m[1]), function () { ws.view = m[0]; renderTools(); drawStage(); renderHud(); });
      b.setAttribute('aria-pressed', String(ws.view === m[0]));
      seg.append(b);
    });
    box.append(seg);
    if (on) {
      var ev = el('span', 'wt wt-ev' + (ws.evidence ? ' on' : '')), eb = btn('', null, function () { ws.evidence = !ws.evidence; renderTools(); drawStage(); });
      eb.setAttribute('aria-pressed', String(ws.evidence));
      eb.append(icon('i-heat'), txt(t('tg.evidence')));
      ev.append(eb);
      if (ws.evidence) {
        var rg = el('input');
        rg.type = 'range'; rg.min = '10'; rg.max = '100'; rg.value = String(Math.round(ws.opacity * 100));
        rg.setAttribute('aria-label', t('tg.opacity'));
        rg.addEventListener('input', function () { ws.opacity = rg.value / 100; drawStage(); });
        ev.append(rg);
      }
      box.append(ev);
      var n = findingsOf(c).length;
      [['markers', 'i-pin', t('tg.markers')], ['outlines', 'i-outline', t('tg.outlines')], ['vessels', 'i-vessel', t('tg.vessels')], ['anatomy', 'i-grid', t('tg.anatomy')]].forEach(function (g) {
        var b = btn('wt', null, function () {
          ws[g[0]] = !ws[g[0]];
          renderTools();
          if (g[0] === 'markers') { renderPins(); } else { drawStage(); }
        });
        b.setAttribute('aria-pressed', String(ws[g[0]]));
        b.append(icon(g[1]), txt(g[2]));
        if (g[0] === 'markers') { b.append(el('span', 'mono', String(n))); }
        box.append(b);
      });
    }
    var z = $('#ws-zoom');
    var out = btn('', '−', function () { zoomAt(ws.z / 1.5); }), fit = btn('zl', nf(ws.z * 100) + '%', function () { ws.z = 1; applyView(); }), inn = btn('', '+', function () { zoomAt(ws.z * 1.5); });
    out.setAttribute('aria-label', t('zm.out')); inn.setAttribute('aria-label', t('zm.in')); fit.setAttribute('aria-label', t('zm.fit'));
    z.innerHTML = '';
    z.append(out, fit, inn);
  }
  function drawStage() {
    var st = state.study;
    if (!st) { return; }
    var c = st.c, D = c.D, cv = $('canvas', stage), x = cv.getContext('2d');
    if (cv.width !== D) { cv.width = D; cv.height = D; }
    pinsSvg.setAttribute('viewBox', '0 0 ' + D + ' ' + D);
    x.globalAlpha = 1;
    x.fillStyle = '#03050A'; x.fillRect(0, 0, D, D);
    var base = ws.view === 'redfree' ? redfreeOf(c) : ws.view === 'enhanced' && c.images.enhanced ? c.images.enhanced : c.images.raw;
    if (base) { x.imageSmoothingQuality = 'high'; x.drawImage(base, 0, 0, D, D); }
    if (!hasLayers(c)) { return; }
    if (ws.evidence && c.evidence) {
      x.fillStyle = 'rgba(3, 5, 10, ' + (0.5 * ws.opacity).toFixed(3) + ')';
      x.fillRect(0, 0, D, D);
      x.globalAlpha = ws.opacity;
      x.drawImage(heatOf(c), 0, 0);
      x.globalAlpha = 1;
    }
    var layers = [];
    if (ws.vessels) { layers.push('vessels'); }
    if (ws.anatomy) { layers.push('anatomy'); }
    if (ws.outlines) { layers.push('ma', 'he', 'ex', 'cws', 'nv'); }
    var ov = overlayOf(c, layers);
    if (ov) { x.drawImage(ov, 0, 0); }
  }
  // a map pin: the tip marks the lesion, the head carries its number (sizes in screen pixels)
  var PIN = 'M0 0C-2.6-4.6-8.6-9.4-8.6-17A8.6 8.6 0 1 1 8.6-17C8.6-9.4 2.6-4.6 0 0Z';
  function renderPins() {
    var st = state.study, F = st ? findingsOf(st.c) : [];
    while (pinsSvg.firstChild) { pinsSvg.removeChild(pinsSvg.firstChild); }
    pinEls = [];
    pinsSvg.style.display = ws.markers && F.length ? '' : 'none';
    F.forEach(function (f, i) {
      var g = svg('g', { class: 'pin' + (i === ws.sel ? ' sel' : ''), 'data-i': String(i) }), p = svg('path', { d: PIN, fill: LCOL[f.k] }), tx = svg('text', { x: '0', y: '-13.4', fill: LINK[f.k] });
      tx.textContent = String(i + 1);
      g.append(p, tx);
      g.addEventListener('pointerenter', function () { ws.hover = i; showTip(); });
      g.addEventListener('pointerleave', function () { if (ws.hover === i) { ws.hover = -1; showTip(); } });
      g.addEventListener('click', function (e) { e.stopPropagation(); selectFinding(i, false); });
      pinsSvg.append(g);
      pinEls.push(g);
    });
    if (ws.sel >= 0 && pinEls[ws.sel]) { pinsSvg.append(pinEls[ws.sel]); }
    placePins();
    showTip();
  }
  function scaleNow() { var st = state.study, Wd = vp.clientWidth; return st && Wd ? Wd / st.c.D * ws.z : 0; }
  function placePins() {
    var st = state.study, S = scaleNow();
    if (!st || !S) { return; }
    var F = findingsOf(st.c);
    pinEls.forEach(function (g, i) {
      var f = F[i], k = (i === ws.sel ? 1.3 : 1) / S;
      g.setAttribute('transform', 'translate(' + f.x.toFixed(2) + ' ' + f.y.toFixed(2) + ') scale(' + k.toFixed(5) + ')');
      g.classList.toggle('sel', i === ws.sel);
    });
  }
  function showTip() {
    var st = state.study, i = ws.hover >= 0 ? ws.hover : ws.sel;
    if (!st || i < 0 || !ws.markers) { tip.hidden = true; return; }
    var f = findingsOf(st.c)[i];
    if (!f) { tip.hidden = true; return; }
    tip.innerHTML = '';
    tip.append(el('b', '', '#' + (i + 1) + ' ' + t('lt.' + f.k) + (subName(f) ? ' · ' + subName(f) : '')));
    var l1 = [], l2 = [], l3 = [t('tp.conf', { v: pct(f.prob) })];
    if (f.q) { l1.push(t('tp.quad', { q: t('qd.' + f.q) })); }
    if (f.k === 'nv') { l1.push(t('tp.score', { v: nf(f.score, 1) })); }
    if (f.um) { l2.push(nf(f.um) + ' µm'); }
    if (f.d !== undefined && f.d !== null) { l2.push(t('tp.dist', { d: nf(f.d, 1) })); }
    [l1, l2, l3].forEach(function (l) { if (l.length) { tip.append(el('span', '', l.join(' · '))); } });
    tip.hidden = false;
    placeTip();
  }
  function placeTip() {
    var st = state.study, i = ws.hover >= 0 ? ws.hover : ws.sel;
    if (tip.hidden || !st || i < 0) { return; }
    var f = findingsOf(st.c)[i], Wd = vp.clientWidth, S = scaleNow();
    if (!f || !S) { return; }
    var vx = Wd / 2 + (f.x - ws.cx) * S, vy = Wd / 2 + (f.y - ws.cy) * S;
    tip.style.visibility = vx < 0 || vy < 0 || vx > Wd || vy > Wd ? 'hidden' : '';
    var tw = tip.offsetWidth, th = tip.offsetHeight, head = vy - (i === ws.sel ? 1.3 : 1) * 26, below = head - 14 - th < 4;
    tip.classList.toggle('below', below);
    tip.style.left = clamp(vx, tw / 2 + 6, Wd - tw / 2 - 6).toFixed(1) + 'px';
    tip.style.top = (below ? vy + 4 : head).toFixed(1) + 'px';
  }
  function selectFinding(i, fromList) {
    var st = state.study;
    if (!st) { return; }
    if (ws.sel === i) { ws.sel = -1; }
    else {
      ws.sel = i;
      if (fromList) {
        var f = findingsOf(st.c)[i];
        ws.z = Math.max(ws.z, 3); ws.cx = f.x; ws.cy = f.y;
        if (!ws.markers) { ws.markers = true; renderTools(); renderPins(); }
      }
    }
    if (ws.sel >= 0 && pinEls[ws.sel]) { pinsSvg.append(pinEls[ws.sel]); }
    $$('#findings .frow').forEach(function (r, k) { r.classList.toggle('sel', k === ws.sel); r.setAttribute('aria-pressed', String(k === ws.sel)); });
    if (!fromList && ws.sel >= 0) { revealRow(ws.sel); }
    applyView();
    showTip();
  }
  function revealRow(i) {
    var box = $('#findings'), row = box.children[i];
    if (!row) { return; }
    var top = row.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop;
    if (top < box.scrollTop || top + row.offsetHeight > box.scrollTop + box.clientHeight) { box.scrollTop = top - box.clientHeight / 2 + row.offsetHeight / 2; }
  }
  function applyView() {
    var st = state.study, Wd = vp.clientWidth;
    if (!st || !Wd) { return; }
    var D = st.c.D, half = D / (2 * ws.z);
    ws.cx = clamp(ws.cx, half, D - half); ws.cy = clamp(ws.cy, half, D - half);
    var S = Wd / D * ws.z, tx = Wd / 2 - ws.cx * S, ty = Wd / 2 - ws.cy * S;
    stage.style.transform = 'translate(' + tx.toFixed(2) + 'px, ' + ty.toFixed(2) + 'px) scale(' + ws.z + ')';
    vp.classList.toggle('pan', ws.z > 1);
    vp.style.touchAction = ws.z > 1 ? 'none' : 'pan-y';
    var zl = $('#ws-zoom .zl');
    if (zl) { zl.textContent = nf(ws.z * 100) + '%'; }
    placePins();
    renderHudTR();
    renderScale();
    placeTip();
  }
  function zoomAt(z, px, py) {
    var st = state.study, Wd = vp.clientWidth;
    if (!st || !Wd) { return; }
    if (px === undefined) { px = Wd / 2; py = Wd / 2; }
    z = clamp(z, 1, 8);
    var S0 = Wd / st.c.D * ws.z, S1 = Wd / st.c.D * z, ix = ws.cx + (px - Wd / 2) / S0, iy = ws.cy + (py - Wd / 2) / S0;
    ws.z = z; ws.cx = ix - (px - Wd / 2) / S1; ws.cy = iy - (py - Wd / 2) / S1;
    applyView();
  }
  // panning, pinching and zooming the photograph
  var pointers = {}, pinch = null;
  function vpPoint(e) { var r = vp.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  vp.addEventListener('pointerdown', function (e) {
    if (!state.study || (e.target.closest && e.target.closest('.pin'))) { return; }
    pointers[e.pointerId] = vpPoint(e);
    var ids = Object.keys(pointers);
    if (ids.length === 2) {
      var a = pointers[ids[0]], b = pointers[ids[1]];
      pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]) || 1, z: ws.z };
    }
    if (ws.z > 1 || ids.length === 2) { try { vp.setPointerCapture(e.pointerId); } catch (err) { /* not capturable */ } vp.classList.add('panning'); }
  });
  vp.addEventListener('pointermove', function (e) {
    var prev = pointers[e.pointerId];
    if (!prev) { return; }
    var now = vpPoint(e), ids = Object.keys(pointers);
    pointers[e.pointerId] = now;
    if (ids.length === 2 && pinch) {
      var a = pointers[ids[0]], b = pointers[ids[1]];
      zoomAt(pinch.z * Math.hypot(a[0] - b[0], a[1] - b[1]) / pinch.d, (a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
      return;
    }
    if (ws.z <= 1) { return; }
    var S = scaleNow();
    ws.cx -= (now[0] - prev[0]) / S; ws.cy -= (now[1] - prev[1]) / S;
    applyView();
  });
  function endPointer(e) {
    delete pointers[e.pointerId];
    if (Object.keys(pointers).length < 2) { pinch = null; }
    if (!Object.keys(pointers).length) { vp.classList.remove('panning'); }
  }
  vp.addEventListener('pointerup', endPointer);
  vp.addEventListener('pointercancel', endPointer);
  vp.addEventListener('dblclick', function (e) { var p = vpPoint(e); zoomAt(ws.z >= 8 ? 1 : ws.z * 2, p[0], p[1]); });
  vp.addEventListener('wheel', function (e) {
    if (!(e.ctrlKey || e.metaKey) || !state.study) { return; }
    e.preventDefault();
    var p = vpPoint(e);
    zoomAt(ws.z * Math.exp(-e.deltaY * 0.0025), p[0], p[1]);
  }, { passive: false });
  vp.addEventListener('keydown', function (e) {
    var st = state.study;
    if (!st) { return; }
    var step = st.c.D / ws.z * 0.1, used = true;
    if (e.key === '+' || e.key === '=') { zoomAt(ws.z * 1.5); }
    else if (e.key === '-') { zoomAt(ws.z / 1.5); }
    else if (e.key === '0') { ws.z = 1; applyView(); }
    else if (e.key === 'ArrowLeft') { ws.cx -= step; applyView(); }
    else if (e.key === 'ArrowRight') { ws.cx += step; applyView(); }
    else if (e.key === 'ArrowUp') { ws.cy -= step; applyView(); }
    else if (e.key === 'ArrowDown') { ws.cy += step; applyView(); }
    else if (e.key === 'Escape') { if (ws.sel >= 0) { selectFinding(ws.sel, false); } }
    else { used = false; }
    if (used) { e.preventDefault(); }
  });
  vp.addEventListener('click', function (e) { if (e.target === pinsSvg && ws.sel >= 0 && !Object.keys(pointers).length) { selectFinding(ws.sel, false); } });
  var resizeT = null;
  window.addEventListener('resize', function () { clearTimeout(resizeT); resizeT = setTimeout(applyView, 80); });

  function lines(box, arr) {                              // one line each; after the second they are hidden on a phone
    box.innerHTML = '';
    arr.forEach(function (l, k) {
      var d = el('div', k > 1 ? 'more' : '');
      if (l.b) { d.append(el('b', '', l.b)); if (l.s) { d.append(txt(' ' + l.s)); } } else { d.append(txt(l)); }
      box.append(d);
    });
  }
  function renderHud() {
    var st = state.study, p = st.patient;
    lines($('#hud-tl'), [{ b: p.id }, [sexAge(p), odos(p.eye)].filter(Boolean).join(' · '), t('hud.mod'), st.id + ' · ' + fmtTime(st.when)]);
    renderHudTR();
    var box = $('#hud-br'), c = st.c;
    box.innerHTML = '';
    box.hidden = !hasLayers(c);
    if (box.hidden) { return; }
    var q = [0, 0, 0, 0];
    findingsOf(c).forEach(function (f) { if (f.q >= 1 && f.q <= 4) { q[f.q - 1]++; } });
    box.append(el('div', 'h', t('hud.quad')));
    // laid out as the photograph is: temporal on the left for a right eye, on the right for a left eye
    (c.res.anatomy.eye === 'L' ? [2, 1, 3, 4] : [1, 2, 4, 3]).forEach(function (k) {
      var s = el('span');
      s.title = t('qd.' + k);
      s.append(txt(QN[k]), el('b', '', String(q[k - 1])));
      box.append(s);
    });
  }
  function renderHudTR() {
    var st = state.study;
    if (!st) { return; }
    var a = st.c.res.anatomy, l = [{ b: t('vw.' + ws.view).toUpperCase(), s: '· ' + nf(ws.z * 100) + '%' }];
    if (a) { l.push(t('hud.um', { v: nf(a.umPerPx, 1) })); }
    lines($('#hud-tr'), l);
  }
  function renderScale() {
    var sb = $('#scalebar'), st = state.study, a = st && st.c.res.anatomy, S = scaleNow();
    if (!a || !S) { sb.hidden = true; return; }
    sb.hidden = false;
    var um = a.umPerPx, target = 110 / S * um, len = 50;
    [50, 100, 200, 250, 500, 1000, 2000, 5000].forEach(function (o) { if (o <= target) { len = o; } });
    $('i', sb).style.width = (len / um * S).toFixed(1) + 'px';
    $('span', sb).textContent = len >= 1000 ? nf(len / 1000) + ' mm' : nf(len) + ' µm';
  }
  function renderLegend() {
    var box = $('#ws-legend'), c = state.study.c;
    box.innerHTML = '';
    if (!hasLayers(c)) { box.append(el('span', '', t('ws.notGraded'))); return; }
    var n = countsOf(c);
    ['ma', 'he', 'ex', 'cws', 'nv'].forEach(function (k) {
      var s = el('span'), i = el('i');
      i.style.background = LCOL[k];
      s.append(i, txt(t('lt.' + k) + ' '), el('b', 'mono', String(n[k])));
      if (!n[k]) { s.classList.add('zero'); }
      box.append(s);
    });
    box.append(el('span', 'hint', t('lg.hint')));
  }

  /* ================================================================ result cards */
  function reasonsOf(r) {
    var out = [];
    if (r.decision.triage === 'RECAPTURE') {
      if (r.quality.noFundus) { return [t('fs.none')]; }
      r.quality.feedback.forEach(function (f) { out.push(t(f.key.replace('fb.', 'fs.'))); });
      if (!out.length) { out.push(t('rs.quality', { v: nf(r.quality.score, 2) })); }
      return out;
    }
    out.push(aiGrade(r) + ' · ' + t('lv.' + aiGrade(r)));
    r.decision.reasons.forEach(function (x) {
      switch (x.key) {
        case 'r.pRef': out.push(t('rs.pRef', { v: pct(x.value), t: pct(x.threshold) })); break;
        case 'r.low': out.push(t('rs.low', { v: pct(x.value), t: pct(x.threshold) })); break;
        case 'r.pUrgent': out.push(t('rs.pUrgent', { v: pct(x.value) })); break;
        case 'r.borderline': out.push(t('rs.borderline', { v: nf(x.score, 2) })); break;
        case 'r.anatomy': out.push(t('flag.' + x.flag)); break;
        default: out.push(t(x.key.replace('r.', 'rs.')));
      }
    });
    return out;
  }
  function mismatch(st) {
    var a = st.c.res.anatomy;
    if (!a || a.flags.length || a.od.confidence < 0.5 || a.eye === st.patient.eye) { return null; }
    return { eye: a.eye, text: t('mm.text', { side: t('side.' + a.eye), eye: t('eye.' + a.eye), rec: t('eye.' + st.patient.eye) }) };
  }
  function renderDecision(st) {
    var r = st.c.res, key = keyOf(st), box = $('#decision');
    box.className = 'decision t-' + key;
    box.innerHTML = '';
    var mid = el('div'), why = el('div', 'why');
    mid.append(el('b', '', t('fu.' + key)));
    reasonsOf(r).forEach(function (s) { why.append(el('span', '', s)); });
    mid.append(why);
    var mm = mismatch(st);
    if (mm) {
      var w = el('div', 'warnline');
      w.append(icon('i-alert'), el('span', '', mm.text), btn('btn btn-sm', t('mm.fix', { eye: t('eye.' + mm.eye) }), function () {
        st.patient.eye = mm.eye;
        if ($('#f-id').value.trim() === st.patient.id) { setFormEye(mm.eye); }
        renderStudy();
        renderQueue();
      }));
      mid.append(w);
    }
    var acts = el('div', 'acts');
    if (r.decision.triage === 'RECAPTURE') { acts.append(btn('btn', t('act.retake'), function () { scrollToEl($('.intake')); })); }
    else if (st.queued) {
      var rb = btn('btn', null, function () { rv.sel = st; rv.startAt = 0; go('review'); });
      rb.append(icon('i-list'), txt(t('act.review')));
      acts.append(rb);
    }
    var nb = btn('btn btn-dark', null, newPatient);
    nb.append(icon('i-plus'), txt(t('act.new')));
    acts.append(nb);
    box.append(el('span', 'lab', t('tri.' + key)), mid, acts);
  }
  function qualityChip(q, rec) {
    if (rec) { return statusChip('bad', t('q.RECAPTURE')); }
    var s = ' · ' + nf(q.score, 2);
    if (q.decision === 'GRADABLE' && q.enhanced) { return statusChip('ok', t('q.after') + s); }
    return statusChip(q.decision === 'GRADABLE' ? 'ok' : 'warn', t('q.' + q.decision) + s);
  }
  function qbars(q) {
    var box = el('div', 'qbars');
    ['field', 'focus', 'illumination', 'contrast', 'artifact'].forEach(function (k) {
      var row = el('div', 'qbar'), tr = el('div', 'track'), fi = el('i'), v = q.sub[k];
      fi.style.width = (100 * clamp(v, 0, 1)).toFixed(1) + '%';
      fi.style.background = v >= 0.5 ? 'var(--accent)' : 'var(--bad)';
      tr.append(fi, el('u'));
      row.append(el('span', '', t('q.sub.' + k)), tr, el('b', '', nf(v, 2)));
      box.append(row);
    });
    return box;
  }
  function renderQuality(st) {
    var box = $('#c-quality'), r = st.c.res, q = r.quality, rec = r.decision.triage === 'RECAPTURE';
    box.innerHTML = '';
    var h = el('div', 'card-h'), h2 = el('h2');
    h2.append(icon('i-eye'), el('span', '', t('qc.title')));
    h.append(h2, qualityChip(q, rec));
    box.append(h);
    if (rec) {
      var rt = el('div', 'retake'), big = el('div', 'big'), body = el('div');
      big.append(icon('i-camera'));
      body.append(el('b', '', t('qc.retake')));
      var fb = q.noFundus ? [t('fb.none')] : q.feedback.map(function (f) { return t(f.key); });
      fb.forEach(function (s) { body.append(el('span', '', s)); });
      rt.append(big, body);
      box.append(rt);
    }
    if (!q.noFundus) { box.append(qbars(q)); }
    if (q.enhanced && q.afterEnhancement) { box.append(el('p', 'fine', t('qc.enh', { a: nf(q.score, 2), b: nf(q.afterEnhancement.score, 2) }))); }
    box.append(el('p', 'fine', t('qc.rule')));
  }
  function renderProbCard(st) {
    var r = st.c.res, box = $('#prob'), ok = graded(r);
    box.closest('.card').hidden = !ok;
    box.innerHTML = '';
    if (!ok) { return; }
    var g = aiGrade(r);
    r.fusion.P.forEach(function (p, k) {
      var row = el('div', 'prob-row' + (k === g ? ' best' : '')), tr = el('div', 'track'), fi = el('i');
      fi.style.width = (100 * p).toFixed(1) + '%';
      fi.style.background = GCOL[k];
      tr.append(fi);
      row.append(el('span', '', k + ' · ' + t('lv.' + k)), tr, el('b', '', pct(p)));
      box.append(row);
    });
    var pr = el('div', 'pref'), left = el('span');
    left.append(txt(t('pb.ref') + ' '), el('span', 'fine', '(' + t('pb.thr', { v: '50%' }) + ')'));
    pr.append(left, el('b', '', pct(r.decision.pReferable)));
    box.append(pr);
  }
  function renderFindings() {
    var st = state.study, box = $('#findings'), ok = graded(st.c.res), F = findingsOf(st.c);
    box.closest('.card').hidden = !ok;
    box.innerHTML = '';
    $('#fl-count').textContent = ok ? '(' + nf(F.length) + ')' : '';
    if (!ok) { return; }
    if (!F.length) { box.append(el('p', 'fine', t('fl.none'))); return; }
    F.forEach(function (f, i) {
      var b = btn('frow' + (i === ws.sel ? ' sel' : ''), null, function () { selectFinding(i, true); }), ty = el('span', 'type'), dot = el('i');
      b.setAttribute('aria-pressed', String(i === ws.sel));
      dot.style.background = LCOL[f.k];
      ty.append(dot, txt(f.k === 'nv' ? f.sub : f.k.toUpperCase()));
      ty.title = t('lt.' + f.k);
      var where = [];
      if (f.k === 'he') { where.push(t('hs.' + f.sub)); }
      if (f.q) { where.push(QN[f.q]); }
      if (f.um) { where.push(nf(f.um) + ' µm'); }
      if (f.k === 'nv') { where.push(t('tp.score', { v: nf(f.score, 1) })); }
      b.append(el('span', 'no', pad(i + 1, 2)), ty, el('span', 'loc', where.join(' · ')), el('span', 'conf', pct(f.prob)));
      box.append(b);
    });
  }
  function renderSummary(st) {
    var box = $('#summary'), r = st.c.res, p = st.patient, e = p.eye;
    box.innerHTML = '';
    var who = p.age !== null && p.age !== undefined ? t('sm.who', { Eye: t('Eye.' + e), eye: t('eye.' + e), age: nf(p.age), sexw: t('sxw.' + p.sex) }) : t('sm.eye', { Eye: t('Eye.' + e), eye: t('eye.' + e) });
    if (p.dm !== null && p.dm !== undefined) { who += t('sm.dm', { n: nf(p.dm) }); }
    if (p.a1c !== null && p.a1c !== undefined) { who += t('sm.a1c', { v: nf(p.a1c, 1) }); }
    var s = [who + t('sm.end')];
    if (!graded(r)) {
      box.append(txt(s[0] + ' '), el('b', '', t('sm.retake', { why: reasonsOf(r).join(', ').toLowerCase() }) + ' ' + t('fu.RECAPTURE') + t('sm.end')));
      return;
    }
    var q = r.quality, L = r.lesions.summary, parts = [], n = countsOf(st.c);
    s.push(t('sm.q', { v: nf(q.score, 2), d: t(q.decision === 'GRADABLE' && q.enhanced ? 'q.after' : 'q.' + q.decision).toLowerCase() }));
    if (n.ma) { parts.push(count('l.ma', n.ma)); }
    if (n.he) {
      var hp = [];
      ['dot', 'blot', 'flame', 'preretinal'].forEach(function (k) { if (L.heCounts[k]) { hp.push(t('hp.' + k, { n: nf(L.heCounts[k]) })); } });
      parts.push(count('l.he', n.he, { parts: hp.join(', ') }));
    }
    if (n.ex) { parts.push(count('l.ex', n.ex)); }
    if (n.cws) { parts.push(count('l.cws', n.cws)); }
    if (n.nv) { parts.push(count('l.nv', n.nv)); }
    s.push(parts.length ? t('sm.found', { list: joinList(parts) }) : t('sm.nothing'));
    var qc = [0, 0, 0, 0], tot = 0;
    findingsOf(st.c).forEach(function (f) { if (f.q) { qc[f.q - 1]++; tot++; } });
    var top = qc.indexOf(Math.max.apply(null, qc));
    if (tot >= 4 && qc[top] > tot / 2) { s.push(t('sm.where', { q: t('qd.' + (top + 1)) })); }
    if (n.ex && isFinite(L.exMinDistFoveaDD)) { s.push(t('sm.ex', { d: nf(L.exMinDistFoveaDD, 1) })); }
    var g = aiGrade(r);
    box.append(txt(s.join(' ') + ' '), el('b', '', t('sm.grade', { g: g, name: t('lv.' + g), p: pct(r.fusion.P[g]), r: pct(r.decision.pReferable) }) + ' ' + t('fu.' + keyOf(st)) + t('sm.end')));
  }
  var DUE = { ROUTINE: [12, 'm'], REFER: [28, 'd'], REFER_DME: [14, 'd'], URGENT: [7, 'd'], HUMAN_REVIEW: [2, 'd'], RECAPTURE: [0, 'd'] };
  function dueOf(st) {
    var d = new Date(st.when), u = DUE[keyOf(st)] || [0, 'd'];
    if (u[1] === 'm') { d.setMonth(d.getMonth() + u[0]); } else { d.setDate(d.getDate() + u[0]); }
    return d;
  }
  function patientMessage(st, L) {
    var saved = lang, key = keyOf(st), s;
    lang = L;
    try { s = t('pm.' + key) + (key === 'RECAPTURE' ? '' : ' ' + t('pm.by', { d: fmtDate(dueOf(st)) })); } finally { lang = saved; }
    return s;
  }
  function copyText(text, b, node) {
    function done(ok) { b.textContent = ok ? t('msg.copied') : t('msg.sel'); setTimeout(function () { b.textContent = t('msg.copy'); }, 1800); }
    function fallback() {
      var r = document.createRange(), s = window.getSelection(), ok = false;
      r.selectNodeContents(node); s.removeAllRanges(); s.addRange(r);
      try { ok = document.execCommand('copy'); } catch (err) { ok = false; }
      done(ok);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text).then(function () { done(true); }, fallback); } else { fallback(); }
  }
  function renderFollowup(st) {
    var box = $('#followup'), key = keyOf(st), due = dueOf(st);
    box.innerHTML = '';
    var when = el('div', 'when'), cal = el('div', 'cal'), tx = el('div');
    cal.append(el('span', '', due.toLocaleDateString(loc(), { month: 'short' }).replace('.', '')), el('b', '', nf(due.getDate())));
    tx.append(el('b', '', t('fu.' + key)), el('span', '', key === 'RECAPTURE' ? t('fd.today') : t('fd.due', { d: fmtDate(due) })));
    when.append(cal, tx);
    box.append(when);
    if (st.patient.a1c !== null && st.patient.a1c !== undefined && st.patient.a1c > 7) {
      var ul = el('ul', 'advice'), li = el('li');
      li.append(icon('i-alert'), el('span', '', t('ad.a1c', { v: nf(st.patient.a1c, 1) })));
      ul.append(li);
      box.append(ul);
    }
    var msg = el('div', 'msg');
    msg.append(el('b', '', t('msg.title')));
    ['en', 'hi'].forEach(function (L) {
      var p = el('p', '', patientMessage(st, L)), row = el('div', 'row'), b = btn('btn btn-sm', t('msg.copy'), function () { copyText(p.textContent, b, p); });
      p.lang = L;
      b.prepend(icon('i-copy'));
      b.setAttribute('aria-label', t('msg.copy') + ' · ' + (L === 'en' ? 'English' : 'हिन्दी'));
      var lab = el('span', 'tag', L === 'en' ? 'English' : 'हिन्दी');
      lab.lang = L;
      row.append(lab, b);
      msg.append(row, p);
    });
    box.append(msg);
  }

  /* ================================================================ review queue */
  var rv = { sel: null, startAt: 0, timer: null }, repLang = 'both';
  var URG = { URGENT: 0, REFER_DME: 1, REFER: 2, HUMAN_REVIEW: 3, ROUTINE: 4 };
  function ordered() {
    return studies.slice().sort(function (a, b) {
      var wa = a.status === 'wait', wb = b.status === 'wait';
      if (wa !== wb) { return wa ? -1 : 1; }
      return wa ? URG[keyOf(a)] - URG[keyOf(b)] || a.when - b.when : b.when - a.when;
    });
  }
  function statusOf(st) {
    if (st.status === 'ok') { return statusChip('ok', t('ss.ok')); }
    if (st.status === 'chg') { return statusChip('warn', t('ss.chg', { g: st.review.grade })); }
    if (st.status === 'ungr') { return statusChip('mute', t('ss.ungr')); }
    return statusChip('info', t('ss.wait'));
  }
  function renderQueue() {
    var wait = studies.filter(function (s) { return s.status === 'wait'; }).length, badge = $('#q-count');
    badge.hidden = !wait;
    badge.textContent = String(wait);
    var times = studies.filter(function (s) { return s.review; }).map(function (s) { return s.review.secs; }).sort(function (a, b) { return a - b; });
    var mid = times.length >> 1, med = times.length ? (times.length % 2 ? times[mid] : (times[mid - 1] + times[mid]) / 2) : 0;
    var stats = $('#rv-stats');
    stats.innerHTML = '';
    [[t('st.n'), nf(studies.length)], [t('st.wait'), nf(wait)], [t('st.med'), times.length ? nf(med, 1) + ' s' : '–'],
      [t('st.u30'), times.length ? pct(times.filter(function (x) { return x <= 30; }).length / times.length) : '–']].forEach(function (s) {
      var d = el('div', 'stat');
      d.append(el('span', '', s[0]), el('b', '', s[1]));
      stats.append(d);
    });
    var rows = ordered(), body = $('#rv-rows');
    if (rv.sel && studies.indexOf(rv.sel) < 0) { rv.sel = null; }
    if (!rv.sel && rows.length) { rv.sel = rows[0]; }
    body.innerHTML = '';
    rows.forEach(function (st) {
      var tr = el('tr', 'row' + (st === rv.sel ? ' sel' : '')), r = st.c.res, key = keyOf(st), p = st.patient, tri = el('td'), stc = el('td'), id = el('td', 'mono', st.id);
      tr.tabIndex = 0;
      tr.setAttribute('aria-selected', String(st === rv.sel));
      if (st.example) { id.append(el('span', 'tag', t('ws.example'))); id.lastChild.style.marginLeft = '8px'; }
      tri.append(statusChip(TRI_CLS[key], t('tri.' + key)));
      stc.append(statusOf(st));
      tr.append(id, el('td', '', [p.id, sexAge(p)].filter(Boolean).join(' · ')), el('td', '', p.phc || '–'), tri,
        el('td', 'n', graded(r) ? String(aiGrade(r)) : '–'), stc, el('td', 'n', st.review ? nf(st.review.secs, 1) + ' s' : '–'));
      function pick() { if (rv.sel !== st) { rv.sel = st; rv.startAt = 0; renderQueue(); } }
      tr.addEventListener('click', pick);
      tr.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); } });
      body.append(tr);
    });
    if (!rows.length) {
      var tr0 = el('tr'), td0 = el('td', 'fine', t('rp.none'));
      td0.colSpan = 7; tr0.append(td0); body.append(tr0);
    }
    renderReport();
    renderPanel();
  }
  $$('#rep-lang button').forEach(function (b) {
    b.addEventListener('click', function () {
      repLang = b.dataset.l;
      $$('#rep-lang button').forEach(function (x) { x.setAttribute('aria-pressed', String(x === b)); });
      renderReport();
    });
  });
  function renderReport() {
    var box = $('#report');
    box.innerHTML = '';
    box.parentNode.hidden = !rv.sel;
    if (!rv.sel) { return; }
    var saved = lang;
    try { buildReport(box, rv.sel); } finally { lang = saved; }
  }
  function reviewText(st) {
    var R = st.review, s = nf(R.secs, 1);
    if (R.kind === 'ungr') { return t('rp.ungrD', { s: s }); }
    if (R.kind === 'set' && R.grade !== aiGrade(st.c.res)) { return t('rp.chg', { g: R.grade, s: s }); }
    return t('rp.ok', { s: s });
  }
  function buildReport(box, st) {
    var c = st.c, r = c.res, key = keyOf(st), L = repLang === 'hi' ? 'hi' : 'en', p = st.patient;
    lang = L;                                             // labels follow the report language
    var band = el('div', 'band'), bt = el('b', '', 'NetraSetu');
    bt.append(el('span', '', t('r.head')));
    band.append(bt, el('small', '', [t('r.study', { id: st.id }), fmtDate(st.when) + ' ' + fmtTime(st.when), t('r.device')].join(' · ')));
    var pt = el('div', 'pt');
    [t('r.pid', { id: p.id }), sexAge(p), t('r.eyeRec', { e: t('Eye.' + p.eye) }) + ' (' + odos(p.eye) + ')', p.dm !== null && p.dm !== undefined ? t('r.dm', { n: nf(p.dm) }) : '',
      p.a1c !== null && p.a1c !== undefined ? t('r.a1c', { v: nf(p.a1c, 1) }) : '', p.phc].forEach(function (s) { if (s) { pt.append(el('span', '', s)); } });
    var ban = el('div', 'ban');
    ban.style.background = TRI_COL[key] || '#5B6272';
    ban.append(el('b', '', t('tri.' + key)), el('span', '', t('fu.' + key)));
    var msgs = el('div', 'msgs');
    if (repLang !== 'hi') { var pe = el('p', '', patientMessage(st, 'en')); pe.lang = 'en'; msgs.append(pe); }
    if (repLang !== 'en') { var ph = el('p', '', patientMessage(st, 'hi')); ph.lang = 'hi'; msgs.append(ph); }
    lang = L;
    box.append(band, pt, ban, msgs);
    var body = el('div', 'body'), pic = canvasOf(640, 640), px = pic.getContext('2d');
    px.fillStyle = '#05070D'; px.fillRect(0, 0, 640, 640);
    var base = c.images.enhanced || c.images.raw;
    if (base) { px.imageSmoothingQuality = 'high'; px.drawImage(base, 0, 0, 640, 640); }
    var ov = overlayOf(c, ['anatomy', 'ma', 'he', 'ex', 'cws', 'nv']);
    if (ov) { px.drawImage(ov, 0, 0, 640, 640); }
    var right = el('div');
    if (graded(r)) {
      right.append(el('h4', '', t('r.p')));
      r.fusion.P.forEach(function (pp, g) {
        var row = el('div', 'pb'), tr = el('div', 't'), fi = el('i');
        fi.style.width = (100 * pp).toFixed(1) + '%'; fi.style.background = GHEX[g];
        tr.append(fi);
        row.append(el('span', '', g + ' · ' + t('lv.s' + g)), tr, el('b', '', pct(pp)));
        right.append(row);
      });
      var s = r.lesions.summary, n = countsOf(c), tb = el('table'), th = el('thead'), hr = el('tr'), tbody = el('tbody');
      hr.append(el('th', '', t('r.find')), el('th', 'n', t('r.count')));
      th.append(hr); tb.append(th);
      var hp = [];
      ['dot', 'blot', 'flame', 'preretinal'].forEach(function (k) { if (s.heCounts[k]) { hp.push(t('hp.' + k, { n: nf(s.heCounts[k]) })); } });
      [[t('r.ma'), n.ma], [t('r.he'), n.he, hp.join(', ')], [t('r.ex'), n.ex], [t('r.cws'), n.cws], [t('r.nv'), n.nv]].forEach(function (rw) {
        var trr = el('tr'), name = el('td', '', rw[0]);
        if (rw[2]) { name.append(el('small', '', rw[2])); }
        trr.append(name, el('td', 'n', nf(rw[1])));
        tbody.append(trr);
      });
      tb.append(tbody);
      tb.style.marginTop = '14px';
      right.append(tb);
    }
    var hq = el('h4', '', t('r.qual'));
    hq.style.marginTop = '14px';
    right.append(hq, el('div', '', r.quality.noFundus ? t('fb.none') : t('r.q', { s: nf(r.quality.score, 2), d: t('q.' + r.quality.decision) })));
    if (r.anatomy) {
      var hl = el('h4', '', t('r.lm'));
      hl.style.marginTop = '14px';
      right.append(hl, el('div', '', t('r.lmV', { d: pct(r.anatomy.od.confidence), f: pct(r.anatomy.fovea.confidence) })));
    }
    body.append(pic, right);
    box.append(body);
    var crit = el('div', 'crit'), met = graded(r) ? r.rules.criteria.filter(function (x) { return x.met; }) : [];
    crit.append(el('h4', '', t('r.crit')));
    if (!met.length) { crit.append(el('div', '', t('r.none'))); }
    met.forEach(function (x) {
      var row = el('div'), dot = el('span', '', '●');
      dot.style.color = ['#0F8A7E', '#6FA35A', '#B8960F', '#E07B0B', '#C8213A'][x.level];
      row.append(dot, el('span', '', t('lv.' + x.level) + ' · ' + (x.id === 'nv' ? t('cr.nv', { w: x.where }) : t('cr.' + x.id)) + ': ' + (x.id === 'nv' ? nf(x.value, 2) : nf(x.value))));
      crit.append(row);
    });
    box.append(crit);
    var foot = el('div', 'foot');
    foot.append(el('span', '', t('r.disc')), el('span', 'sign', st.review ? t('r.done', { what: reviewText(st) }) : t('r.sign') + ':'));
    box.append(foot);
  }
  function renderPanel() {
    var box = $('#rv-panel'), st = rv.sel;
    box.innerHTML = '';
    var h = el('div', 'card-h'), h2 = el('h2');
    h2.append(icon('i-check-c'), el('span', '', t('rp.title')));
    h.append(h2);
    if (st) { h.append(el('span', 'tag', st.id)); }
    box.append(h);
    clearInterval(rv.timer);
    if (!st) { box.append(el('p', 'fine', t('rp.none'))); return; }
    var r = st.c.res, key = keyOf(st), g = aiGrade(r), ai = el('div', 'qline');
    ai.append(statusChip(TRI_CLS[key], t('tri.' + key)), el('span', '', t('rp.ai', { g: g, p: pct(r.decision.pReferable) })));
    box.append(ai);
    var watch = el('div', 'watch'), tm = el('div', 't'), trk = el('div', 'track'), fill = el('i');
    trk.append(fill);
    watch.append(tm, trk);
    box.append(watch);
    function paint() {
      var s = rv.startAt ? (performance.now() - rv.startAt) / 1000 : st.review ? st.review.secs : 0;
      tm.textContent = nf(s, 1) + ' s';
      fill.style.width = Math.min(100, s / 30 * 100).toFixed(1) + '%';
      fill.className = s > 30 ? 'over' : s > 20 ? 'late' : '';
    }
    paint();
    if (rv.startAt) {
      rv.timer = setInterval(function () { if (!document.body.contains(tm)) { clearInterval(rv.timer); return; } paint(); }, 100);
      box.append(btn('btn btn-cta', t('rp.confirm', { d: t('tri.' + key) }), function () { decideReview('ok', g); }));
      box.append(el('div', 'lbl-row', t('rp.set')));
      var gs = el('div', 'rv-grades');
      for (var k = 0; k <= 4; k++) {
        var b = btn('', String(k), decideReview.bind(null, 'set', k));
        b.title = t('lv.' + k);
        gs.append(b);
      }
      box.append(gs, btn('btn', t('rp.ungr'), function () { decideReview('ungr', -1); }), el('p', 'fine', t('rp.keys')));
    } else {
      if (st.review) { box.append(el('p', '', reviewText(st))); }
      box.append(btn('btn btn-dark btn-block', st.review ? t('rp.again') : t('rp.start'), function () { rv.startAt = performance.now(); renderPanel(); }));
    }
    box.append(el('p', 'fine', t('rp.console')));
  }
  function decideReview(kind, grade) {
    var st = rv.sel;
    if (!st || !rv.startAt) { return; }
    var secs = (performance.now() - rv.startAt) / 1000, ai = aiGrade(st.c.res);
    clearInterval(rv.timer);
    rv.startAt = 0;
    st.review = { secs: secs, kind: kind, grade: kind === 'ok' ? ai : grade };
    st.status = kind === 'ungr' ? 'ungr' : kind === 'set' && grade !== ai ? 'chg' : 'ok';
    renderQueue();
  }
  document.addEventListener('keydown', function (e) {
    if (current !== 'review' || !rv.startAt || !rv.sel || (e.target.closest && e.target.closest('input, select, textarea'))) { return; }
    if (e.key === 'Enter') { e.preventDefault(); decideReview('ok', aiGrade(rv.sel.c.res)); }
    else if (/^[0-4]$/.test(e.key)) { decideReview('set', Number(e.key)); }
    else if (e.key === 'u' || e.key === 'U') { decideReview('ungr', -1); }
  });

  /* ================================================================ district planner */
  var PRESETS = {
    best: { phcEquipped: 33, vans: 0, linkTier: 0, aiMode: 'edge', graders: 1, ophthHours: 1, reviewMode: 'xai' },
    noxai: { phcEquipped: 33, vans: 0, linkTier: 0, aiMode: 'edge', graders: 1, ophthHours: 1, reviewMode: 'plain' },
    cloud: { phcEquipped: 33, vans: 0, linkTier: 0, aiMode: 'cloud', graders: 1, ophthHours: 1, reviewMode: 'xai' },
    g2: { phcEquipped: 33, vans: 0, linkTier: 1, aiMode: 'cloud', graders: 1, ophthHours: 1, reviewMode: 'xai' },
    all: { phcEquipped: 36, vans: 0, linkTier: 0, aiMode: 'edge', graders: 2, ophthHours: 2, reviewMode: 'xai' }
  };
  var plan = Object.assign({}, PRESETS.best), simP = window.NetraSim ? NetraSim.defaults() : null, simS = null, simResult = null, simTimer = null;
  function decisionOf() {
    return { phcEquipped: plan.phcEquipped, vans: plan.vans, linkTier: plan.linkTier, aiMode: plan.aiMode, graders: plan.graders,
      ophthHours: plan.ophthHours, sensitivity: 0.92, reviewMode: plan.reviewMode };
  }
  function requestSim() {
    if (!simP) { return; }
    clearTimeout(simTimer);
    simTimer = setTimeout(function () {
      if (!simS) { simS = NetraSim.scenario(simP); }
      simResult = NetraSim.run(simP, decisionOf(), simS);
      renderSim();
    }, 30);
  }
  $$('#sim-form .stepper').forEach(function (s) {
    $$('button', s).forEach(function (b) {
      b.addEventListener('click', function () {
        var k = s.dataset.k;
        plan[k] = Math.max(+s.dataset.min, Math.min(+s.dataset.max, plan[k] + Number(b.dataset.s)));
        renderControls(); requestSim();
      });
    });
  });
  [['#sim-link', 'linkTier', Number], ['#sim-ai', 'aiMode', String], ['#sim-review', 'reviewMode', String]].forEach(function (g) {
    $$(g[0] + ' button').forEach(function (b) {
      b.addEventListener('click', function () { plan[g[1]] = g[2](b.dataset.v); renderControls(); requestSim(); });
    });
  });
  function renderControls() {
    $$('#sim-form .stepper').forEach(function (s) {
      var k = s.dataset.k, v = plan[k];
      $('output', s).textContent = nf(v);
      $$('button', s)[0].disabled = v <= +s.dataset.min;
      $$('button', s)[1].disabled = v >= +s.dataset.max;
    });
    $$('#sim-link button').forEach(function (b) { b.setAttribute('aria-pressed', String(+b.dataset.v === plan.linkTier)); });
    $$('#sim-ai button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.v === plan.aiMode)); });
    $$('#sim-review button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.dataset.v === plan.reviewMode)); });
    var box = $('#sim-presets');
    box.innerHTML = '';
    Object.keys(PRESETS).forEach(function (k) {
      var p = PRESETS[k], b = btn('btn btn-sm', t('p.' + k), function () { plan = Object.assign({}, p); renderControls(); requestSim(); });
      b.setAttribute('aria-pressed', String(Object.keys(p).every(function (x) { return p[x] === plan[x]; })));
      box.append(b);
    });
  }
  function hours(h) { return h < 1 ? '< 1 ' + t('h') : nf(h, h < 10 ? 1 : 0) + ' ' + t('h'); }
  function renderSim() {
    renderControls();
    var box = $('#sim-out');
    box.innerHTML = '';
    if (!simResult) { return; }
    var K = simResult.kpi, T = simP.target, C = K.constraints, miss = Object.keys(C).filter(function (k) { return C[k] < 0; }).length, edge = plan.aiMode === 'edge';
    var v = el('div', 'verdict ' + (K.feasible ? 'ok' : 'no'));
    v.append(icon(K.feasible ? 'i-check' : 'i-alert'), el('span', '', K.feasible ? t('sim.ok') : t('sim.no', { n: miss })));
    box.append(v);
    var tiles = el('div', 'kpis');
    [
      [t('k.screened'), nf(K.perYear.screened), '≥ ' + nf(T.screensPerYear), C.screens],
      [t('k.routine'), hours(K.turnaround.routineP95), '≤ ' + nf(T.routineP95Hours) + ' ' + t('h'), C.routineP95],
      [t('k.urgent'), edge ? t('onsite') : hours(K.urgentNoticeP95), '≤ ' + nf(T.urgentP95Hours) + ' ' + t('h'), C.urgentP95],
      [t('k.graders'), pct(K.utilisation.graders), '≤ ' + pct(T.maxUtilisation), C.graderLoad],
      [t('k.oph'), pct(K.utilisation.ophthalmologist), '≤ ' + pct(T.maxUtilisation), C.ophthLoad],
      [t('k.sens'), pct(K.programmeSensitivity, 1), '≥ ' + pct(T.programmeSensitivity), C.sensitivity]
    ].forEach(function (k) {
      var d = el('div', 'kpi' + (k[3] < 0 ? ' miss' : ''));
      d.append(el('span', '', k[0]), el('b', '', k[1]), el('small', '', t('k.target', { v: k[2] })));
      tiles.append(d);
    });
    box.append(tiles);
    var facts = el('div', 'facts');
    [[t('k.cost'), '₹' + nf(K.costPerScreen)], [t('k.total'), t('c.lakh', { v: nf(K.cost.total / 1e5, 1) })], [t('k.treat'), nf(K.perYear.reachingTreatment)],
      [t('k.missed'), nf(K.missedReferable)], [t('k.uplink'), pct(K.utilisation.uplink)]].forEach(function (f) {
      var sp = el('span');
      sp.append(txt(f[0] + ': '), el('b', '', f[1]));
      facts.append(sp);
    });
    box.append(facts);
    var costs = el('div', 'costs'), keys = ['cameras', 'technicians', 'links', 'ai', 'graders', 'ophthalmologist', 'vans'], max = 0;
    keys.forEach(function (k) { max = Math.max(max, K.cost[k]); });
    keys.slice().sort(function (a, b) { return K.cost[b] - K.cost[a]; }).forEach(function (k) {
      if (!K.cost[k]) { return; }
      var row = el('div', 'cost-row'), trk = el('div', 'track'), fi = el('i');
      fi.style.width = (100 * K.cost[k] / max).toFixed(1) + '%';
      trk.append(fi);
      row.append(el('span', '', t('c.' + k)), trk, el('b', '', t('c.lakh', { v: nf(K.cost[k] / 1e5, 1) })));
      costs.append(row);
    });
    box.append(el('h2', '', t('c.title')), costs, el('p', 'fine', t('sim.note')));
  }

  /* ================================================================ evidence */
  var G16 = 'Gulshan V et al. JAMA 2016;316(22):2402-10', A16 = 'Abràmoff MD et al. Invest Ophthalmol Vis Sci 2016;57(13):5200-6', A13 = 'Abràmoff MD et al. JAMA Ophthalmol 2013;131(3):351-7';
  var V19 = 'Voets M, Møllersen K, Bongo LA. PLoS One 2019;14(6):e0217541', G19 = 'Gulshan V et al. JAMA Ophthalmol 2019;137(9):987-93', T17 = 'Ting DSW et al. JAMA 2017;318(22):2211-23';
  var A18 = 'Abràmoff MD et al. NPJ Digit Med 2018;1:39', R18 = 'Rajalakshmi R et al. Eye 2018;32(6):1138-44', N19 = 'Natarajan S et al. JAMA Ophthalmol 2019;137(10):1182-8';
  var F12 = 'Fraz MM et al. IEEE Trans Biomed Eng 2012;59(9):2538-48', N04 = 'Niemeijer M et al. Proc SPIE Medical Imaging 2004;5370:648-56', P20 = 'Porwal P et al. Med Image Anal 2020;59:101561';
  var SA20 = 'Guo C et al. SA-UNet, ICPR 2020 (arXiv:2004.03696)', AZ15 = 'Azzopardi G et al. Med Image Anal 2015;19(1):46-57', LK16 = 'Liskowski P, Krawiec K. IEEE Trans Med Imaging 2016;35(11):2369-80';
  // transcribed from netra.eval.benchmarks: [task, dataset, method, metric, value, ci, n, source, verify, chart number]
  var BENCH = [
    ['referable-dr', 'Messidor-2', 'Deep learning (Google), high-sensitivity point', 'se', 0.961, null, 1748, G16, 0, 1],
    ['referable-dr', 'Messidor-2', 'Deep learning (Google), high-sensitivity point', 'sp', 0.939, null, 1748, G16, 0, 1],
    ['referable-dr', 'Messidor-2', 'Deep learning (Google), high-specificity point', 'se', 0.870, [0.811, 0.910], 1748, G16, 0, 2],
    ['referable-dr', 'Messidor-2', 'Deep learning (Google), high-specificity point', 'sp', 0.985, [0.977, 0.991], 1748, G16, 0, 2],
    ['referable-dr', 'Messidor-2', 'Deep learning (Google)', 'auc', 0.990, [0.986, 0.995], 1748, G16, 0, 0],
    ['referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion), per patient', 'se', 0.968, [0.933, 0.988], 874, A16, 0, 3],
    ['referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion), per patient', 'sp', 0.870, [0.842, 0.894], 874, A16, 0, 3],
    ['referable-dr', 'Messidor-2', 'IDx-DR X2.1 (CNN lesion detectors + fusion), per patient', 'auc', 0.980, [0.968, 0.992], 874, A16, 0, 0],
    ['referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors), per patient', 'se', 0.968, [0.944, 0.993], 874, A13, 0, 4],
    ['referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors), per patient', 'sp', 0.594, [0.557, 0.630], 874, A13, 0, 4],
    ['referable-dr', 'Messidor-2', 'Iowa Detection Program (classical lesion detectors), per patient', 'auc', 0.937, [0.916, 0.959], 874, A13, 0, 0],
    ['referable-dr', 'Messidor-2', 'Re-implementation of the 2016 deep learning method on public data', 'auc', 0.853, null, 1748, V19, 0, 0],
    ['referable-dr', 'Aravind, India', 'Deep learning (Google), prospective primary care', 'se', 0.889, [0.858, 0.915], null, G19, 0, 5],
    ['referable-dr', 'Aravind, India', 'Deep learning (Google), prospective primary care', 'sp', 0.922, [0.903, 0.938], null, G19, 0, 5],
    ['referable-dr', 'Sankara Nethralaya, India', 'Deep learning (Google)', 'se', 0.921, [0.901, 0.938], null, G19, 0, 6],
    ['referable-dr', 'Sankara Nethralaya, India', 'Deep learning (Google)', 'sp', 0.952, [0.942, 0.961], null, G19, 0, 6],
    ['referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'se', 0.905, [0.873, 0.930], null, T17, 0, 7],
    ['referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'sp', 0.916, [0.910, 0.922], null, T17, 0, 7],
    ['referable-dr', 'Singapore SiDRP', 'Deep learning ensemble', 'auc', 0.936, [0.925, 0.943], null, T17, 0, 0],
    ['referable-dr', 'US primary care (pivotal trial)', 'IDx-DR, autonomous', 'se', 0.872, [0.818, 0.912], 819, A18, 0, 8],
    ['referable-dr', 'US primary care (pivotal trial)', 'IDx-DR, autonomous', 'sp', 0.907, [0.883, 0.927], 819, A18, 0, 8],
    ['referable-dr', 'Chennai, India (smartphone camera)', 'EyeArt on Remidio Fundus-on-Phone, sight-threatening DR', 'se', 0.991, null, 296, R18, 1, 9],
    ['referable-dr', 'Chennai, India (smartphone camera)', 'EyeArt on Remidio Fundus-on-Phone, sight-threatening DR', 'sp', 0.804, null, 296, R18, 1, 9],
    ['referable-dr', 'Mumbai, India (smartphone camera)', 'Medios offline AI, on device', 'se', 1.000, [0.782, 1.000], 213, N19, 0, 10],
    ['referable-dr', 'Mumbai, India (smartphone camera)', 'Medios offline AI, on device', 'sp', 0.884, [0.832, 0.925], 213, N19, 0, 10],
    ['dr-grading', 'APTOS 2019 (private test)', 'Competition winner (ensemble of CNNs)', 'qwk', 0.936, null, null, 'Kaggle APTOS 2019 Blindness Detection, private leaderboard', 0, 0],
    ['dr-grading', 'IDRiD (test)', 'Best challenge entry (LzyUNCC), DR and DME grade both correct', 'acc', 0.6311, null, 103, P20, 0, 0],
    ['vessels', 'DRIVE', 'Second human observer', 'se', 0.776, null, 20, F12, 0, 0], ['vessels', 'DRIVE', 'Second human observer', 'sp', 0.972, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'Second human observer', 'acc', 0.947, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'Matched filter (Chaudhuri 1989), single technique', 'acc', 0.8773, null, 20, N04, 0, 0], ['vessels', 'DRIVE', 'Matched filter (Chaudhuri 1989), single technique', 'auc', 0.7878, null, 20, N04, 0, 0],
    ['vessels', 'DRIVE', 'Morphology + curvature (Zana & Klein 2001), single technique', 'acc', 0.9377, null, 20, N04, 0, 0], ['vessels', 'DRIVE', 'Morphology + curvature (Zana & Klein 2001), single technique', 'auc', 0.8984, null, 20, N04, 0, 0],
    ['vessels', 'DRIVE', 'Ridge features + kNN (Staal 2004)', 'acc', 0.9441, null, 20, N04, 0, 0], ['vessels', 'DRIVE', 'Ridge features + kNN (Staal 2004)', 'auc', 0.9520, null, 20, N04, 0, 0],
    ['vessels', 'DRIVE', 'Gabor wavelet + GMM (Soares 2006)', 'acc', 0.9466, null, 20, F12, 0, 0], ['vessels', 'DRIVE', 'Gabor wavelet + GMM (Soares 2006)', 'auc', 0.9614, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'Multiscale line detector (Nguyen 2013), single technique', 'acc', 0.9407, null, 20, 'Nguyen UTV et al. Pattern Recognit 2013;46(3):703-15', 1, 0],
    ['vessels', 'DRIVE', 'Grey-level + moment features, neural network (Marín 2011)', 'acc', 0.9452, null, 20, F12, 0, 0], ['vessels', 'DRIVE', 'Grey-level + moment features, neural network (Marín 2011)', 'auc', 0.9588, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'se', 0.7406, null, 20, F12, 0, 0], ['vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'sp', 0.9807, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'acc', 0.9480, null, 20, F12, 0, 0], ['vessels', 'DRIVE', 'Ensemble of bagged trees (Fraz 2012)', 'auc', 0.9747, null, 20, F12, 0, 0],
    ['vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015), unsupervised', 'se', 0.7655, null, 20, AZ15, 0, 0], ['vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015), unsupervised', 'sp', 0.9704, null, 20, AZ15, 0, 0],
    ['vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015), unsupervised', 'acc', 0.9442, null, 20, AZ15, 0, 0], ['vessels', 'DRIVE', 'B-COSFIRE (Azzopardi 2015), unsupervised', 'auc', 0.9614, null, 20, AZ15, 0, 0],
    ['vessels', 'DRIVE', 'Deep CNN (Liskowski & Krawiec 2016)', 'acc', 0.9535, null, 20, LK16, 0, 0], ['vessels', 'DRIVE', 'Deep CNN (Liskowski & Krawiec 2016)', 'auc', 0.9790, null, 20, LK16, 0, 0],
    ['vessels', 'DRIVE', 'SA-UNet (Guo 2020), images resized to 592 × 592', 'se', 0.8212, null, 20, SA20, 0, 0], ['vessels', 'DRIVE', 'SA-UNet (Guo 2020), images resized to 592 × 592', 'sp', 0.9840, null, 20, SA20, 0, 0],
    ['vessels', 'DRIVE', 'SA-UNet (Guo 2020), images resized to 592 × 592', 'acc', 0.9698, null, 20, SA20, 0, 0], ['vessels', 'DRIVE', 'SA-UNet (Guo 2020), images resized to 592 × 592', 'auc', 0.9864, null, 20, SA20, 0, 0],
    ['lesion-seg', 'IDRiD', 'Best challenge entry (iFLYTEK), microaneurysms', 'aupr', 0.5017, null, 27, P20, 0, 0],
    ['lesion-seg', 'IDRiD', 'Best challenge entry (VRT), haemorrhages', 'aupr', 0.6804, null, 27, P20, 0, 0],
    ['lesion-seg', 'IDRiD', 'Best challenge entry (PATech), hard exudates', 'aupr', 0.8850, null, 27, P20, 0, 0],
    ['lesion-seg', 'IDRiD', 'Best challenge entry (VRT), soft exudates', 'aupr', 0.6995, null, 27, P20, 0, 0],
    ['landmarks', 'IDRiD', 'Best challenge entry (DeepDR), optic disc centre, px at 4288 × 2848 (lower is better)', 'px', 21.072, null, 103, P20, 0, 0],
    ['landmarks', 'IDRiD', 'Best challenge entry (DeepDR), fovea centre, px (lower is better)', 'px', 64.492, null, 103, P20, 0, 0],
    ['landmarks', 'IDRiD', 'Hand-crafted features (CBER), optic disc centre, px', 'px', 29.183, null, 103, P20, 0, 0],
    ['landmarks', 'IDRiD', 'Hand-crafted features (CBER), fovea centre, px', 'px', 59.751, null, 103, P20, 0, 0],
    ['landmarks', 'IDRiD', 'Best challenge entry (ZJU-BII-SGEX), optic disc segmentation', 'jaccard', 0.9338, null, 27, P20, 0, 0],
    ['standard', 'any', 'British Diabetic Association / Exeter standard, sight-threatening DR', 'se', 0.80, null, null, 'British Diabetic Association, 1997', 0, 0],
    ['standard', 'any', 'British Diabetic Association / Exeter standard, sight-threatening DR', 'sp', 0.95, null, null, 'British Diabetic Association, 1997', 0, 0],
    ['standard', 'any', 'FDA pivotal-trial endpoints (IDx-DR)', 'se', 0.85, null, null, A18, 0, 0],
    ['standard', 'any', 'FDA pivotal-trial endpoints (IDx-DR)', 'sp', 0.825, null, null, A18, 0, 0],
    ['standard', 'any', 'NetraSetu target, referable DR (level 2+)', 'se', 0.90, null, null, 'Problem statement', 0, 0],
    ['standard', 'any', 'NetraSetu target, referable DR (level 2+)', 'sp', 0.85, null, null, 'Problem statement', 0, 0]
  ];
  var TASKS = ['referable-dr', 'vessels', 'lesion-seg', 'landmarks', 'dr-grading', 'standard'], task = 'referable-dr', benchDone = false;
  var METRIC = { se: 'Sensitivity', sp: 'Specificity', auc: 'AUC', acc: 'Accuracy', qwk: 'Weighted kappa', aupr: 'AUPR', px: 'Distance (px)', jaccard: 'Jaccard' };
  var COLS = { 'referable-dr': ['se', 'sp', 'auc'], vessels: ['se', 'sp', 'acc', 'auc'], 'lesion-seg': ['aupr'], landmarks: ['px', 'jaccard'], 'dr-grading': ['qwk', 'acc'], standard: ['se', 'sp'] };
  function renderBenchmarks() {
    benchDone = true;
    var tabs = $('#v-tabs');
    tabs.innerHTML = '';
    TASKS.forEach(function (k) {
      var bt = btn('', t('bm.tab.' + k), function () { task = k; renderBenchmarks(); });
      bt.setAttribute('role', 'tab');
      bt.setAttribute('aria-selected', String(k === task));
      tabs.append(bt);
    });
    var rows = [], byKey = {};
    BENCH.filter(function (x) { return x[0] === task; }).forEach(function (x) {
      var key = x[1] + '|' + x[2] + '|' + x[7];
      if (!byKey[key]) { byKey[key] = { ds: x[1], me: x[2], n: x[6], src: x[7], verify: x[8], no: x[9], m: {} }; rows.push(byKey[key]); }
      byKey[key].m[x[3]] = { v: x[4], ci: x[5] };
      if (x[9]) { byKey[key].no = x[9]; }
    });
    var cols = COLS[task].filter(function (c) { return rows.some(function (r) { return r.m[c]; }); }), ref = task === 'referable-dr', std = task === 'standard';
    var wrap = $('#v-table'), tb = el('table'), th = el('thead'), hr = el('tr');
    wrap.innerHTML = '';
    if (ref) { hr.append(el('th', '', t('bm.no'))); }
    if (!std) { hr.append(el('th', '', t('bm.ds'))); }
    hr.append(el('th', '', t('bm.me')));
    cols.forEach(function (c) { hr.append(el('th', 'n', METRIC[c])); });
    if (!std) { hr.append(el('th', 'n', t('bm.n'))); }
    hr.append(el('th', '', t('bm.src')));
    th.append(hr); tb.append(th);
    var body = el('tbody');
    rows.forEach(function (r) {
      var tr = el('tr');
      if (ref) { tr.append(el('td', 'mono', r.no ? String(r.no) : '')); }
      if (!std) { tr.append(el('td', '', r.ds)); }
      tr.append(el('td', '', r.me));
      cols.forEach(function (c) {
        var cell = el('td', 'n'), x = r.m[c];
        if (x) {
          cell.append(txt(c === 'px' ? x.v.toFixed(1) : x.v.toFixed(3)));
          if (x.ci) { cell.append(el('small', '', x.ci[0].toFixed(3) + '–' + x.ci[1].toFixed(3))); }
        } else { cell.textContent = '–'; }
        tr.append(cell);
      });
      if (!std) { tr.append(el('td', 'n', r.n ? nf(r.n) : '–')); }
      var src = el('td', '', r.src);
      if (r.verify) { src.append(el('small', '', t('bm.verify'))); }
      tr.append(src);
      body.append(tr);
    });
    tb.append(body); wrap.append(tb);
    $('#v-chart').innerHTML = chartSvg();
  }
  function chartSvg() {
    var pts = {};
    BENCH.forEach(function (x) {
      if (x[0] !== 'referable-dr' || !x[9]) { return; }
      var p = pts[x[9]] || (pts[x[9]] = { no: x[9], verify: x[8], name: x[2], ds: x[1] });
      p[x[3]] = x[4]; p[x[3] + 'ci'] = x[5];
    });
    var Wd = 760, Hd = 440, m = { l: 64, r: 24, t: 20, b: 52 }, x0 = 0.55, x1 = 1.0, y0 = 0.76, y1 = 1.0;
    function X(v) { return m.l + (v - x0) / (x1 - x0) * (Wd - m.l - m.r); }
    function Y(v) { return Hd - m.b - (v - y0) / (y1 - y0) * (Hd - m.t - m.b); }
    var o = [], gx, gy;
    o.push('<svg class="chart" viewBox="0 0 ' + Wd + ' ' + Hd + '" role="img" aria-label="' + t('ch.y') + ' / ' + t('ch.x') + '">');
    o.push('<g class="grid">');
    for (gx = 0.55; gx <= 1.0001; gx += 0.05) { o.push('<line x1="' + X(gx) + '" x2="' + X(gx) + '" y1="' + Y(y0) + '" y2="' + Y(y1) + '"/>'); }
    for (gy = 0.76; gy <= 1.0001; gy += 0.04) { o.push('<line x1="' + X(x0) + '" x2="' + X(x1) + '" y1="' + Y(gy) + '" y2="' + Y(gy) + '"/>'); }
    o.push('</g>');
    o.push('<rect class="target" x="' + X(0.85) + '" y="' + Y(1.0) + '" width="' + (X(1.0) - X(0.85)) + '" height="' + (Y(0.90) - Y(1.0)) + '"/>');
    [[0.95, 0.80, ['ch.bda1', 'ch.bda2'], -8, 18], [0.825, 0.85, ['ch.fda'], -8, -12]].forEach(function (sd) {
      o.push('<rect class="std" x="' + (X(sd[0]) - 6) + '" y="' + (Y(sd[1]) - 6) + '" width="12" height="12"/>');
      sd[2].forEach(function (k, j) { o.push('<text x="' + (X(sd[0]) + sd[3]) + '" y="' + (Y(sd[1]) + sd[4] + 16 * j) + '" text-anchor="end">' + t(k) + '</text>'); });
    });
    Object.keys(pts).forEach(function (k) {
      var p = pts[k], cx = X(p.sp), cy = Y(p.se);
      if (p.seci) { o.push('<line class="ci" x1="' + cx + '" x2="' + cx + '" y1="' + Y(p.seci[0]) + '" y2="' + Y(p.seci[1]) + '"/>'); }
      if (p.spci) { o.push('<line class="ci" x1="' + X(p.spci[0]) + '" x2="' + X(p.spci[1]) + '" y1="' + cy + '" y2="' + cy + '"/>'); }
    });
    Object.keys(pts).forEach(function (k) {
      var p = pts[k], cx = X(p.sp), cy = Y(p.se);
      o.push('<g><title>' + p.no + '. ' + p.name.replace(/&/g, '&amp;') + ' · ' + p.ds + ' · Se ' + p.se.toFixed(3) + ', Sp ' + p.sp.toFixed(3) + '</title>');
      o.push('<circle class="pt' + (p.verify ? ' hollow' : '') + '" cx="' + cx + '" cy="' + cy + '" r="10"/>');
      o.push('<text class="ptl" x="' + cx + '" y="' + (cy + 3.8) + '" text-anchor="middle"' + (p.verify ? ' style="fill:var(--ink)"' : '') + '>' + p.no + '</text></g>');
    });
    o.push('<g class="axis">');
    o.push('<line x1="' + X(x0) + '" x2="' + X(x1) + '" y1="' + Y(y0) + '" y2="' + Y(y0) + '"/><line x1="' + X(x0) + '" x2="' + X(x0) + '" y1="' + Y(y0) + '" y2="' + Y(y1) + '"/>');
    for (var tx = 0.55; tx <= 1.0001; tx += 0.05) { o.push('<text x="' + X(tx) + '" y="' + (Y(y0) + 20) + '" text-anchor="middle">' + tx.toFixed(2) + '</text>'); }
    for (var ty = 0.76; ty <= 1.0001; ty += 0.04) { o.push('<text x="' + (X(x0) - 10) + '" y="' + (Y(ty) + 4) + '" text-anchor="end">' + ty.toFixed(2) + '</text>'); }
    o.push('<text x="' + ((X(x0) + X(x1)) / 2) + '" y="' + (Hd - 10) + '" text-anchor="middle" class="lbl-strong">' + t('ch.x') + '</text>');
    o.push('<text transform="translate(16 ' + ((Y(y0) + Y(y1)) / 2) + ') rotate(-90)" text-anchor="middle" class="lbl-strong">' + t('ch.y') + '</text>');
    o.push('</g></svg>');
    return o.join('');
  }

  /* ================================================================ start */
  function renderAll() {
    renderTests();
    renderInput();
    setSteps(state.steps);
    if (state.study && !$('#out').hidden) { renderStudy(); }
    renderQueue();
    renderSim();
    if (benchDone) { renderBenchmarks(); }
  }
  var saved = null;
  try { saved = localStorage.getItem('netrasetu-lang'); } catch (err) { /* storage unavailable */ }
  if (saved === 'hi' || saved === 'en') { lang = saved; }
  fillPatient(EXAMPLE);
  applyStatic();
  renderTests();
  renderInput();
  renderQueue();
  route();
  loadSample().then(function (c) {
    if (state.study || state.running) { return; }
    var st = makeStudy(EXAMPLE, c, true);
    $('#steps').hidden = false;
    setSteps(5, c.res.timing);
    showStudy(st);
    renderQueue();
    if (!state.input) { pickTest({ kind: 'eye', n: 3 }, true); }
  }).catch(function () {
    // the sample images need a web server (they are read back into pixels); run the engine instead
    if (!state.study && !state.running) { pickTest({ kind: 'eye', n: 3 }, true).then(function (inp) { if (inp) { screenNow(); } }); }
  });
})();
