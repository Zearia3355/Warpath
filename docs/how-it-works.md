# How Warpath works today (3.7.9 installed, 3.7.10 built)

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
- **Trail length** `cfg.trailMin`: default **60 min**, clamped 15–1440 (`ns.TrailSeconds`). Map tab radios 15m/30m/1h/4h/12h/24h (`TRAIL_MIN_CHOICES`); `/warpath trail <15m-24h>` (bare number = minutes). Old `cfg.trailHours` is kept but unused.
- Dashes are **anchored by distance along the stroke** (`s.d`, cumulative, map widths, aspect 668/1002, from `ns.StrokeArc`, computed in `Simplify` before reducing, kept in step like `s.ts`; extended at draw time for the open stroke). Tested 0 px movement over time and while walking.
- Per-point times `s.ts` (seconds since `s.t`), kept in step by `Simplify()`. Trail from before 3.4 has no per-point times (no backfill).
- Strokes kept 24 h (`KEEP_HOURS`). `DASH_BUDGET` 4000 pieces, newest first (faintest dropped first). Drawn over roads, no per-square cap.
- **Footsteps were removed in 3.7.6** (`StepLook`, `STEP_*` gone). Road "walked today" is still recorded (`/warpath zone`).
- History of this one feature, for context (it changed six times in two days): 3.4 5-min line fading into footsteps → 3.5 trail-length setting (2–24 h) → 3.6.3 footsteps fade over trail length → 3.7.5 15-min line + two-tone footsteps (jumped; rejected) → 3.7.6 dashes 5–15 min, no footsteps, length setting removed (Joe picked "option 2" from renders) → 3.7.7 length setting back, 15 min–24 h, default 1 h.

### Roads (long memory)
- Built from where you choose to travel. One mark per day of use. Flights and corpse runs never count (`Visit()` skips them).
- **Silver** from `roadMin × SILVER_SHARE` (= 1.5 days of use, i.e. two separate days). **Gold** threshold `db.roadMin` default 2.5 (`/warpath roads <days>`).
- Gradual gilding: silver → warm silver → pale gold → light gold → gold, smoothstep between stops, over roughly 1.8–5 days of use. Width grows smoothly to `ROAD_FULL` 12.
- Worn gold: three stacked lines (outline, gold body, warm-yellow centre stripe that brightens with wear, never white); outline warms near-black → dark bronze.
- **Shimmer** (`cfg.shimmer`, can be turned off): warm band travelling diagonally across each zone every 7 s; centre-stripe colour capped at (1.00, 0.90, 0.50). Runs only while the map is open.
- **Glints**: amber four-point stars (`Interface\Cooldown\star4`, additive), ≤6 per zone, most-worn roads only.
- Joe's road style: "C" — gold roads with dark casing.
- `/warpath roads` counts ("N stretches of gold, M of silver") still use the thresholds, not the blend.
- Budget: roads stop 800 lines short of `LINE_BUDGET` (5000).

### Long memory and the play clock (3.5.0)
- Roads, battle haze and flight routes fade on **days played**, not calendar days ("a weekend away costs nothing"). Joe's decision.
- Play clock = (days played before today) × 24 h + time of day. Only long memory uses it. (Claude's call on the formula.)
- Halving every 14 play-days (`db.longDays`). `/warpath memory <days>` (old two-number form accepted; hours ignored). `Prune()` drops entries faded below 0.05.

### Runs layer (`runs`): corpse runs and flights
- Own store `z.runs` (kind `g` ghost / `f` flight), own lifetime, not the trail history. Along-the-line fade by each segment's own age.
- Corpse runs: dashed **ice blue with a soft glow**, no outline. Flights: thin soft **gold dashes**, ≤45% opacity. (Designed so neither reads as a road: roads are the only solid-with-outline lines.)
- Lifetimes `cfg.runHours` / `cfg.flightHours`: default 24 h; options 1, 6, 24, 48.
- `RUN_BUDGET` 2500. Flights/corpse runs split at 1,200 points (walking strokes at 300).
- **Flight routes** (`z.routes`): each zone's stretch of a flight is matched to earlier ones by its endpoints (tolerance 0.03 map units). Same long memory as roads. Shown after about **five days of flying within a couple of weeks** (3.4.1; was two). Fade-out on at strength ≥ 4, off below 2.5 (Claude's call). Faint, sparse, muted dashes. Never part of roads. Corpse runs get no long memory.

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
- Opens itself once after a **feature** release (new minor), with a "New in" box (`NEW_IN`, wrapped bullet entries). Reopen the box today: `/run WarpathGlobal.seenVersion = nil` then `/reload`.

## Commands (summary)
Everyday (`/warpath help`): `/warpath` (totals + "Type /warpath help"), `zone`, `chronicle`, `map`, `grudge`, `options`, `help all`.
Full list (`/warpath help all`): built from one table of `{command, description, group, everyday}` so both lists can't drift. Includes everything above plus `layer <name> [on|off]`, `replay [hours]` (up to 24), `waypoint death|kill`, `memory <days>`, `roads <days>`, `clear zone`, `clear all` (asks to confirm within 10 s; grudges kept), `debug`, `debug kills`, `debug haze`.
Principles: noun-first names; every toggle takes `on|off` or toggles bare and replies with the new state; unknown command → one line + "Did you mean…"; old names stay as hidden aliases (`toggle`→`map`, `hud`→`table`, `revenge`/`lastkill`→`waypoint death|kill`, `heat`→`battle`, `recent`→`trail`, `shared`→`guild`).

## Saved data
- `db.v` history: 4 (3.3.x) → 5 (3.4) → 6 → 7 (3.6.0) → 8 (3.7.0) → 9 (3.7.1). One `MigrateToV<n>` function each, in `Warpath.lua`; version 6 was missing from this list before 2026-11-23.
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
