-- Warpath: Record
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Cell, Credit, FullName, MapName, Notice, PlayerPos = ns.Cell, ns.Credit, ns.FullName, ns.MapName, ns.Notice, ns.PlayerPos
local Print, Q, Recent, Secret, Simplify, Sound = ns.Print, ns.Q, ns.Recent, ns.Secret, ns.Simplify, ns.Sound
local WorldXY, ZoneData, cur, killCallbacks, recentSight, session = ns.WorldXY, ns.ZoneData, ns.cur, ns.killCallbacks, ns.recentSight, ns.session
local Foes, Victim, Share = ns.Foes, ns.Victim, ns.Share

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local roadSeen, fieldCache, fieldWarned = {}, {}, {}
local hist = {}
local sightSeen, grudgeWarned = {}, {}
local lastHostile, pendingAvenge = -1000, nil
local lastShot, shotPending = -1000, nil

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Mode()
    if UnitIsGhost("player") then return "g" end
    if UnitOnTaxi("player") then return "f" end
end

-- A flight's stretch through a zone, matched to earlier flights by its two
-- ends (flight paths are fixed). A match strengthens one route record with
-- road-style long memory instead of adding a copy.
local function AddFlightRoute(mapID, s)
    local n = #s / 2
    if n < 2 then return end
    local ax, ay, bx, by = s[1], s[2], s[2 * n - 1], s[2 * n]
    if (bx - ax) ^ 2 + (by - ay) ^ 2 < 0.05 * 0.05 then return end
    local z = ZoneData(mapID)
    local now, today = time(), tonumber(date("%y%j"))
    local tol = C.ROUTE_MATCH * C.ROUTE_MATCH
    local function Near(x1, y1, x2, y2) return (x1 - x2) ^ 2 + (y1 - y2) ^ 2 < tol end
    for _, r in ipairs(z.routes) do
        local m = #r
        if (Near(r[1], r[2], ax, ay) and Near(r[m - 1], r[m], bx, by))
            or (Near(r[1], r[2], bx, by) and Near(r[m - 1], r[m], ax, ay)) then
            Credit(r, now, today)
            return
        end
    end
    local r = { l = 0, tl = now }
    for i = 1, #s do r[i] = s[i] end
    Credit(r, now, today)
    z.routes[#z.routes + 1] = r
end

-- Finish the stroke being recorded: simplify it, and remember a flight's route.
local function CloseStroke()
    local s = cur.stroke
    if not s then return end
    Simplify(s)
    if s.k == "f" and cur.map then AddFlightRoute(cur.map, s) end
    cur.stroke = nil
end

-- Walking goes to the trail; corpse runs and flights to their own store.
-- Every point carries its time (seconds since the stroke began) in s.ts.
local function NewStroke(mapID, x, y, mode)
    CloseStroke()
    local z = ZoneData(mapID)
    local now = time()
    local s = { t = now, e = now, k = mode, ts = { 0 }, Q(x), Q(y) }
    local list = mode and z.runs or z.strokes
    list[#list + 1] = s
    cur.map, cur.stroke, cur.mode, cur.x, cur.y = mapID, s, mode, x, y
    cur.wx, cur.wy = WorldXY(mapID, x, y)
    session.zones[mapID] = true
    S.dirty = true
end

-- Are you going somewhere, or milling about? Compares where you are with
-- where you were up to 30 seconds ago.
local function Travelling(mapID, x, y)
    local n = #hist
    if hist.map ~= mapID or (n > 0 and (math.abs(x - hist[n - 1]) > C.JUMP_STEP or math.abs(y - hist[n]) > C.JUMP_STEP)) then
        hist = { map = mapID }
    end
    hist[#hist + 1] = x
    hist[#hist + 1] = y
    if #hist > C.HIST * 2 then
        table.remove(hist, 1)
        table.remove(hist, 1)
    end
    n = #hist / 2
    if n < 20 then return false end
    local dx, dy = (x - hist[1]) * C.GW, (y - hist[2]) * C.GH -- in cells
    local need = C.TRAVEL_CELLS * n / C.HIST
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
    local c = Cell(x, y, C.GW, C.GH)
    local z = ZoneData(mapID)
    local ox, oy = z.cx[c], z.cy[c]
    z.cx[c] = ox and Q(ox + (x - ox) * 0.2) or Q(x)
    z.cy[c] = oy and Q(oy + (y - oy) * 0.2) or Q(y)
    local now, today = time(), tonumber(date("%y%j"))

    local key = mapID * 10000 + c
    if key == cur.cell then
        -- Lingering: 20 seconds in one cell marks it as a haunt for today.
        cur.dwell = (cur.dwell or 0) + 1
        if cur.dwell == C.DWELL_SAMPLES then
            local e = z.heat[c]
            if not e then e = { l = 0, tl = now } z.heat[c] = e end
            Credit(e, now, today)
            S.dirty = true
        end
        return
    end

    local prev = cur.rc
    if prev and cur.cell and math.floor(cur.cell / 10000) == mapID then
        local dx = math.abs(prev % C.GW - c % C.GW)
        local dy = math.abs(math.floor(prev / C.GW) - math.floor(c / C.GW))
        if dx <= 2 and dy <= 2 then
            local edge = math.min(prev, c) * 10000 + math.max(prev, c)
            local e = z.road[edge]
            if not e then e = { l = 0, tl = now, r = 0, tr = now } z.road[edge] = e end
            local seenKey = mapID .. ":" .. edge
            local clock = GetTime()
            if not roadSeen[seenKey] or clock - roadSeen[seenKey] >= C.ROAD_COOLDOWN then
                roadSeen[seenKey] = clock
                e.r, e.tr = math.min(C.RECENT_CAP, Recent(e, now) + 1), now
            end
            e.tp = now
            if travelling then Credit(e, now, today) end
            S.dirty = true
        end
    end
    cur.cell, cur.rc, cur.dwell = key, c, 0
end

local function Sample()
    local mapID, x, y = PlayerPos()
    if not mapID then
        CloseStroke()
        return
    end
    local mode = Mode()
    Visit(mapID, x, y, mode)

    if mapID ~= cur.map or not cur.stroke then return NewStroke(mapID, x, y, mode) end

    local dx, dy = x - cur.x, y - cur.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > C.JUMP_STEP then return NewStroke(mapID, x, y, mode) end
    if mode ~= cur.mode then return NewStroke(mapID, cur.x, cur.y, mode) end
    if d < C.MIN_STEP then return end

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

    if #cur.stroke >= (mode and C.RUN_MAX or C.STROKE_MAX) * 2 then NewStroke(mapID, cur.x, cur.y, mode) end
    local s = cur.stroke
    local now = time()
    s[#s + 1] = Q(x)
    s[#s + 1] = Q(y)
    s.ts = s.ts or {}
    s.ts[#s / 2] = now - s.t
    s.e = now
    cur.x, cur.y, cur.wx, cur.wy = x, y, wx, wy
    S.dirty = true
end

local function See(unit)
    if S.inInstance or not S.ready then return end
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

    if gdb.kos[full] and (not grudgeWarned[full] or now - grudgeWarned[full] > C.GRUDGE_COOLDOWN) then
        grudgeWarned[full] = now
        Notice("Grudge sighted: " .. short, 1, 0.5, 0)
        Sound("READY_CHECK", 8960)
    end

    if sightSeen[full] and now - sightSeen[full] < C.SIGHT_DEDUPE then return end
    sightSeen[full] = now
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local c = Cell(x, y, C.SW, C.SH)
    z.sight[c] = (z.sight[c] or 0) + 1
    session.sightings = session.sightings + 1
    if #recentSight >= 100 then table.remove(recentSight, 1) end
    recentSight[#recentSight + 1] = { mapID = mapID, x = x, y = y, t = time() }
    Share("S", mapID, x, y)
    S.dirty = true
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
    Print("you now hold a grudge against " .. C.GOLD .. full .. "|r. You'll be told when you see them.")
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
        local cells, cutoff = {}, time() - C.FIELD_DAYS * C.DAY
        for _, m in ipairs(z.marks) do
            if m[4] == "death" and m.pvp and m[3] >= cutoff then
                local key = math.floor(m[1] / C.CELL) * 1000 + math.floor(m[2] / C.CELL)
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
        if dx * dx + dy * dy < C.FIELD_RADIUS * C.FIELD_RADIUS
            and (not fieldWarned[fld.key] or now - fieldWarned[fld.key] > C.FIELD_COOLDOWN) then
            fieldWarned[fld.key] = now
            Notice(("Killing field: you have died here %d times"):format(fld.n), 1, 0.25, 0.2)
            Sound("RAID_WARNING", 8959)
        end
    end
end

---------------------------------------------------------------------------
-- Kills and deaths
---------------------------------------------------------------------------

local function AddMark(kind, extra)
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local m = { Q(x), Q(y), time(), kind }
    for k, v in pairs(extra or {}) do m[k] = v end
    z.marks[#z.marks + 1] = m
    if #z.marks > C.MARK_CAP then table.remove(z.marks, 1) end
    db[kind == "death" and "lastDeath" or "lastKill"] = { mapID, m[1], m[2], m[3] }
    S.dirty = true
    return m, mapID, z
end


---------------------------------------------------------------------------
-- Kill shots
---------------------------------------------------------------------------

local RecentlyInCombat, TakeKillShot, FinishShot, Notable
do
function RecentlyInCombat()
    if not cfg.shot.combat then return true end
    return UnitAffectingCombat("player") or (GetTime() - S.lastCombatEnd) <= C.COMBAT_GRACE
end

local function Ordinal(n)
    local tens, ones = n % 100, n % 10
    if tens >= 11 and tens <= 13 then return n .. "th" end
    return n .. (ones == 1 and "st" or ones == 2 and "nd" or ones == 3 and "rd" or "th")
end

local ClassName = ns.ClassName

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
    if k.streak and k.streak >= 2 then parts[#parts + 1] = C.GOLD .. TIMES .. k.streak .. "|r" end
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
        if p.entry then p.entry.shot = gdb.shotCount end
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
    local token = { mark = mark, after = after, test = test, entry = k.entry }
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
    if S.inInstance then return end
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
    if z then
        z.kills = z.kills + 1
        z.streak = (z.streak or 0) + 1
        if z.streak > (z.bestStreak or 0) then z.bestStreak = z.streak end
    end
    if m then Share("K", mapID, m[1], m[2]) end

    -- Avenged: a kill near your own fresh skull.
    local avenged = false
    local p = pendingAvenge
    if p and m and mapID == p.mapID and GetTime() - p.at < C.AVENGE_WINDOW then
        local dx, dy = m[1] - p.mark[1], m[2] - p.mark[2]
        if dx * dx + dy * dy < C.AVENGE_RADIUS * C.AVENGE_RADIUS then
            p.mark.av = math.floor(GetTime() - p.at)
            m.av = p.mark.av
            pendingAvenge, avenged = nil, true
            session.avenged = session.avenged + 1
            z.avenged = (z.avenged or 0) + 1
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
    local tag = k.avenged and "avenged" or k.grudge and "grudge" or times == 1 and "first"
        or ((k.streak == 3 or k.streak == 5 or k.streak % 10 == 0) and "streak") or nil
    if m then
        m.tag, m.streak, m.times = tag, session.streak, times
        k.entry = ns.CampaignKill({ n = short, f = full, c = class, z = mapID, x = m[1], y = m[2],
            t = m[3], tag = tag, st = session.streak, grudge = k.grudge })
    end
    if cfg.shot.on and m and (cfg.shot.mode == "all" or Notable(k))
        and GetTime() - lastShot >= C.SHOT_THROTTLE then
        lastShot = GetTime()
        TakeKillShot(k, m, Announce)
    else
        Announce()
    end
    if session.streak == 3 or session.streak == 5 or session.streak % 10 == 0 then
        Print(("%s%s|r %d kills without dying."):format(C.GOLD, faction.cry, session.streak))
    end

    if m then
        local ctx = {
            mapID = mapID, zone = MapName(mapID), x = m[1], y = m[2], time = m[3],
            streak = session.streak, victim = short, victimFull = full, timesKilled = times,
        }
        for _, fn in ipairs(killCallbacks) do pcall(fn, ctx) end
    end
    ns.UpdateHUD()
end

-- The game can hand out more than one honorable-kill credit for a single
-- enemy death. Credits that arrive within two seconds are one kill unless they
-- name a different dead enemy, and the same victim is never counted twice
-- within 10 seconds. Two enemies dying at once with only one of them targeted
-- counts as one kill: undercounting beats counting phantoms.
function Foes.OnCredit()
    Foes.credits = Foes.credits + 1
    if S.inInstance or not RecentlyInCombat() then return end
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
    if S.inInstance then return end
    local recentFoe = Foes.last and GetTime() - Foes.last.at < C.PVP_WINDOW and Foes.last or nil
    local pvp = GetTime() - lastHostile < C.PVP_WINDOW or recentFoe or Foes.PlayerNearby()
    -- The killer: the enemy you were fighting (the game hides who landed the blow).
    local m, mapID, z = AddMark("death", { pvp = pvp and true or nil,
        kn = pvp and recentFoe and recentFoe.short or nil, kc = pvp and recentFoe and recentFoe.class or nil })
    if pvp then
        session.deaths = session.deaths + 1
        db.deaths = db.deaths + 1
        if session.streak >= 3 then
            Print(("your streak ends at %s%d|r."):format(C.GOLD, session.streak))
        end
        ns.CampaignDeath({ n = m and m.kn, c = m and m.kc, z = mapID, x = m and m[1], y = m and m[2],
            t = time() }, session.streak)
        session.streak = 0
        for _, zz in pairs(db.maps) do zz.streak = 0 end
        if m then
            z.pdeaths = z.pdeaths + 1
            fieldCache[mapID] = nil
            pendingAvenge = { mapID = mapID, mark = m, at = GetTime() }
            Share("D", mapID, m[1], m[2])
        end
    end
    ns.UpdateHUD()
end

-- Forget recording state (/warpath clear).
function ns.ResetRecording()
    fieldCache, roadSeen, pendingAvenge = {}, {}, nil
end
function ns.ForgetFields(mapID) fieldCache[mapID] = nil end

-- Shared with the other files.
ns.AddFlightRoute = AddFlightRoute
ns.CheckFields = CheckFields
ns.CloseStroke = CloseStroke
ns.Fields = Fields
ns.FinishShot = FinishShot
ns.OnDeath = OnDeath
ns.Sample = Sample
ns.See = See
ns.TakeKillShot = TakeKillShot
ns.ToggleGrudge = ToggleGrudge
