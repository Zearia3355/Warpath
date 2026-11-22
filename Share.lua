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
-- Sharing (opt in). Sends only: an enemy was seen here / I died to PvP here.
-- Never your trail, never anyone's name.
---------------------------------------------------------------------------

local shareStats = { sent = 0, refused = 0, got = 0, lastRefusal = nil }

local function Share(kind, mapID, x, y, force)
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
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, C.COMM, msg, channel)
    if ok and (res == nil or res == true or res == 0) then
        shareStats.sent = shareStats.sent + 1
    else
        shareStats.refused = shareStats.refused + 1
        shareStats.lastRefusal = channel .. ": " .. tostring(ok and res or "error")
    end
end

local function FlushShare()
    if not cfg.share or #outQ == 0 or S.inInstance then return end
    local msg = table.remove(outQ, 1)
    if IsInGuild() then SendOne(msg, "GUILD") end
    if IsInRaid() then
        SendOne(msg, "RAID")
    elseif IsInGroup() then
        SendOne(msg, "PARTY")
    end
end

-- The zone a map belongs to: a cave, town or other sub-map counts as its
-- zone, so "in your zone" holds when one of you is in a sub-map.
local function ZoneOf(mapID)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    for _ = 1, 5 do
        if not mapID or Secret(mapID) then return nil end
        local info = C_Map.GetMapInfo(mapID)
        if not info or not info.mapType or info.mapType <= zoneType
            or not info.parentMapID or info.parentMapID == 0 then return mapID end
        mapID = info.parentMapID
    end
    return mapID
end

local function OnComm(prefix, text, _, sender)
    if prefix ~= C.COMM or not cfg.share or S.inInstance then return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if sender == myFull or Ambiguate(sender, "short") == myName then return end
    local now = GetTime()
    -- The same message arrives twice from a guildmate who is also in your
    -- group (GUILD and PARTY/RAID): keep the first copy.
    local key = sender .. "\031" .. text
    if dupSeen[key] and now - dupSeen[key] < 10 then return end
    dupSeen[key] = now

    local sep = text:find(";", 1, true) and ";" or "|" -- 3.3.0 used "|"
    local ver, kind, mapID, x, y = strsplit(sep, text)
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
    if ver ~= C.PROTO or (kind ~= "S" and kind ~= "D" and kind ~= "K" and kind ~= "T") then return end
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if not C_Map.GetMapInfo(mapID) then return end
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

    if #shared >= 200 then table.remove(shared, 1) end
    shared[#shared + 1] = {
        kind = kind, mapID = mapID, x = x, y = y, t = time(), from = from,
        expire = time() + (kind == "S" and C.SIGHT_LIVE or C.SHARED_DEATH),
    }
    S.dirty = true
    if kind == "K" or kind == "D" then ns.AddBattle(mapID, x, y, C.BATTLE_W.shared) end
    -- Kills and deaths get a chat line in your zone; sightings are map-only.
    if kind ~= "S" and ZoneOf(mapID) == ZoneOf(C_Map.GetBestMapForUnit("player")) then
        Print(("%s %s in %s."):format(from, kind == "K" and "scored a kill" or "was killed", MapName(mapID)))
    end
end

-- Shared with the other files.
ns.FlushShare = FlushShare
ns.OnComm = OnComm
ns.Share = Share
ns.shareStats = shareStats
