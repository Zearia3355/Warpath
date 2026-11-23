# Warpath open items

Only open things live here. Close items when Joe confirms them; move shipped work to `how-it-works.md` and `CHANGELOG.txt`.

---

## Installed, not yet published

**3.7.11** (tagged and installed 2026-11-23; CurseForge upload failed on a bad token secret, nothing published; re-run release run 45261632007 once the token is fixed). Carries 3.7.10, which never reached the game, plus:
- Garbled guild grudge messages fall back to plain kill wording (`Phrases.CanSay`, used in `Feats.GuildKillLine`). Found by the test harness.
- `## X-Curse-Project-ID: 1826632` in the TOC, and a `LICENSE` file (MIT, not loaded by the game).
- Changed from 3.7.10: `Phrases.lua`, `Feats.lua`, `Warpath.toc`, `Warpath.lua` (version comment), `CHANGELOG.txt`, new `LICENSE`.

## Built and tagged, superseded by 3.7.11

**3.7.10 — receive diagnostics for guild sharing.** Receiver-only; guildmates don't need it. Patch notes **are** written and are in `CHANGELOG.txt` (the handoff said otherwise; the code and changelog disagreed with it). The TOC and the `Warpath.lua` header both read 3.7.10. It reaches the game only on a rev.

- `Share.lua`: `OnComm` is now a `pcall` wrapper around `Receive`, so one bad message can't stop the next; errors are counted (`diag.errors`, `lastError`). Per-session `diag` counts: every addon message (`all`, `allInside`), messages per channel while inside (all prefixes), secret prefixes, Warpath messages (`ours`, `oursInside`), unreadable text or sender, own echo, duplicates, malformed, sharing off, and arrivals during `InChatMessagingLockdown()`. `ns.DiagStatus()` prints three lines plus the last error.
- `Commands.lua`: `/warpath share status` calls `ns.DiagStatus()`.
- Changed from 3.7.9: `Share.lua`, `Commands.lua`, `Warpath.lua`, `Warpath.toc`, `CHANGELOG.txt`. Stub test: all counts correct.

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

**Roads and shine.** Thicker solid black border; dark border with light rim; soft halo glow; white or cream sheen line with white star glints. All read as *silver* rather than bright gold. The underlying finding: on this map art, lightening toward white reads as a different metal, not a brighter one. Shine has to stay warm.

**Footsteps.** Soft glow or halo behind fresh dots; lifting colour toward a lighter tint — read as a white-ish haze. Footsteps were removed entirely in 3.7.6.

**Trail.** 3.7.5's footsteps with age-based spacing visibly jumped, because spacing was recomputed per redraw from "now". Trail "option 1" (dashes for the whole life, two tones) lost to option 2 in 3.7.6 on renders.

**Zone entry.** Green and red verdict colouring; live or dynamic zone messages (recent sightings, grudge sightings, guildmate deaths); enemy busy hours (judged worthless and removed, with `z.hours` no longer recorded).

**Map.** Hard-edged heat-map zone dots (unattractive in game); a trail heat map, which turned the map into scribbles while questing; 100% permanent map memory.
