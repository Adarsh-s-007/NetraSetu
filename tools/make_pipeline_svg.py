#!/usr/bin/env python3
"""Draw docs/img/pipeline.svg - the NetraSetu architecture at a glance.

Plain SVG, no dependencies: run `python3 tools/make_pipeline_svg.py`.
Colours follow src/+netra/+util/palette.m.
"""
from pathlib import Path

INK, SOFT, PAPER, RULE = "#14182E", "#4A5070", "#FBF8F3", "#E4DED3"
SAFFRON, TEAL, RETINA, BLUE, INDIGO, GREEN = "#E8930C", "#0F8A7E", "#C4441C", "#2a78d6", "#3D4DB7", "#1baf7a"
W, H = 1440, 900
out = []


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def card(x, y, w, h, title, lines, color, tag=None):
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" class="card"/>')
    out.append(f'<rect x="{x}" y="{y}" width="6" height="{h}" rx="3" fill="{color}"/>')
    out.append(f'<text x="{x + 18}" y="{y + 26}" class="h">{esc(title)}</text>')
    if tag:
        out.append(f'<text x="{x + w - 14}" y="{y + 26}" class="tag" fill="{color}">{esc(tag)}</text>')
    for i, t in enumerate(lines):
        out.append(f'<text x="{x + 18}" y="{y + 48 + 17 * i}" class="b">{esc(t)}</text>')


def arrow(points, dashed=False, color=SOFT):
    d = "M" + " L".join(f"{px} {py}" for px, py in points)
    cls = "a dash" if dashed else "a"
    out.append(f'<path d="{d}" class="{cls}" stroke="{color}" marker-end="url(#ah)"/>')


def label(x, y, text, anchor="middle", cls="lab"):
    out.append(f'<text x="{x}" y="{y}" class="{cls}" text-anchor="{anchor}">{esc(text)}</text>')


# ---------------------------------------------------------------- header
out.append(f'<text x="40" y="52" class="title">NetraSetu</text>')
out.append(f'<text x="40" y="78" class="sub">From a photograph taken at a primary health centre to a decision a '
           f'grader can confirm in 30 seconds - and a district plan that makes it happen 100,000 times a year.</text>')

# ---------------------------------------------------------- column 1
card(40, 110, 250, 128, "1  Capture", ["Portable non-mydriatic camera", "at the PHC or a mobile camp",
                                        "technician, both eyes, 6 min"], SAFFRON)
card(40, 262, 250, 196, "2  Quality gate", ["field of view, focus,", "illumination, contrast,",
                                             "artefacts (lashes, flare, haze)", "GRADABLE / ENHANCE / RECAPTURE",
                                             "feedback in Hindi and English:", "“Hold still, refocus, retake”"],
     SAFFRON, "< 1 s")
arrow([(165, 238), (165, 258)])
arrow([(40 + 250, 430), (310, 430), (310, 175), (294, 175)], dashed=True, color=SAFFRON)
label(300, 254, "recapture", anchor="end", cls="lab o")

# ---------------------------------------------------------- column 2
card(340, 110, 270, 150, "3  Standardise", ["aperture circle fitted (clipped too)", "1024-px canvas, 1 DD = 1500 um",
                                              "illumination + colour normalised", "adaptive CLAHE, NL-means denoise"], TEAL)
card(340, 284, 270, 174, "4  Anatomy", ["vessels: Frangi + line detector", "  + top-hat, fusion learned on DRIVE",
                                          "optic disc: 4 independent cues", "fovea: darkness + avascular zone",
                                          "ETDRS grid, quadrants, zones"], TEAL)
arrow([(290, 330), (336, 330)])
arrow([(475, 260), (475, 280)])

# ---------------------------------------------------------- column 3
card(660, 110, 300, 348, "5  Lesions, measured", ["microaneurysms: sub-pixel Gaussian", "  fit, error near the Cramer-Rao bound",
                                                    "haemorrhages: dot / blot / flame /", "  pre-retinal, counted per quadrant",
                                                    "hard exudates vs cotton-wool spots", "  (edge sharpness, Lab yellowness)",
                                                    "macular-oedema zones (1 DD, 500 um)", "neovascularisation (disc / elsewhere)",
                                                    "venous beading (calibre + periodicity)", "IRMA-like anomalies",
                                                    "", "every finding: position, size, probability"], RETINA)
arrow([(610, 370), (656, 370)])

# ---------------------------------------------------------- column 4: three graders
card(1010, 110, 390, 104, "ICDR rule engine", ["the 4-2-1 rule, adapted to one 45° field",
                                                "Monte Carlo over uncertain lesions"], BLUE, "transparent")
card(1010, 226, 390, 104, "Lesion ensemble", ["bagged trees on 32 clinically named features",
                                               "Shapley values: which findings pushed the grade"], BLUE, "interpretable")
card(1010, 342, 390, 116, "CNN", ["ResNet-50, 448 px, ordinal-cost loss, TTA",
                                   "Grad-CAM++ on the referable log-odds, checked", "against the lesions it should be looking at"],
     BLUE, "accurate")
for y in (162, 278, 400):
    arrow([(960, y), (1006, y)])
arrow([(1010, 440), (964, 440)], dashed=True, color=INDIGO)
label(985, 480, "attention-evidence concordance", cls="lab i")

# ---------------------------------------------------------- fusion row
card(1010, 500, 390, 120, "6  Ordinal fusion and calibration", ["proportional-odds stacking of the three branches",
                                                                  "split-conformal grade set (90 % coverage)",
                                                                  "referral threshold with a guaranteed sensitivity"],
     INDIGO)
arrow([(1205, 458), (1205, 496)])

# ---------------------------------------------------------- triage
card(560, 500, 400, 120, "7  Triage", ["RECAPTURE > URGENT > REFER > HUMAN REVIEW > ROUTINE",
                                        "uncertain sets, disagreeing branches, borderline",
                                        "quality or a CNN looking elsewhere go to a person"], INDIGO)
arrow([(1010, 560), (964, 560)])

# ---------------------------------------------------------- outputs
card(40, 500, 470, 120, "8  Explained result", ["annotated fundus + ETDRS grid, criteria with values,",
                                                  "grade probabilities, provenance; A4 report and a",
                                                  "bilingual HTML page that travels over 2G"], GREEN)
arrow([(560, 560), (514, 560)])

# ---------------------------------------------------------- human + district
card(40, 648, 470, 104, "Reader console", ["Enter agrees, 0-4 overrides, R/E/L/A switch views;",
                                            "a stopwatch and an audit log for every decision"], GREEN, "< 30 s")
card(560, 648, 840, 104, "District programme model (Simulink)", [
    "capture -> store-and-forward uplink with outages -> central or edge AI -> grader -> ophthalmologist",
    "age-structured queues give exact turnaround; an optimiser finds the cheapest plan that meets every target"],
     SAFFRON, "100,000+ / year")
arrow([(275, 620), (275, 644)])
arrow([(510, 700), (556, 700)], dashed=True)

# ---------------------------------------------------------- footer
label(40, 800, "Every stage is testable on synthetic eyes with exact ground truth, and validated on APTOS 2019, "
               "IDRiD, DRIVE and Messidor-2 by the experiments in experiments/.", anchor="start", cls="foot")
label(40, 822, "Runs in MATLAB (full pipeline incl. CNN, lesion ensemble, Simulink) and GNU Octave (everything else).",
      anchor="start", cls="foot")

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H - 50}" width="{W}" height="{H - 50}"
 font-family="Noto Sans, Segoe UI, Helvetica, Arial, sans-serif">
<defs><marker id="ah" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
<path d="M0 0 L10 5 L0 10 z" fill="{SOFT}"/></marker></defs>
<style>
.card{{fill:#fff;stroke:{RULE};stroke-width:1.2}}
.h{{font-size:16px;font-weight:700;fill:{INK}}}
.b{{font-size:13px;fill:{SOFT}}}
.tag{{font-size:12px;font-weight:700;text-anchor:end}}
.a{{fill:none;stroke-width:1.6}}
.dash{{stroke-dasharray:5 4}}
.lab{{font-size:12px;fill:{SOFT}}}
.lab.o{{fill:{SAFFRON};font-weight:600}}
.lab.i{{fill:{INDIGO};font-weight:600}}
.title{{font-size:30px;font-weight:800;fill:{INK}}}
.sub{{font-size:15px;fill:{SOFT}}}
.foot{{font-size:13px;fill:{SOFT}}}
</style>
<rect width="100%" height="100%" fill="{PAPER}"/>
{chr(10).join(out)}
</svg>
'''
path = Path(__file__).resolve().parents[1] / "docs" / "img" / "pipeline.svg"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(svg, encoding="utf-8")
print(path)
