-- Warpath 3.3.5
-- Your war, inked on the map.
--
-- Map layers (toggle each with /warpath layer <name>):
--   The map has two memories, both kept on the same grid of ground:
--
--   On the map, today's trail is footsteps; a route used on two separate
--   days becomes a silver road, and one you keep coming back to (about three
--   days of use) becomes gold.
--
--   Long memory  builds one mark per DAY you use a piece of ground, and loses
--                half its strength every 14 days. Thirty laps of a farming
--                loop on one afternoon is one mark; the road you ride every
--                evening gains a mark a day. Nothing is permanent.
--     heat       places you linger (20+ seconds in one spot), in a soft haze.
--     roads      stretches you travel THROUGH, etched in gold once they reach
--                about three days of use. Milling around a quest hub is not
--                travel and never etches.
--   Short memory builds with every pass and loses half its strength every
--                3 hours, so it is today's log and is gone by tomorrow.
--     recent     today's ground in your faction's colour, brighter where you
--                repeat it, plus a crisp line for the last 20 minutes.
--
--   /warpath memory <hours> <days> changes the two half-lives.
--   /warpath roads <days> changes how much use etches a road.
--
--   marks      skulls where you died, blades where you scored honorable kills.
--   sightings  where you have seen hostile players, in their colour, plus a
--              crest for each sighting in the last 15 minutes.
--   shared     sightings and deaths sent by guild and party members who also
--              run Warpath (opt in with /warpath share).
--
-- Things the game does not let an addon know, and what Warpath does instead:
--   * What killed you. A death counts as PvP only if you saw a hostile player
--     in the 20 seconds before it; other deaths get a grey skull and count
--     for nothing.
--   * Where an enemy is. A sighting is recorded at YOUR position.
--   * Who you killed. The victim is read from your target if it is the dead
--     enemy; otherwise the kill is recorded without a name.
--
-- Kill shots (folded in from PvPKillShot): a screenshot on every honorable
-- kill in the open world, or only notable ones, with a small caption of who,
-- where and your streak. The blade on the map remembers which file it was.
--
-- A setup window opens once after each install or update (/warpath setup).
--
-- Other addons can hook kills:  Warpath.RegisterKillCallback(function(ctx) end)
--   ctx = { mapID, zone, x, y, time, streak, victim, victimFull, timesKilled }

local ADDON = ...
local GOLD = "|cffffd100"
local PREFIX = GOLD .. "Warpath|r: "
local COMM = "WARPATH"
local PROTO = "1"

local SAMPLE_INTERVAL = 0.5
local MIN_STEP        = 0.003   -- map units; ignore smaller moves
local JUMP_STEP       = 0.08    -- map units; bigger = teleport, break the stroke
local STROKE_MAX      = 300     -- points per stroke
local SIMPLIFY_TOL    = 0.0015  -- map units; trail simplification tolerance
local KEEP_HOURS      = 24      -- trail history kept (replay window)
local GW, GH          = 96, 64  -- travel heat grid
local SW, SH          = 48, 32  -- sighting heat grid
local ROAD_COOLDOWN   = 300     -- seconds before the same stretch counts another pass
local DWELL_SAMPLES   = 40      -- samples (20 s) in one cell = lingering there
local HIST            = 60      -- samples (30 s) of position history
local TRAVEL_CELLS    = 3       -- net cells moved in that time = travelling
local FRESH_SECONDS   = 120     -- the solid line covers the last two minutes
local RUN_SECONDS     = 1200    -- corpse runs and flights stay as lines for 20 minutes
local STEP_FADE       = 1800    -- footsteps fade from bright to faint over 30 minutes
local STEP_FLOOR      = 0.18    -- ...then hold this faint until today's memory expires
local RECENT_CAP      = 30      -- short memory saturates here
local RECENT_MIN      = 0.2     -- short memory below this is not drawn
local HEAT_MIN        = 1.5     -- long-memory strength before heat shows
local HEAT_FULL       = 10
local ROAD_FULL       = 12
local LN2             = math.log(2)
local SILVER_SHARE    = 0.6     -- silver appears at this share of the gold threshold
local STEP_BUDGET     = 4000
local SHOT_THROTTLE   = 1.5     -- one screenshot per burst of kills
local COMBAT_GRACE    = 3       -- seconds after combat that a kill still counts as yours
local MARK_CAP        = 300
local LINE_BUDGET     = 5000
local DOT_BUDGET      = 3500
local MARK_BUDGET     = 400
local CELL            = 0.04    -- killing-field grid size
local FIELD_DAYS      = 30
local FIELD_RADIUS    = 0.03
local FIELD_COOLDOWN  = 600
local PVP_WINDOW      = 20      -- hostile player seen this recently = PvP death
local SIGHT_DEDUPE    = 120     -- one sighting per player per this many seconds
local SIGHT_LIVE      = 900     -- recent sightings shown as crests
local SHARED_DEATH    = 7200    -- shared deaths shown this long
local AVENGE_WINDOW   = 300
local AVENGE_RADIUS   = 0.10
local GRUDGE_COOLDOWN = 60
local REPLAY_SECONDS  = 20
local DAY             = 86400

local TEX_SKULL  = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local TEX_BLADES = "Interface\\CURSOR\\Attack"
local TEX_GLOW   = "Interface\\Cooldown\\star4"
local TEX_STEP   = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"  -- solid round dot
local TEX_DOT    = "Interface\\AddOns\\" .. ADDON .. "\\glow"  -- soft radial glow shipped with the addon

local FACTION = {
    Horde    = { r = 1.00, g = 0.16, b = 0.10, cry = "Lok'tar ogar!",     crest = "Interface\\TargetingFrame\\UI-PVP-Horde",    foe = "Alliance" },
    Alliance = { r = 0.25, g = 0.55, b = 1.00, cry = "For the Alliance!", crest = "Interface\\TargetingFrame\\UI-PVP-Alliance", foe = "Horde" },
    Neutral  = { r = 1.00, g = 0.82, b = 0.00, cry = "Victory!",          crest = "Interface\\TargetingFrame\\UI-PVP-FFA",      foe = "Neutral" },
}
local LAYERS = { "heat", "roads", "recent", "marks", "sightings", "shared" }

local db, gdb, cfg, faction, foe, myName, myFull
local CFG_DEFAULTS = { sound = true, hudShown = true, quiet = false, share = false }
local SHOT_DEFAULTS = { on = true, mode = "all", card = "text", delay = 0.5, combat = true }
local overlay, head
local lines, dots, glows, pins, labels, steps = {}, {}, {}, {}, {}, {}
local cur = { map = nil, stroke = nil, mode = nil, x = nil, y = nil, wx = nil, wy = nil, cell = nil }
local session = { kills = 0, deaths = 0, streak = 0, best = 0, start = 0, yards = 0, sightings = 0, avenged = 0, zones = {} }
local roadSeen, fieldCache, fieldWarned, zoneWarned = {}, {}, {}, {}
local hist = {}
local sightSeen, grudgeWarned, shareSeen, senderSeen = {}, {}, {}, {}
local recentSight, shared, outQ = {}, {}, {}
local killCallbacks = {}
local replay = { active = false }
local lastHostile, pendingAvenge = -1000, nil
local lastCombatEnd, lastShot, shotPending = -1000, -1000, nil
local setupWaiting = false
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "3.3.0"
local inInstance, ready, dirty, lastDraw, tick = false, false, false, 0, 0
local hud, UpdateHUD

local function Print(msg) print(PREFIX .. msg) end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Q(v) return math.floor(v * 10000 + 0.5) / 10000 end

local function MapName(id)
    local info = C_Map.GetMapInfo(id)
    return info and info.name or ("map " .. id)
end

local function Sound(name, fallback)
    if not cfg.sound or cfg.quiet or inInstance then return end
    local id = (SOUNDKIT and SOUNDKIT[name]) or fallback
    if id then pcall(PlaySound, id, "Master") end
end

-- A banner, or a chat line in quiet mode.
local function Notice(text, r, g, b)
    if inInstance then return end
    if cfg.quiet then
        Print(text)
    elseif RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, { r = r, g = g, b = b })
    else
        UIErrorsFrame:AddMessage(text, r, g, b)
    end
end

local function WorldXY(mapID, x, y)
    local ok, _, wp = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and wp then return wp:GetXY() end
end

local function PlayerPos()
    if inInstance then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or Secret(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or Secret(x) or Secret(y) or (x == 0 and y == 0) then return end
    return mapID, x, y
end

local function Clamp01(v) return v < 0 and 0 or (v > 0.9999 and 0.9999 or v) end
local function Cell(x, y, gw, gh) return math.floor(Clamp01(y) * gh) * gw + math.floor(Clamp01(x) * gw) end
local function CellXY(c, gw, gh) return (c % gw + 0.5) / gw, (math.floor(c / gw) + 0.5) / gh end

local function Ago(t)
    local s = math.max(0, time() - t)
    if s < 90 then return s .. " sec ago" end
    if s < 5400 then return math.floor(s / 60 + 0.5) .. " min ago" end
    if s < 2 * DAY then return math.floor(s / 3600 + 0.5) .. " hr ago" end
    return date("%b %d", t)
end

local function Waypoint(mapID, x, y, label)
    if not (C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(mapID)) then
        Print("can't place a waypoint on that map.")
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    Print(("waypoint set: %s, %s (%.1f, %.1f)."):format(label, MapName(mapID), x * 100, y * 100))
end

-- "Name-Realm" and "Name" for a unit, or nil if hidden.
local function FullName(unit)
    local ok, full, short = pcall(function()
        local n, r = UnitFullName(unit)
        if not n or Secret(n) or Secret(r) then return end
        if not r or r == "" then r = GetNormalizedRealmName() or "" end
        return n .. "-" .. r, n
    end)
    if ok then return full, short end
end

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

---------------------------------------------------------------------------
-- Zone data
---------------------------------------------------------------------------

local function ZoneData(mapID)
    local z = db.maps[mapID]
    if not z then
        z = { strokes = {}, marks = {}, heat = {}, road = {}, cx = {}, cy = {}, sight = {}, hours = {},
            yards = 0, kills = 0, pdeaths = 0 }
        db.maps[mapID] = z
    end
    return z
end

-- Douglas-Peucker on a flat {x1,y1,x2,y2,...} stroke, in place.
local function Simplify(s)
    local n = #s / 2
    if n < 3 then return end
    local keep = { [1] = true, [n] = true }
    local stack = { 1, n }
    while #stack > 0 do
        local b = table.remove(stack)
        local a = table.remove(stack)
        local ax, ay, bx, by = s[2 * a - 1], s[2 * a], s[2 * b - 1], s[2 * b]
        local dx, dy = bx - ax, by - ay
        local len2 = dx * dx + dy * dy
        local worst, wi = 0, nil
        for i = a + 1, b - 1 do
            local px, py = s[2 * i - 1] - ax, s[2 * i] - ay
            local d
            if len2 == 0 then
                d = px * px + py * py
            else
                local cross = px * dy - py * dx
                d = cross * cross / len2
            end
            if d > worst then worst, wi = d, i end
        end
        if wi and worst > SIMPLIFY_TOL * SIMPLIFY_TOL then
            keep[wi] = true
            stack[#stack + 1] = a; stack[#stack + 1] = wi
            stack[#stack + 1] = wi; stack[#stack + 1] = b
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = s[2 * i - 1]
            out[#out + 1] = s[2 * i]
        end
    end
    for i = #s, 1, -1 do s[i] = nil end
    for i = 1, #out do s[i] = out[i] end
end

-- Current strength of a record's long and short memory.
local function Long(e, now)
    if not e.l or e.l <= 0 then return 0 end
    return e.l * math.exp(-LN2 * (now - e.tl) / (db.longDays * DAY))
end
-- Footstep look by time since you last walked there: bright and a little
-- larger at first, easing down to a faint floor over 30 minutes.
local function StepLook(e, now)
    local age = now - (e.tp or e.tr or now)
    if age >= STEP_FADE then return STEP_FLOOR, 0.8 end
    local k = 0.5 * (1 + math.cos(math.pi * age / STEP_FADE))
    return STEP_FLOOR + (0.95 - STEP_FLOOR) * k, 0.8 + 0.45 * k
end

local function Recent(e, now)
    if not e.r or e.r <= 0 then return 0 end
    return e.r * math.exp(-LN2 * (now - e.tr) / (db.recentHours * 3600))
end

-- One mark per calendar day, on top of whatever has not yet faded.
local function Credit(e, now, today)
    if e.d == today then return end
    e.l, e.tl, e.d = Long(e, now) + 1, now, today
end

local function Prune()
    local now = time()
    local cutoff = now - KEEP_HOURS * 3600
    for _, z in pairs(db.maps) do
        local kept = {}
        for _, s in ipairs(z.strokes) do
            if s.e >= cutoff then kept[#kept + 1] = s end
        end
        z.strokes = kept
        while #z.marks > MARK_CAP do table.remove(z.marks, 1) end
        for edge, e in pairs(z.road) do
            if Long(e, now) < 0.05 and Recent(e, now) < 0.05 then z.road[edge] = nil end
        end
        for c, e in pairs(z.heat) do
            if Long(e, now) < 0.05 then z.heat[c] = nil end
        end
    end
    for i = #shared, 1, -1 do
        if shared[i].expire < now then table.remove(shared, i) end
    end
    for i = #recentSight, 1, -1 do
        if now - recentSight[i].t > SIGHT_LIVE then table.remove(recentSight, i) end
    end
    if cur.map and db.maps[cur.map] then
        local z, found = db.maps[cur.map], false
        for _, s in ipairs(z.strokes) do
            if s == cur.stroke then found = true break end
        end
        if not found then cur.stroke = nil end
    end
end

-- v1/v2 kept every point forever. Fold those into the heat grid.
local function Migrate()
    if db.v == 4 then return end
    if db.v == 3 then
        -- 3.0/3.1 stored raw counts. Convert to the two-memory records.
        local now, today = time(), tonumber(date("%y%j"))
        for _, z in pairs(db.maps) do
            z.road, z.cx, z.cy = z.road or {}, z.cx or {}, z.cy or {}
            for c, v in pairs(z.heat) do
                if type(v) == "number" then z.heat[c] = { l = 1, tl = now, d = today } end
            end
            for edge, n in pairs(z.road) do
                if type(n) == "number" then
                    z.road[edge] = { l = 1, tl = now, d = today, r = math.min(n, 5), tr = now }
                end
            end
        end
        if db.layers then db.layers.trail = nil end
        db.roadMin = nil
        db.v = 4
        return
    end
    for _, z in pairs(db.maps) do
        z.heat, z.sight, z.hours = z.heat or {}, z.sight or {}, z.hours or {}
        z.kills, z.pdeaths, z.yards = z.kills or 0, z.pdeaths or 0, z.yards or 0
        z.points = nil
        for _, s in ipairs(z.strokes or {}) do
            s.e = s.e or s.t
            local last
            if s.k ~= "f" and s.k ~= "g" then
                for i = 1, #s - 1, 2 do
                    local c = Cell(s[i], s[i + 1], GW, GH)
                    if c ~= last then z.heat[c] = { l = 1, tl = time(), d = 0 } last = c end
                end
            end
            Simplify(s)
        end
        z.strokes = z.strokes or {}
        for _, m in ipairs(z.marks or {}) do
            if m[5] then m.n, m[5] = m[5], nil end
            if m[6] then m.c, m[6] = m[6], nil end
            if m[4] == "death" then m.pvp = true z.pdeaths = z.pdeaths + 1 else z.kills = z.kills + 1 end
        end
        z.marks = z.marks or {}
        z.road, z.cx, z.cy = z.road or {}, z.cx or {}, z.cy or {}
    end
    db.v = 4
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Mode()
    if UnitIsGhost("player") then return "g" end
    if UnitOnTaxi("player") then return "f" end
end

local function NewStroke(mapID, x, y, mode)
    if cur.stroke then Simplify(cur.stroke) end
    local z = ZoneData(mapID)
    local now = time()
    local s = { t = now, e = now, k = mode, Q(x), Q(y) }
    z.strokes[#z.strokes + 1] = s
    cur.map, cur.stroke, cur.mode, cur.x, cur.y = mapID, s, mode, x, y
    cur.wx, cur.wy = WorldXY(mapID, x, y)
    session.zones[mapID] = true
    dirty = true
end

-- Are you going somewhere, or milling about? Compares where you are with
-- where you were up to 30 seconds ago.
local function Travelling(mapID, x, y)
    local n = #hist
    if hist.map ~= mapID or (n > 0 and (math.abs(x - hist[n - 1]) > JUMP_STEP or math.abs(y - hist[n]) > JUMP_STEP)) then
        hist = { map = mapID }
    end
    hist[#hist + 1] = x
    hist[#hist + 1] = y
    if #hist > HIST * 2 then
        table.remove(hist, 1)
        table.remove(hist, 1)
    end
    n = #hist / 2
    if n < 20 then return false end
    local dx, dy = (x - hist[1]) * GW, (y - hist[2]) * GH -- in cells
    local need = TRAVEL_CELLS * n / HIST
    return dx * dx + dy * dy >= need * need
end

-- Feed both memories. See the header for what each one counts.
local function Visit(mapID, x, y, mode)
    if mode then -- flights and corpse runs are not choices
        cur.cell, cur.rc, cur.dwell = nil, nil, 0
        hist = {}
        return
    end
    local travelling = Travelling(mapID, x, y)
    local c = Cell(x, y, GW, GH)
    local z = ZoneData(mapID)
    local ox, oy = z.cx[c], z.cy[c]
    z.cx[c] = ox and Q(ox + (x - ox) * 0.2) or Q(x)
    z.cy[c] = oy and Q(oy + (y - oy) * 0.2) or Q(y)
    local now, today = time(), tonumber(date("%y%j"))

    local key = mapID * 10000 + c
    if key == cur.cell then
        -- Lingering: 20 seconds in one cell marks it as a haunt for today.
        cur.dwell = (cur.dwell or 0) + 1
        if cur.dwell == DWELL_SAMPLES then
            local e = z.heat[c]
            if not e then e = { l = 0, tl = now } z.heat[c] = e end
            Credit(e, now, today)
            dirty = true
        end
        return
    end

    local prev = cur.rc
    if prev and cur.cell and math.floor(cur.cell / 10000) == mapID then
        local dx = math.abs(prev % GW - c % GW)
        local dy = math.abs(math.floor(prev / GW) - math.floor(c / GW))
        if dx <= 2 and dy <= 2 then
            local edge = math.min(prev, c) * 10000 + math.max(prev, c)
            local e = z.road[edge]
            if not e then e = { l = 0, tl = now, r = 0, tr = now } z.road[edge] = e end
            local seenKey = mapID .. ":" .. edge
            local clock = GetTime()
            if not roadSeen[seenKey] or clock - roadSeen[seenKey] >= ROAD_COOLDOWN then
                roadSeen[seenKey] = clock
                e.r, e.tr = math.min(RECENT_CAP, Recent(e, now) + 1), now
            end
            e.tp = now
            if travelling then Credit(e, now, today) end
            dirty = true
        end
    end
    cur.cell, cur.rc, cur.dwell = key, c, 0
end

local function Sample()
    local mapID, x, y = PlayerPos()
    if not mapID then
        if cur.stroke then Simplify(cur.stroke) end
        cur.stroke = nil
        return
    end
    local mode = Mode()
    Visit(mapID, x, y, mode)

    if mapID ~= cur.map or not cur.stroke then return NewStroke(mapID, x, y, mode) end

    local dx, dy = x - cur.x, y - cur.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > JUMP_STEP then return NewStroke(mapID, x, y, mode) end
    if mode ~= cur.mode then return NewStroke(mapID, cur.x, cur.y, mode) end
    if d < MIN_STEP then return end

    local z = ZoneData(mapID)
    local wx, wy = WorldXY(mapID, x, y)
    if wx and cur.wx then
        local yards = math.sqrt((wx - cur.wx) ^ 2 + (wy - cur.wy) ^ 2)
        if yards < 500 then
            z.yards = z.yards + yards
            db.yards = db.yards + yards
            session.yards = session.yards + yards
        end
    end

    if #cur.stroke >= STROKE_MAX * 2 then NewStroke(mapID, cur.x, cur.y, mode) end
    local s = cur.stroke
    s[#s + 1] = Q(x)
    s[#s + 1] = Q(y)
    s.e = time()
    cur.x, cur.y, cur.wx, cur.wy = x, y, wx, wy
    dirty = true
end

---------------------------------------------------------------------------
-- Sharing (opt in). Sends only: an enemy was seen here / I died to PvP here.
-- Never your trail, never anyone's name.
---------------------------------------------------------------------------

local shareStats = { sent = 0, refused = 0, got = 0, lastRefusal = nil }

local function Share(kind, mapID, x, y, force)
    if not cfg.share then return end
    if not force then
        local key = kind .. mapID .. ":" .. Cell(x, y, SW, SH)
        local now = GetTime()
        if shareSeen[key] and now - shareSeen[key] < 60 then return end
        shareSeen[key] = now
    end
    local msg = ("%s|%s|%d|%.4f|%.4f"):format(PROTO, kind, mapID, x, y)
    if kind == "S" then
        if #outQ < 10 then outQ[#outQ + 1] = msg end
    else
        table.insert(outQ, 1, msg) -- kills, deaths and test pings go first
        if #outQ > 12 then table.remove(outQ) end
    end
end

-- C_ChatInfo.SendAddonMessage returns true/false on older clients and a
-- result code (0 = success) on newer ones.
local function SendOne(msg, channel)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, COMM, msg, channel)
    if ok and (res == nil or res == true or res == 0) then
        shareStats.sent = shareStats.sent + 1
    else
        shareStats.refused = shareStats.refused + 1
        shareStats.lastRefusal = channel .. ": " .. tostring(ok and res or "error")
    end
end

local function FlushShare()
    if not cfg.share or #outQ == 0 or inInstance then return end
    local msg = table.remove(outQ, 1)
    if IsInGuild() then SendOne(msg, "GUILD") end
    if IsInRaid() then
        SendOne(msg, "RAID")
    elseif IsInGroup() then
        SendOne(msg, "PARTY")
    end
end

local function OnComm(prefix, text, _, sender)
    if prefix ~= COMM or not cfg.share or inInstance then return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if sender == myFull or Ambiguate(sender, "short") == myName then return end
    local now = GetTime()
    if senderSeen[sender] and now - senderSeen[sender] < 3 then return end -- per-sender rate limit
    senderSeen[sender] = now

    local sep = text:find(";", 1, true) and ";" or "|" -- 3.3.0 used "|"
    local ver, kind, mapID, x, y = strsplit(sep, text)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if ver ~= PROTO or (kind ~= "S" and kind ~= "D" and kind ~= "K" and kind ~= "T") then return end
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if not C_Map.GetMapInfo(mapID) then return end
    shareStats.got = shareStats.got + 1
    local from = Ambiguate(sender, "short")

    if kind == "T" then -- a test ping: always announced, shown for two minutes
        shared[#shared + 1] = { kind = "S", mapID = mapID, x = x, y = y, t = time(), from = from, expire = time() + 120 }
        dirty = true
        Print(("test ping from %s in %s received. Sharing works."):format(from, MapName(mapID)))
        return
    end

    if #shared >= 200 then table.remove(shared, 1) end
    shared[#shared + 1] = {
        kind = kind, mapID = mapID, x = x, y = y, t = time(), from = from,
        expire = time() + (kind == "S" and SIGHT_LIVE or SHARED_DEATH),
    }
    dirty = true
    -- Kills and deaths get a chat line in your zone; sightings are map-only.
    if kind ~= "S" and mapID == C_Map.GetBestMapForUnit("player") then
        Print(("%s %s in %s."):format(from, kind == "K" and "scored a kill" or "was killed", MapName(mapID)))
    end
end

local function See(unit)
    if inInstance or not ready then return end
    if Foes.Safe(UnitIsDeadOrGhost, unit) == true then return end
    local full, short, _, hostile = Foes.Read(unit)
    local now = GetTime()
    if hostile == nil and Foes.Safe(UnitIsPlayer, unit) and not UnitInParty(unit) and not UnitInRaid(unit) then
        -- The game won't say whether this player is hostile. For "did a
        -- player kill me?" treat a stranger in combat as a probable enemy,
        -- but don't record a sighting on a guess.
        if UnitAffectingCombat("player") then lastHostile = now end
        return
    end
    if hostile ~= true then return end
    lastHostile = now
    if not full then return end

    if gdb.kos[full] and (not grudgeWarned[full] or now - grudgeWarned[full] > GRUDGE_COOLDOWN) then
        grudgeWarned[full] = now
        Notice("Grudge sighted: " .. short, 1, 0.5, 0)
        Sound("READY_CHECK", 8960)
    end

    if sightSeen[full] and now - sightSeen[full] < SIGHT_DEDUPE then return end
    sightSeen[full] = now
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local c = Cell(x, y, SW, SH)
    z.sight[c] = (z.sight[c] or 0) + 1
    local hour = tonumber(date("%H"))
    z.hours[hour] = (z.hours[hour] or 0) + 1
    session.sightings = session.sightings + 1
    if #recentSight >= 100 then table.remove(recentSight, 1) end
    recentSight[#recentSight + 1] = { mapID = mapID, x = x, y = y, t = time() }
    Share("S", mapID, x, y)
    dirty = true
end

local function ToggleGrudge(arg)
    local full, short
    if arg and arg ~= "" then
        full = arg:find("-", 1, true) and arg or (arg .. "-" .. (GetNormalizedRealmName() or ""))
        short = arg
    else
        if not UnitExists("target") or not UnitIsPlayer("target") then
            Print("target a player, or use /warpath grudge Name-Realm.")
            return
        end
        full, short = FullName("target")
        if not full then Print("can't read that player's name right now.") return end
    end
    -- names typed by hand: match case-insensitively against existing entries
    for name in pairs(gdb.kos) do
        if name:lower() == full:lower() then
            gdb.kos[name] = nil
            Print("grudge against " .. name .. " settled.")
            return
        end
    end
    gdb.kos[full] = time()
    Print("you now hold a grudge against " .. GOLD .. full .. "|r. You'll be told when you see them.")
end

---------------------------------------------------------------------------
-- Killing fields: places you keep dying to players
---------------------------------------------------------------------------

local function Fields(mapID)
    local list = fieldCache[mapID]
    if list then return list end
    list = {}
    local z = db.maps[mapID]
    if z then
        local cells, cutoff = {}, time() - FIELD_DAYS * DAY
        for _, m in ipairs(z.marks) do
            if m[4] == "death" and m.pvp and m[3] >= cutoff then
                local key = math.floor(m[1] / CELL) * 1000 + math.floor(m[2] / CELL)
                local c = cells[key]
                if not c then c = { key = key, n = 0, x = 0, y = 0 } cells[key] = c end
                c.n, c.x, c.y = c.n + 1, c.x + m[1], c.y + m[2]
            end
        end
        for _, c in pairs(cells) do
            if c.n >= 2 then
                list[#list + 1] = { key = mapID .. ":" .. c.key, n = c.n, x = c.x / c.n, y = c.y / c.n }
            end
        end
    end
    fieldCache[mapID] = list
    return list
end

local function CheckFields()
    if UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local now = GetTime()
    for _, fld in ipairs(Fields(mapID)) do
        local dx, dy = x - fld.x, y - fld.y
        if dx * dx + dy * dy < FIELD_RADIUS * FIELD_RADIUS
            and (not fieldWarned[fld.key] or now - fieldWarned[fld.key] > FIELD_COOLDOWN) then
            fieldWarned[fld.key] = now
            Notice(("Killing field: you have died here %d times"):format(fld.n), 1, 0.25, 0.2)
            Sound("RAID_WARNING", 8959)
        end
    end
end

local function BusiestHours(z)
    local list = {}
    for h, n in pairs(z.hours) do list[#list + 1] = { h = h, n = n } end
    if #list == 0 then return end
    table.sort(list, function(a, b) return a.n > b.n end)
    local out = {}
    for i = 1, math.min(3, #list) do out[i] = ("%02d:00"):format(list[i].h) end
    return table.concat(out, ", ")
end

local function ZoneWarning()
    local mapID = C_Map.GetBestMapForUnit("player")
    if inInstance or not mapID or Secret(mapID) or zoneWarned[mapID] then return end
    zoneWarned[mapID] = true
    local z = db.maps[mapID]
    if not z then return end
    local n, cutoff = 0, time() - 7 * DAY
    for _, m in ipairs(z.marks) do
        if m[4] == "death" and m.pvp and m[3] >= cutoff then n = n + 1 end
    end
    if n > 0 then
        local hours = BusiestHours(z)
        Print(("%s: the enemy has killed you here |cffff4030%d|r time%s this week.%s")
            :format(MapName(mapID), n, n == 1 and "" or "s",
                hours and (" They are most active around " .. hours .. ".") or ""))
    end
end

---------------------------------------------------------------------------
-- Kills and deaths
---------------------------------------------------------------------------

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

local function AddMark(kind, extra)
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local m = { Q(x), Q(y), time(), kind }
    for k, v in pairs(extra or {}) do m[k] = v end
    z.marks[#z.marks + 1] = m
    if #z.marks > MARK_CAP then table.remove(z.marks, 1) end
    db[kind == "death" and "lastDeath" or "lastKill"] = { mapID, m[1], m[2], m[3] }
    dirty = true
    return m, mapID, z
end


---------------------------------------------------------------------------
-- Kill shots
---------------------------------------------------------------------------

local RecentlyInCombat, TakeKillShot, FinishShot, Notable
do
function RecentlyInCombat()
    if not cfg.shot.combat then return true end
    return UnitAffectingCombat("player") or (GetTime() - lastCombatEnd) <= COMBAT_GRACE
end

local function Ordinal(n)
    local tens, ones = n % 100, n % 10
    if tens >= 11 and tens <= 13 then return n .. "th" end
    return n .. (ones == 1 and "st" or ones == 2 and "nd" or ones == 3 and "rd" or "th")
end

local function ClassName(token)
    if not token then return end
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

local function ShotFile(t)
    local fmt = (GetCVar and GetCVar("screenshotFormat")) or "jpeg"
    local ext = (fmt == "png" or fmt == "tga") and fmt or "jpg"
    return "WoWScrnShot_" .. date("%m%d%y_%H%M%S", t) .. "." .. ext
end

-- k = { name, class, zone, times, streak, avenged (seconds), grudge, when }
local function CardTag(k, long)
    if k.avenged then
        return (long and "AVENGED IN %d SEC" or "AVENGED %ds"):format(k.avenged), 1, 0.82, 0
    elseif k.grudge then
        return "GRUDGE", 1, 0.62, 0.16
    end
    return long and "HONORABLE KILL" or "KILL", 0.79, 0.63, 0.23
end

local function CardDetails(k)
    local bits = {}
    if k.class then bits[#bits + 1] = ClassName(k.class) end
    if k.zone and k.zone ~= "" then bits[#bits + 1] = k.zone end
    if k.times then bits[#bits + 1] = Ordinal(k.times) .. " kill" end
    return bits
end

local function NameColor(k)
    local c = k.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[k.class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local cardText, cardStrip
local DOT = "  \194\183  "   -- middle dot
local TIMES = "\195\151"     -- multiplication sign

local function CardTop()
    return -math.floor(UIParent:GetHeight() * 0.165)
end

local function ShowTextCard(k)
    local f = cardText
    if not f then
        f = CreateFrame("Frame", "WarpathKillCardText", UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetSize(600, 60)
        f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.tag:SetPoint("TOP", 0, 0)
        f.name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        f.name:SetPoint("TOP", f.tag, "BOTTOM", 0, -2)
        f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.info:SetPoint("TOP", f.name, "BOTTOM", 0, -2)
        for _, fs in ipairs({ f.tag, f.name, f.info }) do
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 1)
        end
        cardText = f
    end
    local tag, r, g, b = CardTag(k, true)
    if k.streak and k.streak >= 2 then tag = tag .. DOT .. TIMES .. k.streak end
    f.tag:SetText(tag)
    f.tag:SetTextColor(r, g, b)
    f.name:SetText(k.name)
    f.name:SetTextColor(NameColor(k))
    local bits = CardDetails(k)
    bits[#bits + 1] = date("%b %d, %H:%M", k.when)
    f.info:SetText(table.concat(bits, DOT))
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, CardTop())
    f:Show()
    return f
end

local function ShowStripCard(k)
    local f = cardStrip
    if not f then
        f = CreateFrame("Frame", "WarpathKillCardStrip", UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetHeight(30)
        f.bg = f:CreateTexture(nil, "BACKGROUND")
        f.bg:SetAllPoints()
        f.bg:SetColorTexture(0.06, 0.04, 0.03, 0.72)
        f.top = f:CreateTexture(nil, "BORDER")
        f.top:SetPoint("TOPLEFT")
        f.top:SetPoint("TOPRIGHT")
        f.top:SetHeight(1)
        f.bottom = f:CreateTexture(nil, "BORDER")
        f.bottom:SetPoint("BOTTOMLEFT")
        f.bottom:SetPoint("BOTTOMRIGHT")
        f.bottom:SetHeight(1)
        f.crest = f:CreateTexture(nil, "ARTWORK")
        f.crest:SetSize(20, 20)
        f.crest:SetPoint("LEFT", 8, 0)
        f.crest:SetTexCoord(0, 0.62, 0, 0.62)
        f.tag = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.tag:SetPoint("LEFT", f.crest, "RIGHT", 6, 0)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.text:SetPoint("LEFT", f.tag, "RIGHT", 8, 0)
        cardStrip = f
    end
    local tag, r, g, b = CardTag(k, false)
    f.crest:SetTexture(faction.crest)
    f.tag:SetText(tag)
    f.tag:SetTextColor(r, g, b)
    f.top:SetColorTexture(r, g, b, 0.9)
    f.bottom:SetColorTexture(r, g, b, 0.9)
    local nr, ng, nb = NameColor(k)
    local parts = { ("|cff%02x%02x%02x%s|r"):format(nr * 255, ng * 255, nb * 255, k.name) }
    for _, bit in ipairs(CardDetails(k)) do parts[#parts + 1] = bit end
    if k.streak and k.streak >= 2 then parts[#parts + 1] = GOLD .. TIMES .. k.streak .. "|r" end
    parts[#parts + 1] = "|cffa8987a" .. date("%b %d, %H:%M", k.when) .. "|r"
    f.text:SetText(table.concat(parts, "  |cff6e5e44\194\183|r  "))
    f:SetWidth(8 + 20 + 6 + f.tag:GetStringWidth() + 8 + f.text:GetStringWidth() + 14)
    f:ClearAllPoints()
    f:SetPoint("TOP", UIParent, "TOP", 0, CardTop())
    f:Show()
    return f
end

local function HideCards()
    if cardText then cardText:Hide() end
    if cardStrip then cardStrip:Hide() end
end

-- Banners and sounds wait until the picture is taken, so they are not in it.
function FinishShot(ok)
    local p = shotPending
    if not p then return end
    shotPending = nil
    HideCards()
    if ok and not p.test then
        gdb.shotCount = gdb.shotCount + 1
        if p.mark then
            p.mark.shot = gdb.shotCount
            p.mark.file = ShotFile(p.at or time())
        end
    end
    if p.after then p.after() end
    C_Timer.After(0.5, function()
        if not ok then
            Print("the kill screenshot failed.")
        elseif p.test then
            Print("test screenshot taken.")
        else
            Print(("kill screenshot #%d saved."):format(gdb.shotCount))
        end
    end)
end

-- k: caption contents; mark: the kill's map mark; after: banner and sound for afterwards.
function TakeKillShot(k, mark, after, test)
    if shotPending then -- a shot is already in flight; this kill just gets its banner
        if after then after() end
        return
    end
    local token = { mark = mark, after = after, test = test }
    shotPending = token
    if cfg.shot.card == "text" then
        ShowTextCard(k)
    elseif cfg.shot.card == "strip" then
        ShowStripCard(k)
    end
    C_Timer.After(cfg.shot.delay, function()
        if shotPending ~= token then return end
        token.at = time()
        Screenshot()
    end)
    C_Timer.After(cfg.shot.delay + 3, function() -- never leave the caption up
        if shotPending == token then FinishShot(false) end
    end)
end

function Notable(k)
    return k.times == 1 or k.grudge or k.avenged or (k.times and k.times >= 5)
        or k.streak == 3 or k.streak == 5 or (k.streak and k.streak >= 10 and k.streak % 10 == 0)
end

end

local function OnKill()
    if inInstance then return end
    if not RecentlyInCombat() then return end -- a groupmate's kill while you stood by
    session.kills = session.kills + 1
    session.streak = session.streak + 1
    if session.streak > session.best then session.best = session.streak end
    db.kills = db.kills + 1
    if session.streak > db.bestStreak then db.bestStreak = session.streak end

    local full, short, class = Victim()
    local text = "Honorable kill"
    local times
    if full then
        db.victims[full] = (db.victims[full] or 0) + 1
        times = db.victims[full]
        text = text .. ": " .. short
        if times > 1 then text = text .. (" (%d times now)"):format(times) end
    end
    if session.streak >= 2 then text = text .. ("   x%d"):format(session.streak) end

    local m, mapID, z = AddMark("kill", { n = short, c = class, f = full })
    if z then z.kills = z.kills + 1 end
    if m then Share("K", mapID, m[1], m[2]) end

    -- Avenged: a kill near your own fresh skull.
    local avenged = false
    local p = pendingAvenge
    if p and m and mapID == p.mapID and GetTime() - p.at < AVENGE_WINDOW then
        local dx, dy = m[1] - p.mark[1], m[2] - p.mark[2]
        if dx * dx + dy * dy < AVENGE_RADIUS * AVENGE_RADIUS then
            p.mark.av = math.floor(GetTime() - p.at)
            pendingAvenge, avenged = nil, true
            session.avenged = session.avenged + 1
        end
    end

    local function Announce()
        if avenged then
            Notice("Avenged.  " .. text, 1, 0.82, 0)
            Sound("READY_CHECK", 8960)
        else
            Notice(text, faction.r, faction.g, faction.b)
            Sound("PVP_THROUGH_QUEUE", 8459)
        end
    end

    local k = {
        name = short or "Enemy player", class = class, zone = mapID and MapName(mapID) or "",
        times = times, streak = session.streak, when = time(),
        avenged = avenged and p.mark.av or nil,
        grudge = full and gdb.kos[full] and true or nil,
    }
    if cfg.shot.on and m and (cfg.shot.mode == "all" or Notable(k))
        and GetTime() - lastShot >= SHOT_THROTTLE then
        lastShot = GetTime()
        TakeKillShot(k, m, Announce)
    else
        Announce()
    end
    if session.streak == 3 or session.streak == 5 or session.streak % 10 == 0 then
        Print(("%s%s|r %d kills without dying."):format(GOLD, faction.cry, session.streak))
    end

    if m then
        local ctx = {
            mapID = mapID, zone = MapName(mapID), x = m[1], y = m[2], time = m[3],
            streak = session.streak, victim = short, victimFull = full, timesKilled = times,
        }
        for _, fn in ipairs(killCallbacks) do pcall(fn, ctx) end
    end
    UpdateHUD()
end

-- The game can hand out more than one honorable-kill credit for a single
-- enemy death. Credits that arrive within two seconds are one kill unless they
-- name a different dead enemy, and the same victim is never counted twice
-- within 10 seconds. Two enemies dying at once with only one of them targeted
-- counts as one kill: undercounting beats counting phantoms.
function Foes.OnCredit()
    Foes.credits = Foes.credits + 1
    if inInstance or not RecentlyInCombat() then return end
    local now = GetTime()
    local w = Foes.win
    if now > w.till then
        w.till, w.names, w.unnamed = now + 2, {}, false
    end
    local full = Victim()
    if full then
        if w.names[full] or w.unnamed then return end
        if Foes.counted[full] and now - Foes.counted[full] < 10 then return end
        w.names[full] = true
        Foes.counted[full] = now
    else
        if next(w.names) or w.unnamed then return end
        w.unnamed = true
    end
    Foes.kills = Foes.kills + 1
    OnKill()
end

local function OnDeath()
    if inInstance then return end
    local recentFoe = Foes.last and GetTime() - Foes.last.at < PVP_WINDOW
    local pvp = GetTime() - lastHostile < PVP_WINDOW or recentFoe or Foes.PlayerNearby()
    local m, mapID, z = AddMark("death", { pvp = pvp or nil })
    if pvp then
        session.deaths = session.deaths + 1
        db.deaths = db.deaths + 1
        if session.streak >= 3 then
            Print(("your streak ends at %s%d|r."):format(GOLD, session.streak))
        end
        session.streak = 0
        if m then
            z.pdeaths = z.pdeaths + 1
            fieldCache[mapID] = nil
            pendingAvenge = { mapID = mapID, mark = m, at = GetTime() }
            Share("D", mapID, m[1], m[2])
        end
    end
    UpdateHUD()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function Projection(mapID, viewed)
    if mapID == viewed then return 0, 1, 0, 1 end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, viewed)
    if not ok or not minX or not maxX or not minY or not maxY then return end
    if maxX - minX < 0.002 or maxY - minY < 0.002 then return end
    if minX < -0.5 or maxX > 1.5 or minY < -0.5 or maxY > 1.5 then return end
    return minX, maxX, minY, maxY
end

local function Proj(scene, mapID)
    local p = scene.proj[mapID]
    if p == nil then
        local minX, maxX, minY, maxY = Projection(mapID, scene.viewed)
        if minX then
            p = { ox = minX, oy = minY, sx = maxX - minX, sy = maxY - minY, mapID = mapID }
            p.far = p.sx < 0.25
        else
            p = false
        end
        scene.proj[mapID] = p
    end
    return p
end

-- since: only for replay; collects strokes after that time, oldest first.
local function BuildScene(viewed, since)
    local scene = { viewed = viewed, proj = {}, zones = {}, since = since }
    for mapID, z in pairs(db.maps) do
        local p = Proj(scene, mapID)
        if p then scene.zones[#scene.zones + 1] = { z = z, p = p } end
    end
    if since then
        scene.strokes, scene.points = {}, 0
        for _, e in ipairs(scene.zones) do
            for _, s in ipairs(e.z.strokes) do
                if s.e >= since then
                    scene.strokes[#scene.strokes + 1] = { s = s, p = e.p }
                    scene.points = scene.points + #s / 2
                end
            end
        end
        table.sort(scene.strokes, function(a, b) return a.s.t < b.s.t end)
    end
    return scene
end

local function GetLine(i)
    local l = lines[i]
    if not l then
        l = overlay:CreateLine(nil, "ARTWORK")
        l:SetBlendMode("ADD")
        lines[i] = l
    end
    return l
end

local function GetDot(i)
    local d = dots[i]
    if not d then
        d = overlay:CreateTexture(nil, "BACKGROUND")
        d:SetTexture(TEX_DOT)
        d:SetBlendMode("ADD")
        dots[i] = d
    end
    return d
end

local function GetStep(i)
    local d = steps[i]
    if not d then
        d = overlay:CreateTexture(nil, "ARTWORK", nil, 3)
        d:SetTexture(TEX_STEP)
        d:SetBlendMode("BLEND")
        steps[i] = d
    end
    return d
end

-- Roads draw in normal blend with their outline underneath; trails on top.
local function StyleLine(l, sub, blend)
    l:SetDrawLayer("ARTWORK", sub)
    l:SetBlendMode(blend or "BLEND")
end

local function GetGlow(i)
    local g = glows[i]
    if not g then
        g = overlay:CreateTexture(nil, "BORDER")
        g:SetTexture(TEX_GLOW)
        g:SetBlendMode("ADD")
        g:SetVertexColor(1, 0.12, 0.05)
        glows[i] = g
    end
    return g
end

local function PinEnter(self)
    local d = self.d
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.kind == "death" then
        if d.pvp then
            GameTooltip:AddLine("You fell here", 1, 0.25, 0.2)
            if d.av then
                GameTooltip:AddLine(("Avenged %d sec later (a kill nearby)"):format(d.av), 1, 0.82, 0)
            end
        else
            GameTooltip:AddLine("You died here", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("No enemy player seen; not counted", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(date("%b %d, %H:%M", d[3]), 0.8, 0.8, 0.8)
    elseif self.kind == "kill" then
        GameTooltip:AddLine("Honorable kill", 1, 0.82, 0)
        if d.n then
            local c = d.c and RAID_CLASS_COLORS and RAID_CLASS_COLORS[d.c]
            GameTooltip:AddLine(d.n, c and c.r or 1, c and c.g or 1, c and c.b or 1)
            local n = d.f and db.victims[d.f]
            if n and n > 1 then GameTooltip:AddLine(("Slain by you %d times"):format(n), 0.8, 0.8, 0.8) end
        end
        GameTooltip:AddLine(date("%b %d, %H:%M", d[3]), 0.8, 0.8, 0.8)
        if d.shot then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Screenshot #%d"):format(d.shot), 1, 1, 1)
            if d.file then GameTooltip:AddLine(d.file, 0.62, 0.83, 1) end
        end
    elseif self.kind == "sight" then
        GameTooltip:AddLine("Enemy sighted", foe.r, foe.g, foe.b)
        GameTooltip:AddLine((d.from and ("Reported by " .. d.from .. ", ") or "By you, ") .. Ago(d.t), 0.8, 0.8, 0.8)
    elseif self.kind == "skill" then
        GameTooltip:AddLine(d.from .. " scored a kill here", 0.6, 0.8, 1)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    else -- shared death
        GameTooltip:AddLine(d.from .. " was killed here", 1, 0.5, 0.4)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click to set a waypoint", 0.1, 1, 0.1)
    GameTooltip:Show()
end

local function PinClick(self, button)
    if button ~= "LeftButton" then return end
    local d = self.d
    Waypoint(self.mapID, d[1] or d.x, d[2] or d.y,
        self.kind == "death" and "where you fell" or self.kind == "kill" and "your kill"
        or self.kind == "sight" and "enemy sighting" or self.kind == "skill" and "an ally's kill" or "a fallen ally")
end

local function GetPin(i)
    local f = pins[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f:EnableMouse(true)
        f:SetScript("OnEnter", PinEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)
        f:SetScript("OnMouseUp", PinClick)
        pins[i] = f
    end
    return f
end

local function GetLabel(i)
    local f = labels[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f:SetSize(70, 20)
        f.crest = f:CreateTexture(nil, "OVERLAY")
        f.crest:SetSize(22, 22)
        f.crest:SetPoint("LEFT")
        f.crest:SetTexCoord(0, 0.62, 0, 0.62)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("LEFT", f.crest, "RIGHT", 1, 0)
        labels[i] = f
    end
    return f
end

local function At(obj, p, x, y, w, h)
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", overlay, "TOPLEFT", (p.ox + x * p.sx) * w, -(p.oy + y * p.sy) * h)
end

local function TrailColor(s, age)
    if age < 0 then age = 0 elseif age > 1 then age = 1 end
    if s.k == "g" then return 0.60, 0.85, 1.00, 0.55 - 0.30 * age, 0.7 end
    if s.k == "f" then return 1.00, 0.82, 0.30, 0.40 - 0.20 * age, 0.6 end
    return faction.r, faction.g, faction.b, 0.95 - 0.55 * age, 1
end

local EMPTY = { proj = {}, zones = {} }

-- limit: number of trail points to draw (replay); nil = live view.
local function Draw(scene, limit)
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    local now = time()
    local L = cfg.layers
    local nl, nd, ng, np, nb, ns = 0, 0, 0, 0, 0, 0
    local hx, hy
    local from, upTo = 0, math.huge -- time window for marks

    -- Heat: where you tend to be, and where the enemy has been seen.
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        if L.heat then
            local size = math.max(3, p.sx * w / GW * 3.2)
            for c, rec in pairs(z.heat) do
                local v = Long(rec, now)
                if v >= HEAT_MIN then
                    if nd >= DOT_BUDGET then break end
                    nd = nd + 1
                    local d = GetDot(nd)
                    local x, y = z.cx[c], z.cy[c]
                    if not x then x, y = CellXY(c, GW, GH) end
                    d:SetVertexColor(faction.r, faction.g, faction.b)
                    d:SetAlpha(0.06 + 0.22 * math.min(1, (v - HEAT_MIN) / (HEAT_FULL - HEAT_MIN)))
                    d:SetSize(size, size)
                    At(d, p, x, y, w, h)
                    d:Show()
                end
            end
        end
        if L.sightings then
            local vmax = 5
            for _, v in pairs(z.sight) do if v > vmax then vmax = v end end
            local size = math.max(4, p.sx * w / SW * 2.4)
            local denom = math.log(1 + vmax)
            for c, v in pairs(z.sight) do
                if nd >= DOT_BUDGET then break end
                nd = nd + 1
                local d = GetDot(nd)
                local x, y = CellXY(c, SW, SH)
                d:SetVertexColor(foe.r, foe.g, foe.b)
                d:SetAlpha(0.06 + 0.28 * math.log(1 + v) / denom)
                d:SetSize(size, size)
                At(d, p, x, y, w, h)
                d:Show()
            end
        end
    end

    -- The ground graph. Long memory: silver roads, then gold, each with a dark
    -- outline so they read on light and dark zones alike. Short memory:
    -- footsteps in your faction's colour.
    if not limit and (L.roads or L.recent) then
        local full = math.log(1 + 8)
        local gold = db.roadMin
        local silver = gold * SILVER_SHARE
        local faint = silver * 0.8 -- roads fade in before, and out after, silver
        for _, e in ipairs(scene.zones) do
            local z, p = e.z, e.p
            local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
            local thin = p.far and w * 0.0011 or w * 0.0020
            local spacing = math.max(5, thin * 4.5)
            local dot = math.max(2.5, thin * 2.2)
            for edge, rec in pairs(z.road) do
                local long = L.roads and Long(rec, now) or 0
                local recent = L.recent and Recent(rec, now) or 0
                if long >= faint or recent >= RECENT_MIN then
                    if nl >= LINE_BUDGET - 2 then break end
                    local a, b = math.floor(edge / 10000), edge % 10000
                    local ax, ay = z.cx[a], z.cy[a]
                    local bx, by = z.cx[b], z.cy[b]
                    if not ax then ax, ay = CellXY(a, GW, GH) end
                    if not bx then bx, by = CellXY(b, GW, GH) end
                    local x1, y1, x2, y2 = ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy)
                    if long >= faint then
                        local cr, cg, cb, core, casing, alpha
                        if long >= gold then
                            local depth = math.min(1, (long - gold) / (ROAD_FULL - gold))
                            cr, cg, cb = 0.95, 0.76, 0.29
                            core = thin * (1.4 + 1.6 * depth)
                            casing = core + thin * 1.6
                            alpha = 1
                        else
                            cr, cg, cb = 0.83, 0.85, 0.87
                            core = thin * 1.1
                            casing = core + thin * 1.4
                            alpha = long >= silver and 1 or 0.25 + 0.75 * (long - faint) / (silver - faint)
                        end
                        nl = nl + 1
                        local l = GetLine(nl)
                        StyleLine(l, 1)
                        l:SetThickness(casing)
                        l:SetColorTexture(0.08, 0.05, 0.02, 0.85 * alpha)
                        l:SetStartPoint("TOPLEFT", overlay, x1, y1)
                        l:SetEndPoint("TOPLEFT", overlay, x2, y2)
                        l:Show()
                        nl = nl + 1
                        l = GetLine(nl)
                        StyleLine(l, 2)
                        l:SetThickness(core)
                        l:SetColorTexture(cr, cg, cb, alpha)
                        l:SetStartPoint("TOPLEFT", overlay, x1, y1)
                        l:SetEndPoint("TOPLEFT", overlay, x2, y2)
                        l:Show()
                    end
                    if recent >= RECENT_MIN then
                        local alpha, scale = StepLook(rec, now)
                        local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
                        local n = math.max(1, math.floor(len / spacing + 0.5))
                        for k = 0, n - 1 do
                            if ns >= STEP_BUDGET then break end
                            local t = (k + 0.5) / n
                            ns = ns + 1
                            local d = GetStep(ns)
                            d:SetVertexColor(faction.r, faction.g, faction.b)
                            d:SetAlpha(alpha)
                            d:SetSize(dot * scale, dot * scale)
                            d:ClearAllPoints()
                            d:SetPoint("CENTER", overlay, "TOPLEFT", x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
                            d:Show()
                        end
                    end
                end
            end
        end
    end

    -- Trail.
    local function Stroke(s, p, upto, age, from)
        local r, g, b, a, weight = TrailColor(s, age)
        local thick = (p.far and w * 0.0012 or w * 0.0022) * weight
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        for i = from or 1, upto - 1 do
            if nl >= LINE_BUDGET then break end
            nl = nl + 1
            local l = GetLine(nl)
            StyleLine(l, 4)
            l:SetThickness(thick)
            l:SetColorTexture(r, g, b, a)
            l:SetStartPoint("TOPLEFT", overlay, ox + s[2 * i - 1] * sx, -(oy + s[2 * i] * sy))
            l:SetEndPoint("TOPLEFT", overlay, ox + s[2 * i + 1] * sx, -(oy + s[2 * i + 2] * sy))
            l:Show()
        end
        return ox + s[2 * upto - 1] * sx, -(oy + s[2 * upto] * sy)
    end

    if limit then
        local remaining = limit
        from, upTo = scene.since, scene.since
        for _, e in ipairs(scene.strokes) do
            if remaining <= 0 then break end
            local s = e.s
            local n = #s / 2
            local upto = math.min(n, math.ceil(remaining))
            hx, hy = Stroke(s, e.p, upto, 0)
            upTo = s.t + (s.e - s.t) * (upto / n)
            remaining = remaining - n
        end
    elseif L.recent then
        -- The solid line: your last two minutes, plus corpse runs and flights
        -- for twenty (they leave no footsteps). Points carry no timestamps,
        -- so the cut-off inside a stroke is interpolated from its start and end.
        for _, e in ipairs(scene.zones) do
            local strokes = e.z.strokes
            for i = #strokes, 1, -1 do -- newest first, so the budget drops the oldest
                local s = strokes[i]
                if now - s.e > RUN_SECONDS or nl >= LINE_BUDGET then break end
                local window = s.k and RUN_SECONDS or FRESH_SECONDS
                local n = #s / 2
                if now - s.e <= window and n >= 2 then
                    local from = 1
                    local cutoff = now - window
                    if cutoff > s.t and s.e > s.t then
                        from = math.max(1, math.min(n - 1, math.floor((cutoff - s.t) / (s.e - s.t) * (n - 1)) + 1))
                    end
                    Stroke(s, e.p, n, s.k and (now - s.t) / window or 0, from)
                end
            end
        end
    end

    -- Killing fields.
    if L.marks then
        for _, e in ipairs(scene.zones) do
            for _, fld in ipairs(Fields(e.p.mapID)) do
                ng = ng + 1
                local g = GetGlow(ng)
                local size = w * (e.p.far and 0.03 or 0.07) * math.min(2, 0.8 + fld.n * 0.15)
                g:SetSize(size, size)
                g:SetAlpha(math.min(1, 0.45 + fld.n * 0.1))
                At(g, e.p, fld.x, fld.y, w, h)
                g:Show()
            end
        end
    end

    -- Pins.
    local base = math.max(14, w * 0.018)
    local function Pin(kind, d, p, x, y, tex, size, r, g, b, a)
        if np >= MARK_BUDGET then return end
        np = np + 1
        local f = GetPin(np)
        f.kind, f.d, f.mapID = kind, d, p.mapID
        f.tex:SetTexture(tex)
        if kind == "sight" then f.tex:SetTexCoord(0, 0.62, 0, 0.62) else f.tex:SetTexCoord(0, 1, 0, 1) end
        f.tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        f:SetSize(size, size)
        At(f, p, x, y, w, h)
        f:Show()
    end

    if L.marks then
        for _, e in ipairs(scene.zones) do
            for _, m in ipairs(e.z.marks) do
                if m[3] >= from and m[3] <= upTo then
                    if m[4] == "kill" then
                        Pin("kill", m, e.p, m[1], m[2], TEX_BLADES, base)
                    elseif not m.pvp then
                        Pin("death", m, e.p, m[1], m[2], TEX_SKULL, base * 0.7, 0.6, 0.6, 0.6, 0.5)
                    elseif m.av then
                        Pin("death", m, e.p, m[1], m[2], TEX_SKULL, base, 1, 0.82, 0.2)
                    else
                        Pin("death", m, e.p, m[1], m[2], TEX_SKULL, base)
                    end
                end
            end
        end
    end
    if not limit then
        if L.sightings then
            for _, s in ipairs(recentSight) do
                local p = Proj(scene, s.mapID)
                if p and now - s.t <= SIGHT_LIVE then
                    Pin("sight", s, p, s.x, s.y, foe.crest, base * 1.3, 1, 1, 1, 1 - 0.6 * (now - s.t) / SIGHT_LIVE)
                end
            end
        end
        if L.shared then
            for _, s in ipairs(shared) do
                local p = Proj(scene, s.mapID)
                if p and s.expire >= now then
                    if s.kind == "S" then
                        Pin("sight", s, p, s.x, s.y, foe.crest, base * 1.3, 1, 1, 1, 0.85)
                    elseif s.kind == "K" then
                        Pin("skill", s, p, s.x, s.y, TEX_BLADES, base * 0.9, 0.6, 0.8, 1, 0.9)
                    else
                        Pin("sdeath", s, p, s.x, s.y, TEX_SKULL, base, 0.6, 0.8, 1, 0.9)
                    end
                end
            end
        end

        -- Zone standing, on continent-scale views.
        if L.marks then
            for _, e in ipairs(scene.zones) do
                local z = e.z
                if e.p.far and z.kills + z.pdeaths >= 3 then
                    nb = nb + 1
                    local f = GetLabel(nb)
                    local winning = z.kills >= z.pdeaths
                    local c = winning and faction or foe
                    f.crest:SetTexture(c.crest)
                    f.text:SetText(("%d : %d"):format(z.kills, z.pdeaths))
                    f.text:SetTextColor(c.r, c.g, c.b)
                    At(f, e.p, 0.5, 0.5, w, h)
                    f:Show()
                end
            end
        end
    end

    for i = nl + 1, #lines do lines[i]:Hide() end
    for i = nd + 1, #dots do dots[i]:Hide() end
    for i = ng + 1, #glows do glows[i]:Hide() end
    for i = np + 1, #pins do pins[i]:Hide() end
    for i = nb + 1, #labels do labels[i]:Hide() end
    for i = ns + 1, #steps do steps[i]:Hide() end

    if hx then
        head:SetSize(w * 0.035, w * 0.035)
        head:ClearAllPoints()
        head:SetPoint("CENTER", overlay, "TOPLEFT", hx, hy)
        head:Show()
    else
        head:Hide()
    end
end

local function Redraw()
    if not overlay or not WorldMapFrame:IsShown() or replay.active then return end
    dirty, lastDraw = false, GetTime()
    local viewed = WorldMapFrame:GetMapID()
    if db.shown and not inInstance and viewed and overlay:GetWidth() > 0 then
        Draw(BuildScene(viewed))
    else
        Draw(EMPTY)
    end
end

---------------------------------------------------------------------------
-- Replay
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")

local function StopReplay()
    replay.active = false
    driver:SetScript("OnUpdate", nil)
    Redraw()
end

local function ReplayFrame(_, elapsed)
    if not WorldMapFrame:IsShown() then return StopReplay() end
    replay.clock = replay.clock + elapsed
    replay.acc = replay.acc + elapsed
    if replay.acc < 0.04 then return end
    replay.acc = 0
    local viewed = WorldMapFrame:GetMapID()
    if viewed ~= replay.viewed then
        replay.viewed = viewed
        replay.scene = viewed and BuildScene(viewed, replay.since) or nil
    end
    local progress = replay.clock / REPLAY_SECONDS
    if progress >= 1 + 3 / REPLAY_SECONDS then return StopReplay() end -- hold the last frame 3s
    if replay.scene and replay.scene.points >= 2 then
        Draw(replay.scene, math.max(1, math.min(1, progress) * replay.scene.points))
    else
        Draw(EMPTY)
    end
end

local function StartReplay(hours)
    if not overlay then return end
    hours = math.min(KEEP_HOURS, math.max(1, hours or 6))
    local mapID = C_Map.GetBestMapForUnit("player")
    if not WorldMapFrame:IsShown() then
        if InCombatLockdown() then Print("open your map first; I can't do that for you in combat.") return end
        ToggleWorldMap()
    end
    if mapID and not Secret(mapID) and not InCombatLockdown() then WorldMapFrame:SetMapID(mapID) end
    if cur.stroke then Simplify(cur.stroke) end

    replay.since = time() - hours * 3600
    replay.viewed = WorldMapFrame:GetMapID()
    replay.scene = replay.viewed and BuildScene(replay.viewed, replay.since) or nil
    if not replay.scene or replay.scene.points < 2 then
        Print(("nothing recorded on this map in the last %d hours."):format(hours))
        return
    end
    Print(("replaying the last %d hours. Zoom out to follow it across zones."):format(hours))
    replay.active, replay.clock, replay.acc = true, 0, 1
    driver:SetScript("OnUpdate", ReplayFrame)
end

---------------------------------------------------------------------------
-- World map hookup
---------------------------------------------------------------------------

local function SetupMap()
    if overlay or not WorldMapFrame then return end
    local canvas = WorldMapFrame:GetCanvas()
    overlay = CreateFrame("Frame", "WarpathOverlay", canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 2500)
    overlay:SetScript("OnSizeChanged", function() dirty = true end)
    head = overlay:CreateTexture(nil, "OVERLAY")
    head:SetTexture(TEX_GLOW)
    head:SetBlendMode("ADD")
    head:SetVertexColor(1, 0.9, 0.5)
    head:Hide()
    WorldMapFrame:HookScript("OnShow", Redraw)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Redraw)
end

---------------------------------------------------------------------------
-- War table (HUD) and chronicle
---------------------------------------------------------------------------

local function CreateHUD()
    hud = CreateFrame("Frame", "WarpathHUD", UIParent, "BackdropTemplate")
    hud:SetSize(210, 108)
    hud:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    hud:SetBackdropColor(0.05, 0.03, 0.02, 0.85)
    hud:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    local pos = db.hud
    hud:SetPoint(pos and pos[1] or "TOPLEFT", UIParent, pos and pos[1] or "TOPLEFT", pos and pos[2] or 20, pos and pos[3] or -180)

    hud:SetMovable(true)
    hud:SetClampedToScreen(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", hud.StartMoving)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.hud = { point, x, y }
    end)
    hud:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            local d = db.lastDeath
            if d then Waypoint(d[1], d[2], d[3], "where you last fell")
            else Print("you haven't died yet. Keep it that way.") end
        end
    end)
    hud:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Warpath", 1, 0.82, 0)
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:AddLine("Right-click: waypoint to where you last fell", 1, 1, 1)
        GameTooltip:AddLine("/warpath help for everything else", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    hud:SetScript("OnLeave", GameTooltip_Hide)

    local crest = hud:CreateTexture(nil, "ARTWORK")
    crest:SetTexture(faction.crest)
    crest:SetTexCoord(0, 0.62, 0, 0.62)
    crest:SetSize(30, 30)
    crest:SetPoint("TOPRIGHT", -8, -8)

    hud.title = hud:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hud.title:SetPoint("TOPLEFT", 12, -10)
    hud.title:SetText("Warpath")

    hud.rows = {}
    for i = 1, 5 do
        local fs = hud:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, -14 - i * 15)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(186)
        fs:SetWordWrap(false)
        hud.rows[i] = fs
    end
    hud:SetShown(cfg.hudShown and not inInstance)
end

local function SaveSession()
    local zones = 0
    for _ in pairs(session.zones) do zones = zones + 1 end
    db.lastSession = {
        start = session.start, stop = time(), kills = session.kills, deaths = session.deaths,
        best = session.best, yards = session.yards, sightings = session.sightings,
        avenged = session.avenged, zones = zones,
    }
end

function UpdateHUD()
    SaveSession()
    if not hud or not hud:IsShown() then return end
    hud.rows[1]:SetText(("Kills |cff40ff40%d|r   Deaths |cffff4030%d|r"):format(session.kills, session.deaths))
    hud.rows[2]:SetText(("Streak %s%d|r   Best %s%d|r"):format(GOLD, session.streak, GOLD, db.bestStreak))
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and not Secret(mapID) and not inInstance then
        local z = db.maps[mapID]
        hud.rows[3]:SetText(z and (z.kills + z.pdeaths > 0)
            and ("%s  %d : %d"):format(MapName(mapID), z.kills, z.pdeaths) or MapName(mapID))
        local seen, now = 0, time()
        for _, s in ipairs(recentSight) do
            if s.mapID == mapID and now - s.t <= 300 then seen = seen + 1 end
        end
        local fields = #Fields(mapID)
        if seen > 0 then
            hud.rows[4]:SetText(("|cffff8000%d enem%s seen in the last 5 min|r"):format(seen, seen == 1 and "y" or "ies"))
        elseif fields > 0 then
            hud.rows[4]:SetText(("|cffff4030%d killing field%s here|r"):format(fields, fields == 1 and "" or "s"))
        else
            hud.rows[4]:SetText("|cff808080No enemies seen lately|r")
        end
    else
        hud.rows[3]:SetText("|cff808080Not recording here|r")
        hud.rows[4]:SetText("")
    end
    hud.rows[5]:SetText(("%.1f miles marched"):format(db.yards / 1760))
end

local function Chronicle(s, title)
    if not s then Print("no campaign recorded yet.") return end
    local mins = math.floor(((s.stop or time()) - s.start) / 60)
    Print(("%s%s|r (%s, %dh %02dm): %.1f miles, zones %d, kills %d, deaths %d, best streak %d, enemies sighted %d, deaths avenged %d.")
        :format(GOLD, title, date("%b %d", s.start), math.floor(mins / 60), mins % 60,
            s.yards / 1760, s.zones, s.kills, s.deaths, s.best, s.sightings, s.avenged))
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function Stats()
    local zones, farMap, farYards, deadMap, deadN = 0, nil, 0, nil, 0
    for mapID, z in pairs(db.maps) do
        zones = zones + 1
        if z.yards > farYards then farMap, farYards = mapID, z.yards end
        if z.pdeaths > deadN then deadMap, deadN = mapID, z.pdeaths end
    end
    Print(("%.1f miles marched, zones visited %d. Kills %d, deaths to players %d, best streak %d.")
        :format(db.yards / 1760, zones, db.kills, db.deaths, db.bestStreak))
    if farMap then Print(("Most marched: %s (%.1f mi)."):format(MapName(farMap), farYards / 1760)) end
    if deadMap then Print(("Deadliest ground: %s (%d deaths)."):format(MapName(deadMap), deadN)) end
    local who, most = nil, 0
    for name, n in pairs(db.victims) do
        if n > most then who, most = name, n end
    end
    if who then Print(("Favourite victim: %s (%d kills)."):format(who, most)) end
end

local function ZoneReport()
    local mapID = C_Map.GetBestMapForUnit("player")
    local z = mapID and db.maps[mapID]
    if not z then Print("nothing recorded in this zone yet.") return end
    local seen = 0
    for _, n in pairs(z.sight) do seen = seen + n end
    Print(("%s: kills %d, deaths to players %d, killing fields %d, enemy sightings %d, %.1f miles.")
        :format(MapName(mapID), z.kills, z.pdeaths, #Fields(mapID), seen, z.yards / 1760))
    local goldN, silverN, recent, now = 0, 0, 0, time()
    for _, e in pairs(z.road) do
        local long = Long(e, now)
        if long >= db.roadMin then goldN = goldN + 1
        elseif long >= db.roadMin * SILVER_SHARE then silverN = silverN + 1 end
        if Recent(e, now) >= RECENT_MIN then recent = recent + 1 end
    end
    Print(("Ground remembered: %d stretches of gold road, %d of silver, %d with today's footsteps.")
        :format(goldN, silverN, recent))
    local hours = BusiestHours(z)
    if hours then Print("The enemy is most active here around " .. hours .. " (your local time).") end
end


---------------------------------------------------------------------------
-- Setup window: once after each install or update, or /warpath setup
---------------------------------------------------------------------------

local ShowSetup, MaybeShowSetup, setup
do
-- Everything since 3.2, for anyone updating from any 3.2 or 3.3 build.
local NEW_IN = {
    "Kill screenshots with a small caption. Hover a blade to see which file.",
    "Silver roads on the second day you use a route; gold from the third.",
    "Roads are outlined to show on any zone. Today's trail is footsteps",
    "    that fade behind you over half an hour.",
    "Kills are named in combat, and one enemy death counts as one kill.",
    "Guild sharing includes kills. /warpath share test checks it works.",
    "Completely off in battlegrounds and arenas.",
    "Settings in this window are shared by all your characters.",
}

local function MakeCheck(parent, label, hint)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    if hint then
        cb.hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        cb.hint:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -2)
        cb.hint:SetWidth(420)
        cb.hint:SetJustifyH("LEFT")
        cb.hint:SetText(hint)
    end
    return cb
end

local function MakeRadios(parent, label, options)
    local group = { buttons = {}, value = nil }
    group.label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    group.label:SetText(label)
    local prev
    for i, opt in ipairs(options) do
        local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        rb.value = opt[1]
        rb.text2 = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rb.text2:SetPoint("LEFT", rb, "RIGHT", 3, 0)
        rb.text2:SetText(opt[2])
        if prev then
            rb:SetPoint("LEFT", prev.text2, "RIGHT", 14, 0)
        else
            rb:SetPoint("LEFT", group.label, "LEFT", 96, 0)
        end
        rb:SetScript("OnClick", function() group:Set(rb.value) end)
        group.buttons[i] = rb
        prev = rb
    end
    function group:Set(v)
        self.value = v
        for _, b in ipairs(self.buttons) do b:SetChecked(b.value == v) end
    end
    return group
end

local function SetupLoad(s, c)
    s.shotOn:SetChecked(c.shot.on)
    s.which:Set(c.shot.mode)
    s.caption:Set(c.shot.card)
    s.roads:SetChecked(c.layers.roads)
    s.recent:SetChecked(c.layers.recent)
    s.heat:SetChecked(c.layers.heat)
    s.sightings:SetChecked(c.layers.sightings)
    s.share:SetChecked(c.share)
    s.banners:SetChecked(not c.quiet)
    s.hud:SetChecked(c.hudShown)
end

local function SetupSave(s)
    cfg.shot.on = s.shotOn:GetChecked() and true or false
    cfg.shot.mode = s.which.value or "all"
    cfg.shot.card = s.caption.value or "text"
    cfg.layers.roads = s.roads:GetChecked() and true or false
    cfg.layers.recent = s.recent:GetChecked() and true or false
    cfg.layers.heat = s.heat:GetChecked() and true or false
    cfg.layers.sightings = s.sightings:GetChecked() and true or false
    cfg.share = s.share:GetChecked() and true or false
    cfg.quiet = not s.banners:GetChecked()
    cfg.hudShown = s.hud:GetChecked() and true or false
    if hud then hud:SetShown(cfg.hudShown and not inInstance) end
    UpdateHUD()
    dirty = true
end

local function DefaultsView()
    local layers = {}
    for _, name in ipairs(LAYERS) do layers[name] = true end
    local shot = {}
    for k, v in pairs(SHOT_DEFAULTS) do shot[k] = v end
    return {
        layers = layers, shot = shot, share = CFG_DEFAULTS.share,
        quiet = CFG_DEFAULTS.quiet, hudShown = CFG_DEFAULTS.hudShown,
    }
end

local function BuildSetup()
    local s = CreateFrame("Frame", "WarpathSetup", UIParent, "BackdropTemplate")
    s:SetSize(540, 600 + (26 + #NEW_IN * 15 - 76))
    s:SetPoint("TOP", 0, -90)
    s:SetFrameStrata("DIALOG")
    s:SetToplevel(true)
    s:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    s:EnableMouse(true)
    s:SetMovable(true)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", s.StartMoving)
    s:SetScript("OnDragStop", s.StopMovingOrSizing)
    -- Only "To war" or the close button count as seen. Escape, or the UI
    -- closing every window, shows it again next login.
    s.MarkSeen = function()
        gdb.seenVersion = VERSION
        gdb.installed = gdb.installed or VERSION
    end
    tinsert(UISpecialFrames, "WarpathSetup") -- Escape closes it

    local crest = s:CreateTexture(nil, "ARTWORK")
    crest:SetTexture(faction.crest)
    crest:SetTexCoord(0, 0.62, 0, 0.62)
    crest:SetSize(44, 44)
    crest:SetPoint("TOPLEFT", 22, -20)
    s.title = s:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    s.title:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, -2)
    s.sub = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    s.sub:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)

    local close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() s.MarkSeen() s:Hide() end)

    -- "New in" box (updates only)
    s.newBox = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.newBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    s.newBox:SetBackdropColor(0.14, 0.11, 0.08, 0.9)
    s.newBox:SetBackdropBorderColor(0.55, 0.45, 0.28, 0.9)
    s.newBox:SetPoint("TOPLEFT", 22, -76)
    s.newBox:SetPoint("TOPRIGHT", -22, -76)
    s.newBox:SetHeight(26 + #NEW_IN * 15)
    local nh = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nh:SetPoint("TOPLEFT", 10, -8)
    nh:SetText("NEW SINCE 3.2")
    local prevLine = nh
    for _, line in ipairs(NEW_IN) do
        local fs = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", prevLine, "BOTTOMLEFT", 0, -3)
        fs:SetText(line)
        prevLine = fs
    end
    s.welcome = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s.welcome:SetPoint("TOPLEFT", 22, -80)
    s.welcome:SetWidth(496)
    s.welcome:SetJustifyH("LEFT")
    s.welcome:SetText("Warpath draws your open-world PvP history on the world map. Pick how you want it; everything can be changed later.")

    -- Controls. y is relative to the top of the control area.
    s.body = CreateFrame("Frame", nil, s)
    s.body:SetPoint("TOPLEFT", 22, -(90 + 26 + #NEW_IN * 15 + 14))
    s.body:SetPoint("BOTTOMRIGHT", -22, 60)
    local b, y = s.body, 0
    local function Heading(text)
        local h = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetText(text)
        y = y + 20
    end
    local function Place(widget, x, dy)
        widget:SetPoint("TOPLEFT", x or 0, -y)
        y = y + (dy or 26)
    end

    Heading("KILL SCREENSHOTS")
    s.shotOn = MakeCheck(b, "Take a screenshot when I get an honorable kill")
    Place(s.shotOn)
    s.which = MakeRadios(b, "Which kills", { { "all", "Every kill" }, { "notable", "Notable only" } })
    s.which.label:SetPoint("TOPLEFT", 28, -(y + 4))
    y = y + 22
    s.caption = MakeRadios(b, "Caption", { { "text", "Floating text" }, { "strip", "Caption strip" }, { "none", "None" } })
    s.caption.label:SetPoint("TOPLEFT", 28, -(y + 4))
    y = y + 32

    Heading("ON THE MAP")
    s.roads = MakeCheck(b, "Silver and gold roads")
    s.recent = MakeCheck(b, "Today's footsteps")
    s.heat = MakeCheck(b, "Places I linger (haze)")
    s.sightings = MakeCheck(b, "Enemy sightings")
    s.roads:SetPoint("TOPLEFT", 0, -y)
    s.recent:SetPoint("TOPLEFT", 250, -y)
    y = y + 26
    s.heat:SetPoint("TOPLEFT", 0, -y)
    s.sightings:SetPoint("TOPLEFT", 250, -y)
    y = y + 36

    Heading("GUILD AND PARTY")
    s.share = MakeCheck(b, "Share enemy sightings, my kills and my PvP deaths",
        "Sends map positions only, never names or your trail. Everyone who wants it turns it on.")
    Place(s.share, 0, 46)

    Heading("ALERTS")
    s.banners = MakeCheck(b, "Raid-warning banners and sounds", "Off: alerts become chat lines instead.")
    Place(s.banners, 0, 42)
    s.hud = MakeCheck(b, "Show the war table panel")
    Place(s.hud)

    local foot = s:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 24, 26)
    foot:SetText("Shown once after an install or update. Reopen with /warpath setup.")

    local go = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    go:SetSize(110, 26)
    go:SetPoint("BOTTOMRIGHT", -22, 20)
    go:SetText("To war")
    go:SetScript("OnClick", function()
        SetupSave(s)
        s.MarkSeen()
        Print("settings saved. /warpath setup to change them.")
        s:Hide()
    end)
    local def = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    def:SetSize(100, 26)
    def:SetPoint("RIGHT", go, "LEFT", -8, 0)
    def:SetText("Defaults")
    def:SetScript("OnClick", function() SetupLoad(s, DefaultsView()) end)

    return s
end

function ShowSetup(isUpdate)
    if not setup then setup = BuildSetup() end
    local s = setup
    if isUpdate then
        s.title:SetText("Warpath updated to " .. VERSION)
        s.sub:SetText("Your current settings are already filled in.")
        s.newBox:Show()
        s.welcome:Hide()
    else
        s.title:SetText("Welcome to Warpath")
        s.sub:SetText("These are the defaults. Change anything you like.")
        s.newBox:Hide()
        s.welcome:Show()
    end
    SetupLoad(s, cfg)
    s:Show()
end

-- Once per account per version, never in combat.
function MaybeShowSetup()
    if gdb.seenVersion == VERSION then return end
    if inInstance then setupWaiting = true return end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        setupWaiting = true
        return
    end
    setupWaiting = false
    local ok, err = pcall(ShowSetup, gdb.installed and true or false)
    if not ok then
        Print("the setup window failed to open: " .. tostring(err))
        Print("please send that line to whoever gave you Warpath. Settings are still at their defaults.")
        gdb.seenVersion = VERSION -- don't fail again on every login
    end
end

end

local HELP = {
    "/warpath - campaign stats    |    /warpath zone - this zone's standing and enemy hours",
    "/warpath chronicle - this session and your last one",
    "/warpath setup - the settings window    |    /warpath debug - what Warpath can and can't see",
    "/warpath share test - send a test ping to guildmates    |    /warpath share status - messages sent and received",
    "/warpath shot - kill screenshot status; shot on|off, all|notable, text|strip|none, combat on|off, delay <sec>, test",
    "/warpath replay [hours] - replay your recent march on the map (up to 24)",
    "/warpath revenge  |  lastkill - waypoint to your last death or kill",
    "/warpath grudge [Name-Realm] - add or remove a grudge (default: your target)",
    "/warpath grudges - list your grudges",
    "/warpath share - share sightings and deaths with guild and party (off by default)",
    "/warpath layer heat|roads|recent|marks|sightings|shared - toggle a map layer",
    "/warpath memory <hours> <days> - half-life of short and long memory (default 3 and 14)",
    "/warpath roads <days> - days of use before a road is etched (default 2.5)",
    "/warpath quiet - banners become chat lines, no sounds    |    /warpath sound",
    "/warpath hud  |  toggle - show or hide the war table, or everything on the map",
    "/warpath clear zone | all - forget this zone, or everything",
}

SLASH_WARPATH1, SLASH_WARPATH2 = "/warpath", "/wpath"
-- /killshot and /pks keep working for anyone used to PvPKillShot, unless that
-- addon is still installed and owns them.
local pksLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PvPKillShot")
if not pksLoaded then
    SLASH_WARPATHSHOT1, SLASH_WARPATHSHOT2 = "/killshot", "/pks"
    SlashCmdList.WARPATHSHOT = function(msg)
        local m = (msg or ""):lower():gsub("^%s+", "")
        if m == "toggle" then m = cfg.shot.on and "off" or "on" end
        if m == "status" then m = "" end
        SlashCmdList.WARPATH("shot " .. m)
    end
end
SlashCmdList.WARPATH = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "stats" then
        Stats()
    elseif cmd == "zone" then
        ZoneReport()
    elseif cmd == "setup" then
        local ok, err = pcall(ShowSetup, false)
        if not ok then Print("the setup window failed to open: " .. tostring(err)) end
    elseif cmd == "debug" then
        Print(("in a battleground or instance: %s"):format(inInstance and "yes, Warpath is resting" or "no"))
        Print(("version %s | setup seen %s | install %s | PvPKillShot loaded %s")
            :format(VERSION, tostring(gdb.seenVersion), tostring(gdb.installed),
                tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PvPKillShot"))))
        Print(("sharing %s | %d sent, %d refused, %d received%s")
            :format(cfg.share and "on" or "off", shareStats.sent, shareStats.refused, shareStats.got,
                shareStats.lastRefusal and (" | last refusal " .. shareStats.lastRefusal) or ""))
        Print(("this session: %d honorable-kill credits, counted as %d kills"):format(Foes.credits, Foes.kills))
        local last = Foes.last
        Print(("last kill name: %s | last enemy target: %s | enemies known: %d")
            :format(Foes.miss and ("not read, because " .. Foes.miss) or "read fine",
                last and (last.short .. ", " .. math.floor(GetTime() - last.at) .. "s ago") or "none",
                (function() local n = 0 for _ in pairs(Foes.known) do n = n + 1 end return n end)()))
    elseif cmd == "shot" then
        local sub, val = arg:lower():match("^(%S*)%s*(.-)$")
        local c = cfg.shot
        if sub == "on" or sub == "off" then
            c.on = sub == "on"
        elseif sub == "all" or sub == "notable" then
            c.mode = sub
        elseif sub == "text" or sub == "strip" or sub == "none" then
            c.card = sub
        elseif sub == "combat" and (val == "on" or val == "off") then
            c.combat = val == "on"
        elseif sub == "delay" then
            local n = tonumber(val)
            if n and n >= 0 and n <= 5 then c.delay = n else Print("usage: /warpath shot delay <0-5>") return end
        elseif sub == "test" then
            local mapID = C_Map.GetBestMapForUnit("player")
            TakeKillShot({
                name = myName, class = select(2, UnitClass("player")),
                zone = mapID and not Secret(mapID) and MapName(mapID) or "", times = 4, streak = 3, when = time(),
            }, nil, nil, true)
            return
        elseif sub ~= "" then
            Print("usage: /warpath shot on|off, all|notable, text|strip|none, combat on|off, delay <sec>, test")
            return
        end
        local names = { text = "floating text", strip = "caption strip", none = "no caption" }
        Print(("kill screenshots %s, %s, %s, %.1fs delay, combat check %s. %d taken so far.")
            :format(c.on and "|cff40ff40on|r" or "|cffff4030off|r", c.mode == "all" and "every kill" or "notable kills only",
                names[c.card] or c.card, c.delay, c.combat and "on" or "off", gdb.shotCount))
    elseif cmd == "chronicle" then
        SaveSession()
        Chronicle(db.lastSession, "This campaign")
        if db.prevSession then Chronicle(db.prevSession, "Last campaign") end
    elseif cmd == "replay" then
        if replay.active then StopReplay() else StartReplay(tonumber(arg)) end
    elseif cmd == "revenge" then
        local d = db.lastDeath
        if d then Waypoint(d[1], d[2], d[3], "where you last fell") else Print("no deaths recorded.") end
    elseif cmd == "lastkill" then
        local k = db.lastKill
        if k then Waypoint(k[1], k[2], k[3], "your last kill") else Print("no kills recorded.") end
    elseif cmd == "grudge" then
        ToggleGrudge(arg)
    elseif cmd == "grudges" then
        local names = {}
        for name in pairs(gdb.kos) do names[#names + 1] = name end
        table.sort(names)
        Print(#names == 0 and "you hold no grudges." or ("grudges: " .. table.concat(names, ", ")))
    elseif cmd == "share" and (arg == "test" or arg == "status") then
        if not cfg.share then
            Print("sharing is off. /warpath share turns it on.")
        elseif arg == "test" then
            local mapID, x, y = PlayerPos()
            if not mapID then Print("can't send from here (instances are blocked).") return end
            Share("T", mapID, x, y, true)
            FlushShare()
            Print(("test ping sent (guild %s, group %s). Guildmates with sharing on should see a chat line within seconds.")
                :format(IsInGuild() and "yes" or "no", IsInGroup() and "yes" or "no"))
        end
        Print(("this session: %d sent, %d refused by the game, %d received.%s")
            :format(shareStats.sent, shareStats.refused, shareStats.got,
                shareStats.lastRefusal and (" Last refusal: " .. shareStats.lastRefusal) or ""))
    elseif cmd == "share" then
        cfg.share = not cfg.share
        Print(cfg.share
            and "sharing ON. Guild and party members running Warpath get your enemy sightings, kills and PvP deaths, and you get theirs. Your trail and enemy names are never sent."
            or "sharing off.")
        if not cfg.share then
            for i = #shared, 1, -1 do shared[i] = nil end
            for i = #outQ, 1, -1 do outQ[i] = nil end
        end
        Redraw()
    elseif cmd == "layer" then
        arg = arg:lower()
        if cfg.layers[arg] == nil then
            Print("layers: " .. table.concat(LAYERS, ", "))
        else
            cfg.layers[arg] = not cfg.layers[arg]
            Print(arg .. " layer " .. (cfg.layers[arg] and "shown." or "hidden."))
            Redraw()
        end
    elseif cmd == "roads" then
        local n = tonumber(arg)
        if n and n >= 1.5 and n <= 10 then
            db.roadMin = n
            Print(("a road is etched once it holds about %g days of use."):format(n))
            Redraw()
        else
            Print(("roads are etched at %g days of use. Usage: /warpath roads <1.5-10>. Hide them with /warpath layer roads.")
                :format(db.roadMin))
        end
    elseif cmd == "memory" then
        local hours, days = arg:match("^(%S+)%s+(%S+)$")
        hours, days = tonumber(hours), tonumber(days)
        if hours and days and hours >= 0.5 and hours <= 24 and days >= 2 and days <= 90 then
            db.recentHours, db.longDays = hours, days
            Print(("short memory now halves every %g hours, long memory every %g days."):format(hours, days))
            Redraw()
        else
            Print(("short memory halves every %g hours, long memory every %g days. Usage: /warpath memory <hours 0.5-24> <days 2-90>")
                :format(db.recentHours, db.longDays))
        end
    elseif cmd == "quiet" then
        cfg.quiet = not cfg.quiet
        Print(cfg.quiet and "quiet: banners become chat lines, sounds off." or "banners and sounds back on.")
    elseif cmd == "sound" then
        cfg.sound = not cfg.sound
        Print("sounds " .. (cfg.sound and "on." or "off."))
    elseif cmd == "hud" then
        cfg.hudShown = not cfg.hudShown
        hud:SetShown(cfg.hudShown and not inInstance)
        UpdateHUD()
    elseif cmd == "toggle" then
        db.shown = not db.shown
        Print("map layers " .. (db.shown and "shown." or "hidden (still recording)."))
        Redraw()
    elseif cmd == "clear" then
        arg = arg:lower()
        if arg == "all" then
            db.maps, db.yards, db.victims = {}, 0, {}
            db.kills, db.deaths, db.bestStreak = 0, 0, 0
            db.lastDeath, db.lastKill = nil, nil
            fieldCache, roadSeen, cur.stroke, cur.cell, cur.rc, pendingAvenge = {}, {}, nil, nil, nil, nil
            Print("the slate is clean. Your grudges are kept; settle those one by one.")
        elseif arg == "zone" then
            local mapID = C_Map.GetBestMapForUnit("player")
            if mapID and db.maps[mapID] then
                db.yards = math.max(0, db.yards - db.maps[mapID].yards)
                db.maps[mapID], fieldCache[mapID], cur.stroke, cur.cell, cur.rc = nil, nil, nil, nil, nil
                Print("forgot " .. MapName(mapID) .. ".")
            end
        else
            Print("Usage: /warpath clear zone  |  /warpath clear all")
        end
        Redraw()
        UpdateHUD()
    else
        for _, line in ipairs(HELP) do Print(line) end
    end
end

---------------------------------------------------------------------------
-- Public API (for PvPKillShot and friends)
---------------------------------------------------------------------------

Warpath = {
    RegisterKillCallback = function(fn)
        if type(fn) == "function" then killCallbacks[#killCallbacks + 1] = fn end
    end,
    GetSession = function()
        return { kills = session.kills, deaths = session.deaths, streak = session.streak, best = session.best }
    end,
    GetKillCount = function(fullName) return db and db.victims[fullName] or 0 end,
}

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local DEFAULTS = {
    yards = 0, kills = 0, deaths = 0, bestStreak = 0, recentHours = 3, longDays = 14, roadMin = 2.5,
    shown = true,
}

-- Battlegrounds, arenas, dungeons and raids. Any one of these is enough;
-- each is wrapped so a missing or hidden API just counts as "no".
local function InsideMatch()
    local ok, inside, kind = pcall(IsInInstance)
    if ok and (inside == true or (type(kind) == "string" and kind ~= "none")) then return true end
    if UnitInBattleground and Foes.Safe(UnitInBattleground, "player") then return true end
    if C_PvP then
        for _, fn in ipairs({ C_PvP.IsBattleground, C_PvP.IsArena, C_PvP.IsActiveBattlefield,
                              C_PvP.IsRatedBattleground, C_PvP.IsInBrawl }) do
            if fn and Foes.Safe(fn) == true then return true end
        end
    end
    local zoneKind = GetZonePVPInfo and Foes.Safe(GetZonePVPInfo)
    if zoneKind == "arena" or zoneKind == "combat" then return true end
    return false
end

-- While inside: no recording, no banners or sounds, no kill shots, no
-- sharing, no war table, nothing drawn, no setup window. All of it comes
-- back when you leave.
local function RefreshInstance()
    local was = inInstance
    inInstance = InsideMatch()
    if inInstance and cur.stroke then
        Simplify(cur.stroke)
        cur.stroke = nil
    end
    if was ~= inInstance and db then
        if hud then hud:SetShown(cfg.hudShown and not inInstance) end
        if inInstance then
            for i = #outQ, 1, -1 do outQ[i] = nil end
            if setup and setup:IsShown() then setup:Hide() setupWaiting = true end
        elseif ready then
            C_Timer.After(3, MaybeShowSetup)
        end
        dirty = true
        Redraw()
    end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_PVP_KILLS_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE",
}) do f:RegisterEvent(ev) end

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            WarpathDB = WarpathDB or {}
            WarpathGlobal = WarpathGlobal or {}
            db, gdb = WarpathDB, WarpathGlobal
            db.maps = db.maps or {}
            db.victims = db.victims or {}
            for k, v in pairs(DEFAULTS) do
                if db[k] == nil then db[k] = v end
            end
            gdb.kos = gdb.kos or {}
            -- 3.3: the key settings are account-wide. Seed them from this
            -- character's old settings the first time.
            if not gdb.cfg then
                gdb.cfg = {
                    layers = db.layers or {},
                    share = db.share or false, quiet = db.quiet or false,
                    sound = db.sound ~= false, hudShown = db.hudShown ~= false,
                }
            end
            cfg = gdb.cfg
            cfg.layers = cfg.layers or {}
            for _, name in ipairs(LAYERS) do
                if cfg.layers[name] == nil then cfg.layers[name] = true end
            end
            for k, v in pairs(CFG_DEFAULTS) do
                if cfg[k] == nil then cfg[k] = v end
            end
            cfg.shot = cfg.shot or {}
            for k, v in pairs(SHOT_DEFAULTS) do
                if cfg.shot[k] == nil then cfg.shot[k] = v end
            end
            gdb.shotCount = gdb.shotCount or 0
            if gdb.installed == nil then
                gdb.installed = (db.v ~= nil or next(db.maps) ~= nil) and VERSION or false
            end
            Migrate()
            if db.roadMin == nil or db.roadMin > 10 then db.roadMin = DEFAULTS.roadMin end
            if db.recentHours > 24 then db.recentHours = DEFAULTS.recentHours end
            db.prevSession, db.lastSession = db.lastSession, nil
        elseif arg1 == "Blizzard_WorldMap" and db then
            SetupMap()
        end
    elseif event == "PLAYER_LOGIN" then
        local group = UnitFactionGroup("player")
        faction = FACTION[group or "Neutral"] or FACTION.Neutral
        foe = FACTION[faction.foe]
        myName = UnitName("player")
        myFull = myName .. "-" .. (GetNormalizedRealmName() or "")
        session.start = time()
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM)
        RefreshInstance()
        Prune()
        SetupMap()
        CreateHUD()
        UpdateHUD()
        C_Timer.NewTicker(SAMPLE_INTERVAL, function()
            tick = tick + 1
            Sample()
            if tick % 4 == 0 then CheckFields() end
            if tick % 2 == 0 then Foes.Track() end
            if Foes.dead and not UnitIsDeadOrGhost("player") then Foes.dead = false end
            if tick % 10 == 0 then RefreshInstance() UpdateHUD() end
            if tick % 2 == 0 then FlushShare() end
            if tick % 1200 == 0 then Prune() end
            if dirty and GetTime() - lastDraw > 2 then Redraw() end
        end)
        -- The kill-count event can fire while honor data loads; ignore that.
        C_Timer.After(5, function()
            ready = true
            Foes.dead = UnitIsDeadOrGhost("player") and true or false
            ZoneWarning()
            if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PvPKillShot") then
                Print("PvPKillShot is also running, so every kill gets two screenshots. Warpath does its job now: disable or delete PvPKillShot.")
            end
            C_Timer.After(2, MaybeShowSetup)
            if db.prevSession and db.prevSession.kills + db.prevSession.deaths > 0 then
                Chronicle(db.prevSession, "Last campaign")
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_ACTIVE" or event == "PVP_MATCH_COMPLETE" then
        RefreshInstance()
    elseif event == "PLAYER_DEAD" then
        if ready and not Foes.dead then
            Foes.dead = true
            OnDeath()
        end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        if not UnitIsDeadOrGhost("player") then Foes.dead = false end
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        if ready and (arg1 == nil or arg1 == "player") then Foes.OnCredit() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        RefreshInstance()
        C_Timer.After(1, function() ZoneWarning() UpdateHUD() end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        See("target")
        Foes.Track()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        See("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        See(arg1)
    elseif event == "CHAT_MSG_ADDON" then
        if db then OnComm(arg1, arg2, arg3, arg4) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        lastCombatEnd = GetTime()
        if setupWaiting then C_Timer.After(2, MaybeShowSetup) end
    elseif event == "SCREENSHOT_SUCCEEDED" then
        FinishShot(true)
    elseif event == "SCREENSHOT_FAILED" then
        FinishShot(false)
    end
end)
