-- Warpath: Spirits (3.9)
-- Spirit healers on the map, on the corpse runs layer: where you'll come back
-- after releasing, and whether your side can use each one (shared, Horde
-- only, Alliance only).
--
-- Two sources, combined:
--   * a built-in list of the vanilla graveyards on both continents, with the
--     faction each serves (from the AzerothCore world database's
--     game_graveyard and graveyard_zone tables, the Burning Crusade and
--     later ones left out). Shows every graveyard without dying first.
--   * what your characters learn: when you die the game says where you'll
--     release to (C_DeathInfo.GetDeathReleasePosition), and once you've
--     released you're standing there. Kept account-wide, by faction, so a
--     graveyard both your Horde and your Alliance characters have released
--     to is shared whatever the list says, and one the list doesn't know
--     (this server's own) still shows.
-- The client has no graveyard faction of its own. Positions are world yards,
-- placed on a zone map with C_Map.GetMapPosFromWorldPos, so one record works
-- on every map it falls on. Zone maps only: on a continent 76 icons
-- would be clutter.
local ADDON, ns = ...
local C, S = ns.C, ns.S

local gdb
ns.OnBind(function() gdb = ns.gdb end)

local Spirits = {}
ns.Spirits = Spirits

local MATCH_YD = 60     -- a learned spot this close to a listed graveyard is that graveyard
local ICON_PX = 64      -- icon size at 100% icon size, interface pixels (Joe, test2: 15 was too small; "try 64")
-- The raid frame's resurrect icon (Joe's pick B, 2026-11-26): the map's own
-- graveyard tombstone (test1) duplicated the game's grave icon, which matters.
local ICON = "RaidFrame-Icon-Rez"
local QUIET = 0.6       -- alpha while you're alive; full while dead

-- [continent] = { { worldX, worldY, faction, name }, ... }
-- faction: "S" shared, "H" Horde only, "A" Alliance only
local LIST = {
    [0] = { -- Eastern Kingdoms
        { -9194, -2313, "A", "Redridge Mountains" },
        { -10774, -1190, "A", "Duskwood, Darkshire" },
        { -10547, 1197, "S", "Westfall, Sentinel Hill" },
        { -5351, -2882, "A", "Loch Modan, Thelsamar" },
        { -3289, -2436, "S", "Wetlands, Crossroads" },
        { -6290, -3493, "S", "Badlands" },
        { -11110, -1833, "S", "Deadwind Pass, Morgan's Plot" },
        { 1883, 1629, "H", "Tirisfal Glades, Deathknell" },
        { 1823, 215, "H", "Tirisfal Glades, Undercity" },
        { 516, 1590, "H", "Silverpine Forest, The Sepulcher" },
        { -19, -981, "H", "Hillsbrad Foothills, Tarren Mill" },
        { -1308, -3192, "S", "Arathi Highlands, Eastern Road" },
        { -6164, 336, "A", "Dun Morogh, Anvilmar" },
        { -5680, -519, "S", "Dun Morogh, Kharanos" },
        { -6805, -2287, "H", "Badlands, Kargath" },
        { -9403, -2038, "S", "Redridge Mountains, Lakeshire" },
        { -8935, -189, "A", "Elwynn Forest, Northshire" },
        { -9340, 171, "S", "Elwynn Forest, Goldshire" },
        { -9152, 411, "S", "Elwynn Forest, Stormwind" },
        { -10568, -3377, "S", "Swamp of Sorrows, Stonard" },
        { -14285, 288, "S", "Stranglethorn Vale, Booty Bay" },
        { -733, -592, "A", "Hillsbrad Foothills, Southshore" },
        { 2349, 492, "H", "Tirisfal Glades, Brill" },
        { 324, -2227, "A", "The Hinterlands, Aerie Peak" },
        { -10847, -2950, "S", "Blasted Lands, Dreadmaul Hold" },
        { -11543, -229, "S", "Stranglethorn Vale, Northern Stranglethorn" },
        { -3348, -857, "S", "Wetlands, Baradin Bay" },
        { 908, -1520, "A", "Western Plaguelands, Chillwind Camp" },
        { 2056, -5021, "S", "Eastern Plaguelands, Pestilent Scar" },
        { 1750, -670, "H", "Western Plaguelands, Bulwark" },
        { 1392, -3701, "S", "Eastern Plaguelands, Darrowshire" },
        { -6451, -1114, "S", "Searing Gorge, Thorium Point" },
        { -291, -4374, "H", "The Hinterlands, The Overlook Cliffs" },
        { -5166, -875, "A", "Dun Morogh, Gates of Ironforge" },
        { -9552, -1374, "S", "Elwynn Forest, Eastvale Logging Camp" },
        { 1237, -2412, "S", "Western Plaguelands, Caer Darrow" },
        { 2648, -4014, "S", "Eastern Plaguelands, Blackwood Lake" },
        { -10607, 294, "S", "Duskwood, Ravenhill" },
        { 1978, -3656, "S", "Eastern Plaguelands, Crown Guard Tower" },
    },
    [1] = { -- Kalimdor
        { -593, -2524, "S", "The Barrens, The Crossroads" },
        { -448, 2513, "S", "Desolace, Ethel Rethor" },
        { 234, -4794, "S", "Durotar, Razor Hill" },
        { -2945, -153, "H", "Mulgore, Red Cloud Mesa" },
        { 6739, 210, "S", "Darkshore, Auberdine" },
        { -6432, -278, "S", "Silithus, Valor's Rest" },
        { -2175, -342, "H", "Mulgore, Bloodhoof Village" },
        { 10054, 2117, "A", "Teldrassil, Darnassus" },
        { 9701, 946, "S", "Teldrassil, Dolanaar" },
        { 2633, -630, "S", "Ashenvale, Astranaar" },
        { 10385, 812, "A", "Teldrassil, Aldrassil" },
        { 8706, 965, "S", "Teldrassil, Rut'theran Village" },
        { -3526, -4316, "A", "Dustwallow Marsh, Theramore Isle" },
        { -7191, -3945, "S", "Tanaris, Gadgetzan" },
        { -2518, -1973, "S", "The Barrens, Camp Taurajo" },
        { -1081, -3479, "S", "The Barrens, Ratchet" },
        { -4596, 3229, "S", "Feralas, Feathermoon Stronghold" },
        { -4440, 370, "H", "Feralas, Camp Mojache" },
        { -5530, -3459, "S", "Thousand Needles, Shimmering Flats" },
        { 2681, -4010, "S", "Azshara, Talrendis Point" },
        { 898, 434, "S", "Stonetalon Mountains, Webwinder Path" },
        { 3806, -1600, "S", "Felwood, Morlos'Aran" },
        { -7206, -2437, "S", "Un'Goro Crater, The Marshlands" },
        { 4291, 97, "S", "Darkshore, Twilight Vale" },
        { 6876, -4662, "S", "Winterspring, Everlook" },
        { 2422, -2954, "S", "Ashenvale, Kargathia" },
        { 2943, -6037, "S", "Azshara, Southridge Beach" },
        { 4789, -6845, "S", "Azshara, Legash Encampment" },
        { -3128, -3047, "H", "Dustwallow Marsh, Brackenwall Village" },
        { 7426, -2809, "S", "Moonglade" },
        { 5936, -1218, "S", "Felwood, Irontree Woods" },
        { -778, -4985, "H", "Durotar, Sen'jin Village" },
        { -635, -4296, "H", "Durotar, Valley of Trials" },
        { -4590, 1632, "S", "Feralas, Dire Maul" },
        { 1178, -4464, "S", "Durotar, Northern Durotar" },
        { -982, -75, "H", "Mulgore, Thunder Bluff" },
        { -6831, 891, "S", "Silithus, Cenarion Hold" },
    },
}

local FACTION_KEY = { Horde = "H", Alliance = "A" }

local function Vec(x, y)
    if CreateVector2D then return CreateVector2D(x, y) end
    return { x = x, y = y, GetXY = function(v) return v.x, v.y end }
end

local function World(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then return end
    local ok, c, wp = pcall(C_Map.GetWorldPosFromMapPos, mapID, Vec(x, y))
    if ok and c and wp then
        local wx, wy = wp:GetXY()
        if wx and wy then return c, wx, wy end
    end
end

local function Store()
    gdb.spirits = gdb.spirits or {}
    return gdb.spirits
end

local version = 0 -- bumped on every change, so the per-map cache rebuilds

-- Remember a graveyard your faction released to. Returns the record.
local function Learn(c, wx, wy, how)
    local key = FACTION_KEY[UnitFactionGroup and UnitFactionGroup("player") or ""]
    if not key or not c then return end
    local list, best, bestD = Store(), nil, MATCH_YD
    for _, r in ipairs(list) do
        if r.c == c then
            local d = math.sqrt((r.x - wx) ^ 2 + (r.y - wy) ^ 2)
            if d < bestD then best, bestD = r, d end
        end
    end
    if not best then
        best = { c = c, x = math.floor(wx + 0.5), y = math.floor(wy + 0.5) }
        list[#list + 1] = best
    end
    best[key] = time()
    best.how = how
    version = version + 1
    S.dirty = true
    return best
end

-- Nearest listed graveyard to a world position: its entry and the distance.
local function Nearest(c, wx, wy)
    local best, bestD
    for _, g in ipairs(LIST[c] or {}) do
        local d = math.sqrt((g[1] - wx) ^ 2 + (g[2] - wy) ^ 2)
        if not bestD or d < bestD then best, bestD = g, d end
    end
    return best, bestD
end

Spirits.last = nil -- the last death's check: how far the game's release spot was from the list

-- On death: the game says where you'll release to.
function Spirits.OnDead()
    if S.inInstance or not (C_DeathInfo and C_DeathInfo.GetDeathReleasePosition) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.Secret(mapID) then return end
    local ok, pos = pcall(C_DeathInfo.GetDeathReleasePosition, mapID)
    if not ok or not pos or ns.Secret(pos) then return end
    local x, y = pos:GetXY()
    if not x or ns.Secret(x) then return end
    local c, wx, wy = World(mapID, x, y)
    if not c then return end
    local _, d = Nearest(c, wx, wy)
    Spirits.last = { t = time(), d = d, map = mapID }
    Learn(c, wx, wy, "d")
end

-- Released: you're standing at the spirit healer now.
function Spirits.OnRelease()
    if S.inInstance or not (UnitIsGhost and UnitIsGhost("player")) then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or ns.Secret(mapID) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if not x or ns.Secret(x) then return end
    local c, wx, wy = World(mapID, x, y)
    if c then Learn(c, wx, wy, "r") end
end

-- Every graveyard known: the list, with what your characters saw folded in,
-- plus learned ones the list doesn't have. Each { c, x, y, f, name, H, A }.
local known, knownAt = nil, -1
local function Known()
    if knownAt == version and known then return known end
    known = {}
    for c, list in pairs(LIST) do
        for _, g in ipairs(list) do
            known[#known + 1] = { c = c, x = g[1], y = g[2], f = g[3], name = g[4] }
        end
    end
    for _, r in ipairs(gdb.spirits or {}) do
        local best, bestD
        for _, k in ipairs(known) do
            if k.c == r.c and k.name then
                local d = math.sqrt((k.x - r.x) ^ 2 + (k.y - r.y) ^ 2)
                if d < MATCH_YD and (not bestD or d < bestD) then best, bestD = k, d end
            end
        end
        if not best then
            best = { c = r.c, x = r.x, y = r.y }
            known[#known + 1] = best
        end
        best.H, best.A = best.H or r.H, best.A or r.A
    end
    knownAt = version
    return known
end

-- Who can use it: "S", "H" or "A", and whether your characters have seen it.
-- Seen by both sides is shared, whatever the list says.
function Spirits.Side(k)
    if k.H and k.A then return "S" end
    if k.f == "S" then return "S" end
    if k.f == "H" and k.A then return "S" end
    if k.f == "A" and k.H then return "S" end
    return k.f or (k.H and "H") or (k.A and "A") or "S"
end

-- Graveyards on a zone map, as { k, x, y } in map fractions. Cached per map;
-- rebuilt when something is learned.
local onMap = {}
local function ForMap(viewed)
    local hit = onMap[viewed]
    if hit and hit.v == version then return hit end
    hit = { v = version }
    onMap[viewed] = hit
    if not (C_Map and C_Map.GetMapPosFromWorldPos) then return hit end
    local info = C_Map.GetMapInfo(viewed)
    if not info or info.mapType ~= 3 then return hit end -- zones and cities only
    local cont = World(viewed, 0.5, 0.5)
    if not cont then return hit end
    for _, k in ipairs(Known()) do
        if k.c == cont then
            local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, k.c, Vec(k.x, k.y), viewed)
            if ok and pos then
                local x, y = pos:GetXY()
                if x and y and x > 0.01 and x < 0.99 and y > 0.01 and y < 0.99 then
                    hit[#hit + 1] = { k = k, x = x, y = y }
                end
            end
        end
    end
    return hit
end
Spirits.ForMap = ForMap

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local SIDE_TEXT = {
    S = { "Shared: both factions", 1, 0.82, 0 },
    H = { "Horde only", 1, 0.25, 0.2 },
    A = { "Alliance only", 0.35, 0.65, 1 },
}

local function Enter(self)
    local k = self.k
    local side = Spirits.Side(k)
    local t = SIDE_TEXT[side]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Spirit healer", 1, 1, 1)
    if k.name then GameTooltip:AddLine(k.name, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(t[1], t[2], t[3], t[4])
    local seen
    if k.H and k.A then seen = "Your Horde and Alliance characters have released here"
    elseif k.H then seen = "Your Horde characters have released here"
    elseif k.A then seen = "Your Alliance characters have released here"
    end
    if seen then GameTooltip:AddLine(seen, 0.6, 0.6, 0.6, true)
    elseif k.name then GameTooltip:AddLine("From Warpath's graveyard list; not seen by your characters yet", 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local pool, active = {}, 0
local function GetIcon(overlay, i)
    local f = pool[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.badge = f:CreateTexture(nil, "OVERLAY", nil, 1)
        f.badge:SetPoint("CENTER", f, "BOTTOMRIGHT", 0, 2)
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f:SetScript("OnEnter", Enter)
        f:SetScript("OnLeave", GameTooltip_Hide)
        pool[i] = f
    end
    return f
end

local function Size(f, k, scale)
    local h = ICON_PX * scale / k
    f:SetSize(h, h) -- the art is square (44 x 44)
    f.badge:SetSize(h * 0.75, h * 0.75)
end

-- viewed: the zone map to draw on, or nil to draw nothing (layer off,
-- replay, hidden). k: how much the map is scaled (pins hold their size).
Spirits.drawn = {} -- what the last draw put on the map (tests, debug)
function Spirits.Draw(overlay, viewed, k)
    local n = 0
    local drawn = {}
    Spirits.drawn = drawn
    if viewed and gdb then
        local scale = ((ns.cfg and ns.cfg.iconScale) or 100) / 100
        local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
        local w, h = overlay:GetWidth(), overlay:GetHeight()
        for _, e in ipairs(ForMap(viewed)) do
            n = n + 1
            local f = GetIcon(overlay, n)
            f.k = e.k
            f.tex:SetAtlas(ICON)
            local side = Spirits.Side(e.k)
            if side == "H" then f.badge:SetAtlas("poi-horde") f.badge:Show()
            elseif side == "A" then f.badge:SetAtlas("poi-alliance") f.badge:Show()
            else f.badge:Hide() end
            f.side = side
            f:SetAlpha(dead and 1 or QUIET)
            drawn[n] = { k = e.k, x = e.x, y = e.y, side = side, alpha = dead and 1 or QUIET }
            Size(f, k or 1, scale)
            f:SetFrameLevel(overlay:GetFrameLevel() + 1) -- under every pin
            f:ClearAllPoints()
            f:SetPoint("CENTER", overlay, "TOPLEFT", e.x * w, -e.y * h)
            f:Show()
        end
    end
    for i = n + 1, #pool do pool[i]:Hide() end
    active = n
    return n
end

function Spirits.Rescale(k)
    local scale = ((ns.cfg and ns.cfg.iconScale) or 100) / 100
    for i = 1, active do Size(pool[i], k or 1, scale) end
end

-- /warpath debug spirits
function Spirits.Debug(Print)
    local learned = gdb.spirits or {}
    local nH, nA = 0, 0
    for _, r in ipairs(learned) do
        if r.H then nH = nH + 1 end
        if r.A then nA = nA + 1 end
    end
    local listed = #(LIST[0] or {}) + #(LIST[1] or {})
    Print(("spirit healers: %d listed, %d learned (Horde %d, Alliance %d)"):format(listed, #learned, nH, nA))
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and not ns.Secret(mapID) and C_Map.GetPlayerMapPosition(mapID, "player")
    if pos then
        local c, wx, wy = World(mapID, pos:GetXY())
        if c then
            local g, d = Nearest(c, wx, wy)
            if g then Print(("nearest listed: %s, %d yards from you"):format(g[4], math.floor(d + 0.5))) end
        else
            Print("this client gives no world position for this map")
        end
    end
    if Spirits.last and Spirits.last.d then
        Print(("last death: the game's release spot was %d yards from the nearest listed graveyard"):format(
            math.floor(Spirits.last.d + 0.5)))
    end
end
