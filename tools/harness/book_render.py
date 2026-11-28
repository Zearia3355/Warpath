#!/usr/bin/env python3
"""Render the chronicle (the book window) from the real addon code.

    python tools/harness/render.py --book campaigns --char Lethality-Starunner
    python tools/harness/render.py --book warpath --page 2 --char ...
    python tools/harness/render.py --book settings --section map --char ...
    python tools/harness/render.py --book grudges --beside <design.png> --char ...
    python tools/harness/render.py --book campaigns --onion tools/out/design/book/ref_R1_raw.png --char ...

What this draws is the frame tree Chronicle.lua and Options.lua build under
the stub (wow_stub.lua), laid out the way the client does it: anchors
(SetPoint, SetAllPoints), sizes, scale, frame strata and levels, draw layers
and sublevels, alpha, shown/hidden. Textures: solid colours, the addon's own
files (loaded from this repo), texcoords, vertex colours, SetGradient, masks,
rotation, BLEND/ADD/MOD. Text: the font (path and size), colour, shadow,
justification, wrapping at the string's width, SetSpacing, colour codes.

What it can't draw, and how it says so:
  * Game textures exist only inside the client. They're drawn as stand-ins:
    a tinted box with the texture's short name. The few the book always
    shows (title plate, close button, page arrows, dialog border, buttons,
    check boxes) are shaped after Joe's in-game screenshot so the frame reads.
  * Game fonts can't be rendered outside the client (they ship as .slug).
    The stand-ins are the ones the design renders used, so text widths are
    comparable with them: Candara for Friz, Palatino Linotype Bold small caps
    for Morpheus, Arial Narrow for itself. EB Garamond is the real file.
    Text the code measures (GetStringWidth, wrapping) is measured in the
    stand-in face, so layouts that depend on width follow the stand-in.

Geometry. The canvas is the design renders' 1092x748, at 1.2 render px per
UI unit (Joe's screen: 1 unit = 1.2 px at 2560 wide). Where the book frame's
top-left lands on it is --origin: "shot" (default) is where it is in Joe's
in-game screenshot that the design renders were built over (measured from
the tabs, the cover's symmetric edge lines and the title plate: 20.5, 40.4);
"canon" is what chronicle.md's conversion implies (22.4, 44.4), which puts
the tabs, plate, close and Share 2 px right and 4 px low of the screenshot.

Text placement was fitted to the same screenshot: the baseline sits 0.875
(Friz) / 0.88 (Morpheus) of the font's height below a line's top, and line
height and SetSpacing each round up to whole screen pixels (QuestFont 13 with
spacing 2 steps 19 px, not 18). With these, single-line strings land within
1 px of the screenshot's baselines.
"""

import math
import os
import re
from pathlib import Path

from lupa.lua51 import lua_type
from PIL import Image, ImageChops, ImageDraw, ImageFont

from harness import REPO, Wow

SCALE = 1.2                      # render px per UI unit
CANVAS = (1092, 748)             # the design renders' canvas
ORIGINS = {"shot": (20.5, 40.4), "canon": (22.4, 44.4)}
BACKGROUND = (34, 28, 24)        # behind the book (the game world in Joe's shot)
STRATA = ["WORLD", "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP"]
LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 4}
REGIONS = {"Texture", "FontString", "Line", "MaskTexture"}
NOT_DRAWN = {"Font", "AnimationGroup", "Animation", "Alpha", "Scale", "Translation", "Rotation", "Path"}

WINF = Path(os.environ.get("WINDIR", r"C:\Windows")) / "Fonts"
OFFICE = Path(r"C:\Program Files\Microsoft Office\root\vfs\Fonts\private")
# The design renders' stand-ins (tools/out/design/type/type.py, FONTS), and
# how much wider the game draws the real face than the stand-in at the same
# size: the 3.8.4 probe's GetStringWidth of one sample string in each face,
# over the stand-in's width of it (see GAME_WIDTH below). --fonts game sizes
# each stand-in up by it, so widths and wrapping are the game's.
STANDIN_FACES = {
    "frizqt__.ttf": ([WINF / "Candara.ttf"], False, "Candara for Friz"),
    "morpheus.ttf": ([WINF / "palab.ttf"], True, "Palatino Bold small caps for Morpheus"),
    "arialn.ttf": ([OFFICE / "ARIALN.TTF", WINF / "ARIALN.TTF", WINF / "arialn.ttf"], False, "Arial Narrow"),
    "skurri.ttf": ([WINF / "Candarab.ttf"], False, "Candara Bold for Skurri"),
}
# Probe (2026-11-27): "<label>: Welcome Back — 3.8.4 · “Grudges” …" measured
# 385 in Friz 16, 359 in Arial Narrow 15, 499 in Morpheus 20. The stand-ins
# measure 342, 325 and 548 (small caps). The EB Garamond rows (380, 378) were
# measured before the client had applied the font (SetFont returned false):
# they are Friz 12's width, so they say nothing about EB Garamond.
GAME_WIDTH = {"frizqt__.ttf": 385 / 342.0, "arialn.ttf": 359 / 325.0, "morpheus.ttf": 499 / 548.0}
# Where the client puts the baseline in a line, as a share of the font's
# height down from the line's top. Friz and Morpheus: measured on Joe's
# screenshot (shot.webp), ten single-line strings, +-0.5 px. Arial Narrow:
# its own ascender (0.905 em), not checked in game. Any other face (the
# addon's EB Garamond): its own ascent, unchecked until a screenshot shows it.
GAME_ASCENT = {"frizqt__.ttf": 0.875, "morpheus.ttf": 0.88, "arialn.ttf": 0.905}
# Always present (it ships in the repo): the fallback where a stand-in face
# isn't installed (CI), and every face in --fonts repo, so tests don't
# depend on what fonts the machine has.
REPO_FACE = REPO / "Fonts" / "EBGaramond-Bold.ttf"
SMALLCAPS_RATIO, SMALLCAPS_TRACK = 0.78, 0.028   # type.py's small caps: lower case at 0.78, 0.6 px apart at ~21 px

CODE = re.compile(r"\|c([0-9a-fA-F]{8})|\|r|\|n|\|\||\|T[^|]*\|t|\|H[^|]*\|h|\|h")


# ---------------------------------------------------------------------------- type
class Type:
    """Font faces, measuring and line breaking, in UI units."""

    def __init__(self, fonts="standin"):
        self.mode = fonts
        self._fonts, self._widths, self.used = {}, {}, {}

    def face(self, path):
        """(file, small caps?, label) for a font path as the addon gives it."""
        p = str(path or "").replace("/", "\\")
        low = p.lower()
        if low.startswith("interface\\addons\\warpath\\"):
            f = REPO.joinpath(*p.split("\\")[3:])
            if f.exists():
                return f, False, f.name
        base = low.rsplit("\\", 1)[-1]
        if self.mode == "repo":
            return REPO_FACE, base == "morpheus.ttf", "EB Garamond Bold (tests)"
        cands, caps, label = STANDIN_FACES.get(base, ([WINF / "Candara.ttf"], False, "Candara for " + base))
        for c in cands:
            if c.exists():
                return c, caps, label
        return REPO_FACE, caps, "EB Garamond Bold (no stand-in installed for " + base + ")"

    def em(self, path):
        """Glyph size over the font's height: 1, or with --fonts game the
        game's width over the stand-in's (GAME_WIDTH). Line pitch stays the
        font's height either way, as in the client."""
        if self.mode != "game":
            return 1.0
        base = str(path or "").replace("/", "\\").lower().rsplit("\\", 1)[-1]
        return GAME_WIDTH.get(base, 1.0)

    def font(self, file, px):
        key = (str(file), round(px * 20) / 20)
        if key not in self._fonts:
            self._fonts[key] = ImageFont.truetype(str(file), max(1.0, key[1]))
        return self._fonts[key]

    def text_px(self, file, caps, px, s):
        """Width in px of plain text in a face at px size."""
        key = (str(file), caps, round(px * 20) / 20, s)
        w = self._widths.get(key)
        if w is None:
            if caps:
                w = 0.0
                for i, (ch, sub) in enumerate(self.caps_parts(s)):
                    w += self.font(file, px * (SMALLCAPS_RATIO if sub else 1)).getlength(ch) + (SMALLCAPS_TRACK * px if i else 0)
            else:
                w = self.font(file, px).getlength(s)
            self._widths[key] = w
        return w

    @staticmethod
    def caps_parts(s):
        return [(c.upper(), c.islower()) for c in s]

    def width(self, path, size, s):
        """GetStringWidth: UI units, widest line, colour codes ignored."""
        file, caps, label = self.face(path)
        self.used[label] = True
        px = size * SCALE * self.em(path)
        return max(self.text_px(file, caps, px, plain(line)) for line in plain(s).split("\n")) / SCALE

    def ascent(self, path, line_px):
        """Baseline below a line's top, in px (GAME_ASCENT)."""
        base = str(path or "").replace("/", "\\").lower().rsplit("\\", 1)[-1]
        if base in GAME_ASCENT:
            return line_px * GAME_ASCENT[base]
        file, _, _ = self.face(path)
        return self.font(file, 100).getmetrics()[0] / 100 * line_px

    @staticmethod
    def pitch(size, spacing):
        """A line's height and the gap after it, in units. The client rounds
        each up to whole screen pixels: Joe's screenshot shows QuestFont 13
        with SetSpacing(2) at 19 px a line, not 18 (15.6 -> 16, 2.4 -> 3)."""
        snap = lambda u: math.ceil(u * SCALE - 1e-6) / SCALE
        return snap(size), snap(spacing or 0)

    def height(self, n, size, spacing):
        """GetStringHeight of n lines."""
        lh, sp = self.pitch(size, spacing)
        return n * lh + (n - 1) * sp

    def lines(self, path, size, text, width, wrap, max_lines=None):
        """Break text as the client does: at spaces, to `width` units (0: no
        limit); without word wrap a long line is cut with '...'. Returns lines
        of runs [(text, colour or None)]."""
        file, caps, _ = self.face(path)
        px = size * SCALE * self.em(path)

        def w_of(runs_):
            return self.text_px(file, caps, px, "".join(t for t, _ in runs_)) / SCALE

        out = []
        for para in split_runs(runs(text)):
            if not width or width <= 0:
                out.append(para)
                continue
            if not wrap:
                if w_of(para) > width + 0.01:
                    para = cut(para, width - self.text_px(file, caps, px, "...") / SCALE, w_of) + [("...", None)]
                out.append(para)
                continue
            line = []
            for word in words(para):
                cand = line + ([(" ", None)] if line else []) + word
                if not line or w_of(cand) <= width + 0.01:
                    line = cand
                else:
                    out.append(line)
                    line = word
            out.append(line)
        if max_lines and len(out) > max_lines:
            out = out[:max_lines]
            last = out[-1] + [("...", None)]
            if w_of(last) > width + 0.01:
                last = cut(out[-1], width - self.text_px(file, caps, px, "...") / SCALE, w_of) + [("...", None)]
            out[-1] = last
        return out


def plain(s):
    return CODE.sub(lambda m: "|" if m.group(0) == "||" else ("\n" if m.group(0) == "|n" else ""), str(s))


def runs(s):
    """Text with |cAARRGGBB ... |r codes -> [(text, (r,g,b) or None)]."""
    out, col, pos = [], None, 0
    s = str(s)
    for m in CODE.finditer(s):
        if m.start() > pos:
            out.append((s[pos:m.start()], col))
        tok = m.group(0)
        if m.group(1):
            h = m.group(1)
            col = (int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, int(h[6:8], 16) / 255)
        elif tok == "|r":
            col = None
        elif tok == "|n":
            out.append(("\n", col))
        elif tok == "||":
            out.append(("|", col))
        pos = m.end()
    if pos < len(s):
        out.append((s[pos:], col))
    return out


def split_runs(rs):
    """Split runs at explicit newlines into paragraphs."""
    paras, cur = [], []
    for t, c in rs:
        parts = t.split("\n")
        for i, part in enumerate(parts):
            if i:
                paras.append(cur)
                cur = []
            if part:
                cur.append((part, c))
    paras.append(cur)
    return paras


def words(para):
    """Runs -> words (each a list of runs), split at spaces."""
    out, cur = [], []
    for t, c in para:
        pieces = t.split(" ")
        for i, piece in enumerate(pieces):
            if i:
                if cur:
                    out.append(cur)
                cur = []
            if piece:
                cur.append((piece, c))
    if cur:
        out.append(cur)
    return out


def cut(para, width, w_of):
    """The longest start of a line that fits `width`."""
    flat = [(ch, c) for t, c in para for ch in t]
    lo, hi = 0, len(flat)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if w_of([(ch, c) for ch, c in flat[:mid]]) <= width:
            lo = mid
        else:
            hi = mid - 1
    merged = []
    for ch, c in flat[:lo]:
        if merged and merged[-1][1] == c:
            merged[-1] = (merged[-1][0] + ch, c)
        else:
            merged.append((ch, c))
    return merged


# ---------------------------------------------------------------------------- the frame tree
def is_table(v):
    return lua_type(v) == "table"


def lua_list(t):
    if t is None:
        return []
    return [t[i] for i in range(1, len(t) + 1)]


class Tree:
    """The book's widgets, laid out in UI units (y down) from the book's top-left."""

    def __init__(self, wow, root, typ):
        self.wow, self.root, self.type = wow, root, typ
        self.G = wow.lua.globals()
        self._rect, self._scale, self._level = {}, {}, {}
        self.parent_of = {}
        self.font_of = wow.H["fontOf"]

    # -- properties walked up the parent chain
    @staticmethod
    def key(o):
        return o["__seq"]

    def visible(self, o):
        w = o
        while w is not None:
            if w["__shown"] is False:
                return False
            if self.key(w) == self.key(self.root):
                return True
            w = w["__parent"]
        return True

    def alpha(self, o):
        a, w = 1.0, o
        while w is not None:
            a *= w["__alpha"] if w["__alpha"] is not None else 1
            w = w["__parent"]
        return a

    def scale(self, o):
        k = self.key(o)
        if k not in self._scale:
            s, w = 1.0, o
            while w is not None and self.key(w) != self.key(self.root):
                s *= w["__uiscale"] or 1
                w = w["__parent"]
            self._scale[k] = s
        return self._scale[k]

    def level(self, f):
        k = self.key(f)
        if k not in self._level:
            if f["__level"] is not None:
                self._level[k] = f["__level"]
            else:
                p = f["__parent"]
                self._level[k] = self.level(p) + 1 if p is not None else 0
        return self._level[k]

    def strata(self, f):
        w = f
        while w is not None:
            if w["__strata"]:
                return w["__strata"]
            w = w["__parent"]
        return "MEDIUM"

    def font(self, o):
        path, size, flags = self.font_of(o)
        return path, float(size or 12), flags or ""

    def text_color(self, o):
        w = o
        for _ in range(8):
            if w is None:
                break
            if w["__textColor"] is not None:
                c = w["__textColor"]
                return (c[1], c[2], c[3], c[4] if c[4] is not None else 1)
            w = w["__fontObj"]
        return (1, 1, 1, 1)

    def shadow(self, o):
        off, col, w = None, None, o
        for _ in range(8):
            if w is None:
                break
            if off is None and w["__shadowOffset"] is not None:
                off = (w["__shadowOffset"][1], w["__shadowOffset"][2])
            if col is None and w["__shadowColor"] is not None:
                c = w["__shadowColor"]
                col = (c[1], c[2], c[3], c[4] if c[4] is not None else 1)
            w = w["__fontObj"]
        return off or (0, 0), col or (0, 0, 0, 1)

    # -- anchors
    def anchors(self, o):
        """The region's points as (point, relativeTo, relativePoint, x, y), a
        later point of the same name replacing an earlier one, as in the client."""
        out = {}
        parent = o["__parent"]
        for p in lua_list(o["__points"]):
            vals = [p[i] for i in range(1, 7)]
            point = vals[0]
            if point == "ALL":
                rel = vals[1] if is_table(vals[1]) else parent
                out["TOPLEFT"] = ("TOPLEFT", rel, "TOPLEFT", 0, 0)
                out["BOTTOMRIGHT"] = ("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
                continue
            rest, rel, relp = vals[1:], parent, point
            i = 0
            if is_table(rest[0]) or isinstance(rest[0], str):
                rel = rest[0] if is_table(rest[0]) else self.G[rest[0]]
                i = 1
                if isinstance(rest[1], str):
                    relp = rest[1]
                    i = 2
            x = rest[i] if isinstance(rest[i], (int, float)) else 0
            y = rest[i + 1] if i + 1 < len(rest) and isinstance(rest[i + 1], (int, float)) else 0
            out[point.upper()] = (point.upper(), rel, (relp or point).upper(), x, y)
        return list(out.values())

    def rect(self, o):
        """(left, top, right, bottom) in book units, y down; None if unplaced."""
        k = self.key(o)
        if k in self._rect:
            return self._rect[k]
        self._rect[k] = None             # guards against anchor loops
        if k == self.key(self.root):
            r = (0.0, 0.0, float(self.root["__w"]), float(self.root["__h"]))
            self._rect[k] = r
            return r
        s = self.scale(o)
        sp = o["__scrollParent"]
        if sp is not None:               # a scroll child: at its frame's top-left, moved up by the scroll
            pr = self.rect(sp)
            if pr is None:
                return None
            v = (sp["__vscroll"] or 0) * s
            self._rect[k] = (pr[0], pr[1] - v, pr[0] + (o["__w"] or 0) * s, pr[1] - v + (o["__h"] or 0) * s)
            return self._rect[k]
        L = R = CX = T = B = CY = None
        for point, rel, relp, x, y in self.anchors(o):
            if rel is None:
                continue
            tr = self.rect(rel)
            if tr is None:
                continue
            px = tr[0] if "LEFT" in relp else tr[2] if "RIGHT" in relp else (tr[0] + tr[2]) / 2
            py = tr[1] if "TOP" in relp else tr[3] if "BOTTOM" in relp else (tr[1] + tr[3]) / 2
            ax, ay = px + x * s, py - y * s
            if "LEFT" in point:
                L = ax
            elif "RIGHT" in point:
                R = ax
            else:
                CX = ax
            if "TOP" in point:
                T = ay
            elif "BOTTOM" in point:
                B = ay
            else:
                CY = ay
        text = o["__kind"] == "FontString"
        w = (o["__w"] or 0) * s
        if text and w <= 0 and not (L is not None and R is not None):
            w = self.type.width(self.font(o)[0], self.font(o)[1], o["__text"] or "") * s if o["__text"] else 0
        if L is not None and R is not None:
            l, r = L, R
        elif L is not None:
            l, r = L, L + w
        elif R is not None:
            l, r = R - w, R
        elif CX is not None:
            l, r = CX - w / 2, CX + w / 2
        else:
            return None
        h = (o["__h"] or 0) * s
        if text and h <= 0 and not (T is not None and B is not None):
            h = self.text_block(o, (r - l) / s)[1] * s
        if T is not None and B is not None:
            t, b = T, B
        elif T is not None:
            t, b = T, T + h
        elif B is not None:
            t, b = B - h, B
        elif CY is not None:
            t, b = CY - h / 2, CY + h / 2
        else:
            return None
        self._rect[k] = (l, t, r, b)
        return self._rect[k]

    def text_block(self, o, width):
        """A font string's lines at `width` units, and their height in units."""
        path, size, _ = self.font(o)
        sp = o["__spacing"] or 0
        hset = o["__h"] or 0
        lh, gap = self.type.pitch(size, sp)
        max_lines = int((hset + gap) // (lh + gap) + 1e-6) if hset > 0 else None
        lines = self.type.lines(path, size, o["__text"] or "", width if (o["__w"] or 0) > 0 or width else 0,
                                o["__wrap"] is not False, max(1, max_lines) if max_lines is not None else None)
        n = max(1, len(lines))
        return lines, self.type.height(n, size, sp)

    # -- the tree in draw order
    def walk(self):
        """Every visible frame under the book with its regions, in draw order."""
        frames = []

        def visit(f):
            frames.append(f)
            for c in lua_list(f["__children"]):
                kind = c["__kind"]
                if kind in REGIONS or kind in NOT_DRAWN or c["__layer"]:
                    continue
                if c["__shown"] is not False:
                    visit(c)

        visit(self.root)
        frames = [f for f in frames if self.visible(f)]
        frames.sort(key=lambda f: (STRATA.index(self.strata(f)) if self.strata(f) in STRATA else 3,
                                   self.level(f), self.key(f)))
        out = []
        for f in frames:
            regs = [c for c in lua_list(f["__children"])
                    if c["__kind"] in REGIONS and c["__shown"] is not False]
            regs.sort(key=lambda r: (LAYERS.get(r["__drawLayer"] or "ARTWORK", 2), r["__sub"] or 0, self.key(r)))
            out.append((f, regs))
        return out


# ---------------------------------------------------------------------------- stand-ins for game art
def _short(path):
    p = str(path).replace("/", "\\")
    return p.rsplit("\\", 1)[-1]


def _label_font(px):
    for f in ("arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(f, px)
        except OSError:
            continue
    return ImageFont.load_default()


# The visible part of a few textures inside their region, as fractions,
# measured on Joe's screenshot (campaign-voice/shot.webp).
VISIBLE = {
    "ui-dialogbox-header": (0.24, 0.05, 0.76, 0.54),
    "ui-panel-minimizebutton-up": (0.33, 0.04, 0.99, 0.52),
    "ui-spellbookicon-prevpage-up": (0.09, 0.13, 0.87, 0.87),
    "ui-spellbookicon-nextpage-up": (0.13, 0.13, 0.91, 0.87),
}


def standin(path, w, h, ss):
    """An RGBA picture standing in for a game texture, and its short name."""
    name = _short(path)
    low = name.lower()
    im = Image.new("RGBA", (max(w, 1), max(h, 1)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    vis = VISIBLE.get(low)
    if vis:
        box = [vis[0] * w, vis[1] * h, vis[2] * w, vis[3] * h]
    else:
        box = [0, 0, w - 1, h - 1]
    lab = True
    if low == "questbg":
        d.rectangle([0, 0, w, h], fill=(214, 182, 128, 255))
    elif low == "ui-dialogbox-header":
        d.rectangle(box, fill=(26, 26, 28, 255), outline=(120, 120, 126, 255), width=max(1, 2 * ss))
    elif low.startswith("ui-spellbookicon-"):
        d.rectangle(box, fill=(52, 44, 30, 255), outline=(150, 130, 40, 255), width=max(1, ss))
        cx, cy, r = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2, (box[2] - box[0]) * 0.22
        sgn = -1 if "prev" in low else 1
        d.polygon([(cx + sgn * r, cy), (cx - sgn * r * 0.6, cy - r), (cx - sgn * r * 0.6, cy + r)], fill=(240, 210, 30, 255))
        lab = False
    elif low.startswith("inv_") or low.startswith("classicon") or "icons" in str(path).lower():
        d.rectangle(box, fill=(70, 76, 88, 255), outline=(10, 10, 10, 255), width=max(1, ss))
        d.line([box[0] + w * 0.25, box[3] - h * 0.25, box[2] - w * 0.22, box[1] + h * 0.22], fill=(225, 225, 235, 255),
               width=max(1, int(w / 7)))
        lab = False
    elif "skull" in low:
        s = min(w, h)
        d.ellipse([w / 2 - s * .35, h / 2 - s * .45, w / 2 + s * .35, h / 2 + s * .2], fill=(255, 255, 255, 255))
        d.rectangle([w / 2 - s * .2, h / 2, w / 2 + s * .2, h / 2 + s * .4], fill=(255, 255, 255, 255))
        d.ellipse([w / 2 - s * .22, h / 2 - s * .22, w / 2 - s * .05, h / 2 - s * .05], fill=(0, 0, 0, 0))
        d.ellipse([w / 2 + s * .05, h / 2 - s * .22, w / 2 + s * .22, h / 2 - s * .05], fill=(0, 0, 0, 0))
        lab = False
    else:
        d.rectangle(box, fill=(96, 112, 140, 150), outline=(190, 200, 225, 220), width=max(1, ss))
    if lab and (box[2] - box[0]) > 40 * ss and (box[3] - box[1]) > 11 * ss:
        f = _label_font(8 * ss)
        d.text((box[0] + 3 * ss, box[1] + 2 * ss), "game: " + name, font=f, fill=(110, 110, 140, 200))
    return im, name


def load_addon_texture(path):
    """An addon texture from this repo, or None."""
    p = str(path).replace("/", "\\")
    if not p.lower().startswith("interface\\addons\\warpath\\"):
        return None
    rel = REPO.joinpath(*p.split("\\")[3:])
    for cand in (rel, rel.with_name(rel.name + ".tga"), rel.with_name(rel.name + ".png"), rel.with_name(rel.name + ".blp")):
        if cand.exists() and cand.is_file():
            try:
                return Image.open(cand).convert("RGBA")
            except OSError:
                return None
    return None


# The world map's art stands in from Joe's screenshot of it (the design
# renders' source, in the main checkout's ignored design folder): its map
# canvas is 208-1792 x 61-1117 of world.png, the client's layer 1002 x 668.
WORLD_PNG = Path(os.environ.get("WARPATH_DESIGN", "C:/Users/Joe/Documents/Warpath/tools/out/design")) / "book" / "world.png"
WORLD_CANVAS = (208, 61, 1792, 1117)
_world = {}


def world_tile(tex):
    """Tile i (1-12, 4 a row, 256 layer px) of the world map, or None."""
    if "im" not in _world:
        _world["im"] = Image.open(WORLD_PNG).convert("RGBA") if WORLD_PNG.exists() else None
    im = _world["im"]
    if im is None:
        return None
    _, mid, i = str(tex).split(":")
    i = int(i) - 1
    c, r = i % 4, i // 4
    W, H = WORLD_CANVAS[2] - WORLD_CANVAS[0], WORLD_CANVAS[3] - WORLD_CANVAS[1]
    # a continent's own map (the Ledger's My Lands): its layer is cut from
    # the world map through the continent's fitted rect on it (wow_stub's
    # H.worldRects), so it's the world map's art, not the continent map's
    l, rr, t, b = CONTINENT_ON_WORLD.get(int(mid), (0, 1, 0, 1))
    fx = lambda x: WORLD_CANVAS[0] + (l + (rr - l) * x / 1002) * W
    fy = lambda y: WORLD_CANVAS[1] + (t + (b - t) * y / 668) * H
    box = (fx(c * 256), fy(r * 256), fx((c + 1) * 256), fy((r + 1) * 256))
    return im.crop(tuple(int(round(v)) for v in box)).resize((256, 256), Image.LANCZOS)


# Kalimdor and the Eastern Kingdoms on the world map: the stub's fitted rects
# (wow_stub.lua H.worldRects), left, right, top, bottom.
CONTINENT_ON_WORLD = {1414: (-0.182, 0.644, 0.071, 0.897), 1415: (0.338, 1.164, 0.027, 0.854)}


# ---------------------------------------------------------------------------- painting
class Painter:
    def __init__(self, tree, origin, ss=2):
        self.tree, self.ox, self.oy, self.ss = tree, origin[0], origin[1], ss
        self.im = Image.new("RGBA", (CANVAS[0] * ss, CANVAS[1] * ss), BACKGROUND + (255,))
        self.records = []
        self.clip = None
        self.standins = {}
        self._files = {}

    def X(self, u):
        return (self.ox + u * SCALE) * self.ss

    def Y(self, u):
        return (self.oy + u * SCALE) * self.ss

    def px_box(self, r):
        return self.X(r[0]), self.Y(r[1]), self.X(r[2]), self.Y(r[3])

    def record(self, kind, o, box, **kw):
        s = self.ss
        rec = {"kind": kind, "box": tuple(v / s for v in box), "obj": o}
        rec.update(kw)
        self.records.append(rec)

    # -- compositing
    def composite(self, tile, x, y, blend="BLEND"):
        W, H = self.im.size
        x, y = int(round(x)), int(round(y))
        l, t = max(0, x), max(0, y)
        r, b = min(W, x + tile.width), min(H, y + tile.height)
        if r <= l or b <= t:
            return
        if self.clip:                    # inside a scroll frame: only what its window shows
            cl, ct, cr, cb = (int(round(v)) for v in self.clip)
            l, t, r, b = max(l, cl), max(t, ct), min(r, cr), min(b, cb)
            if r <= l or b <= t:
                return
        tile = tile.crop((l - x, t - y, r - x, b - y))
        if blend == "ADD":
            base = self.im.crop((l, t, r, b))
            a = tile.getchannel("A")
            rgb = ImageChops.multiply(tile.convert("RGB"), Image.merge("RGB", (a, a, a)))
            out = ImageChops.add(base.convert("RGB"), rgb).convert("RGBA")
            self.im.paste(out, (l, t))
        elif blend == "MOD":
            base = self.im.crop((l, t, r, b)).convert("RGB")
            white = Image.new("RGB", tile.size, (255, 255, 255))
            src = Image.composite(tile.convert("RGB"), white, tile.getchannel("A"))
            self.im.paste(ImageChops.multiply(base, src).convert("RGBA"), (l, t))
        else:
            self.im.alpha_composite(tile, (l, t))

    # -- regions
    def texture(self, o):
        tex = o["__texture"]
        if tex is None or tex == "":
            return
        r = self.tree.rect(o)
        if r is None:
            return
        x0, y0, x1, y1 = self.px_box(r)
        w, h = int(round(x1) - round(x0)), int(round(y1) - round(y0))
        if w <= 0 or h <= 0:
            return
        tile = self.texture_tile(o, tex, w, h)
        if tile is None:
            return
        tile = self.shade(o, tile)
        rot = o["__rotation"] or 0
        x, y = round(x0), round(y0)
        if rot:
            big = tile.rotate(math.degrees(rot), resample=Image.BICUBIC, expand=True)
            x += (tile.width - big.width) / 2
            y += (tile.height - big.height) / 2
            tile = big
        self.composite(tile, x, y, o["__blend"] or "BLEND")
        self.record("texture", o, (x0, y0, x1, y1), path=str(tex))

    def texture_tile(self, o, tex, w, h):
        if tex == "color":
            c = o["__color"]
            return Image.new("RGBA", (w, h), tuple(int(round(255 * max(0, min(1, v if v is not None else 1)))) for v in
                                                   (c[1], c[2], c[3], c[4])))
        if isinstance(tex, str) and tex.startswith("atlas:"):
            im, name = standin(tex[6:], w, h, self.ss)
            self.standins[name] = True
            return im
        src = None
        if isinstance(tex, str) and tex.startswith("worldmap:"):
            if tex not in self._files:
                self._files[tex] = world_tile(tex)
            self.standins["world map art: " + ("cut from Joe's world map screenshot" if self._files[tex] is not None
                                               else "missing (no world.png)")] = True
        if isinstance(tex, str):
            if tex not in self._files:
                self._files[tex] = load_addon_texture(tex)
            src = self._files[tex]
        if src is None:
            im, name = standin(tex, w, h, self.ss)   # not mirrored: its label must read
            self.standins[name] = True
            return im
        return self.crop_coords(o, src).resize((w, h), Image.LANCZOS)

    @staticmethod
    def coords(o):
        tc = o["__texcoord"]
        if tc is None:
            return 0, 1, 0, 1
        v = [tc[i] for i in range(1, 9) if tc[i] is not None]
        if len(v) == 8:          # ULx, ULy, LLx, LLy, URx, URy, LRx, LRy
            return v[0], v[6], v[1], v[7]
        return v[0], v[1], v[2], v[3]

    def crop_coords(self, o, src):
        l, r, t, b = self.coords(o)
        W, H = src.size
        img = src.crop((int(round(min(l, r) * W)), int(round(min(t, b) * H)),
                        max(int(round(max(l, r) * W)), int(round(min(l, r) * W)) + 1),
                        max(int(round(max(t, b) * H)), int(round(min(t, b) * H)) + 1)))
        if l > r:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
        if t > b:
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
        return img

    def flip(self, o, im):
        l, r, t, b = self.coords(o)
        if l > r:
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        if t > b:
            im = im.transpose(Image.FLIP_TOP_BOTTOM)
        return im

    def shade(self, o, tile):
        """Vertex colour, gradient, desaturation, alpha and masks."""
        if o["__desat"]:                 # the client greys the texture, then tints it with the vertex colour
            a = tile.getchannel("A")
            tile = tile.convert("L").convert("RGBA")
            tile.putalpha(a)
        v = o["__vertex"]
        if v is not None:
            tile = ImageChops.multiply(tile, Image.new("RGBA", tile.size, tuple(
                int(round(255 * max(0, min(1, x if x is not None else 1)))) for x in (v[1], v[2], v[3], v[4]))))
        g = o["__gradient"]
        if g is not None:
            tile = ImageChops.multiply(tile, gradient(g[1], g[2], g[3], tile.size))
        a = self.tree.alpha(o)
        if a < 0.999:
            tile.putalpha(tile.getchannel("A").point(lambda x, a=a: int(x * a)))
        masks = lua_list(o["__masks"])
        if masks:
            tile = self.apply_masks(o, tile, masks)
        return tile

    def apply_masks(self, o, tile, masks):
        r = self.tree.rect(o)
        x0, y0 = round(self.X(r[0])), round(self.Y(r[1]))
        alpha = tile.getchannel("A")
        for m in masks:
            mr = self.tree.rect(m)
            mt = m["__texture"]
            canvas = Image.new("L", tile.size, 0)
            if mr is not None and mt:
                mx0, my0, mx1, my1 = self.px_box(mr)
                mw, mh = int(round(mx1 - mx0)), int(round(my1 - my0))
                if mw > 0 and mh > 0:
                    src = load_addon_texture(mt)
                    if src is not None:
                        ma = self.crop_coords(m, src).resize((mw, mh), Image.LANCZOS).getchannel("A")
                    else:          # a game mask: round ones are circles, others fill their rect
                        ma = Image.new("L", (mw, mh), 0)
                        dd = ImageDraw.Draw(ma)
                        if any(k in _short(mt).lower() for k in ("circle", "portrait", "round")):
                            dd.ellipse([0, 0, mw - 1, mh - 1], fill=255)
                        else:
                            dd.rectangle([0, 0, mw, mh], fill=255)
                        self.standins["mask " + _short(mt)] = True
                    canvas.paste(ma, (int(round(mx0)) - x0, int(round(my0)) - y0))
            alpha = ImageChops.multiply(alpha, canvas)
        tile.putalpha(alpha)
        return tile

    def text(self, o, r=None, text=None, color=None, justify=None):
        text = o["__text"] if text is None else text
        if not text:
            return
        r = r or self.tree.rect(o)
        if r is None:
            return
        tree, typ, ss = self.tree, self.tree.type, self.ss
        k = tree.scale(o)
        path, size, flags = tree.font(o)
        sp = (o["__spacing"] or 0)
        lines, block = tree.text_block(o, (r[2] - r[0]) / k)
        file, caps, _ = typ.face(path)
        px = size * k * SCALE * ss * typ.em(path)       # glyphs
        lpx = size * k * SCALE * ss                       # the line's height
        base = color or tree.text_color(o)
        a = tree.alpha(o) * (base[3] if len(base) > 3 else 1)
        if a < 0.004:
            return
        jv = o["__justifyV"] or "MIDDLE"
        jh = justify or o["__justifyH"] or "CENTER"
        top = r[1] if jv == "TOP" else (r[3] - block * k if jv == "BOTTOM" else (r[1] + r[3]) / 2 - block * k / 2)
        (sx, sy), scol = tree.shadow(o)
        stroke = 2 if "THICKOUTLINE" in flags else (1 if "OUTLINE" in flags else 0)
        layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        asc = typ.ascent(path, lpx)
        bases = []
        for i, line in enumerate(lines):
            lw = typ.text_px(file, caps, px, "".join(t for t, _ in line))
            lx = self.X(r[0]) if "LEFT" in jh else (self.X(r[2]) - lw if "RIGHT" in jh else
                                                    (self.X(r[0]) + self.X(r[2])) / 2 - lw / 2)
            ly = self.Y(top + i * sum(typ.pitch(size, sp)) * k) + asc
            bases.append(ly / ss)
            passes = []
            if sx or sy:
                passes.append(((sx * k * SCALE * ss, -sy * k * SCALE * ss), scol, True))
            passes.append(((0, 0), None, False))
            for (dx, dy), pcol, is_shadow in passes:
                x = lx
                for t, c in line:
                    col = pcol if is_shadow else (c or base[:3])
                    alpha = (pcol[3] if is_shadow else 1) * a
                    fill = tuple(int(round(255 * max(0, min(1, v)))) for v in col[:3]) + (int(round(255 * alpha)),)
                    x = self.draw_run(d, file, caps, px, x + dx, ly + dy, t, fill, stroke * ss) - dx
        self.composite(layer, 0, 0)
        self.record("text", o, self.px_box(r), text=plain(text), lines=["".join(t for t, _ in ln) for ln in lines],
                    baseline=bases[0] if bases else None, baselines=bases, size=size * k, font=str(path),
                    top=self.Y(top) / ss)

    def draw_run(self, d, file, caps, px, x, y, t, fill, stroke):
        typ = self.tree.type
        kw = {"stroke_width": stroke, "stroke_fill": (0, 0, 0, fill[3])} if stroke else {}
        if not caps:
            f = typ.font(file, px)
            d.text((x, y), t, font=f, fill=fill, anchor="ls", **kw)
            return x + f.getlength(t)
        for i, (ch, sub) in enumerate(typ.caps_parts(t)):
            f = typ.font(file, px * (SMALLCAPS_RATIO if sub else 1))
            x += SMALLCAPS_TRACK * px if i else 0
            d.text((x, y), ch, font=f, fill=fill, anchor="ls", **kw)
            x += f.getlength(ch)
        return x

    # -- frames: what the client's templates and backdrops draw
    def furniture(self, f, stage):
        """stage 'under': before the frame's regions; 'over': after them."""
        r = self.tree.rect(f)
        if r is None:
            return
        tpl = str(f["__template"] or "")
        x0, y0, x1, y1 = self.px_box(r)
        w, h = int(round(x1 - x0)), int(round(y1 - y0))
        if w <= 0 or h <= 0:
            return
        a = self.tree.alpha(f)
        ss = self.ss
        tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        enabled = not f["__disabled"]
        drew = None
        if stage == "under" and f["__backdrop"] is not None:
            self.backdrop(f, r)
        if stage == "under" and "UIPanelButtonTemplate" in tpl:
            top, bot = ((150, 22, 10), (96, 10, 4)) if enabled else ((92, 70, 64), (66, 52, 48))
            for yy in range(h):
                t = yy / max(1, h - 1)
                d.line([(0, yy), (w, yy)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
            d.rectangle([0, 0, w - 1, h - 1], outline=(30, 8, 4, 255), width=ss)
            d.rectangle([ss, ss, w - 1 - ss, h - 1 - ss], outline=(176, 132, 56, 255) if enabled else (120, 110, 100, 255),
                        width=ss)
            drew = "button"
        elif stage == "under" and "UICheckButtonTemplate" in tpl:
            b = [w * 0.16, h * 0.16, w * 0.84, h * 0.84]
            d.rectangle(b, fill=(34, 28, 22, 235), outline=(150, 132, 96, 255) if enabled else (110, 104, 96, 255),
                        width=max(1, ss))
            if f["__checked"]:
                col = (255, 206, 0, 255) if enabled else (150, 150, 150, 255)
                d.line([(w * .26, h * .52), (w * .44, h * .72), (w * .78, h * .26)], fill=col, width=max(2, int(w / 7)))
            drew = "check"
        elif stage == "under" and "UIRadioButtonTemplate" in tpl:
            d.ellipse([w * .08, h * .08, w * .92, h * .92], fill=(34, 28, 22, 235),
                      outline=(150, 132, 96, 255) if enabled else (110, 104, 96, 255), width=max(1, ss))
            if f["__checked"]:
                col = (255, 206, 0, 255) if enabled else (150, 150, 150, 255)
                d.ellipse([w * .32, h * .32, w * .68, h * .68], fill=col)
            drew = "radio"
        elif stage == "under" and tpl == "UIPanelCloseButton":
            vx0, vy0, vx1, vy1 = (v * s for v, s in zip(VISIBLE["ui-panel-minimizebutton-up"], (w, h, w, h)))
            d.rectangle([vx0, vy0, vx1, vy1], fill=(128, 14, 8, 255), outline=(150, 140, 120, 255), width=max(1, ss))
            m = (vx1 - vx0) * 0.28
            for p, q in (((vx0 + m, vy0 + m), (vx1 - m, vy1 - m)), ((vx1 - m, vy0 + m), (vx0 + m, vy1 - m))):
                d.line([p, q], fill=(250, 210, 30, 255), width=max(2, int((vx1 - vx0) / 6)))
            drew = "close"
        elif stage == "under" and "FauxScrollFrameTemplate" in tpl:
            total, shown = f["__fauxTotal"] or 0, f["__fauxShown"] or 0
            if total > shown:          # the template's bar: 16 wide, 6 right of the frame, 16 in from each end
                bx0, by0 = self.X(r[2] + 6), self.Y(r[1] + 16)
                bx1, by1 = self.X(r[2] + 22), self.Y(r[3] - 16)
                bar = Image.new("RGBA", (int(bx1 - bx0), int(by1 - by0)), (60, 60, 70, 190))
                ImageDraw.Draw(bar).text((2 * ss, 2 * ss), "scroll", font=_label_font(8 * ss), fill=(200, 200, 210, 230))
                self.composite(bar, bx0, by0)
                self.standins["FauxScrollFrame bar"] = True
                self.record("furniture", f, (bx0, by0, bx1, by1), what="scrollbar")
        if drew:
            if a < 0.999:
                tile.putalpha(tile.getchannel("A").point(lambda v, a=a: int(v * a)))
            self.composite(tile, x0, y0)
            self.standins["template " + tpl] = True
            self.record("furniture", f, (x0, y0, x1, y1), what=drew)
        if stage == "over":
            text = f["__text"]
            if text and f["__kind"] in ("Button", "CheckButton") and "UIPanelButtonTemplate" in tpl:
                fo = self.tree.G["GameFontNormal" if enabled else "GameFontDisable"]
                self.button_text(f, r, text, fo)
            elif text and f["__kind"] == "EditBox":
                self.edit_text(f, r, text)

    def button_text(self, f, r, text, fo):
        tmp = {"__text": text, "__fontObj": fo, "__justifyH": "CENTER", "__justifyV": "MIDDLE",
               "__seq": -1, "__parent": f, "__alpha": 1, "__kind": "FontString"}
        self.text(self.tree.wow.lua.table_from(tmp), r=r)

    def edit_text(self, f, r, text):
        tmp = {"__text": text, "__fontObj": f["__fontObj"], "__justifyH": "LEFT", "__justifyV": "MIDDLE",
               "__seq": -1, "__parent": f, "__alpha": 1, "__kind": "FontString", "__wrap": False}
        if f["__textColor"] is not None:
            tmp["__textColor"] = f["__textColor"]
        self.text(self.tree.wow.lua.table_from(tmp), r=r)

    def backdrop(self, f, r):
        """BackdropTemplate's edge: a stand-in for UI-DialogBox-Border, its
        dark band and two lines where Joe's screenshot shows them."""
        bd = f["__backdrop"]
        col = f["__backdropBorder"]
        c = (col[1], col[2], col[3]) if col is not None else (1, 1, 1)
        edge = bd["edgeSize"] or 16
        x0, y0, x1, y1 = self.px_box(r)
        w, h = int(round(x1 - x0)), int(round(y1 - y0))
        tile = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        u = SCALE * self.ss

        def frame(inset, thick, fill):
            o = inset * u
            d.rectangle([o, o, w - 1 - o, h - 1 - o], outline=fill, width=max(1, int(round(thick * u))))

        k = edge / 24
        frame(3 * k, 14 * k, (30, 16, 6, 255))
        for inset in (12.5 * k, 16.0 * k):
            frame(inset, 1, tuple(int(255 * v * 0.8) for v in c) + (255,))
        d.text((6 * u, h - 13 * u), "game: " + _short(bd["edgeFile"] or "edge"), font=_label_font(int(8 * self.ss)),
               fill=(150, 130, 100, 200))
        self.composite(tile, x0, y0)
        self.standins["backdrop " + _short(bd["edgeFile"] or "")] = True
        self.record("furniture", f, (x0, y0, x1, y1), what="backdrop")

    # -- everything
    def clip_of(self, f):
        """The window of the scroll frame f sits in, in px, or None."""
        w = f
        while w is not None:
            sp = w["__scrollParent"]
            if sp is not None:
                r = self.tree.rect(sp)
                return self.px_box(r) if r else None
            w = w["__parent"]
        return None

    def paint(self):
        for f, regs in self.tree.walk():
            self.clip = self.clip_of(f)
            self.furniture(f, "under")
            for reg in regs:
                kind = reg["__kind"]
                layer = reg["__drawLayer"] or "ARTWORK"
                if layer == "HIGHLIGHT" or not self.tree.visible(reg):
                    continue
                if kind == "Texture":
                    self.texture(reg)
                elif kind == "FontString":
                    self.text(reg)
            self.furniture(f, "over")
        self.clip = None
        return self.im.convert("RGB").resize(CANVAS, Image.LANCZOS)


def gradient(orient, lo, hi, size):
    """SetGradient: HORIZONTAL runs min->max left to right, VERTICAL bottom to top."""
    w, h = size
    lo = [lo[i] if lo[i] is not None else 1 for i in range(1, 5)]
    hi = [hi[i] if hi[i] is not None else 1 for i in range(1, 5)]
    n = w if orient == "HORIZONTAL" else h
    strip = Image.new("RGBA", (n, 1))
    for i in range(n):
        t = i / max(1, n - 1)
        if orient != "HORIZONTAL":
            t = 1 - t
        strip.putpixel((i, 0), tuple(int(round(255 * (lo[c] + (hi[c] - lo[c]) * t))) for c in range(4)))
    if orient == "HORIZONTAL":
        return strip.resize((w, h), Image.NEAREST)
    return strip.transpose(Image.ROTATE_270).transpose(Image.FLIP_LEFT_RIGHT).resize((w, h), Image.NEAREST)


# ---------------------------------------------------------------------------- driving the addon
TABS = ("campaigns", "grudges", "ledger", "settings", "warpath")


def boot(saved=None, account=None, name="Tester", at=None, fonts="standin", addon_dir=REPO, faction=None):
    """The addon booted with real text metrics, logged in, ready to open."""
    typ = Type(fonts)
    player = {"name": name}
    if faction:
        player["faction"] = faction
    wow = Wow(saved=saved, saved_global=account, player=player, addon_dir=addon_dir)
    if at:
        wow.H.now = int(at)
    wow.H.measure = lambda path, size, text: typ.width(path, size, text)
    wow.H.lines = lambda path, size, text, width, wrap: len(typ.lines(path, size, text, width, wrap))
    wow.H.height = lambda n, size, spacing: typ.height(n, size, spacing)
    wow.login(settle=5)
    return wow, typ


def open_book(wow, tab="campaigns", page=None, section=None, preview=False):
    """Open the chronicle on a tab as the player would, and turn to a page."""
    if tab not in TABS:
        raise ValueError(f"no tab {tab!r}; tabs: {', '.join(TABS)}")
    already = wow.eval("ns.Chronicle.Shown()")
    if tab == "settings":
        wow.run(f"ns.ShowSetup(nil, {lua_str(section) if section else 'nil'})")
    elif not (already == tab and not preview and not page):
        # opened by itself after an update (MaybeShowSetup): left as it is
        wow.run(f"ns.Chronicle.Open({'true' if preview else 'false'}, {lua_str(tab)})")
    if page and page > 1:
        if tab == "campaigns":
            for _ in range(page - 1):
                wow.run("local b = WarpathChronicle.camp.earlier if b:IsEnabled() then b:GetScript('OnClick')(b) end")
        elif tab == "warpath":       # one sheet that scrolls: a "page" is a sheet's height further down
            wow.run(f"local s = WarpathChronicle.news.sheet s:SetScroll({int(page) - 1} * s:Height())")
        elif tab == "grudges":
            wow.run(f"ns.ChronGrudges.Choose({int(page)}, true)")
    return already


# The design renders' right page lists a made-up 21-kill night (the design
# folder's type/overflow.py LONG) under Lethality's real 25 November left
# page. This puts that night into the 25 November campaign (found by its
# start), so the right page can be set beside ov_V5a/ov_V5b. Times are that
# evening's; 0:07 and after fall on the 26th.
DESIGN_NIGHT = r"""
local LONG = {
  {1427,"17:35","Bluey","ROGUE",57,"first"},
  {1443,"20:31","Balrog","MAGE",48,"first"},
  {1452,"22:52","Pherk","DRUID",60,"first"},
  {1452,"22:52","Felon","WARRIOR",55,"first",2},
  {1452,"22:56","Felon","WARRIOR",55,"streak",nil,5},
  {1452,"23:01","Aelric","MAGE",58}, {1452,"23:04","Thornn","SHAMAN",60},
  {1452,"23:09","Mirelle","ROGUE",59}, {1452,"23:12","Brannoc","WARRIOR",60},
  {1452,"23:15","Sylvae","DRUID",57}, {1452,"23:18","Kestrel","ROGUE",60,"avenged"},
  {1452,"23:24","Ondrin","MAGE",56}, {1452,"23:26","Halvard","SHAMAN",60,"streak",nil,10},
  {1452,"23:31","Lunara","DRUID",58}, {1452,"23:33","Pyke","ROGUE",55},
  {1445,"23:59","Xylanthian","SHAMAN",49,"first"},
  {1445,"0:07","Dorrin","WARRIOR",50}, {1445,"0:11","Elspeth","MAGE",52},
  {1445,"0:12","Tamsin","ROGUE",48,nil,2}, {1445,"0:20","Corwin","WARRIOR",51},
  {1445,"0:26","Vela","DRUID",50},
}
for _, c in ipairs(WarpathDB.campaigns) do
  if date("%d %m", c.start) == "25 11" then
    local base = date("*t", c.start)
    base.hour, base.min, base.sec = 0, 0, 0
    local day = time(base)
    c.kl = {}
    for i, k in ipairs(LONG) do
      local h, m = k[2]:match("(%d+):(%d+)")
      local t = day + tonumber(h) * 3600 + tonumber(m) * 60 + i
      if tonumber(h) < 12 then t = t + 86400 end
      c.kl[i] = { z = k[1], t = t, n = k[3], f = k[3] .. "-Design", c = k[4], lv = k[5], tag = k[6], mk = k[7],
        st = k[8] or i, shot = 10 + i, x = 0.5, y = 0.5 }
    end
    c.kills, c.best = 21, 10
  end
end"""


# The Grudges design renders' made-up busy list (grudges/gdata.py BUSY),
# saved as real grudges (so Waypoint and Forgive work, unlike the preview).
DESIGN_GRUDGES = r"""
WarpathGlobal.kos = {}
for _, it in ipairs(ns.ChronGrudges.Samples(time())) do WarpathGlobal.kos[it.full] = it.r end"""


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_book(wow, typ, origin="shot", ss=2):
    """Paint the open chronicle. Returns (image at 1092x748, painter)."""
    root = wow.lua.globals()["WarpathChronicle"]
    if root is None:
        raise RuntimeError("the chronicle was never built")
    if isinstance(origin, str):
        origin = ORIGINS[origin]
    tree = Tree(wow, root, typ)
    painter = Painter(tree, origin, ss)
    img = painter.paint()
    return img, painter


# ---------------------------------------------------------------------------- comparing with a design
def design_canvas(path):
    """A design render at the base canvas (1092x748): an _ingame render is
    scaled back down, and the caption strip under a labelled render is cut."""
    im = Image.open(path).convert("RGB")
    if im.width != CANVAS[0]:
        im = im.resize((CANVAS[0], round(im.height * CANVAS[0] / im.width)), Image.LANCZOS)
    if im.height > CANVAS[1]:
        im = im.crop((0, 0, CANVAS[0], CANVAS[1]))
    elif im.height < CANVAS[1]:
        pad = Image.new("RGB", CANVAS, BACKGROUND)
        pad.paste(im, (0, 0))
        im = pad
    return im


def caption(img, text):
    out = Image.new("RGB", (img.width, img.height + 28), (24, 22, 18))
    out.paste(img, (0, 28))
    ImageDraw.Draw(out).text((10, 5), text, fill=(235, 220, 180), font=_label_font(16))
    return out


def scaled(img, scale):
    if abs(scale - 1) < 1e-6:
        return img
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def beside(code, design, scale, code_label, design_label):
    a, b = caption(scaled(code, scale), code_label), caption(scaled(design, scale), design_label)
    out = Image.new("RGB", (a.width + b.width + 8, max(a.height, b.height)), (24, 22, 18))
    out.paste(a, (0, 0))
    out.paste(b, (a.width + 8, 0))
    return out


def onion(code, design, scale, label):
    return caption(scaled(Image.blend(code, design, 0.5), scale), label)
