# Chronicle: the Ledger tab

Settled with Joe on 2026-11-27 ("Settled"). The Ledger is a new chronicle tab: a detailed breakdown of a player's war, in seven spreads. It follows the canon in `chronicle.md`, which this file doesn't repeat. Nothing here is built yet.

## Where the work is

Everything is in `tools/out/design/ledger/`, which git ignores. Run the scripts from that folder.

- **The saved data:** `snapshot/`, one frozen copy of Joe's saved data. Every figure in the renders and in this file comes from it.
  - The characters and `WarpathGlobal` are as the game wrote them at 2026-11-27 13:40.
  - `snapshot/roster/` is `WarpathGlobal` at 17:13, after Joe's roster capture. Only its `roster` key is read.
  - `snapshot/WHEN.txt` records the dates.
- **Readers:** `dump.py` (a character's data shape), `stats.py` (every stat), `geo.py` (where each zone sits on the world map art).
- **Shared parts:** `lbase.py`. It holds:
  - the book, as `refine.py`'s art without Share or page arrows, plus the five tabs;
  - the canon's type, sheet and scroll bar;
  - class colours and stand-in icons for all nine classes and unknown.
- **Generators, in order:**
  - `directions.py`: L1–L4, round 1.
  - `round2.py`: S1.
  - `lround3.py`: P1–P7. It was named `round3.py`, renamed because `type/` has its own `round3.py`.
  - `round4.py`: Q1–Q7 and the toggle styles, TG.
  - `round5.py`: F1–F7, **the settled design**.
- **Notes:** `content.md` holds the content and saved-data decisions. `directions.md` holds every round, with Joe's words.

### Final renders

`F1.png`–`F7.png` and `F6x.png`, each with `_raw` and `_ingame` (1.175×). Judge at `_ingame`.

- `F1` The Tally | Records
- `F2` The Hours | The Calendar
- `F3` Classes Slain | Classes That Slew
- `F4` My Lands: map | the continent's lands and the chosen land
- `F5` Foes of Note | Who They Were
- `F6` The Wilds | Where the Wilds Strike. `F6x` is the same spread with **made-up** death causes, to show the page once causes are recorded.
- `F7` The Guild's War | The Guild's Lands

## Joe's decisions, quoted

- **Content:** "All of it, as proposed" (round 1); "Agree with 1-5", the spread plan (round 2); "Yes, all four", the extra recordings (round 2).
- **Several spreads:** "For the ledger, we don't need to impose a 2 page limitation." And: "The 2-page limitation really just applied to the campaign tab."
- **Tabs:** "Tabs look okay" (option A: five tabs of 92 px; Ledger third on the left).
- **Grudges keeps its own name:** "Grudges tab should just be 'Grudges' no?" The Ledger keeps "Ledger".
- **From L1–L4:**
  - "L3 left page is awesome."
  - "The hours page of L3 is the best."
  - "Days in the field isn't useful because we have /played."
  - "use real WoW class icons."
- **Honours page declined:** "Isn't honors kinda covered elsewhere, like in tally?"
- **Records:** "we'll need more interesting records."
- **Wilds:** "Don't be lazy on deciding what goes on this page."
- **Calendar:** "should probably go alongside the hours page."
- **Round 3:**
  - Calendar: "Say 1:0 or 3:2 for kills:deaths."
  - "The yellow highlight for most active doesn't work well with the page color."
  - Unknown class: "make the unknown entry a normal row ... use a '?' as the class icon."
  - Lands: "Should be a list of the zones of the selected continent."
  - Long lists: "framed scrolling section."
  - "remove kept from now on."
  - Guild list: "class colored names ... their level ... the guild note."
- **Round 4:**
  - "streaks should have an indicator of.. how to get the streak."
  - "'fastest triple kill' is a weird metric."
  - "maybe the Lands should be My Lands."
  - "Users name should be included in the list ... User should have an indicator."
  - Account toggle: "C3."
- **Data note:** "Plains killed me in Gurubashi arena - its fine." Deaths in free-for-all areas count as PvP deaths, as recorded.

## Layout rules (all spreads)

Positions are render pixels on the 1092 × 748 book, the frame of the Campaigns renders. Multiply by 0.806 for UI units (`W = 880`). The y values are baselines unless stated.

- **Left page:** x 82–510, centre 296. **Right page:** x 586–1017, centre 801.
- **Colours:** the canon's ink (46,28,10), faded (77,56,31), rubric (122,31,15).
  - **Deep rubric (96,14,8)** marks the single highest value on a page: the busiest hour, day of the week and calendar day. It's underlined in the same colour, and it replaces gilt here (Joe, above).
  - Gilt is not used on the Ledger.
- **Faces:** Friz, Morpheus, EB Garamond Bold and Italic, and Arial Narrow, as in the canon.
- **Page heading:** Morpheus small caps 25, rubric, with the 1 px shadow (70,12,6), then the ornament 13 px below it (half-width 110). Baseline y 120, unless a kicker sits above it (then y 140–142, kicker at 104).
- **Sub-heading inside a page:** Morpheus small caps 16 (lower-case letters at 0.76), rubric, with the shadow, then a faded hairline (alpha 0.3) running to the page's edge, 5 px above the baseline.
- **Column heads:** Friz capitals 10–11, letterspaced 1.0, faded, right-aligned over figures.
- **Reckoning rows:** as the canon's Reckoning, with three parts.
  - The label: Friz 16–17, ink.
  - A hairline leader: ink at 0.38, 1 px above the baseline, 10 px clear of both texts.
  - The value: EB Garamond Bold 18–19, rubric, faux-bold.
  - A value not yet counted reads "none yet" in EB Garamond Italic at the label's size, faded, with the leader at 0.25. "none" reads the same.
- **Figures in lists:** EB Garamond Bold 17–20, faux-bold. Rubric for kills, ink for deaths. A zero is an en dash in EB Garamond Italic, faded.
- **Bars:** an inked bar, 9 px tall, ending 3–5 px above the baseline. Rubric at alpha 0.78 for kills; for deaths, (70,46,22) at 0.55, or faded. Length is proportional to the page's largest value. The figure sits 26–28 px after the bar's end.
- **Names:** every foe and guildmate name follows the book's First Last display rule (`chronicle.md`; `chronicle-grudges.md`, "Names"): "Bainekx-Execute" shows as "Bainekx Execute", and realm ids never show. They're drawn in N2 class colour with a black 1 px shadow, then the level in Friz 3 pt smaller in the canon's level colour. Hovering a name shows the game tooltip (see Behaviour).
- **Class tile:** the canon's red tile, 22 px in lists and 30 px on the Classes page, with the class icon (see "What it needs in game"). Unknown uses the question-mark icon.
- **Sheets:** the canon's pasted sheet with the crimson scroll bar, and rows fading at its edges. The scroll bar appears only when the content is taller than the sheet. The sheet is a fixed size; it never shrinks.
- **Chronicler lines:** EB Garamond Italic 15–17, faded, centred, wrapping to the page less 30 px. They use the voice of `campaign-voice/chronicler.py`: numbers in words, third person, the character's name, no pronouns.

### Footer (every spread)

- **Arrows:** the game's page-turn arrows, from the Campaigns page, at (74, 676) and (995, 676).
  - Beside each, the name of the spread it turns to, in Friz 18, ink: at (106, 692) left-aligned, and right-aligned to 990.
  - Page 1 has no left arrow and page 7 has no right arrow. The pages don't wrap.
- **Page number:** "page N of 7" in Arial Narrow 15, faded, centred at (801, 694).
- **Account toggle (C3):** two of the game's red buttons (`UIPanelButtonTemplate`, the Share button's art), each 118 × 26, top-left at (250, 675) and (372, 675).
  - Labels: the character's name and "All characters", in Friz 14.
  - The chosen button is normal, with its label in gold (255,209,0).
  - The other button is desaturated and darkened (colour 0.35, brightness 0.55), with its label grey (150,150,150).
  - Where the account view doesn't apply (the Guild spread), "All characters" is disabled: same art, label (92,86,78), no click.
- **No Share button** on any Ledger spread.
- **Spread names beside the arrows:** The Tally, The Hours, The Classes, My Lands, The Foes, The Wilds, The Guild.

### Navigation

- The Ledger opens on page 1 the first time in a session.
- It reopens on the spread you left until a `/reload`. That's memory only (Claude's call).
- The mouse wheel scrolls the sheet under the cursor and never turns pages.

## The spreads

### 1. The Tally | Records (F1)

**Left: The Tally**
- **Kicker:** "THE WAR OF {NAME} · SINCE {MONTH DAY}" at (296, 104). The date is the earliest kill or death mark.
- **Heading:** "The Tally" at (296, 140).
- **Three great figures:** EB Garamond Bold 46, rubric, faux-bold, with the shadow.
  - Centred in thirds of the page, baseline 214.
  - Captions in Friz capitals 11, faded, at 234.
  - Rubric hairlines (alpha 0.35) between the thirds, y 182–240.

  | Figure | Caption | Definition | Source |
  |---|---|---|---|
  | 28 | `{ENEMY FACTION} SLAIN` | kills, lifetime | `db.kills` |
  | 27 | TIMES FALLEN | PvP deaths, lifetime | `db.deaths` |
  | 6 | BEST STREAK | most kills without a PvP death | `db.bestStreak` |

- **Rows:** reckoning rows from x 106 to 486, from y 266, 21 apart. Label Friz 16; value 18.

  | Row | Lethality | Definition | Source |
  |---|---|---|---|
  | Kill-death ratio | 1.04 | kills ÷ PvP deaths, two places; "—" with no deaths | `db.kills`, `db.deaths` |
  | Different foes slain | 16 | distinct victims | count of keys in `db.victims` |
  | Kills avenged | none | kills that avenged your own fresh death | sum of `z.avenged` |
  | Fell to the wilds | 34 | deaths not counted as PvP | death marks without `pvp` |
  | Miles travelled | 1,402.6 | walked, ridden and flown | `db.yards` / 1760 |
  | Enemies sighted | 1,696 | sightings | sum of every `z.sight` cell |
  | Screenshots taken | 22 | kill screenshots, account-wide | `WarpathGlobal.shotCount` |
  | Flights taken | none yet | **new**: flight-master flights started | `db.flights` |
  | Corpse runs | none yet | **new**: walks back to your body | `db.runs` |
  | Released at a spirit healer | none yet | **new**: resurrections taken at a spirit healer | `db.spirit` |
  | Miles walked as a ghost | none yet | **new**: distance of corpse-run strokes | `db.ghostYards` / 1760 |

- **Multi-kills**, a sub-heading at y ≈ 509. After it, in EB Garamond Italic 15, faded: "each within two minutes of the last".
  - Four columns across the page. Figures: EB Garamond Bold 20 at y + 30, rubric, or faded with a dash when zero.
  - Under each figure, the tier name in Arial Narrow 13, ink, or faded when zero. Under that, how it's earned, in EB Garamond Italic 13.
  - The tiers are Warpath's own (`Phrases.lua`): Double kill ("2 kills"), Triple kill ("3 kills"), Quad kill ("4 kills"), Bloodbath ("5 or more").
  - **Count:** each chain counts once, at the tier it ended on: tier n = marks with `mk == n` minus marks with `mk == n+1`, and Bloodbath is `mk >= 5`. Lethality: 2, 1, 0, 0.
- **Streaks**, a sub-heading about 58 px lower, with "kills without dying" beside it.
  - Five columns: Bloodthirsty ("3 in a row"), Rampage ("5 in a row"), Warmonger ("10 in a row"), Unstoppable ("15 in a row"), and Legend of the Warpath on two lines ("20 in a row"). These are `P.STREAKS`.
  - **Count:** every time a streak reached that title, i.e. kill marks with `streak == n`. Lethality: 4, 3, 0, 0, 0.

**Right: Records.** The heading is at (801, 120). From y 162, each record is a reckoning row from 600 to 1003 (label Friz 17, value 19). Under it, its detail in EB Garamond Italic 14, faded, at x 612, y + 17. Records are 44 apart, or 30 apart with no detail.

| Record | Lethality | Definition | Source |
|---|---|---|---|
| First blood | November 19 · Western Plaguelands, the foe unnamed | the earliest kill mark | kill marks, `[3]`, zone, `n` |
| Bloodiest night | 8 slain · Tuesday, November 24 | the campaign with the most kills | `db.campaigns` + `db.campaign`: `kills`, `start` |
| Most in one hour | 6 · Tuesday, November 24, from 19:09 | the most kills in any 60 minutes starting at a kill | kill marks' times |
| Longest streak | 6 · Duskwood, November 26 · screenshot #22 | the best streak, where and when it peaked | `db.bestStreak`; the kill mark with that `streak` (zone, `shot`) |
| Worst night | 4 fallen · Sunday, November 22 | the campaign with the most PvP deaths (ties: fewer kills) | campaigns' `deaths` |
| Smallest prey | level 28 · Isitin Mytruck, a mage of the High Order Skyborne, in the Wetlands | the lowest-level victim | kill marks' `lv`, `n`, `c`, `ra`, zone |
| Longest night | 15h 59m · Saturday, November 21 | the longest campaign | campaigns' `played` |
| Farthest ridden | 218.6 mi · Saturday, November 21 | the most miles in one campaign | campaigns' `yards` |
| Most enemies seen | 291 · in one night, Saturday, November 21 | the most sightings in one campaign | campaigns' `sightings` |
| Fastest revenge | none yet | the quickest kill avenging your own death, in seconds | kill marks' `av` |
| Closest call | shown once recorded | the kill at the lowest health of your own | **new** `m.hp` |
| Worst odds won | shown once recorded | the kill with most enemies to allies near, worded "at least 3 against 1" | **new** `m.odds` |
| Widest gap in levels | shown once recorded | the kill with the victim most levels above you | **new** `m.my` with `m.lv` |

- The three new records show only once they have a value. Joe: "remove kept from now on".
- Records from campaigns cover only the 30 campaigns kept (`C.CAMPAIGN_KEEP`).
- Each record's detail line is clickable where it names a campaign (it opens that campaign) or a screenshot (it shows the screenshot number in a tooltip).

### 2. The Hours | The Calendar (F2)

**Left: The Hours**, the L3 wheel. Heading at (296, 120).
- **The wheel:**
  - Centre (296, 296), radius 108. An ink ring at alpha 0.55, a second ring 3 px inside it at 0.25, and an inner ring at 0.42 × the radius.
  - 24 spokes clockwise from midnight at the top. Ticks are 7 px every 6 hours and 3 px otherwise.
  - Each hour with kills is a wedge from the inner ring outward, its length proportional to that hour's kills. Fill (140,40,20), edge (90,20,10).
  - The busiest hour is in deep rubric (96,14,8), edged (40,6,2). The wheel prints no figures on the wedges.
  - Labels: "midnight", "dawn", "noon", "dusk" in EB Garamond Italic 15, faded, 20 px outside the ring. Hour figures 3, 9, 15, 21 in Arial Narrow 14, faded, 16 px outside.
  - A rubric diamond marks the centre.
- **Days of the week:** "BY DAY OF THE WEEK" (Friz capitals 11) at (296, 478). Seven columns: day names (EB Garamond Italic 16) at 508; figures (EB Garamond Bold 19, rubric) at 532. The busiest day is in deep rubric, underlined 20 px wide.
- **Chronicler line:** two lines at 590 and 612: "{Name}'s blade is busiest at {hour in words}, / with {n in words} slain in that hour, and on {weekday}s."
- **Source:** the hour and weekday of every kill mark (`[3]`, local time). Lethality: busiest at 22:00 (6), on Thursday (10).

**Right: The Calendar.** Heading at (801, 120).
- **Month line:** "November 2026" in Morpheus small caps 19, ink, at (801, 162).
  - The game's page-turn arrows sit either side: 44 px left of the title's start and 17 px right of its end, top y 143.
  - Beside them, the months they turn to, in EB Garamond Italic 15, faded: "October" right-aligned before the left arrow, "December" after the right.
  - There's no arrow past the current month, or before the first month with a mark.
- **Grid:** day names (EB Garamond Italic 15) at 194, Monday first. Cells are 61.6 × 62 from y 202, with a faded hairline (alpha 0.22) above each week.
  - **Day number:** Arial Narrow 13 at the cell's top left. Ink when you were in the field that day (a campaign spanned it), faded otherwise. Today has a rubric ring.
  - **Fights:** "kills:deaths", centred at the cell's y + 44. Kills in EB Garamond Bold 21, rubric; the colon faded; deaths in EB Garamond Bold 19, ink.
  - The bloodiest day's kills are in deep rubric, underlined 28 px.
  - A day in the field with no fight shows a 12 px faded dash.
- **Under the grid:**
  - The key "kills : deaths. A dash: in the field, no blood." in EB Garamond Italic 15.
  - "{N in words} days of war in {Month}: {kills} slain, {deaths} fallen." in 16.
  - "The bloodiest night: {weekday, month day}, {n} slain ▸" with a rubric arrow. It opens that campaign.
- **Source:** kill marks and PvP death marks by local date; days in the field from campaign `start`/`stop`.
- **Limit:** marks are kept 300 per zone, so a very old month can be incomplete. The calendar never claims a total it doesn't have.

### 3. Classes Slain | Classes That Slew (F3)

The two pages are one table each, with headings at (296, 120) and (801, 120).
- **Rows:** 42 apart from y 170, ten in all: the nine classes and Unknown. Unknown is an ordinary row, with the question-mark icon.
  - Sorted by count, largest first. Ties are alphabetical, with Unknown last.
  - Each row has a 30 px class tile at (x0 + 2, y − 23).
  - The class name, plural, is in Friz 18 at (x0 + 42, y − 2): N2 colour with shadow, or faded when the count is zero. Unknown is always faded.
  - The bar starts at x0 + 190. Kills are in rubric; deaths are in (70,46,22) at 0.55. The figure is EB Garamond Bold 20.
- **Chronicler line:** under the table, in EB Garamond Italic 17. Templates:
  - "{Classes} have fallen most often to {name}'s blade, {n} of each."
  - "Most who struck {name} down went unseen; of those seen, {classes} struck {n in words} each." The first clause appears only when Unknown leads.
- **Sources:**
  - Slain: kill marks' `c`; unknown when absent. Lethality: Paladin 4, Shaman 4, Warrior 3, Hunter, Mage, Priest, Rogue 2 each, Druid 1, Warlock 0, unknown 8.
  - Slew: PvP death marks' `kc`. Lethality: unknown 17; Hunter, Paladin, Warlock 2 each; Druid, Priest, Shaman, Warrior 1 each.

### 4. My Lands (F4)

**Left: the map.** The heading "My Lands" is at (296, 120).
- **Continent buttons:** "Kalimdor" and "Eastern Kingdoms" (red buttons, 150 × 26) centred at y 140. The chosen one is lit, styled as the footer toggle.
- **The continent picture:** the continent's world-map art, inked as on the Campaigns route map (sepia, lightened 40%, so marks and labels read over it). It's scaled to fit the page (≤ 428 × 500), centred, top y 166, with soft rounded edges.
- **Marks on each land with a fight:**
  - Rubric (150,26,14) crossed strokes, 3 px wide, half-size 3 + min(4, (kills+deaths) ÷ 2).
  - Then the kills in EB Garamond Bold 16, rubric, and " · {deaths}" in EB Garamond Bold 15, faded.
  - The land's name in EB Garamond Italic 15, (58,32,10). It's placed below the mark, or above, left or right, whichever doesn't collide.
  - The chosen land has a rubric ring.
- **Key:** "slain · fallen. Choose a land to open its account." in EB Garamond Italic 15 at (296, 664).
- **Clicking:** a mark or label chooses the land.
- **Position of each land:** the client's continent rect for that zone (`C_Map.GetMapRectOnMap(zone, continent)`); the mark sits at the rect's centre. `geo.py` reproduces this on the world map art.

**Right: the lands and the chosen land.**
- **The continent's lands:** a sheet at (576, 104)–(1025, 300), scrolling.
  - Every land of the continent you've been in, sorted by kills+deaths, then by name.
  - Columns: the name in EB Garamond Italic 17 (ink if fought there, faded if not); kills right-aligned at 947 in rubric; deaths at 995 in ink. "KILLS" and "DEATHS" are column heads.
  - The chosen land has a rubric band (alpha 70 of 255, fading at both ends), and its name is in Friz 17 bold rubric. Clicking a row chooses it.
- **The chosen land's account:**
  - Its name as a heading (Morpheus 23) at (801, 340).
  - Three figures in EB Garamond Bold 38 at 404, with captions at 424: SLAIN HERE, FALLEN HERE, BEST STREAK.
  - Reckoning rows from y 460, 24 apart:

  | Row | Source |
  |---|---|
  | Different foes slain here | distinct `n` on the zone's kill marks |
  | Fell to the wilds here | the zone's death marks without `pvp` |
  | Miles travelled here | `z.yards` / 1760 |
  | Enemies sighted here | sum of `z.sight` |
  | Guildmates' kills here | `z.gmarks` with `kind == "K"` |
  | Corpse runs here | **new** `z.runs_n` |

  - Last, one line: "Slain most here {name} ×{n}", the name in N2 (Lethality: Kourne Bladeheart ×2).
- **Opens on:** the bloodiest land (kills+deaths) on the continent you're on. Lethality: Eastern Plaguelands, 8 · 1, best streak 5.
- **Sources:** `z.kills` (from kill marks), PvP death marks, `z.bestStreak`, as above.

### 5. Foes of Note | Who They Were (F5)

**Left: Foes of Note.** Heading at (296, 120). Two blocks: "Slain most" (y 162) and "Struck {Name} down" (after it).
- **Column heads:** FOE, GUILD, LAST, then SLAIN or TIMES.
- **Rows:** six per block, 26 apart.
  - A tile, then the name with its level, at x 114.
  - The guild in EB Garamond Italic 15, faded, at x 290, shortened with "…" to stay clear of the date.
  - The date of the latest one in Arial Narrow 14, faded, right-aligned at 466.
  - The count right-aligned at 510: rubric for slain, ink for times.
- **Sorting:** by count, then the latest first. Six is the cap; "of note" is the top six, so there's no sheet.
- **Sources:**
  - Slain: `db.victims` counts; class, level and guild from the latest kill mark with that `f`.
  - Struck down: `WarpathGlobal.killers` (account-wide) counts; class, level and guild from the PvP death marks' `kc`, `lv`, `gu`.
- **Grudges:** a name that's a grudge (`gdb.kos`) opens it on the Grudges tab when clicked.

**Right: Who They Were.** Heading at (801, 120). One sheet, (576, 146)–(1025, 668), scrolling, with three folding sections, all open by default.
- **Section line:** a rubric chevron, then the title in Morpheus small caps 16, as the Campaigns zone lines.
- **Their levels:** bars for 60, 51–59, 41–50, 31–40, 21–30, 1–20, then "unknown" as a faded figure. Source: kill marks' `lv`.
- **Their races:** every race seen, as bars, then unknown. Source: `ra`.
- **Guilds humbled:** every guild, as bars, then "No guild" as a faded figure. Source: `gu`.
- Each bar row is 24 apart. Labels are Friz 16 ink at the section's x + 14; bars start 90 (levels) or 180 (the others) in.

### 6. The Wilds | Where the Wilds Strike (F6; F6x shows it with made-up causes)

**Left: The Wilds.** Heading at (296, 120).
- **The figure:** total deaths to the wilds in EB Garamond Bold 50, rubric, at (296, 200), with the caption "DEATHS TO BEAST AND WORLD, NOT TO PLAYERS" at 222. Source: death marks without `pvp`.
- **What killed {Name}:** a sub-heading at 262, then a sheet at (72, 276)–(518, 668), scrolling.
  - Each cause: its name in Friz 17, ink, then its kind in EB Garamond Italic 14, faded ("beast", "the world"), and the count right-aligned at 490, rubric.
  - Last: "Not recorded (before this version)", faded, with the deaths that have no cause.
  - Source: **new** `m.cause` and `m.how`. Until then the sheet holds only the "Not recorded" line, as in F6.

**Right: Where the Wilds Strike.** Heading at (801, 120).
- **The lands:** a sheet at (576, 146)–(1025, 452), headed "DEATHS TO THE WILDS".
  - Every land with a wilds death, most first. The name is EB Garamond Italic 17, ink, with a faded leader; the count is rubric.
  - Lethality: Un'Goro Crater 5, Mount Hyjal 5, Western Plaguelands 4…
- **At what hour:** a sub-heading at 490, then the hours strip: 24 bars, baseline 580, height 56, axis labels "midnight", "6", "noon", "18". The busiest hour is in deep rubric with its figure above.
- **Chronicler line:** "The wilds take {Name} most often at {hour in words}." at (801, 630).

### 7. The Guild's War | The Guild's Lands (F7)

**Left: The Guild's War.** Heading at (296, 120). Kicker "AS IT REACHED {NAME} · SINCE {first guild pin date}" at 156.
- **The sheet:** (72, 172)–(518, 664), scrolling, with the column heads SLAIN and FALLEN.
- **Rows:** one per guildmate who has sent a kill or death, **including you**, sorted by kills. Rows are 46 apart.
  - A tile with the guildmate's class.
  - The name in N2 with the level.
  - Under it, in EB Garamond Italic 14, faded: "{rank} · “{public note}”".
  - Kills in rubric at 426; deaths in ink at 490.
- **Your row:**
  - a rubric band (alpha 64 of 255, fading at both ends);
  - a small rubric pointer in the left margin;
  - "(you)" after the level, in EB Garamond Italic 15, rubric.

  Your figures are your own `db.kills` and `db.deaths`.
- **Sources:** guildmates' counts from `z.gmarks` by `from`; class, level, rank and note from the guild roster (`GetGuildRosterInfo`).
- **Victims:** the names and classes of the guild's victims (**new** `g.vn`, `g.vc`) appear in each guildmate's tooltip once recorded.

**Right: The Guild's Lands.** Heading at (801, 120).
- **The lands:** a sheet at (576, 146)–(1025, 430): every land with a guild pin, by total, with slain in rubric and fallen in ink.
- **The guild's hours:** a sub-heading at 466 and an hours strip (baseline 560, height 56) from the guild kill pins' times.
- **Chronicler line:** "Only what reached {Name} while in the field is written here." at (801, 612).

**This spread is this character only.** The account toggle's "All characters" is disabled, because characters can be in different guilds.

## Behaviour

### This character or all characters

- **This character:** the default, and the character's own `db`.
- **All characters:** each character's summary in `WarpathGlobal.chars` (see Saved data), added together:
  - Tally: sums; best streak is the highest; screenshots are account-wide already.
  - Multi-kills and streaks: sums.
  - Records: the best across characters, with "· {character}" added to each detail line.
  - Hours, weekdays, calendar: summed by hour, weekday and date.
  - Classes, Who They Were, The Wilds: summed counts.
  - My Lands: each land's kills, deaths and miles summed. The chosen land's "Slain most here" shows only on this character's view, and reads "this character only" in the account view.
  - Foes of Note: the characters' top-ten lists merged by name.
  - The Guild's War: not available (disabled).
- **Only one character on the new version:** the account view reads, in EB Garamond Italic 16 at the top of each page, "Only {Name} has opened the chronicle since {the release that ships it}." The release number isn't chosen here. It goes in the current 3.8 series, because 3.9 is planned as battleground mode.

### Empty states (a new character)

A character with no fights (Dabank, Derelect) still gets every spread.
- **Tally:** "0 · 0 · 0" figures; every row "none".
- **Records:** the heading and one centred italic line: "No records yet. The first blood will be written here."
- **Hours:** an empty wheel with its labels, and the line "{Name} has drawn no blood yet."
- **Calendar:** the current month with field days dashed.
- **Classes:** both tables with every class at a dash.
- **My Lands:** the map with no marks; the list shows lands walked (faded); the account shows the chosen land's miles and sightings.
- **Foes:** both blocks read "None yet."
- **Who They Were:** the sections with "None yet."
- **Wilds:** "0" and an empty sheet.
- **Guild:** whatever guild pins exist, or "No word from the guild yet."
- **Not in a guild:** the Guild spread shows "{Name} rides with no guild." and the arrows skip nothing.

### Overflow

- Every list that can grow sits on a sheet that scrolls with the mouse wheel: lands (two), Who They Were, causes, wilds lands, guildmates, guild lands.
- Fixed lists don't scroll: Classes (ten rows), Foes (six each), Tally, Records (at most thirteen).

### Hover

- **Names:** a GameTooltip with name, level, class, race and guild, then this character's kills of them and deaths to them, and the grudge state.
- **Wheel spokes and hour bars:** "{hour}:00–{hour}:59 — {n} slain".
- **Calendar cells:** the date, kills, deaths, and the zones fought in.
- **Tally rows:** a one-line definition, the "Definition" column above.
- **Tier columns:** the date the tier was last reached.
- **Map marks and land rows:** the land's kills, deaths and best streak.

## Saved data

Joe agreed to every item. Item 1: "All of it, as proposed". `db.played`, a lifetime time-in-the-field counter, was dropped as /played under another name (Claude's call). Items 4–8: "Yes, all four".

Everything is additive: new keys and new fields only, with no `db.v` bump. Missing fields read as unknown. An older build ignores the new keys, so going back is safe.

| # | Recorded | Where | Written when | Old data |
|---|---|---|---|---|
| 1 | Each character's summary: name, class, faction, level, and the aggregates the account view sums (above), plus its top-ten victims and killers and each record | `WarpathGlobal.chars["Name-Realm"]` | login and logout | Built from the character's own saved data at its first login on the new version: everything that exists is counted |
| 2 | Flights taken | `db.flights` | when a flight starts | Starts at 0 ("none yet") |
| 3 | Corpse runs, total and per land | `db.runs`, `z.runs_n` | when a corpse run ends at the body | Starts at 0 |
| 4 | Your level at each kill and death | `m.my` on marks | at the mark | Blank on old marks: the gap records and "above your level" count new marks only |
| 5 | Your health at each kill; the odds | `m.hp` (0–100); `m.odds = {foes, friends}` | at the kill | Blank: "closest call" and "worst odds won" appear once set |
| 6 | What killed you in the wilds | `m.cause` (a creature's name), `m.how` (`"beast"`, `"fall"`, `"drown"`, `"fatigue"`) on non-PvP death marks | at the death | Blank: counted as "Not recorded" |
| 7 | Releases at a spirit healer; miles walked as a ghost | `db.spirit`; `db.ghostYards` | at the release; along the corpse-run stroke | Start at 0 |
| 8 | Victim name and class on guildmates' kill pins | `g.vn`, `g.vc` on `z.gmarks` | when a guild kill arrives | Blank on old pins |

**Your saved data:** nothing is removed or changed. New counts start from your first fight on the new version. Each character's summary for "All characters" is built from what it already has, the first time it logs in. Old kills and deaths show "unknown" for the new details.

**Migration:** none. Item 1 is a function run at every login (`Ledger.Summarize`), inside `pcall`. On error it prints one chat line, and the account view says it couldn't be read.

### How the uncertain items are read

- **What killed you (item 6).** Forever forbids addons from the combat log. Joe's probe on 2026-11-27: registering `COMBAT_LOG_EVENT_UNFILTERED` gave "ForceTaint_Strong has been blocked from an action only available to the Blizzard UI". So causes come from the client's state at death, read through `ns.Foes.Safe`:
  - a fall: `IsFalling()` true at the death, or within 1 s before it;
  - drowning or fatigue: the `BREATH` or `EXHAUSTION` mirror timer running at the death (`MIRROR_TIMER_START`/`_STOP`);
  - a creature: the hostile non-player you had targeted, or that targeted you, in the 10 s before death. These are its name and creature type (`UnitCreatureType`); "beast" means any creature.
  - Lava, fire and spells can't be told apart. A death none of these explains has no cause, and counts under "Not recorded".
- **Odds (item 5).** These are the counts `Odds()` in `Feats.lua` already makes for the feat lines:
  - enemies in `ns.Foes.near` seen in the last 10 s;
  - allies: you, plus `ns.Foes.allies` and visible groupmates.

  A unit the client hides isn't counted, so enemies can only be under-counted. Records say "at least". A kill with no enemy read stores no odds.
- **Guild kill classes (item 8).**
  - The kill message ends with the victim's name (`…|cry|victim`), but carries no class. Showing classes means **appending a field** after `victim` (`…|victim|class`).
  - Older versions ignore extra fields; a missing class reads as unknown.
  - The patch notes must say guildmates need the new version for their victims' classes to show.

## What it needs in game

- **Class icons:** the client's own. They're either `Interface\Icons\ClassIcon_<Class>` or the `UI-CHARACTERCREATE-CLASSES` atlas with `CLASS_ICON_TCOORDS`; check which exists on Forever. One screenshot settles it for both the Ledger and Grudges: the Grudges session's `_runlines.txt` and the Ledger's three `/run` lines test the same two textures.
  - For Unknown: `Interface\Icons\INV_Misc_QuestionMark`, the macro default.
  - The renders' icons are stand-ins drawn by `lbase.py` and `honour.py`, and never ship.
- **Continent map art (My Lands):** Blizzard's art, drawn from the client's map tiles at run time; it never ships as an image.
  - The method and risks are the Warpath page's: see `chronicle-warpath.md`, "What it needs in game". Use `C_Map.GetMapArtLayerTextures` for Kalimdor (1414) and Eastern Kingdoms (1415), desaturated, tinted and MOD-blended, with a soft mask.
  - Lighten it about 40% toward the page (`SetAlpha`, or a lighter vertex colour) so marks read.
  - Land positions come from `C_Map.GetMapRectOnMap(zone, continent)`.
- **Buttons:** `UIPanelButtonTemplate` for the account toggle and the continent buttons. The off state is `:Disable()`, or a darkened vertex colour plus a grey label. Check that the off look matches F1–F7.
- **Page-turn arrows:** the ones the Campaigns page uses, including the calendar's month arrows.
- **Guild roster:** `C_GuildInfo.GuildRoster()`, then `GetGuildRosterInfo(i)` for level, class, rank and public note. The officer note is never shown.
- **Fonts:** EB Garamond Italic and Bold, bundled as in the canon.
- **Sheets and scrolling:** the canon's `ScrollFrame` with the crimson bar.
- **Drawing:** the wheel, bars and calendar rules are solid textures, rotated with `SetRotation` for the wheel's wedges. Check how `SetRotation` behaves on this client, or draw the wedges as several thin rotated lines.
- **Local time:** all hours and dates use `date()` local time, as the campaign dates do.

## Claude's calls (Joe may veto)

- The order of the spreads and the names beside the arrows.
- The bloodiest night moved from the Hours page to the Calendar.
- Deep rubric (96,14,8) with an underline replaces gilt for "the most" on the Hours, Calendar and hour strips.
- Records:
  - "Worst night" replaces the fastest triple kill;
  - records needing new data appear only once they have one.
- Counting:
  - a chain counts once, at its final tier;
  - a streak counts at every title it reached.
- The Tally:
  - holds the corpse-run, spirit-healer and ghost-miles counters, since they count every death, not only the wilds';
  - "Time in the field" was dropped with "Days in the field".
- My Lands:
  - opens on the bloodiest land of the continent you're on;
  - shows one continent at a time;
  - the map art is lightened.
- The Foes lists stop at six, with no sheet.
- The account view:
  - is defined page by page as above;
  - doesn't apply to the Guild spread.
- The Ledger reopens on the spread you left until a `/reload`.
- Wording: "Kill-death ratio", "Kills avenged", "Struck {Name} down", "Where the Wilds Strike", "At what hour", and the chronicler lines.
- Unknown counts as "the game hid the class". A death in a free-for-all arena counts as PvP, as it is recorded today (Joe: "its fine").
