-- Warpath: Share
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Cell, MapName, Print, Secret, outQ, shared = ns.Cell, ns.MapName, ns.Print, ns.Secret, ns.outQ, ns.shared

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local shareSeen, senderSeen = {}, {}

---------------------------------------------------------------------------
-- Sharing (opt in). Sends only: an enemy was seen here / I died to PvP here.
-- Never your trail, never anyone's name.
---------------------------------------------------------------------------

local shareStats = { sent = 0, refused = 0, got = 0, lastRefusal = nil }

local function Share(kind, mapID, x, y, force)
    if not cfg.share then return end
    if not force then
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

local function OnComm(prefix, text, _, sender)
    if prefix ~= C.COMM or not cfg.share or S.inInstance then return end
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    if sender == myFull or Ambiguate(sender, "short") == myName then return end
    local now = GetTime()
    if senderSeen[sender] and now - senderSeen[sender] < 3 then return end -- per-sender rate limit
    senderSeen[sender] = now

    local sep = text:find(";", 1, true) and ";" or "|" -- 3.3.0 used "|"
    local ver, kind, mapID, x, y = strsplit(sep, text)
    mapID, x, y = tonumber(mapID), tonumber(x), tonumber(y)
    if ver ~= C.PROTO or (kind ~= "S" and kind ~= "D" and kind ~= "K" and kind ~= "T") then return end
    if not mapID or not x or not y or x < 0 or x > 1 or y < 0 or y > 1 then return end
    if not C_Map.GetMapInfo(mapID) then return end
    shareStats.got = shareStats.got + 1
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
    -- Kills and deaths get a chat line in your zone; sightings are map-only.
    if kind ~= "S" and mapID == C_Map.GetBestMapForUnit("player") then
        Print(("%s %s in %s."):format(from, kind == "K" and "scored a kill" or "was killed", MapName(mapID)))
    end
end

-- Shared with the other files.
ns.FlushShare = FlushShare
ns.OnComm = OnComm
ns.Share = Share
ns.shareStats = shareStats
