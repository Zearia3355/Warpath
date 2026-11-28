# Chronicle: the Warpath tab

Settled with Joe on 2026-11-27 ("Settled, write spec"). It follows the canon in `chronicle.md`, which still governs everything this file doesn't say. Nothing here is built yet.

This is the chronicle's front page. After every install or update the book opens here by itself, so it's the first page players see. The left page welcomes the player and teaches the map's marks. The right page is What's New, every release's `NEW_IN` notes, newest first.

## Renders and generators

Everything is under `tools/out/design/warpath/`, which git ignores. Run the scripts from that folder.

**Final renders:** `_ingame` is 1.175×, the in-game size, and `_raw` has no label.
- `r3_Y1_first.png`, `r3_Y1_first_ingame.png`, `r3_Y1_first_raw.png`: a first install.
- `r3_Y1_update*.png`: an update from 3.8.2 to 3.8.4.
- `r3_Y1_settled*.png`: the tab opened later, with nothing new.
- `r3_Y1_factions_ingame.png`: the key's faction rows for a Horde and an Alliance character.

**Generators:**
- `r3.py` draws the final design (`python r3.py`).
- `wp.py` draws the round-1 directions W1, W2 and W3, plus the right page, which is W3's.
- `wbase.py` holds the shared pieces. It imports `type/` and `book/` and forks no art.
- `r2.py` is round 2.
- The text comes from the real `NEW_IN` in `Options.lua`, read at render time.

**Icons in `icons/` are stand-ins and never ship.** The skull, both crests and the map button were cut from Joe's own screenshots. The kill sword was redrawn by eye. In game every one of them is the client's own texture (see "What it needs in game").

**History:** `warpath-directions.md`. Round 1 was W1 (every release open), W2 (folded releases) and W3 (the plate, plus a "read before" line). Round 2 was X1 (plate) and X2 (plain). Round 3 was Y1, the map key, refined twice.

## Joe's picks, in his words

- "I like the right page of W3".
- "I prefer the explicit checkbox with the yellow checkmark over the seal".
- "Scrolling for whats new for sure". This replaces his earlier pick C's "1 of N" paging; he was asked explicitly.
- On "Finding Your Way": "make it useful or … replace it with something useful on a welcome screen". On the map image: "I don't think we need to label the image as a figure".
- "LOVE the new inked image and map key. The your roads part of the key should have a (builds over days) added."
- "We can stop adding the 'never your trail' message at the end of the guild sharing option description."
- "The welcome back message can still include 'you just updated from x.x.x', made obvious in the paragraph".
- The key's icons must be the map's own: "Our own skulls aren't red"; the enemy crest "should also detect if you are horde or ally"; "world map icon in key is too small"; haze "exaggerate a little so its obvious – this is a teaching image".

## Geometry

Positions are in render pixels on the 1092 × 748 book, the same frame as the Campaigns renders. To get UI units, use the canon's conversion (settled 2026-11-27 by measuring the book art; the earlier "× 0.806" assumed the book filled the canvas, which it doesn't): left page x = (render x − 42.1) / 1.2, right page x = (render x − 548.1) / 1.2, y = (render y − 62) / 1.2, from each page's top-left. Sizes divide by 1.2.

- **Left page:** x 82–510, centre 296.
- **Right page:** x 586–1017, centre 801.
- **Baselines:** y values are baselines unless they say otherwise.
- **Colours:** the canon's ink (46,28,10), faded (77,56,31), rubric (122,31,15) and gilt (214,168,82).
- **The page doesn't move between states.** Every block has a fixed y. Only the words change.
- **Tabs:** five tabs, each 92 px wide: Campaigns, Grudges and Ledger left of the title plate; Settings and Warpath right of it. Joe approved this in the Ledger session ("Tabs look okay"). The strip follows that, not the four tabs in these renders, which were not redrawn.

## Left page

| Element | Face, size, colour | Position |
|---|---|---|
| Kicker | Friz capitals 12, letterspaced 1.2, faded, between short rubric rules (the canon's date line) | centred at (296, 107) |
| Title | Morpheus small caps 31, rubric, 1 px dark-red shadow (70,12,6), then the ornament (half-width 120) | centred at (296, 150); ornament at y 167 |
| Welcome | Friz 18 on 22, ink. Sunk Morpheus initial, three lines tall; the lines tuck against its stem. Version numbers in EB Garamond Bold 20, rubric, faux-bold | from (82, 210), 428 wide, 3–4 lines, ending by y 290 |
| Map picture | inked world map with Warpath's marks (below) | 392 × 140, centred, top y 288 |
| Key | two columns of four; a 26 × 18 sample, then Friz 15 ink; a gloss in EB Garamond Italic 15, faded | columns at x 86 and 330; baselines 448, 469, 490, 511 |
| Map button line | the button's icon at 24 px, then Friz 16 ink | icon centre (95, 535); text at (120, 540) |
| Book line | Friz 16 ink | (120, 562) |
| Guild sharing | the game's check button, 18 px, with the yellow tick (`UICheckButtonTemplate`); "Guild sharing" in Friz 18 ink; its state ("on"/"off") in EB Garamond Bold 19, rubric, faux-bold | box top-left (82, 603); label (110, 618) |
| Sharing hint | EB Garamond Italic 16, faded, 19 leading, wraps | from (110, 640), 400 wide, 2 lines |
| Folio | EB Garamond Italic 17, faded: "— i —" | centred at (296, 694) |

### The three states

The page decides its state from what `Chronicle.News` already knows (`view.newSince`, `gdb.installed`, `gdb.seenVersion`). Nothing new is saved.

| | First install | Update | Opened later, nothing new |
|---|---|---|---|
| When | no `gdb.installed` yet (until the book is first closed) | opened by `News(since)` with releases newer than `since` | opened from the tab; `view.newSince` is nil |
| Kicker | `VERSION 3.8.4 · A NEW CHRONICLE` | `VERSION 3.8.4 · TWO NEW RELEASES` (count in words; "ONE NEW RELEASE") | `VERSION 3.8.4` |
| Title | Welcome to Warpath | Welcome Back | Warpath |
| Welcome | see below | see below | see below |
| What's New | all releases in ink, no divider | new ones flanked by gilt diamonds, a divider, read ones faded | all releases in ink, no divider |
| Footer | `5 releases` | `5 releases · 2 new` | `5 releases` |

### Text, final form

Each block gives today's text, then the replacement. `%s` stands for a value filled in at run time.

**Headline:** set by `n.headline` in `RenderNews`.
- Today: `gdb.installed and "Warpath" or "Welcome to Warpath"`.
- New: "Welcome to Warpath" on a first install, "Welcome Back" on an update, "Warpath" otherwise.

**Kicker:** today it's `n.version`, "Version " .. ns.VERSION, in small faded type. New:
```
"VERSION %s  ·  A NEW CHRONICLE"            -- first install
"VERSION %s  ·  %s NEW RELEASE%s"           -- update: count in words, upper case; "S" unless one
"VERSION %s"                                -- otherwise
```

**Welcome:** today's `Welcome()` is three paragraphs:
> Warpath draws your war on the world map: the roads you travel, today's trail, where you fought, killed and fell, and the enemies you've seen.
>
> This book keeps a campaign for each time you ride out, and your ledger of grudges. Open it from the minimap button or with /warpath chronicle.
>
> On the world map, the crossed swords in the top-right corner hide Warpath or choose what it shows. Everything else is on the Settings tab.

New. It's one paragraph, the chronicler's voice, and it leads into the picture. The how-to lines move under the key.
```
-- first install (%s: name, %s: today's date in words, %s: name)
"Here begins the chronicle of %s, opened on the %s. Warpath keeps it, and draws the war on the world map as it is fought, in these marks."
--   e.g. "…opened on the twenty-seventh of November…"
-- update (versions drawn as figures, the name possessive)
"Warpath was just updated, from {3.8.2} to {3.8.4}. What changed is on the facing page, marked new. On the world map it draws %s's war in these marks."
-- otherwise
"This is the chronicle of %s, kept by Warpath. On the world map it draws the war as it is fought, in these marks."
```
`{…}` marks a figure: its own font string in EB Garamond Bold, rubric, faux-bold.

**Map key:** the label, then the gloss in italic.
```
Your roads (builds over days)    A kill
Today's trail                    Where you fell
Where you lingered               An enemy seen
A flight you take often          Where you fought
```

**The two how-to lines:**
```
On the world map, top right: choose what Warpath shows.
This book: the minimap button, or /warpath chronicle.
```
"Everything else is on the Settings tab" goes, because the tab sits beside this one.

**Sharing hint:** set by `ShareCheck`.
- Today: "Guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on. Never your trail."
- New: "Guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on."

### The map picture

The picture is a fixed teaching scene, the same for every player, not their own data. The key must never be empty.

**The ground:**
- The World map's art around the Arathi and Hinterlands coast: sea at the top, land below.
- In the render this is the crop x 1250–1690, y 452–610 of `book/world.png`, Joe's 2000 px World-map screenshot, whose map canvas runs about x 205–1795 and y 62–1120.
- It's printed in sepia like the Campaigns route map. Land becomes bare paper, and sea and shading become brown ink (`refine.ink_map`'s ramp).
- It's multiplied onto the page through a rounded, soft-edged mask (radius 18, about 7 px of feather).

**The marks:** drawn over the ground at full colour (not multiplied), as Warpath draws them:
- A worn **road** in gold on a dark casing, from bottom left to centre right.
- A **flight**: royal blue dashes on a dark casing, arcing over the sea.
- **Today's trail**: dashes in the player's faction colour with one arrow, running into a lingering **area** (a dashed outline).
- **Battle haze**, exaggerated on purpose: two large patches in `DrawHaze`'s blood red, from rust (0.62,0.20,0.09) to dark (0.42,0.03,0.02), at full strength. One sits under the kills and a smaller one under the death.
- Three **kills**: `C.TEX_BLADES`, at the map's pin size.
- One **death**: `C.TEX_SKULL` untinted (white), which is how `Pin("death", …)` draws your own deaths.
- One **enemy seen**: the foe's crest, `ns.faction`'s foe → `C.FACTIONS[foe].crest`. That's the Alliance crest for a Horde player and the Horde crest for an Alliance player.

**The key's samples** use the same pieces:
- Pins are drawn at pin size: kill 20, skull 17, crest 20.
- Lines are drawn in a 26 × 18 box.
- The haze is a solid round patch.
- The trail sample takes the faction colour (`TrailColor`: red for Horde, blue for Alliance). See `r3_Y1_factions_ingame.png`.

**The map button** next to its line is `MapButton.lua`'s own button at 24 px: `C.TEX_SWORDS` in the `MiniMap-TrackingBorder` ring.

## Right page (W3's)

| Element | Face, size, colour | Position |
|---|---|---|
| Heading | Morpheus small caps 25, rubric, shadow, ornament (half-width 110) | "What's New" centred at (801, 120); ornament at y 133 |
| Sheet | the canon's inset sheet: page blended 30% toward (240,208,146), 1 px edge (130,84,40), soft shadow, no stack | box (576, 150)–(1025, 668) |
| Text column | inside the sheet | x 590–1003; first baseline at sheet top + 26 |
| Release heading | "Version 3.8.4" in Morpheus small caps 21, rubric, shadow, centred; rubric hairlines (50%) from the column's edges to 12 px short of the words, at baseline −6 | +26 below; +44 with a title |
| Release title | EB Garamond Italic 17, faded, centred | heading baseline + 20 |
| New release | the heading flanked by two gilt diamonds (canon `diamond`, r 3, edge (70,40,8)) at ±(half-width + 22) | |
| Topic | Friz capitals 11, letterspaced 1.4, faded, then a 30% faded hairline to the column's end (layout C's topic) | x 606; +22 (6 more before every topic but the first) |
| Note | Friz 16 on 20, ink. Its mark is the rubric diamond texture (`Diamond()`), 8 wide and 10 tall, never a bullet glyph. Wraps with a hanging indent | mark at x 594; text at x 606 |
| Between releases | | +18 |
| "Read before" divider (update only) | before the first release the account had already seen: the canon's gilt band (222,150,44, strength 150) across the column; "read before, at version 3.8.2" in EB Garamond Italic 17, rubric, centred; a gilt rule (176,128,52, 90%) under it | band from baseline −20 to +10; rule at +9; then +40 |
| Read releases | heading in (150,80,56) without shadow; notes in (104,82,56); marks in (150,90,60) | |
| Scroll | the canon's: crimson thumb (146,24,14), lit (206,72,48), edged (46,6,4), on a red-tinted cord inside the sheet's right edge; mouse wheel. Rows fade over 16 px at the bottom, and at the top only once scrolled | cord at x 1016 |
| Footer | Arial Narrow 15, faded, "5 releases · 2 new" (first install and otherwise: "5 releases") | right-aligned at (1017, 694) |
| Folio | EB Garamond Italic 17, faded: "— ii —" | centred at (801, 694) |

### Behaviour

- **One spread, no paging.** Gone from `Chronicle.lua`:
  - the Earlier and Later turn buttons;
  - `view.newsStack`, `newsStart`, `newsLine` and `newsNext`;
  - `Lay`'s paging, "(continued)" and "1 of N".

  Every release is drawn once into the sheet's scroll child, newest first, and the sheet scrolls. It opens scrolled to the top, where the newest release is.
- **New** means `Older(view.newSince, rel[1])`, as today. The red NEW badge is replaced by the gilt diamonds and the divider. The divider appears only when the sheet holds both new and read releases.
- **Sheet size is fixed.** A first install with few notes leaves the sheet partly empty.
- **Topics** ("## " lines) work as today.
- **Notes may wrap.** The column, 413 px or about 333 UI units, is a little narrower than today's page, so a few notes take two lines (`Inside your current area…` fits; `Spirit healers show on their own zone's map, with the corpse runs.` wraps). The 70-character cap in `test_notes_stay_short` stays.
- **The page heights in `Lay`** go. Measure each note with `GetStringHeight` after `SetWidth`, as now.

## Claude's calls, for Joe to veto

- **Title "Warpath" when opened later with nothing new**, and "This is the chronicle of %s, kept by Warpath…" as its welcome. This state was rendered (`r3_Y1_settled`), but Joe settled without commenting on it.
- **The kicker carries the version and, after an update, the count of new releases**, so the paragraph can say where you updated from.
- **The first-install date** is today's date in words. It shows only until the book is first closed, so no saved date is needed.
- **The map picture is a fixed teaching scene**, not the player's own map, so it's never empty or cluttered.
- **Key labels**: "Where you lingered", "A flight you take often" and "Where you fought" are my wording.
- **Read releases fade** after the divider, and **no divider on a first install**: everything there is unread but nothing is "new", as today.
- **Roman folios (i, ii)** for the book's front matter, and "5 releases · 2 new" in the footer.
- **The Share button and page-turn arrows are not on this tab.** The Share button belongs to Campaigns, and this tab doesn't turn pages.
- **Proposed `NEW_IN` change:** give 3.8.4 the title "Spirit healers", so every heading pairs a version with its title. `Options.lua` is untouched; this is a proposal only.

## What it needs in game

These are things to check on Forever 1.60.1 before building.

- **World map art** for the picture. The World map's tiles (`Interface\WorldMap\World\World1`…`World12`, or whatever `C_Map.GetMapArtLayerTextures` returns for the World map on this client) are drawn into a small frame, cropped with `SetTexCoord` to the region above.
  - Sepia: `SetDesaturated(true)`, then `SetVertexColor` toward (0.62, 0.86, 1.0) inverse-ink.
  - Multiply blend: `SetBlendMode("MOD")`.
  - Check the tiles' path and that MOD blending exists.
  - If the tiles can't be used, ask Joe before shipping any image. Client art rendered offline is still Blizzard's, so the picture must come from the client at run time.
- **Soft rounded edge** for the picture: `Texture:AddMaskTexture` or `SetMask` with a mask drawn by our script (MIT). Check that the mask API exists. If it doesn't, fall back to a hard rounded frame drawn from the canon's rules.
- **Marks:**
  - Pins: `C.TEX_BLADES`, `C.TEX_SKULL` and `C.FACTIONS[foe].crest`, with whatever texcoords `Pin()` applies.
  - Haze: `C.TEX_DOT` with the haze colours.
  - Road, trail, area and flight dashes: `Map.lua`'s own line pieces. Reuse its drawing helpers rather than copying them, so the key can't drift from the map.
- **Faction:** `ns.faction` (from `UnitFactionGroup`) chooses the crest and the trail colour.
- **Fonts:** EB Garamond Italic and Bold, bundled (see the canon; ask Joe before downloading). Version figures in the paragraph are separate font strings measured with `GetStringWidth`, because a font string has one font.
- **Check button:** `UICheckButtonTemplate`, as `ShareCheck` uses today.
- **Scroll:** a `ScrollFrame` with a scroll child sized to the drawn content, the canon's crimson bar, and `OnMouseWheel`. The edge fade of rows is the same open question as on Campaigns.
- **Number words:** count words (`ONE`, `TWO`…) for the kicker, and a date in words ("the twenty-seventh of November") for the first install. Both are small tables in Lua.

## Tests that change

- **`NewIn`:**
  - The paging tests go: the page count in `test_older_releases_are_a_page_turn_away`, and the Earlier/Later checks.
  - New tests to add:
    - all releases are in the scroll child, newest first;
    - the divider sits before the first release not newer than `newSince`, and is absent on a first install and when opened from the tab;
    - the gilt diamonds appear on new releases only.
  - Keep `test_notes_stay_short`.
- **Share:** the hint's text. Keep the check box's behaviour, including the preview guard.
- **A new key test:** the key's crest follows the faction (Horde → Alliance crest, Alliance → Horde crest), and its pins use the same textures `Pin()` uses.
