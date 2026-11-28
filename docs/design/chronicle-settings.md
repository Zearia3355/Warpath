# Chronicle design: the Settings tab

The Settings tab, redesigned to match the Campaigns page (`chronicle.md`, the canon). **Settled by Joe on 2026-11-27 ("Settled").** Built on 2026-11-28 in `Options.lua` (`SPEC`, `SECTIONS`, the page's geometry `G`), placed by `BuildSettingsPages` in `Chronicle.lua`; see "Calls made while building" at the end.

At build time, `Options.lua`'s SPEC and SECTIONS strings change to the wording below. Five changes are behaviour, not wording; they're listed under "Behaviour changes".

## Joe's picks, in order

1. Round 1 (directions A–D): "Explore C further." Also: "C left page. The underline can be stronger." and "C right page, but the frame extends a little too close to the right side where the tome pages stack."
2. Round 2 (C1–C3): "C2 with the underlining from both C1 and C3."
3. Then: "Mockup each setting page now and confirm with your orchestrator that the design you've mocked up contains the real settings we need." The coordinating session confirmed nothing was missing.
4. From the Ledger session: five tabs, "Tabs look okay". The Grudges tab is just "Grudges" ("Grudges tab should just be 'Grudges' no?").
5. Clarity check: the wording below (clarity.md, reviewed by the coordinating session). Then Joe added:
   - "Corpse runs, fligths, and spirit healers, should probably all be independent settings"
   - "guildmates pins should go as a sub-setting under kills and death pins like we did with battle haze"
   - "the sub settings should be slightly smaller to help indicate hierarchy"
   - "Screenshots right page can be typeset much better"
6. Guild sharing off: Joe suggested removing the pins so the map's guild rows can be greyed. Claude recommended hiding instead; Joe: "Hide, keep the data."
7. Screenshots: "S2, real representative images or its a no-go. note that if we ever update the overlays we have to update this setting too. This really applies to all the UI too." Then: "One large preview."
8. "Settled."

## Final renders

All in `tools/out/design/settings/`. Each has an `_ingame` version at 1.175×. Judge them there.

- `settled_alerts.png`
- `settled_map.png`
- `settled_guild.png`
- `settled_shots.png`
- `settled_zones.png`
- `settled_grudges.png`
- `settled_map_sharing_off.png`: Guild sharing off, with the guild rows greyed.
- `settled_shots_hover.png`: hovering "Caption strip".
- `final_states.png`: main-row control states. Sub-rows follow the same states at their smaller size.

Generator: `settled.py`, run from that folder. It uses `r4.py`, `r5.py` and `r6.py`, which build on `prop.py`, `final.py`, `c2.py`, `dirs.py` and `sbase.py`. The book art is `type/bare.png` (refine.py R1); the tab strip is `ledger/lbase.py` `tabs()`. Fit checks: `overcheck.py`, and the measurements below. Each round's notes are in `settings-directions.md`; the wording audit is `clarity.md`.

## Units and colours

Positions are in **render px** on the book art (1092×748), like the rest of the canon. The game frame is 880×580 at about **1.2 render px per game unit**.

| Page | Game x from the page's left edge | Game y from the page's top |
|---|---|---|
| Left | (render x − 42.1) / 1.2 | (render y − 62) / 1.2 |
| Right | (render x − 548.1) / 1.2 | (render y − 62) / 1.2 |

Font sizes convert the same way. Text columns: left page L0 = 82 to LR = 510 (centre CX = 296); right page R0 = 586 to RR = 1017 (centre RCX = 801). Every y below is a text baseline.

Colours, from the canon: Ink (46,28,10), Faded (77,56,31), Rubric (122,31,15), Rubric shadow (70,12,6). Grey for a setting that can't change right now is (133,115,87), `GREY` in `Chronicle.lua`. No gilt on this tab: nothing here is rare.

## Tab strip

Five tabs, each 92 game units wide (110 render px). Campaigns, Grudges and Ledger sit left of the title plate; Settings and Warpath sit right of it. Settings is raised on this tab. The Ledger page's spec is the source for the strip.

## Left page: the sections

| Element | Face, size, colour | Position |
|---|---|---|
| Heading "Settings" | Morpheus small caps 25, rubric, shadow | centred on CX, y 120 |
| Ornament | the canon's rubric ornament, half-width 110 | y 133 |
| Subline "Shared by all your characters. Changes apply at once." | EB Garamond Italic 17, faded | centred, y 164 |
| Six section rows | | first at y 228, every 70 |
| Section name | Morpheus small caps 21: ink; rubric with shadow when open | x L0+18 = 100 |
| Section description | EB Garamond Italic 16, faded, one line | x 100, y row+22 |
| "/warpath help lists every command." | Arial Narrow 15, faded | centred, y 668 |
| Folio "— xi —" | EB Garamond Italic 17, faded | centred, y 694 |

**The open section:**
- **Wash (C2):** rubric at 12%, from x 70 to 516 and y row−28 to row+32, fading over 60 px at each end.
- **Chevron:** a rubric chevron pointing right, 8×12, its centre at (L0+4, row−7).
- **Bar (C3):** a rubric bar 3 px thick at 90%, at y row+4 to row+6. It runs from x 100 to the name's end + 6 and ends in a rubric diamond, radius 4, at (name end + 12, row+5).
- **Rule (C1):** a solid rubric rule, 2 px at 85%, from x 100 to LR, at y row+34 and row+35.

**Hovering a closed section:** a warm wash (150,90,30) at 8%, the same band. A click turns to that section with the page-turn sound.

## Right page: layout

| Element | Face, size, colour | Position |
|---|---|---|
| Heading (section name) | Morpheus small caps 25, rubric, shadow, then the ornament | centred on RCX, y 120; ornament at y 133 |
| Inset sheet | the canon's pasted sheet: parchment blended 30% toward (240,208,146), soft shadow (60,30,10) offset 2,3 and blurred 3, a 1 px edge (130,84,40), no stack. Pulled in from the page stack (Joe) | x 576 to 1009, y 152 to 650 |
| Controls column | | x0 = 586 to x1 = 999; first row at y 184 |
| Topic | Morpheus small caps 17, rubric. A double rule runs from the text's end + 10 to x1: 1 px at 50% at y−6, and 1 px at 25% at y−3 | x0. 6 px extra above every topic but the first; the topic takes 30 |
| **Main check** | the game's check, 24 px. Label in Friz 17, ink; hint in EB Garamond Italic 16, faded, wrapped, 17 px leading, at label x, y+19 | box at x0, label at x0+32; advance 29, plus the hint's lines |
| **Main layer row** | check 22 px; label Friz 17; inline hint in Garamond Italic 15, faded, 8 px after the label | box at x0, label at x0+30; advance 25 |
| **Sub-setting** (any indented row; Joe: smaller, to show hierarchy) | check 18 px; label Friz 15; hint Garamond Italic 15, 16 px leading | x0+26, label at +24; advance 23 (layer) or 25 plus hint lines (check) |
| Main radio row | label EB Garamond Italic 16, faded, in a 98 px column (or label width + 10). Game radio 16 px; choice in Friz 16, 19 px after the button's left edge. **Chosen: rubric, faux bold** | 10 px between choices; advance 29 |
| **Sub radio row** | label Garamond Italic 15; radio 14 px; choices Friz 15, 17 px after the button | x0+26; advance 24 |
| Pair ("On screen" / "In chat") | two main checks | x0 and x0+190 |
| Slider "Map icon size" | label Friz 17, ink; the game's slider from x0+140 to x0+330; value EB Garamond Bold 19, rubric, faux bold, 14 px after the track | its row takes 30 (+6 above) |
| Ink note ("When one player has killed my characters:") | Friz 17, ink | x0; advance 28 |
| Faded note | EB Garamond Italic 16, faded, wrapped, 17 px leading | x0 (+26 when indented); advance 26 |
| "Restore defaults" (Claude's call) | Arial Narrow 15, ink, with a rubric diamond (radius 3) 9 px before it; on hover, rubric and underlined. The confirm popup stays | right-aligned at RR−2, y 694 |
| Folio "— xii —" (Claude's call) | EB Garamond Italic 17, faded | centred, y 694 |

**Fit** (render, Candara standing in for Friz):

| Section | Content ends at y (sheet bottom 650) |
|---|---|
| Map | 645 |
| Alerts | 633 |
| Zones | 610 |
| Grudges | 556 |
| Screenshots | 556 (its ledger line is at 628) |
| Guild | 360 |

Every right-page text ends by x 999, against a limit of 1001.

**Risk:** Friz is a little wider than the stand-in, so Map and Alerts may gain a wrapped line in game. The `SettingsTab` test must stay green. If one fails, trim that section's hint wording; don't shrink the type.

### Screenshots: its own layout (Joe: S2, then "One large preview")

- **"Screenshot my kills":** a main check with its hint.
- **"Which kills":**
  - Two stacked choices, one per line: game radio 16 px, name in Friz 17 (rubric, faux bold when chosen) at x0+22.
  - "Notable only" has its explanation under it in Garamond Italic 15, 16 px leading.
  - 30 px between choices with no explanation.
- **"Caption":**
  - The three names on one row: radio and Friz 16, 22 px apart.
  - Under them, **one preview of the caption**, the sheet's width (409×124 render px), with a 1 px ink edge.
  - Hovering a name shows that caption in the preview, with a warm wash on the name. The chosen one keeps its radio and rubric.
- **The ledger line "Pictures taken ……… 22":** Friz 17 label, hairline leader, value in EB Garamond Bold 21, rubric, faux bold. It's at the sheet's foot, y 628.
  - Claude's call: it's a new figure on this page, from `gdb.shotCount`.

**The preview must be real** (Joe: "real representative images or its a no-go… if we ever update the overlays we have to update this setting too. This really applies to all the UI too.").

- **Build:** draw the caption with the same code that draws it on screenshots. Refactor `ShowTextCard` and `ShowStripCard` (`Record.lua` 449, 482) so they can build into a given parent at a given scale. Lay that over a captionless background picture. The preview then changes whenever the overlay does.
- **The background can't ship as a screenshot.** A screenshot of the game world is Blizzard's art, and `CLAUDE.md` forbids shipping it; the Warpath page's spec reached the same conclusion for its map. The mock's crops (`shots/wide_{text,strip,none}.png`, from Joe's test shots `WoWScrnShot_112726_172126` / `_172109` / `_172115`, box (1000,180)–(1560,350) of 2560×1440) are design references only. They never ship. The backdrop has to come from the client at run time. **Joe's pick is (a):**
  - **(a) A client texture at run time. Joe picked this: "(a) Loading screen".** a loading-screen image (`Interface\Glues\LoadingScreens\…`) or zone map art, cropped with `SetTexCoord` to a strip of landscape. It's cheap and static, and it's real game art drawn by the client. Check on Forever that the path exists and loads from an addon.
  - **(b) A live 3D scene:** a `PlayerModel` (or `ModelScene`, if it exists on 1.60.1) showing the player's own character, with the real caption over it. It's the most like the player's own pictures, but heavier, and the camera framing needs tuning.
  - **(c) A neutral dark backdrop:** the least representative option.
- **The caption** on any of these is drawn by the real card code, so it never needs redoing by hand. Nothing in the preview is a static image of Warpath's own UI, so there's no "redo these images" step. If a later build does use a static image of a Warpath overlay, `Options.lua` and this spec must say it is redone whenever the kill cards change.
- **The same rule holds for any future UI** that shows another part of Warpath: build it from the real code, over client art loaded at run time.

## Final wording

Section list (left page):

| Section | Description |
|---|---|
| Alerts | What happens when you kill, die, or walk where you've fought |
| Map | What the world map shows, and for how long |
| Guild | Your war shared with guildmates, and theirs with you |
| Screenshots | Kill screenshots and their captions |
| Zones & panels | Zone stats, the war table, the minimap button, this book |
| Grudges | Grudge alerts, and making grudges |

Sub-settings are marked "sub".

**Alerts**
- *Topic:* Your kills and deaths
- Check **Announce on screen**: "Banners at the top of the screen for kills and grudge sightings; big text for multi-kills, streaks and ground warnings."
  - sub radios **Big text size**: Small · Medium · Large (greyed while Announce is off)
- Check **Kills and deaths in chat**: "One line each, worded as your guild sees it. With this and Announce on screen both off, a kill still gets a short line."
- *Topic:* Sound
- Check **Play sounds**: "For kills, dangerous or contested ground, grudge sightings, and this book's pages."
- *Topic:* Ground you've fought on
- Note: "When you walk where you've fought before, Warpath says what it's been for you: your hunting ground, contested, or dangerous. On screen needs Announce on screen; without it, the warning goes to chat."
- Pair **On screen** / **In chat**
  - sub radios **Warn after**: 1 fight · 2 fights · 3 fights (greyed while both are off)

**Map**
- Check **Show Warpath on the world map**: "Same as the crossed swords on the map. Warpath keeps recording either way."
- *Topic:* Layers
  - **Battle haze**, "where fighting happened"
    - sub **with guildmates' fighting**
  - **Roads**, "the ways you travel most"
  - **Today's trail**
    - sub radios **kept for**: 15m · 30m · 1h · 4h · 12h · 24h
  - **Corpse runs**
    - sub radios **kept for**: 1h · 6h · 24h · 48h
  - **Flights**, "the legs you fly most"
    - sub radios **kept for**: 1h · 6h · 24h · 48h
  - **Spirit healers**, "on their own zone's map"
  - **Kill and death pins**
    - sub **with guildmates' kills and deaths**
  - **Enemy sightings**, "the last 15 minutes"
    - sub **with guildmates' sightings**
- Slider **Map icon size** (25–200%)
- Each "kept for" row greys while its layer is off. The three "with guildmates' …" rows grey while Guild sharing is off.

**Guild**
- Check **Guild sharing**: "Works both ways: guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on. Never your trail. Off: theirs are hidden from your map, not deleted."
  - sub check **Share my battle haze**: "Sent to guildmates at login and when they ask, so their maps show where you've fought."
  - sub check **Guildmates' kills and deaths in chat**: "One line each. Their pins stay on the map either way."

**Screenshots**
- Check **Screenshot my kills**: "Saved to the game's Screenshots folder, one picture per burst of kills. /warpath shot test takes a test picture."
- *Topic:* Which kills
  - **Every kill**
  - **Notable only**: "A first kill of a player, grudges, avenged deaths, multi-kills and feats, streaks of 3, 5 and every 10, and anyone you've killed 5 or more times."
- *Topic:* Caption
  - **Floating text** · **Caption strip** · **None**, then the preview
- Ledger line: **Pictures taken** … *n*

**Zones & panels**
- *Topic:* Entering a zone
- Check **A line in chat with my history there**: "Kills, deaths, miles, sightings, avenged deaths, best streak, and how it ranks among your zones."
- Check **A line under the zone's name**
- *Topic:* Panels and buttons
- Check **War table**: "A small panel: enemies seen lately, dangerous ground nearby, and the skull for making a grudge."
- Check **Minimap button**: "Click opens this book; right-click opens Settings."
- *Topic:* This book
- Check **Last campaign's headline in chat at login**
- Check **Open this book at login**
- Note: "Both only when a new campaign starts (after two hours or more away) and the last one had fighting."

**Grudges**
- *Topic:* When I see a grudge
- Check **Announce it, with a sound**: "A banner and a sound. Follows Announce on screen and Play sounds on the Alerts tab."
  - sub radios **Again after**: 1 min · 5 min · 15 min
- Check **Show where on the map**: "Their crest and name, for 15 minutes."
- Check **Skull on their nameplate and target frame**
- *Topic:* Making grudges
- Ink note: "When one player has killed my characters:"
- Radios: Do nothing · Offer a grudge · Add one
- Radios **after**: 2 deaths · 3 deaths · 5 deaths (greyed on "Do nothing")
- Note: "Killing a grudge settles it. A name is struck off only when you forgive it, on the Grudges tab."

Outside this tab, "ledger" still names the grudge list in a few places. They're for whoever settles the Grudges wording:
- the forgive popup "Their name is struck from your ledger." (`Chronicle.lua`)
- `Grudge.lua`'s chat lines
- `/warpath help` (`Commands.lua`)
- the welcome text

## Behaviour changes (agreed with Joe)

1. **Corpse runs, Flights and Spirit healers become three layers** (Joe).
   - New keys in `C.LAYERS` and `C.LAYER_LABELS`, for example `runs`, `flights` and `spirits`. `Map.lua` gates flights (`DrawRuns`, kind "f") and `Spirits.Draw` on their own keys.
   - The map button's menu lists the same layers.
   - **Saved data:** an upgrade copies today's `layers.runs` into the two new keys, so nothing changes until the player changes it. Nothing is deleted.
2. **Guildmates' layer splits in two** (Joe for pins; sightings are Claude's call): "with guildmates' kills and deaths" under Kill and death pins, and "with guildmates' sightings" under Enemy sightings.
   - Today they're one layer, `shared`. Its value is copied into both new keys on upgrade.
3. **Guild sharing off hides guildmates' marks; it doesn't delete them** (Joe: "Hide, keep the data").
   - While `cfg.share` is off, the map draws no guildmates' pins (`z.gmarks`), sightings or haze (`z.guildBattle`).
   - The saved data stays and comes back when sharing is turned on.
   - The three "with guildmates' …" rows grey out, as their `when`.
   - Today, saved guild pins and haze keep drawing with sharing off.
   - Guildmates' deaths also stop counting toward dangerous-ground warnings while sharing is off (`DeathField`, `Warpath.lua` 605). Joe: "No, ignore them." The data (`z.guildDeaths`) is kept and counts again when sharing is turned back on.
4. **Trail, corpse-run and flight lengths move under their layers** and grey while that layer is off. The "Keep on the map for" heading goes. Same settings (`trailMin`, `runHours`, `flightHours`), new place and `when`.
5. **The caption preview** is drawn by the real card code (above).

Rejected:
- Greying the ground warning's "On screen" while Announce is off. It could silence warnings; the note explains it instead.
- Dropping the both-off chat fallback.

## Tests that change

- **`SettingsTab`:** the new rows and the smaller sub-rows. Every section must still fit, Map and Alerts most of all.
- **`NewIn`:** the release gets its `NEW_IN` lines for players.
- **Layers** (map drawing and the map button's menu):
  - `runs`, `flights` and `spirits` each hide only their own marks.
  - The guildmates' pins and sightings keys each hide only theirs.
  - The upgrade copies `layers.runs` and `layers.shared` into the new keys, and nothing is lost (`Upgrades`, `RealData`).
- **Guild sharing off:**
  - No guildmates' pins, sightings or haze are drawn, and their saved data is unchanged.
  - Guildmates' deaths don't count toward dangerous ground (`DeathField`, `Ground` checks). They count again once sharing is back on.
  - Each check is proven able to fail by putting the old behaviour back.
- **Greying (`when`):**
  - Each "kept for" row greys with its layer.
  - The three guildmates' rows grey with Guild sharing.
- **Caption preview:** it builds through the same `ShowTextCard` / `ShowStripCard` code as the screenshots, with no second copy of the card layout.

## Control states

| Control | On | Off | Hover | Disabled |
|---|---|---|---|---|
| Check (`UICheckButtonTemplate`, 24 / 22 / 18 px) | yellow tick | empty dark box | the template's highlight | the template's disabled tick; label and hint in GREY; `:Disable()` |
| Radio (`UIRadioButtonTemplate`, 16 / 14 px) | yellow dot; label rubric, faux bold | dark; label ink | the template's highlight | grey dot; labels GREY |
| Slider (`OptionsSliderTemplate`) | thumb on track; value rubric Garamond Bold | | the template's own | not used |
| Section row (left) | wash, chevron, bar and diamond, rule | ink name | warm wash at 8% | not used |
| Caption name (Screenshots) | radio, rubric | ink | warm wash; the preview shows it | GREY when "Screenshot my kills" is off |
| Restore defaults | | ink | rubric, underlined | not used |

**Keyboard:** none, as today; this client's checks and radios take no focus. Esc closes the book.

**Click area:** the whole label, not only the box. Checks get `SetHitRectInsets(0, -labelWidth, 0, 0)`, and radio labels are clickable too. Claude's call.

## What it needs in the game (check on Forever)

- **Templates already in use:** `UICheckButtonTemplate`, `UIRadioButtonTemplate` and `OptionsSliderTemplate` (with today's −/+ fallback). Smaller sizes are `SetSize` on the same templates; check that the tick art scales cleanly at 18 px.
- **The caption preview's backdrop:** for (a), check that a loading-screen texture path exists on Forever and that `SetTexCoord` crops it. For (b), check that `PlayerModel` / `ModelScene` exist on Forever.
- **Addon-shipped textures** (perhaps the sheet's shadow): Warpath has never loaded one. `glow.tga` has been in the repo since 3.3.5 and nothing uses it. Test with one `/run` that shows it before building on it.
- **Wash gradients:** check whether `SetGradientAlpha` or `SetGradient` (with `CreateColor`) exists on 1.60.1. Fallback: stepped solids.
- **Fonts:** Friz, Morpheus and Arial Narrow are the game's own. EB Garamond Italic and Bold are bundled once for the whole book (canon; ask Joe before downloading). Small caps are one string per letter run; faux bold is the string drawn twice, 1 px apart.
- **`SetHitRectInsets`** on CheckButtons.
- **`Chronicle.lua` already has the pieces:** `Diamond`, `Ornament` and the solid helpers. The chevron is the canon's fold chevron.

## Claude's calls (each can be vetoed)

- "Restore defaults" becomes a footer link, not a red button.
- Folios "— xi —" / "— xii —".
- "/warpath help lists every command." stays as small print on the left.
- The sheet's left edge is at R0−10, keeping the controls' width after the right edge moved in.
- Radio labels in EB Garamond Italic; the chosen radio's label in rubric faux bold.
- Main checks at 24 render px (20 game units; 22 today), layer checks 22, sub-settings 18.
- Whole-label click area.
- Guildmates' sightings get their own sub-row under Enemy sightings.
- "Pictures taken" ledger line on Screenshots.

### Calls made while building (2026-11-28; each can be vetoed)

Built in `Options.lua`: the tables above are its `G` (exposed as `ns.Settings.GEOMETRY`), and the `SettingsPage` tests check the built page against them. Where this spec's table and the settled generator differ, the page follows the generator, because the settled renders are what Joe approved.

- **Main-check hints are EB Garamond Italic 15 on 16 px leading** (the generator's `c_check`), not the 16 on 17 that the table above gives. The fit figures above were measured that way too.
- **Map's first hint is trimmed** to "Same as the crossed swords on the map. Warpath records either way." The design's italic stand-in is Monotype Garamond (`GARAIT.TTF`), which is narrower than the EB Garamond Italic that ships. In the real face the old wording wrapped to two lines and Map ended at 661, past the sheet. Now it ends at 645, as the table says. Guild gains one wrapped line (it ends at 376, not 360), which fits easily. Every other section ends where the fit table says.
- **The preview's backdrop** is `LoadScreenArathiBasin`, cropped to `SetTexCoord(0.1, 0.9, 0.36, 0.68)`. The crop is a guess until it's seen in game, and Warsong Gulch is a one-line change (`PREVIEW` in `Options.lua`).
- **The preview's kill** is the one `/warpath shot test` pictures: your name, class and zone, a 4th kill, ×3, now.
- **The preview's scale and position** come from the design's crop, as shares of the screen: box (1000,180)-(1560,350) of 2560×1440. The caption fills the same part of the preview at any resolution or UI scale. That is 0.73 at Joe's settings.
- **The hover wash on a caption name** is the generator's: (150,90,30) at 12%, from 6 px before the radio to 6 px past the name, fading over 8 px.
- **The click area** covers the label only, not the hint lines or a layer's inline hint.
- **Hovering a caption name previews it even while the row is greyed.** Only the click is disabled.
