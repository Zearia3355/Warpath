"""Export the book art as the textures the addon ships, and compare the ways of packing it.

    python tools/art/export.py            # draw, compare, and write the shipped textures to Art/book/
    python tools/art/export.py --compare  # also rebuild the comparison in tools/out/book-art/

Run from the repo root. The shipped files are the ones `LAYOUT` names; `compose.py` and the
harness's `ArtTextures` test read the same table.
"""
import json
import os
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

sys.path.insert(0, str(Path(__file__).resolve().parent))
import book  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "Art" / "book"
OUT = ROOT / "tools" / "out" / "book-art"
FW, FH = book.ART[2] - book.ART[0], book.ART[3] - book.ART[1]     # 1062 x 704

# ------------------------------------------------------------------ the shipped layout
# One 1024x1024 sheet at 1:1. The art (1062x704: the 1056x696 frame plus 6 px right and 8 px below
# for the corners' shadows) fills the sheet's top 704 rows with its first 1024 columns; the last
# 38 columns are cut into three pieces stacked side by side in the spare rows below. Each piece
# carries a 2 px apron of its neighbours' pixels, so bilinear filtering at a seam samples the
# real neighbour, never another piece. `src` is the piece's rect in the 1062x704 art and
# `at` is where that rect sits on the sheet (the apron is around it).
APRON = 2
STRIP_X = 1024
PIECES = [dict(name="main", src=(0, 0, 1024, 704), at=(0, 0))]
for i, (y0, y1) in enumerate(((0, 235), (235, 470), (470, 704))):
    PIECES.append(dict(name="edge%d" % (i + 1), src=(STRIP_X, y0, FW, y1),
                       at=(APRON + i * (FW - STRIP_X + 2 * APRON + 4), 708 + APRON)))

LAYOUT = {
    "book.tga": dict(size=(1024, 1024), what="the book background: leather, rule, corners, page stack, "
                     "parchment and burn, 1062x704 px at 1:1 (the 880x580 frame at 1.2 px per unit, "
                     "plus 6 px right and 8 px below for the corners' shadows)",
                     pieces=PIECES),
    # 9-slices: `rect` is the shape's own edge, `margin` px in from each side of the texture (anchor it on
    # the box that casts the shadow); `slice` is where to cut the texture (corners slice x slice).
    "book-shadow.tga": dict(size=(256, 256), margin=48, slice=104,
                            what="the book's drop shadow: the leather's rounded rect (radius 16) offset 6,10 "
                                 "and 4 px taller, blur 12, colour (8,3,1) at 80%"),
    "sheet-shadow.tga": dict(size=(64, 64), margin=16, slice=26,
                             what="the inset sheet's soft shadow: the sheet's rect offset 2,3, colour (60,30,10) "
                                  "at 130/255, blur 3"),
    "map-mask.tga": dict(size=(128, 128), slice=56,
                         what="the map pictures' soft mask: a rounded rect inset 10 px across and 8 down, radius 18, "
                              "blur 7; white = shown"),
}
BUDGET = 4 * 1024 * 1024          # all of Art/book together


# ------------------------------------------------------------------ the frame, drawn once
def frame_rgba(fresh=False):
    cache = OUT / "frame.png"
    if cache.exists() and not fresh:
        return Image.open(cache).convert("RGBA")
    full = book.book_rgba(shadow=False)
    alpha = full.getchannel("A")
    inside = Image.new("L", full.size, 0)
    ImageDraw.Draw(inside).rectangle((book.ART[0], book.ART[1], book.ART[2] - 1, book.ART[3] - 1), fill=255)
    spill = ImageChops.multiply(alpha, ImageChops.invert(inside)).point(lambda v: 255 if v > 2 else 0).getbbox()
    assert not spill, "art outside book.ART: %s" % (spill,)
    fr = full.crop(book.ART)
    OUT.mkdir(parents=True, exist_ok=True)
    fr.save(cache)
    return fr


# ------------------------------------------------------------------ packing
def with_apron(frame, src, apron):
    """`src` cut from the frame with `apron` px of real neighbours, edge pixels repeated at the frame's edge."""
    x0, y0, x1, y1 = src
    w, h = x1 - x0 + 2 * apron, y1 - y0 + 2 * apron
    out = Image.new("RGBA", (w, h))
    px, po = frame.load(), out.load()
    for y in range(h):
        sy = min(FH - 1, max(0, y0 - apron + y))
        for x in range(w):
            po[x, y] = px[min(FW - 1, max(0, x0 - apron + x)), sy]
    return out


def pack_sheet(frame, pieces, size):
    sheet = Image.new("RGBA", size, (0, 0, 0, 0))
    for p in pieces:
        if p["name"] == "main":
            x0, y0, x1, y1 = p["src"]
            sheet.paste(frame.crop(p["src"]), p["at"])
            # repeat the main block's last row below it, so filtering never reads the empty gap
            sheet.paste(frame.crop((x0, y1 - 1, x1, y1)).resize((x1 - x0, 2)), (p["at"][0], p["at"][1] + y1 - y0))
        else:
            sheet.paste(with_apron(frame, p["src"], APRON), (p["at"][0] - APRON, p["at"][1] - APRON))
    return sheet


def unpack_sheet(sheet, pieces):
    """What the game draws: each piece's rect of the sheet placed at its rect in the frame."""
    fr = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
    for p in pieces:
        x0, y0, x1, y1 = p["src"]
        ax, ay = p["at"]
        fr.paste(sheet.crop((ax, ay, ax + x1 - x0, ay + y1 - y0)), (x0, y0))
    return fr


def option_d(frame):
    """One 1024 sheet, 1:1, the right-edge strip folded into the spare rows (shipped)."""
    sheet = pack_sheet(frame, PIECES, (1024, 1024))
    return {"book.tga": sheet}, unpack_sheet(sheet, PIECES)


def option_a(frame):
    """Two 1024 sheets, the left and right halves, each cropped by texcoords (2 px overlap at the gutter)."""
    half = FW // 2
    L = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)); L.paste(frame.crop((0, 0, half + 2, FH)), (0, 0))
    R = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)); R.paste(frame.crop((half - 2, 0, FW, FH)), (0, 0))
    back = Image.new("RGBA", (FW, FH))
    back.paste(L.crop((0, 0, half, FH)), (0, 0))
    back.paste(R.crop((2, 0, 2 + FW - half, FH)), (half, 0))
    return {"book-left.tga": L, "book-right.tga": R}, back


def option_b(frame):
    """One 1024 sheet with the frame shrunk to 1024 wide, stretched back up 3% in game."""
    k = 1024 / FW
    w, h = 1024, round(FH * k)
    sheet = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sheet.paste(frame.resize((w, h), Image.LANCZOS), (0, 0))
    back = sheet.crop((0, 0, w, h)).resize((FW, FH), Image.BILINEAR)     # the GPU's filter
    return {"book-scaled.tga": sheet}, back


def seamless(tile):
    """Cross-fade a square with itself rolled by half, so it tiles without a seam."""
    w, h = tile.size
    rolled = ImageChops.offset(tile, w // 2, h // 2)
    m = Image.new("L", (w, h))
    m.putdata([int(255 * min(1.0, 2.2 * min(x, w - 1 - x, y, h - 1 - y) / (w / 2)))
               for y in range(h) for x in range(w)])
    return Image.composite(tile, rolled, m)


def option_c(frame):
    """A leather-and-edges frame plus a tiling parchment. Drawn by re-running the book with every
    piece of paper cut from one seamless 512 px tile, so the look (repeats) can be judged; the
    files are the border band, the tile and a quarter-size wash for the burn and the gutter."""
    T = 512 * book.S
    tile = seamless(book.parchment(T, T, book.PAPER, book.SEED + 900))
    orig = book.parchment

    def tiled(w, h, base, seed):
        out = Image.new("RGB", (w, h))
        for y in range(0, h, T):
            for x in range(0, w, T):
                out.paste(tile, (x, y))
        return out
    book.parchment = tiled
    try:
        lo, hi = 64, 192
        full = book.unmatte(book.build_book((lo,) * 3, False), book.build_book((hi,) * 3, False), lo, hi)
    finally:
        book.parchment = orig
    back = full.crop(book.ART)
    # what would ship: the band outside the parchment's inner box, the tile, and the wash
    ix0, iy0, ix1, iy1 = 62, 54, FW - 62, FH - 54
    band = {"c-top.tga": back.crop((0, 0, FW, iy0)), "c-bottom.tga": back.crop((0, iy1, FW, FH)),
            "c-left.tga": back.crop((0, iy0, ix0, iy1)), "c-right.tga": back.crop((ix1, iy0, FW, iy1))}
    files = dict(band)
    files["c-paper.tga"] = tile.resize((512, 512), Image.LANCZOS).convert("RGB")
    files["c-wash.tga"] = back.crop((ix0, iy0, ix1, iy1)).resize((256, 256), Image.BOX)
    return files, back


# ------------------------------------------------------------------ files and checks
def save_all(files, folder):
    """Each file as TGA, RLE TGA and Pillow's BLP; returns {format: total bytes} and BLP readbacks."""
    folder.mkdir(parents=True, exist_ok=True)
    sizes = {"tga": 0, "tga_rle": 0, "blp": 0}
    blp_back = {}
    for name, im in files.items():
        stem = name[:-4]
        p = folder / (stem + ".tga"); im.save(p); sizes["tga"] += p.stat().st_size
        p = folder / (stem + "-rle.tga"); im.save(p, compression="tga_rle"); sizes["tga_rle"] += p.stat().st_size
        p = folder / (stem + ".blp")
        try:
            q = im.convert("RGBA").quantize(256, method=Image.Quantize.FASTOCTREE)
            q.save(p, blp_version="blp2")
            sizes["blp"] += p.stat().st_size
            blp_back[name] = Image.open(p).convert("RGBA")
        except Exception as e:      # noqa: BLE001
            sizes["blp"] = "failed: %s" % e
    return sizes, blp_back


def flat(im, bg=(40, 30, 24)):
    base = Image.new("RGBA", im.size, bg + (255,))
    return Image.alpha_composite(base, im.convert("RGBA")).convert("RGB")


def diff_stats(a, b):
    d = ImageChops.difference(flat(a), flat(b))
    st = ImageStat.Stat(d)
    mx = max(hi for lo, hi in d.getextrema())
    return sum(st.mean) / 3, mx


CROPS = [("top-left corner", (0, 0, 260, 170)), ("gutter, head", (400, 0, 660, 170)),
         ("right edge, the folded strip", (886, 150, 1062, 320)), ("bottom-right corner", (802, 534, 1062, 704)),
         ("page", (180, 260, 440, 430))]


def comparison(frame, backs, path):
    """Rows: the reference, then each option as the game would draw it; columns: crops at 100%."""
    rows = [("reference (the frame as drawn)", frame)] + backs
    lab = 18
    cw = sum(c[1][2] - c[1][0] for c in CROPS) + 8 * (len(CROPS) - 1)
    ch = max(c[1][3] - c[1][1] for c in CROPS)
    sheet = Image.new("RGB", (cw, len(rows) * (ch + lab + 8)), (24, 20, 16))
    d = ImageDraw.Draw(sheet)
    y = 0
    for name, im in rows:
        d.text((4, y + 3), name, fill=(230, 210, 170))
        x = 0
        for _, box in CROPS:
            sheet.paste(flat(im.crop(box)), (x, y + lab))
            x += box[2] - box[0] + 8
        y += ch + lab + 8
    sheet.save(path)


# ------------------------------------------------------------------ small pieces
def nine_slice_shadow(size, margin, blur, colour, strength):
    """A soft shadow for a rectangle that fills the texture minus `margin`, ready to 9-slice."""
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rectangle((margin, margin, size - 1 - margin, size - 1 - margin), fill=strength)
    m = m.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", (size, size), colour + (0,))
    out.putalpha(m)
    return out


def book_shadow():
    """The book's drop shadow: the leather's rounded rect, blur 12, colour (8,3,1), 80%. Anchor the
    shape's edge (`margin` px in from each side) on the cover rect moved by DROP's offset and grow."""
    size, margin, r = 256, LAYOUT["book-shadow.tga"]["margin"], book.DROP["radius"]
    m = Image.new("L", (size * 2, size * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle((margin * 2, margin * 2, (size - margin) * 2 - 1, (size - margin) * 2 - 1),
                                        r * 2, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(book.DROP["blur"] * 2)).resize((size, size), Image.LANCZOS)
    m = m.point(lambda v: int(v * book.DROP["alpha"]))
    out = Image.new("RGBA", (size, size), book.DROP["colour"] + (0,))
    out.putalpha(m)
    return out


def map_mask():
    """The canon's soft rounded mask: inset 10 px across and 8 down, radius 18, blur 7 (as the design
    renders made it). White = shown. It's 128 px square, so a picture of any size uses it as a 9-slice
    or as four corner quarters; stretched whole, the corners would stretch with it."""
    size = 128
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((10, 8, size - 10, size - 8), 18, fill=255)
    m = m.filter(ImageFilter.GaussianBlur(7))
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(m)
    return out


def write_shipped(frame):
    ART.mkdir(parents=True, exist_ok=True)
    files = {"book.tga": option_d(frame)[0]["book.tga"], "book-shadow.tga": book_shadow(),
             "sheet-shadow.tga": nine_slice_shadow(64, LAYOUT["sheet-shadow.tga"]["margin"], 3, (60, 30, 10), 130), "map-mask.tga": map_mask()}
    for name, im in files.items():
        assert im.size == LAYOUT[name]["size"], name
        im.save(ART / name, compression="tga_rle")
    total = sum((ART / n).stat().st_size for n in files)
    for n in files:
        print("  Art/book/%-18s %9d bytes" % (n, (ART / n).stat().st_size))
    print("  total %d bytes (budget %d)" % (total, BUDGET))
    assert total <= BUDGET


def compare(frame):
    results = []
    backs = []
    for key, fn in (("a", option_a), ("b", option_b), ("c", option_c), ("d", option_d)):
        print("option", key, "...")
        files, back = fn(frame)
        sizes, blp = save_all(files, OUT / key)
        mean, mx = diff_stats(frame, back)
        dims = {n: im.size for n, im in files.items()}
        pow2 = all((w & (w - 1)) == 0 and (h & (h - 1)) == 0 for w, h in dims.values())
        blp_err = None
        if key == "d" and "book.tga" in blp:
            bm, bx = diff_stats(frame, unpack_sheet(blp["book.tga"], PIECES))
            blp_err = (round(bm, 2), bx)
            backs.append(("d as Pillow BLP (256-colour palette)", unpack_sheet(blp["book.tga"], PIECES)))
        results.append(dict(option=key, doc=fn.__doc__.split("\n")[0], files=len(files), dims=dims, pow2=pow2,
                            bytes=sizes, mean_err=round(mean, 2), max_err=mx, blp_err=blp_err))
        backs.append(("option " + key + ": " + fn.__doc__.split("\n")[0], back))
        print(json.dumps(results[-1], default=str))
    backs.sort(key=lambda b: b[0])
    comparison(frame, backs, OUT / "compare-100pct.png")
    (OUT / "compare.json").write_text(json.dumps(results, indent=1, default=str))


if __name__ == "__main__":
    fr = frame_rgba(fresh="--fresh" in sys.argv)
    if "--compare" in sys.argv:
        compare(fr)
    write_shipped(fr)
