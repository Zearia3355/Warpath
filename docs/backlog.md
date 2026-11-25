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

### Several guildmates killing one enemy: duplicate lines and pins
- From: Joe, 2026-11-24
- Status: new
- What: when several guildmates kill the same person, everyone gets duplicates and chat spam. Expected: one kill, said once.
- Notes (from the code, 3.8.2):
  - Every guildmate who credits the kill sends their own `K` message (`Record.lua` `Share("K", …)`), each naming the same victim.
  - The receiver (`Share.lua` `Receive`) drops only an identical message from the same sender (GUILD plus PARTY/RAID copies). Different senders all pass: each prints a chat line (`Feats.GuildKillLine`), adds a pin (`z.gmarks`) at nearly the same spot, and adds to that guildmate's haze layer.
  - Your own kill of that enemy isn't checked against incoming ones either, so you get your line plus a line per guildmate.
  - Fix outline (receiver-side, so it works with guildmates on older versions): group kills of the same victim on the same map within ~30 s. The first report prints and pins; later ones fold into it (one line naming everyone, e.g. "A and B killed Thrall", or silent) and add no pin. Skip a guildmate's report of a victim you just killed yourself. Senders that send no victim name (before 3.7): group by map, a short distance and ~10 s.
  - To decide: haze. Each guildmate's layer counting the kill is arguably right (it's their fight), and the combined haze already damps the rest (0.75 × strongest + 0.15 × others).
  - Ask Joe: is the spam chat lines, pins, or both? Group or raid, or just guild?

---

## Enhancements

### Continent and world maps are hard to read
- From: Joe, 2026-11-25 (screenshots of the world, Kalimdor and Eastern Kingdoms maps)
- Status: needs a design
- What: zoomed out, Warpath draws every kill and death pin, roads, trail scraps and flight dashes at small size, plus each zone's win/loss label. Where they cluster (north Kalimdor, the Plaguelands) it's a pile of overlapping icons, and the win/loss numbers are too small to read among them.
- Notes:
  - What a continent view is for: which zones you win and lose in, and where you've been fighting. Individual pins and road squiggles at that size don't add much.
  - Ideas: on continent and world views, show one readable win/loss badge per zone and drop (or heavily thin) individual pins; or group a zone's pins into one marker with a count; leave out roads and trail scraps there, keep flight legs only if they read; make the win/loss label larger and give it contrast (see "Area time labels are hard to read", same font problem).
  - Pairs with "Zone standing on the zone's own map": decide the badge's look once for both.
  - The world view (both continents) should probably show even less than a continent.
  - Render options from Lethality's real data over these screenshots for Joe to pick; continent placement is already verified against real map rects (`tools/harness/map_rects.lua`).

### Roads, trail and areas pile up where they overlap
- From: Joe, 2026-11-25 (screenshot, Eastern Plaguelands; earlier offered by Claude as "calmer long trails")
- Status: needs a design
- What: where roads, today's trail and lingering areas share ground, they draw on top of each other and the map becomes a mess, worse with the game's quest markers on it. Joe's screenshot had the trail off; with it on, Eastern Plaguelands would be unreadable.
- Notes:
  - Most of the overlap is the trail running along roads you walk every day: the same path drawn twice in two styles. Ideas: where the trail follows a road, draw only the road (or only the newest part of the trail, the bit that says where you just went); hide old trail dashes on silver and gold roads.
  - Areas: roads crossing a filled area draw over it; dim or thin roads inside areas, or draw the area outline only.
  - Fewer marks overall: cap trail dashes per map square, rank-based, never newest-wins, or marks will crawl (anchored, only fade).
  - Quest markers belong to the game and can't be moved; leave room around them only if the map tells us where they are.
  - Real data to render from: Lethality's Plaguelands trail, kept in `tools/out/trail-data-2026-11-24-plaguelands/` (863 points, 4 areas in Eastern Plaguelands). Render options over Joe's screenshot of the same map for him to pick.

### Area time labels are hard to read
- From: Joe, 2026-11-24
- Status: needs a design
- What: the time labels over lingering areas ("23m") are hard to see on the map.
- Notes: from the code (`Map.lua` `GetTag`, `PlaceTag`, `AreaTag`): `GameFontNormalSmall`, no outline; colour is the area's own colour moved 35% towards gold, so a faction red or a faded dusk brown on the yellow parchment, low contrast; alpha follows the area's fade (+0.2), so older areas' labels go dim too. Options to render for Joe over his screenshots: an outline or heavier shadow on the text; a dark Blizzard backing behind it; a stronger, more saturated colour; a slightly larger font; fading the label less than the outline. Keep it warm (brightness from saturation, never towards white) and small.

### Zone standing on the zone's own map
- From: Joe, 2026-11-24
- Status: needs a design
- What: show the zone's win/loss (the same "kills : deaths" standing the continent map shows) on the zone map too. Joe means just the win/loss, not the fuller stats.
- Notes: today the standing (your crest and "kills : deaths", in the winning side's colour) is drawn only on continent views, at each zone's centre, once a zone has 3 or more kills plus deaths (`Map.lua`, "Zone standing", `e.p.far`). On a zone map the centre would sit on top of the pins and trail, so it needs its own place: a corner of the map, or next to the zone's name. Render placements over a screenshot for Joe to pick.

### A clown icon for deaths to mobs
- From: feedback passed on by Joe, 2026-11-24
- Status: needs a design
- What: a pin for dying to a mob would show a clown instead of the grey cross.
- Notes: today it's the raid-marker sheet's cross, desaturated (`TEX_RAID`, texcoords 0.5–0.75, 0.25–0.5; `Map.lua`, pin kind `mob`). Warpath uses only the game's own art, so this needs a Blizzard texture that reads as a clown, with its path checked in the Forever client; no candidate is known yet. Check at normal map size, where pins are small. Falls share the `mob` pin today, so decide whether they get the clown too.

### No chat line when the map button shows or hides Warpath
- From: Joe, 2026-11-24
- Status: wanted
- What: left-clicking the map button to show or hide Warpath on the map prints "Warpath on the map shown." / "hidden (still recording)." in chat. Not needed: you can see the result on the map.
- Notes: the line is in `MapButton.lua` `SetShown()`. Layer toggles from the button's menu already print nothing. Keep the reply for the slash command (`/warpath map`), since every slash toggle replies with its new state (`how-it-works.md`, Commands); only the button click goes quiet. Check whether the button's tooltip should then say "still recording" when hidden, since that hint lived only in the chat line.

### Reopen the "New in" box on demand
- From: Claude (offered, not asked for)
- Status: new
- What: `/warpath new`, or a "What's new" button, to reopen the update window.
- Notes: today it takes `/run WarpathGlobal.seenVersion = nil` then `/reload`.

### Warn when the old Wake addon is loaded
- From: Claude (offered, not asked for)
- Status: new
- What: a chat warning when Wake (the 1.0 ancestor) is also enabled, like the PvPKillShot one.

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
