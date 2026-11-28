-- Warpath: Ledger
-- The figures the chronicle's Ledger tab shows (3.8.5), worked out from a
-- character's saved data. Drawing is Chronicle's job; this file only counts.
-- See docs/design/chronicle-ledger.md for what each figure means.
--
-- Ledger.Stats(db, gdb, opt) -> s, plain tables. opt (all optional):
-- me (your name as the guild sees it, default ns.myName), roster (the list
-- Ledger.Roster() returns; default: read from the client), guild (false:
-- leave s.guild out). Names are saved keys ("Name-Realm" or "First Last"),
-- never display names. Times are time() seconds; hours and dates local.
--
--   s.tally      kills, deaths, best (best streak), kd (kills / deaths, nil
--                with no deaths), foes (different foes slain), avenged,
--                wilds (deaths not counted as PvP), yards, sightings,
--                shots (account-wide), flights, runs, spirit, ghostYards
--   s.first      the earliest kill or death mark's time, or nil
--   s.multi      [2] doubles, [3] triples, [4] quads, [5] bloodbaths: each
--                chain once, at the tier it ended on
--   s.multiLast  [tier] = when that tier was last reached
--   s.streaks    [3], [5], [10], [15], [20]: every time a streak reached
--                that title (Legend of the Warpath: 20, 30, 40...)
--   s.streakLast [tier] = when
--   s.records    by key, each only once it has a value (see RULES):
--                firstBlood { t, map, n, f }; bloodiest { kills, start };
--                hour { n, t }; longest { n, t, map, shot } (the
--                latest time it was reached); worst
--                { deaths, kills, start }; smallest { lv, t, map, n, f, c,
--                ra, gu }; longNight { played, start }; farthest { yards,
--                start }; mostSeen { n, start }; revenge { av, t, map, n, f };
--                closest { hp, t, map, n, f }; odds { foes, friends, t, map,
--                n, f }; gap { gap, lv, my, t, map, n, f, c }
--   s.hours      [0..23] kills by local hour
--   s.weekdays   [1..7] kills by day of the week, 1 = Monday
--   s.calendar   ["YYYY-MM-DD"] = { k, d (PvP deaths), field (a campaign
--                spanned the day), zones = { [mapID] = true } }
--   s.slain      [class token or "unknown"] = kills; s.slew: PvP deaths
--   s.lands      [mapID] = { kills, deaths, best, foes (different foes),
--                wilds, yards, sightings, gkills (guildmates' kills),
--                runs (corpse runs), top = { f, n, count } (slain most here) }
--   s.continents [continent mapID] = { kills, deaths, lands = { mapID... }
--                (by kills + deaths, then name), bloodiest = mapID or nil }
--   s.foes       slain / struck: up to ten { f, n, count, last, c, lv, gu },
--                by count, then latest first. Struck counts are
--                WarpathGlobal.killers (account-wide); details from this
--                character's PvP death marks.
--   s.who        levels ("60", "51-59", "41-50", "31-40", "21-30", "1-20",
--                "unknown"), races (or "unknown"), guilds (or "none")
--   s.wilds      total, unrecorded, causes = { { cause, how, kind, n } } (most
--                first), lands = { [mapID] = n }, hours = { [h] = n }
--   s.guild      first (earliest pin), mates = { { name, full, kills,
--                deaths, victims = { { n, c, t } }, level, class, rank, note,
--                me } } by kills, lands = { [mapID] = { kills, deaths } },
--                hours = { [h] = kills }, inGuild
--
-- Ledger.Summarize() keeps this character's Stats (without the guild and
-- the per-land details only this character's view shows) in
-- WarpathGlobal.chars["Name-Realm"], at login and logout.
-- Ledger.Account(gdb) adds every character's summary together, as the
-- spec's "This character or all characters" says: the same shape as Stats,
-- with chars = { names }, failed = { names whose summary couldn't be made },
-- no guild, and "char" on every record (whose it is).
local ADDON, ns = ...
local C, S = ns.C, ns.S

local Ledger = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local STREAK_TIERS = { 3, 5, 10, 15, 20 }
local BANDS = { "60", "51-59", "41-50", "31-40", "21-30", "1-20", "unknown" }
Ledger.CLASSES, Ledger.STREAK_TIERS, Ledger.BANDS = CLASSES, STREAK_TIERS, BANDS

local function Band(lv)
    if type(lv) ~= "number" or lv < 1 then return "unknown" end -- -1 ("??") isn't a level
    if lv >= 60 then return "60" end
    if lv <= 20 then return "1-20" end
    local lo = math.floor((lv - 1) / 10) * 10 + 1
    return lo .. "-" .. math.min(lo + 9, 59) -- 51-59: 60 is its own band
end

local function Add(t, k, n) t[k] = (t[k] or 0) + (n or 1) end

local function Weekday(t) return (tonumber(date("%w", t)) + 6) % 7 + 1 end -- 1 = Monday
local function Hour(t) return tonumber(date("%H", t)) end
local function Day(t) return date("%Y-%m-%d", t) end

local function StreakTier(n)
    if type(n) ~= "number" then return end
    if n >= 20 then return n % 10 == 0 and 20 or nil end
    for _, s in ipairs(STREAK_TIERS) do if s == n then return s end end
end

-- The continent a map is on, or nil for a continent or the world itself.
local function ContinentOf(id)
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if not ok or not info or (info.mapType or 3) <= 2 then return end
    for _ = 1, 8 do
        local parent = info.parentMapID
        if not parent or parent == 0 then return end
        ok, info = pcall(C_Map.GetMapInfo, parent)
        if not ok or not info then return end
        if info.mapType == 2 then return parent end
    end
end
Ledger.ContinentOf = ContinentOf

-- A zone, city or smaller: not a continent or the world.
local function IsLand(id)
    local ok, info = pcall(C_Map.GetMapInfo, id)
    return not (ok and info and info.mapType and info.mapType <= 2)
end

---------------------------------------------------------------------------
-- Records: which of two is the better. Ties go to the earlier one.
---------------------------------------------------------------------------

local RULES = {
    firstBlood = { "t", -1 }, bloodiest = { "kills", 1 }, hour = { "n", 1 }, longest = { "n", 1 },
    smallest = { "lv", -1 }, longNight = { "played", 1 }, farthest = { "yards", 1 }, mostSeen = { "n", 1 },
    revenge = { "av", -1 }, closest = { "hp", -1 }, gap = { "gap", 1 },
}

local function When(r) return r.t or r.start or math.huge end

local function Better(key, a, b)
    if not b then return true end
    local rule = RULES[key]
    local va, vb
    if rule then
        va, vb = a[rule[1]] * rule[2], b[rule[1]] * rule[2]
    elseif key == "worst" then -- most deaths, then fewer kills
        va, vb = a.deaths * 1000 - a.kills, b.deaths * 1000 - b.kills
    elseif key == "odds" then -- most enemies to allies, then most enemies
        va, vb = a.foes / a.friends, b.foes / b.friends
        if va == vb then va, vb = a.foes, b.foes end
    end
    if va ~= vb then return va > vb end
    return When(a) < When(b)
end

local function Offer(recs, key, r)
    if Better(key, r, recs[key]) then recs[key] = r end
end
Ledger.Better = Better

---------------------------------------------------------------------------
-- One character
---------------------------------------------------------------------------

local function Empty()
    return {
        tally = { kills = 0, deaths = 0, best = 0, foes = 0, avenged = 0, wilds = 0, yards = 0, sightings = 0,
                  shots = 0, flights = 0, runs = 0, spirit = 0, ghostYards = 0 },
        multi = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 }, multiLast = {},
        streaks = { [3] = 0, [5] = 0, [10] = 0, [15] = 0, [20] = 0 }, streakLast = {},
        records = {}, hours = {}, weekdays = {}, calendar = {}, slain = {}, slew = {}, lands = {},
        foes = { slain = {}, struck = {} },
        who = { levels = {}, races = {}, guilds = {} },
        wilds = { total = 0, unrecorded = 0, causes = {}, lands = {}, hours = {} },
    }
end

local function CalDay(s, t)
    local key = Day(t)
    local d = s.calendar[key]
    if not d then d = { k = 0, d = 0, zones = {} } s.calendar[key] = d end
    return d
end

-- Days a campaign spanned are days in the field.
local function FieldDays(s, c)
    if not c.start then return end
    local stop = c.stop or time()
    local t = c.start
    for _ = 1, 62 do
        CalDay(s, t).field = true
        local d = date("*t", t)
        t = time({ year = d.year, month = d.month, day = d.day + 1, hour = 0 })
        if t > stop then break end
    end
end

local function Campaigns(db)
    local list = {}
    if db.campaign then list[#list + 1] = db.campaign end
    for _, c in ipairs(db.campaigns or {}) do list[#list + 1] = c end
    return list
end

local function CampaignRecords(s, db)
    for _, c in ipairs(Campaigns(db)) do
        FieldDays(s, c)
        local start, kills, deaths = c.start, c.kills or 0, c.deaths or 0
        -- records are nights of war: a campaign with no fight sets none, so
        -- a character who never fought has "No records yet" (the spec)
        if start and kills + deaths > 0 then
            if kills > 0 then Offer(s.records, "bloodiest", { kills = kills, start = start }) end
            if deaths > 0 then Offer(s.records, "worst", { deaths = deaths, kills = kills, start = start }) end
            if (c.played or 0) > 0 then Offer(s.records, "longNight", { played = c.played, start = start }) end
            if (c.yards or 0) > 0 then Offer(s.records, "farthest", { yards = c.yards, start = start }) end
            if (c.sightings or 0) > 0 then Offer(s.records, "mostSeen", { n = c.sightings, start = start }) end
        end
    end
end

-- The most kills in any hour starting at a kill.
local function HourRecord(s, times)
    table.sort(times)
    local j = 1
    for i = 1, #times do
        if j < i then j = i end
        while times[j + 1] and times[j + 1] < times[i] + 3600 do j = j + 1 end
        Offer(s.records, "hour", { n = j - i + 1, t = times[i] })
    end
end

local function KillMark(s, m, mapID, land, here, info, times, chains)
    local t = m[3]
    times[#times + 1] = t
    local c = m.c or "unknown"
    Add(s.slain, c)
    Add(s.hours, Hour(t))
    Add(s.weekdays, Weekday(t))
    local day = CalDay(s, t)
    day.k = day.k + 1
    day.zones[mapID] = true
    Add(s.who.levels, Band(m.lv))
    Add(s.who.races, m.ra or "unknown")
    Add(s.who.guilds, m.gu or "none")
    -- multi-kills: a mark with mk = n is the chain reaching n
    if m.mk then
        Add(chains, m.mk)
        local n = math.min(m.mk, 5)
        if not s.multiLast[n] or t > s.multiLast[n] then s.multiLast[n] = t end
    end
    local st = StreakTier(m.streak)
    if st then
        Add(s.streaks, st)
        if not s.streakLast[st] or t > s.streakLast[st] then s.streakLast[st] = t end
    end
    local who = m.f or m.n
    if who then
        here.foes[who] = true
        Add(here.count, who)
        local h = here.count[who]
        local top = land.top
        if not top or h > top.count or (h == top.count and t > top.t) then
            land.top = { f = m.f, n = m.n, count = h, t = t }
        end
    end
    if m.f then
        local i = info[m.f]
        if not i or t > i.last then info[m.f] = { last = t, n = m.n, c = m.c, lv = m.lv, gu = m.gu } end
    end
    local where = { t = t, map = mapID, n = m.n, f = m.f }
    Offer(s.records, "firstBlood", where)
    if type(m.lv) == "number" and m.lv > 0 then
        Offer(s.records, "smallest", { lv = m.lv, t = t, map = mapID, n = m.n, f = m.f, c = m.c, ra = m.ra, gu = m.gu })
        if m.my and m.lv > m.my then
            Offer(s.records, "gap", { gap = m.lv - m.my, lv = m.lv, my = m.my, t = t, map = mapID, n = m.n, f = m.f, c = m.c })
        end
    end
    if m.av then Offer(s.records, "revenge", { av = m.av, t = t, map = mapID, n = m.n, f = m.f }) end
    if m.hp then Offer(s.records, "closest", { hp = m.hp, t = t, map = mapID, n = m.n, f = m.f }) end
    local o = m.odds
    if type(o) == "table" and o[1] and o[2] and o[2] > 0 and o[1] > o[2] then
        Offer(s.records, "odds", { foes = o[1], friends = o[2], t = t, map = mapID, n = m.n, f = m.f })
    end
end

local function DeathMark(s, m, mapID, land, struckInfo)
    local t = m[3]
    if m.pvp then
        Add(s.slew, m.kc or "unknown")
        local day = CalDay(s, t)
        day.d = day.d + 1
        day.zones[mapID] = true
        if m.kf then
            local i = struckInfo[m.kf]
            if not i or t > i.last then struckInfo[m.kf] = { last = t, n = m.kn, c = m.kc, lv = m.lv, gu = m.gu } end
        end
        return
    end
    s.tally.wilds = s.tally.wilds + 1
    land.wilds = land.wilds + 1
    local w = s.wilds
    w.total = w.total + 1
    Add(w.lands, mapID)
    Add(w.hours, Hour(t))
    if m.how then
        local key = m.how .. "|" .. (m.cause or "")
        w.byKey = w.byKey or {}
        local e = w.byKey[key]
        if not e then
            e = { cause = m.cause, how = m.how, kind = m.ct, n = 0 }
            w.byKey[key] = e
        end
        e.n = e.n + 1
    else
        w.unrecorded = w.unrecorded + 1
    end
end

-- Top ten by count, then latest first.
local function TopTen(counts, info)
    local list = {}
    for f, n in pairs(counts) do
        local i = info[f] or {}
        list[#list + 1] = { f = f, n = i.n, count = n, last = i.last, c = i.c, lv = i.lv, gu = i.gu }
    end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        if (a.last or 0) ~= (b.last or 0) then return (a.last or 0) > (b.last or 0) end
        return a.f < b.f
    end)
    for i = #list, 11, -1 do list[i] = nil end
    return list
end

-- Figures worked out from the rest: kill-death ratio, the multi-kill
-- tiers, wilds causes in order, continents. Run on one character and on
-- the account's sum.
local function Finish(s)
    local t = s.tally
    t.kd = t.deaths > 0 and t.kills / t.deaths or nil
    local w = s.wilds
    if w.byKey then
        local list = {}
        for _, e in pairs(w.byKey) do list[#list + 1] = e end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return (a.how .. (a.cause or "")) < (b.how .. (b.cause or ""))
        end)
        w.causes, w.byKey = list, nil
    end
    local conts = {}
    for id, land in pairs(s.lands) do
        local cont = ContinentOf(id)
        if cont then
            local c = conts[cont]
            if not c then c = { kills = 0, deaths = 0, lands = {} } conts[cont] = c end
            c.kills, c.deaths = c.kills + land.kills, c.deaths + land.deaths
            c.lands[#c.lands + 1] = id
        end
    end
    for _, c in pairs(conts) do
        local L = s.lands
        table.sort(c.lands, function(a, b)
            local fa, fb = L[a].kills + L[a].deaths, L[b].kills + L[b].deaths
            if fa ~= fb then return fa > fb end
            local na, nb = ns.MapName(a), ns.MapName(b)
            if na ~= nb then return na < nb end
            return a < b
        end)
        local first = c.lands[1]
        c.bloodiest = first and (L[first].kills + L[first].deaths) > 0 and first or nil
    end
    s.continents = conts
    return s
end

-- Guildmates' pins and the roster. me: your name as the guild knows it.
local function Norm(n) return (tostring(n or ""):gsub("[%s%-]", ""):lower()) end

local function Guild(db, me, roster)
    local g = { mates = {}, lands = {}, hours = {}, inGuild = IsInGuild and IsInGuild() and true or false }
    local by = {}
    local function Mate(name, full)
        local key = Norm(name)
        local e = by[key]
        if not e then
            e = { name = name, full = full, kills = 0, deaths = 0, victims = {} }
            by[key] = e
            g.mates[#g.mates + 1] = e
        end
        return e
    end
    for mapID, z in pairs(db.maps or {}) do
        for _, p in ipairs(z.gmarks or {}) do
            if p.from and (p.kind == "K" or p.kind == "D") then
                if not g.first or (p.t or 0) < g.first then g.first = p.t end
                local land = g.lands[mapID]
                if not land then land = { kills = 0, deaths = 0 } g.lands[mapID] = land end
                local e = Mate(p.from, p.full)
                if p.kind == "K" then
                    e.kills, land.kills = e.kills + 1, land.kills + 1
                    if p.t then Add(g.hours, Hour(p.t)) end
                    if p.vn or p.vc then e.victims[#e.victims + 1] = { n = p.vn, c = p.vc, t = p.t } end
                else
                    e.deaths, land.deaths = e.deaths + 1, land.deaths + 1
                end
            end
        end
    end
    -- you, with your own counts
    if me then
        local e = Mate(me, ns.myFull)
        e.kills, e.deaths, e.me = db.kills or 0, db.deaths or 0, true
    end
    local info = {}
    for _, r in ipairs(roster or {}) do if r[1] then info[Norm(r[1])] = r end end
    for _, e in ipairs(g.mates) do
        local r = info[Norm(e.name)] or (e.full and info[Norm(e.full)])
        if r then e.rank, e.level, e.class, e.note = r[2], r[3], r[4], r[5] end
        table.sort(e.victims, function(a, b) return (a.t or 0) > (b.t or 0) end)
    end
    table.sort(g.mates, function(a, b)
        if a.kills ~= b.kills then return a.kills > b.kills end
        if a.deaths ~= b.deaths then return a.deaths < b.deaths end
        return a.name < b.name
    end)
    return g
end

-- The guild roster from the client: { { name, rank, level, class token, public note } }.
-- The officer note is never read.
function Ledger.Roster()
    local list = {}
    if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return list end
    local ok, n = pcall(GetNumGuildMembers)
    if not ok or type(n) ~= "number" then return list end
    for i = 1, n do
        local ok2, name, rank, _, level, _, _, note, _, _, _, class = pcall(GetGuildRosterInfo, i)
        if ok2 and type(name) == "string" and not ns.Secret(name) then
            list[#list + 1] = { (name:gsub("%-$", "")), rank, level, class, note }
        end
    end
    return list
end

function Ledger.Stats(db, gdb, opt)
    opt = opt or {}
    local s = Empty()
    local t = s.tally
    t.kills, t.deaths, t.best = db.kills or 0, db.deaths or 0, db.bestStreak or 0
    t.yards, t.flights, t.runs = db.yards or 0, db.flights or 0, db.runs or 0
    t.spirit, t.ghostYards = db.spirit or 0, db.ghostYards or 0
    t.shots = gdb and gdb.shotCount or 0
    for _ in pairs(db.victims or {}) do t.foes = t.foes + 1 end

    local info, struckInfo, times, chains, bestMark = {}, {}, {}, {}, nil
    for mapID, z in pairs(db.maps or {}) do
        local land = { kills = z.kills or 0, deaths = z.pdeaths or 0, best = z.bestStreak or 0, foes = 0, wilds = 0,
                       yards = z.yards or 0, sightings = 0, gkills = 0, runs = z.runs_n or 0 }
        for _, n in pairs(z.sight or {}) do land.sightings = land.sightings + n end
        for _, g in ipairs(z.gmarks or {}) do if g.kind == "K" then land.gkills = land.gkills + 1 end end
        t.sightings = t.sightings + land.sightings
        t.avenged = t.avenged + (z.avenged or 0)
        local here = { foes = {}, count = {} }
        for _, m in ipairs(z.marks or {}) do
            local mt = m[3]
            if type(mt) == "number" then
                if not s.first or mt < s.first then s.first = mt end
                if m[4] == "kill" then
                    KillMark(s, m, mapID, land, here, info, times, chains)
                    -- the latest time the best streak was reached (Joe's snapshot: twice)
                    if t.best > 0 and m.streak == t.best and (not bestMark or mt > bestMark.t) then
                        bestMark = { n = t.best, t = mt, map = mapID, shot = m.shot }
                    end
                elseif m[4] == "death" then
                    DeathMark(s, m, mapID, land, struckInfo)
                end
            end
        end
        for _ in pairs(here.foes) do land.foes = land.foes + 1 end
        if land.top then land.top.t = nil end
        if IsLand(mapID) then s.lands[mapID] = land end
    end
    -- each chain once, at its final tier; a chain of five or more is one
    -- bloodbath, so it's the marks that reached five
    for n = 2, 4 do s.multi[n] = (chains[n] or 0) - (chains[n + 1] or 0) end
    s.multi[5] = chains[5] or 0
    if t.best > 0 then s.records.longest = bestMark or { n = t.best } end
    HourRecord(s, times)
    CampaignRecords(s, db)
    s.foes.slain = TopTen(db.victims or {}, info)
    s.foes.struck = TopTen(gdb and gdb.killers or {}, struckInfo)
    if opt.guild ~= false then
        s.guild = Guild(db, opt.me or ns.myName, opt.roster or Ledger.Roster())
    end
    return Finish(s)
end

---------------------------------------------------------------------------
-- Every character: WarpathGlobal.chars
---------------------------------------------------------------------------

local function Round(v) return math.floor(v + 0.5) end

-- This character's summary, from its own saved data. Inside pcall: on an
-- error one chat line, and the account view says this one couldn't be read.
function Ledger.Summarize()
    local db, gdb, key = ns.db, ns.gdb, ns.myFull
    if not (db and gdb and key) then return end
    local ok, err = pcall(function()
        local s = Ledger.Stats(db, gdb, { guild = false })
        s.continents = nil -- worked out again when added up
        s.tally.kd = nil
        s.tally.yards, s.tally.ghostYards = Round(s.tally.yards), Round(s.tally.ghostYards)
        for _, land in pairs(s.lands) do
            land.top, land.foes = nil, nil -- this character's view only
            land.yards = Round(land.yards)
        end
        gdb.chars = gdb.chars or {}
        local _, class = UnitClass("player")
        local level = ns.Foes.Safe(UnitLevel, "player")
        gdb.chars[key] = { stats = s, class = class, faction = UnitFactionGroup("player"),
            level = type(level) == "number" and level or nil, at = time(), ver = ns.VERSION }
    end)
    if not ok then
        ns.Print("couldn't add this character to the Ledger's \"All characters\": " .. tostring(err))
        gdb.chars = gdb.chars or {}
        local e = gdb.chars[key] or {}
        e.err, e.at = tostring(err), time()
        gdb.chars[key] = e
    end
    return ok
end

-- Add b's counts into a, key by key (numbers summed, tables recursed).
local function Sum(a, b)
    for k, v in pairs(b) do
        if type(v) == "number" then a[k] = (a[k] or 0) + v
        elseif type(v) == "table" then a[k] = a[k] or {} Sum(a[k], v) end
    end
end

local function Latest(a, b)
    for k, v in pairs(b) do if not a[k] or v > a[k] then a[k] = v end end
end

-- Foes lists merged by name. counts: sum (each character's own kills) or
-- max (struck down: the counts are already account-wide).
local function MergeFoes(lists, how)
    local counts, info = {}, {}
    for _, list in ipairs(lists) do
        for _, e in ipairs(list) do
            local had = counts[e.f]
            counts[e.f] = how == "max" and math.max(had or 0, e.count) or (had or 0) + e.count
            local i = info[e.f]
            if not i or (e.last or 0) > (i.last or 0) then info[e.f] = { last = e.last, n = e.n, c = e.c, lv = e.lv, gu = e.gu } end
        end
    end
    return TopTen(counts, info)
end

function Ledger.Account(gdb)
    local out = Empty()
    out.chars, out.failed = {}, {}
    local slain, struck = {}, {}
    out.wilds.byKey = {}
    local keys = {}
    for key in pairs(gdb.chars or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local s = gdb.chars[key].stats
        if gdb.chars[key].err or type(s) ~= "table" then
            out.failed[#out.failed + 1] = key
        else
            out.chars[#out.chars + 1] = key
            local t = out.tally
            for k, v in pairs(s.tally or {}) do
                if k == "best" then t.best = math.max(t.best, v)
                elseif k ~= "shots" and k ~= "kd" and type(v) == "number" then t[k] = (t[k] or 0) + v end
            end
            if s.first and (not out.first or s.first < out.first) then out.first = s.first end
            for _, k in ipairs({ "multi", "streaks", "hours", "weekdays", "slain", "slew" }) do Sum(out[k], s[k] or {}) end
            Latest(out.multiLast, s.multiLast or {})
            Latest(out.streakLast, s.streakLast or {})
            Sum(out.who, s.who or {})
            for day, d in pairs(s.calendar or {}) do
                local o = out.calendar[day]
                if not o then o = { k = 0, d = 0, zones = {} } out.calendar[day] = o end
                o.k, o.d, o.field = o.k + (d.k or 0), o.d + (d.d or 0), o.field or d.field
                for z in pairs(d.zones or {}) do o.zones[z] = true end
            end
            for id, land in pairs(s.lands or {}) do
                local o = out.lands[id]
                if not o then o = {} out.lands[id] = o end
                for k, v in pairs(land) do
                    if k == "best" then o.best = math.max(o.best or 0, v)
                    elseif type(v) == "number" then o[k] = (o[k] or 0) + v end
                end
            end
            local w, sw = out.wilds, s.wilds or {}
            w.total, w.unrecorded = w.total + (sw.total or 0), w.unrecorded + (sw.unrecorded or 0)
            Sum(w.lands, sw.lands or {})
            Sum(w.hours, sw.hours or {})
            for _, e in ipairs(sw.causes or {}) do
                local k = e.how .. "|" .. (e.cause or "")
                local o = w.byKey[k]
                if not o then o = { cause = e.cause, how = e.how, kind = e.kind, n = 0 } w.byKey[k] = o end
                o.n = o.n + e.n
            end
            for rk, r in pairs(s.records or {}) do
                local copy = {}
                for k, v in pairs(r) do copy[k] = v end
                copy.char = key
                Offer(out.records, rk, copy)
            end
            slain[#slain + 1] = s.foes and s.foes.slain or {}
            struck[#struck + 1] = s.foes and s.foes.struck or {}
        end
    end
    out.tally.shots = gdb.shotCount or 0
    for _, land in pairs(out.lands) do
        for _, k in ipairs({ "kills", "deaths", "best", "wilds", "yards", "sightings", "gkills", "runs" }) do
            land[k] = land[k] or 0
        end
    end
    out.foes.slain = MergeFoes(slain, "sum")
    out.foes.struck = MergeFoes(struck, "max")
    return Finish(out)
end

ns.Ledger = Ledger
