# Settings review (2026-11-26)

Joe asked for a review of every setting before the settings move into the chronicle (backlog: "Rework the settings panel"): what each one really does, whether it's needed, real gaps, and whether the controls make sense to someone who doesn't already know the features. Traced from the code (`Options.lua`, `Warpath.lua`, `Record.lua`, `Share.lua`, `Ground.lua`, `Zone.lua`), not from the labels.

Nothing here is built. Every proposal is Claude's unless marked Joe's.

---

## The biggest problem: kill alerts are four overlapping switches

What happens when you kill someone depends on four settings that interact:

| Today's label | Saved as | What it actually does |
|---|---|---|
| Raid-warning banners and sounds | `quiet` (inverted) | It's really **quiet mode**. Off: every banner becomes a chat line, **every** alert sound stops, the big text stops, ground warnings move to chat, and the line under the zone name disappears. The label mentions none of that. |
| Sounds | `sound` | Alert sounds and the book's page-turn sounds. |
| Big text on screen | `overlay` | Big centred text for multi-kills, streak milestones and "Streak ended". Off: those go to the banner instead. (Ground warnings use the same big text but ignore this switch.) |
| My kills and deaths in chat | `selfChat` | One chat line per kill or death, worded as your guild sees it. |

So a single kill can be a banner, big text, a chat line and a sound, chosen by four switches, one of which secretly overrides the others. "Banners" means the Blizzard raid-warning text at the top of the screen, which a new player has no reason to know.

**Proposal:** one group, three plain controls, no hidden master switch.

> **YOUR KILLS AND DEATHS**
> [x] Announce on screen — *A line at the top of the screen for each kill; big text for multi-kills and streaks.*
> Big text size: Small · Medium · Large
> [x] Also in chat — *One line per kill or death, as your guild sees it.*
>
> **SOUND**
> [x] Play sounds — *Kills, ground warnings, grudge sightings, and the book's pages.*

- `quiet` goes away as a setting. `/warpath quiet` stays as a shortcut that turns off "Announce on screen" and "Play sounds" (and back on).
- The separate big-text on/off goes (its size stays). Someone who wants no big text turns off on-screen announcing. **Claude's call, easy to keep if you'd rather.**
- Saved data: an account with `quiet` on keeps behaving the same (announce off, sounds off, ground warnings to chat, zone line off). Nothing is lost.

---

## Section by section

Verdicts: **keep**, **reword**, **change control**, **move**, **drop**.

### General

| Setting | What it does | Verdict |
|---|---|---|
| Banners / Sounds / Big text / My kills in chat | See above. | **Change control** (the kill-alerts group above) |
| Big text size | Small, medium or large big text. | **Keep** |
| Ground warnings on screen / in chat | When you walk onto ground where you (and guildmates) have died: "Dangerous", "Contested" or "Your hunting ground". | **Reword**: nobody knows what "ground warnings" are. Heading "Dangerous ground", hint: *Warns when you walk where you've died before.* |
| Warn after 1/2/3 deaths | How many deaths on a spot before it counts. | **Reword**: "Warn after 1 / 2 / 3 deaths there" |
| War table panel | The small panel: enemies seen lately, dangerous ground nearby, the grudge skull button. | **Reword**, hint: *A small panel showing enemies seen lately and dangerous ground nearby.* |
| Minimap button | Shows or hides the minimap button. | **Keep**. Hint: *Opens this book.* |
| Share enemy sightings, my kills and my PvP deaths | Guild sharing, **both ways**: with it off you also receive nothing from guildmates (`Share.lua` drops every incoming message), and you don't get the newer-version notice. | **Reword**, the most misleading label of all: "Guild sharing", hint: *See guildmates' kills, deaths and sightings on your map, and share yours. Never your trail.* |
| Share my battle history | Your battle haze goes to guildmates at login. | **Keep**, indented under Guild sharing, since it does nothing without it. |

### Map

| Setting | What it does | Verdict |
|---|---|---|
| Show Warpath on the world map | Same as the crossed swords on the map. | **Keep** |
| Show all pin history | Shows faded pins too. Resets at every login, so it isn't really a setting. | **Move**: it already lives in the map button's menu and `/warpath history`. Drop it from settings. |
| Layers | 7 layers plus guildmates' haze. | **Reword** the unclear ones, below. |
| Shimmer on well-worn gold roads | A moving glint on gold roads. | **Drop**? Purely cosmetic, and one more thing to read. Keep the look as it is. Your call. |
| Map icon size | 25–200%. | **Keep** |
| Today's trail: 15m … 24h | How long the trail stays. | **Keep**. Label "Keep today's trail for". |
| Corpse runs: 1h … 48h | How long corpse runs stay. Flights have their own length (`flightHours`, 24 h), with no control. | **Reword** to "Keep corpse runs for". See gaps for flights. |

Layer names as a stranger would read them:

| Today | Proposed |
|---|---|
| Battle haze | Battle haze — *where fighting happened* |
| Silver and gold roads | Roads — *the routes you travel most* |
| Today's trail | Today's trail |
| Corpse runs and flights | Corpse runs and flights |
| Kills and deaths | Kill and death pins |
| Recent enemy sightings | Enemy sightings — *the last few minutes* |
| Guild sharing | **Guildmates' kills and deaths** (today it reads like the sharing switch) |
| Guildmates' battle haze | Guildmates' battle haze |

Hints in faded italic only where a name isn't enough, so the page stays short.

### Screenshots

| Setting | What it does | Verdict |
|---|---|---|
| Take a screenshot when I get an honorable kill | Kill screenshots. | **Reword**: "Screenshot my kills" |
| Which kills: Every kill / Notable only | Notable = first kill of a player, grudges, avenged, streaks, multi-kills, feats. | **Keep**, with "Notable" explained in one line under it. |
| Caption: Floating text / Caption strip / None | What's drawn on the picture. | **Keep** |
| (hidden) delay 0.5 s, in-combat shots | Slash- and file-only. | Leave hidden. |

### Chronicle & zones

| Setting | What it does | Verdict |
|---|---|---|
| Zone stats in chat | A line of your history when you enter a zone. | **Reword** under a heading "Entering a zone": "A line in chat with my history there" |
| Zone stats under the zone name | A short line under the big zone name. | **Reword**: "A line under the zone's name" |
| Headline in chat at login | The last campaign's headline. | **Keep** |
| Open the chronicle at login | Opens the book after a campaign with fighting. | **Keep**, "Open this book when I log in (after a fight)" |
| Open the chronicle (button) | | **Drop**: you're already in it. |

### Grudges

| Setting | What it does | Verdict |
|---|---|---|
| Banner and sound | When a grudge is sighted. | **Keep** |
| Remind me again after 1/5/15 min | Repeat for the same grudge. | **Keep** |
| Show where on the map | Their crest and name for 15 minutes. | **Keep** |
| Skull on nameplates and target frame | | **Keep** |
| When a player kills me: Do nothing / Offer / Add, then "...after they kill me 2/3/5 times" | Two rows that only make sense read together. | **Change control** into one sentence: "When the same player kills me [3] times: Do nothing · Offer a grudge · Add a grudge" |
| Settling note and "Open the ledger" button | | **Drop**: the Grudges tab is one click away. |

---

## Real gaps

1. **No way to silence guildmates' kill and death chat lines.** With sharing on, every guildmate kill anywhere prints a line. In a busy guild that's spam, and the only way out is turning sharing off, which also loses their pins. Proposal: "Guildmates' kills in chat" under Guild sharing, on by default.
2. **Flights have a hidden length.** Corpse runs get a choice; flights (same layer) are fixed at 24 h. Either drop the corpse-run row too, or one row, "Keep runs and flights for". Claude would merge them.
3. **Guild sharing is off by default and hard to find**, so most guildmates may never see each other's kills. Changing the default only helps new installs; existing players keep their choice. A cheaper fix that also helps existing players: a "Guild sharing" checkbox on the Warpath tab's welcome page, right where it already says sharing is off. Defaults are Joe's call.
4. **No "Restore defaults".** One small button at the bottom of each section, with a confirm.
5. **Two map settings are per character and slash-only** (`/warpath memory`, `/warpath roads`: how fast roads and haze fade, how soon roads turn gold). Fine as advanced commands; just not on the page.

## What the pages would hold

| Section | Rows now | Rows proposed |
|---|---|---|
| General | 12 checks, 2 choice rows | 7 checks, 2 choice rows (alerts 3, sound 1, dangerous ground 2+1, war table and minimap 2, guild sharing 3) |
| Map | 12 checks, slider, 2 choice rows | 10 checks, slider, 2 choice rows |
| Screenshots | 1 check, 2 choice rows | same |
| Chronicle & zones | 4 checks, 1 button | 4 checks |
| Grudges | 3 checks, 3 choice rows, note, button | 3 checks, 2 choice rows |

## Decisions (Joe, 2026-11-26: "Agree with all except 5, where I want these separate lengths.")

1. The kill-alerts group: quiet mode, banner, big text and chat merged into the three controls above. **Yes.**
2. Drop the big-text on/off (keep size). **Yes.**
3. Drop shimmer as a setting. **Yes.**
4. Guildmates' kills in chat: add the switch. **Yes.**
5. One length for runs and flights. **No: separate lengths.** Flights get their own row, "Keep flights for", beside "Keep corpse runs for" (gap 2 closed by adding the control).
6. Guild sharing checkbox on the welcome page, and default on for new installs. **Yes.**
