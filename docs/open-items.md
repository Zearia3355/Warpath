# Warpath open items

Only open things live here: work in progress and checks waiting on Joe. Close items when Joe confirms them; move shipped work to `how-it-works.md` and `CHANGELOG.txt`. Ideas and bugs nobody is working on yet go in `backlog.md`.

---

## 3.8.3 batch: installed as 3.8.3-test2 (branch `areas-merge`)

Built from the backlog on 2026-11-25, alongside 3.8.3-test1's area changes. Installed 2026-11-25 by script (commit `8977243`; `/reload` is enough; backup `tools/out/savedvars-backup-2026-11-25-3.8.3-test2/`). Not yet: `NEW_IN`, changelog, release version.

- Ground warnings ("DANGEROUS GROUND" etc.) stay up 4–6.5 s by line length instead of under 2 s (`Overlay.Show` takes `hold`; `Overlay.ReadHold`). Kill text unchanged. Tests in `Overlay` (mutation-checked: without the hold, the reading test fails).
- The map button's left-click shows/hides Warpath without a chat line; `/warpath map` still replies. Tests in `MapButton` (mutation-checked).
- Several guildmates killing one enemy: one line, one pin (`Share.lua` `NoteKill`; `Record.lua` skips your own line when a guildmate said it first). Found in Lethality's data: 5 of Joe's kills on 2026-11-24 in Eastern Plaguelands had Plains Stomper's pin 0–1 s later, 0.1–0.8% of the map away. No near-identical pins from two different guildmates were in the data. Tests in `Share` (8; mutation-checked: no folding, no own-line skip, no same-reporter rule, no pin removal each fail). Receiver-side, so only players on 3.8.3 stop seeing the duplicates; patch notes say so.

- Wake and PvPKillShot mentioned nowhere in the addon (Joe, 2026-11-25): the PvPKillShot login warning, its field in `/warpath debug`, the `/killshot` and `/pks` aliases and the public `Warpath` global (kill callbacks; Claude's call) are gone. Not in test2. Changelog: say `/killshot` and `/pks` no longer work, use `/warpath shot`.

- Area time labels: WoW yellow on a soft dark patch, staying full strength until the trail's last quarter (Joe's pick, style D with yellow text, from renders over his Undercity screenshot). Tests in `Lingering` (3; mutation-checked: the old colour and fade fail two). Not in test2.

- Zone standing on the zone's own map: crest and "kills : deaths" in the map's top-left corner (Joe's pick, B of four placements rendered over his Eastern Plaguelands screenshot). From the first kill or death; continent views unchanged. Tests in `MapDrawing` (3; mutation-checked: always hidden fails two, shown on continents fails one). Not in test2.

**Joe to check in game**
- Walk onto dangerous or contested ground: the warning can be read before it fades.
- Map button left-click: no chat line; the tooltip still says "Hidden (still recording)".
- Killing with a guildmate who also gets credit (party, Plains Stomper): one chat line and one pin per kill.
- Zone map with kills or deaths: the standing sits in the top-left corner next to the round button, clear of it, readable, and stays put while zooming.

## 3.8.2: live-area trail cut to 3 s

Joe in game (3.8.1, Undercity): inside the area he was in, his last 45 s of line scribbled over it; "that was never the intent", stopping the scribble is the point of the areas. Now only the last 3 s show there (`SHOW` in `Linger.lua`; `LAG` 45 s still decides when steps join). Old areas keep hiding your line until a minute inside reopens them (Joe: live only). Test `test_inside_the_area_you_are_in_only_your_last_moments_show` now checks 5 s; it fails with 45 s put back.

**Joe to check in game**
- Lingering in an area: only a short tail behind the arrow, no loops.

## 3.8.1: released 2026-11-24 (tag on `ad8ef02`; CI run 45521771033 uploaded to CurseForge, "Success", and GitHub Releases)

- Guild version check: the sync hello carries the version; one chat line per session when a guildmate runs a newer release (sharing on, both on 3.8.1+). Tests in `Share` (mutation-checked: without the once-guard, and without the check, they fail).
- Update window after every release, `NEW_IN` keyed by version (`NewIn` tests). Joe's account last saw `3.8.0-test4`, so he gets the 3.8.0 and 3.8.1 entries together.
- `/warpath trail clear`, listed under Map; help said "(default 1h)", now 12h.

Listed on CurseForge after review (about 15–20 min after upload); Joe updated through the CurseForge app on 2026-11-24 and it worked.

**Joe to check in game**
- The update window opens after installing 3.8.1, headed "NEW IN 3.8.0 TO 3.8.1".
- The version notice can only be seen once a release after 3.8.1 exists and a guildmate runs it.

## 3.8.0 "Roads, trails and flights": released 2026-11-24, Joe installing from CurseForge

Tagged on `main` (`5425eb5`); CI run 45519414319 uploaded to CurseForge ("Success") and GitHub Releases. The CI zip matches a local `git archive` build file for file. Release work: `NEW_IN` for 3.8; one-time map reset (layers + guild haze on, trail 12 h); trail default 12 h; faction-mark trials removed; `/warpath roads` and `/warpath zone` on the drawn bands; `/warpath clear trail`; `Settings` tests (6, two mutation-checked). Backup: `tools/out/savedvars-backup-2026-11-24-3.8.0/`.

**Joe to check**
- Installing through the CurseForge app (the project may still be awaiting moderation, so the app may not find it yet). The hand-copied `Interface\AddOns\Warpath` folder shows as an unknown local addon until replaced; removing it first is safe (saved data is in `WTF`).
- After a full restart: the "New in 3.8" box, the window opening on the Map tab, the reset (his trail goes from 24 h to 12 h; set it back on the Map tab).

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

**Done for 3.8.0:** version, changelog, faction-mark trials removed ("plate" stays as a constant), `/warpath roads` and zone counts on the drawn bands, merged to `main`.

**After 3.8.0**
- Drop `z.roadOld` in the release after 3.8.0 (Joe, 2026-11-24; saves ~0.6 MB on Lethality). It deletes data, so say so in that release's notes.
- Glints and shimmer: check they still suit the gilt look and the new top of the scale.
- Prune of one-day stretches and the per-stretch "walked today" fields (`r`, `tr`): storage savings proposed on 2026-11-23, not built.

## Trail rework (3.8.0): installed as 3.8.0-test7, watching in game

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
- Joe in game (test4): re-entering an old area didn't refresh it; the hover list filled with "1 min" entries; the area by the lift spread up the hallway; lingering left the last 2.5 min of line scribbled inside the live area. All four fixed on branch `trail-fixes` (worktree `.claude/worktrees/trail-fixes`, made from `bef7a82` because a flight-path session was editing the main folder), merged with the flight legs into `trail-areas` (`a4fe53d`) and installed as 3.8.0-test5 (backup `tools/out/savedvars-backup-2026-11-24-test5/`). Tests: `test_a_minute_inside_an_old_area_reopens_it`, `test_the_visit_list_reads_like_visits`, `test_a_corridor_walked_out_and_back_stays_a_line`, `test_inside_the_area_you_are_in_only_your_last_moments_show`, each mutation-checked.
- Joe (test3): dashes jaggy where the solid line turns to dashes; dashes between arrows unevenly spaced. Both fixed in 3.8.0-test4: medium smoothing (test `test_dashes_stay_put_when_you_walk_on_after_a_stop`) and even spacing (test `test_dashes_and_arrows_are_evenly_spaced`), both mutation-checked.
- Seen in test1: clearing the trail with `/run` without a `/reload` leaves the stroke being recorded out of the zone's list, so nothing draws. `/warpath clear trail` built for 3.8.0 (test `test_clear_trail_clears_the_trail_and_keeps_the_rest`, mutation-checked).

**Done for 3.8.0:** `NEW_IN`, changelog, flight legs included.

- Joe (Plaguelands data, after 3.8.2): the trail was still a mess, with no big central area. Built 3.8.3-test1 on branch `areas-merge` (installed 2026-11-24, backup `tools/out/savedvars-backup-2026-11-24-3.8.3-test1/`): forming radius 225 yd on zone maps, 150 yd and a 400 yd cap in cities, touching areas merge. Replayed on his data: Eastern Plaguelands 6 areas instead of 4, the middle questing one area; the Undercity unchanged (one area on the ring). Tests `test_side_by_side_areas_become_one`, `test_far_apart_areas_stay_apart`, `test_a_city_keeps_the_tighter_radius`, each mutation-checked. Joe to judge in game: questing hubs, towns (do small town stops now form areas more readily?), cities. Not yet: `NEW_IN` and changelog for 3.8.3.

**Open questions**
- Hide small areas from standing in town (auction house, mail), or at least their labels, especially in neutral towns.
- A long slow drift (grinding along a road) caps an area at 0.30 and starts a new one: may look like a chain of blobs. Judge on real data.
- How far the Forever world map zooms (arrows are judged zoomed in).
- Real data: ask for the friend's Silithus `SavedVariables\Warpath.lua`; none of Joe's characters has a messy trail.
- Real data kept (2026-11-24): Lethality's Plaguelands trail, in `tools/out/trail-data-2026-11-24-plaguelands/` (untracked; character save plus `WarpathGlobal`, as written at 19:03 and, after Joe's `/reload`, at 20:29). The 20:29 copy: Eastern Plaguelands (1423) 14 strokes, 863 points, 4 areas; Western Plaguelands (1422) 28 points; Undercity (1458) 480 points, 1 area; map 1454 136 points. The game prunes the trail after 12 h and areas after 24 h; these files keep it. To use it in the harness, point `WARPATH_WTF`/`render.py --wtf` at a copy laid out like the WTF folder.

## Flight legs (3.8.0): installed as 3.8.0-test7, watching in game

Design in `how-it-works.md` (Flight legs). New file `Flights.lua` (**needs a full game restart**).

- Joe in game (test5): warm gold dashes were nearly invisible on the parchment. Now royal blue with a dark casing, picked from renders over his Kalimdor and Barrens screenshots; zone maps at 65% width. Installed as 3.8.0-test6 (backup `tools/out/savedvars-backup-2026-11-24-test6/`); Joe: the blue shows up. test7 (backup `-test7/`) makes continent legs 65% as wide too, his call; not rendered first, at his request. **Joe confirmed test7 in game (2026-11-24): the dashes look good.** Still to watch: dark zones (Felwood, Ashenvale), where legs cross water, and next to blue (Alliance) kill marks.
- Joe: does a leg build up visibly over a week of normal flying? Real data so far has 3 days, so only the trunk shows.
- Saved data grows: Lethality's routes become 88 legs, 3,868 points (roughly 200 KB on a 1.8 MB file, estimated, not measured). Storing `t` and `d` once per run of points would halve it if it matters.
- Untested in game: a flight that crosses onto the continent map between zones (Kalimdor 1414) lays a few scrap legs there; they're flown once and stay hidden.

## Open investigation: guildmates' kills don't reach Joe inside battlegrounds

Opened 2026-11-22. This is the one piece of live work.

- **Facts.** In AV, Joe's `/warpath share status` showed 0 received. A guildmate in the open world sent `/warpath share test` (his status: 4 sent, 0 refused, 6 received); Joe in AV saw nothing. Outside, Joe received 1 non-sync message plus history, so outdoor delivery works.
- One open-world kill by the guildmate also showed nothing for Joe. Unresolved whether the guildmate's own Warpath counted it — ask whether his own kill line printed (`/warpath debug kills`).
- **Hypotheses.** (a) The client doesn't deliver GUILD addon messages into battlegrounds. (b) They arrive as secret values during `InChatMessagingLockdown` and `OnComm` dropped them before counting.
- **Fix options.** A whisper relay only helps for (a). **Catch-up on exit** — the receiver asks guildmates what it missed when leaving — works for both.
- **Next step:** the diagnostics (3.7.10) are in every release since 3.7.11, so they're in Joe's game. Have a guildmate send `/warpath share test` while Joe is inside a battleground, then read `/warpath share status`.
- Joe, 2026-11-24: **debug this first**, before any catch-up design: it's still unexplained behaviour. Find which hypothesis holds before choosing a fix. Catch-up on exit shares its design with the backlog's "Catch up on guildmates' kills and deaths missed while offline", so that waits on this.

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

---

Not started yet? Bugs, enhancements, feature ideas and declined or rejected ideas live in `backlog.md`.
