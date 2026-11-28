"""Lay the shipped textures back together, the way the addon will draw them, and diff the result.

    python tools/art/compose.py [--backdrop shot.png] [--ref ref_R1_raw.png]

Run from the repo root. It reads only Art/book/ and the layout table in export.py:
- the book's drop shadow, 9-sliced onto the cover rect moved by its offset;
- the book sheet's pieces, each at its rect in the art, the art anchored at the frame's top left.

It is compared with the generator's own render of the same book (shadow included) on the same
backdrop: that is the reference minus everything the game draws. With --ref, it is also compared
with the design render, whose differences are then only the game's pieces (tabs, title plate,
close, Share, page arrows), the text and the route map. Images go to tools/out/book-art/.
"""
import argparse
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

sys.path.insert(0, str(Path(__file__).resolve().parent))
import book  # noqa: E402
import export as E  # noqa: E402


def nine_slice(tex, m, box):
    """Draw `tex` stretched over `box` (x0, y0, x1, y1), its outer `m` px kept unstretched."""
    w, h = tex.size
    x0, y0, x1, y1 = box
    xs, ys = (0, m, w - m, w), (0, m, h - m, h)
    dx, dy = (x0, x0 + m, x1 - m, x1), (y0, y0 + m, y1 - m, y1)
    out = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    for j in range(3):
        for i in range(3):
            piece = tex.crop((xs[i], ys[j], xs[i + 1], ys[j + 1]))
            size = (dx[i + 1] - dx[i], dy[j + 1] - dy[j])
            if size[0] > 0 and size[1] > 0:
                out.paste(piece.resize(size, Image.BILINEAR), (dx[i] - x0, dy[j] - y0))
    return out


def compose(backdrop):
    canvas = backdrop.convert("RGBA")
    # the drop shadow
    sh = Image.open(E.ART / "book-shadow.tga").convert("RGBA")
    m = E.LAYOUT["book-shadow.tga"]["margin"]
    (ox, oy), (gx, gy) = book.DROP["offset"], book.DROP["grow"]
    cx0, cy0, cx1, cy1 = book.COVER
    edge = (cx0 + ox, cy0 + oy, cx1 + ox + gx, cy1 + oy + gy)
    outer = (edge[0] - m, edge[1] - m, edge[2] + m, edge[3] + m)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(nine_slice(sh, E.LAYOUT["book-shadow.tga"]["slice"], outer), outer[:2])
    canvas = Image.alpha_composite(canvas, layer)
    # the book, piece by piece
    sheet = Image.open(E.ART / "book.tga").convert("RGBA")
    art = E.unpack_sheet(sheet, E.LAYOUT["book.tga"]["pieces"])
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(art, book.ART[:2])
    return Image.alpha_composite(canvas, layer).convert("RGB")


def report(name, a, b, path):
    d = ImageChops.difference(a, b)
    st = ImageStat.Stat(d)
    hist = d.convert("L").histogram()
    n = sum(hist)
    over = {k: round(100 * sum(hist[k + 1:]) / n, 3) for k in (2, 8, 32)}
    print("%-44s mean %.3f  max %d  %% of pixels off by more than 2/8/32: %s/%s/%s" % (
        name, sum(st.mean) / 3, max(hi for lo, hi in d.getextrema()), over[2], over[8], over[32]))
    d.point(lambda v: min(255, v * 4)).save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--backdrop", help="a 1092x748 image behind the book (the design renders used Joe's screenshot)")
    ap.add_argument("--ref", help="the design render to compare with (book/ref_R1_raw.png)")
    args = ap.parse_args()
    bg = Image.open(args.backdrop).convert("RGB") if args.backdrop else Image.new("RGB", (book.W, book.H), (52, 46, 40))
    E.OUT.mkdir(parents=True, exist_ok=True)
    # the generator draws at 2x and shrinks, so its backdrop goes through that round trip too
    bg = bg.resize((book.W * book.S, book.H * book.S), Image.LANCZOS).resize((book.W, book.H), Image.LANCZOS)
    got = compose(bg)
    got.save(E.OUT / "composed.png")
    want = book.build_book(bg, shadow=True)
    want.save(E.OUT / "generator.png")
    report("vs the generator's render (same backdrop)", got, want, E.OUT / "diff-generator.png")
    if args.ref:
        ref = Image.open(args.ref).convert("RGB")
        report("vs the design render (has text, controls, map)", got, ref, E.OUT / "diff-design.png")
