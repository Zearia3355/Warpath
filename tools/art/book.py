"""The chronicle's book art: crimson leather, gold corners, the page stack, parchment and burn.

Moved here from the design folder (tools/out/design/book: refine.py on top of aged.py and tome.py),
keeping only what draws the book itself. Nothing in it reads an outside image: every pixel is drawn
by this script, so the art is ours and ships under the addon's MIT licence.

The book is drawn at 2x (S) on a 1092x748 canvas, the design renders' canvas, and downsampled.
The frame the addon shows (880x580 UI units, 1.2 px per unit on Joe's screen) is FRAME inside it.
`book_rgba()` returns the book alone with an alpha channel: it draws the book twice, on two flat
greys, and solves for alpha, so every soft edge (rounded corners, the corner pieces' shadows) keeps
exactly the coverage the design render had.

Pillow only (no numpy), like the design scripts.
"""
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

S = 2                                   # supersampling
W, H = 1092, 748                        # the design renders' canvas
GUT = 546                               # the gutter
COVER = (22, 44, 1070, 733)             # the leather
PX0, PY0, PX1, PY1 = 60, 74, 1032, 702  # the top leaf's page block
SEED = 6
LEATHER = (92, 18, 12)
PAPER = (228, 180, 106)                 # the canon's parchment base
# the 880x580-unit frame at 1.2 px per unit, centred on the leather
FRAME = (18, 40, 1074, 736)             # 1056 x 696
# the art's own rect: the frame, plus the gold corners' shadows that fall past its right and foot
ART = (18, 40, 1080, 744)               # 1062 x 704, anchored at the frame's top left
# the book's own drop shadow (drawn on the scene behind it, shipped separately as a 9-slice)
DROP = dict(offset=(6, 10), grow=(0, 4), radius=16, blur=12, colour=(8, 3, 1), alpha=0.8)
# The foot of the page stack and the bottom corners (Joe, 2026-11-28, from
# 3.8.5-test2 in game): the pages lie over the bottom corner pieces ("all 7"),
# the stack fans 75% as far at the foot (more leather below it), and the stack
# casts a soft shadow on the gold it covers (S1). The top corners stay over
# the pages, as settled.
FOOT_FAN = 0.75
STACK_SHADOW = dict(blur=2.5, dx=1.5, dy=2.5, alpha=0.6, colour=(40, 18, 4))


def sc(box): return tuple(int(v * S) for v in box)


# ------------------------------------------------------------------ noise helpers (from tome.py)
def noise(w, h, cell, seed, blur=None, aspect=1.0):
    r = random.Random(seed)
    sw, sh = max(2, int(w / (cell * aspect))), max(2, int(h / cell))
    im = Image.new("L", (sw, sh))
    im.putdata([r.randint(0, 255) for _ in range(sw * sh)])
    im = im.resize((w, h), Image.BICUBIC)
    return im.filter(ImageFilter.GaussianBlur(blur)) if blur else im


def fbm(w, h, cells, seed, weights=None):
    weights = weights or [1.0] * len(cells)
    out = Image.new("L", (w, h), 128)
    for i, (c, wt) in enumerate(zip(cells, weights)):
        n = noise(w, h, c, seed + i * 17, blur=max(1, c / 4))
        out = ImageChops.add(out, n.point(lambda v, wt=wt: int(128 + (v - 128) * wt)), 1, -128)
    return out


def colorize(shade, base, gain=1.0, centre=128):
    """shade 128 = base colour; above lightens by saturating, below darkens."""
    chans = []
    for c in base:
        chans.append(shade.point([max(0, min(255, int(c * (1 + (s - centre) / 128 * gain)))) for s in range(256)]))
    return Image.merge("RGB", chans)


def rrect_mask(size, box, r, blur=0):
    mk = Image.new("L", size, 0)
    ImageDraw.Draw(mk).rounded_rectangle(box, r, fill=255)
    return mk.filter(ImageFilter.GaussianBlur(blur)) if blur else mk


def dist_edge_mask(w, h, reach, sides="lrtb", wobble=None, power=2.0, strength=255):
    """255 at the chosen edges fading to 0 at `reach` px; built from 1-D gradients."""
    out = Image.new("L", (w, h), 0)
    def ramp(n):
        return [int(strength * max(0.0, 1 - i / reach) ** power) for i in range(n)]
    if "l" in sides:
        g = Image.new("L", (w, 1)); g.putdata(ramp(w)); out = ImageChops.lighter(out, g.resize((w, h)))
    if "r" in sides:
        g = Image.new("L", (w, 1)); g.putdata(ramp(w)[::-1]); out = ImageChops.lighter(out, g.resize((w, h)))
    if "t" in sides:
        g = Image.new("L", (1, h)); g.putdata(ramp(h)); out = ImageChops.lighter(out, g.resize((w, h)))
    if "b" in sides:
        g = Image.new("L", (1, h)); g.putdata(ramp(h)[::-1]); out = ImageChops.lighter(out, g.resize((w, h)))
    if wobble is not None:
        out = ImageChops.multiply(out, wobble.point(lambda v: int(150 + v * 0.42)))
    return out


# ------------------------------------------------------------------ the cover
def leather(w, h, base, seed, grain=1.0):
    big = fbm(w, h, [260, 90], seed, [0.55, 0.35])
    fine = noise(w, h, 3.2, seed + 5, blur=0.9)
    pores = fine.filter(ImageFilter.EMBOSS).point(lambda v: int(128 + (v - 128) * 0.9 * grain))
    cr = noise(w, h, 18, seed + 9, blur=3, aspect=3.5).filter(ImageFilter.FIND_EDGES).point(
        lambda v: 128 - min(40, v * 2))                    # faint creases
    shade = ImageChops.add(big, pores, 1, -128)
    shade = ImageChops.add(shade, cr, 1, -128)
    return colorize(shade, base, gain=0.9)


def pressed_rule(img, box, inset):
    """Blind tooling: a groove pressed into the leather, dark in the cut, a lit lip below it."""
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = [v * S for v in box]
    for ins, wd in ((inset, 2), (inset + 4, 1)):
        i = ins * S
        d.rounded_rectangle((x0 + i + S, y0 + i + S, x1 - i + S, y1 - i + S), 6 * S, outline=(150, 46, 30), width=wd * S)
        d.rounded_rectangle((x0 + i, y0 + i, x1 - i, y1 - i), 6 * S, outline=(30, 4, 2), width=wd * S)


# ------------------------------------------------------------------ metal, lit from the top left
def lit_metal(mask, base, seed, depth=9):
    """A rounded bevel: height from repeated erosion, shading from its slope, a warm sheen."""
    w, h = mask.size
    hmap = Image.new("L", (w, h), 0)
    cur = mask
    step = 255 // depth
    for _ in range(depth):
        hmap = ImageChops.add(hmap, cur.point(lambda v: step if v > 128 else 0))
        cur = cur.filter(ImageFilter.MinFilter(3))
    hmap = hmap.point(lambda v: int(255 * math.sqrt(v / 255))).filter(ImageFilter.GaussianBlur(1.2 * S))
    kx = ImageFilter.Kernel((3, 3), [-1, 0, 1, -2, 0, 2, -1, 0, 1], scale=1, offset=128)
    ky = ImageFilter.Kernel((3, 3), [-1, -2, -1, 0, 0, 0, 1, 2, 1], scale=1, offset=128)
    gx, gy = hmap.filter(kx), hmap.filter(ky)
    shade = ImageChops.add(gx.point(lambda v: 128 - (v - 128) * 3), gy.point(lambda v: 128 - (v - 128) * 3), 1, -128)
    grain = fbm(w, h, [20 * S, 5 * S, 1.5 * S], seed, [0.22, 0.16, 0.12])
    shade = ImageChops.add(shade, grain, 1, -128)
    diag = Image.linear_gradient("L").rotate(45, expand=True).resize((w, h)).point(lambda v: int(118 + v * 0.08))
    shade = ImageChops.add(shade, diag, 1, -128)
    col = colorize(shade, base, gain=0.85)
    hot = shade.point(lambda v: max(0, (v - 175) * 4))
    return Image.composite(Image.new("RGB", (w, h), (246, 204, 104)), col, hot.filter(ImageFilter.GaussianBlur(S)))


def stud(img, cx, cy, r, gold):
    """A pyramid stud, lit from the top left whichever corner it sits in."""
    d = ImageDraw.Draw(img)
    def sh(k): return tuple(max(0, min(255, int(c * k))) for c in gold)
    tl, tr, br, bl, c = (cx - r, cy - r), (cx + r, cy - r), (cx + r, cy + r), (cx - r, cy + r), (cx, cy)
    d.ellipse((cx - r + S, cy - r + 2 * S, cx + r + 2 * S, cy + r + 3 * S), fill=(40, 22, 4))   # its shadow
    d.polygon([tl, tr, c], fill=sh(1.3))
    d.polygon([tl, bl, c], fill=sh(1.05))
    d.polygon([tr, br, c], fill=sh(0.7))
    d.polygon([bl, br, c], fill=sh(0.5))
    d.line([tl, c], fill=sh(1.5), width=S)


def gold_corner(img, x, y, sx, sy, seed, size=84, arm=24, gold=(170, 118, 42)):
    w, h = img.size
    L, ar, ch = size * S, arm * S, 9 * S
    pts = [(0, 0), (L, 0), (L - ch, ar), (ar, ar), (ar, L - ch), (0, L)]
    mk = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mk).polygon([(x + sx * px, y + sy * py) for px, py in pts], fill=255)
    bb = mk.getbbox()
    pad = 6 * S
    bb = (bb[0] - pad, bb[1] - pad, bb[2] + pad, bb[3] + pad)
    sub = mk.crop(bb)
    # shadow falls down-right on the leather, the same for every corner
    shd = sub.filter(ImageFilter.GaussianBlur(3 * S)).point(lambda v: int(v * 0.6))
    img.paste(Image.new("RGB", sub.size, (14, 3, 0)), (bb[0] + 2 * S, bb[1] + 3 * S), shd)
    img.paste(lit_metal(sub, gold, seed), bb[:2], sub)
    edge = ImageChops.subtract(sub, sub.filter(ImageFilter.MinFilter(3)))
    img.paste(Image.new("RGB", sub.size, (78, 48, 14)), bb[:2], edge.point(lambda v: int(v * 0.7)))
    for cx, cy, rr in ((x + sx * ar * 0.52, y + sy * ar * 0.52, 7 * S),
                       (x + sx * (L - 15 * S), y + sy * ar * 0.5, 4 * S),
                       (x + sx * ar * 0.5, y + sy * (L - 15 * S), 4 * S)):
        stud(img, cx, cy, rr, gold)


# ------------------------------------------------------------------ paper
def parchment(w, h, base, seed):
    """Paper with a body: grain at every scale, fibres, flecks, a faint crumple, warm patches."""
    shade = fbm(w, h, [180 * S, 60 * S, 18 * S, 5 * S, 2 * S], seed, [0.30, 0.32, 0.27, 0.14, 0.10])
    # crumple: a faint network of ridges, lit from the top left
    rn = noise(w, h, 70 * S, seed + 7, blur=6 * S).point(lambda v: 255 - min(255, abs(v - 128) * 6))
    rn = rn.filter(ImageFilter.GaussianBlur(1.5 * S)).filter(ImageFilter.EMBOSS).point(lambda v: int(128 + (v - 128) * 0.55))
    shade = ImageChops.add(shade, rn, 1, -128)
    r_, g_, b_ = base
    img = Image.merge("RGB", [shade.point([max(0, min(255, int(c * (1 + (v - 128) / 128 * k)))) for v in range(256)])
                              for c, k in ((r_, 0.30), (g_, 0.40), (b_, 0.60))])
    # warm patches: some areas slightly oranger, some paler
    warm = noise(w, h, 240 * S, seed + 9, blur=40 * S).point(lambda v: max(0, (v - 128) * 3))
    img = Image.composite(Image.new("RGB", (w, h), (min(255, r_ + 4), int(g_ * 0.9), int(b_ * 0.72))), img, warm)
    # fibres: short strokes, a little darker or lighter, at every angle
    rr = random.Random(seed)
    fib = Image.new("L", (w, h), 128)
    fd = ImageDraw.Draw(fib)
    for _ in range(int(w * h / (S * S) / 55)):
        x, y = rr.random() * w, rr.random() * h
        ln = rr.uniform(2, 6) * S
        an = rr.uniform(0, math.pi)
        fd.line((x, y, x + math.cos(an) * ln, y + math.sin(an) * ln),
                fill=rr.choice([114, 118, 122, 136, 140]), width=1)
    fib = fib.filter(ImageFilter.GaussianBlur(0.5 * S))
    img = ImageChops.multiply(img, Image.merge("RGB", [fib.point(lambda v: min(255, int(v * 1.99)))] * 3))
    # flecks: tiny dark specks
    fl = Image.new("L", (w, h), 0)
    dd = ImageDraw.Draw(fl)
    for _ in range(int(w * h / (S * S) / 900)):
        x, y = rr.random() * w, rr.random() * h
        q = rr.choice([0.5, 0.6, 0.8, 1.0, 1.4]) * S
        dd.ellipse((x - q, y - q, x + q, y + q), fill=rr.randint(40, 120))
    return Image.composite(Image.new("RGB", (w, h), (92, 52, 22)), img, fl)


def age_paper(w, h, base, seed):
    paper = parchment(w, h, base, seed)
    # gentle tide-marks: broad and faint, never blotches
    clouds = fbm(w, h, [520, 220], seed + 40, [0.8, 0.4]).point(lambda v: max(0, (v - 150) * 2))
    paper = Image.composite(Image.new("RGB", (w, h), tuple(int(c * 0.84) for c in base)), paper,
                            clouds.filter(ImageFilter.GaussianBlur(24 * S)))
    r = random.Random(seed)
    fx = Image.new("L", (w, h), 0)
    fd = ImageDraw.Draw(fx)
    for _ in range(40):
        x, y = r.random() * w, r.random() * h
        rad = r.choice([1, 1, 1, 1.5, 2, 3]) * S
        fd.ellipse((x - rad, y - rad, x + rad, y + rad), fill=r.randint(25, 80))
    return Image.composite(Image.new("RGB", (w, h), (126, 66, 24)), paper, fx.filter(ImageFilter.GaussianBlur(S)))


def burn(sub, sd):
    """Edge toning: a smooth falloff from the frayed edge, tinted from amber to brown."""
    pw, ph = sub.size
    far = sub.filter(ImageFilter.GaussianBlur(30 * S))
    near = sub.filter(ImageFilter.GaussianBlur(7 * S))
    wide = ImageChops.subtract(Image.new("L", (pw, ph), 255), far).point(lambda v: min(255, int(v * 1.5)))
    tight = ImageChops.subtract(Image.new("L", (pw, ph), 255), near).point(lambda v: min(255, int(v * 2.2)))
    vary = noise(pw, ph, 160 * S, sd + 3, blur=30 * S).point(lambda v: int(185 + (v - 128) * 0.5))
    return ImageChops.multiply(wide, vary), tight


def deckle(size, box, seed, rough=5, jag=1.6):
    """A rectangle whose edge wanders and frays: blur, add noise, threshold."""
    w, h = size
    mk = Image.new("L", size, 0)
    ImageDraw.Draw(mk).rectangle(box, fill=255)
    soft = mk.filter(ImageFilter.GaussianBlur(rough * S))
    n1 = noise(w, h, rough * 2.2 * S, seed, blur=S).point(lambda v: int((v - 128) * 1.1))
    n2 = noise(w, h, jag * S, seed + 1).point(lambda v: int((v - 128) * 0.55))
    out = ImageChops.add(ImageChops.add(soft, n1.point(lambda v: v + 128), 1, -128),
                         n2.point(lambda v: v + 128), 1, -128)
    out = out.point(lambda v: 255 if v > 128 else 0)
    # fray only near the edge: nothing detached outside, no holes inside
    x0, y0, x1, y1 = box
    k = rough * 1.3 * S
    outer = Image.new("L", size, 0); ImageDraw.Draw(outer).rectangle((x0 - k, y0 - k, x1 + k, y1 + k), fill=255)
    inner = Image.new("L", size, 0); ImageDraw.Draw(inner).rectangle((x0 + k, y0 + k, x1 - k, y1 - k), fill=255)
    out = ImageChops.lighter(ImageChops.multiply(out, outer), inner)
    return out.filter(ImageFilter.GaussianBlur(0.6 * S))


# ------------------------------------------------------------------ the page block
def build_leaves(img, base, seed, union=None):
    big = img.size
    r = random.Random(seed)
    # the block under the top leaf, back to front: each leaf its own rippling outline, further out at
    # the fore-edge and fanning toward the foot's outer corners, with a soft shadow on the one below,
    # a lit lip, a dark hairline, and the paper's grain
    grain = parchment(big[0], big[1], base, seed + 500)
    x0, y0, x1, y1 = PX0, PY0, PX1, PY1
    half = (x1 - x0) / 2
    n = 7
    offs, acc = [], 0.0
    for _ in range(n):
        acc += r.uniform(2.4, 3.4)
        offs.append(acc)

    def ripple(rr):
        waves = [(rr.uniform(0.5, 1.3), rr.uniform(40, 150), rr.uniform(0, 6.3)) for _ in range(3)]
        return lambda t: sum(amp * math.sin(t / wl * 6.283 + ph) for amp, wl, ph in waves)

    for i in range(n - 1, -1, -1):
        o = offs[i]
        rr = random.Random(seed * 31 + i)
        rt, rl, rb, rrt = ripple(rr), ripple(rr), ripple(rr), ripple(rr)
        pts = []
        def fan(x): return 0.55 + 0.75 * min(1.0, abs(x - GUT) / half) ** 1.5
        for x in range(int(x0), int(x1) + 1, 4):                   # head: barely shows
            pts.append((x, y0 - o * 0.18 - abs(rt(x)) * 0.3))
        for y in range(int(y0), int(y1) + 1, 4):                   # fore-edge, right
            k = 0.75 + 0.45 * (y - y0) / (y1 - y0)
            pts.append((x1 + o * k + rrt(y), y))
        for x in range(int(x1), int(x0) - 1, -4):                  # foot
            pts.append((x, y1 + (o * fan(x) + rb(x)) * FOOT_FAN))
        for y in range(int(y1), int(y0) - 1, -4):                  # fore-edge, left
            k = 0.75 + 0.45 * (y - y0) / (y1 - y0)
            pts.append((x0 - o * k - rl(y), y))
        mk = Image.new("L", big, 0)
        ImageDraw.Draw(mk).polygon([(px * S, py * S) for px, py in pts], fill=255)
        fray = noise(big[0], big[1], 1.2 * S, seed + i).point(lambda v: 255 if v > 70 else 0)
        edge = ImageChops.subtract(mk, mk.filter(ImageFilter.MinFilter(3)))
        mk = ImageChops.subtract(mk, ImageChops.multiply(edge, ImageChops.invert(fray)))
        mk = mk.filter(ImageFilter.GaussianBlur(0.5 * S))
        if union is not None:
            union[0] = mk if union[0] is None else ImageChops.lighter(union[0], mk)
        shd = mk.filter(ImageFilter.GaussianBlur(1.8 * S)).point(lambda v: int(v * 0.72))
        img.paste(Image.new("RGB", big, (46, 20, 6)), (S, int(1.5 * S)), shd)
        tone = r.uniform(0.86, 0.97) * (1 - i * 0.035)
        leaf = Image.merge("RGB", [c.point(lambda v, k=k: int(v * k)) for c, k in
                                   zip(grain.split(), (tone, tone * 0.94, tone * 0.8))])
        img.paste(leaf, (0, 0), mk)
        rim = ImageChops.subtract(mk, mk.filter(ImageFilter.MinFilter(3)))
        lip = ImageChops.subtract(mk.filter(ImageFilter.MinFilter(3)), mk.filter(ImageFilter.MinFilter(5)))
        img.paste(Image.new("RGB", big, (240, 204, 140)), (0, 0), lip.point(lambda v: int(v * 0.45)))
        img.paste(Image.new("RGB", big, (64, 30, 10)), (0, 0), rim.point(lambda v: int(v * r.uniform(0.7, 0.95))))
    # the top leaf, left and right
    for side, box, sd in (("l", (PX0, PY0, GUT + 30, PY1), seed + 101),
                          ("r", (GUT - 30, PY0, PX1, PY1), seed + 202)):
        mk = deckle(big, sc(box), sd, rough=4.5, jag=1.6)
        halfm = Image.new("L", big, 0)
        ImageDraw.Draw(halfm).rectangle(sc((0, 0, GUT, H)) if side == "l" else sc((GUT, 0, W, H)), fill=255)
        mk = ImageChops.multiply(mk, halfm)
        bx0, by0, bx1, by1 = mk.getbbox()
        pw, ph = bx1 - bx0, by1 - by0
        sub = mk.crop((bx0, by0, bx1, by1))
        paper = age_paper(pw, ph, base, sd)
        wide, tight = burn(sub, sd)
        paper = Image.composite(Image.new("RGB", (pw, ph), (176, 106, 44)), paper, wide)
        paper = Image.composite(Image.new("RGB", (pw, ph), (110, 56, 20)), paper, tight)
        gx = GUT * S - bx0
        gv, cv = [], []
        for x in range(pw):
            dx = abs(x - gx) / S
            gv.append(int(225 * max(0.0, 1 - dx / 70) ** 2.2))
            cv.append(int(60 * math.exp(-((dx - 105) / 50) ** 2)))
        g = Image.new("L", (pw, 1)); g.putdata(gv)
        c = Image.new("L", (pw, 1)); c.putdata(cv)
        paper = Image.composite(Image.new("RGB", (pw, ph), (60, 28, 10)), paper, g.resize((pw, ph)))
        paper = Image.composite(Image.new("RGB", (pw, ph), tuple(min(255, int(v * 1.06)) for v in base)), paper,
                                c.resize((pw, ph)))
        shd = sub.filter(ImageFilter.GaussianBlur(2.5 * S)).point(lambda v: int(v * 0.55))
        img.paste(Image.new("RGB", (pw, ph), (40, 18, 6)), (bx0 + S, by0 + 2 * S), shd)
        img.paste(paper, (bx0, by0), sub)


# ------------------------------------------------------------------ the book
def drop_shadow_mask(size, scale=S):
    """The book's drop shadow on whatever lies behind it, as a coverage mask (0..255 * alpha)."""
    cx0, cy0, cx1, cy1 = [v * scale for v in COVER]
    (ox, oy), (gx, gy) = DROP["offset"], DROP["grow"]
    sh = rrect_mask(size, (cx0 + ox * scale, cy0 + oy * scale, cx1 + (ox + gx) * scale, cy1 + (oy + gy) * scale),
                    DROP["radius"] * scale, blur=DROP["blur"] * scale)
    return sh.point(lambda v: int(v * DROP["alpha"]))


def build_book(background, shadow=True):
    """The book over `background` (a 1092x748 RGB image, or a colour), at 1x."""
    if isinstance(background, Image.Image):
        big = background.convert("RGB").resize((W * S, H * S), Image.LANCZOS)
    else:
        big = Image.new("RGB", (W * S, H * S), background)
    cx0, cy0, cx1, cy1 = sc(COVER)
    if shadow:
        big = Image.composite(Image.new("RGB", big.size, DROP["colour"]), big, drop_shadow_mask(big.size))
    cw, ch = cx1 - cx0, cy1 - cy0
    lea = leather(cw, ch, LEATHER, SEED, grain=0.45)
    # scuffs: darker blotches and worn, browner patches
    sc_ = fbm(cw, ch, [180 * S / 2, 60 * S / 2], SEED + 3, [0.9, 0.6]).point(lambda v: max(0, (v - 150) * 4))
    lea = Image.composite(Image.new("RGB", (cw, ch), (58, 16, 10)), lea, sc_.filter(ImageFilter.GaussianBlur(6 * S)))
    wear = dist_edge_mask(cw, ch, 9 * S, "lrtb", noise(cw, ch, 22, SEED, blur=4), power=1.5, strength=190)
    lea = Image.composite(Image.new("RGB", (cw, ch), (120, 44, 26)), lea, wear)
    bevel = dist_edge_mask(cw, ch, 20 * S, "lrtb", power=1.3, strength=90)
    lea = Image.composite(Image.new("RGB", (cw, ch), (12, 2, 0)), lea, bevel)
    big.paste(lea, (cx0, cy0), rrect_mask((cw, ch), (0, 0, cw - 1, ch - 1), 14 * S))
    pressed_rule(big, COVER, 8)
    # the bottom corners first: the page stack lies over them
    bare = big.copy()
    for (x, y, sx, sy) in ((cx1, cy1, -1, -1), (cx0, cy1, 1, -1)):
        gold_corner(big, x, y, sx, sy, SEED + x + y)
    gold = ImageChops.difference(big, bare).convert("L").point(lambda v: 255 if v > 6 else 0)
    union = [None]
    build_leaves(big, PAPER, SEED + 20, union)
    stack_shadow(big, gold, union[0])
    for (x, y, sx, sy) in ((cx0, cy0, 1, 1), (cx1, cy0, -1, 1)):
        gold_corner(big, x, y, sx, sy, SEED + x + y)
    return big.resize((W, H), Image.LANCZOS)


def stack_shadow(img, gold, leaves):
    """The page stack's soft shadow on the gold it lies over (S1)."""
    if leaves is None:
        return
    k = STACK_SHADOW
    cast = ImageChops.offset(leaves, int(k["dx"] * S), int(k["dy"] * S)).filter(ImageFilter.GaussianBlur(k["blur"] * S))
    sh = ImageChops.multiply(ImageChops.multiply(cast, ImageChops.invert(leaves)), gold)
    sh = sh.point(lambda v: int(v * k["alpha"]))
    img.paste(Image.new("RGB", img.size, k["colour"]), (0, 0), sh)


def unmatte(on_a, on_b, a, b):
    """Recover RGBA from the same art drawn over two flat greys a < b (difference matting)."""
    pa, pb = on_a.load(), on_b.load()
    w, h = on_a.size
    out = Image.new("RGBA", (w, h))
    po = out.load()
    span = float(b - a)
    for y in range(h):
        for x in range(w):
            ca, cb = pa[x, y], pb[x, y]
            d = sum(cb[i] - ca[i] for i in range(3)) / 3.0
            al = max(0.0, min(1.0, 1 - d / span))
            if al <= 0.002:
                po[x, y] = (0, 0, 0, 0)
                continue
            col = tuple(max(0, min(255, int(round((ca[i] - (1 - al) * a) / al)))) for i in range(3))
            po[x, y] = col + (int(round(al * 255)),)
    return out


def book_rgba(shadow=False):
    """The book alone, 1092x748 RGBA. Without `shadow`, its drop shadow is left out (it ships as a 9-slice)."""
    lo, hi = 64, 192
    return unmatte(build_book((lo, lo, lo), shadow), build_book((hi, hi, hi), shadow), lo, hi)
