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
    win = { till = 0, names = {}, unnamed = false }, -- the current burst of kill credit
    counted = {},                                    -- victim -> when their kill was counted
    credits = 0, kills = 0,                          -- raw credits vs kills counted, this session
    dead = false }                                   -- dead now; PLAYER_DEAD can repeat

function Foes.Safe(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok and not Secret(v) then return v end
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
    local hostile = Foes.Safe(UnitCanAttack, "player", unit)
    if hostile == true then
        Foes.known[full] = class or Foes.known[full] or true
    elseif hostile == nil and Foes.known[full] then
        hostile = true
    end
    if not class and type(Foes.known[full]) == "string" then class = Foes.known[full] end
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

-- Shared with the other files.
ns.Foes = Foes
ns.Victim = Victim
