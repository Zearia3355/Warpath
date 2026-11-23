#!/usr/bin/env python3
"""Draw Warpath's CurseForge logo from the addon's own visual language.

Dark ground under a faint map grid, battle haze bleeding red through it, a
road that gilds from dull bronze to worn gold as it climbs, the dashes of
today's trail breaking away from it, and amber glints on the worn stretch.

Follows the project's own rule that brightness comes from saturation, never
from lightening toward white, so the centre stripe tops out at warm yellow.

Technique notes: each road layer is stroked in ONE flat colour, and the
gilding is a gradient composited through the stroke's own mask. Colouring
per segment instead leaves ribbing where the round joins overlap.
Everything is drawn at 4x and downsampled, since PIL does not antialias.
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 4
OUT = 400
N = OUT * S

GROUND = (16, 13, 10)
GRID = (33, 27, 19)
HAZE = (168, 26, 30)
CASING = (32, 22, 10)
DULL = (104, 76, 28)
GOLD = (206, 152, 40)
BRIGHT = (255, 203, 84)
STRIPE_LO = (150, 112, 36)
STRIPE_HI = (255, 224, 138)
TRAIL = (205, 66, 50)
GLINT = (116, 82, 28)


def bezier(p0, p1, p2, p3, steps=200):
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0],
            u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1],
        ))
    return out


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def stroke_mask(pts, width):
    """A flat mask of one stroke: no colour, so no colour-join artefacts.

    The round joins still scallop the edge slightly, which shows as faint
    ticks across the road, so the mask gets a small blur. That also gives the
    road the soft edge it has in game.
    """
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    d.line(pts, fill=255, width=width, joint="curve")
    r = width / 2
    for end in (pts[0], pts[-1]):
        d.ellipse([end[0]-r, end[1]-r, end[0]+r, end[1]+r], fill=255)
    return m.filter(ImageFilter.GaussianBlur(S * 1.4))


def gilding(lo, hi):
    """A gradient running along the road's climb: bottom-left to top-right."""
    g = Image.new("RGB", (N, N))
    px = g.load()
    for y in range(N):
        for x in range(0, N, 8):           # 8px columns, smoothed later
            t = (x / N) * 0.45 + (1 - y / N) * 0.55
            c = lerp(lo, hi, t)
            for k in range(8):
                if x + k < N:
                    px[x + k, y] = c
    return g.filter(ImageFilter.GaussianBlur(S * 2))


# --- ground, map grid, battle haze ------------------------------------------
img = Image.new("RGB", (N, N), GROUND)
gd = ImageDraw.Draw(img)
for i in range(1, 8):
    p = int(N * i / 8)
    gd.line([(p, 0), (p, N)], fill=GRID, width=max(S // 2, 1))
    gd.line([(0, p), (N, p)], fill=GRID, width=max(S // 2, 1))

haze = Image.new("RGB", (N, N), (0, 0, 0))
hd = ImageDraw.Draw(haze)
for cx, cy, r, a in ((0.28, 0.62, 0.34, 1.00), (0.64, 0.33, 0.26, 0.80),
                     (0.46, 0.50, 0.20, 0.60), (0.78, 0.74, 0.16, 0.50),
                     (0.18, 0.30, 0.14, 0.35)):
    for step in range(32, 0, -1):
        f = step / 32
        rr = r * N * f
        hd.ellipse([cx*N - rr, cy*N - rr, cx*N + rr, cy*N + rr],
                   fill=lerp((0, 0, 0), HAZE, a * (1 - f) ** 1.5 * 0.60))
img = ImageChops.add(img, haze.filter(ImageFilter.GaussianBlur(N * 0.028)))

# --- today's trail: dashes that shorten and fade as they age ----------------
draw = ImageDraw.Draw(img)
trail = bezier((0.05*N, 0.74*N), (0.30*N, 0.90*N),
               (0.50*N, 0.52*N), (0.78*N, 0.40*N))
seg, gap, i = 10, 11, 0
while i < len(trail) - 1:
    piece = trail[i:i + seg]
    if len(piece) > 1:
        t = i / len(trail)
        draw.line(piece, fill=lerp(TRAIL, GROUND, t * 0.65),
                  width=max(int((11 - 6 * t) * S), 2), joint="curve")
    i += seg + gap

# --- the road -----------------------------------------------------------------
road = bezier((0.16*N, 0.96*N), (0.31*N, 0.44*N),
              (0.69*N, 0.60*N), (0.86*N, 0.06*N))

img.paste(CASING, (0, 0), stroke_mask(road, int(26 * S)))
img.paste(gilding(DULL, BRIGHT), (0, 0), stroke_mask(road, int(16 * S)))
img.paste(gilding(STRIPE_LO, STRIPE_HI), (0, 0), stroke_mask(road, int(5 * S)))

# --- glints, added so they glow rather than paint ---------------------------
glints = Image.new("RGB", (N, N), (0, 0, 0))
qd = ImageDraw.Draw(glints)
for at, size in ((0.74, 30), (0.89, 21), (0.60, 16)):
    gx, gy = road[int(at * (len(road) - 1))]
    r = size * S
    qd.polygon([(gx, gy-r), (gx+r*0.22, gy), (gx, gy+r), (gx-r*0.22, gy)], fill=GLINT)
    qd.polygon([(gx-r, gy), (gx, gy-r*0.22), (gx+r, gy), (gx, gy+r*0.22)], fill=GLINT)
img = ImageChops.add(img, glints.filter(ImageFilter.GaussianBlur(S * 2.4)))

img.resize((OUT, OUT), Image.LANCZOS).save(
    r"C:\Users\Joe\AppData\Local\Temp\claude\1ea274ff47dd4eda\5b88f6de-ed86-4b6f-b423-07efd0e5e25f\scratchpad\warpath-logo.png", "PNG")
print("wrote warpath-logo.png 400x400")
