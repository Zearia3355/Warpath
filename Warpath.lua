
-- Warpath 3.7.2
-- Your war, inked on the map.
--
-- Map layers (/warpath layer <name> [on|off], or right-click the map button):
--   The map has two memories, both kept on the same grid of ground:
--
--   Long memory  builds one mark per DAY you use a piece of ground, and loses
--                half its strength every 14 days you PLAY (days away don't
--                count). Nothing is permanent.
--     battle     where fighting happens: your kills and PvP deaths, plus your
--                guildmates' (theirs count for less, and never more than
--                yours). One red that deepens with use. Sightings don't count.
--     roads      stretches you travel THROUGH. A route used on two separate
--                days turns silver, then gilds gradually towards gold; well
--                worn gold is burnished and shines.
--   Short memory builds with every pass and fades on real time: a stretch
--                walked once stays about 7 hours (2 to 24 in options).
--     trail      today's footsteps in your faction's colour, vivid when fresh,
--                deepening after an hour and fading slowly over the trail
--                length, plus a solid line for your last 5 minutes.
--     runs       corpse runs (dashed ice blue) and flights (long gold dashes),
--                fading along their length over 24 hours, plus the flight
--                routes you keep taking.
--
--   marks      skulls where you died, blades where you scored honorable kills.
--   sightings  where you have seen hostile players.
--   guild      sightings, kills and deaths sent by guildmates who run Warpath.
--
-- Things the game does not let an addon know, and what Warpath does instead:
--   * What killed you. A death counts as PvP if you saw a hostile player in
--     the 20 seconds before it. The killer is the enemy you were fighting.
--   * Where an enemy is. A sighting is recorded at YOUR position.
--   * Who you killed. Read from your target, the last enemy you targeted, or
--     an enemy seen dying nearby. The game's honorable-kill counter says how
--     many died.
--
-- Other addons can hook kills:  Warpath.RegisterKillCallback(function(ctx) end)
--   ctx = { mapID, zone, x, y, time, streak, victim, victimFull, timesKilled }

local ADDON, ns = ...

-- Warpath is split across the files listed in Warpath.toc, loaded in that
-- order. They share one table, ns: constants in ns.C, changing state in
-- ns.S, saved data via ns.OnBind, and each file's functions as ns.<Name>.

local C = {
    GOLD = "|cffffd100",
    COMM = "WARPATH",
    PROTO = "1",
    SAMPLE_INTERVAL = 0.5,
    MIN_STEP        = 0.003,   -- map units; ignore smaller moves
    JUMP_STEP       = 0.08,    -- map units; bigger = teleport, break the stroke
    STROKE_MAX      = 300,     -- points per walking stroke
    RUN_MAX         = 1200,    -- points per corpse run or flight
    SIMPLIFY_TOL    = 0.0015,  -- map units; trail simplification tolerance
    KEEP_HOURS      = 24,      -- trail history kept (replay window)
    GW = 96, GH = 64,  -- travel heat grid
    SW = 48, SH = 32,  -- sighting heat grid
    ROAD_COOLDOWN   = 300,     -- seconds before the same stretch counts another pass
    DWELL_SAMPLES   = 40,      -- samples (20 s) in one cell = lingering there
    HIST            = 60,      -- samples (30 s) of position history
    TRAVEL_CELLS    = 3,       -- net cells moved in that time = travelling
    FRESH_SECONDS   = 300,     -- the solid line covers your last five minutes
    STEP_FADE       = 1800,    -- footsteps shrink from fresh size over 30 minutes (opacity: StepLook)
    STEP_VIVID      = 600,     -- ...and are vivid, with a dark rim, for the first 10
    STEP_DEEP       = 3600,    -- ...and deepen to the darker faction colour between 1 and 2 hours
    RECENT_CAP      = 30,      -- short memory saturates here
    RECENT_MIN      = 0.2,     -- short memory below this is not drawn
    HEAT_MIN        = 1.5,     -- long-memory strength before heat shows
    HEAT_FULL       = 10,
    ROAD_FULL       = 12,
    LN2             = math.log(2),
    LOG2_5          = math.log(5) / math.log(2), -- short memory 1 -> 0.2 (RECENT_MIN) takes this many half-lives
    SILVER_SHARE    = 0.6,     -- silver appears at this share of the gold threshold
    STEP_BUDGET     = 4000,
    SHOT_THROTTLE   = 1.5,     -- one screenshot per burst of kills
    COMBAT_GRACE    = 3,       -- seconds after combat that a kill still counts as yours
    MARK_CAP        = 300,
    LINE_BUDGET     = 5000,    -- roads and the walking line
    ROAD_RESERVE    = 800,     -- lines roads leave free for the walking line
    RUN_BUDGET      = 2500,    -- corpse runs, flights and flight routes
    GLINT_CAP       = 6,       -- amber glints per zone
    DOT_BUDGET      = 3500,
    MARK_BUDGET     = 400,
    CELL            = 0.04,    -- killing-field grid size
    FIELD_DAYS      = 30,
    FIELD_RADIUS    = 0.03,
    FIELD_COOLDOWN  = 600,
    PVP_WINDOW      = 20,      -- hostile player seen this recently = PvP death
    SIGHT_DEDUPE    = 120,     -- one sighting per player per this many seconds
    SIGHT_LIVE      = 900,     -- recent sightings shown as crests
    SHARED_DEATH    = 7200,    -- shared deaths shown this long
    AVENGE_WINDOW   = 300,
    AVENGE_RADIUS   = 0.10,
    GRUDGE_COOLDOWN = 60,
    REPLAY_SECONDS  = 20,
    ROUTE_MATCH     = 0.03,    -- flight stretches this close at both ends are one route
    ROUTE_MIN       = 4,       -- long memory before a flight route shows: about five
                               -- separate days of flying it within a couple of weeks
    ROUTE_OFF       = 2.5,     -- ...and it only goes again below this, fading on the way
    TRAIL_CHOICES   = { 2, 4, 7, 12, 24 }, -- hours a stretch walked once stays
    GRUDGE_SEEN     = 900,     -- a grudge sighting stays named on the map this long
    GRUDGE_LOG      = 30,      -- encounters kept per grudge
    BATTLE_MIN      = 0.6,     -- battle heat (spread, below) under this isn't drawn:
                               -- one kill shows faintly, a lone sighting doesn't
    BATTLE_FULL     = 4,       -- ...and is darkest from here (was 6 before 3.6.4)
    BATTLE_SPREAD   = 1.2,     -- each fight also warms the cells around it (Gaussian,
    BATTLE_REACH    = 2,       -- this many cells each way), so a running fight adds up
    BATTLE_ALPHA    = { 0.16, 0.42 }, -- faintest and darkest drawn patch (was 0.07-0.32)
    BATTLE_W        = { kill = 1, death = 1 }, -- heat each of your fights adds (3.7: sightings don't)
    -- Guildmates' haze (3.7): 3/4 of the strongest guildmate's heat on a spot,
    -- plus a little of everyone else's, never above this, so your own fights
    -- always read darkest at equal size.
    GUILD_TOP       = 0.75,
    GUILD_REST      = 0.15,
    GUILD_CAP       = 3.6,
    CHAIN           = 120,     -- kills within 2 minutes of the one before make a chain (double, triple...)
    SAME_VICTIM     = 10,      -- the same victim twice within this is one kill
    GROUND_GUILD    = 0.5,     -- a guildmate's death counts half of yours on dangerous ground
    CAMPAIGN_GAP    = 7200,    -- back within 2 hours = the same campaign
    CAMPAIGN_KEEP   = 30,
    ZONE_REENTRY    = 1800,    -- zone stats again after 30 minutes away
    SHARE_COOLDOWN  = 5,
    DAY             = 86400,
    TEX_SKULL  = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    TEX_BLADES = "Interface\\CURSOR\\Attack",
    TEX_GLOW   = "Interface\\Cooldown\\star4",
    TEX_STEP   = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",  -- solid round dot
    TEX_DOT    = "Interface\\AddOns\\" .. ADDON .. "\\glow",  -- soft radial glow shipped with the addon
    TEX_SWORDS = "Interface\\Icons\\Ability_DualWield",
    FACTION = {
        Horde    = { r = 1.00, g = 0.16, b = 0.10, deep = { 0.65, 0.03, 0.13 }, cry = "Lok'tar ogar!",     crest = "Interface\\TargetingFrame\\UI-PVP-Horde",    foe = "Alliance" },
        Alliance = { r = 0.25, g = 0.55, b = 1.00, deep = { 0.10, 0.22, 0.72 }, cry = "For the Alliance!", crest = "Interface\\TargetingFrame\\UI-PVP-Alliance", foe = "Horde" },
        Neutral  = { r = 1.00, g = 0.82, b = 0.00, deep = { 0.70, 0.50, 0.00 }, cry = "Victory!",          crest = "Interface\\TargetingFrame\\UI-PVP-FFA",      foe = "Neutral" },
    },
    -- Saved layer keys. "recent" and "shared" are typed as "trail" and "guild".
    LAYERS = { "battle", "roads", "recent", "runs", "marks", "sightings", "shared" },
    LAYER_NAMES = { battle = "battle", roads = "roads", recent = "trail", runs = "runs",
        marks = "marks", sightings = "sightings", shared = "guild" },
    LAYER_LABELS = { battle = "Battle haze", roads = "Silver and gold roads",
        recent = "Today's trail", runs = "Corpse runs and flights", marks = "Kills and deaths",
        sightings = "Recent enemy sightings", shared = "Guild sharing" },
    CFG_DEFAULTS = { sound = true, hudShown = true, quiet = false, share = false, shown = true,
        zoneChat = true, zoneText = true, chronLogin = true, chronOpen = false, shimmer = true,
        runHours = 24, flightHours = 24, fieldAlert = true,
        iconScale = 100, overlay = true, overlaySize = "medium",
        groundScreen = true, groundChat = true, groundAfter = 2,
        guildHaze = true, shareHistory = true },
    GRUDGE_DEFAULTS = { alert = true, again = 1, map = true, plates = true, auto = "off", after = 3 },
    SHOT_DEFAULTS = { on = true, mode = "all", card = "text", delay = 0.5, combat = true },
}
C.PREFIX = C.GOLD .. "Warpath|r: "
ns.C = C

-- State that several files read and change.
local S = { inInstance = false, ready = false, dirty = false, lastDraw = 0,
    lastCombatEnd = -1000, setupWaiting = false, hud = nil }
ns.S = S

-- Saved data and who you are. Set at load and login by Events.lua, then
-- handed to every file that registered with ns.OnBind.
local binders = {}
function ns.OnBind(fn) binders[#binders + 1] = fn end
function ns.Rebind() for _, fn in ipairs(binders) do fn() end end
local db, gdb, cfg
ns.OnBind(function() db, gdb, cfg = ns.db, ns.gdb, ns.cfg end)

local cur = { map = nil, stroke = nil, mode = nil, x = nil, y = nil, wx = nil, wy = nil, cell = nil }
local session = { kills = 0, deaths = 0, streak = 0, best = 0, start = 0, yards = 0, sightings = 0, avenged = 0, zones = {} }
local recentSight, shared, outQ = {}, {}, {}
local killCallbacks = {}
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "3.7.2"

local function Print(msg) print(C.PREFIX .. msg) end
local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Q(v) return math.floor(v * 10000 + 0.5) / 10000 end

local function MapName(id)
    local info = id and C_Map.GetMapInfo(id)
    return info and info.name or ("map " .. tostring(id))
end

local function Sound(name, fallback)
    if not cfg.sound or cfg.quiet or S.inInstance then return end
    local id = (SOUNDKIT and SOUNDKIT[name]) or fallback
    if id then pcall(PlaySound, id, "Master") end
end

-- Interface sounds (book, page turn) that are not alerts: only the sound
-- setting turns these off.
local function UISound(name, fallback)
    if not cfg.sound then return end
    local id = (SOUNDKIT and SOUNDKIT[name]) or fallback
    if id then pcall(PlaySound, id) end
end

-- A banner, or a chat line in quiet mode.
local function Notice(text, r, g, b)
    if S.inInstance then return end
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
    if S.inInstance then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or Secret(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or Secret(x) or Secret(y) or (x == 0 and y == 0) then return end
    return mapID, x, y
end

-- Is an addon-message sender you? On WoW Forever a character's name comes
-- back as "First Last" (with a space) and the realm reads as empty, so the
-- plain "Name-Realm" test missed your own guild messages echoing back (3.7.1).
-- Compared without spaces, dashes or case against every form of your name.
local sentRecent = {}  -- text -> when you sent it (guild echo check)
local function Norm(s) return (tostring(s or ""):gsub("[%s%-]", ""):lower()) end
local function IsMe(sender)
    local n = Norm(sender)
    if n == "" then return false end
    local me = ns.myName
    if n == Norm(me) or n == Norm(ns.myFull) or n == Norm(UnitName and UnitName("player")) then return true end
    local ok, a, b = pcall(UnitFullName, "player")
    if ok and type(a) == "string" and n == Norm(a .. (type(b) == "string" and b or "")) then return true end
    return false
end
-- A message you sent in the last 15 seconds, back from a sender whose name
-- begins with yours: your own guild message echoing back.
local function IsEcho(text, sender)
    local t = sentRecent[text]
    if not t or GetTime() - t > 15 then return false end
    local me = Norm(ns.myName)
    return me ~= "" and Norm(sender):sub(1, #me) == me
end
local function NoteSent(text)
    local now = GetTime()
    sentRecent[text] = now
    for k, t in pairs(sentRecent) do if now - t > 15 then sentRecent[k] = nil end end
end

local function Clamp01(v) return v < 0 and 0 or (v > 0.9999 and 0.9999 or v) end
local function Cell(x, y, gw, gh) return math.floor(Clamp01(y) * gh) * gw + math.floor(Clamp01(x) * gw) end
local function CellXY(c, gw, gh) return (c % gw + 0.5) / gw, (math.floor(c / gw) + 0.5) / gh end

local function Ago(t)
    local s = math.max(0, time() - t)
    if s < 90 then return s .. " sec ago" end
    if s < 5400 then return math.floor(s / 60 + 0.5) .. " min ago" end
    if s < 2 * C.DAY then return math.floor(s / 3600 + 0.5) .. " hr ago" end
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

local function ClassName(token)
    if not token then return end
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[token]) or (token:sub(1, 1) .. token:sub(2):lower())
end

local function ClassColor(token)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Miles(yards) return (yards or 0) / 1760 end

---------------------------------------------------------------------------
-- Zone data
---------------------------------------------------------------------------

-- Fields every zone has from 3.4 on.
local function ZoneFields(z)
    z.strokes, z.marks, z.heat, z.road = z.strokes or {}, z.marks or {}, z.heat or {}, z.road or {}
    z.cx, z.cy, z.sight = z.cx or {}, z.cy or {}, z.sight or {}
    z.runs, z.routes, z.battle = z.runs or {}, z.routes or {}, z.battle or {}
    z.deaths = z.deaths or {}
    z.yards, z.kills, z.pdeaths = z.yards or 0, z.kills or 0, z.pdeaths or 0
    z.streak, z.bestStreak, z.avenged = z.streak or 0, z.bestStreak or 0, z.avenged or 0
    z.hours = nil -- 3.4: enemy busy hours are no longer recorded
    z.heat = nil  -- 3.6: where you lingered is no longer recorded
    return z
end

local function ZoneData(mapID)
    local z = db.maps[mapID]
    if not z then
        z = ZoneFields({})
        db.maps[mapID] = z
    end
    return z
end

-- Douglas-Peucker on a flat {x1,y1,x2,y2,...} stroke, in place. A stroke's
-- per-point times (s.ts, seconds since s.t) are kept in step.
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
        if wi and worst > C.SIMPLIFY_TOL * C.SIMPLIFY_TOL then
            keep[wi] = true
            stack[#stack + 1] = a; stack[#stack + 1] = wi
            stack[#stack + 1] = wi; stack[#stack + 1] = b
        end
    end
    local out, ots, ts = {}, {}, s.ts
    for i = 1, n do
        if keep[i] then
            out[#out + 1] = s[2 * i - 1]
            out[#out + 1] = s[2 * i]
            if ts then ots[#ots + 1] = ts[i] or ts[#ts] end
        end
    end
    for i = #s, 1, -1 do s[i] = nil end
    for i = 1, #out do s[i] = out[i] end
    if ts then s.ts = ots end
end

-- Time of point i of a stroke, or nil when the stroke has no per-point times.
local function PointTime(s, i)
    local ts = s.ts
    if not ts then return end
    return s.t + (ts[i] or ts[#ts] or 0)
end

-- The play clock: real time while you play, but a calendar day you don't
-- play doesn't count. Built as (days played before today) + time of day, so
-- it runs smoothly through a session and past midnight. Long memory decays
-- on this clock, so time away costs nothing.
local playAt, playCache = -1, 0
local function SecondsToday(t)
    local d = date("*t", t)
    return d.hour * 3600 + d.min * 60 + d.sec
end
local function PlayNow()
    local now = time()
    if now == playAt then return playCache end
    local p = db.play
    if not p then
        p = { days = 0, day = tonumber(date("%y%j", now)), base = now - SecondsToday(now) }
        db.play = p
    end
    local today = tonumber(date("%y%j", now))
    if p.day ~= today then
        p.days, p.day = p.days + 1, today
    end
    playAt, playCache = now, p.base + p.days * C.DAY + SecondsToday(now)
    return playCache
end

-- Current strength of a record's long and short memory. (Long ignores the
-- time passed in: it always uses the play clock.)
local function Long(e)
    if not e.l or e.l <= 0 then return 0 end
    return e.l * math.exp(-C.LN2 * (PlayNow() - e.tl) / (db.longDays * C.DAY))
end

-- Footstep look by time since you last walked there: alpha, size scale,
-- vividness (1 = just walked: pure faction colour with a dark rim) and
-- depth (1 = the deep, darker faction colour of older steps).
-- 3.6.3: steps fade slowly over the whole trail length instead of dropping
-- to a faint floor within 30 minutes. With a 24-hour trail: 90% at 1 hour,
-- 75% at 6, 55% at 12, 35% at 18, gone at 24. Shorter trails scale the same.
local STEP_CURVE = { { 0, 0.95 }, { 0.04, 0.90 }, { 0.25, 0.75 }, { 0.50, 0.55 }, { 0.75, 0.35 }, { 1, 0 } }
local function StepLook(e, now)
    local age = now - (e.tp or e.tr or now)
    local vivid = 0
    if age < C.STEP_VIVID then vivid = 0.5 * (1 + math.cos(math.pi * age / C.STEP_VIVID)) end
    local f = age / ((cfg.trailHours or 7) * 3600)
    local alpha = 0
    if f < 1 then
        for i = 2, #STEP_CURVE do
            local a, b = STEP_CURVE[i - 1], STEP_CURVE[i]
            if f <= b[1] then alpha = a[2] + (b[2] - a[2]) * (f - a[1]) / (b[1] - a[1]) break end
        end
    end
    local k = age < C.STEP_FADE and 0.5 * (1 + math.cos(math.pi * age / C.STEP_FADE)) or 0
    local d = math.max(0, math.min(1, (age - C.STEP_DEEP) / C.STEP_DEEP))
    return alpha, 0.9 + 0.25 * k, vivid, d * d * (3 - 2 * d)
end

-- Short memory's half-life from the trail setting: a stretch walked once
-- fades from 1 to RECENT_MIN in cfg.trailHours.
local function Recent(e, now)
    if not e.r or e.r <= 0 then return 0 end
    local half = (cfg.trailHours or 7) * 3600 / C.LOG2_5
    return e.r * math.exp(-C.LN2 * (now - e.tr) / half)
end

-- One mark per calendar day you play, on top of whatever has not yet faded.
local function Credit(e, now, today)
    if e.d == today then return end
    e.l, e.tl, e.d = Long(e) + 1, PlayNow(), today
end

-- Battle heat: each fight adds to its spot; fades on the play clock like roads.
-- e.ts: when it last changed (real time), so a guild sync sends only what's new.
local function AddHeat(layer, c, w)
    local e = layer[c]
    if not e then e = { l = 0, tl = PlayNow() } layer[c] = e end
    e.l, e.tl, e.ts = Long(e) + w, PlayNow(), time()
    S.dirty = true
end

local function AddBattle(mapID, x, y, w)
    if not mapID or not x or not y then return end
    AddHeat(ZoneData(mapID).battle, Cell(x, y, C.SW, C.SH), w)
end

-- Your PvP deaths on the same grid (3.7): what dangerous ground is made of.
local function AddDeathHeat(mapID, x, y, w)
    if not mapID or not x or not y then return end
    AddHeat(ZoneData(mapID).deaths, Cell(x, y, C.SW, C.SH), w)
end

-- A guildmate's layer, from their live kills and deaths and their synced
-- history: z.guildBattle[sender] / z.guildDeaths[sender], cell -> { l, tl }.
local function GuildLayer(mapID, key, sender)
    local z = ZoneData(mapID)
    z[key] = z[key] or {}
    local t = z[key][sender]
    if not t then t = {} z[key][sender] = t end
    return t
end

-- The guild part of a spot: 3/4 of the strongest guildmate, 0.15 of the rest, capped.
local function GuildPart(layers, out, town)
    if not layers then return end
    local top, sum = {}, {}
    for _, cells in pairs(layers) do
        for c, e in pairs(cells) do
            if not town[c] then
                local v = Long(e)
                if v > 0 then
                    sum[c] = (sum[c] or 0) + v
                    if v > (top[c] or 0) then top[c] = v end
                end
            end
        end
    end
    for c, t in pairs(top) do
        local g = math.min(C.GUILD_CAP, C.GUILD_TOP * t + C.GUILD_REST * (sum[c] - t))
        if g > 0 then out[c] = (out[c] or 0) + g end
    end
end

-- Spread raw cell values over their neighbours (3.6.4). Only cells with a
-- value of their own are returned, so the haze never reaches ground where
-- nothing happened.
local function Spread(raw)
    local out = {}
    local R, k = C.BATTLE_REACH, -1 / (2 * C.BATTLE_SPREAD * C.BATTLE_SPREAD)
    for c in pairs(raw) do
        local cx, cy = c % C.SW, math.floor(c / C.SW)
        local v = 0
        for dy = -R, R do
            local y = cy + dy
            if y >= 0 and y < C.SH then
                for dx = -R, R do
                    local x = cx + dx
                    local n = x >= 0 and x < C.SW and raw[y * C.SW + x]
                    if n then v = v + n * math.exp(k * (dx * dx + dy * dy)) end
                end
            end
        end
        out[c] = v
    end
    return out
end

-- One layer of heat, faded, with neutral-town ground (z.town) left out:
-- seeing the enemy there is expected, so it doesn't haze the map. Its heat
-- stays saved.
local function Own(layer, town, w)
    local raw = {}
    for c, e in pairs(layer or {}) do
        local v = not town[c] and Long(e) or 0
        if v > 0 then raw[c] = v * (w or 1) end
    end
    return raw
end

-- The haze as drawn: your heat plus the guild part (when shown), spread.
-- guild: nil = follow the setting, false = yours only.
local function BattleField(z, guild)
    local town = z.town or {}
    local raw = Own(z.battle, town)
    if guild ~= false and cfg.guildHaze then GuildPart(z.guildBattle, raw, town) end
    return Spread(raw)
end

-- Your deaths, and guildmates' deaths (half weight, capped like the haze), spread.
local function DeathField(z)
    local town = z.town or {}
    local mine = Spread(Own(z.deaths, town))
    local graw = {}
    GuildPart(z.guildDeaths, graw, town)
    for c, v in pairs(graw) do graw[c] = v / C.GUILD_TOP * C.GROUND_GUILD end
    return mine, Spread(graw)
end

local function RunSeconds(kind)
    return (kind == "f" and cfg.flightHours or cfg.runHours) * 3600
end

local function Prune()
    local now = time()
    local cutoff = now - C.KEEP_HOURS * 3600
    for _, z in pairs(db.maps) do
        local kept = {}
        for _, s in ipairs(z.strokes) do
            if s.e >= cutoff then kept[#kept + 1] = s end
        end
        z.strokes = kept
        kept = {}
        for _, s in ipairs(z.runs) do
            if now - s.e < RunSeconds(s.k) then kept[#kept + 1] = s end
        end
        z.runs = kept
        kept = {}
        for _, r in ipairs(z.routes) do
            if Long(r, now) >= 0.05 then kept[#kept + 1] = r end
        end
        z.routes = kept
        while #z.marks > C.MARK_CAP do table.remove(z.marks, 1) end
        for edge, e in pairs(z.road) do
            if Long(e, now) < 0.05 and Recent(e, now) < 0.05 then z.road[edge] = nil end
        end
        for c, e in pairs(z.battle) do
            if Long(e) < 0.05 then z.battle[c] = nil end
        end
        for c, e in pairs(z.deaths) do
            if Long(e) < 0.05 then z.deaths[c] = nil end
        end
        for _, key in ipairs({ "guildBattle", "guildDeaths" }) do
            for sender, cells in pairs(z[key] or {}) do
                for c, e in pairs(cells) do
                    if Long(e) < 0.05 then cells[c] = nil end
                end
                if next(cells) == nil then z[key][sender] = nil end
            end
        end
    end
    for i = #shared, 1, -1 do
        if shared[i].expire < now then table.remove(shared, i) end
    end
    for i = #recentSight, 1, -1 do
        if now - recentSight[i].t > C.SIGHT_LIVE then table.remove(recentSight, i) end
    end
    if cur.map and db.maps[cur.map] and cur.stroke then
        local z, found = db.maps[cur.map], false
        for _, s in ipairs(cur.stroke.k and z.runs or z.strokes) do
            if s == cur.stroke then found = true break end
        end
        if not found then cur.stroke = nil end
    end
end

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------

-- v1/v2 kept every point forever; v3 stored raw counts. Bring them to v4.
local function MigrateToV4()
    if db.v == 3 then
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
        z.heat, z.sight = z.heat or {}, z.sight or {}
        z.kills, z.pdeaths, z.yards = z.kills or 0, z.pdeaths or 0, z.yards or 0
        z.points = nil
        for _, s in ipairs(z.strokes or {}) do
            s.e = s.e or s.t
            local last
            if s.k ~= "f" and s.k ~= "g" then
                for i = 1, #s - 1, 2 do
                    local c = Cell(s[i], s[i + 1], C.GW, C.GH)
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

-- A 3.3 session summary as a 3.4 campaign (totals only).
local function OldCampaign(s)
    if type(s) ~= "table" or not s.start then return end
    local stop = s.stop or s.start
    return { start = s.start, stop = stop, played = math.max(0, stop - s.start), cur = 0,
        kills = s.kills or 0, deaths = s.deaths or 0, best = s.best or 0, streak = 0,
        yards = s.yards or 0, sightings = s.sightings or 0, avenged = s.avenged or 0,
        grudges = 0, zoneCount = s.zones or 0, zones = {}, kl = {}, dl = {}, old = true }
end

-- 3.4 (db.v 5). Everything new is built on the side and swapped in only
-- when all of it worked; the 3.3 session fields stay for one release.
local function MigrateToV5()
    local maps = {}
    -- Corpse runs and flights move out of the trail into their own store.
    for mapID, z in pairs(db.maps) do
        local strokes, runs = {}, {}
        for _, s in ipairs(z.strokes or {}) do
            if s.k == "g" or s.k == "f" then
                local r = { t = s.t, e = s.e or s.t, k = s.k, ts = {} }
                local n = #s / 2
                for i = 1, n do
                    r[2 * i - 1], r[2 * i] = s[2 * i - 1], s[2 * i]
                    r.ts[i] = n > 1 and math.floor((r.e - r.t) * (i - 1) / (n - 1) + 0.5) or 0
                end
                runs[#runs + 1] = r
            else
                strokes[#strokes + 1] = s
            end
        end
        maps[mapID] = { strokes = strokes, runs = runs, avenged = 0, bestStreak = 0 }
    end
    -- Deaths avenged and best streak per zone, replayed from the marks.
    local events = {}
    for mapID, z in pairs(db.maps) do
        for _, m in ipairs(z.marks or {}) do
            if m[4] == "kill" then
                events[#events + 1] = { t = m[3], map = mapID, kill = true }
            elseif m.pvp then
                events[#events + 1] = { t = m[3], map = mapID }
                if m.av then maps[mapID].avenged = maps[mapID].avenged + 1 end
            end
        end
    end
    table.sort(events, function(a, b) return a.t < b.t end)
    local run = {}
    for _, ev in ipairs(events) do
        if ev.kill then
            run[ev.map] = (run[ev.map] or 0) + 1
            if run[ev.map] > maps[ev.map].bestStreak then maps[ev.map].bestStreak = run[ev.map] end
        else
            run = {}
        end
    end
    -- The last two 3.3 sessions become campaigns.
    local open = OldCampaign(db.lastSession)
    local prev = OldCampaign(db.prevSession)

    -- Everything worked: switch over.
    for mapID, z in pairs(db.maps) do
        local m = maps[mapID]
        z.strokes, z.runs = m.strokes, m.runs
        z.avenged, z.bestStreak, z.streak = m.avenged, m.bestStreak, run[mapID] or 0
        ZoneFields(z)
    end
    db.campaigns = db.campaigns or {}
    if prev and prev.kills + prev.deaths + prev.sightings > 0 then table.insert(db.campaigns, 1, prev) end
    if open then db.campaign = open end
    db.v = 5
end

-- 3.5 (db.v 6): long memory moves to the play clock. The clock starts equal
-- to real time, so every stored strength stays exactly as it was.
local function MigrateToV6()
    if not db.play then
        local now = time()
        db.play = { days = 0, day = tonumber(date("%y%j", now)), base = now - SecondsToday(now) }
    end
    db.v = 6
end

-- 3.6 (db.v 7): the battle haze, back-filled from your kill and death marks
-- (each faded by its age) and your sighting counts (no times: counted as
-- about a month old). The lingering haze goes.
local function MigrateToV7()
    local now, half = time(), db.longDays * C.DAY
    local W = C.BATTLE_W
    for _, z in pairs(db.maps) do
        local heat = {}
        for _, m in ipairs(z.marks or {}) do
            if m[4] == "kill" or m.pvp then
                local c = Cell(m[1], m[2], C.SW, C.SH)
                local age = math.max(0, now - (m[3] or now))
                heat[c] = (heat[c] or 0) + W.kill * 2 ^ (-age / half)
            end
        end
        for c, n in pairs(z.sight or {}) do
            heat[c] = (heat[c] or 0) + 0.25 * n * 0.25 -- 3.6 counted sightings a quarter
        end
        z.battle = {}
        for c, l in pairs(heat) do
            if l >= 0.05 then z.battle[c] = { l = l, tl = PlayNow() } end
        end
        z.heat = nil
    end
    db.v = 7
end

-- 3.7 (db.v 8): dangerous ground, back-filled from your PvP death marks
-- (each faded by its age). Nothing is removed or converted.
local function MigrateToV8()
    local now, half = time(), db.longDays * C.DAY
    for _, z in pairs(db.maps) do
        local heat = {}
        for _, m in ipairs(z.marks or {}) do
            if m[4] == "death" and m.pvp then
                local c = Cell(m[1], m[2], C.SW, C.SH)
                local age = math.max(0, now - (m[3] or now))
                heat[c] = (heat[c] or 0) + 2 ^ (-age / half)
            end
        end
        z.deaths = {}
        for c, l in pairs(heat) do
            if l >= 0.05 then z.deaths[c] = { l = l, tl = PlayNow() } end
        end
    end
    db.v = 8
end

-- 3.7.1 (db.v 9): the haze rebuilt from your kill and death marks, which is
-- all 3.7 counts. The old haze had enemy sightings (3.6 counted each one a
-- quarter of a kill) and your own guild messages echoing back (counted again
-- as a guildmate's) mixed in, so a spot where you once died and saw a lot of
-- enemies read as a war zone. The old haze is kept as z.battleOld, hidden.
local function MigrateToV9()
    local now, half = time(), db.longDays * C.DAY
    for _, z in pairs(db.maps) do
        if z.battleOld == nil then z.battleOld = z.battle or {} end
        local heat = {}
        for _, m in ipairs(z.marks or {}) do
            if m[4] == "kill" or m.pvp then
                local c = Cell(m[1], m[2], C.SW, C.SH)
                local age = math.max(0, now - (m[3] or now))
                heat[c] = (heat[c] or 0) + 2 ^ (-age / half)
            end
        end
        z.battle = {}
        for c, l in pairs(heat) do
            if l >= 0.05 then z.battle[c] = { l = l, tl = PlayNow(), ts = now } end
        end
    end
    db.v = 9
end

local function Migrate()
    if db.v ~= 4 and db.v ~= 5 and db.v ~= 6 and db.v ~= 7 and db.v ~= 8 and db.v ~= 9 then MigrateToV4() end
    if db.v == 4 then
        local ok, err = pcall(MigrateToV5)
        if not ok then
            Print("the 3.4 upgrade of your saved data hit an error, so new features start fresh: " .. tostring(err))
            db.v = 5
        end
    end
    if db.v == 5 then MigrateToV6() end
    if db.v == 6 then
        local ok, err = pcall(MigrateToV7)
        if not ok then Print("the 3.6 upgrade hit an error, so the battle haze starts empty: " .. tostring(err)) db.v = 7 end
    end
    if db.v == 7 then
        local ok, err = pcall(MigrateToV8)
        if not ok then Print("the 3.7 upgrade hit an error, so dangerous ground starts empty: " .. tostring(err)) db.v = 8 end
    end
    if db.v == 8 then
        local ok, err = pcall(MigrateToV9)
        if not ok then Print("the 3.7.1 haze rebuild hit an error, so the haze is as it was: " .. tostring(err)) db.v = 9 end
    end
    for _, z in pairs(db.maps) do ZoneFields(z) end
    db.campaigns = db.campaigns or {}
end

-- Shared with the other files.
ns.IsMe = IsMe
ns.IsEcho = IsEcho
ns.NoteSent = NoteSent
ns.AddBattle = AddBattle
ns.AddDeathHeat = AddDeathHeat
ns.AddHeat = AddHeat
ns.BattleField = BattleField
ns.DeathField = DeathField
ns.GuildLayer = GuildLayer
ns.Spread = Spread
ns.Ago = Ago
ns.Cell = Cell
ns.CellXY = CellXY
ns.ClassColor = ClassColor
ns.ClassName = ClassName
ns.Credit = Credit
ns.FullName = FullName
ns.Long = Long
ns.MapName = MapName
ns.Migrate = Migrate
ns.Miles = Miles
ns.Notice = Notice
ns.PlayNow = PlayNow
ns.PlayerPos = PlayerPos
ns.PointTime = PointTime
ns.Print = Print
ns.Prune = Prune
ns.Q = Q
ns.Recent = Recent
ns.RunSeconds = RunSeconds
ns.Secret = Secret
ns.Simplify = Simplify
ns.Sound = Sound
ns.StepLook = StepLook
ns.UISound = UISound
ns.VERSION = VERSION
ns.Waypoint = Waypoint
ns.WorldXY = WorldXY
ns.ZoneData = ZoneData
ns.cur = cur
ns.killCallbacks = killCallbacks
ns.outQ = outQ
ns.recentSight = recentSight
ns.session = session
ns.shared = shared
