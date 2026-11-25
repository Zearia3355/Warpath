# How Warpath works today (3.7.11 released; 3.7.12-test2 installed from branch `roads-snap`)

Reconstructed on 2026-11-23 from the claude.ai project's patch notes, release queue, backlog and build plan. **Where this file and the code disagree, the code wins:** fix this file when you find a mismatch. Keep it current on every release (that's the point of it: the old project had no single "how it works now" doc, so changes went unnoticed).

**Verification status.** The document was written without being checked against the code, and a spot-check on 2026-11-23 found four mismatches, since corrected here or in `CLAUDE.md`: the `db.v` chain omitted version 6; the code layout omitted `Grudge.lua`; `SAMPLE_GRUDGES` was reported as a leaked global when it is a forward-declared local; and 3.7.10's patch notes were said to be unwritten when they were already in `CHANGELOG.txt`. These constants were confirmed correct against the source: `LINE_SOLID` 300, `cfg.trailMin` default 60, `TRAIL_MIN_CHOICES`, `DASH_BUDGET` 4000, `GUILD_TOP`/`GUILD_REST`/`GUILD_CAP` 0.75/0.15/3.6, `CHAIN` 120, `MARK_CAP`/`GMARK_CAP` 300, `ROUTE_MATCH` 0.03, `ROUTE_MIN` 4, `ROUTE_OFF` 2.5, `db.roadMin` 2.5, `db.longDays` 14. The rest of the file is still unverified prose — treat it as a guide to intent, not as a specification.

Conventions: `cfg.*` = settings shared by all characters (account-wide `WarpathGlobal`). `db.*` / `z.*` = per-character data / per-zone data. "Play clock" = days played, not calendar days (see Long memory).

---

## Map layers

Layer names (typed / saved key): `battle` (old `heat`), `roads`, `trail` (saved as `recent`), `marks`, `sightings`, `guild` (saved as `shared`), `runs`. Typed names were renamed in 3.4 without migrating saved keys; old names still work.

Master switch: `cfg.shown` (shared by all characters). Map button left-click, `/warpath map [on|off]` (old `toggle`). Hiding never stops recording.

### Today's trail
- Last **5 minutes**: solid line (`LINE_SOLID` 300 s, `DrawWalkLine`).
- After that: **dashes** (`DrawTrail`, one per `DASH_PERIOD` 5 × thin) that shorten, thin and fade evenly to the end of the trail length. `DashLook(age, life)`: fill 0.85→0.5, thickness 1→0.55, alpha 0.95→0, linear from 5 min to trail end.
- **Trail length** `cfg.trailMin`: default **12 h** (720 min; 60 before 3.8.0), clamped 15–1440 (`ns.TrailSeconds`). Map tab radios 15m/30m/1h/4h/12h/24h (`TRAIL_MIN_CHOICES`); `/warpath trail <15m-24h>` (bare number = minutes). Old `cfg.trailHours` is kept but unused.
- Dashes are **anchored by distance along the stroke** (`s.d`, cumulative, map widths, aspect 668/1002, from `ns.StrokeArc`, computed in `Simplify` before reducing, kept in step like `s.ts`; extended at draw time for the open stroke). Tested 0 px movement over time and while walking.
- Per-point times `s.ts` (seconds since `s.t`), kept in step by `Simplify()`. Trail from before 3.4 has no per-point times (no backfill).
- Strokes kept 24 h (`KEEP_HOURS`). `DASH_BUDGET` 4000 pieces, newest first (faintest dropped first). Drawn over roads, no per-square cap.
- **Footsteps were removed in 3.7.6** (`StepLook`, `STEP_*` gone). Road "walked today" is still recorded (`/warpath zone`).
- History of this one feature, for context (it changed six times in two days): 3.4 5-min line fading into footsteps → 3.5 trail-length setting (2–24 h) → 3.6.3 footsteps fade over trail length → 3.7.5 15-min line + two-tone footsteps (jumped; rejected) → 3.7.6 dashes 5–15 min, no footsteps, length setting removed (Joe picked "option 2" from renders) → 3.7.7 length setting back, 15 min–24 h, default 1 h.

### Trail rework (3.8.0) — shipped in 3.8.0 (tested in game as 3.8.0-test1 to test7)

Why: on a friend's single hour of questing in Silithus, the trail was a red scribble. Every step is drawn, all dashes look alike, and the fade is linear over the trail length, so age can't be read ("where was I" works, "when" doesn't). The intent, in Joe's words: show recent travel, be readable in time, and stay out of the way of using the map to navigate. Picked from Python concept sketches on synthetic data (`trail_sketch*.py`, scratchpad only, not in the repo). Built in `Linger.lua` (recording, outline geometry, clipping) and `Map.lua` (`DrawToday`: `AreaScene`, `DrawWalkLine`, `DrawTrail`/`StrokeDashes`, `DrawAreas`, `DrawHere`, tags). Thresholds are first guesses; tune on real data.

**Lingering areas** (Joe's idea: tangles become "zoned areas" with trails between them)
- An area forms once you've stayed within `FORM_R` 0.05 map widths of the centre for `FORM_T` 4 min. Until then it's ordinary trail.
- While you're in it, it grows: a trail point joins 45 s after it's made if you're still inside, and its piece of trail fades out over ~90 s. The outline only moves outward.
- **Distances are in yards** (test4): each map's width in yards comes from the game (`C_Map.GetWorldPosFromMapPos`, cached per map; 4000 if it can't say). Map fractions made city areas (the Undercity) several times tighter than zone areas. Forming: within `FORM_YD` 150 yd of the centre for 4 min. Leaving: `MARGIN_YD` 90 yd outside. Stops growing past `SPAN_YD` 1200 yd. On a typical zone these are close to the earlier fractions; in a city they are several times roomier. (Joe asked for the lift room to be covered; the values are Claude's call, kept under the radius of an Undercity lap, about 160 yd, so a lap doesn't become one area.)
- **Short trips join:** leaving keeps the walk out (only the ground outside the area); if you're back inside within 2 min (`TRIP_T`) and never more than 150 yd out (`TRIP_YD`), the ground the trip covered joins the area, unless the trip only went out along a line and back: every point within `TRIP_WIDE_YD` 10 yd of the line from where it left to its furthest point. A corridor stays a line. (Joe, test4: an area spread up the Undercity hallway)
- **Recent trail joins:** when an area forms, your trail from the last 10 min (`RECENT`) within 150 yd of its centre joins it (the wandering before the 4 minutes were up), but only where you were milling about: a point where either side of it (12 s, `MILL_T`) is a straight walk of at least 12.5 yd, net over 75% of path, is travelling and doesn't join.
- **Reopening:** a minute inside an older area still on your trail (`REOPEN_T`) reopens it as a new visit, from when you entered; passing through doesn't. A few seconds out at the edge (up to 15) don't restart the count. Stepping back in within 10 min still reopens at once. (Joe, test4: re-entering an old area didn't refresh it)
- **Visit list on hover:** visits under 10 min apart read as one, and anything under 2 min folds into its neighbour (`Linger.Visits`). Stepping in and out at the edge had made a list of "1 min" entries. (Joe, test4)
- Forming needs movement through the 4 minutes (points in at least 3 of the 4 one-minute slices): standing still, or a few steps then standing, is not lingering.
- Leaving = more than `MARGIN` 0.03 outside the outline. The walk out never joined, so it stays a link. The outline then freezes and never changes. A 10-min trail gap (logged off) also closes it; an area stops growing past 0.30 across.
- Stepping back inside within 10 min (`REENTER`) reopens it with a new visit record. Every re-entry is its own record, so a visit's times cover only time inside; the tooltip shows visits under 2 min apart as one.
- Time counts per sample (twice a second) while inside, AFK included: `/afk` is often on while you're still playing (Joe).
- **Return visits:** lingering again on or next to an area that's still on the trail reopens it. One outline, the label shows **total** time there; hovering lists the visits ("18m at 2:10 pm, 9m at 2:48 pm"). The area's age follows the latest visit, so revisiting refreshes it. (Joe)
- **Shape:** C — follows the perimeter of the ground covered (convex hull, padded and rounded). Label above it: time spent, e.g. "26m", "2.7h".
- **Inside the area you're in,** your line shows only until those steps would have joined it (`LAG`, 45 s): your last moments, not a scribble of the last 2.5 minutes. (Joe, test4)
- **After you leave, it's clean:** links stop at the outline and nothing inside is drawn. Dashes inside are hidden from the start (in the area you're in too) and stay hidden; only the solid line, which shows inside while you're there, fades out over ~1 min after you leave. (Joe's sketch; in test3 the hidden dashes came back for that minute, fixed)
- **Saved** as `z.areas` (per zone): `h` the convex hull (flat, quantized), `v` visits `{ s, e, t }`, `e` last time inside, `w` a change counter for the outline cache. Recomputing from strokes wouldn't be stable (`Simplify()` changes points when a stroke closes). Pruned with the trail after 24 h (`KEEP_HOURS`). Not shared; old versions ignore the key. No `db.v` bump.
- Live state (the window, pending steps, which area you're in) is memory only. After a `/reload` inside an area, the next sample re-enters it as a new visit.
- **Drawing cost:** trail from a visit is inside the outline by construction (every step taken during a visit joined it), so hidden trail is skipped by its time alone (`hide` spans: each visit trimmed 20 s at the start and `LAG` + 20 s at the end) before any cutting; the rest is cut exactly against the outline (`Linger.Clip`, with a fits-inside circle as a fast path). Timed in the harness on a 3-hour synthetic session: 6.5 ms per redraw at a 1 h trail (3.8 before), 8 ms at 4 h and 24 h (10-13 before), with a fifth of the lines.

**Links (lines between areas) and age**
- Last **2.5 min**: solid line (`LINE_SOLID` 150; was 5 min: a lap of the Undercity stayed all solid). After that, dashes anchored to the ground, as today, starting with a small jump along the colour gradient (`TRAIL_STEP` 0.15) so the change is noticeable early; then the slow fade. (Joe)
- **Colour:** one continuous gradient, faction colour → faction `deep` → dusk (desaturated, darker; never paler), on a time scale that moves fast early (5 m, 15 m, 1 h, 4 h, 24 h roughly evenly spaced). Opacity eases off along it and fades to nothing over the last quarter of the trail length. (Joe: gradient, not steps)
- **Rhythm:** long dashes → short dashes → dots, in three bands on the same scale, crossing over gently.
- **Area outlines share the rhythm and colour of their age**, so a link never looks weaker than the area it leads to. The area you're in: solid, full colour.
- **Links hold:** a link stays at least as visible as the older of the two areas it joins, so areas don't hang off faded links. Revisiting an area can strengthen its old links again (an event, not time passing).
- **Dusk** is the faction's `deep` colour 60% of the way to earth brown (0.36, 0.27, 0.18): reddish brown for the Horde, slate for the Alliance.
- **Smoothing:** dashes follow the path smoothed along its own length (`TRAIL_SMOOTH` 1.0 dash slot either side, weighted 1-2-3-2-1), so recording kinks don't read as jaggies; the solid line stays exact. It depends only on ground already walked; the window narrows evenly near a stroke's ends. Worst shift when you stop, let the end turn to dashes and walk on round a tight bend: 0.43 px at 1.0 (1.7 px at 2.0, a visible crawl), tested. (Joe: medium)
- **Spacing:** the marks repeat every 4 dash slots as dash, dash, arrow with three equal gaps (laid out at a fresh dash's length). As marks shorten with age, the dashes give up more on the side facing the arrow (the arrow only shortens from its back), so all three gaps grow alike. Before this, the shorter arrow left a gap about four times the others before each arrow. (Joe)
- **Direction:** about every third dash is an arrow. Its shaft takes in the slot before it, at **75%** of that length (option C), with a head 0.6 × a dash. Arrows scale with map zoom, so they read zoomed in; at normal size the colour gradient carries old → new. An arrow's tip is fixed on the ground (it only shortens from the back as it ages); whether it's skipped for a bend (over 35° under it) is judged at full length, so arrows can't switch on as they age. The trail runs right up to your arrow: one line (`tail`) from the end of the trail as last drawn to where you are, updated every 0.05 s while the map is open (the trail itself redraws every 2 s at most, and points are recorded every few steps). The arrowhead at your position in 3.8.0-test1 was dropped: a gap opened behind your arrow while it waited for the next point (Joe). Comets (tapered dashes) were dropped: Joe read the tail as the arrow tip.

### Roads (long memory) — reworked in 3.7.12 (branch `roads-snap`, installed as 3.7.12-test2)

**Recording** (`Record.lua`, `Visit`)
- Built from where you choose to travel. One credit per stretch per calendar day of use, only while travelling (`Travelling()`: 3 cells net in 30 s). Flights and corpse runs never count.
- Stretches join cells of a 96×64 grid. **Snapping (3.7.12):** where you stand is matched to the best-worn road point within one cell (`Snap`, `PointWear`), counting only wear from earlier days (otherwise a new road keeps pulling you back onto the point you just left). A route walked on different days with a cell of drift builds one road, not parallel lanes. Before this, 92% of Lethality's 8,900 stretches had one day of credit and routes showed broken, doubled and late.
- A cell's road point (`z.cx`, `z.cy`) moves only while you travel, so standing about (quest givers, mailboxes) no longer bends roads.

**Upgrade to `db.v` 10** (`MergeLanes`, `MigrateToV10`)
- Side-by-side lanes recorded before snapping fold into one road: points taken best-worn first take over weaker points across their road (never along it), stretches are re-joined between the points that remain.
- Lanes landing on one stretch add their days; a shared last day counts once (`L / e.l`). Rungs between lanes fold to nothing. A rung the fold would stretch past two cells across its road stays unfolded where walked (it would draw as a long spoke; first seen in Undercity).
- The roads as they were are kept, hidden, as `z.roadOld`. Lethality's save grew from 1.67 to 2.26 MB because of it; dropping it later brings the file well below where it started.

**What's drawn** (`Map.lua`: `RoadChains`, `Bridge`, `Bubbles`, `Lynchpins`, `DrawGround`)
- Roads are chains between junctions and ends, corners cut a quarter of the way (Chaikin). Pieces overlap slightly at joins while fully drawn, so the dark edge doesn't notch through at bends.
- Hidden, never deleted: scraps (a piece of `ROAD_SCRAP` 2 stretches or fewer on its own); stubs (dead ends of `ROAD_SPUR` 3 or fewer off a road, unless gold); the weaker side of a loop of `ROAD_BUBBLE` 10 stretches or fewer all round.
- Gaps joined through ground walked at least `ROAD_WALKED` 0.3 (one day, ~24 days played): up to `ROAD_BRIDGE` 4 stretches onto any road, up to `ROAD_BRIDGE_END` 12 where two road ends face each other. A join may step between walked cells that touch. Joins never start or end at scraps (they chained one-day wandering into roads). A join takes the look of the weaker road it joins.
- **Frozen layout:** everything above is decided on strengths as of your last travel in the zone; between visits the whole layout fades by one shared factor. Decided on today's strengths instead, the network rewired and brightened as it faded (found by time-lapse; 273 popped and 480 brightened points on day 6 in Un'Goro).
- **Lynchpin threads** (Joe's idea): stretches on the strongest route between two strong fragments (the strongest spanning tree) stay at least `ROAD_THREAD` 0.5 visible while the strongest stretch on each side is still drawn, so a fading network keeps its fragments joined. Dead ends are never held.
- A road's look (colour, width, tier) is averaged along it over `ROAD_SMOOTH` 3 stretches either side, so whole stretches gild together; whether and how much a piece shows still comes from its own strength.
- Opacity fades from full at silver (1.5) all the way to nothing at 1.2 (it used to stop at a quarter and vanish).
- The remaining fragments in a fade are the most-walked stretches on their own record (checked: the 10 strongest are always among them). Joe likes the fragment look.

**The look: gilt** (`ROAD_STYLE` "gilt"; "plate" is the flat 3.7 look)
- Raised metal like Blizzard's gold frame trim: dark edge, body, shade on the far side, warm highlight towards the light (top left). `GILT_RELIEF` 1.0 (deep, Joe's pick). Shine stays warm, never white.
- Staged gilding: pewter, then a gold thread along the lit edge, then the body turns gold; the edge goes iron to bronze. No blend through cream.
- **Levels by habit**, not by how long anyone has played: a road used every k days played settles at 1 / (1 − 2^(−k/14)) (ceiling 20.7). At the default gold threshold (`db.roadMin` 2.5; `/warpath roads` scales all of them):

| Look | Strength | Daily use from scratch | Habit it holds at (of days played) |
|---|---|---|---|
| silver | 1.5 | day 2 | two recent days |
| gold thread begins | 5.7 (2.28×) | day 6.5 | about twice a week |
| full gold | 9.6 (3.82×) | day 12.5 | every 2 to 2.5 days |
| faction tier 1 | 12 | day 17.5 | about 4 days in 7 |
| faction tier 2 | 16.4 | day 31.5 | about 4 days in 5 |
| end of band | 20 (8×) | — | every day |

- **Faction mark** (in the faction's `deep` colour): tier 1 a thin streak down the gold; tier 2 the shaded side too. The trial alternatives ("enamel", "banded", "embossed") were removed in 3.8.0. Band multipliers of `db.roadMin` are `C.GILD_START` 2.28, `C.GILD_FULL` 3.82, `C.GILD_TOP` 8, shared by `Map.lua` and the `/warpath zone` counts.
- Glints (amber stars, ≤6 per zone) and shimmer still run on the most worn roads.
- Tried and dropped on renders: cartographer's ink (vanishes on dark maps), trodden earth, gold rims and an engraved groove beyond gold (rims read as rail track; red-gold reads as bronze), and gems (rubies, sapphires, emeralds: at normal map size a road is 4–6 px, so stones read as specks).
- `/warpath roads` counts ("N stretches of gold, M of silver", `Zone.lua`) still use the old thresholds (1.5 and 2.5), not the new bands. See open items.
- Budget: roads stop 800 lines short of `LINE_BUDGET` (5000). A gilt piece draws 4 lines (5 with the streak).

### Long memory and the play clock (3.5.0)
- Roads, battle haze and flight routes fade on **days played**, not calendar days ("a weekend away costs nothing"). Joe's decision.
- Play clock = (days played before today) × 24 h + time of day. Only long memory uses it. (Claude's call on the formula.)
- Halving every 14 play-days (`db.longDays`). `/warpath memory <days>` (old two-number form accepted; hours ignored). `Prune()` drops entries faded below 0.05.

### Runs layer (`runs`): corpse runs and flight legs
- Own store `z.runs` (kind `g` ghost / `f` flight), own lifetime, not the trail history. Along-the-line fade by each segment's own age.
- Corpse runs: dashed **ice blue with a soft glow**, no outline. Lifetime `cfg.runHours`: default 24 h; options 1, 6, 24, 48. `RUN_BUDGET` 2500. Corpse runs get no long memory.
- Flights are still recorded into `z.runs` (replay uses them), but **today's flight is no longer drawn as its own line** (3.8): it lives in the legs. `cfg.flightHours` (24 h) now only sets how long those strokes are kept; its options row is gone. Flights/corpse runs split at 1,200 points (walking strokes at 300).

### Flight legs (`z.air`, `Flights.lua`, 3.8)
- **Why:** flight paths run point to point through hubs you pass on every trip, so drawing every flight spins a web (Joe's long-standing worry). And the old routes (`z.routes`, 3.4.1–3.7) were matched by their two ends inside a zone, so one path flown from different places, or cut at a zone edge, split into several records. None of Lethality's 87 routes ever reached the bar of 4 (strongest 2.87), so nothing was ever drawn.
- **Recording:** when a flight's stroke closes, it is resampled every `AIR_STEP` (30) yd and each point is snapped to the nearest leg point within `AIR_SNAP` (100) yd. Matched points gain one day of long memory (once per calendar day, same clock and 14-play-day half-life as roads); runs of unmatched points start a new leg, joined to the leg points either side. A return flight beside the outbound one (~50 yd off) is the same leg. Distances in yards from the map's width (`Linger.MapYards`; maps are 3:2).
- **Store:** `z.air = { leg, ... }`, leg = flat `x, y, ...` plus parallel arrays `l` (strength), `t` (play clock), `d` (day credited). A leg is dropped once every point has faded below 0.05.
- **Shown:** only legs flown on about **two days** (`AIR_SHOW` 2), fading in over `AIR_FADE` (0.6) below that. A threshold on days, not a ranking, so one leg never makes another vanish. On Lethality's data (3 days of flying) Kalimdor shows one trunk (Crossroads north through Ashenvale) instead of a web.
- **Look: royal blue dashes with a dark casing** (Joe's pick, 2026-11-24). History: a solid "groove" (dropped: dashes say "flight path", solid says "road"), then warm gold dashes, which shipped in 3.8.0-test5 and were **nearly invisible in game**: the world map is yellow-gold parchment and the renders' olive stand-in hid it. Re-rendered over his screenshots (`render.py --backdrop`): earthy colours (umber, bronze) vanish or look like the map's printed roads; of six non-earthy colours (violet, royal blue, teal, emerald, fel green, magenta) he picked royal blue. Core (0.25, 0.45, 1.00) over a casing (0.08, 0.05, 0.10); dash 10 px, gap 9 px. Thickness in line widths: casing ×3.2→4.4, core ×1.4→2.2; alpha casing 0.75→0.95, core 0.95→1.0; from 2 days to `ROAD_FULL` (12). A line width is a fraction of the map's width: **0.00117 on a continent** and **0.0013 on a zone**, both 65% of what was first rendered (0.0018, 0.0020). Joe found the zone width a little thick on renders, then the continent width in game (test6), and asked for the same cut. Drawn under roads (ARTWORK −2/−1). Points credited together that lie within 0.5 px of a straight line are one line; grouping looks only at that, never at fading. Dashes are measured from the start of the leg (pixel distance along its points), not from the first part still drawn, so as part of a leg fades the rest stays put. `AIR_BUDGET` 1500 lines.
- **Old routes:** converted once per zone on login (`Flights.Convert`, from `Migrate`, in `pcall`): strongest first, each laid at its current strength, merged as the stronger of the two (not added). A zone with `z.air` is done, so it is safe to run again and **no `db.v` bump**: going back to 3.8.0-test4 is safe (it ignores `z.air`). `z.routes` is kept, no longer added to or drawn.
- Tests: `Flights` (6): a flight flown once draws nothing; two days etch one leg (return flight merged); flights from different places build the shared leg only; legs only fade (day to day and against day one); dashes stay put as a weaker half of a leg fades; old routes come over as one leg, idempotent, routes kept. Each but idempotency was mutation-checked (idempotency holds even without the `z.air` guard, because re-laying snaps onto the same points).

### Battle haze (`battle`)
- One red that deepens as fights pile up, **kills and PvP deaths only** (sightings removed from it in 3.7.0). Each fight also warms surrounding cells. Fades over 14 play-days.
- Rebuilt from kill/death marks in 3.7.1 (`db.v` 9). The previous haze is kept hidden as `z.battleOld`, not deleted.
- **Guild haze**: each guildmate's history kept separately (`z.guildBattle[sender]`, deaths `z.guildDeaths[sender]`). Combined as **0.75 × strongest guildmate + 0.15 × the rest, capped at 3.6** (Claude's deviation in 3.7.0, told to Joe). Own fights always read darkest.
- Toggles: "Battle haze" (whole layer) and "Guildmates' battle haze" (Map tab + map button menu); "Share my battle history" (General tab), `/warpath share history [on|off]`, `/warpath share sync` (ask everyone again).
- Tuning knobs if it reads too strong: `BATTLE_ALPHA`, `BATTLE_FULL`, patch size.
- Neutral towns: haze hidden there, not erased (3.6.4 fixed 3.6.1–3.6.3's `TownSweep()` wiping town cells).
- `/warpath debug haze`: strongest spots in this zone.

### Pins (`marks`, `guild`)
- Own kills/deaths in the zone's marks (check the field name in code); guildmates' in `z.gmarks` (saved since 3.7.4). **Cap 300 own + 300 guild per zone, oldest dropped.**
- Fade on **calendar time** (Joe's decision, 3.7.4 — unlike long memory):
  - Own kills/deaths: full 2 days, fade over 5 (gone after a week).
  - Notable ×2: avenged deaths, grudge kills, first kill of a player, streaks, multi-kills, feats.
  - Mob/fall deaths: gone within a calendar day; icon is a desaturated grey cross (`TEX_RAID`, texcoords 0.5–0.75, 0.25–0.5), pin kind `mob`.
  - Guild pins: full 2 h, fade over 3 days.
  - Below 0.03 alpha: not drawn. `ns.MarkFade`, `ns.GuildFade`.
- **Show all history** (`S.showAll`): every stored pin at full strength; switches off at login. Map button menu, Map tab, `/warpath history [on|off]`. Replays always draw every own pin.
- Pins keep constant screen size when the map is enlarged/zoomed (Leatrix Maps). Size 25–200%: Map tab or `/warpath icons <25-200>`.
- Guild kills/deaths draw above sighting crests, slightly bigger.
- **Clicking a pin does nothing** (3.7.9): hover shows the tooltip, clicks fall through to the map (`SetMouseClickEnabled(false)`). Waypoints remain via chronicle list click, grudge ledger Waypoint button, `/warpath waypoint death|kill`.
- Kill mark fields: victim `Name-Realm` (`m.f`), screenshot number/predicted file (`mark.shot`, `mark.file`), `tag` (first/grudge/avenged/streak), `streak`, `times`, `av`, `mk`, `ft`; level/race/guild when visible. Death marks: killer `kn`, `kc`, killer full name.

### Sightings (`sightings`)
- Live crests of recent enemy sightings, 15 min, fading. Guild-shared crests (`shared`) are memory-only (lost on reload).
- Not recorded in neutral towns (no crests, no war-table count, no haze, nothing shared, no zone-stat count). Guildmates' sightings from towns ignored. Kills, deaths and grudge alerts still work in towns.
- Sightings count in zone stats (`z.sight`, one per enemy per 2 min).

### Map button and minimap button
- Map button: crossed swords, top-right of the world map's scroll container; shift-drag to move (position saved account-wide). Left-click: show/hide all. Right-click: layers menu (incl. battle haze, guild haze, show all history). Greyed in battlegrounds.
- Minimap button (LibDBIcon): left-click chronicle, right-click settings, drag around the edge, greyed in battlegrounds; MBB/Titan Panel pick it up. On by default; General tab or `/warpath minimap`.

---

## Kills, deaths, streaks

### Counting
- From the game's honorable-kill counter; an enemy seen dying nearby can name a kill. Two kills in one burst count even if the second victim was never targeted.
- **Guarded** (Joe's choice): a nameless credit within 2 s of a counted kill, with no second death seen, isn't counted. `/warpath debug kills` shows credits vs counted. If double credits never happen in practice, drop the guard (open check).
- Same enemy within 10 s = one kill. Kills only count in combat or within 3 s of leaving it.
- Deaths counted once even if reported twice. Killer = last hostile targeted in the 20 s before death.

### Multi-kills, streaks, feats (3.7.0)
- Chain window **2 minutes** (Joe's choice): Double, Triple, Quad, Bloodbath (5+).
- Streaks: Bloodthirsty 3, Rampage 5, Warmonger 10, Unstoppable 15, Legend of the Warpath 20 then every 10.
- Feats: Grudge settled, Nemesis down, Payback (who last killed you, within 10 min), Guardian (enemy who killed a guildmate in last 2 min), Clutch (<15% health), Outnumbered, Underdog (3+ levels above, or ??), Comeback (after 3+ deaths in a row), Back from the dead (within 1 min of reviving), Death avenged, Old rival (10th/25th/50th/100th kill of a player), Ground taken (kill on your dangerous ground), Flawless (full health).
- One line per kill: tier + best feat/milestone. Faction cry ("Blood and thunder!" / "For the Alliance!") 1 in 3 at streaks 10+ (Claude's assumption, never explicitly approved). Phrase lists in `Phrases.lua` (as drafted by Claude).
- "Streak ended at 7 by Aldric" for streaks of 3+, small and grey.
- **Deaths avenged**: a kill within 5 min near where you died (meaning fixed everywhere).
- Death wording (3.7.6): `died` 12 lines (5 need `{killer}`), `took` 5, `ended` 5. `DeathFields` deals a line number for every death.

### Chat and on-screen
- Own kill/death chat lines, worded as guildmates see them: `cfg.selfChat` default **on**; General tab "My kills and deaths in chat"; `/warpath chat [on|off]`. In quiet mode it replaces the old short line.
- Big text overlay for own multi-kills/streaks under the kill caption (upgrades in place): on/off, small/medium/large; `/warpath overlay [on|off|test]`.
- Quiet mode `/warpath quiet`: banners become chat lines, no sounds. `/warpath sound` for sounds only.

### Dangerous ground (3.7.0, replaced killing fields)
- PvP deaths on the haze grid. Walking onto ground where they add up: **Dangerous** (red, warning sound), **Contested** (amber, softer), **Your hunting ground** (gold, no sound). Guildmates' deaths add on.
- Out of combat only, never in neutral towns, once per area per session, never on top of a kill's big text.
- Settings: on-screen, in chat, warn after 1/2/3 deaths (default 2). `/warpath fields on|off` toggles both.
- War table shows "Dangerous ground nearby"; `/warpath zone` counts spots.

---

## Kill screenshots (absorbed PvPKillShot in 3.3.0)
- Open world only. Default **every kill**; option notable only (first kill of a player, grudges, avenged, streaks 3/5/every 10, 5+ kills of a player, and since 3.7 every feat and multi-kill).
- Caption: floating text (default), one-line strip, or none. Banners and sounds wait until after the shot. `cfg.shot.delay` before the shot.
- `/warpath shot [on|off]`, `shot all|notable`, `shot caption text|strip|none`, `shot test`. `/killshot`, `/pks` still work. Warns if PvPKillShot is installed.

## Chronicle (book)
- `/warpath chronicle` opens a book on a leather cover, 880 × 580. Tabs **Campaigns** and **Grudges** on the top edge.
- **Campaign** = play with gaps under 2 h (Joe's decision); a reload/quick relog continues it. Duration = time played. Empty campaigns (no kills/deaths/sightings) aren't saved. **Last 30 per character**; kills list cap 200, deaths 100 per campaign. Per character.
- Headline word by kills+deaths (Claude's call): Patrol 0, Clash 1–2, Skirmish 3–12, Battle 13–24, War 25+; place = bloodiest zone's first word, kept whole for multi-word names (Dun Morogh, Mount Hyjal…).
- Page: write-up paragraph, numbers, **7 highlights** (nemesis, favourite victim, bloodiest ground, longest streak + who ended it, grudges settled/deaths avenged, screenshot numbers, Best burst), Deeds and Losses list on the facing page (hover for level/race/guild; click → waypoint). "Earlier"/"Later" with spellbook arrows.
- "Nemesis" = the enemy you were fighting when you fell (client limitation).
- Share: small button beside "Deeds and Losses", or `/warpath chronicle share [guild|party|say|whisper <name>]` (default guild). Two plain chat lines, <255 chars each. No automatic posts.
- Login options (Chronicle tab of options): headline in chat (on), open the window (off). Fire only after a new campaign started and the last one had fighting.
- `/warpath chronicle chat` (full report to chat), `/warpath chronicle preview` (sample data).
- Names in class colours are darkened to read on parchment.

## Grudges (3.5.0)
- Ledger: kills each way, last seen, level/race/class/guild, Joe's note, dated encounters, Waypoint button.
- Add: `/warpath grudge [name]` (default target), the war table's **skull button** (left: target or last offered; right: opens ledger), "Inscribe a name..." in the book.
- **Only removed by Forgive** (button, or `/warpath grudge forgive <name>`). Joe's rule. Killing one marks it settled.
- Grudge sighted: banner with zone and history, crest + name on map 15 min, skull on nameplate and target frame.
- Auto-offer after 2/3/5 deaths to one player, or auto-add: **off by default**. Offer = plain chat line, accept within 10 min with the skull or `/warpath grudge` (Claude's call).
- `/warpath grudges` (ledger), `/warpath grudges chat`. Own realm not shown on grudges.

## Zone-entry stats (3.4.0)
- Chat line on entering a zone with history: kills, deaths, miles, enemies sighted, deaths avenged, best streak, plus one rank tag ("your deadliest zone" > "bloodiest ground" > "most-travelled" > "most-watched", only with real activity). Zeros omitted.
- Short line under the game's big zone name, neutral gold, **only while the zone name is visible** (`IsVisible()`, 3.7.3).
- Fires on entry and on re-entry after 30+ min away. Never in battlegrounds. Respects quiet mode.
- `/warpath zone chat|text [on|off]` (both default on), `/warpath zone test`. Busy hours removed; `z.hours` no longer recorded.
- Per-zone `z.kills`, `z.pdeaths`, `z.yards`, `z.sight`, `z.avenged`, `z.streak`, `z.bestStreak` (resets on any PvP death anywhere).
- Open: if the zone line feels too central under the zone name, move or shrink it.

## Guild sharing
- Shares sightings, kills, PvP deaths (with enemy names), and battle history (sync). **Never the trail.**
- Sightings: map-only, one a minute per spot. Kills/deaths always get through; only exact duplicates (guild + party copy) dropped.
- Guildmates' kills/deaths print a chat line from any zone ("Bob scored a triple kill in Felwood!").
- Sync: at login a GUILD hello; guildmates whisper back what changed since they last sent, trickled behind kills/deaths. `db.syncSent`. `CHAT_MSG_SYSTEM` "no player named" drops queued sync for that name.
- Inside instances: receive yes (3.7.8), send no, record nothing. A hello received inside goes unanswered until next login.
- `/warpath share [on|off]`, `share test`, `share status` (3.7.10: three diagnostic lines + last error), `share history`, `share sync`.

## Battlegrounds, arenas, dungeons, raids
- Warpath records nothing, shows no banners/caption/sounds, takes no screenshots, sends nothing, hides the war table, draws nothing; holds the options window until you leave. Multiple detection signals, re-checked every 5 s (`InsideMatch`, `S.inInstance`).

## War table (HUD)
- `/warpath table [on|off]` (old `hud`). "4 enemies seen (5 min)", dangerous/contested ground nearby, skull button for grudges.

## Options window
- `/warpath setup` (the name again since 3.6.4) or `/warpath options`. Tabs: General, Map, Screenshots, Chronicle & zones, Grudges. Settings shared by all characters.
- Opens itself once after **every** release (from 3.8.1; until 3.8.0 only after a feature release), with a "New in" box: `NEW_IN` entries keyed by version, showing every entry newer than `gdb.seenVersion` (`ns.NewIn.Older`: numeric, a test build before its release; at most 8 lines, newest kept). Header "NEW IN 3.8.1", or "NEW IN 3.8.0 TO 3.8.1" across several. Not when going back to an older version. 3.8.0's box covers roads, the trail, flights and the map reset; when the reset changed anything (`S.mapWasReset`) the window opens on the Map tab.
- **3.8.0 one-time map reset** (`Events.lua`, flag `cfg.mapReset = "3.8"`, inside `pcall`): every `C.LAYERS` layer and `cfg.guildHaze` on, `cfg.trailMin` to the 12 h default. Kept: `iconScale`, `shown`, `runHours`, `shimmer`. Settings only, no history. Reopen the box today: `/run WarpathGlobal.seenVersion = nil` then `/reload`.

## Commands (summary)
Everyday (`/warpath help`): `/warpath` (totals + "Type /warpath help"), `zone`, `chronicle`, `map`, `grudge`, `options`, `help all`.
Full list (`/warpath help all`): built from one table of `{command, description, group, everyday}` so both lists can't drift. Includes everything above plus `layer <name> [on|off]`, `replay [hours]` (up to 24), `waypoint death|kill`, `memory <days>`, `roads <1.5-10>` (scales every road band; replies with days of daily use to full gold, from `db.longDays`), `clear trail` (3.8: strokes and areas on every map, plus the stroke being recorded and the live area; roads, marks, runs kept), `clear zone`, `clear all` (asks to confirm within 10 s; grudges kept), `debug`, `debug kills`, `debug haze`.
Principles: noun-first names; every toggle takes `on|off` or toggles bare and replies with the new state; unknown command → one line + "Did you mean…"; old names stay as hidden aliases (`toggle`→`map`, `hud`→`table`, `revenge`/`lastkill`→`waypoint death|kill`, `heat`→`battle`, `recent`→`trail`, `shared`→`guild`).

## Saved data
- `db.v` history: 4 (3.3.x) → 5 (3.4) → 6 → 7 (3.6.0) → 8 (3.7.0) → 9 (3.7.1) → 10 (3.7.12, lane merge; old roads kept as `z.roadOld`). One `MigrateToV<n>` function each, in `Warpath.lua`; version 6 was missing from this list before 2026-11-23.
- Known deleting behaviour (all intentional and disclosed): 3.6.0 deleted `z.heat`; `Prune()` drops long-memory entries faded below 0.05; 3.6.1–3.6.3 `TownSweep()` wiped town cells (fixed 3.6.4, unrecoverable); 3.7.1 dropped guild layers filed under your own name; mark caps drop oldest past 300 per zone.

---

## Decision log

Who decided what. Add to this on every release. **Claude's calls are open to Joe's veto.**

| Date | Decision | By |
|---|---|---|
| 2026-11-20 | Solid trail line 5 min with fade (later superseded, see Today's trail) | Joe |
| 2026-11-21 | Explainer one-pager dropped | Joe |
| 2026-11-21 | Campaign gap 2 h; per character; window + chat; must look like WoW | Joe |
| 2026-11-21 | Deaths avenged = kill within 5 min near where you died, everywhere | Joe |
| 2026-11-21 | Busy hours removed; `z.hours` no longer recorded | Joe |
| 2026-11-21 | Pre-3.4 trail: no backfill | Joe |
| 2026-11-21 | Campaign share v1: plain chat, ≤2 lines, guild default, no auto-posts | Joe |
| 2026-11-21 | Corpse runs/flights own layer; corpse runs 24 h | Joe |
| 2026-11-21 | Flights 24 h; flight-route design | Claude (at Joe's request) |
| 2026-11-21 | Headline words, place naming; runs lifetimes 1/6/24/48 h; map button placement; shimmer path; route match tolerance 0.03; per-zone best streak resets on any PvP death | Claude |
| 2026-11-21 | Neutral towns: don't clutter; hide, don't erase | Joe |
| 2026-11 | Long memory fades on days played; flight routes linger once shown; grudges only removed manually; auto-grudges off | Joe |
| 3.5.x | Play-clock formula; route fade on ≥4 / off <2.5; grudge offer mechanics; book 880×580 | Claude |
| 2026-11-22 | Kill counting guarded; chain window 2 min | Joe |
| 2026-11-22 | Faction cry 1 in 3 at 10+; phrase lists as drafted | Claude (assumed) |
| 2026-11-22 | Guild haze 0.75 × strongest + 0.15 × rest, cap 3.6 | Claude (deviation, told Joe) |
| 2026-11-22 | Pins fade on calendar time with the durations above; show-all off at login | Joe |
| 2026-11-22 | Trail: dashes over the fade, footsteps removed (option 2 from renders) | Joe |
| 2026-11-22 | Trail length 15 min–24 h, default 1 h | Joe |
| 2026-11-22 | Own kills/deaths in chat, on by default; varied death lines | Joe |
| 2026-11-22 | Receive guild messages everywhere, including instances | Joe |
| 2026-11-22 | No waypoint on pin click | Joe |
| 2026-11-22 | Upgrade rule; versioning rule (3.7.x for tinkering) | Joe |
| 2026-11-22 | Declined: receiver-side multi-kill counting for guildmates on 3.6 | Joe |
| 2026-11-23 | 3.7.11: a guild kill whose wording can't be said with the fields it carried (grudge, no victim) prints as a plain kill, with our own pick of line. General (`Phrases.CanSay`), not a grudge special case | Claude |
| 2026-11-23 | No `embedded-libraries` in `.pkgmeta`: CurseForge rejected the upload over a library slug; the relations are cosmetic | Claude |
| 2026-11-24 | Moved the `3.7.11` tag to the packaging fix rather than cutting 3.7.12: no shipped file changed and nothing had been published under 3.7.11 | Joe |
| 2026-11-23 | Roads snap to the best-worn road within a cell; lanes merged on upgrade (`db.v` 10) | Joe (asked for the prototype) |
| 2026-11-23 | Merged lanes add their days, a shared last day counted once | Claude (open to veto) |
| 2026-11-23 | Old roads kept hidden as `z.roadOld` (save grows ~0.6 MB until dropped) | Claude (open to veto) |
| 2026-11-23 | Prototype installed under its own label (3.7.12-test, then -test2), not as 3.7.11 | Claude |
| 2026-11-23 | Hide scraps (≤2), stubs (≤3 unless gold); fold loops of ≤10; join gaps of ≤4, or ≤12 end to end, through ground walked ≥0.3 | Claude (thresholds); Joe (asked for continuity and loop folding) |
| 2026-11-24 | Road layout frozen between visits so roads only fade; fade all the way out | Joe (approved fix) |
| 2026-11-24 | Keep the fragment look; lynchpin threads at 0.5 | Joe |
| 2026-11-24 | Gilt look, deep relief; staged gilding; look smoothed along each road | Joe (picks); Claude (smoothing) |
| 2026-11-24 | Levels set by habit; gold thread day 6.5, full gold day 12.5 (middle ground), faction tiers at 2.5 and 4.5 weeks of daily use | Joe |
| 2026-11-24 | Gems scrapped; faction mark "streak" (streak, then embossed shade) | Joe |
| 2026-11-24 | Trail rework design: lingering areas that form live, grow, freeze on leaving; outline follows the ground covered (C), label = total time, visits on hover; links stop at the outline once you've left | Joe |
| 2026-11-24 | Link age: continuous colour gradient + dash rhythm; arrows about every third dash, 75% shaft | Joe |
| 2026-11-24 | Area thresholds (form 4 min within 0.05, join after 45 s, leave at 0.03 outside, 10-min gap closes, max 0.30 across, return merges); log time scale; area outlines share the rhythm; a link holds at the older area's level; live area solid; arrowhead at your position | Claude (open to veto) |
| 2026-11-24 | Time in an area counts while AFK too (`/afk` is often on while playing) | Joe |
| 2026-11-24 | No arrowhead at your position; the trail always joins your arrow (live tail line) | Joe |
| 2026-11-24 | Solid line 2.5 min (about a lap of the Undercity), then a small jump along the gradient | Joe |
| 2026-11-24 | Dashes smoothed along the path, medium (1.0 slot); dash, dash, arrow evenly spaced at every age | Joe |
| 2026-11-24 | Areas cover where you lingered: distances in yards, short trips past the edge join, recent trail joins on forming | Joe |
| 2026-11-24 | Area distances: form 150 yd, leave 90 yd, trips 2 min / 150 yd, recent 10 min, max 1200 yd; 4000 yd when the game can't give a map's width | Claude (open to veto) |
| 2026-11-24 | Re-entering an old area refreshes it; the visit list reads as visits; corridors stay lines; inside the area you're in only your last moments show | Joe (asked) |
| 2026-11-24 | Reopen after 1 min inside (15 s grace at the edge); visits merge under 10 min apart, fold under 2 min; a trip within 10 yd of its own line is a corridor; recent trail joins only milling points; inside the live area the line shows for 45 s | Claude (open to veto) |
| 2026-11-24 | Link holding keeps visibility only (colour and dashes show the link's own age); a loop back into the same area isn't held | Claude (open to veto) |
| 2026-11-24 | Roads, trail and flight-path rework ship together as **3.8.0**, "Roads, trails and flights" (a feature release: `NEW_IN` entry, options window opens once) | Joe |
| 2026-11-24 | Flights: lines only for the legs you fly most (not landings; not every flight), so the map never becomes a web; dashed (reads as flight, not road) | Joe |
| 2026-11-24 | Flight legs: royal blue with a dark casing (warm gold vanished on the real parchment); zone maps 65% of the first width, continent as rendered | Joe |
| 2026-11-24 | Flight-leg casing colour and alphas | Claude (open to veto) |
| 2026-11-24 | Flight legs on continent maps also at 65% width (test7) | Joe |
| 2026-11-24 | Flight legs: snap 100 yd, points every 30 yd; shown from about two days (fade in from 1.4); old routes merged as the stronger, not summed; no `db.v` bump (convert once per zone); today's flight no longer drawn on its own and its options row removed; legs under roads | Claude (open to veto) |
| 2026-11-24 | 3.8.0: one-time map reset, layers + trail length (keep icon size, map switch, corpse runs); trail default 12 h | Joe |
| 2026-11-24 | The reset also turns guild haze back on (it sits with the layers on the Map tab); the options window opens on the Map tab when the reset changed something | Claude (open to veto) |
| 2026-11-24 | Faction-mark trials removed (streak only); "plate" road style kept as a constant; `/warpath roads` keeps its 1.5–10 range and says days to full gold, or "never" above about 5.4 | Claude (open to veto) |
| 2026-11-24 | `z.roadOld` kept for 3.8.0, dropped in a later release | Joe |
| 2026-11-24 | The update window opens after every release, fix releases included | Joe |
| 2026-11-24 | `NEW_IN` keyed by version, showing everything unseen (8 lines max); a test build counts as before its release, so testers still see the release's box | Claude (open to veto) |
| 2026-11-24 | Built: forming needs movement in 3 of the 4 minutes; every re-entry is its own visit record (tooltip merges those under 2 min apart); dusk = faction deep 60% towards earth brown; hidden trail skipped by visit time; arrow bend judged at full length, tip fixed | Claude (open to veto) |
