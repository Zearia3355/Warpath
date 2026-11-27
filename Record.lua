-- Warpath: Record
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Cell, Credit, FullName, MapName, Notice, PlayerPos = ns.Cell, ns.Credit, ns.FullName, ns.MapName, ns.Notice, ns.PlayerPos
local PlayNow = ns.PlayNow
local Long, Print, Q, Recent, Secret, Simplify, Sound = ns.Long, ns.Print, ns.Q, ns.Recent, ns.Secret, ns.Simplify, ns.Sound
local WorldXY, ZoneData, cur, recentSight, session = ns.WorldXY, ns.ZoneData, ns.cur, ns.recentSight, ns.session
local Foes, Victim, Share = ns.Foes, ns.Victim, ns.Share

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local roadSeen = {}
local hist = {}
local sightSeen = {}
local lastHostile, pendingAvenge = -1000, nil
local lastShot, shotPending = -1000, nil

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Mode()
    if UnitIsGhost("player") then return "g" end
    if UnitOnTaxi("player") then return "f" end
end

-- Finish the stroke being recorded: simplify it, and etch a flight into its legs.
local function CloseStroke()
    local s = cur.stroke
    if not s then return end
    Simplify(s)
    if s.k == "f" and cur.map and ns.Flights then ns.Flights.Add(cur.map, s) end
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

-- Roads follow the road you already have (3.7.12). Nobody walks a route on
-- exactly the same line twice: a day later you pass a cell to one side,
-- which used to start a second lane beside the first, so the route's days
-- were split between lanes and it showed late, broken and doubled. Now where
-- you stand is matched to the best-worn road point within a cell of you, and
-- steps run between matched points, so a route keeps gaining days on one line.

-- How worn a road point was before today: its best stretch. Today's own
-- steps don't count, or a new road would keep pulling you back onto the
-- point you just left.
local function PointWear(z, n, today)
    local GW, best = C.GW, 0
    local nx, ny = n % GW, math.floor(n / GW)
    for y = ny - 2, ny + 2 do
        for x = nx - 2, nx + 2 do
            if x >= 0 and x < GW and y >= 0 and (x ~= nx or y ~= ny) then
                local m = y * GW + x
                local e = z.road[math.min(n, m) * 10000 + math.max(n, m)]
                if e then
                    local L = Long(e) - (e.d == today and 1 or 0)
                    if L > best then best = L end
                end
            end
        end
    end
    return best
end

-- The road point for a cell: the best-worn one in reach, or the cell itself
-- when nothing nearby is more worn than it.
local function Snap(z, c, today)
    local GW = C.GW
    local cx, cy = c % GW, math.floor(c / GW)
    local best, bestW = c, PointWear(z, c, today)
    for y = cy - 1, cy + 1 do
        for x = cx - 1, cx + 1 do
            if x >= 0 and x < GW and y >= 0 and (x ~= cx or y ~= cy) then
                local n = y * GW + x
                local w = PointWear(z, n, today)
                if w > bestW then best, bestW = n, w end
            end
        end
    end
    return best
end

-- The 3.7.12 upgrade: fold the side-by-side lanes recorded before roads
-- followed themselves into one road each. Points are taken best-worn first;
-- each keeps its place and takes over the weaker points beside it (across
-- its road, never along it). Stretches are then re-joined between the
-- points that remain, and lanes that land on the same stretch add up their
-- days. Rungs between two lanes of one road fold to nothing and go.
local function MergeLanes(z, now)
    local GW = C.GW
    local wear, dx, dy, nodes = {}, {}, {}, {}
    local function Note(n, m, L)
        if not wear[n] then nodes[#nodes + 1] = n wear[n] = -1 end
        if L > wear[n] then
            local vx, vy = m % GW - n % GW, math.floor(m / GW) - math.floor(n / GW)
            local vl = math.sqrt(vx * vx + vy * vy)
            wear[n], dx[n], dy[n] = L, vx / vl, vy / vl
        end
    end
    for edge, e in pairs(z.road) do
        local a, b = math.floor(edge / 10000), edge % 10000
        local L = Long(e)
        Note(a, b, L)
        Note(b, a, L)
    end
    table.sort(nodes, function(p, q)
        if wear[p] ~= wear[q] then return wear[p] > wear[q] end
        return p < q
    end)
    -- Kept points with a point m across their road within a cell: the
    -- nearest one (straight across before diagonal), then the best worn.
    local kept = {}
    local function Beside(m)
        local mx, my = m % GW, math.floor(m / GW)
        local best, bd
        for y = my - 1, my + 1 do
            for x = mx - 1, mx + 1 do
                local n = y * GW + x
                if x >= 0 and x < GW and n ~= m and kept[n] then
                    local vx, vy = mx - x, my - y
                    local d = vx * vx + vy * vy
                    if math.abs(vx * dx[n] + vy * dy[n]) / math.sqrt(d) <= 0.75
                        and (not best or d < bd or (d == bd and wear[n] > wear[best])) then
                        best, bd = n, d
                    end
                end
            end
        end
        return best
    end
    local root = {}
    for _, n in ipairs(nodes) do
        local into = Beside(n)
        if into then root[n] = into else kept[n], root[n] = true, n end
    end
    local road = {}
    for edge, e in pairs(z.road) do
        local a0, b0 = math.floor(edge / 10000), edge % 10000
        local a, b = root[a0], root[b0]
        -- A stretch the fold would pull out past two cells, running across
        -- its road rather than along it, was a rung between lanes that came
        -- apart (common in cities, where lanes are packed tight): folded, it
        -- would draw as a long straight spoke. It stays where it was walked
        -- instead, unfolded; on its own it is a scrap and isn't drawn, but a
        -- gap can still be joined across it.
        local key = a ~= b and math.min(a, b) * 10000 + math.max(a, b)
        if key and math.max(math.abs(a % GW - b % GW), math.abs(math.floor(a / GW) - math.floor(b / GW))) > 2 then
            local vx, vy = b0 % GW - a0 % GW, math.floor(b0 / GW) - math.floor(a0 / GW)
            if math.abs(vx * dx[a] + vy * dy[a]) / math.sqrt(vx * vx + vy * vy) < 0.7 then key = edge end
        end
        if key then
            local r = road[key]
            if not r then r = { l = 0, tl = PlayNow(), r = 0, tr = now, days = {} } road[key] = r end
            local L = Long(e)
            r.l = r.l + L
            -- Lanes last walked on the same day (there and back) count that
            -- day once. What the last day still adds is L / e.l.
            if e.d and e.l and e.l > 0 then
                local last = L / e.l
                local seen = r.days[e.d]
                if seen then r.l = r.l - math.min(seen, last) end
                r.days[e.d] = math.max(seen or 0, last)
            end
            r.r = math.max(r.r, Recent(e, now))
            if e.d and (not r.d or e.d > r.d) then r.d = e.d end
        end
    end
    for _, r in pairs(road) do r.days = nil end
    z.road = road
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
    -- Where a road bends in this cell: the average of where you travel
    -- through it. Standing about (a quest giver, a mailbox) no longer pulls
    -- the road towards you (3.7.12).
    local ox, oy = z.cx[c], z.cy[c]
    if not ox then
        z.cx[c], z.cy[c] = Q(x), Q(y)
    elseif travelling then
        z.cx[c], z.cy[c] = Q(ox + (x - ox) * 0.2), Q(oy + (y - oy) * 0.2)
    end
    local now, today = time(), tonumber(date("%y%j"))

    local key = mapID * 10000 + c
    if key == cur.cell then return end

    local prev = cur.rc
    local same = prev and cur.cell and math.floor(cur.cell / 10000) == mapID
    local rc = Snap(z, c, today)
    if same and rc == prev then cur.cell = key return end
    if same then
        local dx = math.abs(prev % C.GW - rc % C.GW)
        local dy = math.abs(math.floor(prev / C.GW) - math.floor(rc / C.GW))
        if dx <= 2 and dy <= 2 then
            local edge = math.min(prev, rc) * 10000 + math.max(prev, rc)
            local e = z.road[edge]
            if not e then e = { l = 0, tl = now, r = 0, tr = now } z.road[edge] = e end
            local seenKey = mapID .. ":" .. edge
            local clock = GetTime()
            if not roadSeen[seenKey] or clock - roadSeen[seenKey] >= C.ROAD_COOLDOWN then
                roadSeen[seenKey] = clock
                e.r, e.tr = math.min(C.RECENT_CAP, Recent(e, now) + 1), now
            end
            if travelling then Credit(e, now, today) end
            S.dirty = true
        end
    end
    cur.cell, cur.rc, cur.dwell = key, rc, 0
end

local function Sample()
    local mapID, x, y = PlayerPos()
    if not mapID then
        CloseStroke()
        if ns.Linger then ns.Linger.Reset() end
        return
    end
    local mode = Mode()
    Visit(mapID, x, y, mode)
    if ns.Linger then ns.Linger.Step(mapID, x, y, mode) end

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

---------------------------------------------------------------------------
-- Neutral towns (Booty Bay, Gadgetzan, Ratchet...): the other faction is
-- everywhere (auction house, boats, flight masters) and nobody fights, so
-- sightings there aren't recorded, shared, counted or added to the haze.
-- Kills, deaths and grudge alerts still work. English names; sanctuaries
-- are caught by the game's own zone PvP type in any language.
---------------------------------------------------------------------------

local NEUTRAL_TOWNS = {
    ["Booty Bay"] = true, ["The Salty Sailor Tavern"] = true, ["Gadgetzan"] = true,
    ["Ratchet"] = true, ["Everlook"] = true, ["Light's Hope Chapel"] = true,
    ["Cenarion Hold"] = true, ["Thorium Point"] = true, ["Steamwheedle Port"] = true,
    ["Mudsprocket"] = true, ["Shattrath City"] = true, ["Area 52"] = true,
    ["The Stormspire"] = true, ["Dalaran"] = true,
}

local function InNeutralTown()
    local kind = GetZonePVPInfo and Foes.Safe(GetZonePVPInfo)
    if kind == "sanctuary" then return true end
    local sub = GetSubZoneText and Foes.Safe(GetSubZoneText)
    if type(sub) == "string" and NEUTRAL_TOWNS[sub] then return true end
    local zone = GetZoneText and Foes.Safe(GetZoneText)
    return type(zone) == "string" and NEUTRAL_TOWNS[zone] or false
end

-- Standing in a town marks its map cell as town ground, once. Town ground
-- is hidden, not wiped (3.6.4): its haze isn't drawn and its sighting count
-- isn't shown in zone stats, but what was recorded there stays saved.
-- (3.6.1 to 3.6.3 erased it; that is gone.) Sightings shared by guildmates
-- from that cell are ignored from then on.
local function TownSweep()
    if S.inInstance or not InNeutralTown() then return end
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local c = Cell(x, y, C.SW, C.SH)
    z.town = z.town or {}
    if z.town[c] then return end
    z.town[c] = true
    S.dirty = true
end

local function See(unit)
    if S.inInstance or not S.ready then return end
    if Foes.Safe(UnitIsDeadOrGhost, unit) == true then return end
    local full, short, class, hostile = Foes.Read(unit)
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

    ns.Grudge.OnSighted(full, short, class)
    if InNeutralTown() then return end

    if sightSeen[full] and now - sightSeen[full] < C.SIGHT_DEDUPE then return end
    sightSeen[full] = now
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local z = ZoneData(mapID)
    local c = Cell(x, y, C.SW, C.SH)
    z.sight[c] = (z.sight[c] or 0) + 1 -- 3.7: sightings no longer add to the battle haze
    session.sightings = session.sightings + 1
    if #recentSight >= 100 then table.remove(recentSight, 1) end
    recentSight[#recentSight + 1] = { mapID = mapID, x = x, y = y, t = time() }
    Share("S", mapID, x, y)
    S.dirty = true
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

-- The bottom edge of the kill caption showing now, as an offset from the
-- top of the screen (the overlay's lane sits under it), or nil.
function ns.CaptionBottom()
    for _, f in ipairs({ cardText, cardStrip }) do
        if f and f:IsShown() then
            local b, top = f:GetBottom(), UIParent:GetTop()
            if b and top then
                local k = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
                if f == cardText then b = (f.info:GetBottom() or b) end
                return b * k - top
            end
        end
    end
end
ns.CardTop = CardTop

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
        or k.feat or (k.chain and k.chain >= 2)
end

end

local Feats, P = ns.Feats, ns.Phrases

-- One counted kill. full/short/class: the victim when known.
local function OnKill(full, short, class)
    session.kills = session.kills + 1
    session.streak = session.streak + 1
    if session.streak > session.best then session.best = session.streak end
    db.kills = db.kills + 1
    if session.streak > db.bestStreak then db.bestStreak = session.streak end
    local first = session.kills == 1 -- first blood of the campaign
    local n = Feats.Chain()

    local times
    if full then
        db.victims[full] = (db.victims[full] or 0) + 1
        times = db.victims[full]
    end

    local info = full and Foes.info[full] or {}
    local m, mapID, z = AddMark("kill", { n = short, c = class, f = full, lv = info.lv, ra = info.ra, gu = info.gu })
    if z then
        z.kills = z.kills + 1
        z.streak = (z.streak or 0) + 1
        if z.streak > (z.bestStreak or 0) then z.bestStreak = z.streak end
    end
    if m then ns.AddBattle(mapID, m[1], m[2], C.BATTLE_W.kill) end

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

    local k = {
        name = short or "Enemy player", full = full, short = short, class = class, lv = info.lv,
        zone = mapID and MapName(mapID) or "", mapID = mapID, x = m and m[1], y = m and m[2],
        times = times, streak = session.streak, when = time(), chain = n, first = first,
        avenged = avenged and p.mark.av or nil,
        grudge = full and ns.Grudge.Get(full) and true or nil,
    }
    local feats = Feats.Collect(k)
    local top = feats[1]
    k.feat = top and top.key ~= "streak" and top.key or nil
    Feats.OnKilled(short)

    -- The kill line your guildmates get; 3.7.6 prints it for you too.
    local kfields = Feats.KillFields(n, k, feats)
    local tag = k.avenged and "avenged" or k.grudge and "grudge" or times == 1 and "first"
        or (P.StreakPool(k.streak) and "streak") or nil
    if m then
        m.tag, m.streak, m.times = tag, session.streak, times
        m.mk = n >= 2 and n or nil
        m.ft = k.feat
        k.entry = ns.CampaignKill({ n = short, f = full, c = class, z = mapID, x = m[1], y = m[2],
            t = m[3], tag = tag, st = session.streak, grudge = k.grudge, lv = info.lv, ra = info.ra, gu = info.gu,
            mk = m.mk, ft = k.feat })
        Share("K", mapID, m[1], m[2], nil, kfields)
    end
    -- a guildmate who also got credit may have said it already (3.8.3)
    local said = m and ns.NoteKill(short, mapID, m[1], m[2])
    if k.grudge then ns.Grudge.OnKill(full, mapID, true) end

    -- One line per kill: the big text for multi-kills and streak milestones,
    -- else the banner; with "Announce on screen" off, one chat line. Sounds
    -- after the picture.
    local big = cfg.announce and Feats.OverlayFor(n, k, feats)
    if big then ns.Overlay.Show(big) end
    local function Announce()
        -- your own kill in chat, worded as your guild sees it (3.7.6)
        if cfg.selfChat and not said then ns.Print(Feats.GuildKillLine(myName, k.zone, strsplit("|", kfields))) end
        if big then return end
        if not cfg.announce or n >= 2 or P.StreakPool(k.streak) then
            if not cfg.announce then
                if not cfg.selfChat then ns.Print(Feats.OwnLine(n, k, feats)) end
            else
                ns.Notice(Feats.OwnLine(n, k, feats), faction.r, faction.g, faction.b)
                Sound("PVP_THROUGH_QUEUE", 8459)
            end
            return
        end
        local text = "Honorable kill"
        if short then
            text = text .. ": " .. short
            if times > 1 then text = text .. (" (%d times now)"):format(times) end
        end
        if session.streak >= 2 then text = text .. ("   x%d"):format(session.streak) end
        local extra = Feats.OwnExtra(top)
        if avenged then
            Notice("Avenged.  " .. text .. (extra and extra ~= "Death avenged." and ("  " .. extra) or ""), 1, 0.82, 0)
            Sound("READY_CHECK", 8960)
        else
            Notice(text .. (extra and ("  " .. extra) or ""), faction.r, faction.g, faction.b)
            Sound("PVP_THROUGH_QUEUE", 8459)
        end
    end

    if cfg.shot.on and m and (cfg.shot.mode == "all" or Notable(k))
        and GetTime() - lastShot >= C.SHOT_THROTTLE then
        lastShot = GetTime()
        TakeKillShot(k, m, Announce)
    else
        Announce()
    end

    ns.UpdateHUD()
end

---------------------------------------------------------------------------
-- Counting kills (3.7). The game's honorable-kill counter says how many
-- enemies died; names come from your target, the last enemy you targeted,
-- or an enemy seen dying. Guarded, because it isn't known yet whether this
-- client ever credits one death twice:
--   * the same victim twice within 10 seconds is one kill;
--   * a credit with no name, within 2 seconds of a counted kill, only
--     counts if a second death was seen (that is, it has a name of its own);
--   * a name within 2 seconds after an unnamed kill is that same kill.
-- Undercounting beats counting phantoms. /warpath debug kills shows the log.
---------------------------------------------------------------------------

local function Skip(full)
    return Foes.counted[full] and GetTime() - Foes.counted[full] < C.SAME_VICTIM
end

-- One credit. cand: the victim picked when the credit arrived, if any.
local function CountCredit(cand)
    local now = GetTime()
    local full, short, class, src
    if cand and not Skip(cand.full) then
        full, short, class, src = cand.full, cand.short, cand.class, cand.src
    else
        full, short, class, src = Foes.Pick(Skip)
    end
    if full then
        if Foes.unnamedAt and now - Foes.unnamedAt <= 2 then
            return "named " .. short .. " right after an unnamed kill: taken as the same kill"
        end
        Foes.counted[full] = now
    else
        if now - (Foes.lastCountAt or -1000) <= 2 then
            return "no name, 2 s after a kill, no second death seen: not counted"
        end
        Foes.unnamedAt = now
    end
    Foes.lastCountAt = now
    Foes.kills = Foes.kills + 1
    OnKill(full, short, class)
    return full and ("counted: " .. short .. " (" .. (src or "target") .. ")") or "counted, no name"
end

local function Settle(cand, tries)
    local hk, before = Foes.ReadHK(), Foes.hk
    if hk and before and hk > before then
        Foes.counterWorks, Foes.hk = true, hk
        for i = 1, hk - before do
            Foes.Log(("credit %d of %d: %s"):format(i, hk - before, CountCredit(i == 1 and cand or nil)),
                before + i - 1, before + i)
        end
        return
    end
    if hk and before and hk == before and Foes.counterWorks then
        if tries < 2 then return C_Timer.After(1.2, function() Settle(cand, tries + 1) end) end
        Foes.Log("+0: a repeat event, ignored", before, hk)
        return
    end
    if hk then Foes.hk = hk end
    -- no counter this client will show (or it hasn't moved yet): one credit, guarded
    Foes.Log("no counter change seen: one credit, " .. CountCredit(cand), before, hk)
end

function Foes.OnCredit()
    Foes.credits = Foes.credits + 1
    if S.inInstance or not RecentlyInCombat() then
        Foes.Log("credit while out of combat: a groupmate's kill, not counted", Foes.hk, Foes.ReadHK())
        Foes.hk = Foes.ReadHK() or Foes.hk
        return
    end
    local full, short, class, src = Foes.Pick(Skip)
    local cand = full and { full = full, short = short, class = class, src = src } or nil
    C_Timer.After(0.3, function() Settle(cand, 0) end)
end

local function OnDeath()
    if S.inInstance then return end
    local recentFoe = Foes.last and GetTime() - Foes.last.at < C.PVP_WINDOW and Foes.last or nil
    local pvp = GetTime() - lastHostile < C.PVP_WINDOW or recentFoe or Foes.PlayerNearby()
    -- The killer: the enemy you were fighting (the game hides who landed the blow).
    local killer = pvp and recentFoe or nil
    local ki = killer and Foes.info[killer.full] or {}
    local m, mapID, z = AddMark("death", { pvp = pvp and true or nil,
        kn = killer and killer.short, kc = killer and killer.class, kf = killer and killer.full,
        lv = ki.lv, ra = ki.ra, gu = ki.gu })
    if pvp then
        local streak = session.streak
        session.deaths = session.deaths + 1
        db.deaths = db.deaths + 1
        if streak >= 3 then
            local by = killer and killer.short
            if not cfg.announce then
                -- the death line below says it when your own lines are on
                if not cfg.selfChat then
                    Print(("Streak ended at %s%d|r%s."):format(C.GOLD, streak, by and (" by " .. by) or ""))
                end
            else
                ns.Overlay.Show({ title = ("Streak ended at %d"):format(streak), sub = by and ("by " .. by) or "",
                    r = 0.72, g = 0.72, b = 0.72, sr = 0.8, sg = 0.8, sb = 0.8, small = true })
            end
        end
        ns.CampaignDeath({ n = killer and killer.short, c = killer and killer.class, f = killer and killer.full,
            lv = ki.lv, ra = ki.ra, gu = ki.gu, z = mapID, x = m and m[1], y = m and m[2], t = time() }, streak)
        if killer then ns.Grudge.OnDeath(killer.full, killer.class, mapID) end
        local fields = Feats.DeathFields(killer and killer.full, streak)
        -- your own death in chat, worded as your guild sees it (3.7.6)
        if cfg.selfChat then
            local zone = mapID and MapName(mapID) or (GetZoneText and GetZoneText()) or ""
            Print(Feats.GuildDeathLine(myName, zone, strsplit("|", fields)))
        end
        Feats.OnDied(true, killer)
        session.streak = 0
        for _, zz in pairs(db.maps) do zz.streak = 0 end
        if m then
            z.pdeaths = z.pdeaths + 1
            ns.AddBattle(mapID, m[1], m[2], C.BATTLE_W.death)
            ns.AddDeathHeat(mapID, m[1], m[2], 1)
            ns.Ground.Forget(mapID)
            pendingAvenge = { mapID = mapID, mark = m, at = GetTime() }
            Share("D", mapID, m[1], m[2], nil, fields)
        end
    else
        Feats.OnDied(false)
    end
    ns.UpdateHUD()
end

-- Forget recording state (/warpath clear).
function ns.ResetRecording()
    roadSeen, pendingAvenge = {}, nil
    ns.Ground.Forget()
    ns.Ground.Reset()
end
function ns.ForgetFields(mapID) ns.Ground.Forget(mapID) end

-- Shared with the other files.
ns.MergeLanes = MergeLanes
ns.CloseStroke = CloseStroke
ns.FinishShot = FinishShot
ns.OnDeath = OnDeath
ns.Sample = Sample
ns.See = See
ns.TakeKillShot = TakeKillShot

ns.InNeutralTown = InNeutralTown
ns.TownSweep = TownSweep
