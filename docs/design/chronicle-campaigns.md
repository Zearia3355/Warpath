# Chronicle design: the Campaigns tab

The Campaigns page, the page the canon (`chronicle.md`) was drawn from. Its design was settled with Joe on 2026-11-27 ("Settled", "The book is done", and V5 for the deeds); until now it was recorded only in the ignored design folder. This file writes it down in the form of the other page specs, with every position measured from the generator code, not by eye.

**Status: settled design, spec written 2026-11-28 for phase 2.** The positions are the generators'. Where the design was hand-placed for one campaign and the page must work for every campaign, the rule chosen is marked **Claude's call**.

## Sources

All under `tools/out/design/` (ignored), read by absolute path from the main checkout.

- **Renders:** `type/ov_V5a.png` (every zone open, at the top), `type/ov_V5b.png` (Winterspring folded, scrolled to the end), `_ingame` versions at 1.175×; `ov_V5_right.png` (both right pages). The `_raw` left page is `type/type_T5_raw.png`.
- **Generators:** `type/combo.py` (V5: the sheet, folding zones, scroll), on `type/type.py` (`content`: date, title, drop cap, prose, map, footer), `type/mix.py` (T5: T1's left page and headings with T2's right page), `type/honour.py` (S3b rows, tiles, band, diamond), `type/overflow.py` (the 21-kill night `LONG`, `rows_at`, `reckoning`, `footer`), `type/explore.py` (`TOP`, `BOT`, `base`), `type/round3.py`. The book's own pieces: `book/refine.py` (`ink_map`, `place_picture`), `book/mock3.py` (columns, colours), `book/mock4.py` (`ornament`).
- **Notes:** `type/type-final.md` (settled), `type/type-directions.md` (every round, with Joe's picks), `book/book-final.md`.
- **Joe's picks:** T1's left page and titles with T2's right page (T5); N2 names; S3b honours; V5 (V2's pasted sheet without the stack under it, V4's folding zones all open by default, V1's scroll inside); a crimson scroll bar; route map R1; one spread per campaign ("The 2-page limitation really just applied to the campaign tab"); no shrinking.

## Units

The canon's. Positions are **render px** on the 1092×748 design canvas, 1.2 px a game unit:

- Left page: game x = (render x − 42.1) / 1.2. Right page: game x = (render x − 548.1) / 1.2.
- Both pages: game y = (render y − 62) / 1.2, down from the page's top.

Text columns (`mock3.py`): left page L0 = 82 to LR = 510, centre CX = 296; right page R0 = 586 to RR = 1017, centre RCX = 801.

Every y is a **text baseline** unless it says "top". "Right at x" means right-aligned with its right edge at x. Sizes are render px (divide by 1.2 for the game's font size).

## Colours

- Ink (46,28,10); Faded (77,56,31); Rubric (122,31,15); Rubric shadow (70,12,6), offset 1 px right and down; Level (106,80,48).
- Gilt diamond (176,128,52), edged (70,40,8) one px wider all round.
- Names, N2: class colour taken halfway from the parchment-inked tone toward the game's colour, black 1 px shadow. The inked tone scales the game colour down so its luminance is at most 0.28 (`mock3.ink`). Unknown class: ink, no shadow.
- Map ink: road and crosses (150,26,14); labels and the flag's pole (70,40,14).

## Faces

| Key | Face | Notes |
|---|---|---|
| Friz | `Fonts\FRIZQT__.TTF` | body, labels, nav |
| Morpheus | `Fonts\MORPHEUS.TTF` | titles, headings, the drop cap, raised tags |
| Narrow | `Fonts\ARIALN.TTF` | times, footer controls |
| Garamond Italic | `Interface\AddOns\Warpath\Fonts\EBGaramond-Italic.ttf` | zones, tags, folios |
| Garamond Bold | `Interface\AddOns\Warpath\Fonts\EBGaramond-Bold.ttf` | Reckoning values |

**Small caps** (`type.py` `smallcaps`): each letter its own string, upper case; a capital at the full size, a lower-case letter as its capital at `int(size × ratio)` (ratio 0.78; 0.74 for the raised tags), each followed by 0.6 px. **Letterspaced capitals** (the date): each letter its own string, followed by its width plus 1.2 px. **Faux bold:** the string drawn again 1 px right.

## The spread

Tabs (five, 92 units each, `ledger/lbase.py` `TABS_A`), Campaigns raised: Campaigns x 65–175, Grudges 183–293, Ledger 301–411, Settings 813–923, Warpath 931–1041. Each: a dark edge (56,16,5) 1 px outside a gold rim (190,154,100); inside, 3 px in, (45,25,9) when chosen (with a (82,61,23) line along its top) or (21,15,10). Top at y 12 when chosen, 20 otherwise, foot at 45. Label Friz 16, centred, baseline top + 21 (chosen) or + 17, gold (255,209,0) when chosen, else (196,196,196), black shadow 1 px. The title plate, close button, Share button and page-turn arrows are the game's, where Joe's screenshot has them.

### Left page: the chronicle

| Element | Face, size, colour | Position (render px) |
|---|---|---|
| Date line: "WEDNESDAY, NOVEMBER 25 · A SKIRMISH" (two spaces either side of the dot) | Friz 12, letterspaced capitals (+1.2 px), faded | centred on CX, y 107 |
| Date rules | 1 px, rubric at 55% | 40 px long, 12 px from the text each side, y 103 |
| Title, two lines: "From Searing Gorge" / "to Dustwallow Marsh" (`Chronicler.Write().title`; one line when the title has one) | Morpheus small caps 31 (lower case 24), rubric, rubric shadow | centred on CX, y 150 and 185 |
| Ornament | rules: 1 px rubric at 55% (y −1) and 30% (y +2), from 16 to 120 px either side of centre; diamonds: rubric, radius 5 at the centre, radius 2 at ±11 | centred on CX, y 202 (the last title line + 17) |
| Prose | Friz 18, ink, 22 px leading, wrapped by hand to the column L0–LR (428 px), one string per line and per name | first baseline y 242 (ornament + 40) |
| Drop cap | the prose's first letter, Morpheus, rubric, rubric shadow, sized so its ink is two leadings plus the body's cap height tall (55 px in the stand-ins: Palatino 80) | baseline on the third line (y 286), left edge x 81 |
| Tuck | lines 1–2 start at the letter's stem + 5 (x 115 for "L"), line 3 clears its foot + 6 (x 136) | |
| Names in the prose (N2) | Friz 18, N2 colour, black shadow; punctuation after a name is ink | in the line, hover: GameTooltip |
| Route map | 372 × 180, the world map's art printed in sepia (below), a soft rounded mask | left x 110 (centred on CX), top y = max(478, the line after the prose + 2): 486 for the reference campaign's eleven lines |

The prose's words are measured with `GetStringWidth` and broken where the next word would pass the column's right edge less the line's indent (`type.py` `rich_wrap`).

### The route map (R1, `refine.py` `ink_map`, `place_picture`)

- **Art:** `C_Map.GetMapArtLayerTextures(947, 1)` (12 tiles of 256 px, layer 1002 × 668), each tile a texture cropped by texcoords to the window x 58.2–855.2, y 144.9–530.7 of the layer (the design's crop of Joe's world map, 300–1560 × 290–900 of `world.png`, whose canvas is 208–1792 × 61–1117), scaled to 372 × 180.
- **Print:** desaturated, then MOD blend with a vertex colour, then an ADD layer of a flat colour under the same mask: page × (a + b·grey) per channel, the straight line closest to the design's sepia ramp (land to bare paper, darks to (110…255) tinted by (0.62, 0.86, 1.0)). Fitted values are in the code.
- **Mask:** `Art/book/map-mask.tga` over the whole picture (rounded rect inset 14/12, radius 26, blur 10 in the design).
- **Zones:** the campaign's zones in the order first fought in (kills and deaths; zones with neither are skipped), each at the centre of `C_Map.GetMapRectOnMap(zone, 947)`. A zone with no rect on 947 is placed through its continent (zone on 1414/1415, continent on 947); one with neither is left off.
- **Road:** a dashed red line between consecutive zones, each leg a quadratic curve bowed by −10% (odd legs +12%) of its length to the left of travel, cut into 20 dashes (2 of every 4 steps of 80), 2.2 px wide.
- **Cross** where something fell: two 2.6 px strokes, ±6 px. **"×N"** when N > 1: Friz 13, map red, its top-left at (+9, −8) from the zone.
- **Start ring:** radius 11, 1.6 px, map red, round the first zone. **End flag:** a 1.6 px pole 26 px up from the last zone in (70,40,14), a red pennant from the top, 14 px out and 10 px tall.
- **Labels:** the zone's name, Friz 15, (70,40,14). The design hand-placed four (Searing Gorge up-left, Desolace below, Winterspring up-right, Dustwallow Marsh right). **Claude's call:** for every campaign, each label takes the first of these that stays 14 px inside the picture and clears the road, marks, flag and earlier labels: right (+14, +18 baseline), below (centred, +22), up-right (+12, −4), up-left (right-aligned −14, −16), left (right-aligned −14, +18). Where this differs from the hand placement on the reference campaign it's listed in the build report.

### Right page: Deeds and Losses, The Reckoning

| Element | Face, size, colour | Position (render px) |
|---|---|---|
| Heading "Deeds and Losses" | Morpheus small caps 25, rubric, shadow; ornament half-width 110 | centred on x 802, y 120; ornament y 133 |
| Share | the game's red button, as in Joe's screenshot | x 938–1023, top y 95 |
| Inset sheet | parchment blended 30% toward (240,208,146); shadow (60,30,10) at 51% offset (2,3), blurred 3 (`Art/book/sheet-shadow.tga`); 1 px edge (130,84,40); no stack under it; four paste marks, 7 px rules of (150,100,40) at 25% | x 576–1025, y 142–420 (top) |
| Window | the rows scroll inside it | x 578–1023, y 146–416 |
| Row fades | 16 px at an edge, **only while more lies beyond that edge** (the design always faded the foot; with nothing below there's nothing to fade, so it looks the same) | |
| Content column | x0 = 584, x1 = 1005 | first zone line y 162 when unscrolled |
| Zone line | see below | baseline y |
| Rows | 27 px apart, the first 22 below its zone line; 4 px more after a zone's last row; a folded zone's next line is 26 below it | |
| Scroll bar | cord: 1 px of (110,30,18) at 40%, x 1016, y 152–410. Thumb: rounded, x 1013–1020, at least 22 tall, its length the window's share of the content of 258; edge (46,6,4), fill (146,24,14) 1 px in, a lit line (206,72,48) at x 1015 from 3 px below its top to 4 above its foot. **Only while the content overflows** (Claude's call, from the plan's tests; the design always drew it) | |
| Heading "The Reckoning" | Morpheus small caps 23, rubric, shadow; ornament half-width 100 | centred on RCX, y 448; ornament y 461 |
| Reckoning rows | label Friz 18, ink; leader 1 px ink at 38% from 10 px after the label to 10 px before the value, at y − 1; value EB Garamond Bold 21, rubric, faux bold | labels x 616; values right at x 987 (986 + the 1 px bold); y 488, 514, 540, 566, 592, 618 |

**Zone line** (`combo.py` `zones`), baseline y:

- Chevron, rubric: open, a triangle pointing down (584, y−8), (592, y−8), (588, y−2); folded, pointing right (586, y−10), (592, y−6), (586, y−2). Clicking the line folds or opens the zone.
- Zone name: EB Garamond Italic 17, faded, x 598.
- Tally: EB Garamond Italic 15, faded, right at x 1005. "N slain"; **Claude's call** for deaths, which the design never showed: "N slain, M fell", or "M fell" with no kills.
- Honour diamonds: one gilt diamond (radius 3) per honour row in the zone, right to left from 10 px before the tally, 11 px apart, centred 5 px above the baseline (the first at the tally's left − 13).
- Rule: 1 px faded at 30%, from 8 px after the zone name to the tally's left − 14 − 11 × (number of diamonds), y − 4.

**Row** (S3b, `honour.py` `make_row("b")`), baseline y:

| Part | Look | Position |
|---|---|---|
| Gilt band (honour rows) | (222,150,44) at 63% (160/255); across, in over the first 6% and out from 55% to the end, to the power 1.4; top and bottom soften over 4 px except where it joins a neighbouring honour row (the top then starts 1 px higher) | x 578–1009, y−20 to y+7 |
| Tile, ordinary | 22 px: a dark edge (60,30,10) 1 px outside a gold rim (176,128,52), red ground (110,16,10) 2 px in, the class icon over the inner 18 px | x 586, top y−17 |
| Tile, honour | bevelled gold: dark edge (52,28,6) 4 px out; a 3 px frame lit (246,206,112) top and left, (150,98,30) bottom and right; ground (70,40,8); the class icon over the inner 20 px | same box |
| Class icon | `Interface\Icons\ClassIcon_<CLASS>` (Claude's call after the probe). Unknown class: no icon, a "?" in Morpheus 15, gilt, centred | |
| Time | Arial Narrow 15, faded, "17:35" | x 616 |
| Name | Friz 18, N2, black shadow: the foe's first name (`Chronicler`'s `NameRun.text`) | x 658 |
| Level | Friz 15, Level; "??" for −1; none if unknown | 6 px after the name |
| Tag, raised part | Morpheus small caps 16 (lower case 11, ratio 0.74), rubric, shadow; led by a gilt diamond (radius 3) 9 px before it, centred 5 px above the baseline | right at x 1005 |
| Tag, plain part | EB Garamond Italic 17, faded; right at 10 px before the diamond (19 px before the raised part), or at x 1005 when nothing is raised | |

**What a deed's tag says** (from the kill's saved fields; today's `DeedText`):

| Saved | Words | Raised? |
|---|---|---|
| `tag == "first"` | first blood | no |
| `tag == "streak"` and `st` | streak of N | yes |
| `tag == "grudge"` | grudge | yes |
| `tag == "avenged"` | revenge (the design's word; today's is "avenged") | yes |
| `mk >= 2` | double kill, triple kill, quad kill, bloodbath of N (`Campaign.Burst`) | yes |
| a feat `ft` (not the grudge or avenged one again) | the feat's name, lower case ("payback", "outnumbered") | yes |

A row with anything raised is an **honour**: gold tile, band, a diamond on its zone line. The raised parts join with ", "; plain parts likewise. **Claude's call:** feats count as raised, being rare by design; "revenge" replaces "avenged" as the design has it.

**Deaths** (Claude's call; the design's night had none): a death row has a dark tile (edge (60,30,10), rim faded (77,56,31), ground ink (46,28,10)) with the killer's class icon at 60%, or the skull when the killer is unknown; the killer's name in N2 (or "someone unseen" in Garamond Italic 17, faded); the tag "fell" in Garamond Italic 17, rubric. Never raised.

**Rows** hover: the GameTooltip as today (name in class colour, who, screenshot number, "Click to set a waypoint here"); click sets the waypoint. Not in preview.

### Footer

| Element | Face, size, colour | Position (render px) |
|---|---|---|
| Earlier arrow | the game's page-turn button (as today: 28 units, its art at x 74–101, y 676–702) | |
| "Earlier" | Friz 18, ink | x 106, y 692 |
| Left folio "— vii —" | EB Garamond Italic 17, faded | x 200, y 694 |
| "campaign 4 of 5" | Arial Narrow 15, faded | 14 px after the folio, y 694 |
| Quiet box | 14 × 14 px, fill (26,18,10), 1 px edge (168,132,64); a gold check when on | 16 px after "campaign…", top y 682 |
| "show 4 quiet" | Arial Narrow 15, ink | 20 px after the box's left, y 694 |
| Right folio "— viii —" | EB Garamond Italic 17, faded | centred on x 801, y 694 |
| "Later" | Friz 18, ink | right at x 990, y 692 |
| Later arrow | the game's button, art at x 995–1022, y 676–702 | |

Folios: the left page is the campaign's number × 2 − 1 in lower-case Roman numerals, the right × 2, the number counting from the oldest kept (as today).

## States

- **Open campaign:** as above; the date line's tag is the campaign's scale ("a skirmish"); an open campaign adds " · in progress" after it (Claude's call: today's status words kept, in the same letterspaced capitals).
- **Before 3.4 (`camp.old`):** totals only; the sheet says "Kills and deaths weren't listed before 3.4." in Garamond Italic 17, faded, centred at y 190.
- **Nothing yet:** the sheet says "No blood spilled yet."
- **Preview** (`/warpath chronicle preview`): `Campaign.Sample()`, " · sample pages" after the date, Share disabled, no tooltips or waypoints, the quiet filter not applied.
- **Folded zone:** its rows hidden, its line 26 px tall. Fold state belongs to the open page and resets when you turn to another campaign (Claude's call). All open by default (Joe).
- **Scrolled:** mouse wheel over the sheet, or drag the thumb; 27 px a notch (one row; Claude's call). The scroll resets to the top when you turn the page.

## Behaviour

- **One spread per campaign** (Joe). Deeds scroll inside the sheet; nothing ever pages.
- **The quiet filter** (`docs/backlog.md`, "Filter chronicle campaigns by activity"): a quiet campaign is a patrol or a clash (`Chronicler.Write().quiet`). By default they're hidden: Earlier and Later step over them, and "campaign N of M" counts only those shown. The box beside "show N quiet" (N = how many are hidden) shows them all. The newest campaign always shows, so the book never opens on nothing. Remembered per account (`WarpathGlobal.cfg`-level, key `chronQuiet`; **Claude's call**, new key, nothing removed). Hidden when there are no quiet campaigns. Joe's open questions (threshold; whether the 30 kept counts only shown ones) stay open: this build hides patrols and clashes and keeps the 30 as today.
- **Names** use Forever's First Last (`ns.DisplayName`) in tooltips; the prose and rows show the first name, as the design does.
- **Name tooltip** (prose and rows): the display name in class colour; "Level 55 Warrior" (with race and guild when known; "Level ??"); "Slain twice this campaign" / "Slew <you> once"; "Grudge held" when the foe is in the grudge ledger.
- **Reckoning rows:** "<Foe faction> slain" (kills), "<you> fell" (deaths, "none" for 0), "Best streak" (`c.best`, "none" for 0), "Miles ridden" (one decimal), "In the field" (`Campaign.Duration`), "Screenshots" ("#11–#31", "#12" for one, "none").

## Fonts load late on this client

The probe found `SetFont` returning false for EB Garamond and `GetStringWidth` measuring the old face, though the text later drew in Garamond. So: both Garamond faces are set on hidden strings when the addon loads, and every measured layout (the prose's wrap and drop cap, the zone line's rule, the Reckoning's leaders, the footer's run) is laid out again on the next frames after the book first opens, until two layouts in a row measure the same. See the build report for how Joe checks it.

## Tests

- **Geometry:** the spec's positions are a table in `ChronCampaigns.lua` (`ns.ChronCampaigns.GEOMETRY`); a test builds the page for the reference campaign and checks that each named element lands within 1 unit of its row.
- **Sheet:** fixed size whatever the campaign; scroll range = content − window; bar only when overflowing; the top fade only once scrolled, the foot fade only while more lies below; the wheel scrolls one row.
- **Folding:** folding a zone hides its rows and closes the gap; the zone line shows its tally and diamonds either way.
- **Quiet filter:** quiet campaigns skipped by Earlier/Later, counted in "show N quiet", the newest always shown; the box shows them; the setting persists.
- **Display names and words:** First Last in tooltips; tags as the table above.
- **Every campaign of every real character** opens, renders and turns without a Lua error (`RealData`).

## Claude's calls

1. Small caps and letterspaced capitals as one string per letter, mirroring the generator exactly (it sets each letter alone with fixed tracking, no kerning).
2. Map labels by rule, not hand placement (above).
3. Map print as MOD plus an ADD layer (page × (a + b·grey)), the closest linear fit to the design's sepia ramp, because MOD alone can only darken.
4. Death rows, the "M fell" tally, and "revenge" for avenged; feats raised.
5. Row fades and the bar only where there's more to see.
6. Fold state per page; one row per wheel notch.
7. The quiet filter's key, threshold (patrol and clash) and the newest-always rule.
8. Class icons `ClassIcon_<CLASS>`; "?" for unknown.
9. The Ledger tab's page, until its phase, says in the left page's centre "The Ledger is being written." in Garamond Italic, faded, and nothing else.
10. The prose is one string per word piece, each placed at the measured width of the words before it plus a space's, as the generator sets it (merged strings drifted up to 4 px at line ends against the design).
11. The map print's flat ADD term is the fit plus 5% of the page, matched to the design render through the harness (sea and land within 4 levels of the design).
12. The sheet's shadow is cut out from under the sheet (the design pastes the paper over the unshadowed page; with the shadow under a 30% sheet the paper read grey).
13. One origin for both pages, the book's top-left at (20.5, 40.4): the canon's right-page origin (548.1) is 0.4 px left of where the book's page frame actually starts (548.5 = 20.5 + 440 × 1.2); converting every position from the book's own origin removes the difference.
14. Map labels by rule: on the reference campaign only Winterspring's lands elsewhere than the hand placement (right of its cross, 22 px lower than the design's up-right).

## Built (phase 2, 2026-11-28)

`ChronCampaigns.lua` builds this page on `Book.lua`'s kit; `GEOMETRY` is this file's numbers. Side-by-side renders and the list of remaining differences are in the build report.
