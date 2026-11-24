# Warpath open items

Only open things live here. Close items when Joe confirms them; move shipped work to `how-it-works.md` and `CHANGELOG.txt`.

---

## Released, waiting on CurseForge moderation

**3.7.11** (released 2026-11-23/24): on CurseForge as "Warpath Forever" (project 1826632) and GitHub Releases, installed in Joe's game. The CurseForge file and project aren't visible to others until a moderator approves the project.

## Built and tagged, superseded by 3.7.11

**3.7.10 — receive diagnostics for guild sharing.** Receiver-only; guildmates don't need it. Patch notes **are** written and are in `CHANGELOG.txt` (the handoff said otherwise; the code and changelog disagreed with it). The TOC and the `Warpath.lua` header both read 3.7.10. It reaches the game only on a rev.

- `Share.lua`: `OnComm` is now a `pcall` wrapper around `Receive`, so one bad message can't stop the next; errors are counted (`diag.errors`, `lastError`). Per-session `diag` counts: every addon message (`all`, `allInside`), messages per channel while inside (all prefixes), secret prefixes, Warpath messages (`ours`, `oursInside`), unreadable text or sender, own echo, duplicates, malformed, sharing off, and arrivals during `InChatMessagingLockdown()`. `ns.DiagStatus()` prints three lines plus the last error.
- `Commands.lua`: `/warpath share status` calls `ns.DiagStatus()`.
- Changed from 3.7.9: `Share.lua`, `Commands.lua`, `Warpath.lua`, `Warpath.toc`, `CHANGELOG.txt`. Stub test: all counts correct.

## Roads rework (3.7.12): installed as 3.7.12-test2, watching in game

Branch `roads-snap` (commits `d923548` to `bbf735e`), not merged to `main`, nothing published. Installed 2026-11-24; Joe checked it in game: "a lot better initially", all silver so far. Design and thresholds are in `how-it-works.md` (Roads).

**Watch as play continues**
- Gilding and the faction tiers arriving on real roads (thread from day 6.5 of daily use, full gold 12.5, streak 17.5, emboss 31.5). Judge the pace and the look over the real map art.
- Lynchpin threads (0.5) against busy map art; fragments as roads fade.
- Small stair-steps at bends in the highlight and shade lines (visible zoomed in, worse at deep relief). Fix if they bother: offset the relief lines as one polyline per road instead of per piece.
- Orgrimmar's centre is still the busiest knot; Tirisfal's northern road stops short of the main road (no walked ground between).

**Before release**
- Version: 3.7.12 or 3.8.0 (Joe's call; it's a large rework of an existing feature).
- `CHANGELOG.txt` entry with the "Your saved data:" line (upgrade to `db.v` 10 merges lanes; old roads kept as `z.roadOld`). Guildmates are unaffected: nothing shared changed.
- Decide on `z.roadOld`: keep for one release, then drop (saves ~0.6 MB on Lethality).
- Remove the faction-mark treatments not chosen ("enamel", "banded", "embossed") and decide whether "plate" stays as an option.
- `/warpath roads` counts in `Zone.lua` still use the old thresholds (silver 1.5, gold 2.5); align them with the drawn bands, and reword what `/warpath roads <days>` means (it now scales every band).
- Glints and shimmer: check they still suit the gilt look and the new top of the scale.
- Prune of one-day stretches and the per-stretch "walked today" fields (`r`, `tr`): storage savings proposed on 2026-11-23, not built.
- Merge `roads-snap` into `main`, then the normal release checklist.

## Trail rework (3.8.0): installed as 3.8.0-test4, watching in game

Branched off `roads-snap`; committed on `trail-areas` (not merged). Design in `how-it-works.md` (Trail rework). 3.8.0 is "Roads, trails and flights": the roads rework (3.7.12 prototype) and the coming flight-path rework ship with it (Joe, 2026-11-24).

**Built and tested in the harness**
- `Linger.lua` (new file: **needs a full game restart**, not `/reload`), hooked from `Record.lua`'s `Sample()`; prune in `Warpath.lua`; drawing in `Map.lua`.
- `Lingering` tests (7): an area forms from questing and freezes on leaving; standing still isn't lingering; a short trip past the edge doesn't split it; a return visit adds to the same area; after leaving, no trail is drawn inside the outline; areas and links only fade over 1-30 min; areas are pruned after a day. Mutation-checked: disabling the merge splits the area; drifting the outline trips the fade test; without the cut, trail shows inside.
- The existing `Steadiness` test caught an arrow switching on as it aged (bend judged on the shrinking shaft); fixed.
- All 48 tests pass, real characters included.

**Next**
- Installed 2026-11-24 as 3.8.0-test1 (backup `tools/out/savedvars-backup-2026-11-24-test1/`). Joe to check in game after a full restart: areas forming while questing, outlines over real map art, time labels and hover, arrows zoomed in, colours by age, the 1 h and 24 h settings, small town areas.
- Tuning seen on renders: an arrowhead cut at an outline can leave a stray tick at the edge.
- Joe in game (test1): a gap opened behind his arrow while moving, made worse by the arrowhead at the trail's end. Fixed in 3.8.0-test2 (installed 2026-11-24, backup `tools/out/savedvars-backup-2026-11-24-test2/`): arrowhead dropped, a live line joins the trail to your arrow (`MapDrawing`-style test `test_the_trail_reaches_you_between_redraws`).
- Joe in game (test2): the line stayed solid too long (a lap of the Undercity, about 2.5 min, all solid). Now solid 2.5 min, then a small colour jump (in 3.8.0-test3).
- Found on renders while tuning that (fixed in 3.8.0-test3): coming back into an area hid all the trail since its first visit (hidden spans of earlier visits ran to now); a loop back into the area you're in was held at age 0, so it looked new forever. Both fixed, with a test for the first.
- Joe in game (test3): leaving an area filled it with trail for a minute (the hidden dashes came back, fading). Fixed in 3.8.0-test4; test `test_the_hidden_trail_stays_hidden_when_you_leave` (mutation-checked).
- Joe in game (test3): the area by the Undercity lift covers only part of the ground he lingered on. Causes: only time after forming counts; steps past a short margin end the visit and are dropped; distances are fractions of the map, so in cities (Undercity) they are several times shorter in yards. Built in 3.8.0-test4 (installed 2026-11-24, backup `tools/out/savedvars-backup-2026-11-24-test4/`), Joe's go-ahead: distances in yards, short trips past the edge join, recent trail joins on forming. Tests `test_areas_are_measured_in_yards`, `test_a_short_trip_past_the_edge_joins_the_area`, `test_trail_from_just_before_an_area_forms_joins_it`, each failing with its feature off. The harness stub now makes maps 4000 yd wide (was 1000), with `H.mapYards[id]` for a city. Unverified: the Undercity's real width in yards (the thresholds assume about 960).
- Joe in game (test4): re-entering an old area didn't refresh it; the hover list filled with "1 min" entries; the area by the lift spread up the hallway; lingering left the last 2.5 min of line scribbled inside the live area. All four fixed on branch `trail-fixes` (worktree `.claude/worktrees/trail-fixes`, made from `bef7a82` because a flight-path session was editing the main folder), not installed. Tests: `test_a_minute_inside_an_old_area_reopens_it`, `test_the_visit_list_reads_like_visits`, `test_a_corridor_walked_out_and_back_stays_a_line`, `test_inside_the_area_you_are_in_only_your_last_moments_show`, each mutation-checked. To install: merge `trail-fixes` and the flight work, then a test build.
- Joe (test3): dashes jaggy where the solid line turns to dashes; dashes between arrows unevenly spaced. Both fixed in 3.8.0-test4: medium smoothing (test `test_dashes_stay_put_when_you_walk_on_after_a_stop`) and even spacing (test `test_dashes_and_arrows_are_evenly_spaced`), both mutation-checked.
- Seen in test1: clearing the trail with `/run` without a `/reload` leaves the stroke being recorded out of the zone's list, so nothing draws. Offered: `/warpath clear trail` that resets the stroke in progress.

**Before release (with the roads items above)**
- `NEW_IN` entry for 3.8.0; `CHANGELOG.txt` with "Your saved data:" (adds `z.areas`; nothing deleted; trail only, nothing shared); a full restart is needed (new file).
- The flight-path rework: built on `trail-areas` (2026-11-24), not yet in the game; see below.

**Open questions**
- Hide small areas from standing in town (auction house, mail), or at least their labels, especially in neutral towns.
- A long slow drift (grinding along a road) caps an area at 0.30 and starts a new one: may look like a chain of blobs. Judge on real data.
- How far the Forever world map zooms (arrows are judged zoomed in).
- Real data: ask for the friend's Silithus `SavedVariables\Warpath.lua`; none of Joe's characters has a messy trail.

## Flight legs (3.8.0): built, not in the game yet

Design in `how-it-works.md` (Flight legs). New file `Flights.lua` (**needs a full game restart**).

- Joe in game: do the warm gold dashes read against real map art, and stay clear of gilded roads where the two cross?
- Joe: does a leg build up visibly over a week of normal flying? Real data so far has 3 days, so only the trunk shows.
- Saved data grows: Lethality's routes become 88 legs, 3,868 points (roughly 200 KB on a 1.8 MB file, estimated, not measured). Storing `t` and `d` once per run of points would halve it if it matters.
- Untested in game: a flight that crosses onto the continent map between zones (Kalimdor 1414) lays a few scrap legs there; they're flown once and stay hidden.

## Open investigation: guildmates' kills don't reach Joe inside battlegrounds

Opened 2026-11-22. This is the one piece of live work.

- **Facts.** In AV, Joe's `/warpath share status` showed 0 received. A guildmate in the open world sent `/warpath share test` (his status: 4 sent, 0 refused, 6 received); Joe in AV saw nothing. Outside, Joe received 1 non-sync message plus history, so outdoor delivery works.
- One open-world kill by the guildmate also showed nothing for Joe. Unresolved whether the guildmate's own Warpath counted it — ask whether his own kill line printed (`/warpath debug kills`).
- **Hypotheses.** (a) The client doesn't deliver GUILD addon messages into battlegrounds. (b) They arrive as secret values during `InChatMessagingLockdown` and `OnComm` dropped them before counting.
- **Fix options.** A whisper relay only helps for (a). **Catch-up on exit** — the receiver asks guildmates what it missed when leaving — works for both.
- **Next step:** install 3.7.10, have a guildmate send a test ping while Joe is inside, then read `/warpath share status`.

## Found by the test harness

- ~~Grudge line with no victim~~: fixed in 3.7.11, now a regular test.
- **Map drawing is switched off on Joe's account** (`cfg.shown = false` in `WarpathGlobal`, seen 2026-11-23). Probably deliberate via the map button, but worth a glance if the map ever "shows nothing".

## Waiting on in-game confirmation

Nothing in the old project tracked these to closure, so the state of most was simply unknown. An amnesty was applied on 2026-11-23: the 3.4-era block was dropped (the handoff itself marked it "probably moot — much of it was reworked since"), and what remains is only what has a concrete next action. From here, each check is tied to the release that introduced it, so it either closes or expires.

**3.7.9**
- Hovering a pin still shows its tooltip; left and right click over a pin zoom the map.

**3.7.6–3.7.7**
- Dashed fade over real map art; dashes steady while walking; the 1 h default not too busy.
- Own kill and death lines appear once, not twice in quiet mode; killer names in death lines.
- General tab: "Big text on screen" and "My kills and deaths in chat" side by side without overlap. Map tab: trail radios fit.

**3.7.x**
- Grey cross for mob deaths (texcoords on this client's raid-marker sheet); pin fading; show-all from the map button.
- Rebuilt haze on light and dark zones — retune `BATTLE_ALPHA`, `BATTLE_FULL` or patch size if too strong.
- `/warpath debug kills` after a night of play: any "+2 for one death", or "+0 repeat" lines? **If never, drop the kill-counting guard.**
- LibDBIcon on this client; MBB and Titan Panel pick up the minimap button.
- Pin size at default zoom, and for the guildmate running Leatrix Maps.
- Dangerous-ground wording and tones.

## Tuning knobs Joe may ask for

- Zone line under the zone name too central → move or shrink it.
- Rebuilt haze too strong → `BATTLE_ALPHA`, `BATTLE_FULL`, patch size.

## Offered, not asked for

- A Warpath warning when the old Wake addon is loaded, like the PvPKillShot one.
- `/warpath new`, or a "What's new" button, to reopen the "New in" box. Today: `/run WarpathGlobal.seenVersion = nil` then `/reload`.
- Long trails: hide old dashes on silver and gold roads, or cap dashes per map square (rank-based, never newest-wins).

## Declined and dropped

- Declined 2026-11-22: receiver-side multi-kill counting for guildmates still on 3.6.
- Dropped: map presets.
- Dropped 2026-11-21: the explainer one-pager.

---

## Deferred backlog

### Victory pose in kill screenshots
Most unknowns, least payoff. First step before any design: test in game whether an addon can fire an emote on this client without a keypress (fallback: keybind or macro).

- Approach: emote on the kill, delay the screenshot ~0.5–1 s to catch mid-pose (`cfg.shot.delay` already exists), then caption, banner and sound.
- Constraints: emotes don't animate while moving, mounted or casting, so skip the pose then; emotes are public, so nearby players see "Joe flexes" and it should be a setting; the default camera shows your back; a delayed shot can miss the corpse.
- Possible settings: off / on / notable only; which emote, or random; per race.

### Screenshot renamer
Addons can't rename files, so this is a small companion program outside WoW. The in-game data it needs shipped in 3.4.

- Reads SavedVariables (per character and `WarpathGlobal`): each kill's predicted file name, shot number, victim, class, zone, tag, streak, times killed.
- Output names like `2026-11-20 23.31 - Thrall (Shaman) - Arathi Highlands - Grudge.jpg`, optionally into `Screenshots\Warpath\2026-11\`, or by victim or zone. ISO date first; no Windows-forbidden characters; realm suffix optional.
- Runs after play, since SavedVariables are only written at logout or `/reload`: manual, scheduled, or a launcher shortcut.
- Match by time within ±2 s plus shot number (the predicted name can be off by a second).
- Prefer **copying** into a Warpath folder over renaming, since renaming breaks the hover file name on the map unless written back, which is only safe with WoW closed.
- Non-kill screenshots untouched. PowerShell (nothing to install) or Python (easier to maintain).

---

## Previously rejected ideas

Renamed from "Rejected designs — don't revisit" on 2026-11-23, at Joe's request: this is now a reference list, not a prohibition. Anything here can be reopened. The reasons are kept because they are findings worth not rediscovering — particularly the first group, which is the same lesson three times over.

**Road looks (2026-11-24).** Cartographer's ink (vanishes on dark maps like Felwood); trodden earth (blends into the map, tiers hard to tell apart); gold rims beyond gold (busy, like rail track); an engraved groove with deeper red-gold (reads as bronze, a lower metal); gems of any shape or arrangement (at normal map size a road is 4–6 px, so stones read as specks, and even spacing looked uncanny). Faction enamel with gold wires lost to a plain streak.

**Roads and shine.** Thicker solid black border; dark border with light rim; soft halo glow; white or cream sheen line with white star glints. All read as *silver* rather than bright gold. The underlying finding: on this map art, lightening toward white reads as a different metal, not a brighter one. Shine has to stay warm.

**Footsteps.** Soft glow or halo behind fresh dots; lifting colour toward a lighter tint — read as a white-ish haze. Footsteps were removed entirely in 3.7.6.

**Trail.** 3.7.5's footsteps with age-based spacing visibly jumped, because spacing was recomputed per redraw from "now". Trail "option 1" (dashes for the whole life, two tones) lost to option 2 in 3.7.6 on renders.

**Zone entry.** Green and red verdict colouring; live or dynamic zone messages (recent sightings, grudge sightings, guildmate deaths); enemy busy hours (judged worthless and removed, with `z.hours` no longer recorded).

**Map.** Hard-edged heat-map zone dots (unattractive in game); a trail heat map, which turned the map into scribbles while questing; 100% permanent map memory.
