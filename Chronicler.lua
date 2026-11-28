-- Warpath: Chronicler
-- A campaign written up as a chronicle page (3.8.5): the date line, a
-- two-line title and the prose, as data. No drawing here: the Campaigns page
-- draws it, one font string per run, so a foe's name can be coloured and
-- hovered. Ported from the design prototype (campaign-voice/chronicler.py)
-- whose voice Joe approved: third person, past tense, zone by zone in the
-- order it happened, "the rogue Bluey" the first time and "Bluey" after,
-- crowds in words, numbers in words where a scribe would.
--
-- Phrasing is chosen by the campaign's start time, never at random, so a
-- page always reads the same and different nights read differently.
local ADDON, ns = ...

local Chronicler = {}

-- Prose names, with the article a sentence needs ("the Barrens").
local ZONES = { [1411] = "Durotar", [1412] = "Mulgore", [1413] = "the Barrens", [1416] = "the Alterac Mountains",
    [1417] = "the Arathi Highlands", [1418] = "the Badlands", [1419] = "the Blasted Lands", [1420] = "Tirisfal Glades",
    [1421] = "Silverpine Forest", [1422] = "the Western Plaguelands", [1423] = "the Eastern Plaguelands",
    [1424] = "the Hillsbrad Foothills", [1425] = "the Hinterlands", [1426] = "Dun Morogh", [1427] = "Searing Gorge",
    [1428] = "the Burning Steppes", [1429] = "Elwynn Forest", [1430] = "Deadwind Pass", [1431] = "Duskwood",
    [1432] = "Loch Modan", [1433] = "the Redridge Mountains", [1434] = "Stranglethorn Vale",
    [1435] = "the Swamp of Sorrows", [1436] = "Westfall", [1437] = "the Wetlands", [1438] = "Teldrassil",
    [1439] = "Darkshore", [1440] = "Ashenvale", [1441] = "Thousand Needles", [1442] = "the Stonetalon Mountains",
    [1443] = "Desolace", [1444] = "Feralas", [1445] = "Dustwallow Marsh", [1446] = "Tanaris", [1447] = "Azshara",
    [1448] = "Felwood", [1449] = "Un'Goro Crater", [1450] = "Moonglade", [1451] = "Silithus", [1452] = "Winterspring",
    [1453] = "Stormwind", [1454] = "Orgrimmar", [1455] = "Ironforge", [1456] = "Thunder Bluff", [1457] = "Darnassus",
    [1458] = "the Undercity", [2482] = "Mount Hyjal" }

-- Where it happened, said like a chronicle. The first eleven are the
-- prototype's, as Joe read them; the rest follow their pattern.
local PLACE = { [1452] = "in the snows of Winterspring", [1427] = "among the forges of Searing Gorge",
    [1443] = "in the dust of Desolace", [1445] = "in the mire of Dustwallow Marsh",
    [1423] = "in the blighted Eastern Plaguelands", [1422] = "on the fields of the Western Plaguelands",
    [1448] = "beneath the rotting boughs of Felwood", [2482] = "on the slopes of Mount Hyjal",
    [1437] = "in the wet hills of the Wetlands", [1431] = "in the gloom of Duskwood",
    [1434] = "in the jungles of Stranglethorn",
    [1411] = "in the red dust of Durotar", [1412] = "on the plains of Mulgore", [1413] = "out on the Barrens",
    [1416] = "in the passes of the Alterac Mountains", [1417] = "on the hills of the Arathi Highlands",
    [1418] = "among the rocks of the Badlands", [1419] = "in the ashes of the Blasted Lands",
    [1420] = "in the glades of Tirisfal", [1421] = "beneath the pines of Silverpine Forest",
    [1424] = "in the foothills of Hillsbrad", [1425] = "in the wilds of the Hinterlands",
    [1426] = "on the snowfields of Dun Morogh", [1428] = "in the embers of the Burning Steppes",
    [1429] = "in the fields of Elwynn", [1430] = "in the dead hills of Deadwind Pass",
    [1432] = "on the shores of Loch Modan", [1433] = "in the hills of Redridge",
    [1435] = "in the fens of the Swamp of Sorrows", [1436] = "on the farmlands of Westfall",
    [1438] = "under the boughs of Teldrassil", [1439] = "on the dark shores of Darkshore",
    [1440] = "in the forests of Ashenvale", [1441] = "among the mesas of Thousand Needles",
    [1442] = "on the crags of the Stonetalon Mountains", [1444] = "in the green wilds of Feralas",
    [1446] = "in the sands of Tanaris", [1447] = "on the cliffs of Azshara",
    [1449] = "in the depths of Un'Goro Crater", [1450] = "beneath the moon of Moonglade",
    [1451] = "among the hives of Silithus", [1453] = "in the streets of Stormwind",
    [1454] = "in the streets of Orgrimmar", [1455] = "in the halls of Ironforge",
    [1456] = "on the rises of Thunder Bluff", [1457] = "in the groves of Darnassus",
    [1458] = "in the halls of the Undercity" }

-- Zones the title puts you on, not in ("on Mount Hyjal").
local ON = { [2482] = "on " }

local KALIMDOR = {}
for _, id in ipairs({ 1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448,
    1449, 1450, 1451, 1452, 1454, 1456, 1457, 2482 }) do KALIMDOR[id] = true end
local CONTINENTS = { [1414] = true, [1415] = true }

local CLASSES = { WARRIOR = "warrior", ROGUE = "rogue", MAGE = "mage", PRIEST = "priest", DRUID = "druid",
    HUNTER = "hunter", SHAMAN = "shaman", PALADIN = "paladin", WARLOCK = "warlock" }

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

local function Word(n) return ns.NumberWord(n) end

-- Crowds said the way a chronicle would: words, then rounded.
local function Many(n)
    if n <= 20 then return Word(n) end
    if n < 30 then return "a score and more" end
    if n < 100 then return "some " .. Word(math.floor(n / 10) * 10) end
    if n < 200 then return "over a hundred" end
    return "hundreds"
end
Chronicler.Many = Many

local function Times(n) return n == 1 and "once" or n == 2 and "twice" or (Word(n) .. " times") end

local function CapS(s) return (s:gsub("^%l", string.upper)) end

local function ZoneName(z)
    if ZONES[z] then return ZONES[z] end
    local ok, info = pcall(C_Map.GetMapInfo, z)
    local name = ok and info and info.name
    if not name then return "unknown lands" end
    return (name:gsub("^The ", "the "))
end
Chronicler.ZoneName = ZoneName

local function Place(z) return PLACE[z] or ("in " .. ZoneName(z)) end
Chronicler.Place = Place

-- A real zone, not a continent or the world (flying can report those).
local function IsLand(z)
    if CONTINENTS[z] then return false end
    local ok, info = pcall(C_Map.GetMapInfo, z)
    return not (ok and info and info.mapType and info.mapType < 3)
end

local function OnKalimdor(z)
    if KALIMDOR[z] then return true end
    if ZONES[z] then return false end
    local ok, info = pcall(C_Map.GetMapInfo, z)
    return ok and info and info.parentMapID == 1414 or false
end

local function TimeOfDay(h)
    return h < 5 and "before dawn" or h < 12 and "in the morning" or h < 14 and "at midday"
        or h < 18 and "in the afternoon" or h < 22 and "in the evening" or "at night"
end

local function Scale(fights)
    return fights == 0 and "patrol" or fights <= 2 and "clash" or fights <= 12 and "skirmish"
        or fights <= 24 and "battle" or "war"
end
Chronicler.Scale = Scale

---------------------------------------------------------------------------
-- Pieces: a phrase is a list of plain strings and name runs ({ text = ... }),
-- so names keep their data all the way to the page.
---------------------------------------------------------------------------

local function IsRun(x) return type(x) == "table" and x.text ~= nil end

-- Append a string, a run or a list of either to out.
local function Put(out, x)
    if x == nil then return out end
    if type(x) == "string" or IsRun(x) then out[#out + 1] = x return out end
    for _, v in ipairs(x) do out[#out + 1] = v end
    return out
end

local function Cat(...)
    local out = {}
    for i = 1, select("#", ...) do Put(out, (select(i, ...))) end
    return out
end

-- F("{1} fell {2}", who, at): placeholders take strings, runs or lists.
local function F(template, ...)
    local args, out, pos = { ... }, {}, 1
    while true do
        local a, b, n = template:find("{(%d)}", pos)
        if not a then break end
        if a > pos then out[#out + 1] = template:sub(pos, a - 1) end
        Put(out, args[tonumber(n)])
        pos = b + 1
    end
    if pos <= #template then out[#out + 1] = template:sub(pos) end
    return out
end

-- Capitalise a phrase's first letter (a name already has its capital).
local function Cap(list)
    if type(list) == "string" then return CapS(list) end
    local out = Cat(list)
    if type(out[1]) == "string" then out[1] = CapS(out[1]) end
    return out
end

-- {"a"}, {"a", "b"} -> "a and b"; three or more -> "a, b and c"
local function Join(lists)
    local out = {}
    for i, l in ipairs(lists) do
        if i > 1 then out[#out + 1] = (i == #lists) and " and " or ", " end
        Put(out, l)
    end
    return out
end

-- One string per run: neighbouring strings merged.
local function Flatten(list)
    local runs = {}
    for _, x in ipairs(list) do
        if type(x) == "string" then
            local last = runs[#runs]
            if last and not last.name then last.text = last.text .. x
            elseif x ~= "" then runs[#runs + 1] = { text = x } end
        else
            runs[#runs + 1] = x
        end
    end
    return runs
end

local function Plain(runs)
    local t = {}
    for i, r in ipairs(runs) do t[i] = r.text end
    return table.concat(t)
end
Chronicler.Plain = Plain

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

-- Kills and deaths in the order they happened.
local function Events(c)
    local out = {}
    for i, k in ipairs(c.kl or {}) do out[#out + 1] = { e = k, kill = true, t = k.t or 0, z = k.z or 0, i = i } end
    local nk = #out
    for i, d in ipairs(c.dl or {}) do out[#out + 1] = { e = d, kill = false, t = d.t or 0, z = d.z or 0, i = nk + i } end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.i < b.i end)
    return out
end

local function Key(e) return e.f or e.n end

-- The two-line title: "From Searing Gorge" / "to Dustwallow Marsh"; one zone
-- with two thirds of the fighting is "The Skirmish" / "in Felwood".
local function Title(ev, scale)
    local order, count, top = {}, {}, nil
    for _, x in ipairs(ev) do
        if not count[x.z] then order[#order + 1] = x.z end
        count[x.z] = (count[x.z] or 0) + 1
    end
    if #order == 0 then return { "A " .. CapS(scale) } end
    for _, z in ipairs(order) do if not top or count[z] > count[top] then top = z end end
    local first, last = order[1], order[#order]
    if #order == 1 or count[top] * 3 >= #ev * 2 or first == last then
        return { "The " .. CapS(scale), (ON[top] or "in ") .. ZoneName(top) }
    end
    return { "From " .. ZoneName(first), "to " .. ZoneName(last) }
end

-- One write-up's state: what has been named, and the seed.
local function Writer(c, me, foe)
    local w = { c = c, me = me, foe = foe, seed = math.floor(c.start or 0), named = {}, slain = {}, slew = {} }
    for _, k in ipairs(c.kl or {}) do local key = Key(k) if key then w.slain[key] = (w.slain[key] or 0) + 1 end end
    for _, d in ipairs(c.dl or {}) do local key = Key(d) if key then w.slew[key] = (w.slew[key] or 0) + 1 end end
    return w
end

-- Same campaign, same slot: same choice.
local function Pick(w, slot, options)
    return options[(math.floor(w.seed / 7) + slot * 31) % #options + 1]
end

-- A foe's name as a run: what the page needs to colour it and tooltip it.
local function NameRun(w, e)
    local key = Key(e)
    local full = ns.DisplayName(e.f or e.n)
    local short = e.n and (e.n:match("^[^%-]+")) or (full and full:match("^%S+"))
    return { text = short, name = full, key = key, class = e.c, level = e.lv, race = e.ra, guild = e.gu,
        slain = w.slain[key] or 0, slew = w.slew[key] or 0 }
end

-- "the rogue Bluey" the first time, "Bluey" after.
local function Who(w, e)
    local cls = CLASSES[e.c or ""]
    if e.n and w.named[Key(e)] then return { NameRun(w, e) } end
    if e.n then
        w.named[Key(e)] = true
        if cls then return { "the " .. cls .. " ", NameRun(w, e) } end
        return { NameRun(w, e) }
    end
    return { cls and ("a " .. cls) or "one whose name went unrecorded" }
end

-- Victims in order, a name met again folded in: "Bainekx twice".
local function Blows(w, list)
    local seen, order = {}, {}
    for _, e in ipairs(list) do
        local key = Key(e) or e
        if not seen[key] then seen[key] = { e = e, n = 0 } order[#order + 1] = key end
        seen[key].n = seen[key].n + 1
    end
    local out = {}
    for _, key in ipairs(order) do
        local s = seen[key]
        out[#out + 1] = Cat(Who(w, s.e), s.n == 1 and "" or (" " .. Times(s.n)))
    end
    return out
end

local function SettingOut(w, out)
    local c, me = w.c, w.me
    local s0, s1 = date("*t", c.start or 0), date("*t", c.stop or c.start or 0)
    local hours = ((c.played or 0) + (c.cur or 0)) / 3600
    local untilWhen = ""
    if (s1.yday ~= s0.yday or s1.year ~= s0.year) and s1.hour < 6 then
        untilWhen = Pick(w, 1, { " and did not rest until the small hours", " and rode on long past midnight" })
    elseif hours >= 8 then
        untilWhen = " and was in the field the whole day long"
    end
    local tod = TimeOfDay(s0.hour)
    out[#out + 1] = { Pick(w, 0, { me .. " rode out " .. tod .. untilWhen .. ".",
        me .. " took to the road " .. tod .. untilWhen .. ".", me .. " set out " .. tod .. untilWhen .. "." }) }

    local lands, kal, ek = 0, false, false
    for z in pairs(c.zones or {}) do
        if IsLand(z) then
            lands = lands + 1
            if OnKalimdor(z) then kal = true else ek = true end
        end
    end
    local seen, foe = c.sightings or 0, w.foe
    if lands >= 10 then
        local road = (kal and ek) and Pick(w, 2, { "The road crossed both continents",
            "It was a long road, over both continents", "The way led from one continent to the other" })
            or ("The road ran through " .. Word(lands) .. " lands")
        out[#out + 1] = { road .. (seen >= 3 and Pick(w, 3, {
            ", and " .. Many(seen) .. " of the " .. foe .. " were seen along the way.",
            "; " .. Many(seen) .. " of the " .. foe .. " were seen on it." }) or ".") }
    elseif seen >= 20 then
        out[#out + 1] = { CapS(Many(seen)) .. " of the " .. foe .. " were seen on the roads." }
    end
end

-- Kills in one zone, as the start of its sentence.
local function KillsIn(w, kills, at, told, opening)
    local n = #kills
    local distinct, keys = 0, {}
    for _, k in ipairs(kills) do
        local key = Key(k.e) or k
        if not keys[key] then keys[key] = true distinct = distinct + 1 end
    end
    if n == 1 then
        local who = Who(w, kills[1].e)
        if opening then
            return Pick(w, 10 + told, { F("The first to fall was {1}, {2}", who, at), F("First blood was {1}'s, {2}", who, at) })
        end
        return Pick(w, 10 + told, { F("{1}, {2} fell", Cap(at), who), F("{1} fell {2}", Cap(who), at) })
    end
    if distinct == 1 then
        local together = kills[n].t - kills[1].t <= 90
        return F("{1}, {2} fell {3}{4}", Cap(at), Who(w, kills[1].e), Times(n), together and " in as many minutes" or "")
    end
    local named = {}
    for _, k in ipairs(kills) do if k.e.n then named[#named + 1] = k end end
    if #named == 0 then return F("{1}, {2} fell", Cap(at), Word(n)) end
    if n <= 4 then
        -- told in order: a pair within a minute falls "in the same breath"
        local unnamed = n - #named
        local done, clauses, i = {}, {}, 1
        while i <= #named do
            local k, nxt = named[i], named[i + 1]
            if nxt and Key(nxt.e) ~= Key(k.e) and nxt.t - k.t <= 60 and #clauses == 0 then
                clauses[#clauses + 1] = F("{1} and {2} fell in the same breath", Who(w, k.e), Who(w, nxt.e))
                done[Key(k.e)], done[Key(nxt.e)] = true, true
                i = i + 2
            else
                if done[Key(k.e)] then
                    clauses[#clauses + 1] = F("{1} fell again before long", NameRun(w, k.e))
                elseif #clauses == 0 then
                    clauses[#clauses + 1] = F("{1} fell", Who(w, k.e))
                else
                    clauses[#clauses + 1] = F("{1} soon after", Who(w, k.e))
                end
                done[Key(k.e)] = true
                i = i + 1
            end
        end
        if unnamed > 0 then
            clauses[#clauses + 1] = { unnamed == 1 and "one more besides" or (Word(unnamed) .. " more besides") }
        end
        local body = clauses[1]
        if #clauses > 1 then
            body = {}
            for j, cl in ipairs(clauses) do
                if j > 1 then body[#body + 1] = (j == #clauses) and ", and " or ", " end
                Put(body, cl)
            end
        end
        return F("{1}, {2}", Cap(at), body)
    end
    -- a crowd: the count, and up to two names
    if #named >= 2 then
        return F("{1} {2} fell, {3} and {4} among them", Cap(at), Word(n), Who(w, named[1].e), Who(w, named[2].e))
    elseif #named == 1 then
        return F("{1} {2} fell, {3} among them", Cap(at), Word(n), Who(w, named[1].e))
    end
    return F("{1} {2} fell", Cap(at), Word(n))
end

-- Deaths in one zone: the end of its sentence, or all of it.
local function DeathsIn(w, deaths, z, at, told, afterKills)
    local me, list, unseen = w.me, {}, 0
    for _, d in ipairs(deaths) do
        if d.e.n then list[#list + 1] = d.e else unseen = unseen + 1 end
    end
    local named = Blows(w, list)
    if unseen > 0 then
        named[#named + 1] = { unseen == 1 and "a foe no one saw" or (Word(unseen) .. " foes no one saw") }
    end
    local ks, n = Join(named), #deaths
    if afterKills then
        if n == 1 then return F("until {1} fell to {2}", me, ks) end
        return F("until {1} fell {2}, to {3}", me, Times(n), ks)
    end
    if n == 1 then return F("{1}, {2} fell to {3}", Cap(at), me, ks) end
    return Pick(w, 20 + told, { F("{1} went badly: {2} fell {3} there, to {4}", CapS(ZoneName(z)), me, Times(n), ks),
        F("{1}, {2} fell {3}, to {4}", Cap(at), me, Times(n), ks) })
end

-- The fighting, zone by zone in the order it happened.
local function Fighting(w, ev, out)
    local groups = {}
    for _, x in ipairs(ev) do
        local g = groups[#groups]
        if g and g.z == x.z then g[#g + 1] = x else groups[#groups + 1] = { z = x.z, x } end
    end
    local firstKill, fell, told = true, false, 0
    for gi, g in ipairs(groups) do
        if told == 4 then
            local rest = 0
            for j = gi, #groups do rest = rest + #groups[j] end
            out[#out + 1] = { "There was more fighting after, " .. Word(rest) .. " blows in all, before the day was done." }
            break
        end
        told = told + 1
        local kills, deaths = {}, {}
        for _, x in ipairs(g) do if x.kill then kills[#kills + 1] = x else deaths[#deaths + 1] = x end end
        local at, parts = Place(g.z), {}
        if #kills > 0 then
            parts[#parts + 1] = KillsIn(w, kills, at, told, firstKill and not fell and #ev > 1)
            firstKill = false
        end
        if #deaths > 0 then
            parts[#parts + 1] = DeathsIn(w, deaths, g.z, at, told, #kills > 0)
            fell = true
        end
        local s = {}
        for j, p in ipairs(parts) do
            if j > 1 then s[#s + 1] = ", " end
            Put(s, p)
        end
        s[#s + 1] = "."
        out[#out + 1] = s
    end
end

-- The run for whoever ended the streak, from the deaths that name them.
local function EnderRun(w, name)
    for _, d in ipairs(w.c.dl or {}) do
        if d.n == name or d.f == name then return NameRun(w, d) end
    end
    return NameRun(w, { n = name })
end

local function Reckoning(w, ev, out)
    local c, me, foe = w.c, w.me, w.foe
    local k, d = c.kills or 0, c.deaths or 0
    if k > 0 and d == 0 then
        out[#out + 1] = { Pick(w, 30, { CapS(Word(k)) .. " of the " .. foe .. " were slain, and not once was " .. me .. " brought down.",
            CapS(Word(k)) .. " of the " .. foe .. " fell, and " .. me .. " never did." }) }
    elseif d > 0 and k == 0 then
        if #ev > 0 then out[#out + 1] = { "No " .. foe .. " blood was spilled that day." } end
    elseif k > 0 and d > 0 then
        out[#out + 1] = { Pick(w, 30, {
            "When it was over, " .. Word(k) .. " of the " .. foe .. " had fallen, at a cost of " .. Word(d) .. (d == 1 and " death." or " deaths."),
            CapS(Word(k)) .. " slain, " .. Times(d) .. " fallen: so the day was reckoned." }) }
    else
        out[#out + 1] = { Pick(w, 30, { "No blood was spilled.", "Not a blade was drawn in anger." }) }
    end
    local best = c.best or 0
    if best >= 3 then
        if c.bestBy then
            out[#out + 1] = F("A streak of {1} was ended by {2}.", Word(best), EnderRun(w, c.bestBy))
        elseif not c.bestEnded and d > 0 then
            out[#out + 1] = { "The streak of " .. Word(best) .. " was never broken." }
        end
    end
end

-- The page's words for campaign c, written about the character me (a name in
-- any stored form; the first name is used). foe: "Alliance" or "Horde"
-- (defaults to the other faction). Returns:
--   date  = { weekday, month, day, text = "Wednesday, November 25",
--             scale = "skirmish", tag = "a skirmish" }
--   title = { "From Searing Gorge", "to Dustwallow Marsh" } (one or two lines)
--   scale = "patrol" | "clash" | "skirmish" | "battle" | "war"; quiet = patrol or clash
--   runs  = { { text = "Lethality set out ... the rogue " },
--             { text = "Bluey", name = "Bluey Vitruvius", key = "Bluey-Vitruvius",
--               class = "ROGUE", level = 57, race, guild, slain = 1, slew = 0 }, ... }
--     A run with .name is a foe's name; the rest is plain prose. The drop
--     cap is just the first letter of the first run.
--   text  = the prose as one plain string
function Chronicler.Write(c, me, foe)
    me = ns.DisplayName(me or ns.myName or "") or ""
    me = me:match("^%S+") or "Someone"
    if foe ~= "Alliance" and foe ~= "Horde" then
        local f = ns.faction and ns.faction.foe
        foe = (f == "Alliance" or f == "Horde") and f or "enemy"
    end

    local w = Writer(c, me, foe)
    local ev = Events(c)
    local scale = Scale((c.kills or 0) + (c.deaths or 0))
    local sentences = {}
    SettingOut(w, sentences)
    Fighting(w, ev, sentences)
    Reckoning(w, ev, sentences)

    local all = {}
    for i, s in ipairs(sentences) do
        if i > 1 then all[#all + 1] = " " end
        Put(all, s)
    end
    local runs = Flatten(all)

    local t = date("*t", c.start or 0)
    local weekday, month = ns.DayName(t.wday), ns.MonthName(t.month)
    return {
        date = { weekday = weekday, month = month, day = t.day, text = weekday .. ", " .. month .. " " .. t.day,
            scale = scale, tag = "a " .. scale },
        title = Title(ev, scale),
        scale = scale, quiet = scale == "patrol" or scale == "clash",
        runs = runs, text = Plain(runs),
    }
end

ns.Chronicler = Chronicler
