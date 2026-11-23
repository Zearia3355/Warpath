# Warpath — project guide for Claude Code

Warpath is a World of Warcraft addon for **WoW Forever** (open-world PvP, Interface `16001` / client 1.60.1). It draws your war on the world map — today's trail, worn roads, battle haze, kill and death pins, enemy sightings, flight routes — takes kill screenshots (it absorbed the older PvPKillShot addon), keeps a chronicle book of campaigns and a grudge ledger, and shares kills, deaths and sightings with guildmates. Guildmates run it too, so releases are shared with them.

Originally named **Wake** (1.0).

Feature-by-feature behaviour is in `docs/how-it-works.md`; open items are in `docs/open-items.md`. Read both before changing a feature. Machine-specific paths and character names are in `CLAUDE.local.md`, which is deliberately untracked.

Migrated from a claude.ai Project on 2026-11-23. Everything before that is in `CHANGELOG.txt` and in the imported release history (see below).

---

## Current state (2026-11-23)

- **`main`** is at 3.7.10 plus the repo's own tooling. Tag `3.7.10` is the newest release.
- **Installed in the game:** 3.7.9. 3.7.10 is built and tagged but **not installed** — it reaches the AddOns folder only when Joe says "rev".
- **Saved-data version:** `db.v` = 9 (since 3.7.1).
- **Open investigation:** guildmates' kills don't reach Joe inside battlegrounds. 3.7.10 exists to diagnose it. See `docs/open-items.md`.
- **Nothing else is queued.**

## The repo

History was imported on 2026-11-23: **21 tagged releases, 3.3.5 to 3.7.10**, from the pre-split monolith and the release zips, each commit carrying that version's `CHANGELOG.txt` entry as its body. Blobs were verified byte-identical to the shipped files. Before this, the installed addon folder was the only copy of the code and the zips were snapshots with no diffs — flagged as the project's biggest risk in the 2026-11-23 process review.

**The working copy is not the AddOns folder.** That separation is what enforces the release rule below: installed files change only on a rev, by running the install script, never as a side effect of editing.

- `tools/install.ps1` copies the working copy into the game's AddOns folder. Repo-only files are excluded.
- Releases are tagged with a **bare version number** (`3.7.11`), never `v3.7.11`: the packager uses the tag verbatim as the version string and does not strip a leading `v`, so a `v` tag would publish as "v3.7.11" on CurseForge.
- `.github/workflows/release.yml` fires on such a tag, builds with the BigWigs packager and uploads to CurseForge and the GitHub release.
- The imported tags point at commits from before that workflow existed, so re-pushing history can never trigger an upload.
- `.pkgmeta` keeps libraries **committed in-tree** instead of pulling them as `externals`. Their versions were chosen to work on the Forever client; externals would upgrade them on every build, untested, and lib behaviour cannot be checked outside the game.
- `.gitattributes` pins `eol=lf`, because Git for Windows defaults to `core.autocrlf=true` and the CI runner checks out LF. Without it, a local build and a CI build produce different zips.

### Before CurseForge publishing works

Two things need Joe's account, and the workflow skips the upload until they exist:

1. A CurseForge project, whose id goes in `Warpath.toc` as `## X-Curse-Project-ID: <id>`.
2. A `CF_API_TOKEN` repo secret.

The current packager reads `CF_API_TOKEN` and `GH_API_TOKEN`. The widely-copied wiki example uses `CF_API_KEY` and `GITHUB_OAUTH`; both are deprecated.

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
- The options window opens by itself only for **feature** releases (new minor), not fix releases. Fix releases get no `NEW_IN` entry — so `NEW_IN` ending at an older version than the current one is correct, not a bug.
- `ns.VERSION` comes from the TOC via `GetAddOnMetadata`. The TOC is the only functional version site; the number at the top of `Warpath.lua` is a comment, so keep it in step but know it changes nothing.

### Upgrades and saved data
- **Core tenet: preserve existing saved data.** Import and upgrade it wherever possible.
- Every rev's upgrade must preserve user history. **If it can't, say so before building** and get Joe's agreement. Any deletion is called out and agreed first.
- Prefer **hiding over deleting** (old haze kept as `z.battleOld`; neutral-town data hidden, not wiped).
- Every release's patch notes carry a **"Your saved data:"** line.
- Before installing, say when a reload or restart will drop anything held only in memory. (3.7.4's install dropped unsaved guild pins and Joe noticed.) Live enemy-sighting crests are still memory-only.
- Upgrades run inside `pcall`; on error, print one chat line and start the new feature empty rather than breaking.
- Saved-data versions: `db.v` 4 (3.3.x) → 5 (3.4) → 6 → 7 (3.6.0) → 8 (3.7.0) → 9 (3.7.1). One `MigrateToV<n>` function each, in `Warpath.lua`.

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
2. Build; compile-check every Lua file under Lua 5.1 (limits: 200 locals, 60 upvalues). **See the gap noted under Testing.**
3. In one pass: update `docs/how-it-works.md` (feature state + decision log), `CHANGELOG.txt`, and `docs/open-items.md` (close checks Joe has confirmed, add new ones).
4. Bump `## Version:` in `Warpath.toc`, and the comment at the top of `Warpath.lua` to match.
5. Release summary for Joe: files changed, saved-data impact, whether `/reload` is enough or a restart is needed, and any calls you made yourself.
6. Commit, then on Joe's go-ahead: tag the bare version, push the tag (CI publishes), and run `tools/install.ps1`.

---

## Code layout

Lua 5.1, one shared addon namespace (`ns`). Load order is `Warpath.toc`, which is the dependency graph — check it there, not here:

`Warpath.lua` (constants `ns.C`, state `ns.S`, helpers, migrations, version) · `Phrases.lua` · `Foes.lua` · `Share.lua` (guild comms: `OnComm` → `Receive`, send queue, diagnostics) · `Sync.lua` · `Grudge.lua` · `Overlay.lua` · `Feats.lua` · `Ground.lua` · `Record.lua` · `Campaign.lua` · `Zone.lua` · `Map.lua` (drawing, replay) · `MapButton.lua` · `Minimap.lua` · `Hud.lua` (war table) · `Chronicle.lua` (book window) · `Options.lua` (tabbed window) · `Commands.lua` (command table, help, aliases) · `Events.lua`

Libraries in `Libs\`: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 r56 (taken from Questie's repo).

Each file takes `local ADDON, ns = ...` and shares state through `ns`. Saved data arrives via `ns.OnBind(fn)`: each module registers a closure, and `ns.Rebind()` re-hands `db`, `gdb`, `cfg` and `faction` to all of them at load and login.

Globals written: `Warpath` (public API, for PvPKillShot and friends), `WarpathGlobal` and `WarpathDB` (saved), `SLASH_WARPATH1/2`, and `SLASH_WARPATHSHOT1/2` (only when PvPKillShot is not loaded, so `/killshot` and `/pks` keep working). Nothing else leaks — values defined after their use are forward-declared as locals.

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
- Sync hello: `1|H|full` (GUILD)
- Battle history: `1|B|map|b/d|clear|cells` (whisper)
- Inside instances (`S.inInstance`: battlegrounds, arenas, dungeons, raids): sending is off, own recording is off, **receiving is on** (3.7.8) — but see the open investigation.
- **Never share the player's trail.**
- Guildmates on older versions must keep working. When a change is receiver-side, say in the patch notes that guildmates need the new version too.

## Testing outside the game

**Current gap:** the release checklist calls for a Lua 5.1 compile check, and there is no Lua interpreter on this machine (no `lua`, `luac`, `luacheck`). Python 3.13 is available. The old harness was rebuilt from scratch in a throwaway container and lost with it. Rebuilding it in `tools/`, committed this time, is the highest-value piece of unfinished setup.

Intended shape, from the old project:

- `pip install lupa pycairo` — lupa gives a Lua 5.1 runtime.
- `stub.lua` stubs the WoW API and records the lines and textures drawn.
- `run.lua` loads `Warpath.lua` + `Map.lua` against real SavedVariables and calls `ns.Redraw()` (marks and sightings layers off, `ns.Grudge` stubbed).
- `render.py` draws the recorded lines and textures with pycairo on an olive stand-in background — this is what produces the before/after renders Joe picks from.
- Steadiness test: hook each dash's centre and compare across `NOW` shifts and strokes truncated to an earlier time. Target 0 px movement.
- Line test: load `Warpath.lua`, `Phrases.lua`, `Feats.lua`; call `DeathFields`/`GuildDeathLine`, `KillFields`/`GuildKillLine`.
- Share test: `Share.lua` loads alone with a stub `ns`; call `ns.OnComm` with fake messages.

Map art isn't available outside the game, so final looks are always checked in game.
