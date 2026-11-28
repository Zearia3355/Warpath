# Chronicle design: the Grudges tab

The Grudges tab, redesigned to match the Campaigns page (`chronicle.md`, the canon). This is a design only: nothing here is built yet. Today's page is `BuildGrudgePages`, `RenderGrudges`, `GrudgeList` and `LastSeen` in `Chronicle.lua`. Its data comes from `Grudge.lua`.

**Status: settled** (Joe, 2026-11-27: "Settled"). The look is R2a. The title is settled as "Grudges" (relayed from the Ledger session; `chronicle.md` records it). Still to follow: the real class icons, which wait on Joe's in-game screenshot. See **Open**.

## Joe's picks

- **Round 1** (G1 ledger, G2 feud, G3 roll, G4 blood debt; `directions.py`):
  - "I enjoy the encounters log from G1 - hope it's global and not specific to the selected grudge player on the left - I'd want it to be a global log of all grudge encounters or it'd probably be pretty empty."
  - "G1 also has the best ledger on the left page."
  - "G3 has the best right page top-right summary, EXCEPT for the blows counter, where G1 has better stats."
  - "The class icons should be the actual blizzard class icons."
  - "Can this use WoW Forevers new First Last name system?"
- **Round 2** (R2a, the global log with the chosen grudge's lines washed; R2b, the same with a filter): "R2a, tinted lines".
- **After round 2:** "The icons above the name on the right page are just a little too high up on the page. I'd like a bit more margin from the page edge." "Typset for when no grudges are held should be better." (E1 and E2, `empty.py`) "E1". "Wording suggestions okay."
- **Relayed from the Ledger session:**
  - "Grudges tab should just be 'Grudges' no?"
  - Five tabs: "Tabs look okay."
  - "The 2-page limitation really just applied to the campaign tab." Grudges doesn't need a second spread: the list and the log scroll inside their sheets.

## Final renders

All are in `tools/out/design/grudges/`. Each has an `_ingame` version at 1.175×, and a `_raw` version with no label. Judge them at in-game size.

- `final_busy.png`: a made-up busy list (11 grudges), with Wreckless Dawnmere chosen. It shows the gilt marks, a note and a long log.
- `final_busy_scrolled.png`: the list and the log both scrolled, with Hask Stonebeard chosen.
- `final_real.png`: Lethality's real grudges (4, none with blood yet), with Savage Druiduser chosen.
- `final_real_unknown.png`: the real grudges with Xaryu Forever chosen. This is today's default pick (first in the list), and nothing is known about them.
- `final_empty.png`: no grudges at all (E1). Its generator is `empty.py`.
- Generator: `final.py`, built on `round2.py`, `directions.py`, `gparts.py`, `gdata.py`, `gbase.py` and `mkbare.py`. Run it from that folder.
  - The book is the R1 art, without Share or the page arrows.
  - The tab strip comes from `ledger/lbase.py` `tabs()`.
  - The real data is read only, from `WarpathGlobal.kos`.
- Earlier rounds: `G1..G4_real/_busy` and `R2a/R2b_*`. Notes: `directions.md`.

## Units

The units are the canon's. Positions are in **render px** on the book art (1092×748), at about 1.2 render px per game unit:

- Left page: game x = (render x − 42.1) / 1.2.
- Right page: game x = (render x − 548.1) / 1.2.
- Both pages: game y = (render y − 62) / 1.2.

Text columns:
- Left page: L0 = 82 to LR = 510, centre CX = 296.
- Right page: R0 = 586 to RR = 1017, centre RCX = 801.

Every y below is a text baseline unless it says "top".

## Colours

- **The canon's:**
  - Ink (46,28,10)
  - Faded (77,56,31)
  - Rubric (122,31,15)
  - Rubric shadow (70,12,6)
  - Level (106,80,48)
  - Gilt diamond (176,128,52), edged (70,40,8)
- **Gilt band** (the rare thing): (222,150,44) at 59%.
  - Across, it fades in over the first 6% and out from 55% to the end, on a curve to the power 1.4.
  - Top and bottom soften over 4 px.
  - Neighbouring gilt rows join into one band.
- **Chosen wash:** parchment blended 16% toward (70,50,44), flat and square-ended. A rubric hairline at 75% runs along its top and bottom edges. It must never read as gilt (coordinator's review, round 2).
- **Names (N2):** class colour taken halfway from the parchment-inked tone toward the game's colour, with a black 1 px shadow. A foe of unknown class is drawn in plain ink with no shadow.

## Terms: what the page counts, and where it comes from

Every grudge is one entry in `WarpathGlobal.kos` (`gdb.kos` in `Grudge.lua`). The ledger is account-wide and keyed by the full name.

| Term | Meaning | Source |
|---|---|---|
| **held** | A name in `gdb.kos`. It leaves only when forgiven (`Grudge.Forgive`). Killing a grudge never removes it. | `Grudge.List()`, `Grudge.Count()` |
| **slew** (Lethality slew them) | Kills of this foe. | `r.kills`. `Grudge.Add` starts it from this character's `db.victims[full]` (kills made before the grudge, on the character that added it). `Grudge.OnKill` adds 1 for each kill after that. |
| **fell** (They slew Lethality) | Deaths to this foe. The killer is the client's best guess: the last hostile player targeted in the 20 s before death. | `r.deaths`. `Grudge.Add` starts it from `gdb.killers[full]`, which is account-wide. `Grudge.OnDeath` adds 1 for each death after that. |
| **settled** | Kills made while the grudge was held. So settled ≤ slew. | `r.settled`, +1 in `Grudge.OnKill` |
| **settled this week** | Settlings, not grudges: entries in any grudge's log with `k == "k"` and `t` within 7 days. It's said as "settled N times this week" (or "none settled this week") so it agrees with the gilt marks, which are per grudge. Each log keeps 30 entries (`C.GRUDGE_LOG`). | `r.log` |
| **settled lately** (the gilt) | A grudge with at least one settling in the last 7 days. | `r.log` |
| **no blood yet** | `r.kills + r.deaths == 0`. | |
| **last seen** | The latest sighting: zone and time. Sightings within 10 min are logged once. "not seen since <the day it was added>" when there is none. | `r.seen = {t, z, x, y}` from `Grudge.OnSighted` |
| **encounters** | The log entries. `g` inscribed by hand; `a` added automatically; `s` sighted; `k` slew them (a settling); `d` fell to them. | `r.log = {{t, k, z}}` |
| **note** | Up to 120 characters, written on the page. | `r.note`, `Grudge.SetNote` |
| **who** | Level (−1 shows as "??"), race, class and guild. | `r.lv`, `r.ra`, `r.class`, `r.gu`, from `Foes.info` at add, sighting and death |
| **held since** | When the name was set down; "added automatically" when `r.auto`. | `r.added`, `r.auto` |

## Names: Forever's First Last

Forever has no realms. Its players have a first and a last name, and the ledger receives them two ways:

- **Guild messages, and names typed with a space** give "Plains Stomper". A realm id may be appended after a hyphen, as in "Charkoalz Rogue-CAMWOWUS2Realm6PvP".
- **`UnitName`** returns the surname where a realm would be, so the key becomes "Plains-Stomper".

Lethality's saved data has both forms for the same players ("Plains Stomper" and "Plains-Stomper", "Danika Patrik", "Bainekx-Execute").

**Display rule** (Claude's call; replaces `Grudge.Short` for display):
1. If the part before the first hyphen has a space, show that part: "Charkoalz Rogue".
2. Otherwise, if something follows the hyphen, show the two parts joined by a space: "Savage-Druiduser" shows as "Savage Druiduser".
3. A trailing hyphen alone is dropped: "Xaryu Forever-" shows as "Xaryu Forever".

Realm ids are never shown. Today's `who` line appends one when it differs from `GetNormalizedRealmName()`, which is empty on Forever, so today every realm id shows.

**Open for the build:** both key forms can exist for one player. `Grudge.Find` matches case-insensitively, but not across a space and a hyphen. Normalising the keys means migrating saved data, so it needs Joe's agreement first (see `CLAUDE.md`, Upgrades).

## The spread

The tab strip has five tabs, each 92 game units wide: Campaigns, Grudges and Ledger left of the title plate, Settings and Warpath right of it, with Grudges raised. Draw it with `ledger/lbase.py` `tabs()`. The book has no Share button and no page arrows on this tab, and no folios (the tab doesn't page; Claude's call).

### Left page: the grudges

| Element | Face, size, colour | Position (render px) |
|---|---|---|
| Heading "Grudges" | Morpheus small caps 25, rubric, 1 px shadow; the canon's ornament under it (rules and a gilt diamond), half-width 110 | centred on CX, y 120; ornament y 133 |
| Summary kicker: "Eleven grudges held · settled six times this week" | Friz 12, capitals, letterspaced 1.2, faded; a short rubric rule (55%) each side, 18 px long, 12 px from the text | centred on CX, y 158 |
| Inset sheet | the canon's pasted sheet: parchment blended 30% toward (240,208,146), soft shadow (60,30,10) offset 2,3 and blurred 3, 1 px edge (130,84,40), no stack, faint paste marks at the corners | x 72–518, y 176–652 (top) |
| Column legend "slew · fell" | EB Garamond Italic 14, faded | right-aligned at x 494, y 194 |
| List window | rows scroll inside it; rows fade over 16 px at an edge only while more lies beyond that edge | x 74–516, y 197–649 |
| Row | 46 px tall; the first row's top is at y 213 when unscrolled | see below, relative to the row's top `y` |
| Class tile | 26 px: red tile, a 1 px dark edge (60,30,10), a gold rim (176,128,52), red ground (110,16,10), the class icon inset 2 px. **Bevelled gold tile** when settled lately. Unknown class: an empty red tile with a gilt "?" in Morpheus | x 84, top y+8 |
| Name | Friz 18, N2 | x 120, y+22 |
| Level | Friz 15, Level colour | 6 px after the name, y+22 |
| Sub-line: last seen ("Hillsbrad Foothills, 20 minutes ago" / "not seen since Nov 19"), plus "· added automatically" when auto | EB Garamond Italic 15, faded; **rubric** when the sighting is under an hour old | x 120, y+39 |
| Tally | slew in **EB Garamond Bold 19, ink, faux bold**; "·" in Garamond Italic 17, faded, 6 px either side; fell in Garamond Bold 19, **rubric**, faux bold. "no blood yet" in Garamond Italic 15, faded, when both are 0 | right-aligned at x 494, y+22 |
| Row rule | 1 px, faded at 16% | x 120–494, y+45; none under the last row |
| Settled lately | the gilt band behind the row | x 76–498, y to y+44 |
| Chosen | the chosen wash and hairlines, **plus the ribbon bookmark**: a crimson ribbon end lying across the sheet's left edge with a V notch. Edge (46,6,4), fill (146,24,14), a lit line (206,72,48) along its top. Hidden when the row is scrolled out | wash x 76–498, y to y+44; ribbon x 63–77, y+4 to y+40 |
| Scroll bar | the canon's: a cord 2 px wide in (110,30,18) at 40%; the thumb rounded, 8 px wide, at least 22 tall, fill (146,24,14), edge (46,6,4), a lit line (206,72,48) | cord x 509, y 203–643; only when the list overflows |
| "Inscribe a name..." | the game's red `UIPanelButtonTemplate`, Friz 15, gold label | 170 × 22, centred on CX, top y 676 |

### Right page: the chosen grudge, then every encounter

| Element | Face, size, colour | Position (render px) |
|---|---|---|
| Portrait tile | 64 px: a red tile, or the bevelled gold tile when settled lately; the class icon inset 2 px; the "?" tile when the class is unknown | x 769–833, top y 92 (20 px below the page's top edge; Joe: "a bit more margin from the page edge") |
| Name | Morpheus small caps 31, rubric, 1 px shadow. **Long names step down 1 size at a time to 25 to fit 411 px**; WoW names are at most 12 + 12 letters (Claude's call) | centred on RCX, y 192 |
| Ornament | the canon's, half-width 120 | y 209 |
| Who: "Level 60 Human Rogue · <Stormwind Guard>" / "Class unknown" | EB Garamond Italic 18, faded | centred, y 233 |
| Held-since kicker: "Held since Saturday, November 21" (", added automatically") | Friz 12, capitals, letterspaced 1.2, faded; rubric rules 24 px long | centred, y 254 |
| Account: "Lethality slew them", "They slew Lethality", "Settled", "Last seen" | labels in Friz 18, ink; a 1 px ink hairline leader at 38%, from 10 px after the label to 10 px before the value; values in **EB Garamond Bold 21, rubric, faux bold**. **A zero reads "none"** (as The Reckoning's "Lethality fell: none"). The Last seen value is EB Garamond Italic 18, ink ("not since Nov 21" when never seen). "Lethality" is the character's name | labels x 616; values right-aligned at x 986; y 284, 310, 336, 362 |
| Note | the note in curly quotes, EB Garamond Italic 18, ink. Empty: "Click to write a note about them..." in Garamond Italic 17, faded. A 1 px faded rule at 30%, 380 px long, under it. Click to edit, as today | centred, y 394; rule y 400 |
| Heading "Encounters" | Morpheus small caps 21, rubric, shadow; ornament half-width 90 | centred, y 428; ornament y 441 |
| Inset sheet | the same sheet | x 576–1025, y 446–662 (top) |
| Log window | scrolls inside the sheet; the same edge fades and crimson scroll bar (cord at x 1016) | y 449–659 |
| Day heading: "Today", "November 26" | EB Garamond Italic 16, faded; a 1 px faded rule at 30% from 8 px after the text to x 1001, 4 px above the baseline | x 586; it takes one 23 px slot like an entry, its baseline 3 px down the slot (first heading y 470, first entry y 490). Was 18 px above the next entry: in game (3.8.5-test4) that touched the line above (Claude's call) |
| Entry line | 23 px a line | relative to the line's baseline `y`: |
| · glyph | 12 px, centred at (593, y−5). `d` a skull in rubric; `k` a gilt diamond; `s` an eye in faded ink; `g`/`a` a quill nib in faded ink | |
| · time | Arial Narrow 15, faded ("21:10") | x 606 |
| · line | Friz 16, ink, with the foe's name in N2: "Fell to **Wreckless Dawnmere**", "**Wreckless Dawnmere** sighted", "Inscribed **Savage Druiduser**", "**Elowen Starfall** added automatically". **A settling: "SLEW" in Morpheus small caps 15, rubric, shadow (the canon's raised rare part), then the name** | x 644 |
| · zone | EB Garamond Italic 15, faded; none for `g`/`a` | right-aligned at x 1001 |
| · settling | the gilt band behind the line | x 580–1005, y−17 to y+6 |
| · the chosen grudge's lines | **the chosen wash and hairlines** (R2a, Joe's pick) | x 580–1005, y−17 to y+6 |
| "Waypoint to last sighting" | red `UIPanelButtonTemplate`, Friz 15; greyed (disabled) when the grudge was never seen | 200 × 22, x 592, top y 676 |
| "Forgive" | red `UIPanelButtonTemplate` | 110 × 22, x 901, top y 676 |

## Behaviour

- **Sort** (as today): last seen first (`r.seen.t`, otherwise `r.added`), ties by full name.
- **Choosing:** click a row to choose it, with today's sound. The first grudge is chosen by default.
  - Clicking a foe's name in the encounter log also chooses that grudge, and scrolls the list to it (Claude's call).
- **Hover:**
  - A list row gets the chosen wash at half strength (8%), with no hairlines and no ribbon.
  - A name, in the list or in the log, shows a GameTooltip, as the canon allows for names:
    - First line: the name, in the game's own class colour.
    - The who line.
    - "Slain N times · fell N times · settled N times".
    - Last seen.
    - The note, if there is one.
  - The account's "Last seen" value shows the same tooltip, with the coordinates.
- **Scroll:** the mouse wheel over either sheet scrolls it. The list moves one row (46) per notch; the log moves one line (23) per notch. Each scroll bar can be dragged.
  - The top edge fades only once scrolled; the bottom edge fades only while more lies below.
  - The sheets never change size ("No shrinking").
  - A list that fits shows no scroll bar.
- **The global log:** every grudge's `r.log` entries, merged and sorted newest first under day headings.
  - Each grudge keeps 30 entries, so the log holds up to 30 × the grudges held.
  - A grudge with no `g` or `a` entry (from before the log existed in 3.5) gets one "Inscribed" line, dated `r.added` (Claude's call; Lethality's Dizz Zz and Charkoalz Rogue need it).
- **Note:** a click puts the text in an EditBox (`SetMaxLetters(120)`). Enter or losing focus keeps it; Esc cancels. Its hint shows only while it's empty (today's behaviour).
- **Forgive:** today's confirmation popup. The grudge leaves the list and its lines leave the log. The next grudge is chosen.
- **Waypoint:** as today (`Waypoint(s.z, s.x, s.y, ...)`), disabled when there's no `r.seen`.
- **Preview mode** (`view.preview`): `SAMPLE_GRUDGES`, with Forgive, Waypoint, the note and Inscribe disabled, as today. Give the samples First Last names.

### Empty and sparse states

- **No grudges at all** (`final_empty`, layout E1; Joe: "Typset for when no grudges are held should be better", then "E1"):
  - Heading "Grudges" and the kicker "No grudges held", as usual.
  - **Left page: no list sheet.** With nothing to list, the page is set as prose on the parchment itself (Claude's call; an empty sheet looked like a list that had failed to load).
    - The prose, in Friz 18, ink, 22 px leading, wrapped to x 92–500, with the canon's sunk drop cap (Morpheus, rubric, three lines, the lines tucked to the L's stem): "Lethality held no grudge. No foe had yet done enough to be remembered by name, and the pages that follow stood empty, waiting." "Lethality" is the character's name. First baseline y 262.
    - The canon's ornament, half-width 70, centred on CX, 16 px under the last line.
    - Centred on CX, in EB Garamond Italic 18, faded, 22 px leading: "Target an enemy and click the skull / on the war table, or inscribe a name below." Then a 12 px gap, then "A foe who kills you again and again / will be offered to you." The first line sits 58 px under the prose's last line. The last two lines show only while grudge offers are on (`cfg.grudge.auto ~= "off"`); with "add", they read "…will be added for you." (Claude's call.)
    - "Inscribe a name..." stays at the left page's foot.
  - **Right page:**
    - The portrait's place is kept as an empty blind-tooled square, 64 px at x 769, top y 92: parchment blended 18% toward (150,100,50); a pressed edge, dark (90,56,24) at 55% top and left and lit (255,236,190) at 50% bottom and right; a small gilt diamond (radius 4) at its centre.
    - "No Name Yet" in Morpheus small caps 25, **faded** (not rubric: nothing is there yet), centred, y 192, with the ornament (half-width 120) at y 209.
    - Centred, in EB Garamond Italic 18, faded, at y 250, 272 and 294: "When a name is set down, / its account is kept on this page: / the blood between you, and where it was last seen."
    - The Encounters heading at y 428 and its sheet at y 446–662, with "Nothing yet." in Garamond Italic 17, faded, centred in the sheet.
    - Waypoint and Forgive are hidden.
- **A grudge with no blood yet** (`final_real`): its row reads "no blood yet". The account reads "none", "none", "none". There's no gilt.
- **A grudge never seen:** the sub-line and the account read "not seen since <date>" / "not since <date>", and Waypoint is greyed out.
- **A grudge with nothing known** (`final_real_unknown`): the "?" tile; the name in plain ink without a shadow; "Class unknown" as the who line; no level.
- **A grudge with no encounters yet:** it still has its "Inscribed" line in the log, so the log is never empty while a grudge is held.

## What it needs in the game (check on Forever)

- **Class icons: open.** Joe wants the real Blizzard class icons, from the client's own files (never art from websites). Two candidates:
  - `Interface\Icons\ClassIcon_<CLASS>`: square, which suits the tiles.
  - `Interface\TargetingFrame\UI-Classes-Circles` with `CLASS_ICON_TCOORDS`: round.

  `tools/out/design/grudges/_runlines.txt` is three `/run` lines that draw both rows in game. Joe's screenshot will show which exist and give the renders the real icons. Every icon in the renders today is a stand-in.
- **Font strings** (one font and one shadow each):
  - **List row:** the name, the level, the sub-line, kills, the dot, deaths (or "no blood yet").
  - **Account row:** the label and the value.
  - **Log line:** the time; the verb before the name, the name and the verb after it, placed with `GetStringWidth`; "SLEW" as small-caps runs; the zone.
  - **Small caps:** one string per letter run, as in the canon.
  - **Faux bold:** the string drawn twice, 1 px apart.
- **Pools:** the list needs about 11 row frames (9.5 visible); the log needs about 10 line frames (9 visible). Use a FauxScrollFrame as today, with day headings taking a 23 px slot so every slot is the same height (built: the log is on the kit's sheet, every row on one 23 px grid from y 467).
- **Textures:**
  - Tiles, washes, bands, rules, the sheet and the ribbon are `SetColorTexture` solids, as the Campaigns page builds them.
  - Fading bands need `SetGradientAlpha`, or `SetGradient` with `CreateColor`; check which exists on 1.60.1. The fallback is stepped solids.
  - The bevelled gold tile is the Campaigns honour tile.
  - The ribbon's notch is two triangles, a small texture, or the ribbon left square-ended.
  - The glyphs: the skull can be the game's `Interface\TargetingFrame\UI-TargetingFrame-Skull`, and the eye a small addon texture or an atlas if one exists. Verify both.
- **Fonts:** Friz, Morpheus and Arial Narrow are the game's own. EB Garamond Italic and Bold are bundled once for the whole book (canon; ask Joe before downloading).
- **APIs already in use:** `UIPanelButtonTemplate`, `FauxScrollFrameTemplate`, the EditBox, `GameTooltip`, `StaticPopup_Show` and `Waypoint`.

## Claude's calls (each can be vetoed)

- **Gilt** marks a grudge settled in the last 7 days (the gold tile and band) and each settling in the log (the band, the diamond and "SLEW"). Nothing else on the page is gilt.
- **The chosen grudge:** a cool, flat wash between rubric hairlines, with a ribbon bookmark. Today it's a crimson wash and a diamond.
- **Colours:** your kills are in ink and theirs in rubric. Today's green isn't in the canon palette.
- **The summary says settlings as times** ("settled six times this week"). It's the same count as today, worded so it agrees with the per-grudge gilt.
- **Buttons:** "Inscribe a name..." moves to the left page's foot; Waypoint and Forgive to the right page's foot.
- **The legend "you · them"** becomes "slew · fell" at the sheet's top right.
- **Realm ids are never shown**, and names are shown as First Last (see Names).
- **Zeros read "none"** in the account.
- **An "Inscribed" line** in the log for grudges from before the log existed.
- **A sub-line in rubric** when the foe was seen within the hour.
- **Long names step down in size** in the portrait title only.
- **Clicking a name in the log** chooses that grudge.
- **No folios** on this tab.
- **The no-grudges page:** its wording, no list sheet, and "No Name Yet" in faded ink.

## Wording: "ledger" for grudges

The page is "Grudges", and "Ledger" is now another tab, so the word goes everywhere a player meets it for grudges. Claude's proposal; Joe: "Wording suggestions okay." The Settings note matches the Settings spec.

| File:line | Today | Proposed |
|---|---|---|
| `Chronicle.lua:637` | The Ledger of Grudges (page title) | Grudges (settled) |
| `Chronicle.lua:1200` | Forgive %s?
Their name is struck from your ledger. | Forgive %s?
Their name is struck off. |
| `Grudge.lua:86` | X is already in your ledger of grudges. | you already hold a grudge against X. |
| `Grudge.lua:111` | you forgive X. Their name is struck from your ledger. | you forgive X. Their name is struck off. |
| `Commands.lua:157` | X is already in your ledger. /warpath grudge forgive to strike them out. | you already hold a grudge against X. /warpath grudge forgive to strike them off. |
| `Commands.lua:532` (help) | strike a grudge from your ledger | forgive a grudge and strike the name off |
| `Commands.lua:533` (help) | your ledger of grudges (book, or chat) | your grudges (book, or chat) |
| `Hud.lua:136` | X is already in your ledger. Right-click the skull to open it. | you already hold a grudge against X. Right-click the skull to see your grudges. |
| `Hud.lua:138` | target a player to hold a grudge against them. Right-click the skull to open your ledger. | target a player to hold a grudge against them. Right-click the skull to see your grudges. |
| `Hud.lua:148` (tooltip) | X is in your ledger | You hold a grudge against X |
| `Hud.lua:153` (tooltip) | Right-click: open your ledger | Right-click: open your grudges |
| `Options.lua:210` (Settings note) | Killing a grudge settles it. A name leaves your ledger only when you forgive it, on the Grudges tab. | Killing a grudge settles it. A name is struck off only when you forgive it, on the Grudges tab. |

Not covered here:
- The welcome text (`Chronicle.lua:979`, "your ledger of grudges") is replaced by the Warpath spec, and its new wording doesn't use the word.
- Code comments (`Grudge.lua:2-3`, `Chronicle.lua:595`, `Hud.lua:85`, `Map.lua:240`) and the frame name `WarpathChronicleLedger` (`Chronicle.lua:669`) aren't seen by players. Rename them when building, to avoid confusion with the Ledger tab's code.
- Old release notes in `NEW_IN` and `CHANGELOG.txt` stay as written.

Lines quoted 2026-11-27; check them against the code when building.

## Open

- **Class icons:** waiting on Joe's screenshot of `_runlines.txt`. When it arrives, crop the real icons into the renders and record which texture exists.
- **Name keys:** whether to merge "First Last" and "First-Last" keys in saved data. This is a migration, so Joe's agreement comes first.
