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
- **Trail gives way to roads** (3.8.3, Joe's pick of four renders over his Eastern Plaguelands screenshot from the saved 2026-11-24 trail): where a dash runs along a road you can see (a drawn piece above 0.3 alpha, within `ROAD_NEAR` 0.8 road cells, about 30 yd), it's kept `TRAIL_ROAD_KEEP` 10 min, then fades out over `TRAIL_ROAD_FADE` 5 min. The same path drawn twice was most of the clutter. Off the roads, and with the roads layer off, the trail is unchanged. Decided by each dash's place and age alone, so it only fades (`OnRoad`, `e.roadSegs` from `DrawGround`). Not chosen: roads dimming inside lingering areas (barely showed on real data).
- **Old trail stays readable** (3.8.3, Joe's picks over his Dustwallow screenshot, where 9-hour-old trail had sunk into the marsh's own red-brown ink as dots): colour stays the faction's `deep` once there (no dusk), alpha 0.95 → 0.80, dashes shorten to 65% of a slot (no dots). Every dash sits on a dark casing (0.10, 0.04, 0.03 at 0.75 × its alpha, `TRAIL_CASE` 1.7 × its width, one draw sublayer below all dash colour; counted against `LINE_BUDGET`, not `DASH_BUDGET`).
- **Older passes give way to newer ones** (3.8.3, Joe's pick D): a mark is hidden where a mark at least `TRAIL_YIELD_T` 120 s newer runs within `TRAIL_YIELD` 2 dash slots, in about the same direction either way (`TRAIL_YIELD_COS` 0.85, about 30°). Crossings stay. Marks are drawn newest first, each zone's drawn marks kept in a pixel grid per redraw (`e.seen`, `Yields`). Every newer mark still on the trail counts, even one faded by a road, so an older pass can't reappear as time passes; only walking there again hides it. Out-and-back trips and the same stretch walked twice were drawing parallel rails.
- **Sharp turns stay solid** (3.8.3, Joe, from his Undercity hairpin screenshot, where the dashes at the turn broke into scattered pieces): where the smoothed path turns more than `TURN_SHARP` 1.4 rad (about 80°) between a dash slot before and a slot after, the trail never breaks into dashes there. The solid stretch runs `TURN_PAD` 1 slot before the turning part to 1 slot after, out to the full (fresh) length of any mark it touches, so the next dash keeps the usual gap (`TurnSpans`, `DrawTurn`, `MarkExtent`). It ages, fades, gives way and sits on the casing like a dash, in the look of its middle. Turns are judged at fixed places along the stroke (every quarter slot) and only where the path after them is final (a slot plus twice the smoothing window back from the stroke's end), so a stretch never moves. Rounding sharp turns with extra smoothing was rendered and dropped: it knotted junctions and would crawl at the end you're walking.
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
- **Open world vs cities (3.8.3-test1, not released):** on zone maps an area forms within **225 yd** (`FORM_YD`; was 150). On a city map (under `CITY_YD` 2000 yd wide; the Undercity is about 960) it stays **150 yd** and an area stops growing at **400 yd** (`CITY_SPAN_YD`; zones 1200). Joe's Plaguelands data (2026-11-24): questing roamed 200–330 yd every 4 min, so an hour of questing made only 4 small areas, and the east hub none. At 225 yd in the Undercity the area swallowed the corridor to the lift, so cities keep the tight radius.
- **Touching areas merge (3.8.3-test1):** while you're in an area, it takes in any area still on the trail whose outline touches it (hulls within 2 × `PAD`), as long as the result stays under the size cap: hull of both, visits of both in time order. Only while you're in it, so it's the same kind of change as an area growing. Merging across a gap was tried (within 90 yd) and dropped: the outline around both covered the road between them.
- **Reopening:** a minute inside an older area still on your trail (`REOPEN_T`) reopens it as a new visit, from when you entered; passing through doesn't. A few seconds out at the edge (up to 15) don't restart the count. Stepping back in within 10 min still reopens at once. (Joe, test4: re-entering an old area didn't refresh it)
- **Visit list on hover:** visits under 10 min apart read as one, and anything under 2 min folds into its neighbour (`Linger.Visits`). Stepping in and out at the edge had made a list of "1 min" entries. (Joe, test4)
- Forming needs movement through the 4 minutes (points in at least 3 of the 4 one-minute slices): standing still, or a few steps then standing, is not lingering.
- Leaving = more than `MARGIN` 0.03 outside the outline. The walk out never joined, so it stays a link. The outline then freezes and never changes. A 10-min trail gap (logged off) also closes it; an area stops growing past 0.30 across.
- Stepping back inside within 10 min (`REENTER`) reopens it with a new visit record. Every re-entry is its own record, so a visit's times cover only time inside; the tooltip shows visits under 2 min apart as one.
- Time counts per sample (twice a second) while inside, AFK included: `/afk` is often on while you're still playing (Joe).
- **Return visits:** lingering again on or next to an area that's still on the trail reopens it. One outline, the label shows **total** time there; hovering lists the visits ("18m at 2:10 pm, 9m at 2:48 pm"). The area's age follows the latest visit, so revisiting refreshes it. (Joe)
- **Shape:** C — follows the perimeter of the ground covered (convex hull, padded and rounded). Label above it: time spent, e.g. "26m", "2.7h". **Look (3.8.3, Joe's pick):** WoW's standard yellow (`NORMAL_FONT_COLOR`, 1/0.82/0) on a soft dark patch (the addon's `glow.tga` tinted 0.06/0.03/0.02, text width + 22 by 26 px, alpha 0.7 × the label's). Until 3.8.3 it was the area's own colour moved 35% towards gold, at the area's alpha + 0.2, which on the parchment was a dim red or brown and nearly vanished on old areas. Label alpha is `min(1, 0.2 + 1.6 × area alpha)`: full strength for most of the trail's life, fading only in its last quarter. Picked from eight styles rendered over his Undercity screenshot (outline, fade less, backing, stronger colour, dark ink, larger); he asked for the yellow on top of the backing.
- **Inside the area you're in,** only your last 3 s of line show (`SHOW`, Linger.lua), plus the tail to your arrow: not a scribble of the last minutes. From 3.8.3 it fades like a comet's tail: full just behind you, brightness `(1 - age/SHOW)^CURVE` (`CURVE` 1, an even fade) and width down to `TAPER` (half) at the far end, each piece by its own age, so it only fades where it lies. The comet is drawn from where you've been while the map is open (sampled every 0.1 s, `TRACE_STEP` in Map.lua, memory only), not from recorded steps: steps are about 12 yards apart and the map redraws every 2 s at most, so a comet built from them was one straight line to your arrow at one brightness that grew, then vanished at each redraw (Joe, test10 and test13). Each piece fades every frame by the age at its middle. Inside the area the tail line to your arrow gives way to the comet; recorded trail isn't drawn there at all. Opening the map inside an area shows no comet until you move; it grows in over 3 s. Steps that haven't joined yet (`LAG`, 45 s) lie outside the outline, so they still show. (Joe, test4; 45 s until 3.8.2, when Joe asked for ~3 s: "the point of the zone is to stop scribbling the map")
- **After you leave, it's clean:** links stop at the outline and nothing inside is drawn. Dashes inside are hidden from the start (in the area you're in too) and stay hidden; only the solid line, which shows inside while you're there, fades out over ~1 min after you leave. (Joe's sketch; in test3 the hidden dashes came back for that minute, fixed)
- **Saved** as `z.areas` (per zone): `h` the convex hull (flat, quantized), `v` visits `{ s, e, t }`, `e` last time inside, `w` a change counter for the outline cache. Recomputing from strokes wouldn't be stable (`Simplify()` changes points when a stroke closes). Pruned with the trail after 24 h (`KEEP_HOURS`). Not shared; old versions ignore the key. No `db.v` bump.
- Live state (the window, pending steps, which area you're in) is memory only. After a `/reload` inside an area, the next sample re-enters it as a new visit.
- **Drawing cost:** trail from a visit is inside the outline by construction (every step taken during a visit joined it), so hidden trail is skipped by its time alone (`hide` spans: each visit trimmed 20 s at the start and `LAG` + 20 s at the end) before any cutting; the rest is cut exactly against the outline (`Linger.Clip`, with a fits-inside circle as a fast path). Timed in the harness on a 3-hour synthetic session: 6.5 ms per redraw at a 1 h trail (3.8 before), 8 ms at 4 h and 24 h (10-13 before), with a fifth of the lines.

**Links (lines between areas) and age**
- Last **2.5 min**: solid line (`LINE_SOLID` 150; was 5 min: a lap of the Undercity stayed all solid). After that, dashes anchored to the ground, as today, starting with a small jump along the colour gradient (`TRAIL_STEP` 0.15) so the change is noticeable early; then the slow fade. (Joe)
- **Colour:** (from 3.8.3: faction colour → faction `deep`, then it stays; dusk, below, is gone; see Today's trail) one continuous gradient, faction colour → faction `deep` → dusk (desaturated, darker; never paler), on a time scale that moves fast early (5 m, 15 m, 1 h, 4 h, 24 h roughly evenly spaced). Opacity eases off along it and fades to nothing over the last quarter of the trail length. (Joe: gradient, not steps)
- **Rhythm:** long dashes → short dashes → dots, in three bands on the same scale, crossing over gently. (From 3.8.3: long → slightly shorter, 85% → 65% of a slot, no dots.)
- **Area outlines share the colour and fade of their age**, so a link never looks weaker than the area it leads to. The area you're in: solid, full colour.
- **Past outlines drawn like the trail (3.8.3, Joe's pick C, 2026-11-26):** the trail's own dash (one per slot, 85% → 65% of it with age) on the same dark casing, so areas stay in step with the links. Replaces pick H, below. The outline of the area you're in stays solid, uncased like the fresh solid line.
- **Past outlines' dashes (3.8.3, Joe's pick H; replaced by pick C above):** closer together than the trail's, so old areas stay joined up instead of thinning to sparse dots. One dash every 0.75 trail slots (about 7.5 px on a zone map), filling 80% of it when fresh down to 55% at the trail's end (`AREA_PERIOD`, `AREA_NEW`, `AREA_OLD` in `Map.lua`). Until 3.8.3 they used the trail's own rhythm: a dash every 10 px shrinking to 25%, which at 3 h+ was a sparse row of faint dots. Joe first picked D (the trail's dash, gap capped at a third of a slot), but a capped gap changes the period with age, so every dash slid along the outline; the only-fade test caught it. The period is now fixed, and H was the fixed version closest to D.
- **Links hold:** a link stays at least as visible as the older of the two areas it joins, so areas don't hang off faded links. Revisiting an area can strengthen its old links again (an event, not time passing).
- **Dusk** (until 3.8.3, removed: on Dustwallow it matched the map's ink) was the faction's `deep` colour 60% of the way to earth brown (0.36, 0.27, 0.18): reddish brown for the Horde, slate for the Alliance.
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
- **On a continent or the world (3.8.3, Joe: "take a bit more artistic liberty; keep the start, path, end as accurate as possible without making the dashes look janky"):** at continent scale a leg's 30-yd points are under a pixel apart, so dashes drawn along them came out as kinked shapes. Found on a per-leg render of Lethality's Kalimdor: legs recorded on the **continent map itself** (the game placed you on Kalimdor or Eastern Kingdoms, not a zone) were drawn zone-style, at zone width and unsmoothed; and a leg's ends, joined to the nearest point of the leg it left or met (sometimes one not drawn), made small hooks. Now every leg on a continent view, its own included (`mapType` ≤ 2), goes through `DrawLegsFar`: an end that doubles back (over 120°) within `hook` 4.5 line widths is dropped; the leg is simplified (Douglas-Peucker, `simplify` 3.4 widths, ends kept) and rounded (`smooth` 3 passes of corner cutting, ends fixed); a leg under `tiny` 16 widths across (about 14 px: a flight circling in to land or take off) isn't drawn; the leg is **cut at sharp bends** (over about 60°, `bendcos` 0.5, judged `bend` 8 widths either side; a piece shorter than a dash and its gap merges with its neighbour), and **each piece gets fitted dashes**: whole dashes of the usual length, the gaps sharing the rest evenly, half a gap at both ends, so every bend and every hand-over between legs is one ordinary gap (Joe, after the first fix dropped whole dashes and left long holes); each dash is a **straight stroke** between its two ends on that path; **one look**: a leg is shown from halfway up the zone map's fade-in (strength 1.7) and drawn whole, never half-faded grey pieces along a route. Dashes are queued and drawn most-flown first (`FlushAir`): a dash of another leg within `rail` 10.7 widths gives way if it runs alongside (within about 30°, either way) or, for a leg's first or last dash, if it comes within `touch` 3.5 widths of the stronger dash (two dashes meeting at a leg junction read as an L, V or T; mid-leg that's a crossing, which stays). Width **0.00088** (75% of 0.00117; Joe). The shape depends only on the leg's points, which change only when you fly; all leg points fade at the same rate, so which leg is stronger changes only when you fly. Zone maps unchanged. Rails and the straight dashes were Joe's picks from renders; the rest are Claude's calls (decision log).
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
- **Scores** (with the `marks` layer, 3.8.3): "kills : deaths" in **blue** when you're clearly ahead, **yellow** when it's close (within one fight, or within a quarter of the fights), **red** when clearly behind (`ns.Standing`). Joe's picks, 2026-11-25, from renders over his screenshots.
  - A zone's own map: your crest and the score in the top-left corner beside the game's round button, on a soft dark patch, from the first kill or death. Attached to the map frame, not the canvas, so zooming doesn't move it; hidden in replays (`MapButton.lua` `ZoneStanding`).
  - A continent (Kalimdor, Eastern Kingdoms): a small score (`GameFontNormalSmall`, no crest) on a dark patch at each zone's centre, from the first fight (was 3, with the winning side's crest and colour). The most fought-over zone keeps its centre; a score that would overlap another score steps to the nearest clear spot (down a step, up a step, down two, ...). Scores never move for pins and draw above them on their dark patch (Joe, after test5, where scores dodging pins jumped about as pins came and faded).
  - The world view (both continents): one score per continent (`C.CONTINENTS`), its zones' totals, a size up, below the continent's middle so it clears the printed name; no zone scores.
- **Crowded pins** (continent and world views only, 3.8.3; Joe: "all the pins represented; if there's too many, they should combine to a big sword or big skull"): every pin is drawn, but kills (yours and guildmates') within about a pin and a half of each other chain into one group, and so do deaths. A group of 3 or more (`C.CROWD_MIN`) is one sword or skull a little bigger than a pin (1.1× plus 0.04× per pin, at most 1.5×) with no number on it, guildmates' blue when they're most of it, as strong as its freshest pin. (test3 drew 1.5–2.4× with a white count under it; Joe after test3: "a little big", and picked smaller with no count from renders of four looks over his screenshots, 2026-11-26. Declined: a fanned stack, a count badge at the corner, a dark patch under the pin.) Big pins that would overlap are pushed apart. Hover: "12 kills here", yours and guildmates', "Zoom in to see each one". Groups come from the pins' places only, so a big pin changes only when pins are added or fade out (it can split back into single pins). Zone maps never combine.
- Kill mark fields: victim `Name-Realm` (`m.f`), screenshot number/predicted file (`mark.shot`, `mark.file`), `tag` (first/grudge/avenged/streak), `streak`, `times`, `av`, `mk`, `ft`; level/race/guild when visible. Death marks: killer `kn`, `kc`, killer full name.

### Sightings (`sightings`)
- Live crests of recent enemy sightings, 15 min, fading. Guild-shared crests (`shared`) are memory-only (lost on reload).
- Not recorded in neutral towns (no crests, no war-table count, no haze, nothing shared, no zone-stat count). Guildmates' sightings from towns ignored. Kills, deaths and grudge alerts still work in towns.
- Sightings count in zone stats (`z.sight`, one per enemy per 2 min).

### Map button and minimap button
- Map button: crossed swords, top-right of the world map's scroll container; shift-drag to move (position saved account-wide). Left-click: show/hide all, silently (3.8.3; the tooltip says "Hidden (still recording)", `/warpath map` still replies in chat). Right-click: layers menu (incl. battle haze, guild haze, show all history). Greyed in battlegrounds.
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
- From 3.8.3 three plain switches (Settings, Alerts), no hidden master switch (`docs/settings-review.md`):
  - **Announce on screen** (`cfg.announce`, default on): the raid-warning banner for each kill, big text (`Overlay`) for multi-kills, streak milestones and "Streak ended"; big text size small/medium/large stays. Off: the kill goes to chat (your guild-style line if "Also in chat" is on, else the short own line), other banners (`ns.Notice`) print to chat, and on-screen ground warnings go to chat.
  - **Also in chat** (`cfg.selfChat`, default on): one line per kill or death, worded as guildmates see them; `/warpath chat [on|off]`.
  - **Play sounds** (`cfg.sound`): alert sounds and the book's page sounds; `/warpath sound`.
- Until 3.8.2: quiet mode (`cfg.quiet`, shown inverted as "Raid-warning banners and sounds") also stopped every alert sound, the big text, on-screen ground warnings and the zone line; and a separate big-text switch (`cfg.overlay`) sent multi-kills to the banner instead. 3.8.3's upgrade (`Events.lua`): quiet on becomes announce off, sounds off and the zone line off; both keys are dropped. `/warpath quiet [on|off]` is now a shortcut for announce and sounds together; `/warpath overlay test` still shows a sample.

### Dangerous ground (3.7.0, replaced killing fields)
- Walking onto ground you've fought on: **Dangerous** (red, warning sound; deaths at least twice your kills), **Contested** (amber, softer), **Your hunting ground** (gold, no sound; kills at least twice your deaths). The tone is from your kills and PvP deaths within 2.5 cells (`Tally`).
- What sets it off (3.8.3, Joe: "an 'activity here' tag to fire hunting/contested/dangerous"): your own battle haze there (`BattleField(z, false)`: kills and deaths alike, spread and fading as on the map) reaching `cfg.groundAfter` fights (1/2/3, default 2). Until 3.8.2 only your deaths counted (the death field), so a hunting ground where you'd never died never spoke. Guildmates' deaths only add a sentence ("Guildmates have died here twice").
- Out of combat only, never in neutral towns, once per area per session, never on top of a kill's big text.
- Shown in the kill big text's frame, but held long enough to read (3.8.3): 4–6.5 s at full strength, about a second per 15 letters of the line under the title (`Overlay.ReadHold`). Kill text keeps its short flash (1.2 s hold). A kill while a warning shows replaces it.
- Settings (Alerts, "Ground you've fought on"): on screen, in chat, after 1/2/3 fights (default 2). `/warpath fields on|off` toggles both. The "Ground taken" feat and the war table's "dangerous ground nearby" use the same trigger.
- War table shows "Dangerous ground nearby"; `/warpath zone` counts spots.

---

## Kill screenshots
- Open world only. Default **every kill**; option notable only (first kill of a player, grudges, avenged, streaks 3/5/every 10, 5+ kills of a player, and since 3.7 every feat and multi-kill).
- Caption: floating text (default), one-line strip, or none. Banners and sounds wait until after the shot. `cfg.shot.delay` before the shot.
- `/warpath shot [on|off]`, `shot all|notable`, `shot caption text|strip|none`, `shot test`. (3.8.3 removed the `/killshot` and `/pks` aliases and everything else kept for the older PvPKillShot addon.)

## Chronicle (book)
- `/warpath chronicle` opens a book on a leather cover, 880 × 580. Tabs **Campaigns** and **Grudges** on the top edge, left of the title plate; **Settings** and **Warpath** right of it (3.8.3).
- **Layout C** (3.8.3, Joe's pick of three mocks): topics under small faded capitals with a thin rule (`Topic` in `Chronicle.lua`), used on every page.
- **Warpath tab** (3.8.3, Joe: players may never find the chronicle, so the update notes moved here): left page a welcome (what Warpath does, where the book and the map button are, `/warpath help`), a **Guild sharing** checkbox (the same switch as Settings, Guild, and `/warpath share`; no Settings button since test10, the tab is beside it); right page **What's New**, every `NEW_IN` release newest first, Earlier/Later to older ones. Each release: its version large in red, an optional short `title` small and faded beside it, a small red **NEW** mark when it's newer than the account last saw, a rule; then its lines, grouped under topics where the entry has `"## Topic"` lines (from 3.8.3). Notes are one short line each, at 13 pt (Joe's pick C, 2026-11-26). A release too long for the page carries on to the next, headed "(continued)"; the page shows "1 of N" at its foot. After every install or update the book opens here by itself (`MaybeShowSetup` → `Chronicle.News`), held out of combat and battlegrounds; releases newer than the account last saw are marked NEW (none on a first install). Closing the book, any way, marks the release seen (`gdb.seenVersion`). Always reachable from the tab. Joe asked for it to be permanent.
- **Campaign** = play with gaps under 2 h (Joe's decision); a reload/quick relog continues it. Duration = time played. Empty campaigns (no kills/deaths/sightings) aren't saved. **Last 30 per character**; kills list cap 200, deaths 100 per campaign. Per character.
- Headline word by kills+deaths (Claude's call): Patrol 0, Clash 1–2, Skirmish 3–12, Battle 13–24, War 25+; place = bloodiest zone's first word, kept whole for multi-word names (Dun Morogh, Mount Hyjal…).
- Page: write-up paragraph, numbers, **Highlights** (nemesis, favourite victim, bloodiest ground, longest streak + who ended it, grudges settled/deaths avenged, screenshot numbers, Best burst; from 3.8.3 only those with something to say, under a topic), Deeds and Losses list on the facing page (hover for level/race/guild; click → waypoint). From 3.8.3 the deeds sit under the zone's name, a new heading each time the zone changes so the night still reads in order; each row is the time, a sword or skull, the name and level (or "Fell to …"), and the tag (first blood, streak, double kill, feat) in red on the right. "Earlier"/"Later" with spellbook arrows.
- "Nemesis" = the enemy you were fighting when you fell (client limitation).
- Share: small button beside "Deeds and Losses", or `/warpath chronicle share [guild|party|say|whisper <name>]` (default guild). Two plain chat lines, <255 chars each. No automatic posts.
- Login options (Settings, Zones & panels): headline in chat (on), open the book (off). Fire only after a new campaign started and the last one had fighting.
- Grudges (3.8.3): the ledger lists kills · deaths on the right, or "no blood yet" (the dot leaders are gone); a grudge's encounters run newest first under a heading for each day ("Today", "November 21"), with the time beside each.
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
- Fires on entry and on re-entry after 30+ min away. Never in battlegrounds. Until 3.8.2 quiet mode also hid the line under the zone name; from 3.8.3 only its own setting does.
- `/warpath zone chat|text [on|off]` (both default on), `/warpath zone test`. Busy hours removed; `z.hours` no longer recorded.
- Per-zone `z.kills`, `z.pdeaths`, `z.yards`, `z.sight`, `z.avenged`, `z.streak`, `z.bestStreak` (resets on any PvP death anywhere).
- Open: if the zone line feels too central under the zone name, move or shrink it.

## Guild sharing
- Shares sightings, kills, PvP deaths (with enemy names), and battle history (sync). **Never the trail.**
- Sightings: map-only, one a minute per spot. Kills/deaths always get through; only exact duplicates (guild + party copy) dropped.
- One kill, said once (3.8.3, receiver-side, so it works with guildmates on older versions): when several of you get credit for one enemy, the first report (yours or a guildmate's) prints a line and pins; later reports of it fold in silently, with no line and no pin, but still count in that guildmate's own haze layer. Same enemy: same victim name on the same map within 30 s; a report without a name (before 3.7, or an unnamed kill) matches by place, within 0.015 of the map and 10 s. Only different reporters fold, so one guildmate's two kills stay two. Your own kill landing after a guildmate's report of it skips your own chat line and takes their pin off the map (your skull is there). `/warpath share status` counts folds as "repeat kills of one enemy". Session memory only, nothing saved.
- Guildmates' kills/deaths print a chat line from any zone ("Bob scored a triple kill in Felwood!").
- Sync: at login a GUILD hello; guildmates whisper back what changed since they last sent, trickled behind kills/deaths. `db.syncSent`. `CHAT_MSG_SYSTEM` "no player named" drops queued sync for that name.
- Inside instances: receive yes (3.7.8), send no, record nothing. A hello received inside goes unanswered until next login.
- `/warpath share [on|off]`, `share test`, `share status` (3.7.10: three diagnostic lines + last error), `share history`, `share sync`.

### Newer-version notice (3.8.1)
- The sync hello carries the sender's version (`1|H|<full>|<version>`); `Sync.lua` `CheckVersion`. A version newer than yours (`ns.VersionOlder`, shared with the update window) prints one line: the version, yours, and "Update from the CurseForge app, as Warpath Forever". Once a session; again only for an even newer one. Test builds (`3.8.2-test1`) and anything not `x.y.z` are ignored.
- Only between guildmates with sharing on, because the hello is sent and read only then (`cfg.share` is off by default). Nothing new is sent when sharing is off.

## Battlegrounds, arenas, dungeons, raids
- Warpath records nothing, shows no banners/caption/sounds, takes no screenshots, sends nothing, hides the war table; holds the update window (the chronicle's Warpath tab) until you leave. Multiple detection signals, re-checked every 5 s (`InsideMatch`, `S.inInstance`).
- What you look at by hand still works (3.8.3, Joe: resting meant no pins or spam from the match, not hiding the rest of the world). The map draws every map except the one you're standing in (`Map.lua` `InsideMap`; an unreadable position draws nothing), so the battleground's own map stays clean. The map button toggles and opens the layer menu; the chronicle and the minimap button open by hand. The chronicle still closes on the way in.

## War table (HUD)
- `/warpath table [on|off]` (old `hud`). "4 enemies seen (5 min)", dangerous/contested ground nearby, skull button for grudges.

## Settings (the chronicle's Settings tab, 3.8.3)
- Joe, 2026-11-26: "make the chronicle the main way to interact with everything - including settings now". The options window (`WarpathSetup`) is gone. `/warpath setup` (or `options`, `config`, `settings`), the minimap button's right-click and the Warpath tab's Settings button open the book on this tab. Shared by all characters.
- Left page: the sections, each a name and a line on what's in it: **Alerts, Map, Guild, Screenshots, Zones & panels, Grudges**. Right page: the open section's controls under topics, ink on parchment, hints in faded small text only where a name isn't enough. Built from one table, `SPEC` in `Options.lua` (kinds: topic, note, check, pair, radios, layers, icons); a row with `when` greys out while it does nothing (big text size with announcing off, guild rows with sharing off, and so on).
- Every change applies at once (no "To war" button). **Restore defaults**, bottom right, resets the open section only, after a confirm.
- The wording came out of a review of every setting (`docs/settings-review.md`, Joe's decisions recorded there). Dropped from the page: "Show all pin history" (resets at login; it's in the map button's menu and `/warpath history`), the shimmer switch (`cfg.shimmer` still read, default on, no control), the "Open the chronicle" and "Open the ledger" buttons. Added: guildmates' kills and deaths in chat (`cfg.guildChat`, default on; their pins stay either way), how long recent flights stay (`cfg.flightHours`, which had no control), Restore defaults.
- Guild sharing (`cfg.share`) is on by default from 3.8.3 (Joe). Only new installs take it: an existing account keeps its saved value, and account settings seeded from an older character's (pre-3.3) keep that character's choice, off if it never set one.
- `NEW_IN` (in `Options.lua`) is one entry per release, keyed by version (`ns.NewIn.Older`: numeric, a test build before its release, two test builds of one release by their number, so a new test build opens the book too). From 3.8.3 an entry can carry a `title` and `"## Topic"` lines (`Unseen` skips them).
- **3.8.0 one-time map reset** (`Events.lua`, flag `cfg.mapReset = "3.8"`, inside `pcall`): every `C.LAYERS` layer and `cfg.guildHaze` on, `cfg.trailMin` to the 12 h default. Kept: `iconScale`, `shown`, `runHours`, `shimmer`. Settings only, no history. To see the update opening again: `/run WarpathGlobal.seenVersion = nil` then `/reload` (the Warpath tab is always there anyway).

## Commands (summary)
Everyday (`/warpath help`): `/warpath` (totals + "Type /warpath help"), `zone`, `chronicle`, `map`, `grudge`, `setup`, `help all`.
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
| 2026-11-24 | Reopen after 1 min inside (15 s grace at the edge); visits merge under 10 min apart, fold under 2 min; a trip within 10 yd of its own line is a corridor; recent trail joins only milling points; inside the live area the line shows for 45 s | Claude (open to veto; **vetoed 2026-11-24**: Joe wants ~3 s, see `open-items.md`) |
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
| 2026-11-24 | 3.8.1: tell players when a guildmate runs a newer version; `/warpath trail clear` | Joe |
| 2026-11-24 | Version check rides on the existing sync hello, so it works only with sharing on (sending a version ping with sharing off would break the opt-out); once a session, again for an even newer one; test builds ignored; `trail clear` listed under Map, `clear trail` still works | Claude (open to veto) |
| 2026-11-24 | Built: forming needs movement in 3 of the 4 minutes; every re-entry is its own visit record (tooltip merges those under 2 min apart); dusk = faction deep 60% towards earth brown; hidden trail skipped by visit time; arrow bend judged at full length, tip fixed | Claude (open to veto) |
| 2026-11-24 | 3.8.2: inside the live area only the last 3 s of line show (`SHOW`), separate from `LAG` 45 s, so areas still grow as before; old areas keep hiding your line until a minute inside reopens them (no tail there) | Joe |
| 2026-11-24 | 3.8.3-test1: a wider forming radius in the open world, a tighter one in cities; areas next to each other merge (Joe asked for a bigger central area and whether cities need their own rules) | Joe |
| 2026-11-24 | Forming 225 yd on zones; city = map under 2000 yd wide, 150 yd and a 400 yd cap; "touching" = outlines meet (2 × `PAD`); merge only into the area you're in | Claude (open to veto) |
| 2026-11-25 | 3.8.3: ground warnings held 4–6.5 s by line length (1 s per 15 letters) instead of the kill flash's 1.2 s; a second ground warning waits for the first, a kill replaces it | Claude (open to veto) |
| 2026-11-25 | 3.8.3: the map button's left-click no longer prints a chat line; `/warpath map` still does | Joe |
| 2026-11-25 | 3.8.3: repeat kill reports fold silently (no "A and B killed X" line); windows 30 s by name, 10 s and 0.015 by place without one; folded reports still add to that guildmate's haze; your own later kill removes the guildmate's just-received pin of it | Claude (open to veto) |
| 2026-11-25 | 3.8.3: every mention of Wake and PvPKillShot comes out of the addon, since only Joe ever had them: the PvPKillShot warning, its field in `/warpath debug`, the `/killshot` and `/pks` aliases; the Wake warning was declined | Joe |
| 2026-11-25 | 3.8.3: the public `Warpath` global (kill callbacks, session and kill-count reads) removed with them, since PvPKillShot was its only user | Claude (open to veto) |
| 2026-11-25 | 3.8.3: area time labels in WoW yellow on a soft dark patch (style D, yellow text) | Joe |
| 2026-11-25 | 3.8.3: backing made from the addon's own `glow.tga`, not a new texture; patch alpha 0.7; label alpha `min(1, 0.2 + 1.6a)`, so it stays full until the trail's last quarter | Claude (open to veto) |
| 2026-11-25 | 3.8.3: zone standing on the zone's own map, top-left corner | Joe |
| 2026-11-25 | 3.8.3: past area outlines dashed closer together, every 7.5 px, 80% -> 55% (H, after D was found to crawl) | Joe |
| 2026-11-25 | 3.8.3: the corner standing shows from the first kill or death (continent still needs 3); font `GameFontNormal`, one size up from the continent's; same dark patch as area labels; hidden in replays | Claude (open to veto) |
| 2026-11-25 | 3.8.3: welcome and What's New move into the chronicle on a permanent Warpath tab; the book opens there after every update instead of the options window | Joe |
| 2026-11-25 | 3.8.3: the Warpath tab sits right of the title plate (no room left of it); closing the book any way marks the release seen (the options window counted only "To war" or its close button); a first install marks nothing "new"; the welcome text; release notes paged by what fits | Claude (open to veto) |
| 2026-11-25 | 3.8.3: older trail gives way to the roads it runs along (option B of four); roads dimming inside areas not chosen | Joe |
| 2026-11-25 | 3.8.3: trail on roads kept 10 min, fades over 5; "along" = within 0.8 road cells; only roads drawn above 0.3 alpha count | Claude (open to veto) |
| 2026-11-26 | 3.8.3: old trail stays crimson (no dusk), fades less, long dashes (65%, no dots), dark casing 1.7×; an older pass gives way to a newer one alongside it (D) | Joe |
| 2026-11-26 | 3.8.3: past area outlines in the trail's dash on the casing (C); sharp turns stay a solid line from a bit before to a bit after (Joe's own spec after seeing B); rounding dropped | Joe |
| 2026-11-26 | 3.8.3: continent flight legs 75% width, weaker legs alongside give way, smoothed with straight dashes, the continent's own legs included | Joe |
| 2026-11-26 | 3.8.3: continent flights: dashes fitted per piece between sharp bends (not dropped at bends and junctions, which left long holes); tiny legs hidden; every shown leg drawn whole; the trail's solid-turn rule rendered and rejected for flights (squiggles); recording rework to the backlog | Joe |
| 2026-11-26 | 3.8.3: continent flights: bend = over 60° within 8 widths either side; tiny = under 16 widths across; shown from strength 1.7 (halfway up the fade-in); junction touch 3.5 widths, a leg's end dashes only | Claude (open to veto) |
| 2026-11-26 | 3.8.3: continent flights: hook = an end doubling back over 120° within 4.5 widths; simplify 3.4 widths, 3 rounding passes; rail 10.7 widths (~9 px), alongside = within ~30°; a dash touching a stronger leg's dash end within 2.5 widths gives way (junction Ls); rails only on continents | Claude (open to veto) |
| 2026-11-26 | 3.8.3: "sharp" = over 80° across a slot either side; solid reaches 1 slot past the turning part (0.5 rendered too short) and out to the marks it touches; a turn's look is its middle's age; the live area's solid outline stays uncased | Claude (open to veto) |
| 2026-11-26 | 3.8.3: giving way needs the newer pass 2+ min newer and within ~30° (either way); faded-on-road newer marks still count; casing on dashes only (not the solid line, not area outlines) and outside `DASH_BUDGET`; area outline dash length keeps its old age scale | Claude (open to veto) |
| 2026-11-25 | 3.8.3 continent and world maps: blue/yellow/red scores; world view one score per continent; continents a small score per zone on a dark patch; every pin drawn, crowded ones combine into a big sword or skull with a count | Joe |
| 2026-11-26 | Combined pins at most 1.5× a pin (was 2.4×), and no count under them; the tooltip still says how many | Joe |
| 2026-11-26 | Scores step around pins, not pins around scores (test5; Claude's argument, Joe agreed) | Joe |
| 2026-11-26 | Inside a battleground, other maps still draw; only the map you're standing in stays clean (Joe clarified the 3.7 rule: no pins or spam from the match, not hiding everything) | Joe |
| 2026-11-26 | 3.8.3: inside the live area the 3 s line fades like a comet instead of ending sharply; kept at 3 s (10/20/30 s comets rendered and declined) | Joe |
| 2026-11-26 | 3.8.3: settings move into the chronicle as a Settings tab; the options window goes (Joe: "make the chronicle the main way to interact with everything - including settings now") | Joe |
| 2026-11-26 | 3.8.3: What's New, Campaigns and Grudges in layout C (topics under small capitals), Joe's pick of three mocks | Joe |
| 2026-11-26 | 3.8.3 settings review, all of Claude's proposals except one: quiet mode, the banner switch and big text become "Announce on screen" + "Also in chat" + "Play sounds"; no separate big-text switch; no shimmer switch; a switch for guildmates' kill lines in chat; guild sharing on for new installs and a switch on the welcome page. Corpse runs and recent flights keep **separate** lengths (Joe's one change) | Joe |
| 2026-11-26 | 3.8.3 settings: six sections (General split into Alerts and Guild; war table and minimap button join zones and the book as "Zones & panels"), because General wouldn't fit one page; changes apply at once, no save button; Restore defaults per section with a confirm; "Recent flights" as the label for `flightHours`; layer hints only on battle haze, roads and sightings; grudge making as "When the same player keeps killing me:" + action + "after N deaths"; an account that had big text off now gets big text with announcing (it went to the banner before); an account with shimmer off keeps it off with no switch | Claude (open to veto) |
| 2026-11-26 | 3.8.3 chronicle: a release's "new since you last played" became a small red NEW mark; each 3.8.x release can have a short title; a deed row drops "Slew … in <zone>." for the name, with the zone as the heading and the tag on the right; a zone heading repeats when you come back to a zone later that night; highlights with nothing to say are left out; grudge encounters show only the time, under day headings | Claude (open to veto) |
| 2026-11-26 | After test9 in game: the welcome page's Settings button goes (the tab is beside it); a new test build opens the book like a release (test8 → test9 stayed shut) | Joe |
| 2026-11-26 | After test9: "with guildmates' fighting" sits indented under Battle haze (it adds to the one haze; it read like a layer of its own); 8 px above every heading after the first (headings sat on the line above in game) | Claude (open to veto) |
| 2026-11-26 | Ground warnings fire on any fighting of yours there (the haze), not only your deaths, so hunting and contested ground speak too | Joe |
| 2026-11-26 | That trigger is your own haze, faded like the map's (not all-time pin counts), at the same 1/2/3 setting, now "fights"; the settings heading becomes "Ground you've fought on" with "On screen" / "In chat"; guildmates' fighting doesn't set it off | Claude (open to veto) |
| 2026-11-26 | 3.8.3: the comet fades evenly (`CURVE` 1, not the faster 1.5) and thins to half width (`TAPER` 0.5); fade per piece by the age at its middle | Claude (open to veto) |
| 2026-11-26 | 3.8.3: the comet fades every frame, not only at redraws; the tail to your arrow is its head, faded by its middle's age (test10's comet skipped) | Claude (open to veto) |
| 2026-11-26 | Replaced after test13 (Joe: "a full strength line forms behind me for 3 seconds and then the whole thing disappears"): the comet is drawn from your position every 0.1 s while the map is open, kept in memory only, instead of from recorded steps at redraws; still 3 s | Claude (open to veto) |
| 2026-11-26 | After test14 (Joe, Undercity): the comet draws in any area that hides your line, old ones you've walked back into included, not only the one you're lingering in; where an area hides the line only partly, the comet makes up the rest | Claude (open to veto) |
| 2026-11-26 | With that: the map button, the minimap button and the chronicle work by hand inside too, settings included; the war table, banners, zone header and update window stay off there | Claude (open to veto) |
| 2026-11-26 | Reversed after test5: scores dodging pins jumped about as pins came and faded. Scores stay put and draw over pins (Joe) | Joe |
| 2026-11-26 | What's New back to the C mock Joe picked: one short line per note (the build had kept paragraphs, so two topics filled a page), version 18 pt, title small and faded, notes 13 pt, "1 of N" under the page. `test_notes_stay_short` caps a note at 70 characters | Joe |
| 2026-11-26 | The shortened 3.8.3 notes leave out the quiet-mode carry-over, sharing on for new players, the Campaigns/Grudges restyle, the quiet map button and "guildmates need 3.8.3 too"; the changelog carries them. 3.8.0–3.8.2 shortened the same way; 3.8.0 gets its title back | Claude (open to veto) |
| 2026-11-25 | 3.8.3: "close" = within one fight or a quarter of the fights; zone scores from the first fight; overlapping scores step down, most-fought keeps its centre; continent score at 62% down its box; combine at 3 within 1.4 pin widths, chained; big pin 1.5×+0.12×n up to 2.4×; overlapping big pins pushed apart; mixed groups take guildmates' blue when they're the majority; the zone-map corner shows your own crest (it showed the winner's) | Claude (open to veto) |
