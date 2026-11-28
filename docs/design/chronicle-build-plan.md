# Chronicle redesign: build plan

Written 2026-11-27, after the design specs were committed (`1f6127a`). This file is the order of work for building them. The designs are in this folder: `chronicle.md` (the canon), `chronicle-warpath.md`, `chronicle-grudges.md`, `chronicle-settings.md` and `chronicle-ledger.md`. The Campaigns page has no spec here yet; its settled design is only in the ignored `tools/out/design/type/type-final.md` and `book/book-final.md` (phase 2 fixes that).

**The goal is to match the renders.** Every phase ends with a render of the real code, taken through the harness, set beside the settled design render at in-game size. Joe judges looks in game; the side-by-side is how we get there without guessing.

Nothing here is built yet. Nothing reaches the AddOns folder until Joe says to install a test build.

---

## Decisions (one still open)

1. **Download EB Garamond: done.** Joe approved (2026-11-27). `EBGaramond-Italic.ttf` and `EBGaramond-Bold.ttf` from `octaviopardo/EBGaramond12` (OFL 1.1), with the licence beside them in `Fonts/`; on branch `chronicle-probe`.
2. **Which release carries it: settled.** Joe, 2026-11-27: "Yes, 3.8.5". 3.8.4 (spirit healers, shared kills) is released as it is, and the chronicle redesign is built as **3.8.5**, one release at the end, with test builds along the way. (3.9 is battleground mode.)
3. **The probe build: done.** Installed as 3.8.4-probe1 and run by Joe (2026-11-27); results under phase 0.
4. **Grudge name keys** (open in `chronicle-grudges.md`): whether "Plains Stomper" and "Plains-Stomper" are merged in saved data. This would be a migration, so it needs Joe's agreement. Recommendation: **display-only** for this release (the display rule makes both read "Plains Stomper"), and merge later if duplicates bother him. Without the merge, one player can show as two grudges.

---

## Phase 0: what the client can do (done 2026-11-27)

Every page depends on things Warpath has never done on Forever. One probe build checks them all at once, so we don't build on a guess.

`/warpath probe` opens one panel that draws each item and labels it ✓ or ✗ (pcall around each):

| # | Check | Who needs it | If it fails |
|---|---|---|---|
| 1 | An addon `.tga` draws (`glow.tga`, plus one 2048×1024 test sheet) | the whole book art | ask Joe; fall back to vertex-coloured solids for everything |
| 2 | An addon `.ttf` draws via `SetFont` | every page (EB Garamond) | stand in game faces for italic and bold; ask Joe |
| 3 | `Fonts\MORPHEUS.TTF`, `FRIZQT__.TTF`, `ARIALN.TTF` by path | small caps and sizes | use the font objects that carry them |
| 4 | Class icons: `Interface\Icons\ClassIcon_<CLASS>` and `UI-Classes-Circles` with `CLASS_ICON_TCOORDS` (the Grudges `_runlines.txt`) | Campaigns, Grudges, Ledger | the third choice, today's `UI-CharacterCreate-Classes` |
| 5 | `INV_Misc_QuestionMark` | unknown class | a "?" in Morpheus, as the Grudges spec already allows |
| 6 | `SetGradient` with `CreateColor`, or `SetGradientAlpha` | bands, washes and row fades | stepped solids |
| 7 | `CreateMaskTexture` / `AddMaskTexture` | the soft-edged map pictures | a hard-edged frame |
| 8 | `SetBlendMode("MOD")` | map pictures printed in sepia | plain alpha blend at reduced alpha |
| 9 | `C_Map.GetMapArtLayerTextures` for the World map, 1414 and 1415, drawn and cropped | the Warpath, Campaigns and My Lands maps | ask Joe; no image ships in its place |
| 10 | A loading-screen texture under `Interface\Glues\LoadingScreens\` | the Settings caption preview | (c), a dark backdrop, after asking |
| 11 | `Texture:SetRotation` | the Ledger's hour wheel | thin rotated lines, or a bar strip |
| 12 | Check and radio templates at 18 and 14 px; `SetHitRectInsets` | Settings sub-rows | keep the 22 px boxes |
| 13 | `IsFalling`, `MIRROR_TIMER_START`, `UnitCreatureType`, `GetGuildRosterInfo` | Ledger recordings | drop that recording, and say so |

**Status (2026-11-27):** built as **3.8.4-probe1** on branch `chronicle-probe` (`1ce08de`) and installed by script. Joe approved downloading EB Garamond: `EBGaramond-Italic.ttf` (602,136 bytes) and `EBGaramond-Bold.ttf` (687,396) from `octaviopardo/EBGaramond12` `fonts/ttf`, with `OFL.txt` as `Fonts/EBGaramond-OFL.txt`. The 2048×1024 test sheet is 8.4 MB uncompressed and 6.8 MB as RLE TGA, too large to ship as one file; phase 1 must split or tile it. Joe ran it in game (2026-11-27 21:24, Lethality in Moonglade), with a screenshot and the saved `WarpathGlobal.probe`.

### Probe results (Forever 1.60.1)

Everything the designs need exists. No fallback is needed.

| # | Check | Result |
|---|---|---|
| 1 | Addon textures | **Work.** `glow.tga`, the 2048×1024 sheet (plain and RLE TGA) and the soft-alpha disc all draw, alpha included. |
| 2 | EB Garamond from `Fonts/` | **Works.** Both faces draw, and the em dash, middle dot, curly quotes and ellipsis are all there. `SetFont` returned **false** for them even though they drew and measured (380 and 378 px against Friz's 385), so never gate on its return value. |
| 3 | Game fonts by path | **Work:** `Fonts\MORPHEUS.TTF`, `FRIZQT__.TTF`, `ARIALN.TTF`, `SKURRI.TTF`. Morpheus has all four punctuation marks. For the record, `QuestTitleFont` and `Fancy22Font` are Morpheus, `QuestFont` is Friz 13, and `NumberFontNormal` is Arial Narrow 14 with an outline. |
| 4 | Class icons | **All four exist:** `ClassIcon_<CLASS>` (square, with a bevel), `UI-Classes-Circles` (round), `UI-CharacterCreate-Classes` (square) and the `classicon-<class>` atlas (square, brighter, edge to edge). `CLASS_ICON_TCOORDS` exists. |
| 5 | `INV_Misc_QuestionMark` | **Works.** |
| 6 | Gradients | **`SetGradient` with `CreateColor` works.** `SetGradientAlpha` doesn't exist. |
| 7 | Masks | **Work:** a soft-edged disc masks a solid. |
| 8 | MOD blend | **Accepted** (`GetBlendMode` returns MOD), and the swatch drew darker than the page. `SetDesaturated` wasn't tested; check it in the first phase-1 build. |
| 9 | Map art | **Works:** `GetMapArtLayerTextures` gives 12 tiles of 256 px (layer 1002×668) for the World map (947), Kalimdor (1414) and Eastern Kingdoms (1415). All three drew, and so does the old `World\World1` path. |
| 10 | Loading screens | **Exist:** Kalimdor, Eastern Kingdom, Warsong Gulch, Arathi Basin and Dire Maul. **Missing:** Orgrimmar. |
| 11 | `SetRotation` | **Works.** |
| 12 | Small controls | **Work:** checks at 24, 22 and 18 px and radios at 16 and 14 draw cleanly, and `SetHitRectInsets` works. |
| 13 | APIs | **All exist:** `IsFalling`, `GetMirrorTimerInfo`/`Progress`, `UnitCreatureType`/`Family`, `GetGuildRosterInfo` (name, rank, level, class and public note all read), `GetNumGuildMembers`, `C_GuildInfo.GuildRoster`, `C_Texture`. The bare `GuildRoster()` doesn't exist: use `C_GuildInfo.GuildRoster`. |

**Screen:** Joe plays at 2560 px wide, and the UI is 2133 units wide, so **1 UI unit = 1.2 screen pixels** at his settings. The book (880×580 units) covers about 1056×696 pixels. Consequences:
- **The book background doesn't need a 2048-wide sheet.** Its art is drawn at 1056×696 and packed into 1024×1024 sheets: for example, each page with its half of the cover on one sheet, cropped with texcoords. That's 4 MB each uncompressed, so phase 1 compares TGA RLE against Pillow's BLP output for size and looks.
- **The conversion question** is settled in phase 1 against this figure, as planned.

**Choices made from the results (Claude's calls):**
- **Class icons: `ClassIcon_<CLASS>`.** It's the true class icon, square, which suits the canon's tiles, and the framed bevel reads at 26 px. The atlas is the alternative if Joe prefers it brighter.
- **Gradients:** `SetGradient` with `CreateColor` only.
- **The Settings caption preview:** Arathi Basin or Warsong Gulch landscape (for Joe to pick in the render), with no fallback needed.

The probe ships in no release. It lives on its own branch, and the answers are written into this file and the specs' "What it needs in game" sections.

**One conversion for all pages (settled 2026-11-27).** The specs gave two: the Warpath and Ledger specs multiplied by 0.806 (880/1092); the Grudges and Settings specs subtract a page origin and divide by 1.2. Measured on `book/ref_R1_raw.png`, the book's leather runs from about x 22 to 1072 and y 44 to 735, so the 880×580 frame is drawn at **1.2 render px per unit** inside a larger canvas (room for the tabs and the scene around it). The Grudges and Settings formula is right, and 0.806 was 3% off; the Warpath and Ledger specs now say so. It also matches Joe's screen (1.2 px per unit at 2560 wide, from the probe), so a render pixel is a screen pixel at his settings. In the code, every position is written in render pixels copied straight from the specs' tables and converted by one function, `Book.X/Y`, so a spec and its code can be compared line by line.

---

## Phase 1: the book kit (shared by every page)

### Files

`Chronicle.lua` is 1,298 lines today. With the Ledger it would be several times that, and the client's 200-locals and 60-upvalues limits would come into play. Split it:

| File | Holds |
|---|---|
| `Book.lua` | Art, type and helpers. Faces (`Face("friz", 18)` etc.), small caps (one string per letter run), faux bold (drawn twice, 1 px apart), shadowed rubric, the ornament, drop cap, `Sheet` (pasted sheet, scroll child, crimson bar, edge fades, wheel), `Tile` (red, gold-bevelled, "?"), `GiltBand` (with join), `Wash`, `Reckon` (label, leader, value), `Name` (the First Last display rule, N2 colour, tooltip), `Diamond`, `Chevron`, `Ribbon`, number and date words, the px→unit conversion |
| `Chronicle.lua` | The frame, art, the five tabs, routing, Open/News/Refresh, popups |
| `ChronCampaigns.lua`, `ChronGrudges.lua`, `ChronWarpath.lua`, `ChronLedger.lua` | One page each: build and render |
| `Options.lua` | The Settings page, as today, rebuilt on `Book.lua` |
| `Chronicler.lua` | The campaign prose, ported from `campaign-voice/chronicler.py` |
| `Ledger.lua` | The Ledger's numbers (`Ledger.Stats`, `Ledger.Summarize`), with no drawing in it, so it can be tested alone |

New files mean a full restart, as always. The `.toc` order is `… Campaign.lua, Chronicler.lua, Ledger.lua, Zone.lua, Map.lua, … Book.lua, Chronicle.lua, Chron*.lua, Options.lua …`.

### Art

- **The generator moves into the repo.** The book ships, so the script that draws it must be tracked: `refine.py` and its parts go into `tools/art/` (MIT, like the rest). It exports TGAs into `Art/`. The ignored design folder stays the design record.
- **What ships as a texture:** the cover, corners, page stack, parchment and burn as one book background. The probe measured the book at about 1056×696 screen pixels on Joe's screen (1.2 px per unit), so it's drawn at that size and packed into 1024×1024 sheets (see "Probe results"). A single 2048×1024 sheet was 8.4 MB, or 6.8 MB as RLE TGA. File sizes are checked before committing.
- **What stays code:** sheets, bands, washes, tiles, rules, ribbons and diamonds are vertex-coloured solids and gradients, as the specs ask. The sheet's soft shadow can be a small 9-slice TGA (addon textures load).
- **Kept from the game:** tabs (restyled to five of 92 px), the title plate, close, Share, page-turn arrows and `UIPanelButtonTemplate`.

### A book renderer in the harness

Today the harness can't draw the book (`docs/open-items.md` says so), which is why earlier chronicle looks were only mocked. `render.py` gains `--book <tab>`, drawing the chronicle's real frames from the real code:

- textures from `Art/` as they are, and game textures as labelled stand-ins;
- fonts: EB Garamond itself; Candara for Friz, Palatino small caps for Morpheus and Arial Narrow for Arial Narrow (the stand-ins the design renders used, so the two are comparable);
- `--scale 1.175` for the in-game size, and `--beside <design.png>` to place it next to the settled render, or `--onion` to overlay them at 50%.

Each phase is done when its side-by-side matches, element by element, within a pixel or two at in-game size, except where a stand-in font differs.

### Tests for the kit

- **Names:** the display rule on every form in Lethality's data ("Savage-Druiduser", "Xaryu Forever-", "Charkoalz Rogue-CAMWOWUS2Realm6PvP").
- **Number words and date words:** "the twenty-seventh of November", "TWO NEW RELEASES".
- **Sheet:** fixed size, scroll range, a bar only when the content overflows, the top fade only once scrolled.
- **Layout:** each page's positions from its spec table are kept as data in its file, and a test checks that the built frames land there (±1 unit). This keeps code and spec from drifting.

---

## Phase 2: Campaigns, the page the canon was drawn from

Campaigns comes first because it's the reference page. If `ov_V5a_ingame.png` can be matched, the kit is right.

1. **Write `docs/design/chronicle-campaigns.md`** from `type-final.md`, `book-final.md` and the chronicler notes, in the same form as the other specs (geometry, states, sources, tests). This is the one page with no tracked spec. Joe confirms it before the build.
2. **Port the chronicler** (`chronicler.py`, 285 lines) to `Chronicler.lua`: zone by zone, phrase tables, "the rogue Bluey" then "Bluey", crowds in words, phrasing chosen by a seed from the campaign's start. Test it against `samples.txt`: the same campaigns must give the same prose.
3. **Left page:** the date line, a two-line title ("From X" / "to Y"), the hand-wrapped prose with the sunk drop cap and N2 names (one string per run, measured), and the route map (the world art in sepia, a dashed road through the zones in order, crosses ×N, a ring and a flag).
4. **Right page:** Deeds and Losses on the sheet: folding zone lines and S3b rows (tile, time, name, level, tag; the rare part raised; gilt bands joined), then The Reckoning.
5. **Footer:** Earlier and Later, folios, "campaign 4 of 5", "show 4 quiet" (the backlog's activity filter, as drawn). One spread per campaign: deeds scroll inside the sheet and never page.

---

## Phase 3: Warpath tab

As `chronicle-warpath.md`. The three states come from what `News` already knows; nothing new is saved. The map picture is a fixed teaching scene drawn with `Map.lua`'s own line and pin helpers (refactored so they can draw into any frame), so the key can't drift from the map. What's New becomes one scrolling sheet, and the paging code (`newsStack`, `Lay`'s pages, Earlier/Later on this tab) goes. Tests as listed in its spec ("Tests that change").

## Phase 4: Grudges

As `chronicle-grudges.md` (R2a and E1): the list sheet with the ribbon bookmark, the account with leaders, the global encounters log under day headings, the empty page as prose, and the wording table applied across `Grudge.lua`, `Commands.lua`, `Hud.lua` and `Options.lua`. The frame named `WarpathChronicleLedger` is renamed, to free the word for the Ledger tab.

## Phase 5: Settings

As `chronicle-settings.md`. This phase changes behaviour, not just looks:

- `runs`, `flights` and `spirits` become separate layers, and `shared` splits into guildmates' pins and guildmates' sightings. The upgrade copies today's values into the new keys and deletes nothing (agreed). The map button's menu follows.
- Guild sharing off hides guildmates' marks and their deaths' weight on dangerous ground, keeping the data (agreed).
- The caption preview is built from the real `ShowTextCard`/`ShowStripCard` code, refactored to draw into a given parent and scale, over a loading-screen crop.
- The `SettingsTab` fit test with the new rows. If Friz runs wider than the stand-in, the hint wording is trimmed; the type never shrinks.

## Phase 6: Ledger recordings (could move earlier)

The Ledger's new figures count only from the version that records them, so the sooner they're recorded, the fuller the page is at release. Recording can go into the first test build after phase 0, ahead of the pages:

- `db.flights`, `db.runs`/`z.runs_n`, `db.spirit`, `db.ghostYards`;
- on marks: `m.my`, `m.hp`, `m.odds`, and `m.cause`/`m.how` from state at death (the combat log is blocked on Forever);
- `g.vn`/`g.vc`: the kill message gains a trailing class field, which older versions ignore. The patch notes say guildmates need the new version for their victims' classes to show.
- `Ledger.Summarize` into `WarpathGlobal.chars` at login and logout, inside `pcall`.

All additive, with no `db.v` bump (agreed). Tests: each recording, older builds ignoring the keys (`Upgrades`), and `RealData` showing nothing lost.

## Phase 7: Ledger spreads

As `chronicle-ledger.md`: seven spreads with page arrows and the C3 account toggle, built on `Ledger.Stats`, which is tested alone against the figures the spec quotes from Lethality's snapshot (28 · 27 · 6; multi-kills 2, 1, 0, 0; busiest at 22:00 with 6; and so on). Then the pages in order F1→F7, each matched to its `_ingame` render. The account view and empty states come last, with Dabank and Derelect as the empty cases.

---

## How each phase goes

1. Build on branch `chronicle` (from `areas-merge`, or from `main` once 3.8.4 is released).
2. `check.py` and `test_warpath.py` with `WARPATH_WTF`, plus the new tests, each proven able to fail.
3. Render with `--book` beside the settled design; fix differences or list them for Joe.
4. Player-facing text (NEW_IN, welcome) is written before installing.
5. A test build goes in only on Joe's go-ahead (`3.8.5-testN`, with a SavedVariables backup), with a note on whether it needs a restart. Joe judges in game; his calls go into the specs.
6. Calls I make myself are marked "Claude's call" in the spec and in `docs/how-it-works.md`.

Release once, when all five tabs are done: `CHANGELOG.txt`, `NEW_IN`, "Your saved data:", the release checklist in `CLAUDE.md`.

## Risks

- **Addon textures or fonts don't load on Forever.** Everything rests on them, which is why phase 0 comes first.
- **Friz is wider than the stand-in.** Fixed sheets and fixed type mean wording is trimmed, never shrunk; the fit tests catch it.
- **Lua limits.** Many font strings per row (one font per string) push locals and upvalues; the file split and keeping layouts in data tables keep each file small. `check.py` reports it.
- **Frame counts.** The Ledger has hundreds of font strings. Spreads are built lazily, on first view, and pooled.
- **The map art** may not crop cleanly from `GetMapArtLayerTextures`. If it can't, the pictures need Joe's decision; no offline image of Blizzard's art ships.

---

## Merged so far (into `chronicle`, 2026-11-27)

Reviewed by the orchestrator, then merged; 270 tests pass on the merged branch with Joe's real characters (`check.py` clean).

| Piece | Branch | What landed |
|---|---|---|
| Chronicler | `claude/chronicle-chronicler-21e2a7` | `Chronicler.lua` (`Write(camp, who, foe)`: date, title, prose runs); `ns.DisplayName`, `NumberWord`, `OrdinalWord`, `DateWords`, `MonthName`, `DayName` in `Warpath.lua` (so phase 1's kit doesn't need its own number and date words). Lethality's prose matches `samples.txt` word for word. |
| Settings behaviour | `claude/chronicle-settings-behaviour-97ea54` | Layers `runs`/`flights`/`spirits` and `guildMarks`/`guildSights` (old keys kept for 3.8.4); sharing off hides guild pins, sightings, haze and guild deaths in `DeathField`; lengths under their layers; `ns.KillCard.Text/Strip(k, parent, scale)`; grudge wording; Settings wording as the spec's "Final wording". |
| Ledger data | `claude/chronicle-ledger-data-44878f` | Recordings (`db.flights`, `db.runs`/`z.runs_n`, `db.spirit`, `db.ghostYards`, `m.my`, `m.hp`, `m.odds`, `m.cause`/`m.how`/`m.ct`, `g.vn`/`g.vc` with the kill message's new trailing class); `Ledger.lua` (`Stats`, `Roster`, `Summarize`, `Account`). |
| Book art | `claude/chronicle-art-dac0d1` | `Art/book/book.tga` (1024², RLE, 2.38 MB, 1:1 with the right-edge strip folded into spare rows), `book-shadow.tga` (9-slice), `sheet-shadow.tga`, `map-mask.tga`; generator in `tools/art/`. |

### Calls the sessions made (for the decision log and Joe's veto)

- **Chronicler:** one-zone title "The Skirmish" / "in Felwood" (prototype: "The Felwood Skirmish"); lowercase articles inside titles; phrases for 35 zones the prototype lacked; numbers as words up to 999; "The Barrens went badly"; with no faction the foe is "the enemy"; two prototype crashes fixed.
- **Settings:** guildmates' rows grey and their marks hide while the parent layer is off; the three "kept for" rows step 22 px (Map was 2 px over its page); guild entries in the map button's menu indented under their parents; "Sharing off" chat line adds that marks are hidden, not deleted.
- **Ledger data:** Bloodbath counts `mk == 5` (the spec's `>= 5` would count a chain of six twice); campaign records only from campaigns with a fight; "Longest streak" uses the latest time the best was reached; corpse run vs spirit healer by distance at unghost (100 yd); an expired breath or fatigue timer beats a creature; "Worst odds won" only when outnumbered; "Struck down" in the account view takes the highest count, since `killers` is account-wide.
- **Book art:** the art is 1062×704 (not 1056×696) so the corner shadows aren't cut; the book's drop shadow is a separate 9-slice; packing option (d).

### To check in game (first build that wires each in)

- RLE textures with varying alpha (the leather's corners and shadows); the map mask stretched over a picture (corners may stretch: sliced mask or four corners).
- Map and Alerts settings still fitting with Friz.
- `flightHours` seems to draw nothing (recent "f" strokes have no look in `RUN_LOOK`; flights draw only as legs): decide what Flights' "kept for" should do.
- Ledger recordings: `MIRROR_TIMER_*`, `IsFalling`, `UnitCreatureType`, `PLAYER_UNGHOST`, `GetGuildRosterInfo`'s return order, the 100 yd body distance.

### Player lines collected for 3.8.5

- Settings (`NEW_IN`): corpse runs, flights and spirit healers are separate map layers; guildmates' pins and sightings each have a switch, under yours; with guild sharing off, guildmates' marks are hidden, not deleted; trail, corpse-run and flight lengths sit under their layers in Settings.
- Guild: guildmates need the new version for the Ledger to show their victims' classes; kills from older versions show the class as unknown.
- Saved data: settings only change by copying; nothing is removed; new Ledger counts start from the first fight on 3.8.5; each character's "All characters" summary is built from what it already has at its first login.
- Install: new files (`Chronicler.lua`, `Ledger.lua`, `Art/`, `Fonts/`) need a full restart.
