# tools/art: the chronicle's book art

These scripts draw the textures in `Art/book/`. Nothing here ships, since `.pkgmeta` and `tools/install.ps1` both leave `tools/` out. The textures they write do ship.

## Licence

Every pixel is drawn by these scripts: noise, polygons, blurs and gradients in Pillow. No screenshot, Blizzard art or outside image is read. The scripts and the textures are the addon's own work, under its MIT licence (`LICENSE`).

## Regenerate

From the repo root, with Pillow installed (`pip install pillow`):

```
python tools/art/export.py              # draw the book, write Art/book/*.tga
python tools/art/export.py --compare    # also rebuild the packing comparison in tools/out/book-art/
python tools/art/export.py --fresh      # redraw instead of using the cached tools/out/book-art/frame.png
python tools/art/compose.py --backdrop <1092x748 image> --ref <design render>
```

- **Drawing time:** the first run draws the book twice (about 20 s each) and caches the result. Later runs reuse the cache unless `--fresh` is given. The output is deterministic, because every random source is seeded.
- **Checking:** `compose.py` lays the shipped files back together the way the addon will draw them. It diffs the result against the generator's own render, which has no text, and against a design render if one is given. Results are in "Proof" below.
- **Tests:** after regenerating, run `python tools/harness/test_warpath.py ArtTextures`. It checks that each file exists, is a TGA the client can load, has power-of-two sides and stays within the size budget.

## Files

| File | What it is |
|---|---|
| `book.py` | The generator, moved from the design folder (`tools/out/design/book/refine.py` on top of `aged.py` and `tome.py`). Only the code that draws the book itself came across: the leather, the pressed rule, the gold corners, the page stack, the parchment and the burn. The mock-only parts stayed behind: text, the route map, controls pasted from a screenshot, stitches, the ribbon and the headbands. Drawn over the same screenshot, `build_book()` matches the original byte for byte. `book_rgba()` recovers the alpha channel by drawing the book over two flat greys. |
| `export.py` | Packs the art and writes `Art/book/`. `LAYOUT` is the one table of what ships and where each piece sits. With `--compare`, it also builds the other packing options for comparison. |
| `compose.py` | The proof: it rebuilds the 1092×748 design canvas from the shipped files. |

### `Art/book/` (all 32-bit RLE TGA, 2.5 MB in total)

| Texture | Size | Bytes | What it is, and how to draw it |
|---|---|---|---|
| `book.tga` | 1024×1024 | 2,383,247 | The book background, drawn at 1:1 for Joe's screen (1.2 px per UI unit). It holds the leather with its blind-tooled rule, the gold corners, the 7-leaf page stack, the parchment and the burn. The art is **1062×704 px**: the 880×580-unit frame (1056×696 px) plus 6 px on the right and 8 px at the foot, where the corner pieces' shadows fall. Anchor it at the frame's top left. It's packed as four pieces (below). |
| `book-shadow.tga` | 256×256 | 86,368 | The book's drop shadow on the scene behind it, as a 9-slice: the leather's rounded rect (radius 16), blur 12, colour (8,3,1) at 80%. Its edge is 48 px in from each side of the texture. Anchor that edge on the leather rect moved by (6, 10), 4 px taller. Cut it at 104 px. |
| `sheet-shadow.tga` | 64×64 | 5,484 | The canon's inset-sheet shadow, as a 9-slice: colour (60,30,10) at 130/255, blur 3. Its edge is 16 px in from each side. Anchor that edge on the sheet's rect moved by (2, 3). Cut it at 26 px. |
| `map-mask.tga` | 128×128 | 30,992 | The soft mask for map pictures (white means shown). It's a rounded rect inset 10 px across and 8 px down, radius 18, blur 7, as the design renders drew it. Cut it at 56 px. |

Positions in this table are in screen pixels on Joe's screen. Divide by 1.2 for UI units, which is the same conversion as `Book.X/Y`.

### How `book.tga` is packed

The art's first 1024 columns fill the sheet's top 704 rows. The last 38 columns are cut into three pieces, placed side by side in the spare rows below. Each piece is drawn as its own texture, with texcoords cropping its rect from the sheet:

| Piece | Rect in the 1062×704 art (x0, y0, x1, y1) | Top left on the sheet |
|---|---|---|
| main | 0, 0, 1024, 704 | 0, 0 |
| edge1 | 1024, 0, 1062, 235 | 2, 710 |
| edge2 | 1024, 235, 1062, 470 | 48, 710 |
| edge3 | 1024, 470, 1062, 704 | 94, 710 |

Each edge piece has a 2 px apron of its real neighbours' pixels, and the main block's last row is repeated twice below it. Bilinear filtering at a seam therefore samples the true neighbour, not an empty part of the sheet, which matters when the UI scale isn't exactly 1.2.

## Why this packing

The probe had found that a 2048×1024 sheet is too big (8.4 MB, or 6.8 MB as RLE). These are the options, measured with `export.py --compare`. Comparison crops at 100% are in `tools/out/book-art/compare-100pct.png`.

| Option | Files | TGA | RLE TGA | Pillow BLP | Error against the drawn art |
|---|---|---|---|---|---|
| **(d) one sheet at 1:1, right edge folded into the spare rows (shipped)** | 1 (4 pieces) | 4.19 MB | **2.38 MB** | 1.05 MB | exact |
| (a) two 1024 sheets, left and right halves | 2 | 8.39 MB | 2.43 MB | 2.10 MB | exact |
| (b) one 1024 sheet, shrunk to 1024 wide, stretched 3% back up in game | 1 | 4.19 MB | 2.26 MB | 1.05 MB | mean 0.6, max 54: the 1 px rules and the grain go soft |
| (c) leather border plus a tiling parchment (512 tile, quarter-size wash) | 6 | 1.80 MB* | 1.62 MB* | 0.52 MB* | the tiling shows (see below) |

\* Option (c)'s border pieces aren't packed into power-of-two sheets, so its sizes are a floor.

- **RLE costs almost nothing for empty space.** The transparent part of a sheet packs to almost nothing, so (a) and (d) come out the same size compressed. (d) needs one file instead of two.
- **(c) is out because the tiling shows.** Run on the real generator, the same cloud pattern repeats on both pages, and the seams between tiles can be seen (`tools/out/book-art/c-whole.png`). It also needs six or more textures and an untested tiling path.
- **BLP is out.** Pillow writes BLP only as a 256-colour palette, which bands the burn and the gutter shadow visibly (second row of the comparison; mean error 3.5, max 29). It can't write the DXT compression that the game's own BLPs use. Whether Forever reads a palette BLP2 from an addon is also untested.

**What the probe proved, and what it didn't:** 32-bit RLE TGA loads, because the probe's RLE sheet was 32-bit, saved by Pillow the same way as these. But that sheet's alpha was a constant 255. Varying alpha was proven only on the uncompressed disc. So these are the first RLE textures with real alpha, and the first in-game look should confirm that the leather's rounded corners and the corner shadows blend correctly.

## Proof (`compose.py`)

`compose.py` draws the drop shadow 9-slice and the four pieces over the design renders' backdrop, which is Joe's screenshot from the main checkout and isn't committed.

- **Against the generator's own render on the same backdrop:** mean difference 0.12 per channel, max 25. Only 0.04% of pixels differ by more than 8.
  - Inside the book, the difference is zero.
  - What remains is on the backdrop, around sharp details such as the old tab lettering. It comes from the generator drawing its shadow at 2× before shrinking, while the game draws at 1×.
- **Against `ref_R1_raw.png`:** the differences are only the text, the route map and the game's own pieces: tabs, title plate, close, Share and page arrows (`tools/out/book-art/diff-design.png`). The leather, corners, stack, paper and burn match.
