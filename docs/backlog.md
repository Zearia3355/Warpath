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

_None reported outside the work in `open-items.md`. The guild-sharing-in-battlegrounds problem is an open investigation there._

---

## Enhancements

### Reopen the "New in" box on demand
- From: Claude (offered, not asked for)
- Status: new
- What: `/warpath new`, or a "What's new" button, to reopen the update window.
- Notes: today it takes `/run WarpathGlobal.seenVersion = nil` then `/reload`.

### Warn when the old Wake addon is loaded
- From: Claude (offered, not asked for)
- Status: new
- What: a chat warning when Wake (the 1.0 ancestor) is also enabled, like the PvPKillShot one.

### Calmer long trails
- From: Claude (offered, not asked for)
- Status: new
- What: hide old trail dashes on silver and gold roads, or cap dashes per map square.
- Notes: any cap must be rank-based, never newest-wins, or marks will crawl.

### Tuning knobs, if Joe asks
- From: Claude
- Status: new
- What: zone line under the zone name too central → move or shrink it. Rebuilt haze too strong → `BATTLE_ALPHA`, `BATTLE_FULL`, patch size.

---

## Feature requests

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
