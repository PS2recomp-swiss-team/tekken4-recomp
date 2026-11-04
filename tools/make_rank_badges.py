"""Original metallic T4 HUD badge previews and T5DR rank metadata.

The 37 ranks match the T5DR tier indices. SVGs reproduce the host overlay's
160x100 bevel layers, simple emblem and progress rail; no text is inside a badge.
Player-owned T5DR cached art is read only by the runtime and never bundled here.
All generated previews stay in local build artifacts, outside version control.

    python tools/make_rank_badges.py                       build/rank-badges/svg previews
    python tools/make_rank_badges.py --png DIR --height H   PNG previews (PySide6)
    python tools/make_rank_badges.py --header FILE          runtime metadata header
    python tools/make_rank_badges.py --sheet FILE.svg       labelled review sheet
    python tools/make_rank_badges.py --check                verify local SVG previews
"""
import argparse
from html import escape
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# T5DR tier names/order and fallback colour groups. Keep aligned with the launcher's t4lobby/ranks.py.
NAMES = ['Beginner', '9th Kyu', '8th Kyu', '7th Kyu', '6th Kyu', '5th Kyu', '4th Kyu', '3rd Kyu', '2nd Kyu', '1st Kyu', '1st Dan', '2nd Dan', '3rd Dan', '4th Dan', '5th Dan', '6th Dan', '7th Dan', 'Shihan', 'Expert', 'Warrior', 'Master', 'Virtuoso', 'Champion', 'Lone Wolf', 'Destroyer', 'Berserker', 'Sage', 'Legend', 'Fujin', 'Raijin', 'Deity', 'Lord of War', 'Dragon Lord', 'Tekken Lord', 'Dark Lord', 'Tekken Lord (Kouryu)', 'Tekken Lord (Kirin)']
RANK_GROUPS = [(0, 0, 'beginner'), (1, 9, 'kyu'), (10, 16, 'dan'), (17, 18, 'lightblue'), (19, 21, 'green'), (22, 23, 'yellow'), (24, 25, 'orange'), (26, 27, 'red'), (28, 29, 'blue'), (30, 32, 'purple'), (33, 36, 'gold')]

OUT = os.path.join(ROOT, "build", "rank-badges", "svg")
W, H = 160, 100                     # 1.6:1, matching the window-resolution host overlay

# (plate, light, dark, emblem): emblem = ("poly", sides) or ("star", points); 0 sides = circle
PALETTE = {
    "beginner": ("#7d838c", "#c9ccd1", "#3c4047", ("poly", 0)),
    "kyu": ("#8b5a2b", "#d29a5e", "#40260f", ("poly", 3)),
    "dan": ("#8f99a4", "#e6ebf0", "#4a525b", ("poly", 4)),
    "lightblue": ("#2f9ccc", "#a6e2f8", "#15506b", ("poly", 5)),
    "green": ("#2f9446", "#9ee0a8", "#164d22", ("poly", 6)),
    "yellow": ("#c9a514", "#f7e481", "#6b540a", ("star", 4)),
    "orange": ("#de7012", "#f8b673", "#733605", ("star", 5)),
    "red": ("#c22a26", "#f39a94", "#5e0f0d", ("star", 6)),
    "ruler": ("#8f2479", "#e895d8", "#440c39", ("star", 7)),
    "blue": ("#2449c4", "#98aef7", "#0f2063", ("star", 8)),
    "purple": ("#6526c4", "#bb98f7", "#2f0f63", ("star", 10)),
    "gold": ("#cf9a12", "#ffe58a", "#614606", ("star", 12)),
}
GROUPS = [(lo, hi, key, *PALETTE[key]) for lo, hi, key in RANK_GROUPS]
TOP = len(NAMES) - 1                # the top rank: a black plate with a gold rim


def group(tier):
    for g in GROUPS:
        if g[0] <= tier <= g[1]:
            return g
    return GROUPS[0]


def spec(tier):
    """Everything the badge of `tier` is made of (also the C++ header's row)."""
    lo, hi, key, plate, light, dark, (kind, n) = group(tier)
    pips = tier - lo + 1 if hi > lo else 0
    if tier == TOP:
        plate, dark = "#16130c", "#000000"
    return dict(tier=tier, name=NAMES[tier], group=key, plate=plate, light=light, dark=dark, kind=kind, n=n,
                pips=pips, of=hi - lo + 1)


# Geometry mirrors runtime/tekken4_badge_draw.h, in its 160x100 design coordinates.
def _pts(points):
    return " ".join(f"{x:.5f},{y:.5f}" for x, y in points)


def svg(tier):
    s = spec(tier)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
           f"<!-- Original T4 HUD badge {tier}: {s['name']} -->"]

    def polygon(points, colour):
        out.append(f'<polygon points="{_pts(points)}" fill="{colour}"/>')

    def shape(inset):
        return [(16+inset, inset), (144-inset, inset), (160-inset, 50),
                (144-inset, 100-inset), (16+inset, 100-inset), (inset, 50)]

    polygon(shape(0), "#07151f")
    polygon(shape(3), "#c5f2ff")
    polygon(shape(9), "#263746")
    polygon([(16, 9), (144, 9), (151, 30), (9, 30)], "#f2fbff")
    polygon([(9, 70), (151, 70), (144, 91), (16, 91)], "#56869e")
    polygon(shape(16), s["dark"])
    polygon([(28, 18), (132, 18), (144, 49), (16, 49)], s["plate"])
    polygon([(28, 18), (132, 18), (136, 28), (24, 28)], s["light"])
    n = 16 if s["n"] == 0 else min(s["n"], 8)
    count = n * 2 if s["kind"] == "star" else n
    emblem = []
    for i in range(count):
        angle = -1.570796327 + 6.283185307 * i / count
        radius = 30 * (0.48 if s["kind"] == "star" and i % 2 else 1)
        emblem.append((70 + radius * math.cos(angle), 51 + radius * math.sin(angle)))
    for i in range(count):
        polygon([(70, 51), emblem[i], emblem[(i+1) % count]], s["light"])
    polygon([(65, 35), (77, 51), (65, 65), (56, 51)], "#f3fbff")
    polygon([(115, 76), (125, 76), (125, 30), (115, 30)], "#12212b")
    progress = s["pips"] / s["of"] if s["of"] > 0 else 0
    if progress > 0:
        polygon([(115, 76), (125, 76), (125, 76-46*progress), (115, 76-46*progress)], s["light"])
    out.append("</svg>")
    return "\n".join(out) + "\n"


def file_name(tier):
    return "t4_rank_%02d.svg" % tier


def stale_svgs(folder):
    expected = {file_name(tier) for tier in range(len(NAMES))}
    try:
        return sorted(name for name in os.listdir(folder)
                      if re.fullmatch(r"t4_rank_\d{2,}\.svg", name) and name not in expected)
    except FileNotFoundError:
        return []


def write_svgs(folder=OUT):
    os.makedirs(folder, exist_ok=True)
    for tier in range(len(NAMES)):
        with open(os.path.join(folder, file_name(tier)), "w", encoding="utf-8", newline="\n") as f:
            f.write(svg(tier))
    for name in stale_svgs(folder):
        os.remove(os.path.join(folder, name))
    return len(NAMES)


def check(folder=OUT):
    bad = []
    for tier in range(len(NAMES)):
        try:
            with open(os.path.join(folder, file_name(tier)), encoding="utf-8") as f:
                if f.read() != svg(tier):
                    bad.append(file_name(tier))
        except OSError:
            bad.append(file_name(tier))
    return bad + stale_svgs(folder)


def sheet(path):
    cols = 6
    rows = (len(NAMES) + cols - 1) // cols
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {cols * 220} {rows * 130}">',
             f'<rect width="{cols * 220}" height="{rows * 130}" fill="#1b1d22"/>']
    for tier in range(len(NAMES)):
        x, y = (tier % cols) * 220 + 30, (tier // cols) * 130 + 10
        inner = svg(tier).split("\n", 2)[2].rsplit("</svg>", 1)[0]
        parts.append(f'<g transform="translate({x},{y})">{inner}</g>')
        parts.append(f'<text x="{x + W / 2}" y="{y + 114}" text-anchor="middle" font-family="Arial" font-size="12" '
                     f'fill="#aab">{tier}: {escape(NAMES[tier])}</text>')
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


def pngs(folder, height=100):
    from PySide6.QtCore import QByteArray, Qt
    from PySide6.QtGui import QGuiApplication, QImage, QPainter
    from PySide6.QtSvg import QSvgRenderer
    _app = QGuiApplication.instance() or QGuiApplication(["badges"])
    os.makedirs(folder, exist_ok=True)
    for tier in range(len(NAMES)):
        r = QSvgRenderer(QByteArray(svg(tier).encode("utf-8")))
        img = QImage(round(height * W / H), height, QImage.Format_ARGB32_Premultiplied)
        img.fill(Qt.transparent)
        p = QPainter(img)
        p.setRenderHint(QPainter.Antialiasing)
        r.render(p)
        p.end()
        img.save(os.path.join(folder, "t4_rank_%02d.png" % tier))
    return len(NAMES)


# ---------------------------------------------------------------------------------------------- C++ header
def _rgb(h):
    return "0x%s" % h.lstrip("#").upper()


def header(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    rows = []
    for tier in range(len(NAMES)):
        s = spec(tier)
        rows.append('    {"%s", %s, %s, %s, %d, %d, %d, %d},' % (
            s["name"], _rgb(s["plate"]), _rgb(s["light"]), _rgb(s["dark"]), 1 if s["kind"] == "star" else 0, s["n"],
            s["pips"], s["of"]))
    text = f"""// GENERATED by tools/make_rank_badges.py --header (do not edit by hand).
// Tekken 5 DR rank metadata: tier = index (0..36), matching the launcher and T5DR cache.
// Colours and simple emblems describe our own fallback art. The host HUD draws its own
// metallic badge geometry at window resolution; rank names are separate from the emblem.
#pragma once
#include <cstdint>

namespace tekken4_rank_badges
{{
    struct Badge
    {{
        const char *name;
        uint32_t plate, light, dark;   // 0xRRGGBB
        int star;                      // 1 = star with n points, 0 = polygon with n sides (0 = circle)
        int n;
        int pips, of;
    }};
    constexpr int kWidth = {W}, kHeight = {H};
    constexpr int kCount = {len(NAMES)};
    constexpr Badge kBadges[kCount] = {{
{chr(10).join(rows)}
    }};
}}
"""
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--png", metavar="DIR")
    ap.add_argument("--height", type=int, default=100)
    ap.add_argument("--header", metavar="FILE")
    ap.add_argument("--sheet", metavar="FILE")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    if a.check:
        bad = check()
        print("badges up to date" if not bad else "out of date: " + ", ".join(bad))
        return 1 if bad else 0
    if a.png:
        print(pngs(a.png, a.height), "PNG badges in", a.png)
    if a.header:
        header(a.header)
        print("header", a.header)
    if a.sheet:
        sheet(a.sheet)
        print("sheet", a.sheet)
    if not (a.png or a.header or a.sheet):
        print(write_svgs(), "SVG badges in", OUT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
