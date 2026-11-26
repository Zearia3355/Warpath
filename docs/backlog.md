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
