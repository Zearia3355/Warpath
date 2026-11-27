# Warpath open items

Only open things live here: work in progress and checks waiting on Joe. Close items when Joe confirms them; move shipped work to `how-it-works.md` and `CHANGELOG.txt`. Ideas and bugs nobody is working on yet go in `backlog.md`.

---

## 3.8.3: released 2026-11-26 (tag on `8d4b3d9`; CI run 45938193545 uploaded to CurseForge, "Success!", and GitHub Releases; listed on the files page)

The checks below that Joe hadn't confirmed shipped unconfirmed; check them in game on the release.

Built from the backlog on 2026-11-25, alongside 3.8.3-test1's area changes. test2 installed 2026-11-25 (commit `8977243`; backup `-3.8.3-test2/`) with the first three items. **test3** installed 2026-11-25 by script (commit `3a9957d`; full restart; backup `tools/out/savedvars-backup-2026-11-25-3.8.3-test3/`), with everything below. `NEW_IN`, changelog and release version are written.

- Ground warnings ("DANGEROUS GROUND" etc.) stay up 4–6.5 s by line length instead of under 2 s (`Overlay.Show` takes `hold`; `Overlay.ReadHold`). Kill text unchanged. Tests in `Overlay` (mutation-checked: without the hold, the reading test fails).
- The map button's left-click shows/hides Warpath without a chat line; `/warpath map` still replies. Tests in `MapButton` (mutation-checked).
- Several guildmates killing one enemy: one line, one pin (`Share.lua` `NoteKill`; `Record.lua` skips your own line when a guildmate said it first). Found in Lethality's data: 5 of Joe's kills on 2026-11-24 in Eastern Plaguelands had Plains Stomper's pin 0–1 s later, 0.1–0.8% of the map away. No near-identical pins from two different guildmates were in the data. Tests in `Share` (8; mutation-checked: no folding, no own-line skip, no same-reporter rule, no pin removal each fail). Receiver-side, so only players on 3.8.3 stop seeing the duplicates; patch notes say so.

- Wake and PvPKillShot mentioned nowhere in the addon (Joe, 2026-11-25): the PvPKillShot login warning, its field in `/warpath debug`, the `/killshot` and `/pks` aliases and the public `Warpath` global (kill callbacks; Claude's call) are gone. In test3. Changelog: say `/killshot` and `/pks` no longer work, use `/warpath shot`.

- Area time labels: WoW yellow on a soft dark patch, staying full strength until the trail's last quarter (Joe's pick, style D with yellow text, from renders over his Undercity screenshot). Tests in `Lingering` (3; mutation-checked: the old colour and fade fail two). In test3.

- Zone standing on the zone's own map: crest and "kills : deaths" in the map's top-left corner (Joe's pick, B of four placements rendered over his Eastern Plaguelands screenshot). From the first kill or death; continent views unchanged. Tests in `MapDrawing` (3; mutation-checked: always hidden fails two, shown on continents fails one). In test3.

- Continent and world maps (Joe's picks from renders over his clean screenshots): scores in blue/yellow/red (ahead, close, behind), the zone-map corner too; the world view shows one score per continent; continents a small score per zone on a dark patch; every pin drawn, and 3+ kills or deaths close together become one bigger sword or skull, pushed apart where they'd overlap. Tests in `MapDrawing` (8 new; mutation-checked: no combining, no push, no step-down, one colour, zone scores on the world each fail). `render.py` now draws text, and frames by level. In test3. After test3, smaller (at most 1.5× a pin) and no count text, (Joe, 2026-11-26). In test5 (installed 2026-11-26 by script; `/reload` is enough; backup `-3.8.3-test5/`), scores also stepped around pins; in play they jumped about, so after test5 they stay put and draw over pins: test `test_a_score_stays_put_over_pins_and_draws_above_them` (mutation-checked: dodging pins fails it). In test6 (installed 2026-11-26 by script; `/reload` is enough; backup `-3.8.3-test6/`).

- Trail gives way to roads (Joe's pick, B of four renders over his Eastern Plaguelands screenshot): trail along a road you can see is kept 10 minutes, then fades out over 5. Tests in `TrailOnRoads` (3; mutation-checked: never giving way, no keep, giving way everywhere each fail; a steadiness test runs through the fade). In test3.

- Old trail readable on busy map art (Joe, 2026-11-26, from his Dustwallow screenshot: "impossible to decipher"; picks from renders of Lethality's 9-hour-old Dustwallow trail over that screenshot). Old trail used to sink to an earthy red-brown and shrink to dots, the same ink as the marsh outlines. Now: it stays the faction's deep colour (crimson for the Horde) and fades less (alpha 0.95 → 0.80 before the last quarter); dashes shorten only to 65% of a slot, no dots; every dash sits on a dark casing 1.7 × its width; and an older pass gives way where a newer one, at least 2 min newer, runs alongside it within 2 dash slots and about the same direction (pick D of four: as is, dim, hide, hide wider). Crossings stay. Area outlines take the new colour; their dash length (pick H) is unchanged. The solid last-2.5-min line has no casing. Tests in `OldTrail` (6; mutation-checked: old look, no casing, never giving way, any direction, no time gap, and counting only visible newer marks each fail). In test7 (installed 2026-11-26 by script; `/reload` is enough; backup `-3.8.3-test7/`).
- Area outlines and sharp turns (Joe, 2026-11-26, after test7 in game: "trail looks much better"; picks from renders of his Searing Gorge area and Undercity hairpin): past area outlines use the trail's own dash on the dark casing (pick C), replacing pick H; at a sharp turn (over about 80°) the trail stays a solid line from a slot before the turn to a slot after (Joe's spec). Tests: `OldTrail` hairpin, gentle bend, turn only fades; `Lingering` outline casing, outline dash (updated). Mutation-checked: no solid turns, a short solid stretch, every bend solid, a turn growing with age, no outline casing, pick H's dash each fail. In test8 (installed 2026-11-26 by script, `/reload` is enough; backup `-3.8.3-test8/`).
- Other maps draw inside battlegrounds (Joe, 2026-11-26: "resting" meant no pins, kill reporting or spam from the match, not hiding the overlays of other zones). Only the map you're standing in stays clean. The map button works inside (no longer greyed), and so do the chronicle and the minimap button by hand (Claude's call). Tests: `test_the_battleground_map_stays_clean`, `test_other_maps_still_draw_inside_a_battleground`, `test_an_unreadable_position_inside_draws_nothing`, `test_the_button_and_the_book_work_inside_a_battleground` (mutation-checked: the old blanket rule and the old click guard each fail). In test8 (installed 2026-11-26 by script, `/reload` is enough; backup `-3.8.3-test8/`).
- Continent flight legs (Joe, 2026-11-26: thinner, rails, "artistic liberty" with accurate start, path and end, no janky dashes): 75% width; legs simplified and rounded, each dash a straight stroke; the continent's own legs (recorded while the game placed you on the continent map) drawn the same way instead of zone-style; hooked ends dropped; a weaker leg alongside a stronger one, or touching its dash at a junction, gives way. Zone maps unchanged. Tests in `FlightsOnContinents` (8 new; mutation-checked: continent's own legs zone-style, no simplify or rounding, old width, no rails, no hook trimming, no junction give-way, rails ignoring direction, shape following the fade each fail). Then (Joe, after renders: Vs at junctions, then "large gaps"): dashes fitted per piece between sharp bends (whole dashes, even gaps, half a gap at each end), tiny legs (landing circles) hidden, every shown leg drawn whole, junction touch on a leg's end dashes only. The trail's solid-turn rule was rendered for flights and rejected (squiggles). Tests: even spacing end to end, a U-turn's bend is a gap, tiny legs, one look, a T junction (each mutation-checked; the L test is now also covered by the half-gap ends). Remaining sparseness in south-west Kalimdor is the recorded data: backlog "Record flight legs as whole routes". In test8 (installed 2026-11-26 by script, `/reload` is enough; backup `-3.8.3-test8/`).
- Map button toggle left the last drawing up (Joe, 2026-11-26; found in the "Map toggle warpath layers bug" session): since test3 the score step asked `C_Map.GetMapInfo` for the hidden scene's missing map ID, which raises in the client, so the clearing redraw stopped. Battlegrounds use the same empty redraw. Fix: no scores without a viewed map (`DrawMarks`). The stub's `GetMapInfo` now raises on a non-number like the client, which made three existing tests (hidden map, instances, zone-score hiding) fail before the fix. In test7.
- Chronicle's X did nothing in combat (Joe, 2026-11-26; Escape worked): the `UIPanelCloseButton` template's click goes through `HideUIPanel`, which the secure panel manager ignores in combat. The X now hides the book directly. The stub's close button now goes through a `HideUIPanel` that does nothing in combat, like the client; `test_the_books_x_closes_it_in_combat` fails on test12's code. In test13 (installed 2026-11-26 by script; `/reload`; backup `-3.8.3-test13/`). Joe confirmed it works in game (2026-11-26).
- Comet tail in the live area (Joe, 2026-11-26: "a more comet-like fade from the end to bright just behind me"; after renders of 10/20/30 s comets, "keep it short, aim for 3 seconds"): inside the area you're in, the 3 s of line fades and thins with age instead of ending sharply (`CURVE`, `TAPER` in Linger.lua). Test `test_inside_the_area_you_are_in_the_line_fades_like_a_comet` (mutation-checked: the old cut-off fails it). In test9 (installed 2026-11-26 by script; full restart; backup `-3.8.3-test9/`). In test10 it skipped (Joe: froze, then jumped every couple of seconds while walking): it was worked out only at redraws. Now it fades every frame, the tail to your arrow included (`test_the_comet_fades_between_redraws`, fails on test10's code). In test12 and test13 it still failed (Joe, test13: "a full strength line forms behind me for 3 seconds and then the whole thing disappears and a new line begins"): built from recorded steps (12 yards apart) at redraws, it was one straight line to your arrow that reset at each redraw. Now drawn from your position every 0.1 s while the map is open (`test_the_comet_never_vanishes_and_only_fades`, fails on test13's code, as does the reworked fade test). In test14 (installed 2026-11-26 by script; `/reload`; backup `-3.8.3-test14/`) Joe confirmed it in the area he was lingering in, but back in an old area (before it reopens) the line still grew and vanished: the comet drew only in the live area. Now it draws in any area that hides your line (`test_the_comet_shows_in_an_old_area_too`, fails on test14's code). Also after test14 (Joe, Undercity): leaving an area brought your solid line back inside it for a minute. An area you've left now keeps it hidden (`test_the_hidden_trail_stays_hidden_when_you_leave` now runs at the real 2.5 min solid line and fails on test14's code). In test15 (installed 2026-11-26 by script; `/reload`; backup `-3.8.3-test15/`): check both in game.
- Past area outlines dashed closer together (Joe's pick H, from renders of test areas aged 10 min to 10 h on a parchment stand-in): a fixed period of 0.75 trail slots, dash 80% -> 55%, so old areas stay joined up. D, his first pick, made dashes slide as they aged (only-fade test). Test `test_an_old_area_outline_stays_joined_up` (mutation-checked: the old spacing fails it). In test4 (installed 2026-11-25 by script, commit `f88ef16`; `/reload` is enough; backup `-3.8.3-test4/`).

- Welcome and What's New in the chronicle (Joe, 2026-11-25): a permanent **Warpath** tab, right of the title plate; the book opens there after each update instead of the options window, and closing it marks the release seen. 3.8.3's `NEW_IN` entry is written (10 lines). Tests in `NewIn` (4 new; mutation-checked: never opening, not marking seen, everything marked new, no paging each fail). The harness's `Hide` now runs `OnHide`, and buttons keep `Enable`/`Disable`.

- Settings in the chronicle, layout C, settings review (Joe, 2026-11-26; decisions in `docs/settings-review.md`): a **Settings** tab beside Warpath with six sections, every change at once, Restore defaults per section; the options window is gone. Quiet mode and big text became "Announce on screen" (accounts with quiet on keep announcing, sounds and the zone line off); a switch for guildmates' kill lines in chat; recent flights get their own length; sharing on for new installs and a switch on the welcome page. What's New grouped by topic with a NEW mark; campaign deeds under zone headings and only highlights with something to say; grudges with "no blood yet" and encounters by day. 3.8.3's `NEW_IN` rewritten under topics. Tests: `AlertSettings` (6), `SettingsTab` (7), `Share` (2 new), `NewIn` (updated, 1 new); `upgrade_matrix.py` follows quiet mode into its new form. Mutation-checked: guild lines always printed, a section 100 px taller, and quiet mode not keeping sounds off each fail. In test9 (installed 2026-11-26 by script; **full restart**, the `.toc` changed; backup `-3.8.3-test9/`). The book's look has only been mocked, not rendered from code (the harness has no book renderer).

- After test10, in test11 (installed 2026-11-26 by script; `/reload` is enough; backup `-3.8.3-test11/`): What's New as the C mock Joe picked: one short line per note for every release, the version larger, the title small and faded, notes at 13 pt, "1 of N" at the page's foot. Tests: `test_notes_stay_short`, and the page count in `test_older_releases_are_a_page_turn_away` (both mutation-checked: a 92-character note, and a fixed or off-by-one count, each fail).
- After test9, in test10 (installed 2026-11-26 by script; `/reload` is enough; backup `-3.8.3-test10/`): ground warnings fire on any fighting of yours (the haze), so hunting and contested ground speak too; settings say "Ground you've fought on", after 1/2/3 fights. Tests `GroundWarnings` (4; mutation-checked: the old death-only trigger fails the hunting test). Also: no Settings button on the welcome page, new test builds open the book, "with guildmates' fighting" under Battle haze, room above headings.

**Joe to check in game**
- Walk into a zone where you've killed but never died: "Your hunting ground" once, gold, no sound.
- Settings tab (after installing): each section fits its page, labels readable on the parchment, checkboxes and radio buttons line up, greyed rows look greyed; Restore defaults asks first; the minimap right-click and `/warpath setup` open it.
- What's New (test11): all of 3.8.3 on one page, most notes on one line, the version larger than its faded title, "1 of 2" at the foot, text readable at 13 pt. Earlier shows 3.8.0 to 3.8.2. The Guild sharing box on the welcome page matches your setting.
- Campaigns: deeds under zone headings, tags on the right not clipping long names; Highlights only shows lines with something in them. Grudges: "no blood yet", encounters under day headings.
- In a battleground: open the map, switch to a zone or continent outside it, and your war is drawn there; the battleground's own map stays clean. The map button toggles it; the minimap button opens the chronicle.
- Old lingering areas (a few hours old) are easy to see with the closer dashes, and the outline of the area you're in still stands out as the solid one.
- After a full restart: the book opens on the Warpath tab, 3.8.3 marked NEW; the welcome and the notes read well; Settings turns to the Settings tab; Earlier reaches 3.8.0; closing it and logging in again doesn't reopen it.
- Walk onto dangerous or contested ground: the warning can be read before it fades.
- Map button left-click: no chat line; the tooltip still says "Hidden (still recording)".
- Killing with a guildmate who also gets credit (party, Plains Stomper): one chat line and one pin per kill.
- Map button: clicking Warpath off clears the map on every map, and on again draws it back; entering a battleground leaves nothing drawn.
- Kalimdor and Eastern Kingdoms: flight legs thinner, clean straight dashes along smooth routes, starts and ends where you flew, no side-by-side rails or L-shaped junctions; zone maps' flights as before.
- A hairpin or sharp corner: one solid hook through the turn, dashes either side; gentle bends stay dashed. Old area outlines look like the trail lines around them.
- Old trail in a busy zone (Dustwallow): crimson long dashes with a dark edge you can follow hours later; walking back the way you came leaves one line, not two; crossings still show both.
- Walking along your roads: after 10–15 minutes the trail on them fades away and the roads read clean; trail across open ground stays.
- World and continent maps: scores readable and coloured right; combined swords and skulls only a little bigger than a pin, no numbers, none overlapping; scores stay put, readable over pins; hovering a big pin says how many.
- Milling about inside a lingering area: the short line behind you fades out like a comet, brightest at your arrow.
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
