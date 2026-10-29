"""Which Tekken 4 menu is this 640x448 guest frame? (tools/run_fixed_fight.ps1 navigates with it.)

  python -I tools/menu_screen.py --json <frame.bmp>
      {"screen","row","side","char","dist","gap","detail"}
  python -I tools/menu_screen.py --make-refs
      crops logs/menu_refs/ from the frames named below (gitignored, like logs/stage_refs/)

screen: display, startgame, movie, title, difficulty, mode, fighter, loading, other
row:    mode highlight (story..options) or difficulty highlight (easy..ultrahard)
side:   1p or cpu on the fighter screen
char:   name under the cursor that is choosing (kazuya / xiaoyu / hwoarang / yoshimitsu)
detail: startgame yes|no, display pal60|above|below|hold
A settled menu crop is dist<= the threshold in ACCEPT and gap>=8, same idea as stage_card.py.
"""
import os
import struct
import sys

REF_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "logs", "menu_refs")

# Crops that stay put while a preview animates. Sources are 640x448 guest frames.
FHEAD = (170, 8, 470, 42)          # CHOOSE YOUR FIGHTER
SQUARES = (32, 80, 56, 300)        # mode-list colour squares (not the difficulty list)
DIFFROWS = (180, 150, 460, 220)    # EASY / MEDIUM / HARD
OLIVE = (180, 185, 460, 225)       # Start game? panel
DISPLAY = (160, 200, 480, 290)     # caution text on the 640x512 display menu (above the highlight)
LEFT_NAME = (0, 360, 250, 410)
RIGHT_NAME = (400, 360, 630, 410)

# Highlighted mode-row text, median Y of the orange band (pitch 24). VS is skipped by Down.
MODE_ROWS = [("story", 92), ("arcade", 116), ("vs", 140), ("team", 164), ("survival", 188),
             ("practice", 212), ("training", 236), ("tekken", 260), ("options", 284)]
# Difficulty rows. MEDIUM measured at y 183-190; the others are one row pitch (~28) off that.
DIFF_ROWS = [("easy", 160), ("medium", 186), ("hard", 212), ("veryhard", 238), ("ultrahard", 264)]

ACCEPT = {
    "fighter": 40.0,
    "mode": 20.0,
    "difficulty": 18.0,
    "startgame": 30.0,
    "display": 28.0,
    "title": 22.0,
    "char": 18.0,
}


def read_bmp(path):
    data = open(path, "rb").read()
    off, = struct.unpack_from("<I", data, 10)
    w, h = struct.unpack_from("<ii", data, 18)
    bpp, = struct.unpack_from("<H", data, 28)
    if bpp != 32:
        sys.exit(f"{path}: {bpp} bpp, expected 32")
    return w, abs(h), data[off:], h < 0


def crop_bytes(path, box):
    w, h, px, top = read_bmp(path)
    return crop_px(w, h, px, top, box), (w, h)


def crop_px(w, h, px, top, box):
    x0, y0, x1, y1 = box
    out = bytearray()
    for y in range(y0, y1):
        row = y if top else h - 1 - y
        base = (row * w + x0) * 4
        line = px[base:base + (x1 - x0) * 4]
        out += bytes(b for i, b in enumerate(line) if i % 4 != 3)
    return bytes(out)


def crop_hash(buf):
    h = 2166136261
    for b in buf[::8]:
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return "%08x" % h


def mean_abs(a, b):
    if not a or len(a) != len(b):
        return 999.0
    return sum(abs(x - y) for x, y in zip(a, b)) / len(a)


def luma(px):
    """Mean of R,G,B, one pixel in four. px is BGRA."""
    s = n = 0
    for i in range(0, len(px) - 3, 16):
        s += px[i] + px[i + 1] + px[i + 2]
        n += 1
    return s / (n * 3) if n else 0.0


def load_ref(name):
    path = os.path.join(REF_DIR, name)
    if not os.path.isfile(path):
        return None
    return open(path, "rb").read()


def orange_ys(w, h, px, top, x0, x1, y0, y1):
    ys = []
    for y in range(y0, y1):
        n = 0
        row = y if top else h - 1 - y
        base = row * w * 4
        for x in range(x0, x1):
            i = base + x * 4
            b, g, r = px[i], px[i + 1], px[i + 2]
            if r > 170 and 60 < g < 190 and b < 90 and r > g + 40:
                n += 1
        if n >= 8:
            ys.append(y)
    return ys


def nearest_row(ys, table):
    if len(ys) < 6:
        return "", 99
    # one tight band, not a scattering of orange UI
    if ys[-1] - ys[0] > 22:
        # keep the densest 16-row window
        best = None
        for i, y in enumerate(ys):
            window = [t for t in ys if y <= t <= y + 16]
            if best is None or len(window) > len(best):
                best = window
        ys = best
        if not ys or len(ys) < 6:
            return "", 99
    med = ys[len(ys) // 2]
    name, center = min(table, key=lambda it: abs(it[1] - med))
    return (name, abs(center - med)) if abs(center - med) <= 12 else ("", abs(center - med))


def yellow_box(w, h, px, top, x0, x1, y0, y1):
    xs, ys = [], []
    for y in range(y0, y1):
        row = y if top else h - 1 - y
        base = row * w * 4
        for x in range(x0, x1):
            i = base + x * 4
            b, g, r = px[i], px[i + 1], px[i + 2]
            if r > 190 and g > 160 and b < 80:
                xs.append(x)
                ys.append(y)
    if len(xs) < 8:
        return None
    return (sum(xs) / len(xs), sum(ys) / len(ys), len(xs))


def classify(path):
    w, h, px, top = read_bmp(path)
    if w == 640 and h == 512:
        return classify_tall(w, h, px, top)
    if w != 640 or h != 448:
        return {"screen": "other", "row": "", "side": "", "char": "", "dist": 999, "gap": 0,
                "detail": f"size {w}x{h}"}
    samples = luma(px)
    crops = {
        "fighter": crop_px(w, h, px, top, FHEAD),
        "mode": crop_px(w, h, px, top, SQUARES),
        "difficulty": crop_px(w, h, px, top, DIFFROWS),
        "startgame": crop_px(w, h, px, top, OLIVE),
        "display": crop_px(w, h, px, top, DISPLAY),
    }
    refs = {k: load_ref(k + ".raw") for k in ("fighter", "mode", "difficulty", "startgame")}
    scored = []
    for name, ref in refs.items():
        if ref is None:
            continue
        scored.append((mean_abs(crops[name], ref), name))
    scored.sort()
    screen, dist, gap = "other", 999.0, 0.0
    accepted = [item for item in scored if item[0] <= ACCEPT.get(item[1], 20.0)]
    if accepted:
        dist, screen = accepted[0]
        gap = (scored[1][0] - dist) if len(scored) > 1 else 999.0
    if screen == "other" and samples < 8.0:
        screen = "loading"
    elif screen == "other" and samples > 18.0:
        screen = "movie"
    row, side, char, detail = "", "", "", ""
    if screen == "mode":
        row, _off = nearest_row(orange_ys(w, h, px, top, 48, 220, 70, 320), MODE_ROWS)
    elif screen == "difficulty":
        row, _off = nearest_row(orange_ys(w, h, px, top, 200, 480, 130, 320), DIFF_ROWS)
        if not row:
            # MEDIUM is yellow-orange; the same band detector with a wider gate
            ys = []
            for y in range(140, 300):
                n = 0
                rr = y if top else h - 1 - y
                base = rr * w * 4
                for x in range(200, 420):
                    i = base + x * 4
                    b, g, r = px[i], px[i + 1], px[i + 2]
                    if r > 180 and g > 120 and b < 90 and r > b + 60:
                        n += 1
                if n >= 8:
                    ys.append(y)
            row, _off = nearest_row(ys, DIFF_ROWS)
    elif screen == "startgame":
        yb = yellow_box(w, h, px, top, 200, 480, 190, 240)
        if yb and yb[0] >= 315:
            detail = "no"
        elif yb:
            detail = "yes"
    elif screen == "display":
        yb = yellow_box(w, h, px, top, 160, 500, 140, 340)
        # PAL60 is the middle option. menupick-disp measured the highlighted row; constants below.
        if yb:
            detail = display_detail(yb[1])
        else:
            detail = "hold"
    elif screen == "fighter":
        side, char, detail = fighter_id(w, h, px, top)
    return {"screen": screen, "row": row, "side": side, "char": char,
            "dist": round(dist, 2), "gap": round(gap, 2), "detail": detail}


# Yellow-glyph Y on the 640x512 display menu (logs/grok/menupick-disp frame_9s PAL50 cy 299, frame_12s PAL60 cy 326).
DISPLAY_Y = {"pal60": 326}


def display_detail(y):
    if abs(y - DISPLAY_Y["pal60"]) <= 14:
        return "pal60"
    if y < DISPLAY_Y["pal60"]:
        return "above"
    return "below"


def classify_tall(w, h, px, top):
    """The display-mode menu is presented 640x512. Everything after PAL60 is 640x448."""
    if luma(px) < 8.0:
        return {"screen": "loading", "row": "", "side": "", "char": "", "dist": 0, "gap": 0, "detail": ""}
    ref = load_ref("display.raw")
    probe = crop_px(w, h, px, top, DISPLAY)
    dist = mean_abs(probe, ref) if ref is not None else 999.0
    if dist <= ACCEPT["display"]:
        yb = yellow_box(w, h, px, top, 180, 500, 250, 400)
        detail = display_detail(yb[1]) if yb else "hold"
        return {"screen": "display", "row": "", "side": "", "char": "", "dist": round(dist, 2),
                "gap": 0, "detail": detail}
    return {"screen": "other", "row": "", "side": "", "char": "", "dist": round(dist, 2), "gap": 0, "detail": "tall"}


def fighter_id(w, h, px, top):
    """Right bar decides 1P (empty) vs CPU (a name). Kazuya's 1P plate is the left bar;
    the CPU plate is name_kazuya_r (menupick-1: CPU cursor starts on Kazuya, not Xiaoyu)."""
    left = crop_px(w, h, px, top, LEFT_NAME)
    right = crop_px(w, h, px, top, RIGHT_NAME)
    scores = []
    right_refs = (("xiaoyu", "name_xiaoyu.raw"), ("hwoarang", "name_hwoarang.raw"),
                  ("yoshimitsu", "name_yoshimitsu.raw"), ("kazuya", "name_kazuya_r.raw"),
                  ("empty", "name_empty.raw"))
    for name, fn in right_refs:
        ref = load_ref(fn)
        if ref is not None and len(ref) == len(right):
            scores.append((mean_abs(right, ref), name))
    scores.sort()
    tag = crop_hash(right)
    kref = load_ref("name_kazuya.raw")
    left_kaz = mean_abs(left, kref) if kref is not None else 999.0
    if not scores:
        if left_kaz <= ACCEPT["char"]:
            return "1p", "kazuya", tag
        return "", "", tag
    best, second = scores[0], scores[1] if len(scores) > 1 else (999.0, "")
    gap = second[0] - best[0]
    if best[1] != "empty" and best[0] <= ACCEPT["char"] and gap >= 8.0:
        return "cpu", best[1], tag
    if best[1] == "empty" and best[0] <= ACCEPT["char"]:
        if left_kaz <= ACCEPT["char"]:
            return "1p", "kazuya", tag
        return "1p", "", tag
    return "", "", tag


def emit(info):
    print('{"screen":"%s","row":"%s","side":"%s","char":"%s","dist":%.2f,"gap":%.2f,"detail":"%s"}'
          % (info["screen"], info["row"], info["side"], info["char"], info["dist"], info["gap"], info["detail"]))


def make_refs():
    os.makedirs(REF_DIR, exist_ok=True)
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    sources = {
        "fighter.raw": ("logs/fixed_probe1/frame_46s.bmp", FHEAD),
        "mode.raw": ("logs/gl_screens1/frame_38s.bmp", SQUARES),
        "difficulty.raw": ("logs/gl_screens1/frame_34s.bmp", DIFFROWS),
        "startgame.raw": ("logs/gl_screens1/frame_14s.bmp", OLIVE),
        "name_kazuya.raw": ("logs/fixed_probe1/frame_46s.bmp", LEFT_NAME),
        "name_empty.raw": ("logs/fixed_probe1/frame_46s.bmp", RIGHT_NAME),
        "name_xiaoyu.raw": ("logs/fixed_probe1/frame_49s.bmp", RIGHT_NAME),
        "name_hwoarang.raw": ("logs/fixed_probe1/frame_50s.bmp", RIGHT_NAME),
    }
    disp = os.path.join(root, "logs", "grok", "menupick-disp", "frame_12s.bmp")
    if os.path.isfile(disp):
        sources["display.raw"] = ("logs/grok/menupick-disp/frame_12s.bmp", DISPLAY)
    yoshi = os.path.join(root, "logs", "grok", "menupick-yoshi.bmp")
    if os.path.isfile(yoshi):
        sources["name_yoshimitsu.raw"] = ("logs/grok/menupick-yoshi.bmp", RIGHT_NAME)
    kcpu = os.path.join(root, "logs", "grok", "menupick-1", "frame_req_00000091.bmp")
    if os.path.isfile(kcpu):
        sources["name_kazuya_r.raw"] = ("logs/grok/menupick-1/frame_req_00000091.bmp", RIGHT_NAME)
    for name, (rel, box) in sources.items():
        data, _ = crop_bytes(os.path.join(root, rel.replace("/", os.sep)), box)
        with open(os.path.join(REF_DIR, name), "wb") as f:
            f.write(data)
        print(f"{name} {len(data)} from {rel}")


CHECK = [
    ("logs/grok/menupick-disp/frame_9s.bmp", "display", "", "", "above"),
    ("logs/grok/menupick-disp/frame_12s.bmp", "display", "", "", "pal60"),
    ("logs/grok/menupick-disp/frame_15s.bmp", "startgame", "", "", "no"),
    ("logs/gl_screens1/frame_14s.bmp", "startgame", "", "", "no"),
    ("logs/gl_screens1/frame_18s.bmp", "loading", "", "", ""),
    ("logs/gl_screens1/frame_34s.bmp", "difficulty", "medium", "", ""),
    ("logs/hud_claude3/frame_85s.bmp", "difficulty", "medium", "", ""),
    ("logs/gl_screens1/frame_38s.bmp", "mode", "story", "", ""),
    ("logs/grok/test-mode-1/frame_38s.bmp", "mode", "arcade", "", ""),
    ("logs/grok/test-mode-3/frame_43s.bmp", "mode", "team", "", ""),
    ("logs/grok/test-mode-1/frame_41s.bmp", "mode", "survival", "", ""),
    ("logs/grok/test-mode-1/frame_43s.bmp", "mode", "practice", "", ""),
    ("logs/fixed_probe1/frame_43s.bmp", "mode", "practice", "", ""),
    ("logs/grok/test-mode-1/frame_45s.bmp", "mode", "training", "", ""),
    ("logs/grok/test-mode-1/frame_47s.bmp", "mode", "tekken", "", ""),
    ("logs/fixed_probe1/frame_46s.bmp", "fighter", "", "kazuya", "1p"),
    ("logs/iopdump1/frame_46s.bmp", "fighter", "", "kazuya", "1p"),
    ("logs/grok/menupick-1/frame_req_00000061.bmp", "fighter", "", "kazuya", "1p"),
    ("logs/grok/menupick-1/frame_req_00000091.bmp", "fighter", "", "kazuya", "cpu"),
    ("logs/grok/menupick-1/frame_req_00000085.bmp", "fighter", "", "kazuya", "cpu"),
    ("logs/grok/menupick-2/frame_req_00000081.bmp", "fighter", "", "yoshimitsu", "cpu"),
    ("logs/grok/menupick-2/frame_req_00000086.bmp", "fighter", "", "yoshimitsu", "cpu"),
    ("logs/fixed_probe1/frame_49s.bmp", "fighter", "", "xiaoyu", "cpu"),
    ("logs/fixed_probe1/frame_50s.bmp", "fighter", "", "hwoarang", "cpu"),
    ("logs/fixed_probe1/frame_52s.bmp", "fighter", "", "hwoarang", "cpu"),
    ("logs/iopdump1/frame_51s.bmp", "fighter", "", "hwoarang", "cpu"),
    ("logs/grok/music-1/frame_25s.bmp", "movie", "", "", ""),
    ("logs/hud_claude3/frame_59s.bmp", "movie", "", "", ""),
]


def check():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    bad = 0
    for rel, screen, row, char, extra in CHECK:
        path = os.path.join(root, rel.replace("/", os.sep))
        info = classify(path)
        got_extra = info["detail"] if screen in ("display", "startgame") else info["side"]
        ok = info["screen"] == screen and (not row or info["row"] == row) and (not char or info["char"] == char)
        if extra and screen in ("display", "startgame"):
            ok = ok and info["detail"] == extra
        if extra in ("1p", "cpu"):
            ok = ok and info["side"] == extra
        flag = "ok" if ok else "FAIL"
        if not ok:
            bad += 1
        print(f"{flag} {rel} -> {info['screen']} row={info['row']} side={info['side']} char={info['char']} "
              f"detail={info['detail']} dist={info['dist']} gap={info['gap']}")
    print(f"{len(CHECK) - bad}/{len(CHECK)}")
    if bad:
        sys.exit(1)


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--make-refs":
        make_refs()
        return
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        check()
        return
    if len(sys.argv) == 3 and sys.argv[1] == "--json":
        emit(classify(sys.argv[2]))
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
