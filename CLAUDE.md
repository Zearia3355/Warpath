# Warpath — project guide for Claude Code

Warpath is a World of Warcraft addon for **WoW Forever** (open-world PvP, Interface `16001` / client 1.60.1). It draws your war on the world map — today's trail, worn roads, battle haze, kill and death pins, enemy sightings, flight routes — takes kill screenshots, keeps a chronicle book of campaigns and a grudge ledger, and shares kills, deaths and sightings with guildmates. Guildmates run it too, so releases are shared with them.

Originally named **Wake** (1.0).

Feature-by-feature behaviour is in `docs/how-it-works.md`; work in progress is in `docs/open-items.md`. Read both before changing a feature. Future work (bugs, enhancements, feature requests, and ideas already declined) is in `docs/backlog.md`: when Joe reports a bug or asks for something that isn't being built now, add it there. Machine-specific paths and character names are in `CLAUDE.local.md`, which is deliberately untracked.

Migrated from a claude.ai Project on 2026-11-23. Everything before that is in `CHANGELOG.txt` and in the imported release history (see below).

---

## Current state (2026-11-25)

- **Installed in the game: 3.8.3-test5** (2026-11-26, branch `areas-merge`, by script): test4 plus combined pins smaller (at most 1.5× a pin) with no number under them, and continent scores stepping around pins (Joe's picks). `/reload` loads it (no new files); the version shown stays test3 until a restart. Backup `tools/out/savedvars-backup-2026-11-26-3.8.3-test5/`. Before it, **3.8.3-test4** (2026-11-25, commit `f88ef16`): test3 plus past area outlines dashed closer together (Joe's pick H). `/reload` loads it (no new files); the version shown stays test3 until a restart. Backup `tools/out/savedvars-backup-2026-11-25-3.8.3-test4/`. Before it, **3.8.3-test3** (commit `3a9957d`): test2 plus the zone score in the zone map's corner, blue/yellow/red scores, one score per continent on the world map, crowded pins combining into a big sword or skull, the trail giving way to roads, yellow area labels, Wake and PvPKillShot removed, and the welcome and What's New on the chronicle's new Warpath tab (the book opens there after an update). **Needs a full restart** to show the new version and open the book. Backup `tools/out/savedvars-backup-2026-11-25-3.8.3-test3/`. Before it, **3.8.3-test2** (commit `8977243`): test1's areas plus three backlog fixes: ground warnings stay up 4–6.5 s, the map button's click prints no chat line, and a kill several guildmates get credit for is said and pinned once. `/reload` is enough (no new files); the version shown stays 3.8.2 until a restart. Backup `tools/out/savedvars-backup-2026-11-25-3.8.3-test2/`. Before it, 3.8.3-test1 (2026-11-24): wider lingering areas in the open world, tighter in cities, touching areas merge. See `docs/open-items.md` (3.8.3 batch, Trail rework).
- **3.8.2 is released** (2026-11-24): inside the area you're lingering in, only the last 3 s of trail show (was 45 s). Published by CI to CurseForge and GitHub Releases; Joe installs from the CurseForge app.
- **3.8.1 is released** (2026-11-24): guild version check, `/warpath trail clear`, update window after every release. Published by CI to CurseForge and GitHub Releases. Installed in Joe's game through the CurseForge app (an update from 3.8.0), which worked. New files take roughly 15–20 minutes of CurseForge review before they are listed.
- **3.8.0 "Roads, trails and flights" is released** (2026-11-24): tagged `3.8.0` on `main`, published by CI to CurseForge (upload "Success", visibility still subject to the project's moderation) and GitHub Releases (`Warpath-3.8.0-forever.zip`, identical file for file to a local `git archive` build). **Not installed by `tools/install.ps1`:** Joe is installing it himself from the CurseForge app to test that route; his game still has 3.8.0-test7 until he does. SavedVariables backup before it: `tools/out/savedvars-backup-2026-11-24-3.8.0/`. See `docs/open-items.md` (3.8.0).
- **3.7.11 is released**: tagged, published to CurseForge (pending the project's moderation) and GitHub Releases. It was installed in Joe's game (byte-identical to the published zip) until the road test builds replaced it. It was the first release through the pipeline.
- **Installed before that:** **3.7.12-test2** (2026-11-24), a prototype of the roads rework from branch `roads-snap`, not `main`. Installed under its own label because installed files never change under an existing version number. Joe checked it in game: "a lot better initially"; everything is still silver, and he is watching how gilding arrives as he plays. SavedVariables backups: `tools/out/savedvars-backup-2026-11-23/` (before the first test build) and `-2026-11-24/`.
- **Saved-data version:** `db.v` = 10 on Joe's characters (the test build's road merge). **Never reinstall 3.7.11 over it:** 3.7.11's `Migrate()` doesn't know version 10 and would rerun `MigrateToV4`, which recounts kills and deaths from pins and inflates totals. To go back, restore a backup with the game closed.
- **Open investigation:** guildmates' kills don't reach Joe inside battlegrounds. 3.7.10's diagnostics (in 3.7.11) exist to diagnose it. See `docs/open-items.md`.
- **3.8.0 "Roads, trails and flights"** (Joe, 2026-11-24): the roads rework, the trail rework and a coming flight-path rework ship together as a feature release.
- **Installed in the game: 3.8.0-test7** (2026-11-24, from branch `trail-areas`): test6 with continent-map flight legs at 65% width, like zone maps (Joe, after seeing test6 in game; the blue reads). Joe confirmed the flight dashes look good in test7. Before that, 3.8.0-test6: test5 with the flight legs recoloured. test5's warm gold dashes were nearly invisible on the parchment map; test6 draws them royal blue with a dark casing, thinner on zone maps (Joe's picks from renders over his screenshots). Needs a full restart. Before that, 3.8.0-test5 (merge `a4fe53d` + label): the roads prototype, the trail rework and the flight legs together (new `Flights.lua`). test5 added the flight legs (from the flight-path session) and the area fixes from test4 play (reopen after a minute inside, a readable visit list, corridors stay lines, only your last 45 s of line inside the live area). Earlier, for the trail: test2 joined the trail to your arrow; test3 makes the line solid for 2.5 min with a small colour jump, and fixes trail vanishing on a return to an area and loops looking new; test4 adds dash smoothing, even dash/arrow spacing, hidden trail staying hidden on leaving, and areas measured in yards with short trips and recent trail joining. SavedVariables backups: `tools/out/savedvars-backup-2026-11-24-test1/` (before the trail rework), `-test2/`, `-test3/`, `-test4/`, `-test5/`, `-test6/`, `-test7/`. It adds `z.areas` and `z.air` only; going back to 3.7.12-test2 is safe (it ignores the key). See `docs/open-items.md` (Trail rework).
- **Roads rework (3.7.12 prototype, now part of 3.8.0):** built and in game test; what's left before release is in `docs/open-items.md` (Roads rework). The design, thresholds and decisions are in `docs/how-it-works.md` (Roads, decision log).

## The repo

History was imported on 2026-11-23: **21 tagged releases, 3.3.5 to 3.7.10**, from the pre-split monolith and the release zips, each commit carrying that version's `CHANGELOG.txt` entry as its body. Blobs were verified byte-identical to the shipped files. Before this, the installed addon folder was the only copy of the code and the zips were snapshots with no diffs — flagged as the project's biggest risk in the 2026-11-23 process review.

**The working copy is not the AddOns folder.** That separation is what enforces the release rule below: installed files change only on a rev, by running the install script, never as a side effect of editing.

- `tools/install.ps1` copies the working copy into the game's AddOns folder. Repo-only files are excluded.
- Releases are tagged with a **bare version number** (`3.7.11`), never `v3.7.11`: the packager uses the tag verbatim as the version string and does not strip a leading `v`, so a `v` tag would publish as "v3.7.11" on CurseForge.
- `.github/workflows/release.yml` fires on such a tag, builds with the BigWigs packager and uploads to CurseForge and the GitHub release.
- The imported tags point at commits from before that workflow existed, so re-pushing history can never trigger an upload.
- `.pkgmeta` keeps libraries **committed in-tree** instead of pulling them as `externals`. Their versions were chosen to work on the Forever client; externals would upgrade them on every build, untested, and lib behaviour cannot be checked outside the game.
- `.gitattributes` pins `eol=lf`, because Git for Windows defaults to `core.autocrlf=true` and the CI runner checks out LF. Without it, a local build and a CI build produce different zips.

### CurseForge

The project exists as of 2026-11-23: **Warpath Forever**, project id **1826632**, MIT licensed, listed publicly, 3rd-party distribution allowed. Its id is in `Warpath.toc` as `## X-Curse-Project-ID: 1826632`.

**The CurseForge project is named "Warpath Forever"; the addon is still "Warpath".** The plain name was already taken on CurseForge by an abandoned 2024 travel tracker, and names are global. `package-as: Warpath` in `.pkgmeta` keeps the folder, the slash commands and the saved data untouched, so this is a storefront name only. Don't "fix" the mismatch.

**Token status: valid** (2026-11-24; the CurseForge check returns HTTP 200 and lists WoW Forever 1.60.1). Getting there took four tries, all for one reason: the clipboard held the `gh secret set` command, not the token, when it was pasted at `gh`'s hidden prompt. Opening a terminal with a command already typed in, or a Run button, appears to replace the clipboard. **Copy the token only after the prompt is waiting.** The packager's `[token set]` only means the secret is non-empty; verify with the **CurseForge check** workflow (Actions → CurseForge check → Run), which goes red unless CurseForge returns a version list. Tokens are made at `https://authors.curseforge.com/#/settings/api-tokens` (Author Settings → API Tokens; the portal uses hash routes, so the older `/account/api-tokens` path that third-party guides cite lands on Not Found). A token pasted anywhere else, chat included, is exposed: revoke it and make a new one. A failed publish is re-run with `gh run rerun <id>`, but a re-run builds from the tag's commit, so a fix to packaging config needs the tag moved (see the decision log).

A new project is invisible to others and its files do not sync until a moderator approves it. CurseForge reviews roughly 2,000 new projects a week and rejections come back with a reason.

---

## Rules (Joe's, standing)

### Release
- Fixes collect in the working copy and **only reach the AddOns folder when Joe says to rev.** Never stealth-update installed files.
- **Every release gets a new version number** and patch notes. Never change installed files under an existing version number (a fix after 3.4.0 is installed ships as 3.4.1).
- Releases are cumulative ("Includes 3.7.0 to 3.7.8").
- Patch notes go in `CHANGELOG.txt`, newest first, in the existing plain style: plain-language bullets, aimed at guildmates, not at developers.
- The explainer one-pager was dropped on 2026-11-21. Releases no longer update it.

### Versioning
- Tinkering with existing features stays in the current minor series (3.7.x).
- A new minor version (3.8.0) is for new features.
- After **every** release, fix releases included (Joe, 2026-11-24), the chronicle opens by itself on its **Warpath** tab: a welcome and What's New (from 3.8.3; the options window before). Every release gets a `NEW_IN` entry in `Options.lua`, keyed by its version, plain lines for players; the page lists every release newest first and marks those newer than what the account last saw (a test build counts as before its release). The `NewIn` test fails if the current release has no entry.
- `ns.VERSION` comes from the TOC via `GetAddOnMetadata`. The TOC is the only functional version site; the number at the top of `Warpath.lua` is a comment, so keep it in step but know it changes nothing.

### Upgrades and saved data
- **Core tenet: preserve existing saved data.** Import and upgrade it wherever possible.
- Every rev's upgrade must preserve user history. **If it can't, say so before building** and get Joe's agreement. Any deletion is called out and agreed first.
- Prefer **hiding over deleting** (old haze kept as `z.battleOld`; neutral-town data hidden, not wiped).
- Every release's patch notes carry a **"Your saved data:"** line.
- Before installing, say when a reload or restart will drop anything held only in memory. (3.7.4's install dropped unsaved guild pins and Joe noticed.) Live enemy-sighting crests are still memory-only.
- Upgrades run inside `pcall`; on error, print one chat line and start the new feature empty rather than breaking.
- Saved-data versions: `db.v` 4 (3.3.x) → 5 (3.4) → 6 → 7 (3.6.0) → 8 (3.7.0) → 9 (3.7.1) → 10 (3.7.12, on `roads-snap`). One `MigrateToV<n>` function each, in `Warpath.lua` (`MigrateToV10` calls `ns.MergeLanes` in `Record.lua`).

### Upgrading from hand-copied installs (verified 2026-11-23)

Every release from 3.3.5 to 3.7.10 upgrades to the current version with nothing lost, tested by `Upgrades` on every push. A mutation check (deleting marks in the 3.4 step) failed exactly the 3.3.5 row, so the test sees real upgrade steps. Limits: the data is a short synthetic session, not years of play; nothing older than 3.3.5 exists to test (the code routes any saved-data version below 4 through `MigrateToV4`); the old **Wake** addon's data is a different addon and is never imported.

Moving a hand-copied install to the CurseForge app: saved data lives in `WTF`, not the addon folder, so nothing is lost however the files arrive. The app recognises addons by matching files against uploads, so a hand-copied folder shows as an unknown local addon with no updates. Install "Warpath Forever" through the app once. Removing the old `Interface\AddOns\Warpath` folder first is safe and avoids leftovers or "modified" warnings. This only works because `package-as: Warpath` keeps the folder name: a different folder name would orphan everyone's saved data. **Never change `package-as`.**

### Design principles
- **Preserve Blizzard's art and the Warcraft theme.** Build UI from the game's own textures, fonts and sounds; no custom art. Verify texture paths exist in the Forever client.
- **Don't clutter** the map or UI, especially where seeing the other faction is expected (neutral towns: Booty Bay, Gadgetzan, Ratchet, Everlook, Light's Hope). Hide, don't erase.
- **Brightness comes from saturation, never from lightening toward white.** Any white or cream highlight reads as silver on roads and as haze on footsteps. Keep shine warm — yellow, amber, bronze.
- Map marks must be **anchored to the ground and only fade.** Anything recomputed per redraw from "now" — spacing by age, newest-wins caps, gap checks — makes marks crawl. Joe notices and rejects jumping.
- Kill card: small and unobtrusive, top centre.
- Fading as the default view, with a "show all history" toggle, beats permanent clutter.

### Working with Joe
- He wants direct analysis and real pushback, not validation. No padding.
- **Visual changes: render before/after from his real saved data before building**, and let him pick from the renders. He approves looks in game.
- When you make a design call yourself, **say so explicitly** in the release summary and log it in the decision log in `docs/how-it-works.md`, marked "Claude's call", so he can veto it. Buried decisions were a recurring problem.
- Batch fixes into **one release per play session** rather than one release per in-game reaction. The trail was redesigned six times in two days that way. Git makes this easier: iterate on `main` without releasing, and rev once.

### Release checklist
1. Read this file and `docs/how-it-works.md`.
2. Build; run `python tools/harness/check.py` and `python tools/harness/test_warpath.py` (with `WARPATH_WTF` set, so real characters boot too). CI runs both on every push and the release workflow won't publish unless they pass.
3. In one pass: update `docs/how-it-works.md` (feature state + decision log), `CHANGELOG.txt`, the release's `NEW_IN` entry in `Options.lua` (plain, one line per change, for players), and `docs/open-items.md` (close checks Joe has confirmed, add new ones).
4. Bump `## Version:` in `Warpath.toc`, and the comment at the top of `Warpath.lua` to match.
5. Release summary for Joe: files changed, saved-data impact, whether `/reload` is enough or a restart is needed, and any calls you made yourself.
6. Commit, then on Joe's go-ahead: back up SavedVariables, tag the bare version, push the tag (CI publishes). Watch the run until the log shows the CurseForge upload "Success", then until the version is listed on the CurseForge files page (about 15–20 min of review). Joe installs releases from the CurseForge app (from 3.8.0); run `tools/install.ps1` only if he asks. Test builds still install by script.

---

## Code layout

Lua 5.1, one shared addon namespace (`ns`). Load order is `Warpath.toc`, which is the dependency graph — check it there, not here:

`Warpath.lua` (constants `ns.C`, state `ns.S`, helpers, migrations, version) · `Phrases.lua` · `Foes.lua` · `Share.lua` (guild comms: `OnComm` → `Receive`, send queue, diagnostics) · `Sync.lua` · `Grudge.lua` · `Overlay.lua` · `Feats.lua` · `Ground.lua` · `Record.lua` · `Linger.lua` (lingering areas: recording, outline geometry, clipping; 3.8) · `Flights.lua` (flight legs: recording, conversion from routes; 3.8) · `Campaign.lua` · `Zone.lua` · `Map.lua` (drawing, replay) · `MapButton.lua` · `Minimap.lua` · `Hud.lua` (war table) · `Chronicle.lua` (book window) · `Options.lua` (tabbed window) · `Commands.lua` (command table, help, aliases) · `Events.lua`

Libraries in `Libs\`: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 r56 (taken from Questie's repo).

Each file takes `local ADDON, ns = ...` and shares state through `ns`. Saved data arrives via `ns.OnBind(fn)`: each module registers a closure, and `ns.Rebind()` re-hands `db`, `gdb`, `cfg` and `faction` to all of them at load and login.

Globals written: `WarpathGlobal` and `WarpathDB` (saved), `SLASH_WARPATH1/2`, and Warpath's own named frames. Nothing else leaks — values defined after their use are forward-declared as locals.

Constraints:
- The original single file hit Lua's limits (192/200 top-level locals; `Draw()` at 47/60 upvalues). Keep files and functions small.
- **Adding a file, or changing the `.toc`, needs a full game restart**, not `/reload`. The version shown in-game comes from the `.toc` and stays stale until restart; patch notes say so.
- The Options window's General tab is near `BODY_H` (330): add settings beside existing ones, not as new rows. Radio rows fit about six short choices.

## WoW Forever client quirks

- Addon-message senders arrive as **"First Last"** — a space, no realm. `GetNormalizedRealmName()` is empty. Your own GUILD addon messages **echo back to you**. Never build a whisper target by appending a realm; compare with `ns.IsMe` / `ns.IsEcho`. (3.7.1 fixed a spam loop caused by this.)
- `C_ChatInfo.InChatMessagingLockdown` exists (Forever 1.60.1); messages may arrive as secret values during lockdown.
- In combat the game hides whether a unit is hostile, dead, even a player. Reading a hidden value is an error, so every read goes through `ns.Foes.Safe`, which turns "hidden" into nil.
- The client hides who killed you. Killer = last hostile player targeted in the 20 s before death, a best guess. Victims: what the game still exposes, then remembered enemies, then last enemy targeted within 15 s.
- Bullet and star glyphs can draw as boxes in the game font: draw small textures instead.
- Use `IsVisible()`, not `IsShown()`, for Blizzard font strings (the zone-name text keeps its shown flag after fading).
- Don't hand-break UI text: set a width and let it wrap.
- The client's tab template was missing (left red buttons); Warpath draws its own tabs.
- Which dropdown API exists varies (`MenuUtil` vs `UIDropDownMenu`); both are coded.
- Addons can't rename, move or write files, and `Screenshot()` takes no file name. Screenshots are `WoWScrnShot_MMDDYY_HHMMSS.jpg`.
- New characters get every addon enabled by default.
- SavedVariables are written only at logout or `/reload`. Edit them only with the game closed.

## Guild message protocol

Prefix-based addon messages (`WARPATH`, proto `1`). Old versions safely ignore unknown messages.

- Kill: `1|K|map|x|y|pool|line|chain|feat|featLine|a1|a2|cry|victim`
- Death: `1|D|map|x|y|killerFull|streak|line|took` (from 3.7.6, `line` is set for every death)
- Sync hello: `1|H|full|version` (GUILD; the version from 3.8.1. Older versions read only `full`. A receiver on an older release prints one chat line per session, again only for an even newer one; test builds never count. Only between guildmates with sharing on.)
- Battle history: `1|B|map|b/d|clear|cells` (whisper)
- Inside instances (`S.inInstance`: battlegrounds, arenas, dungeons, raids): sending is off, own recording is off, **receiving is on** (3.7.8) — but see the open investigation.
- **Never share the player's trail.**
- Guildmates on older versions must keep working. When a change is receiver-side, say in the patch notes that guildmates need the new version too.

## Testing outside the game

`tools/harness/` loads the real addon under **genuine Lua 5.1** (lupa's bundled `lua51`, not LuaJIT) against a stubbed WoW API. Setup: `pip install lupa pillow`. Nothing in `tools/` ships to players.

| Command | What it does |
|---|---|
| `python tools/harness/check.py` | Compiles every file in `Warpath.toc` order with the real 5.1 compiler, so the 200-local / 60-upvalue limits are enforced exactly. Reports each file's top-level locals used (heaviest: `Map.lua`, ~81/200) and any `.lua` the TOC never loads. |
| `python tools/harness/test_warpath.py` | Boot, slash commands, an hour of simulated play, guild sharing and the 3.7.10 diagnostics, every chat line at every index, map drawing. |
| `WARPATH_WTF=<account dir> python tools/harness/test_warpath.py` | Also boots every real character (`RealData`): no Lua errors, nothing lost, SavedVariables checksummed before and after to prove they are never written. |
| `python tools/harness/upgrade_matrix.py [tags]` | For every release tag: that release plays a session and saves, then the working copy upgrades the data. Prints what survived. Also runs as the `Upgrades` test (CI checks out tags for it). |
| `python tools/harness/render.py --wtf <account dir> --char Name-Realm [--map ID] [--ref A --ref B] [--layers roads,trail] [--backdrop shot.png --canvas x1,y1,x2,y2]` | Renders the map from real saved data with the addon's own `Map.lua`. Repeated `--ref` renders each git ref side by side: the before/after Joe picks from. `--ref work` is the uncommitted working copy. Defaults to the zone with most roads, as of the character's last logout. `--backdrop` draws over an in-game screenshot of the same map (`--canvas` cuts out the map's canvas), at its in-game size. |

How the stub behaves, so you know what a failure means:
- **Widgets accept any method** as a recorded no-op; methods whose results matter (sizes, points, text, colours, line endpoints, blend, draw layer) are implemented.
- **Unknown globals stay nil**, as in the client, because Warpath guards optional APIs with `if C_X and C_X.Y`. A missing stub fails loudly with a traceback naming it: add the stub, don't make globals magic.
- A test failure can be the stub's fault. Two were found while building it (an animation type mistaken for a frame name, which invented a global called `Alpha`; `SetAllPoints` not inheriting size, which made the map silently draw nothing). Check that before blaming the addon.
- Time is controlled: `wow.H.now` (wall clock), `wow.advance(s)` runs `C_Timer` callbacks in order.
- World positions: every map is 4000 yards wide unless a test sets `__H.mapYards[id]` (a city such as the Undercity is about 1000). Set it before `login()`: `Linger.lua` reads a map's width once, at its first sample.

Renders are trustworthy for geometry, colour, alpha, thickness, fade and draw order (frames by frame level), and draw text (scores, counts, area labels) in a stand-in bold serif at the font template's size; tests pin orientation (a kill at 0.25, 0.75 draws at exactly that point) and placement of other zones.

**Other zones need real map rects.** `Map.lua` draws every zone with data onto the viewed map via `C_Map.GetMapRectOnMap`. The first stub answered "covers the whole map" for every pair, and a Felwood render came out 95% other zones' roads stacked full-size. Joe caught it against an in-game screenshot on 2026-11-23. The client's real rects were captured on 2026-11-23 and are committed as `tools/harness/map_rects.lua` (41 real overlaps plus the list of maps the capture covered). On this client **no zone overlaps another zone**: every zone-on-zone rect is 0,0,0,0, so a zone map only ever shows its own data, and the 41 overlaps all place zones on Kalimdor (1414) or Eastern Kingdoms (1415). Continent views render correctly from them. A pair of maps the capture didn't cover is treated as "no overlap" and `render.py` reports it as not placed. After visiting new zones, re-capture by running this on the character in game, then `/reload` (it adds a `mapRects` key to `WarpathGlobal`, which Warpath ignores; the harness merges it over the fixture, and the fixture can be regenerated from it):

    /run local m,t=WarpathDB.maps,{} for a in pairs(m) do for b in pairs(m) do local ok,x,X,y,Y=pcall(C_Map.GetMapRectOnMap,a,b) if ok and x then t[a]=t[a] or {} t[a][b]={x,X,y,Y} end end end WarpathGlobal.mapRects=t

**Judge colours over real map art.** The world map is yellow-gold parchment. Warm gold flight dashes looked fine on the olive stand-in and were nearly invisible in game (3.8.0-test5). Render colour choices with `--backdrop` over one of Joe's screenshots.

Lesson: a render that *looks* like a map proves nothing. Check new render features against an in-game screenshot of the same data.

Verified against in-game screenshots on 2026-11-23 (Lethality's data): Felwood (road shape and skull positions) and Kalimdor (northern skull cluster, the blue blade marks east of it, the trail south). Joe confirmed both. Map art and icon textures exist only in the client, so the ground is an olive stand-in and icons are simple glyphs. **Final looks are always checked in game.**

The harness's first real catch: a garbled guild message with the grudge wording and no victim printed "settled a grudge in Felwood:  falls!". Fixed in 3.7.11; now a regular test.

**Steadiness** (`Steadiness` tests) guards the "anchored to the ground, only fade" rule: walk, stop, then as time passes no trail ink may appear where there was none. It deliberately does *not* compare segment centres, as the old project's test did — a dash crossing a bend is several segments whose split point changes as it shortens, so centres move even when the dash doesn't. A companion test proves the check catches a 3 px crawl. 3.8 added: dashes stay put when you walk on after a stop (dash smoothing narrows near a stroke's end; 2 slots of smoothing fails it), and dashes and arrows are evenly spaced at every age.

**Lingering** (`Lingering` tests, 3.8) covers the areas: forming and freezing, not from standing still, not split by short trips, return visits, yards vs map fractions, short trips and recent trail joining, the trail stopping at the outline (and staying hidden when you leave), areas and links only fading, the trail reaching your arrow between redraws, and pruning. Each was checked by switching its feature off (or putting the bug back): several first versions passed against the bug, usually because they checked too late or the old thresholds happened to cover the case. `ns.Linger.State()` exposes the live recording state for tests.

**Road fading** (`RoadFading` tests, 3.7.12) extends that rule to roads: play-days pass with nothing walked, and no road ink may appear or get more opaque from one day to the next. Simulate play-days by setting `ns.db.play.days` *and* nudging `wow.H.now` by a second: `PlayNow()` caches per second, so without the nudge the clock silently doesn't move. Any rule that looks at neighbours (joins, scraps, loops, threads, smoothing) can break only-fade even when each piece fades correctly; the 3.7.12 prototype did exactly that and only a time-lapse showed it. `Roads` tests cover snapping, the lane merge, gap joins and loop folding.

Lessons from the 3.7.12 road work, worth keeping:
- **Prove each new test can fail** by briefly reintroducing the bug. Three road tests passed against the bug on their first version (a test compared against its own setting; one never reached the state it checked; one was masked by another rule).
- **Measure on drawn lines, not pixels.** A pixel-brightness check counted gold fading to silver as "brightening", because silver is paler.
- **Look renders:** to render zoomed in, set `WarpathOverlay.__w/__h` after login (the overlay copies the canvas size once). For colour progressions, a synthetic swatch (one test road per strength) beats real data, which has few strong roads; label rows by habit or days of use, not raw strength. To preview levels real roads haven't reached, scale every `e.l` and say so on the render.
- **Normal map size decides.** A road is 4–6 px wide at default zoom; any detail smaller than that (gems, rims) becomes specks. Judge every look at normal size as well as zoomed.
