-- Warpath: Foes
local ADDON, ns = ...
local C, S = ns.C, ns.S
local FullName, Secret = ns.FullName, ns.Secret

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

-- In combat the game can hide whether a unit is hostile, dead, even a
-- player. Testing a hidden value is an error, so every read goes through
-- Foes.Safe, which turns "hidden" into nil ("don't know").
local Foes = { known = {}, last = nil, miss = nil,
    info = {},                                       -- full -> { lv, ra, gu }: level, race, guild when last read
    win = { till = 0, names = {}, unnamed = false }, -- the current burst of kill credit
    counted = {},                                    -- victim -> when their kill was counted
    credits = 0, kills = 0,                          -- raw credits vs kills counted, this session
    dead = false,                                    -- dead now; PLAYER_DEAD can repeat
    near = {}, allies = {},                          -- full -> when last seen, hostile / friendly players
    dying = {},                                      -- full -> { short, class, at }: enemies seen dead (3.7)
    log = {} }                                       -- the last honorable-kill credits, for /warpath debug kills

function Foes.Safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok and not Secret(v) then return v end
end

-- Level, race and guild, whenever the game lets us read them. Mid-fight
-- they may be hidden; the last values read are kept. Level -1 means the
-- enemy is far above you ("??").
function Foes.Note(unit, full)
    local i = Foes.info[full]
    if not i then i = {} Foes.info[full] = i end
    local lv = Foes.Safe(UnitLevel, unit)
    if type(lv) == "number" and lv ~= 0 then i.lv = lv end
    local ok, race = pcall(UnitRace, unit)
    if ok and type(race) == "string" and not Secret(race) then i.ra = race end
    local gok, guild = pcall(GetGuildInfo, unit)
    if gok and type(guild) == "string" and not Secret(guild) and guild ~= "" then i.gu = guild end
end

-- "60 Human Mage", "?? Orc Rogue", "Mage" (whatever is known), plus " <Guild>" when asked.
function Foes.Describe(lv, ra, classToken, gu)
    local parts = {}
    if lv then parts[#parts + 1] = lv == -1 and "??" or tostring(lv) end
    if ra then parts[#parts + 1] = ra end
    if classToken then parts[#parts + 1] = ns.ClassName(classToken) end
    local text = table.concat(parts, " ")
    if gu then text = text .. (text ~= "" and " " or "") .. "<" .. gu .. ">" end
    return text
end

-- full, short, class, hostile (true, false, or nil when hidden).
-- Players seen as hostile while the game still said so are remembered, so
-- they are recognised in combat too.
function Foes.Read(unit)
    if not Foes.Safe(UnitExists, unit) then return end
    if Foes.Safe(UnitIsPlayer, unit) == false then return end
    local full, short = FullName(unit)
    if not full or short == myName then return end
    local class
    local ok, _, c = pcall(UnitClass, unit)
    if ok and type(c) == "string" and not Secret(c) then class = c end
    Foes.Note(unit, full)
    local hostile = Foes.Safe(UnitCanAttack, "player", unit)
    if hostile == true then
        Foes.known[full] = class or Foes.known[full] or true
    elseif hostile == nil and Foes.known[full] then
        hostile = true
    end
    if not class and type(Foes.known[full]) == "string" then class = Foes.known[full] end
    -- who's around, for "Outnumbered"
    if hostile == true then Foes.near[full] = GetTime()
    elseif hostile == false then Foes.allies[full] = GetTime() end
    return full, short, class, hostile
end

-- Keep track of the last hostile player you had targeted, as a fallback for
-- naming a kill when the game hides your target at that moment.
-- Is a non-group player showing a nameplate right now? Used at the moment
-- you die, when the game may already be hiding who attacked you.
function Foes.PlayerNearby()
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return false end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit and Foes.Safe(UnitIsPlayer, unit) and not Foes.Safe(UnitInParty, unit)
            and not Foes.Safe(UnitInRaid, unit) then
            local _, _, _, hostile = Foes.Read(unit)
            if hostile ~= false then return true end
        end
    end
    return false
end

function Foes.Track()
    local full, short, class, hostile = Foes.Read("target")
    if full and hostile == true and Foes.Safe(UnitIsDeadOrGhost, "target") ~= true then
        Foes.last = { full = full, short = short, class = class, at = GetTime() }
    end
end

local function Victim()
    local full, short, class, hostile = Foes.Read("target")
    if full and hostile ~= false then
        if Foes.Safe(UnitIsDeadOrGhost, "target") ~= false then
            Foes.miss = nil
            return full, short, class
        end
        Foes.miss = "your target was still alive"
    elseif full then
        Foes.miss = "your target was friendly"
    elseif Foes.Safe(UnitExists, "target") then
        Foes.miss = "the game hid your target's name"
    else
        Foes.miss = "you had no target"
    end
    local last = Foes.last
    if last and GetTime() - last.at <= 15 and last.full ~= full then
        Foes.miss = nil
        return last.full, last.short, last.class
    end
end

-- An enemy player seen dead (nameplate, target, mouseover): a second name
-- for a burst of kill credit. Kept 30 seconds.
function Foes.SawDead(unit)
    if Foes.Safe(UnitIsDeadOrGhost, unit) ~= true then return end
    local full, short, class, hostile = Foes.Read(unit)
    if not full or hostile ~= true then return end
    if not Foes.dying[full] then Foes.dying[full] = { short = short, class = class, at = GetTime() } end
end

-- Look over the nameplates for enemies who just died. Cheap; runs twice a
-- second while you're fighting.
function Foes.ScanDead()
    local now = GetTime()
    for full, d in pairs(Foes.dying) do if now - d.at > 30 then Foes.dying[full] = nil end end
    for full, t in pairs(Foes.near) do if now - t > 60 then Foes.near[full] = nil end end
    for full, t in pairs(Foes.allies) do if now - t > 60 then Foes.allies[full] = nil end end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            Foes.SawDead(unit)
            Foes.NoteAttacker(unit)
        end
    end
end

---------------------------------------------------------------------------
-- What killed you outside PvP (3.8.5, for the Ledger's Wilds). Forever
-- closes the combat log to addons, so the cause is read from the client's
-- state at the death: a fall, the breath or fatigue timer, or the hostile
-- creature you fought in the last 10 seconds (your target, or one that had
-- you targeted). Lava, fire and spells can't be told apart: no cause.
---------------------------------------------------------------------------

Foes.creature = nil  -- { name, kind, at }: the last hostile creature you fought
Foes.fellAt = -1000  -- the last time you were seen falling
Foes.mirror = {}     -- "BREATH" / "EXHAUSTION" -> { ends, stopped }

-- unit is a hostile creature (never a player, never one the game hides): note it.
function Foes.NoteCreature(unit)
    local Safe = Foes.Safe
    if Safe(UnitExists, unit) ~= true or Safe(UnitIsPlayer, unit) ~= false then return end
    if Safe(UnitCanAttack, "player", unit) ~= true or Safe(UnitIsDeadOrGhost, unit) == true then return end
    local name = Safe(UnitName, unit)
    if type(name) ~= "string" or name == "" then return end
    local kind = UnitCreatureType and Safe(UnitCreatureType, unit)
    Foes.creature = { name = name, kind = type(kind) == "string" and kind ~= "" and kind or nil, at = GetTime() }
end

-- A creature on a nameplate that has you targeted.
function Foes.NoteAttacker(unit)
    if Foes.Safe(UnitIsPlayer, unit) ~= false then return end
    if Foes.Safe(UnitIsUnit, unit .. "target", "player") == true then Foes.NoteCreature(unit) end
end

function Foes.NoteFalling()
    if IsFalling and Foes.Safe(IsFalling) == true then Foes.fellAt = GetTime() end
end

-- MIRROR_TIMER_START (name, value in ms, max, scale: -1 counts down) and _STOP (name).
function Foes.OnMirror(event, name, value, _, scale)
    if type(name) ~= "string" or Secret(name) then return end
    if event == "MIRROR_TIMER_START" then
        local ends
        if type(value) == "number" and type(scale) == "number" and scale < 0 then
            ends = GetTime() + value / 1000 / -scale
        end
        Foes.mirror[name] = { ends = ends }
    elseif Foes.mirror[name] then
        Foes.mirror[name].stopped = GetTime()
    end
end

-- At a death outside PvP: cause (a creature's name or nil), how ("fall",
-- "drown", "fatigue", "beast" for any creature), the creature's type. A
-- timer that ran out comes first; one still running counts only when no
-- creature explains the death (a murloc kills you underwater, not the water).
function Foes.Cause()
    local now = GetTime()
    Foes.NoteFalling()
    if now - Foes.fellAt <= 1 then return nil, "fall" end
    local running
    for _, name in ipairs({ "BREATH", "EXHAUSTION" }) do
        local t = Foes.mirror[name]
        if t and (not t.stopped or now - t.stopped <= 2) then
            local how = name == "BREATH" and "drown" or "fatigue"
            if t.ends and now >= t.ends - 1 then return nil, how end
            running = running or how
        end
    end
    Foes.NoteCreature("target")
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
        for _, plate in ipairs(plates) do
            local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
            if unit then Foes.NoteAttacker(unit) end
        end
    end
    local c = Foes.creature
    if c and now - c.at <= 10 then return c.name, "beast", c.kind end
    if running then return nil, running end
end

-- Who a kill credit was for: your dead target, the last enemy you targeted
-- (15 s), or an enemy seen dying in the last 5 seconds. Names counted in
-- the last 10 seconds (skip) are passed over. full, short, class, source.
function Foes.Pick(skip)
    local full, short, class = Victim()
    if full and not skip(full) then return full, short, class, Foes.miss == nil and "target" end
    local best
    for f, d in pairs(Foes.dying) do
        if GetTime() - d.at <= 5 and not skip(f) and (not best or d.at > best.at) then
            best = { full = f, short = d.short, class = d.class, at = d.at }
        end
    end
    if best then return best.full, best.short, best.class, "seen dying" end
end

-- The game's honorable-kill count this session, or nil when the client won't say.
function Foes.ReadHK()
    if not GetPVPSessionStats then return end
    local ok, hk = pcall(GetPVPSessionStats)
    if ok and type(hk) == "number" and not Secret(hk) then return hk end
end

function Foes.Log(text, before, after)
    local log = Foes.log
    log[#log + 1] = { t = time(), text = text, before = before, after = after }
    while #log > 30 do table.remove(log, 1) end
end

-- Shared with the other files.
ns.Foes = Foes
ns.Victim = Victim
