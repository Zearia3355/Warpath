# Warpath

A World of Warcraft addon for **WoW Forever** that inks your war onto the world map.

Warpath remembers where you fight and where you travel, and draws it back to you:

- **Today's trail** — a solid line for your last five minutes, then dashes that shorten, thin and fade over a window you choose (15 minutes to 24 hours).
- **Silver and gold roads** — routes you use on separate days turn silver, then gild gradually toward gold. Well-worn gold is burnished and shines.
- **Battle haze** — one red that deepens where your fights pile up, yours and your guildmates'.
- **Kills and deaths** — blades and skulls where they happened, fading over days, with the victim's name, class and your streak.
- **Corpse runs and flights** — their own layer, plus the flight routes you keep taking.
- **Enemy sightings**, **dangerous ground** warnings, and a **grudge ledger** that only forgets when you forgive.
- **Multi-kills, streaks and feats**, announced in chat and on screen, shared with guildmates running Warpath.
- **Kill screenshots** with a caption (it absorbs the older PvPKillShot addon).
- **A chronicle book** of your campaigns, and your record in each zone as you enter it.

Two memories sit on the same grid of ground. Long memory builds one mark per *day* you use a piece of ground and halves every 14 days you **play**, so a weekend away costs nothing. Short memory builds with every pass and fades on real time.

Nothing is permanent, and nothing about your trail is ever shared.

## Install

Download the latest release and extract it into `Interface\AddOns`, so that `Interface\AddOns\Warpath\Warpath.toc` exists. Adding or removing files needs a full game restart rather than `/reload`.

## Commands

`/warpath` for your totals, `/warpath help` for the everyday commands, `/warpath help all` for everything. The map button (top-right of the world map) toggles everything Warpath draws; right-click it to pick layers.

## Built with

Lua 5.1 against Interface `16001`. Libraries: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0.

Author: Joe + Claude.
