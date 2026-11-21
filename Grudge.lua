-- Warpath: Grudge
-- Your ledger of grudges, shared by all your characters (gdb.kos, keyed by
-- Name-Realm). A grudge only ever leaves the ledger when you forgive it:
-- killing one counts it as settled and nothing more.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local MapName, Notice, PlayerPos, Print, Sound, FullName, Ago = ns.MapName, ns.Notice, ns.PlayerPos, ns.Print, ns.Sound, ns.FullName, ns.Ago
local Foes = ns.Foes

local db, gdb, cfg
ns.OnBind(function() db, gdb, cfg = ns.db, ns.gdb, ns.cfg end)

local Grudge = {}
local alerted = {}      -- full -> GetTime() of the last sighting alert
local offered = {}      -- full -> true once offered this session
local pending           -- { full, class, at }: the last grudge offered in chat
local live = {}         -- full -> { full, short, class, mapID, x, y, t } recent sightings, for the map

local function Short(full) return (full:gsub("%-.*$", "")) end
Grudge.Short = Short

-- Case-insensitive lookup; returns the stored key and the record.
local function Find(full)
    if not full or not gdb then return end
    local r = gdb.kos[full]
    if r then return full, r end
    local low = full:lower()
    for k, v in pairs(gdb.kos) do
        if k:lower() == low then return k, v end
    end
end

-- 3.5: a grudge was just the time it was added; now it's a record.
function Grudge.Upgrade()
    gdb.kos = gdb.kos or {}
    gdb.killers = gdb.killers or {}
    for k, v in pairs(gdb.kos) do
        if type(v) ~= "table" then
            gdb.kos[k] = { added = tonumber(v) or time(), kills = 0, deaths = 0, settled = 0, log = {} }
        end
        local r = gdb.kos[k]
        r.kills, r.deaths, r.settled, r.log = r.kills or 0, r.deaths or 0, r.settled or 0, r.log or {}
    end
end

local function Log(r, kind, mapID)
    r.log[#r.log + 1] = { t = time(), k = kind, z = mapID }
    while #r.log > C.GRUDGE_LOG do table.remove(r.log, 1) end
end

-- "killed you 4 times · settled once"
function Grudge.History(r)
    local parts = {}
    if r.deaths > 0 then parts[#parts + 1] = "killed you " .. (r.deaths == 1 and "once" or (r.deaths .. " times")) end
    if r.settled > 0 then parts[#parts + 1] = "settled " .. (r.settled == 1 and "once" or (r.settled .. " times")) end
    return table.concat(parts, " \194\183 ")
end

function Grudge.Get(full) local _, r = Find(full) return r end
function Grudge.Key(full) return (Find(full)) end

-- All grudges as a list: { full, r }.
function Grudge.List()
    local list = {}
    for full, r in pairs(gdb.kos) do list[#list + 1] = { full = full, r = r } end
    return list
end

function Grudge.Count()
    local n = 0
    for _ in pairs(gdb.kos) do n = n + 1 end
    return n
end

-- Something changed: marks on nameplates and the target frame, the map, the book.
function Grudge.Changed()
    S.dirty = true
    Grudge.RefreshMarks()
    if ns.Chronicle and ns.Chronicle.Refresh then ns.Chronicle.Refresh() end
end

-- how: nil (by you) or "auto". Returns the record.
function Grudge.Add(full, class, how)
    local key, r = Find(full)
    if r then
        Print(Short(key) .. " is already in your ledger of grudges.")
        return r
    end
    if type(class) ~= "string" then class = type(Foes.known[full]) == "string" and Foes.known[full] or nil end
    local info = Foes.info[full] or {}
    r = { added = time(), class = class, lv = info.lv, ra = info.ra, gu = info.gu,
        kills = (db.victims and db.victims[full]) or 0,
        deaths = gdb.killers[full] or 0, settled = 0, log = {}, auto = how == "auto" or nil }
    gdb.kos[full] = r
    Log(r, how == "auto" and "a" or "g")
    if pending and pending.full == full then pending = nil end
    Print(("%s %s%s|r. You'll be told when you see them.")
        :format(how == "auto" and "grudge added automatically against" or "you now hold a grudge against", C.GOLD, Short(full)))
    Grudge.Changed()
    return r
end

function Grudge.Forgive(full)
    local key = Find(full)
    if not key then
        Print("no grudge against " .. Short(full) .. " to forgive.")
        return
    end
    gdb.kos[key] = nil
    live[key] = nil
    Print("you forgive " .. Short(key) .. ". Their name is struck from your ledger.")
    Grudge.Changed()
end

function Grudge.SetNote(full, note)
    local _, r = Find(full)
    if not r then return end
    note = note and note:gsub("^%s+", ""):gsub("%s+$", "") or ""
    r.note = note ~= "" and note:sub(1, 120) or nil
end

---------------------------------------------------------------------------
-- What happens in the world
---------------------------------------------------------------------------

function Grudge.OnSighted(full, short, class)
    local key, r = Find(full)
    if not r then return end
    if class and not r.class then r.class = class end
    local info = Foes.info[full]
    if info then r.lv, r.ra, r.gu = info.lv or r.lv, info.ra or r.ra, info.gu or r.gu end
    local mapID, x, y = PlayerPos()
    local now = time()
    if mapID then
        r.seen = { t = now, z = mapID, x = x, y = y }
        live[key] = { full = key, short = short or Short(key), class = r.class, mapID = mapID, x = x, y = y, t = now }
        S.dirty = true
    end
    local last = r.log[#r.log]
    if not (last and last.k == "s" and now - last.t < 600) then Log(r, "s", mapID) end
    local g = cfg.grudge
    if g.alert and (not alerted[key] or GetTime() - alerted[key] > (g.again or 1) * 60) then
        alerted[key] = GetTime()
        local hist = Grudge.History(r)
        Notice("Grudge sighted: " .. (short or Short(key)) .. (mapID and (" \226\128\148 " .. MapName(mapID)) or "")
            .. (hist ~= "" and (" \194\183 " .. hist) or ""), 1, 0.5, 0)
        Sound("READY_CHECK", 8960)
    end
end

function Grudge.OnKill(full, mapID)
    local key, r = Find(full)
    if not r then return end
    r.kills, r.settled = r.kills + 1, r.settled + 1
    Log(r, "k", mapID)
    Print(("grudge against %s settled%s."):format(Short(key),
        r.settled > 1 and (" (" .. r.settled .. " times now)") or ""))
    Grudge.Changed()
end

-- killer: the enemy you were fighting when you fell (full name), if known.
function Grudge.OnDeath(full, class, mapID)
    if not full then return end
    local n = (gdb.killers[full] or 0) + 1
    gdb.killers[full] = n
    local key, r = Find(full)
    if r then
        r.deaths = r.deaths + 1
        if class and not r.class then r.class = class end
        local info = Foes.info[full]
        if info then r.lv, r.ra, r.gu = info.lv or r.lv, info.ra or r.ra, info.gu or r.gu end
        Log(r, "d", mapID)
        Grudge.Changed()
        return
    end
    local g = cfg.grudge
    if g.auto == "off" or n < (g.after or 3) then return end
    if g.auto == "add" then
        Grudge.Add(full, class, "auto")
    elseif not offered[full] then
        offered[full] = true
        pending = { full = full, class = class, at = GetTime() }
        Print(("%s has killed you %d times. Click the skull on the war table, or type %s/warpath grudge|r, to hold a grudge against them.")
            :format(Short(full), n, C.GOLD))
        if ns.GrudgeButtonRefresh then ns.GrudgeButtonRefresh() end
    end
end

-- The grudge last offered in chat, if it's still recent (10 minutes).
function Grudge.Pending()
    if pending and GetTime() - pending.at < 600 and not Find(pending.full) then return pending end
end

-- Recent grudge sightings, for the map.
function Grudge.Live()
    local list, now = {}, time()
    for key, e in pairs(live) do
        if now - e.t > C.GRUDGE_SEEN or not gdb.kos[key] then live[key] = nil else list[#list + 1] = e end
    end
    return list
end

---------------------------------------------------------------------------
-- A small skull on grudges' nameplates and on the target frame
---------------------------------------------------------------------------

local function Mark(holder, anchor, size)
    local t = holder.WarpathGrudgeMark
    if not t then
        t = holder:CreateTexture(nil, "OVERLAY")
        t:SetTexture(C.TEX_SKULL)
        holder.WarpathGrudgeMark = t
    end
    t:SetSize(size, size)
    t:ClearAllPoints()
    if anchor ~= holder then
        t:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    else
        t:SetPoint("BOTTOM", holder, "TOP", 0, -2)
    end
    t:Show()
end

local function Unmark(holder)
    if holder and holder.WarpathGrudgeMark then holder.WarpathGrudgeMark:Hide() end
end

function Grudge.OnPlate(unit, shown)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then return end
    if not shown or not cfg.grudge.plates or S.inInstance then Unmark(plate) return end
    local full = FullName(unit)
    if full and Find(full) then
        local uf = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
        local name = uf and (uf.name or uf.Name)
        if type(name) ~= "table" then name = nil end
        pcall(Mark, plate, name or plate, 16)
    else
        Unmark(plate)
    end
end

local function TargetHolder()
    local tf = TargetFrame
    if not tf then return end
    local portrait = TargetFramePortrait
        or (tf.TargetFrameContainer and tf.TargetFrameContainer.Portrait) or tf.portrait
    return tf, portrait
end

function Grudge.OnTarget()
    if ns.GrudgeButtonRefresh then ns.GrudgeButtonRefresh() end
    local tf, portrait = TargetHolder()
    if not tf then return end
    local full = cfg.grudge.plates and not S.inInstance and FullName("target")
    if full and Find(full) then
        pcall(function()
            local t = tf.WarpathGrudgeMark
            if not t then
                t = tf:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetTexture(C.TEX_SKULL)
                tf.WarpathGrudgeMark = t
            end
            t:SetSize(22, 22)
            t:ClearAllPoints()
            t:SetPoint("BOTTOMLEFT", portrait or tf, "BOTTOMLEFT", -2, -2)
            t:Show()
        end)
    else
        Unmark(tf)
    end
end

function Grudge.RefreshMarks()
    if ns.GrudgeButtonRefresh then ns.GrudgeButtonRefresh() end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and type(plates) == "table" then
        for _, plate in ipairs(plates) do
            local uf = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
            local unit = plate.namePlateUnitToken or (uf and uf.unit)
            if unit then Grudge.OnPlate(unit, true) end
        end
    end
    Grudge.OnTarget()
end

ns.Grudge = Grudge
