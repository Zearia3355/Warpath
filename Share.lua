-- Warpath: Share
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Cell, MapName, Print, Secret, outQ, shared = ns.Cell, ns.MapName, ns.Print, ns.Secret, ns.outQ, ns.shared

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local shareSeen, senderSeen, dupSeen, lastSweep = {}, {}, {}, 0

---------------------------------------------------------------------------
-- Sharing (opt in). Sends: an enemy was seen here; I scored a kill or died
-- here (from 3.7 with the victim's or killer's name, the multi-kill tier and
-- feat, for the kill line); and, when asked, your battle haze (Sync.lua).
-- Never your trail.
---------------------------------------------------------------------------

local shareStats = { sent = 0, refused = 0, got = 0, lastRefusal = nil }

-- extra: fields appended after the position (3.7 kill and death details).
-- Older versions read the first five fields and ignore the rest.
local function Share(kind, mapID, x, y, force, extra)
    if not cfg.share then return end
    -- Sightings: at most one per map cell a minute. Kills and deaths are
    -- always sent (until 3.6.1 a second kill or death in the same spot
    -- within a minute was silently not shared).
    if kind == "S" and not force then
        local key = kind .. mapID .. ":" .. Cell(x, y, C.SW, C.SH)
        local now = GetTime()
        if shareSeen[key] and now - shareSeen[key] < 60 then return end
        shareSeen[key] = now
    end
    local msg = ("%s|%s|%d|%.4f|%.4f"):format(C.PROTO, kind, mapID, x, y)
    if extra and extra ~= "" then msg = msg .. "|" .. extra end
    if #msg > 250 then msg = msg:sub(1, 250) end
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
    ns.NoteSent(msg)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, C.COMM, msg, channel)
    if ok and (res == nil or res == true or res == 0) then
        shareStats.sent = shareStats.sent + 1
    else
        shareStats.refused = shareStats.refused + 1
        shareStats.lastRefusal = channel .. ": " .. tostring(ok and res or "error")
    end
end

local function FlushShare()
    if not cfg.share or S.inInstance then return end
    if #outQ == 0 then -- nothing urgent: a piece of battle history, if any is waiting
        if ns.Sync then ns.Sync.FlushOne() end
        return
    end
    local msg = table.remove(outQ, 1)
    if IsInGuild() then SendOne(msg, "GUILD") end
    if IsInRaid() then
        SendOne(msg, "RAID")
    elseif IsInGroup() then
        SendOne(msg, "PARTY")
    end
end

-- The sender as one key: "Name-Realm", or the name exactly as the client
-- gives it when there's no realm to add (WoW Forever: "First Last").
-- 3.7.0 appended an empty realm ("First Last-"), so whispers back failed.
-- One kill, said once (3.8.3). When several guildmates get credit for the
-- same enemy, each sends a kill; the first report (or your own kill) prints
-- and pins, later ones of the same enemy fold into it. Same enemy: same name
-- on the same map within KILL_SAME s; a sender with no victim name (before
-- 3.7) matches by place, within KILL_NEAR of the map and KILL_NONAME s. Only
-- different reporters fold: one guildmate's two kills are two kills. Each
-- guildmate's haze still counts it (their fight).
-- 3.8.4: the line waits KILL_HOLD s, so everyone who reports the kill in
-- that time is named on it ("(with Ann Lee)"), and on its pin. A report
-- after the line printed is still folded, unnamed.
local KILL_SAME, KILL_NONAME, KILL_NEAR, KILL_HOLD = 30, 10, 0.015, 2
local recentKills = {} -- { v = victim (lower case, no realm) or nil, map, x, y, at, by, who, with, line, pin, said }

local function VictimKey(name)
    if type(name) ~= "string" or name == "" then return nil end
    return (name:gsub("%-.*$", "")):lower()
end

local function SameKill(v, mapID, x, y, by)
    local now = GetTime()
    for i = #recentKills, 1, -1 do
        if now - recentKills[i].at > KILL_SAME then table.remove(recentKills, i) end
    end
    for _, e in ipairs(recentKills) do
        if e.map == mapID and e.by ~= by then
            if v and e.v then
                if e.v == v then return e end
            elseif now - e.at <= KILL_NONAME then
                local dx, dy = e.x - x, e.y - y
                if dx * dx + dy * dy <= KILL_NEAR * KILL_NEAR then return e end
            end
        end
    end
end

-- "Ann", "Ann and Bob", "Ann, Bob and Cid". max: at most that many names,
-- the rest counted ("Ann, Bob, Cid and 7 others").
local function JoinNames(list, max)
    if #list <= 1 then return list[1] or "" end
    if max and #list > max + 1 then
        return table.concat(list, ", ", 1, max) .. (" and %d others"):format(#list - max)
    end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end
ns.JoinNames = JoinNames

local function SayKill(e)
    e.said = true
    if e.line then
        -- three names at most in chat; the pin's tooltip has them all
        Print(#e.with > 0 and (e.line .. " (with " .. JoinNames(e.with, 3) .. ")") or e.line)
    end
end

-- A kill reported (by: the reporter's full name; nil: you). who: the name
-- to show; line: the chat line to print, or nil (or set .line on the
-- record before the timer fires); pin: its mark, if already made. True when someone else already reported this kill: the reporter is
-- added to its line (if not yet printed) and its pin. Otherwise remembers
-- it, schedules its line and returns false plus its record (set .pin).
-- Your own kill arriving after a guildmate's report takes that report's pin
-- off the map: your own mark is there, and names them.
local function NoteKill(victim, mapID, x, y, by, who, line, pin)
    local v = VictimKey(victim)
    by = by or ""
    local e = SameKill(v, mapID, x, y, by)
    if e then
        if by == "" and pin then
            if e.pin then
                local list = db.maps[mapID] and db.maps[mapID].gmarks or {}
                for i = #list, 1, -1 do if list[i] == e.pin then table.remove(list, i) S.dirty = true break end end
            end
            local names = { e.who }
            for _, n in ipairs(e.with) do names[#names + 1] = n end
            e.pin, pin.with = pin, names
        elseif e.pin then
            e.pin.with = e.pin.with or {}
            table.insert(e.pin.with, who)
            S.dirty = true
        end
        if not e.said then table.insert(e.with, who) end
        return true
    end
    e = { v = v, map = mapID, x = x, y = y, at = GetTime(), by = by, who = who, with = {}, line = line, pin = pin }
    recentKills[#recentKills + 1] = e
    C_Timer.After(KILL_HOLD, function() SayKill(e) end)
    return false, e
end

local function FullSender(sender)
    if sender:find("-", 1, true) or sender:find(" ", 1, true) then return sender end
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) == "string" and realm ~= "" then return sender .. "-" .. realm end
    return sender
end
ns.FullSender = FullSender

-- 3.7.10 diagnostics: what reaches the client and why anything is dropped,
-- shown by /warpath share status. Counts this session only; nothing saved.
local diag = { all = 0, allInside = 0, ours = 0, oursInside = 0, unreadable = 0, unreadableInside = 0,
    secretPrefix = 0, own = 0, dup = 0, folded = 0, bad = 0, off = 0, errors = 0, lockdownSeen = 0, channels = {} }
local function Lockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return nil end
    local ok, v = pcall(f)
    if ok and not Secret(v) then return v == true end
end

-- 3.7.8: guildmates' messages are received everywhere, battlegrounds,
-- arenas, dungeons and raids included, so you hear about their open-world
-- kills and deaths while you're inside and their pins are waiting on your
-- map when you come out. Inside, Warpath still sends nothing and records
-- nothing of yours.
local function Receive(prefix, text, channel, sender)
    local inside = S.inInstance
    diag.all = diag.all + 1
    if inside then diag.allInside = diag.allInside + 1 end
    if Lockdown() then diag.lockdownSeen = diag.lockdownSeen + 1 end
    if Secret(prefix) then diag.secretPrefix = diag.secretPrefix + 1 return end
    if inside and type(channel) == "string" and not Secret(channel) then
        diag.channels[channel] = (diag.channels[channel] or 0) + 1
    end
    if prefix ~= C.COMM then return end
    diag.ours = diag.ours + 1
    if inside then diag.oursInside = diag.oursInside + 1 end
    if not cfg.share then diag.off = diag.off + 1 return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then
        diag.unreadable = diag.unreadable + 1
        if inside then diag.unreadableInside = diag.unreadableInside + 1 end
        return
    end
    if sender == myFull or Ambiguate(sender, "short") == myName or ns.IsMe(sender) or ns.IsEcho(text, sender) then
        diag.own = diag.own + 1
        return
    end
    -- battle-haze sync (3.7): hellos and history
    local head = text:sub(1, 4)
    if head == C.PROTO .. "|H|" or head == C.PROTO .. "|B|" then
        if ns.Sync then ns.Sync.OnMessage(text, FullSender(sender), channel) end
        return
    end
    local now = GetTime()
    -- The same message arrives twice from a guildmate who is also in your
    -- group (GUILD and PARTY/RAID): keep the first copy.
    local key = sender .. "\031" .. text
    if dupSeen[key] and now - dupSeen[key] < 10 then diag.dup = diag.dup + 1 return end
    dupSeen[key] = now

    local sep = text:find(";", 1, true) and ";" or "|" -- 3.3.0 used "|"
    local ver, kind, mapID, x, y, f1, f2, f3, f4, f5, f6, f7, f8, f9 = strsplit(sep, text)
    -- Flood guard for sightings only: at most 6 per sender per 10 seconds.
    -- Kills, deaths and test pings always get through (the sender already
    -- limits them). Until 3.6.1 a 3-second limit on every message dropped
    -- kills that came right after a sighting, which in a fight is most of them.
    if kind == "S" then
        local b = senderSeen[sender]
        if not b or now - b.t >= 10 then b = { t = now, n = 0 } senderSeen[sender] = b end
        if b.n >= 6 then return end
        b.n = b.n + 1
    end
    if now - lastSweep > 60 then
        lastSweep = now
        for k, t in pairs(dupSeen) do if now - t >= 10 then dupSeen[k] = nil end end
        for k, b in pairs(senderSeen) do if now - b.t >= 10 then senderSeen[k] = nil end end
    end
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if ver ~= C.PROTO or (kind ~= "S" and kind ~= "D" and kind ~= "K" and kind ~= "T") then diag.bad = diag.bad + 1 return end
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then diag.bad = diag.bad + 1 return end
    if not C_Map.GetMapInfo(mapID) then diag.bad = diag.bad + 1 return end
    shareStats.got = shareStats.got + 1
    if kind == "S" then -- a sighting in a neutral town you've walked through
        local z = db.maps[mapID]
        if z and z.town and z.town[Cell(x, y, C.SW, C.SH)] then return end
    end
    local from = Ambiguate(sender, "short")

    if kind == "T" then -- a test ping: always announced, shown for two minutes
        shared[#shared + 1] = { kind = "S", mapID = mapID, x = x, y = y, t = time(), from = from, expire = time() + 120 }
        S.dirty = true
        Print(("test ping from %s in %s received. Sharing works."):format(from, MapName(mapID)))
        return
    end

    local full = FullSender(sender)
    local zone = MapName(mapID)
    local say = cfg.guildChat ~= false
    local said, kill
    if kind == "K" then said, kill = NoteKill(f9, mapID, x, y, full, from) end
    if said then
        -- someone already said this kill: their haze only, no pin, no line
        diag.folded = diag.folded + 1
        ns.AddHeat(ns.GuildLayer(mapID, "guildBattle", full), Cell(x, y, C.SW, C.SH), 1)
        S.dirty = true
        return
    end
    if kind == "S" then
        if #shared >= 200 then table.remove(shared, 1) end
        shared[#shared + 1] = { kind = kind, mapID = mapID, x = x, y = y, t = time(), from = from,
            expire = time() + C.SIGHT_LIVE }
    else
        -- Kills and deaths are saved (3.7.4), so they can fade over 3 days
        -- instead of vanishing at logout. 300 per zone, oldest dropped.
        local z = ns.ZoneData(mapID)
        z.gmarks = z.gmarks or {}
        z.gmarks[#z.gmarks + 1] = { kind = kind, x = x, y = y, t = time(), from = from, full = full }
        if kill then kill.pin = z.gmarks[#z.gmarks] end
        while #z.gmarks > C.GMARK_CAP do table.remove(z.gmarks, 1) end
    end
    S.dirty = true
    -- A guildmate's kills and deaths go into their own layer of the haze
    -- (3.7), never into yours; deaths also into their dangerous ground.
    local c = Cell(x, y, C.SW, C.SH)
    if kind == "K" or kind == "D" then
        ns.AddHeat(ns.GuildLayer(mapID, "guildBattle", full), c, 1)
        if kind == "D" then ns.AddHeat(ns.GuildLayer(mapID, "guildDeaths", full), c, 1) end
        if ns.Ground then ns.Ground.Forget(mapID) end
    end
    -- Kills and deaths get one chat line wherever they happen, unless that's
    -- turned off (3.8.3); sightings are map-only. A 3.7 sender's line carries
    -- the tier and feat.
    if kind == "K" then
        -- printed by NoteKill's timer, with anyone else who has credit
        if say then kill.line = ns.Feats.GuildKillLine(from, zone, f1, f2, f3, f4, f5, f6, f7, f8, f9) end
    elseif kind == "D" then
        if f1 and f1 ~= "" then ns.Feats.GuildDeath(f1, from) end
        if say then Print(ns.Feats.GuildDeathLine(from, zone, f1, f2, f3, f4 or "")) end
    end
    if kind ~= "S" then
        shareStats.lastEvent = ("%s %s in %s, %s"):format(from, kind == "K" and "kill" or "death", zone, date("%H:%M"))
    end
end

-- Errors are counted, not raised, so a bad message can't stop the next one.
local function OnComm(...)
    local ok, err = pcall(Receive, ...)
    if not ok then
        diag.errors = diag.errors + 1
        diag.lastError = Secret(err) and "(unreadable)" or tostring(err)
    end
end

local function DiagStatus()
    local d = diag
    Print(("diagnostics: %d Warpath messages reached your client (%d inside an instance), %d unreadable (%d inside), %d errors."):format(
        d.ours, d.oursInside, d.unreadable, d.unreadableInside, d.errors))
    Print(("dropped: %d your own echo, %d duplicates, %d repeat kills of one enemy, %d malformed%s."):format(
        d.own, d.dup, d.folded, d.bad, d.off > 0 and (", " .. d.off .. " while sharing was off") or ""))
    local parts = {}
    for ch, n in pairs(d.channels) do parts[#parts + 1] = ch .. " " .. n end
    table.sort(parts)
    local lock = Lockdown()
    Print(("inside instances: %d addon messages from all addons%s, %d with an unreadable prefix. Chat lockdown now: %s (on for %d arrivals)."):format(
        d.allInside, #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "", d.secretPrefix,
        lock == nil and "unknown" or (lock and "on" or "off"), d.lockdownSeen))
    if d.lastError then Print("last error: " .. d.lastError) end
end

-- Shared with the other files.
ns.DiagStatus = DiagStatus
ns.NoteKill = NoteKill
ns.FlushShare = FlushShare
ns.OnComm = OnComm
ns.Share = Share
ns.shareStats = shareStats
