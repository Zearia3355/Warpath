-- Warpath: Campaign
-- A campaign is continuous play with gaps under two hours, per character.
-- The open one is db.campaign; closed ones are db.campaigns, newest first.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local MapName, Miles, Print, session = ns.MapName, ns.Miles, ns.Print, ns.session

local db, gdb, cfg, faction, foe, myName
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName
end)

local Campaign = {}
local DASH = " \226\128\148 "   -- em dash
local KILL_CAP, DEATH_CAP = 200, 100

local function New()
    local now = time()
    return { start = now, stop = now, played = 0, cur = 0,
        kills = 0, deaths = 0, best = 0, streak = 0, yards = 0, sightings = 0, avenged = 0,
        grudges = 0, zones = {}, kl = {}, dl = {} }
end

local function HadFighting(c)
    return c and ((c.kills or 0) + (c.deaths or 0) + (c.sightings or 0)) > 0
end

local function ZoneCount(c)
    if c.zoneCount and next(c.zones or {}) == nil then return c.zoneCount end
    local n = 0
    for _ in pairs(c.zones or {}) do n = n + 1 end
    return n
end

local function Played(c) return (c.played or 0) + (c.cur or 0) end

-- Copy the running counters into the open campaign. Called every few seconds.
function Campaign.Save()
    local c = db and db.campaign
    if not c then return end
    local now = time()
    c.stop, c.cur = now, math.max(0, now - session.start)
    c.kills, c.deaths, c.best, c.streak = session.kills, session.deaths, session.best, session.streak
    c.yards, c.sightings, c.avenged = session.yards, session.sightings, session.avenged
    for mapID in pairs(session.zones) do
        if not c.zones[mapID] then c.zones[mapID] = { k = 0, d = 0 } end
    end
end

local function Close(c)
    if not c then return end
    c.played, c.cur = Played(c), 0
    if not HadFighting(c) then return end
    table.insert(db.campaigns, 1, c)
    while #db.campaigns > C.CAMPAIGN_KEEP do table.remove(db.campaigns) end
    return true
end

-- At login and /reload: back within two hours continues the campaign.
-- Returns true when a new campaign started and the one before it had fighting.
function Campaign.Begin()
    local c, now = db.campaign, time()
    if c and now - (c.stop or 0) < C.CAMPAIGN_GAP then
        c.played, c.cur = Played(c), 0
        if c.old then c.old, c.partial = nil, true end -- began under 3.3: lists only from now on
        session.kills, session.deaths, session.best = c.kills or 0, c.deaths or 0, c.best or 0
        session.streak, session.yards, session.sightings = c.streak or 0, c.yards or 0, c.sightings or 0
        session.avenged = c.avenged or 0
        for mapID in pairs(c.zones or {}) do session.zones[mapID] = true end
        return false
    end
    local closed = Close(c)
    db.campaign = New()
    for k in pairs(session.zones) do session.zones[k] = nil end
    session.kills, session.deaths, session.best, session.streak = 0, 0, 0, 0
    session.yards, session.sightings, session.avenged = 0, 0, 0
    return closed and true or false
end

local function ZoneEntry(c, mapID)
    if not mapID then return end
    local e = c.zones[mapID]
    if not e then e = { k = 0, d = 0 } c.zones[mapID] = e end
    return e
end

-- e = { n, f, c, z, x, y, t, tag, st, grudge }. Returns the stored entry
-- (the screenshot number is filled in once the picture is taken).
function ns.CampaignKill(e)
    local c = db.campaign
    if not c then return end
    local z = ZoneEntry(c, e.z)
    if z then z.k = z.k + 1 end
    if e.grudge then c.grudges = (c.grudges or 0) + 1 end
    e.grudge = nil
    if e.st and e.st >= (session.best or 0) then
        -- a new best: remember where, and that nobody has ended it yet
        c.bestZone, c.bestBy, c.bestEnded = e.z, nil, nil
    end
    c.kl[#c.kl + 1] = e
    if #c.kl > KILL_CAP then table.remove(c.kl, 1) end
    return e
end

-- e = { n, c, z, x, y, t }; streak = your streak at the moment you fell.
function ns.CampaignDeath(e, streak)
    local c = db.campaign
    if not c then return end
    local z = ZoneEntry(c, e.z)
    if z then z.d = z.d + 1 end
    if streak and streak > 0 and streak >= (session.best or 0) and not c.bestEnded then
        c.bestEnded, c.bestBy = true, e.n
    end
    c.dl[#c.dl + 1] = e
    if #c.dl > DEATH_CAP then table.remove(c.dl, 1) end
end

---------------------------------------------------------------------------
-- Writing it up
---------------------------------------------------------------------------

-- Two-word zone names that read badly cut to their first word.
local KEEP_FULL = { Dun = true, Loch = true, Thousand = true, Blasted = true, Swamp = true,
    Mount = true, Isle = true, Ruins = true, Valley = true, Lake = true,
    Eastern = true, Western = true, Northern = true, Southern = true, Searing = true, Burning = true }

local function ShortZone(name)
    name = (name or ""):gsub("^The ", "")
    local first = name:match("^(%S+)")
    if not first or KEEP_FULL[first] or first == name then return name end
    return first
end

local function Most(counts)
    local who, n = nil, 0
    for k, v in pairs(counts) do
        if v > n or (v == n and who and tostring(k) < tostring(who)) then who, n = k, v end
    end
    return who, n
end

-- Everything the window, the chat report and sharing need, in one place.
function Campaign.Summary(c)
    local s = { c = c }
    s.kills, s.deaths = c.kills or 0, c.deaths or 0
    s.best, s.miles, s.played = c.best or 0, Miles(c.yards), Played(c)
    s.sightings, s.avenged, s.grudges = c.sightings or 0, c.avenged or 0, c.grudges or 0
    s.zones = ZoneCount(c)

    local victims, vclass, killers, kclass = {}, {}, {}, {}
    for _, k in ipairs(c.kl or {}) do
        if k.n then victims[k.n] = (victims[k.n] or 0) + 1 vclass[k.n] = k.c end
    end
    for _, d in ipairs(c.dl or {}) do
        if d.n then killers[d.n] = (killers[d.n] or 0) + 1 kclass[d.n] = d.c end
    end
    s.nemesis, s.nemesisN = Most(killers)
    s.nemesisClass = s.nemesis and kclass[s.nemesis]
    s.victim, s.victimN = Most(victims)
    s.victimClass = s.victim and vclass[s.victim]

    local blood = {}
    for mapID, e in pairs(c.zones or {}) do
        if e.k + e.d > 0 then blood[mapID] = e.k + e.d end
    end
    s.ground = Most(blood)
    s.groundName = s.ground and MapName(s.ground)
    s.bestZone = c.bestZone and MapName(c.bestZone)
    s.bestBy = c.bestBy

    local lo, hi
    for _, k in ipairs(c.kl or {}) do
        if k.shot then lo, hi = math.min(lo or k.shot, k.shot), math.max(hi or k.shot, k.shot) end
    end
    s.shotLo, s.shotHi = lo, hi

    -- The headline: "The Hillsbrad Skirmish".
    local fights = s.kills + s.deaths
    local word = fights == 0 and "Patrol" or fights <= 2 and "Clash" or fights <= 12 and "Skirmish"
        or fights <= 24 and "Battle" or "War"
    local where
    if s.groundName then
        where = ShortZone(s.groundName)
    else
        local most, n = nil, -1
        for mapID in pairs(c.zones or {}) do
            local z = db.maps[mapID]
            local y = z and z.yards or 0
            if y > n then most, n = mapID, y end
        end
        where = most and ShortZone(MapName(most))
    end
    s.title = where and ("The " .. where .. " " .. word) or ("A " .. word:lower())
    s.tally = ("%d kill%s, %d death%s"):format(s.kills, s.kills == 1 and "" or "s", s.deaths, s.deaths == 1 and "" or "s")
    s.headline = s.title .. DASH .. s.tally
    return s
end

function Campaign.Duration(sec)
    local mins = math.floor((sec or 0) / 60)
    if mins < 60 then return mins .. "m" end
    return ("%dh %02dm"):format(math.floor(mins / 60), mins % 60)
end

-- The six highlights as { label, text } (text nil when there is nothing).
function Campaign.Highlights(s)
    local list = {}
    list[1] = { "Nemesis of the night", s.nemesis and (s.nemesis .. (s.nemesisN > 1 and (" (" .. s.nemesisN .. " deaths)") or "")) }
    list[2] = { "Favourite victim", s.victim and (s.victim .. (s.victimN > 1 and (" (" .. s.victimN .. " kills)") or "")) }
    list[3] = { "Bloodiest ground", s.groundName }
    local streak
    if s.best > 0 then
        streak = tostring(s.best)
        if s.bestBy then streak = streak .. ", ended by " .. s.bestBy
        elseif s.c.bestEnded then streak = streak .. ", ended" end
        if s.bestZone then streak = streak .. " in " .. s.bestZone end
    end
    list[4] = { "Longest streak", streak }
    local settled = {}
    if s.grudges > 0 then settled[#settled + 1] = s.grudges .. (s.grudges == 1 and " grudge settled" or " grudges settled") end
    if s.avenged > 0 then settled[#settled + 1] = s.avenged .. (s.avenged == 1 and " death avenged" or " deaths avenged") end
    list[5] = { "Grudges and vengeance", #settled > 0 and table.concat(settled, ", ") or nil }
    list[6] = { "Screenshots", s.shotLo and (s.shotLo == s.shotHi and ("#" .. s.shotLo) or ("#" .. s.shotLo .. "\226\128\147#" .. s.shotHi)) }
    return list
end

---------------------------------------------------------------------------
-- The campaign as a short paragraph, for the book
---------------------------------------------------------------------------

local WORDS = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty" }
local function Word(n) return WORDS[n] or tostring(n) end
Campaign.Word = Word

local function Times(n) return n == 1 and "once" or n == 2 and "twice" or (Word(n) .. " times") end

local function Span(sec)
    local mins = math.floor((sec or 0) / 60 + 0.5)
    if mins < 50 then return Word(math.max(1, mins)) .. (mins == 1 and " minute" or " minutes") end
    local hours = math.floor(mins / 60 + 0.5)
    if hours <= 1 then return "an hour" end
    return Word(hours) .. " hours"
end

function Campaign.Prose(s)
    local c = s.c
    local out = {}
    -- where you went
    local names = {}
    local zones = {}
    for mapID, e in pairs(c.zones or {}) do zones[#zones + 1] = { id = mapID, n = (e.k or 0) + (e.d or 0) } end
    table.sort(zones, function(a, b) return a.n > b.n end)
    for i, z in ipairs(zones) do if i <= 2 then names[#names + 1] = MapName(z.id) end end
    local through = ""
    if #zones == 1 then through = " through " .. names[1]
    elseif #zones == 2 then through = " through " .. names[1] .. " and " .. names[2]
    elseif #zones > 2 then through = (" through %s, %s and %s other zone%s"):format(names[1], names[2], Word(#zones - 2), #zones == 3 and "" or "s") end
    local first = ("You rode out at %s"):format(date("%H:%M", c.start))
    if s.miles >= 0.1 then
        first = first .. (" and marched %.1f miles%s over %s"):format(s.miles, through, Span(s.played))
    else
        first = first .. (" and spent %s%s"):format(Span(s.played), through ~= "" and (" in" .. through:sub(9)) or "")
    end
    if s.sightings > 0 then
        first = first .. (", watching %s pass"):format(s.sightings == 1 and "one enemy" or (Word(s.sightings) .. " enemies"))
    end
    out[#out + 1] = first .. "."
    -- blood
    local k, d = s.kills, s.deaths
    local took = k == 1 and "one life" or (Word(k) .. " lives")
    if k == 0 and d == 0 then
        out[#out + 1] = "No blood was spilled."
    elseif d == 0 then
        out[#out + 1] = ("You took %s and gave none."):format(took)
    else
        local to = ""
        if s.nemesis then
            if d == 1 then to = ", to " .. s.nemesis
            elseif s.nemesisN > 1 then to = ", most often to " .. s.nemesis end
        end
        if k == 0 then
            out[#out + 1] = ("You took no lives and fell %s%s."):format(Times(d), to)
        else
            out[#out + 1] = ("You took %s and gave %s%s."):format(took, Word(d), to)
        end
    end
    -- the streak
    if s.best >= 3 then
        if s.bestBy then
            out[#out + 1] = ("Your best streak, %s, was ended by %s%s."):format(Word(s.best), s.bestBy,
                s.bestZone and (" in " .. s.bestZone) or "")
        elseif c.bestEnded then
            out[#out + 1] = ("Your best streak was %s."):format(Word(s.best))
        else
            out[#out + 1] = ("Your streak of %s was never broken."):format(Word(s.best))
        end
    end
    -- debts paid
    local paid = {}
    if s.grudges > 0 then paid[#paid + 1] = ("settled %s"):format(s.grudges == 1 and "a grudge" or (Word(s.grudges) .. " grudges")) end
    if s.avenged > 0 then paid[#paid + 1] = ("avenged %s"):format(s.avenged == 1 and "a death" or (Word(s.avenged) .. " deaths")) end
    if #paid > 0 then out[#out + 1] = "You " .. table.concat(paid, " and ") .. "." end
    return table.concat(out, " ")
end

-- All campaigns for paging: the open one first, then the closed ones.
function Campaign.List()
    Campaign.Save()
    local list = {}
    if db.campaign and (HadFighting(db.campaign) or #db.campaigns == 0) then list[1] = db.campaign end
    for _, c in ipairs(db.campaigns) do list[#list + 1] = c end
    return list
end

function Campaign.IsOpen(c) return c == db.campaign end

-- The full report in chat.
function Campaign.ChatReport(c, label)
    if not c then Print("no campaign recorded yet.") return end
    local s = Campaign.Summary(c)
    Print(("%s%s|r: %s%s|r"):format(C.GOLD, label or "Campaign", C.GOLD, s.headline))
    Print(("%s, played %s. %.1f miles, %d zone%s, %d enemies sighted, best streak %d.")
        :format(date("%b %d, %H:%M", c.start), Campaign.Duration(s.played), s.miles, s.zones,
            s.zones == 1 and "" or "s", s.sightings, s.best))
    for _, h in ipairs(Campaign.Highlights(s)) do
        if h[2] then Print("  " .. h[1] .. ": " .. h[2]) end
    end
    if c.old then Print("  (recorded before 3.4: totals only)") end
    if c.partial then Print("  (began before 3.4: kills and deaths are listed from the update on)") end
end

-- One line at login, about the campaign that just ended.
function Campaign.LoginLine()
    local c = db.campaigns[1]
    if not c then return end
    local s = Campaign.Summary(c)
    local line = "Last campaign: " .. C.GOLD .. s.headline .. "|r"
    if s.nemesis then line = line .. ", nemesis " .. s.nemesis end
    Print(line .. ". |cffa0a0a0/warpath chronicle|r")
end

---------------------------------------------------------------------------
-- Sharing (plain chat text, readable by anyone)
---------------------------------------------------------------------------

local lastShare = -1000

local function Clip(text)
    text = text:gsub("|", "||")
    if #text > 250 then text = text:sub(1, 247) .. "..." end
    return text
end

function Campaign.ShareLines(c)
    local s = Campaign.Summary(c)
    local one = ("[Warpath] %s%s%s, best streak %d, %.1f miles."):format(s.title, DASH, s.tally, s.best, s.miles)
    local bits = {}
    if s.nemesis then bits[#bits + 1] = "Nemesis: " .. s.nemesis .. "." end
    if s.victim then bits[#bits + 1] = "Favourite victim: " .. s.victim .. "." end
    if s.groundName then bits[#bits + 1] = "Bloodiest ground: " .. s.groundName .. "." end
    if s.grudges > 0 then bits[#bits + 1] = s.grudges .. (s.grudges == 1 and " grudge settled." or " grudges settled.") end
    if s.avenged > 0 then bits[#bits + 1] = s.avenged .. (s.avenged == 1 and " death avenged." or " deaths avenged.") end
    local two = #bits > 0 and table.concat(bits, " ") or nil
    return Clip(one), two and Clip(two)
end

-- where: guild | party | say | whisper; target: whisper name.
function Campaign.Share(c, where, target)
    if not c then Print("no campaign to share yet.") return end
    if S.inInstance then Print("sharing is off in battlegrounds and arenas.") return end
    where = (where == nil or where == "") and "guild" or where:lower()
    local channel
    if where == "guild" or where == "g" then
        if not IsInGuild() then Print("you're not in a guild. Try /warpath chronicle share party.") return end
        channel = "GUILD"
    elseif where == "party" or where == "p" or where == "group" then
        if not IsInGroup() then Print("you're not in a group.") return end
        channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    elseif where == "say" or where == "s" then
        channel = "SAY"
    elseif where == "whisper" or where == "w" then
        if not target or target == "" then Print("usage: /warpath chronicle share whisper <name>") return end
        channel = "WHISPER"
    else
        Print("usage: /warpath chronicle share [guild|party|say|whisper <name>]")
        return
    end
    if GetTime() - lastShare < C.SHARE_COOLDOWN then
        Print("one share every few seconds, please.")
        return
    end
    lastShare = GetTime()
    local one, two = Campaign.ShareLines(c)
    SendChatMessage(one, channel, nil, channel == "WHISPER" and target or nil)
    if two then SendChatMessage(two, channel, nil, channel == "WHISPER" and target or nil) end
end

-- Sample data for /warpath chronicle preview.
function Campaign.Sample()
    local now = time()
    local mapA, mapB = C_Map.GetBestMapForUnit("player") or 1424, 1416
    if ns.Secret(mapA) then mapA = 1424 end
    local function K(n, c, z, ago, tag, st, shot)
        return { n = n, c = c, z = z, t = now - ago, tag = tag, st = st, shot = shot, x = 0.5, y = 0.5 }
    end
    return {
        start = now - 3 * 3600, stop = now - 600, played = 8040, cur = 0,
        kills = 9, deaths = 3, best = 4, streak = 0, yards = 21650, sightings = 21, avenged = 1, grudges = 2,
        zones = { [mapA] = { k = 6, d = 2 }, [mapB] = { k = 3, d = 1 } },
        bestZone = mapB, bestBy = "Thrall", bestEnded = true, sample = true,
        kl = {
            K("Jaina", "MAGE", mapA, 10500, "first", 1, 41), K("Uther", "PALADIN", mapA, 10200, nil, 2, 42),
            K("Jaina", "MAGE", mapA, 9000, "streak", 3, 43), K("Varian", "WARRIOR", mapB, 8600, "grudge", 4, 44),
            K("Tyrande", "PRIEST", mapB, 6000, "avenged", 1, 45), K("Jaina", "MAGE", mapB, 5000, nil, 2, 46),
            K("Mathias", "ROGUE", mapA, 3000, "grudge", 3, 47), K("Muradin", "WARRIOR", mapA, 2200, nil, 4, 48),
            K("Genn", "DRUID", mapA, 1200, nil, 1, 49),
        },
        dl = {
            { n = "Thrall", c = "SHAMAN", z = mapB, t = now - 8000, x = 0.4, y = 0.4 },
            { n = "Thrall", c = "SHAMAN", z = mapA, t = now - 4000, x = 0.4, y = 0.4 },
            { z = mapA, t = now - 900, x = 0.4, y = 0.4 },
        },
    }
end

ns.Campaign = Campaign
