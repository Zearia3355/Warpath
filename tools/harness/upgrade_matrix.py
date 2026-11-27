#!/usr/bin/env python3
"""Can the current Warpath upgrade saved data from every older release?

For each release tag, oldest first:
  1. run THAT release (extracted from git) on a fresh character and play a
     short session: walk two zones, change a setting, add a grudge, take a
     PvP kill, die, receive a guildmate's kill, log out;
  2. write its WarpathDB / WarpathGlobal out as SavedVariables text, the way
     the client does at logout;
  3. boot the CURRENT working copy on that data and log in;
  4. check what survived.

    python tools/harness/upgrade_matrix.py            # every tag
    python tools/harness/upgrade_matrix.py 3.4.0 3.6.4

An action an old release doesn't have (grudges before 3.5, say) is skipped,
not counted as a failure. A release that won't run at all in the harness is
reported as such: that's a limit of the stub, not of the upgrade.
"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import REPO, LuaFailure, Wow  # noqa: E402
from render import addon_from_ref  # noqa: E402

# Write a table out as Lua source, like the client's SavedVariables writer.
SERIALISE = r"""
local function ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v then return "0" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end
        return string.format("%.17g", v)
    end
    if t == "table" then
        local parts = {}
        for k, x in pairs(v) do
            local ks
            if type(k) == "string" then ks = string.format("[%q]", k)
            elseif type(k) == "number" then ks = "[" .. string.format("%.17g", k) .. "]"
            elseif type(k) == "boolean" then ks = "[" .. tostring(k) .. "]" end
            local xs = ks and ser(x)
            if xs then parts[#parts + 1] = ks .. " = " .. xs end
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n}"
    end
end
__saved = {
    db = "WarpathDB = " .. (ser(WarpathDB) or "nil") .. "\n",
    gdb = "WarpathGlobal = " .. (ser(WarpathGlobal) or "nil") .. "\n",
}
"""

# What must survive, measured the same way on old and new data. Tolerant of
# layout changes between versions (corpse runs moved out of strokes in 3.4).
MEASURE = r"""
local db, gdb = WarpathDB or {}, WarpathGlobal or {}
local m = { zones = 0, marks = 0, trail = 0, roads = 0, roadsNow = 0, yards = 0, gmarks = 0 }
for _, z in pairs(db.maps or {}) do
    m.zones = m.zones + 1
    m.marks = m.marks + #(z.marks or {})
    m.gmarks = m.gmarks + #(z.gmarks or {})
    m.trail = m.trail + #(z.strokes or {}) + #(z.runs or {})
    -- Road pieces as recorded. From 3.7.12 (db.v 10) side-by-side lanes are
    -- merged into one road, so there are fewer pieces by design; the pieces
    -- as they were are kept hidden in z.roadOld, and that's what must survive.
    for _ in pairs(z.roadOld or z.road or {}) do m.roads = m.roads + 1 end
    for _ in pairs(z.road or {}) do m.roadsNow = m.roadsNow + 1 end
    m.yards = m.yards + (z.yards or 0)
end
m.kills, m.deaths = db.kills or 0, db.deaths or 0
m.grudges = 0
for _ in pairs(gdb.kos or {}) do m.grudges = m.grudges + 1 end
local cfg = gdb.cfg or db
-- quiet mode; from 3.8.3 it lives on as "Announce on screen" off, with sounds off
m.quiet = (cfg.quiet == true or (cfg.announce == false and cfg.sound == false)) and 1 or 0
m.v = db.v or 0
__m = m
"""

KEYS = ["zones", "marks", "trail", "roads", "yards", "kills", "deaths", "grudges", "gmarks", "quiet"]


def measure(wow):
    wow.run(MEASURE)
    m = wow.lua.globals()["__m"]
    return {k: float(m[k] or 0) for k in KEYS + ["v", "roadsNow"]}


def try_cmd(wow, cmd):
    try:
        wow.run(f'if SlashCmdList.WARPATH then SlashCmdList.WARPATH("{cmd}") end')
        return True
    except LuaFailure:
        return False


def play(wow):
    """A short session that touches every kind of saved data."""
    wow.login(settle=2)
    try_cmd(wow, "quiet")                        # a setting changed from its default
    try_cmd(wow, "share on")
    try_cmd(wow, "grudge Aldric-Realm")          # 3.5+
    for i in range(240):                         # two minutes in Felwood
        wow.H.player.x = 0.30 + i * 0.0015
        wow.H.player.y = 0.40 + (i % 30) * 0.002
        wow.advance(0.5)
    # a PvP kill: in combat, the honorable-kill counter ticks
    wow.H.combat = True
    wow.fire("PLAYER_REGEN_DISABLED")
    wow.H.hk = (wow.H.hk or 0) + 1
    wow.fire("PLAYER_PVP_KILLS_CHANGED")
    wow.advance(1)
    wow.H.combat = False
    wow.fire("PLAYER_REGEN_ENABLED")
    wow.advance(2)
    wow.fire("PLAYER_DEAD")                      # a death
    wow.advance(30)
    # a guildmate's kill (saved since 3.7.4)
    try:
        wow.run("if ns.OnComm then ns.OnComm('WARPATH', '1|K|1448|0.40|0.60', 'GUILD', 'Bob Smith') end")
    except LuaFailure:
        pass
    wow.H.player.mapID = 1440                    # into Ashenvale
    wow.fire("ZONE_CHANGED_NEW_AREA")
    for i in range(120):
        wow.H.player.x = 0.50 + i * 0.002
        wow.advance(0.5)
    wow.fire("PLAYER_LOGOUT")


def upgrade(ref, workdir):
    old_dir = addon_from_ref(ref)
    old = Wow(addon_dir=old_dir)
    play(old)
    before = measure(old)
    old.run(SERIALISE)
    s = old.lua.globals()["__saved"]
    char, acct = workdir / f"{ref}-char.lua", workdir / f"{ref}-acct.lua"
    char.write_text(s["db"], encoding="utf-8")
    acct.write_text(s["gdb"], encoding="utf-8")

    new = Wow(saved=char, saved_global=acct, addon_dir=REPO)
    new.H.now = old.H.now                        # upgrade straight after logout
    new.login(settle=5)
    after = measure(new)
    errors = [l for l in new.chat if "hit an error" in l]
    lost = [k for k in KEYS if after[k] < before[k] - (0.5 if k == "yards" else 0)]
    if before["roads"] > 0 and after["roadsNow"] == 0:
        lost.append("roads (merged to nothing)")
    return before, after, errors, lost


def main(refs):
    import subprocess
    if not refs:
        tags = subprocess.run(["git", "-C", str(REPO), "tag"], capture_output=True, text=True).stdout.split()
        refs = sorted(tags, key=lambda t: tuple(int(x) for x in t.split(".")))
    work = Path(tempfile.mkdtemp(prefix="warpath-upgrade-"))
    print(f"{'from':<7} {'db.v':>4}  " + " ".join(f"{k:>7}" for k in KEYS) + "   result")
    worst = []
    for ref in refs:
        try:
            before, after, errors, lost = upgrade(ref, work)
        except LuaFailure as e:
            first = str(e).strip().splitlines()[0][:90]
            print(f"{ref:<7}  --   did not run in the harness: {first}")
            worst.append((ref, "harness"))
            continue
        row = " ".join(f"{int(before[k]):>3}>{int(after[k]):<3}" for k in KEYS)
        verdict = "OK" if not (errors or lost) else ("LOST " + ",".join(lost) if lost else "") + (" ERR " + errors[0] if errors else "")
        if verdict != "OK":
            worst.append((ref, verdict))
        print(f"{ref:<7} {int(before['v']):>4}  {row}   {verdict}")
    print()
    print("columns are before>after; every release upgraded cleanly" if not worst else f"problems: {worst}")
    return 1 if any(w[1] != "harness" for w in worst) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
