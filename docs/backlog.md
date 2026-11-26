# Warpath backlog

Future work that nobody is building yet: reported bugs, enhancements to existing features, and new feature ideas. Work in progress and release checks live in `open-items.md`; shipped behaviour lives in `how-it-works.md`.

## How to use this file

- **Add** an entry under the right heading, newest at the top of its section. Use the template below; one entry per idea or bug.
- **Bugs** are things that behave wrongly today. **Enhancements** change or tune an existing feature. **Feature requests** are new things.
- **When work starts**, move the entry to `open-items.md` (under its release or rework) and delete it here. Don't keep two copies.
- **When an idea is declined or dropped**, move it to "Declined and dropped" with the date and the reason, so it isn't rediscovered.
- `From` says who raised it: Joe, a guildmate (by character name), the test harness, or Claude ("offered, not asked for").

Template:

```
### Short title
- From: Joe, 2026-11-24
- Status: new | wanted | needs a test in game | needs a design
- What: one or two plain sentences: what happens (bugs: what you expected instead, and where).
- Notes: anything known so far (cause, constraints, first step). Optional.
```

---

## Bugs

_The guild-sharing-in-battlegrounds problem is an open investigation in `open-items.md`._

---

## Enhancements

### Record flight legs as whole routes (3.9)
- From: Joe, 2026-11-26 (Kalimdor's continent flights around Thunder Bluff and the Crossroads: "I just don't get what the heck is happening in this region visually")
- Status: wanted, needs a design; changes saved data, so Joe agrees the upgrade before it's built
- What: one route should be one leg. Today a flight that strays more than 100 yards (`AIR_SNAP`) from a leg starts a new one, so a few real routes are stored as many fragments (Lethality's Thunder Bluff approach is 9 legs, 1412#1 to #9), each with its own days flown, and the landing circles at a flight master are recorded as tiny legs of their own (1413#3, #27, #28, #30). On a continent that draws as broken pieces starting and stopping, which drawing can tidy (3.8.3) but not join.
- Notes: candidates: legs between flight masters (a flight's start and end are taxi nodes); a wider snap scaled to the map (yards are tiny on a continent); merging existing legs once on upgrade (like the 3.7.12 lane merge, hiding over deleting). The 3.8.3 continent drawing (fitted dashes, tiny legs hidden, one look) stays useful on top. The per-leg diagnostic render that found this is in the 2026-11-26 trail session (each leg its own colour, labelled zone#leg and days flown); worth adding to `render.py` as a layer.

### Flesh out replay, and advertise it on the map
- From: Joe, 2026-11-26 (didn't know replay existed: "when did we add this feature?"; wants it fleshed out and advertised on the map)
- Status: wanted, needs a design
- What: `/warpath replay [hours]` has animated your last hours of trail on the map since 3.0.0 (20 s, up to 24 h, `Map.lua` `StartReplay`), but it's listed only in `/warpath help all`, so nobody finds it. Joe wants it **fleshed out** and **advertised on the world map, next to Warpath's map button** (crossed swords, top-right of the map; Claude's reading of "near the mini map toggle", confirm with Joe). Fleshing out is open: candidates are play/pause and speed, a time scrubber, a clock showing the time reached, kills and deaths appearing as the line reaches them, choosing the window (1 h, 6 h, today).
- Notes: replay draws the march "as one line" (`DrawReplay`) and predates the 3.8 lingering areas, trail-gives-way-to-roads and flight legs. Check in game and in a render that it still looks right with them before advertising it. It's also the base for match replay in battleground mode (Feature requests).

### Rework the settings panel, and first-install defaults
- From: Joe, 2026-11-25
- Status: needs a design
- What: redo the options window: its layout, which settings it offers, and the panel as a whole. At the same time, re-evaluate the defaults a new install starts with.
- Notes:
  - Today: a tabbed window (`Options.lua`, Warpath's own tabs because the client's tab template is missing). The General tab is full (near `BODY_H` 330, radio rows fit about six short choices), which is why new settings have had to squeeze in beside old ones.
  - Start from an inventory: every setting, its default, where it lives (tab, map button menu, slash command), and whether anyone changes it. Some settings exist in two or three places.
  - Defaults to look at: guild sharing is off by default (`cfg.share`), so the guild features, the version check included, do nothing until someone finds the switch; kill screenshots default to every kill; trail length 12 h; which map layers start on.
  - Changing defaults affects only new installs; existing players keep their settings (preserve saved data). Any reset for existing players is called out first, as 3.8.0's map reset was.
  - The update box left this window in 3.8.3 (it's the chronicle's Warpath tab now), so the window no longer opens by itself.

### A clown icon for deaths to mobs
- From: feedback passed on by Joe, 2026-11-24
- Status: needs a design
- What: a pin for dying to a mob would show a clown instead of the grey cross.
- Notes: today it's the raid-marker sheet's cross, desaturated (`TEX_RAID`, texcoords 0.5–0.75, 0.25–0.5; `Map.lua`, pin kind `mob`). Warpath uses only the game's own art, so this needs a Blizzard texture that reads as a clown, with its path checked in the Forever client; no candidate is known yet. Check at normal map size, where pins are small. Falls share the `mob` pin today, so decide whether they get the clown too.

### Tuning knobs, if Joe asks
- From: Claude
- Status: new
- What: zone line under the zone name too central → move or shrink it. Rebuilt haze too strong → `BATTLE_ALPHA`, `BATTLE_FULL`, patch size.

---

## Feature requests

### Battleground mode (3.9.x main feature)
- From: Joe, 2026-11-26 ("we are not done tinkering with 3.8.x, but let's begin planning")
- Status: needs a design. First step: one in-game session to see what the client gives inside a match (below).
- What: Warpath does something useful in battlegrounds instead of resting. Today it records, draws and sends nothing in any instance (`Events.lua` `InsideMatch`).
- Research (2026-11-26), what other addons do: objective timers (Capping, Capped), enemy frames (BattleGroundEnemies, Gladius, sArena), flag carriers (Warsong Flag Carrier, Zurk Maps), incoming calls (BG Defender), enemy detection (Spy), healer marks (Healers Have To Die), honour standing (HonorSpy), match history (REFlex, now retail-only; PVPHistoryClassic+, BG Historian, small on Classic). Nothing remembers a player's battlegrounds over time. Joe's picks from these (2026-11-26): match history, grudges, objective timers, flag carrier tracking, healer marks. Not picked: enemy frames, enemy detection, incoming calls, honour tracking.
- Targets (Joe, 2026-11-26):
  - **Match replay** (Joe: "amazing"): after a match, play your path through it on the battleground map, built on the existing replay. Keep only the last few matches.
  - **Match history and battleground stats**, in the chronicle: a page per match (result, length, killing blows, deaths, nemesis, grudges met) and totals per battleground, with win rates by battleground and faction and personal bests folded in (most killing blows, longest life, least time dead, fastest win).
  - **Grudges inside battlegrounds**: the skull on nameplates and the target frame when a grudge is on the other team (the code exists, switched off by `S.inInstance` in `Grudge.lua`), the match noted in their ledger entry. No banners or sounds mid-fight unless Joe wants them.
  - **Objective timers**: capture countdowns for bases and towers, flag respawn in Warsong Gulch. Built from the game's own status-bar art. Source to find on this client: the battleground system chat messages, or the map's landmark/POI timers.
  - **Flag carrier tracking** (Warsong Gulch): who carries each flag, from the "picked up by" system messages, which needs no addon messages. Health only while the carrier is your target, mouseover or nameplate. Sharing the carrier's health with teammates (Warsong Flag Carrier's trick) needs messages inside: wait for the open investigation.
  - **Healer marks**: mark enemy healers on nameplates, like the grudge skull. Detecting them is the open question: the scoreboard's healing column and class (no combat reads) if this client has it; the combat log likely hides it in combat.
  - **Enemies you meet again** ("decent idea"): count enemy names from the scoreboard across matches ("faced Thrall in 14 matches, your side won 9"), group by guild to spot premades. Ties in with grudges.
  - **Time spent dead**: share of the match dead, and the graveyard you came back at most. Pairs with "Spirit healers on the map".
  - **Victory screenshot**: the scoreboard open at the match's end, through the kill-shot pipeline.
  - **War table for battlegrounds**: this match's killing blows and deaths, your current life, grudges on the other team.
  - **Guild group record**: wins together when two or more guildmates share a match; an opt-in line to guild chat. Depends on messages getting through inside (open investigation in `open-items.md`).
- Known risks:
  - Honourable kills aren't kills: everyone nearby gets credit, so Warpath's kill counting (kill count going up) would inflate inside. Stats need killing blows from the scoreboard (`GetBattlefieldScore`) instead.
  - The game hides values in combat (`ns.Foes.Safe`); battlegrounds are mostly combat.
  - Battleground maps aren't in the harness's captured map rects.
- To check in game first: does the scoreboard API exist and update during the match (`UPDATE_BATTLEFIELD_SCORE`); is there a map ID and player position inside; can the winner be read at the end (`GetBattlefieldWinner`, `PVP_MATCH_COMPLETE`); which battleground system messages arrive (flag pickups, base assaults) and whether they're readable mid-fight; does the scoreboard show healing done; do enemy nameplates show inside. Run the share diagnostics in the same session (open investigation).

### Spirit healers on the map
- From: Joe, 2026-11-25
- Status: needs a design
- What: show where the spirit healers are, so you know where you'll come back after releasing. Neither the Forever client nor Warpath marks them on the world map today.
- Notes:
  - Closest thing today: a corpse run starts recording once you're a ghost (`Record.lua`, mode `g`), so each ice-blue dashed run begins at the graveyard you released at. Corpse runs fade after `cfg.runHours` (24 h default).
  - Natural approach: remember the place where each corpse run starts (or where you rez at a spirit healer, `PLAYER_UNGHOST` with no corpse reached) as a graveyard, per zone, kept permanently like other zone records. Learned only from your own deaths, so unvisited graveyards stay unknown; guildmates could share theirs later.
  - Check whether the client exposes graveyard positions directly (retail has `C_DeathInfo.GetGraveyardsForMap`; check it exists and works on 1.60.1). If it does, every graveyard could show at once without dying first.
  - Look: a small Blizzard icon (an ankh or spirit-healer art, path checked in the Forever client), quiet enough not to clutter. Maybe only while dead, or as a toggle.
  - Saved data: new per-zone key only; nothing changed or removed.

### What you did in a lingering area, on hover
- From: Joe, 2026-11-25
- Status: needs a design
- What: hovering a lingering area ("zone") shows more than how long you were there: gold looted, items looted, XP gained, and other stats useful while levelling and at end game.
- Notes:
  - Today the hover shows only the visit list and time spent (`z.areas`, visits `{ s, e, t }`).
  - Candidates, per visit or per area: gold gained (money before and after, so vendoring counts unless loot is read separately), items looted (count, best quality), XP gained and mobs killed (XP messages), quests turned in, levels gained, reputation gained, deaths, and PvP kills already on the map. Possibly XP per hour while levelling, rep or gold per hour at end game.
  - Check every event exists and reads cleanly on the Forever client, including in combat, where the game hides values (`ns.Foes.Safe`).
  - Areas are pruned after 24 h, so the stats would go with them. Decide whether anything rolls up into the zone's lifetime totals (the zone-entry chat line, the chronicle).
  - Saved-data size: a few numbers per visit is small, item lists aren't; prefer counts.
  - Keep the tooltip short: a few lines, zeros left out, like the zone-entry line.

### Catch up on guildmates' kills and deaths missed while offline
- From: Joe, 2026-11-24
- Status: wanted, needs a design. Waits on the battleground debugging in `open-items.md` (Joe, 2026-11-24: debug that first).
- What: when you log in, get the kill and death pins guildmates made while you were offline, and send yours to guildmates who were offline when you made them.
- Notes:
  - Today the login sync (`Sync.lua`) catches up only **battle haze** cells. Kills and deaths go out once, live over GUILD, so anyone offline never gets them.
  - Natural fit: on the login hello, each guildmate whispers back their own kill/death pins newer than what you last got from them (a per-sender "last seen" time, like `db.syncSent`), trickled behind live traffic like the haze sync.
  - Open question: only the person who made the pin sends it, or guildmates also relay pins they received from others? Own-only is simple, but you miss everything from guildmates who are offline when you log in. Relaying needs a pin id (sender + time) to drop duplicates, and never relays pins back to whoever made them.
  - Same mechanism as the "catch-up on exit" fix for battlegrounds (see `open-items.md`, open investigation): leaving a battleground could send the same hello. Design them together.
  - Guildmates need the new version for it to work both ways; older versions must keep ignoring the new message. Limits: how far back (days), how many pins per guildmate, and whether caught-up pins show differently from live ones.

### Victory pose in kill screenshots
- From: Joe (deferred backlog)
- Status: needs a test in game
- What: strike an emote on a kill and take the screenshot mid-pose.
- Notes: most unknowns, least payoff. First step before any design: test in game whether an addon can fire an emote on this client without a keypress (fallback: keybind or macro).
  - Approach: emote on the kill, delay the screenshot ~0.5–1 s to catch mid-pose (`cfg.shot.delay` already exists), then caption, banner and sound.
  - Constraints: emotes don't animate while moving, mounted or casting, so skip the pose then; emotes are public, so nearby players see "Joe flexes" and it should be a setting; the default camera shows your back; a delayed shot can miss the corpse.
  - Possible settings: off / on / notable only; which emote, or random; per race.

### Screenshot renamer
- From: Joe (deferred backlog)
- Status: needs a design
- What: give kill screenshots readable names. Addons can't rename files, so this is a small companion program outside WoW. The in-game data it needs shipped in 3.4.
- Notes:
  - Reads SavedVariables (per character and `WarpathGlobal`): each kill's predicted file name, shot number, victim, class, zone, tag, streak, times killed.
  - Output names like `2026-11-20 23.31 - Thrall (Shaman) - Arathi Highlands - Grudge.jpg`, optionally into `Screenshots\Warpath\2026-11\`, or by victim or zone. ISO date first; no Windows-forbidden characters; realm suffix optional.
  - Runs after play, since SavedVariables are only written at logout or `/reload`: manual, scheduled, or a launcher shortcut.
  - Match by time within ±2 s plus shot number (the predicted name can be off by a second).
  - Prefer **copying** into a Warpath folder over renaming, since renaming breaks the hover file name on the map unless written back, which is only safe with WoW closed.
  - Non-kill screenshots untouched. PowerShell (nothing to install) or Python (easier to maintain).

---

## Declined and dropped

- Declined 2026-11-26: kill pins on battleground maps from scoreboard killing blows. Too much activity in battlegrounds; the map would fill with pins.
- Declined 2026-11-26: lingering areas on battleground maps (which bases you held). Joe doesn't want to muddy the battleground map.
- Not picked by Joe 2026-11-26 for battleground mode: enemy frames (BattleGroundEnemies, Gladius), enemy detection (Spy), incoming calls (BG Defender), honour tracking (HonorSpy).
- Not offered, Claude's judgement 2026-11-26: battle haze across matches (objectives would just colour in), strategy notes on battleground maps (clutter), live team calls or carrier tracking (Capping and BG Defender do it better, and they need messages inside).
- Declined 2026-11-25: roads dimming inside lingering areas (option C for the Plaguelands pile-up). Rendered on Lethality's real trail it barely changed anything; Joe picked trail giving way to roads instead.
- Declined 2026-11-25: a warning when the old Wake addon is loaded. Only Joe ever had Wake or PvPKillShot, so 3.8.3 removes every mention of both from the addon instead.
- Declined 2026-11-22: receiver-side multi-kill counting for guildmates still on 3.6.
- Dropped: map presets.
- Dropped 2026-11-21: the explainer one-pager.

## Previously rejected ideas

Renamed from "Rejected designs — don't revisit" on 2026-11-23, at Joe's request: this is a reference list, not a prohibition. Anything here can be reopened. The reasons are kept because they are findings worth not rediscovering — particularly the first group, which is the same lesson three times over.

**Road looks (2026-11-24).** Cartographer's ink (vanishes on dark maps like Felwood); trodden earth (blends into the map, tiers hard to tell apart); gold rims beyond gold (busy, like rail track); an engraved groove with deeper red-gold (reads as bronze, a lower metal); gems of any shape or arrangement (at normal map size a road is 4–6 px, so stones read as specks, and even spacing looked uncanny). Faction enamel with gold wires lost to a plain streak.

**Roads and shine.** Thicker solid black border; dark border with light rim; soft halo glow; white or cream sheen line with white star glints. All read as *silver* rather than bright gold. The underlying finding: on this map art, lightening toward white reads as a different metal, not a brighter one. Shine has to stay warm.

**Footsteps.** Soft glow or halo behind fresh dots; lifting colour toward a lighter tint — read as a white-ish haze. Footsteps were removed entirely in 3.7.6.

**Trail.** 3.7.5's footsteps with age-based spacing visibly jumped, because spacing was recomputed per redraw from "now". Trail "option 1" (dashes for the whole life, two tones) lost to option 2 in 3.7.6 on renders.

**Zone entry.** Green and red verdict colouring; live or dynamic zone messages (recent sightings, grudge sightings, guildmate deaths); enemy busy hours (judged worthless and removed, with `z.hours` no longer recorded).

**Map.** Hard-edged heat-map zone dots (unattractive in game); a trail heat map, which turned the map into scribbles while questing; 100% permanent map memory.
