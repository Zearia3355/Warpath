-- Warpath: Sync
-- Guild-wide battle haze (3.7). At login Warpath says hello over the guild's
-- addon channel; guildmates running 3.7 whisper back the parts of their own
-- battle haze (and dangerous ground) that changed since they last sent you
-- theirs, a little at a time behind kills, deaths and sightings. Each
-- guildmate's history is kept in its own layer, so nothing counts twice and
-- your own haze is never sent back to anyone as theirs.
--
-- Messages: "1|H|<full>|<version>"  hello; full = 1 asks for everything
--           again. The version (3.8.1) tells guildmates a newer Warpath is
--           out; older versions read only <full> and ignore the rest.
--           "1|B|<map>|<layer b|d>|<clear 0|1>|<cells>"  cells are
--           3 base-36 characters of cell index + 2 of strength (0.01 steps).
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Long, Print = ns.Long, ns.Print

local db, gdb, cfg, myFull
ns.OnBind(function() db, gdb, cfg, myFull = ns.db, ns.gdb, ns.cfg, ns.myFull end)

local Sync = { queue = {}, stats = { sentMsgs = 0, gotMsgs = 0, gotFrom = {}, last = nil } }
local helloed = {}           -- sender -> true: we've asked them this session
local answering = {}         -- sender -> true: a reply is scheduled
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local PER_MSG = 44
local MAX_QUEUE = 400

local function Enc(n, width)
    local out = ""
    for _ = 1, width do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end

local function Dec(str)
    local n = 0
    for i = 1, #str do
        local d = B36:find(str:sub(i, i), 1, true)
        if not d then return end
        n = n * 36 + d - 1
    end
    return n
end

local function Send(msg, target)
    if target and ns.IsMe(target) then return end
    if not target then ns.NoteSent(msg) end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, C.COMM, msg, target and "WHISPER" or "GUILD", target)
    if ok and (res == nil or res == true or res == 0) then Sync.stats.sentMsgs = Sync.stats.sentMsgs + 1 end
end

-- Called by the share queue when it has nothing more urgent to send.
function Sync.FlushOne()
    local item = table.remove(Sync.queue, 1)
    if item then Send(item.msg, item.to) return true end
end

function Sync.Hello(full, to)
    if not cfg.share or S.inInstance then return end
    if not to and not IsInGuild() then return end
    Send(("%s|H|%s|%s"):format(C.PROTO, full and "1" or "0", ns.VERSION or ""), to)
end

local function HaveGuildLayers()
    for _, z in pairs(db.maps) do
        if z.guildBattle and next(z.guildBattle) then return true end
    end
    return false
end

-- At login, a little after everything else.
function Sync.Start()
    if not cfg.share or not IsInGuild() then return end
    C_Timer.After(8 + math.random() * 8, function() Sync.Hello(not HaveGuildLayers()) end)
end

-- Queue everything of yours that changed since you last sent to this guildmate.
local function Answer(to, full)
    answering[to] = nil
    if not cfg.share or not cfg.shareHistory or S.inInstance then return end
    db.syncSent = db.syncSent or {}
    local since = (not full and db.syncSent[to]) or -1
    local now = time()
    for mapID, z in pairs(db.maps) do
        local town = z.town or {}
        for _, pair in ipairs({ { "b", z.battle }, { "d", z.deaths } }) do
            local cells = {}
            for c, e in pairs(pair[2] or {}) do
                if not town[c] and (e.ts or 0) > since then
                    local v = math.min(1295, math.floor(Long(e) * 100 + 0.5))
                    if v >= 5 then cells[#cells + 1] = Enc(c, 3) .. Enc(v, 2) end
                end
            end
            for i = 1, #cells, PER_MSG do
                if #Sync.queue >= MAX_QUEUE then break end
                local chunk = table.concat(cells, "", i, math.min(#cells, i + PER_MSG - 1))
                local clear = (full or since < 0) and i == 1 and "1" or "0"
                Sync.queue[#Sync.queue + 1] = { to = to,
                    msg = ("%s|B|%d|%s|%s|%s"):format(C.PROTO, mapID, pair[1], clear, chunk) }
            end
        end
    end
    db.syncSent[to] = now
end

-- A guildmate runs a newer release (3.8.1): say so once a session, and
-- again only for an even newer one. Test builds ("3.8.2-test1") aren't
-- published, so they never count.
local newestTold
local function CheckVersion(text)
    local _, _, _, ver = strsplit("|", text)
    if type(ver) ~= "string" or #ver > 12 or not ver:match("^%d+%.%d+%.%d+$") then return end
    if not ns.VersionOlder(ns.VERSION, ver) then return end
    if newestTold and not ns.VersionOlder(newestTold, ver) then return end
    newestTold = ver
    Print(("Warpath %s is out (you have %s): a guildmate is running it. Update from the CurseForge app, as \"Warpath Forever\".")
        :format(ver, ns.VERSION or "?"))
end
Sync.NewestTold = function() return newestTold end -- for tests

local function OnHello(text, sender, channel)
    CheckVersion(text)
    local full = text:sub(5, 5) == "1"
    -- ask them for theirs too, once a session
    if channel ~= "WHISPER" and not helloed[sender] then
        helloed[sender] = true
        C_Timer.After(1 + math.random() * 4, function() Sync.Hello(not HaveGuildLayers(), sender) end)
    end
    helloed[sender] = true
    if answering[sender] or not cfg.shareHistory then return end
    answering[sender] = true
    C_Timer.After(3 + math.random() * 17, function() Answer(sender, full) end)
end

local function OnHistory(text, sender)
    local _, _, mapID, layer, clear, cells = strsplit("|", text)
    mapID = tonumber(mapID)
    if not mapID or not cells or (layer ~= "b" and layer ~= "d") or not C_Map.GetMapInfo(mapID) then return end
    local key = layer == "b" and "guildBattle" or "guildDeaths"
    local t = ns.GuildLayer(mapID, key, sender)
    if clear == "1" then for c in pairs(t) do t[c] = nil end end
    local play = ns.PlayNow()
    for i = 1, #cells - 4, 5 do
        local c, v = Dec(cells:sub(i, i + 2)), Dec(cells:sub(i + 3, i + 4))
        if c and v and c < C.SW * C.SH then t[c] = { l = v / 100, tl = play } end
    end
    Sync.stats.gotMsgs = Sync.stats.gotMsgs + 1
    Sync.stats.gotFrom[sender] = true
    Sync.stats.last = time()
    if ns.Ground then ns.Ground.Forget(mapID) end
    S.dirty = true
end

function Sync.OnMessage(text, sender, channel)
    if ns.IsMe(sender) then return end
    if text:sub(3, 3) == "H" then OnHello(text, sender, channel) else OnHistory(text, sender) end
end

-- The game said a whisper's target isn't online: drop what's queued for them.
function Sync.Unreachable(name)
    local n = 0
    for i = #Sync.queue, 1, -1 do
        local to = Sync.queue[i].to
        if to == name or to == name .. "-" or (to:gsub("%-$", "")) == name then table.remove(Sync.queue, i) n = n + 1 end
    end
    return n
end

-- /warpath share sync: ask every guildmate for everything again.
function Sync.Request()
    if not cfg.share then Print("sharing is off. /warpath share on turns it on.") return end
    if not IsInGuild() then Print("you're not in a guild.") return end
    Sync.Hello(true)
    Print("asked guildmates running Warpath 3.7 for their battle history. It arrives over the next minute or two.")
end

function Sync.Status()
    local senders, cells = {}, 0
    for _, z in pairs(db.maps) do
        for who, layer in pairs(z.guildBattle or {}) do
            senders[who] = true
            for _ in pairs(layer) do cells = cells + 1 end
        end
    end
    local n = 0
    for _ in pairs(senders) do n = n + 1 end
    Print(("guild battle haze: %d guildmate%s, %d spots | this session %d history messages received, %d sent, %d waiting%s")
        :format(n, n == 1 and "" or "s", cells, Sync.stats.gotMsgs, Sync.stats.sentMsgs, #Sync.queue,
            cfg.shareHistory and "" or " | sharing your history is OFF"))
end

ns.Sync = Sync
