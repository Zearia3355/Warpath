# Chronicle design: the canon

Settled with Joe on 2026-11-27 for the Campaigns page. Every other page of the chronicle (Grudges, Settings, Warpath, and the new Ledger) is redesigned to match it. This file is the reference those page designs follow. Nothing here is built yet.

Each page's own design lives beside this file as `chronicle-<page>.md`.

## Where the work is

All of it is under `tools/out/design/`, which git ignores. Each folder has its own `.md` notes, and its scripts run from that folder.

- **The book art** is in `book/`. The generator is `refine.py`, run as `python refine.py R1`. The final render is `ref_R1.png`, with `ref_R1_raw.png` unlabelled. Notes: `book-final.md`, `tome-passes.md`.
- **The type and the Campaigns page** are in `type/`. The generator is `combo.py`, built on `type.py`, `mix.py`, `honour.py` and `overflow.py`. The final renders are `ov_V5a.png` and `ov_V5b.png`; `_ingame` versions are at 1.175×, the size in Joe's screenshot. Notes: `type-final.md` (settled) and `type-directions.md` (every round, with Joe's picks).
- **The chronicler voice** is in `campaign-voice/`. The prose generator is `chronicler.py`, with samples in `samples.txt`. `shot.webp` is Joe's in-game screenshot of today's book.

## The book (Joe: "The book is done.")

- **Cover:** deep crimson leather, scuffed, with a blind-tooled double rule. No stitching, no ribbon, no headbands; Joe rejected all three.
- **Corners:** antique gold L-pieces with pyramid studs, lit from the top left.
- **Page stack:** 7 rippled, frayed leaves under the top leaf, fanning toward the outer corners.
- **Bottom corners under the pages** (Joe, 2026-11-28, after seeing 3.8.5-test2 in game): the page stack lies over the two bottom corner pieces; the top corners stay over the pages ("the top corners look fine already, its just the bottom ones"). From renders: all seven leaves over the metal (B), with the stack's foot fanned 75% as far as before so more leather shows below it ("the margin on the bottom between the edges of the book cover and the pages needs to be increased"), and a soft shadow from the stack on the gold (S1, "S1 soft"). In `tools/art/book.py`: `FOOT_FAN`, `STACK_SHADOW`, `stack_shadow()`.
- **Parchment:** `parchment()` in `refine.py`. Base (228,180,106), with grain at five scales, fibres, flecks, a faint crumple and warm patches.
- **Burn:** an even falloff from the deckled edge, amber further in, brown at the rim. No blotches.
- **Kept from the game:** the tabs, title plate, close button, Share button, page-turn arrows and icons.
- **Licence:** all the art is drawn by our own scripts, so it ships under MIT. Outside art is allowed only if it is licensed for an MIT addon (CC0, or CC-BY with credit; see `CLAUDE.md`, Design principles).

## Type (Joe: "Settled")

- **Display faces:** Morpheus small caps, in rubric, with a 1 px dark-red shadow. They're for titles and page headings ("Deeds and Losses", "The Reckoning"), each followed by the rubric ornament (rules and a gilt diamond).
- **Date and kicker lines:** Friz capitals, letterspaced and faded, between short rubric rules.
- **Body:** Friz, 18 px on 22 px leading.
- **Drop cap:** a sunk Morpheus capital in rubric, three lines tall, with no box. The lines tuck in against its stem. It's for a page that opens with prose.
- **Names:** in class colour taken halfway from the parchment-inked tone toward the game's colour (N2), with a black 1 px shadow. A name can be hovered for a game tooltip.
- **Foe names, every page:** Forever's First Last. "Plains-Stomper" and "Plains Stomper" both show as "Plains Stomper", and realm ids are never shown. The display rule is in `chronicle-grudges.md`, under Names.
- **Class icons, every page:** the client's own (Joe: "the actual blizzard class icons"). Which texture exists on Forever, `ClassIcon_*` or `UI-Classes-Circles`, waits on Joe's screenshot of `tools/out/design/grudges/_runlines.txt`.
- **Italic:** EB Garamond Italic (OFL, to be bundled), faded. It's for secondary labels: zone names, tags and folios. The game has no italic face.
- **Figures that matter:** EB Garamond Bold in rubric, faux-bold. They go in ledger values, set against Friz labels with hairline rule leaders.
- **Small print:** Arial Narrow, faded. It's for times and footer controls ("campaign 4 of 5", "show 4 quiet").
- **The rare thing raised:** a gilt diamond, then Morpheus capitals in rubric. A warm gilt band runs behind a special row, and neighbouring special rows join into one band. Only what is rare is raised; the common case ("first blood") stays faded italic.
- **Inset sheet:** content that's a list sits on one pasted sheet, slightly paler than the page, with a soft shadow and no stack under it. It's a fixed size and scrolls inside, with a crimson scroll bar: thumb (146,24,14), lit at (206,72,48), edged in (46,6,4), on a red-tinted cord. Rows fade at the sheet's edges.
- **Row tiles:** a class-icon tile, red normally and bevelled gold for an honour.

### Colours

- Ink (46,28,10)
- Faded (77,56,31)
- Rubric (122,31,15)
- Gilt (214,168,82)

## Where the book sits in a render (measured 2026-11-27)

Every page spec gives positions in render pixels on the 1092 × 748 design canvas. The book renderer (`render.py --book`) measured the game's own frame against Joe's screenshot, which the design renders pasted their tabs, plate and buttons from: the book's top-left is at **(20.5, 40.4)**, and 1 UI unit is 1.2 px. So:

- left page: x = (render x − 42.1) / 1.2, right page: x = (render x − 548.1) / 1.2, both: y = (render y − 62) / 1.2, from each page's top-left (the pages sit `PAD` = 18 units inside the book);
- sizes divide by 1.2.

The first guess, (44, 66) and (550, 66), was 2 px right and 4 px low; the specs now use the measured values. The book art (`Art/book/book.tga`) was cut with the frame at (18, 40), so in game it's anchored 2.1 units left and 0.3 units up of the book's top-left; then the art, the game's controls and the text all land where the designs show them.

## Joe's standing rules for these designs

- **One spread per campaign.** On Campaigns, overflow scrolls inside a sheet and never turns the page. Joe, 2026-11-27: "The 2-page limitation really just applied to the campaign tab." Other pages may use several spreads with page arrows; the Ledger does (see `chronicle-ledger.md`).
- **Tabs:** five, each 92 px wide: Campaigns, Grudges and Ledger left of the title plate, Settings and Warpath right of it. Joe: "Tabs look okay." Every page's tab strip follows this, whatever its renders show.
- **Names:** the Ledger tab keeps "Ledger". The Grudges page drops "The Ledger of Grudges" (Joe: "Grudges tab should just be 'Grudges' no?"); it's now titled "Grudges".
- **Fixed sizes.** "No shrinking."
- **Bold is allowed.** Use faux bold where it helps someone read; don't make everything one weight.
- **The voice is a chronicler's.** Third person, past tense, never machine-like. Numbers in prose are said in words where a scribe would.
- **Warcraft-like.** Every page should feel like a book from Azeroth, not a web page.
- **Free on art, not on function.** Be bold with the book's art, but leave the tabs and features alone unless Joe asks.
- **How Joe picks.** Render a range of options on real saved data, and let him pick or combine. Make your own calls where you have to, mark them "Claude's call", and expect them to be vetoed.
- **Normal size decides.** Judge every render at in-game size (the `_ingame` renders), not only zoomed in.

## Known limits in the client

- The client ships its fonts as compiled `.slug` files, so Friz and Morpheus can't be rendered outside the game. Stand-ins: Candara for Friz (whose old-style figures make numbers look bouncier than they will in game), and Palatino Bold small caps for Morpheus.
- A font string has one font and one shadow. Mixed styles mean one string per run, measured with `GetStringWidth`.
- The client's textures are packed, so icons in renders are stand-ins. Which class-icon texture exists on Forever is still to be checked.
- Before downloading a font or any art, ask Joe, giving the file name, source and size.
