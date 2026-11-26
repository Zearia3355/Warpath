-- Warpath: Map
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Ago, CellXY, Long, PlayNow, Print, Secret = ns.Ago, ns.CellXY, ns.Long, ns.PlayNow, ns.Print, ns.Secret
local Simplify, cur, recentSight, shared = ns.Simplify, ns.cur, ns.recentSight, ns.shared
local Fields, PointTime, RunSeconds, ClassColor = ns.Fields, ns.PointTime, ns.RunSeconds, ns.ClassColor
local StrokeArc, TrailSeconds = ns.StrokeArc, ns.TrailSeconds

local db, gdb, cfg, faction, foe
ns.OnBind(function()
    db, gdb, cfg, faction, foe = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe
end)

local overlay, head
local lines, dots, glows, pins, labels, steps, rims, glints = {}, {}, {}, {}, {}, {}, {}, {}
local tags, activeTags = {}, 0   -- time labels on lingering areas (3.8)
local TagAnchor                  -- defined with the tags, used when pins rescale
local replay = { active = false }
local shimmer, twinkle = {}, {}   -- rebuilt on every draw, animated while the map is open

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end
local function Smooth(t) t = Clamp(t) return t * t * (3 - 2 * t) end
local function Lerp(a, b, t) return a + (b - a) * t end

-- Silver to gold through several stops, eased between them.
local STOPS = {
    { 0.83, 0.85, 0.87 },  -- silver
    { 0.86, 0.83, 0.74 },  -- first gilding (warm silver)
    { 0.92, 0.82, 0.55 },  -- pale gold
    { 0.95, 0.80, 0.42 },  -- light gold
    { 0.95, 0.76, 0.29 },  -- gold
}
local function Gild(g)
    if g <= 0 then return STOPS[1][1], STOPS[1][2], STOPS[1][3] end
    if g >= 1 then return STOPS[5][1], STOPS[5][2], STOPS[5][3] end
    local f = g * (#STOPS - 1)
    local i = math.floor(f)
    local t, a, b = Smooth(f - i), STOPS[i + 1], STOPS[i + 2]
    return Lerp(a[1], b[1], t), Lerp(a[2], b[2], t), Lerp(a[3], b[3], t)
end

---------------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------------

local function Projection(mapID, viewed)
    if mapID == viewed then return 0, 1, 0, 1 end
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, viewed)
    if not ok or not minX or not maxX or not minY or not maxY then return end
    if maxX - minX < 0.002 or maxY - minY < 0.002 then return end
    if minX < -0.5 or maxX > 1.5 or minY < -0.5 or maxY > 1.5 then return end
    return minX, maxX, minY, maxY
end

local function Proj(scene, mapID)
    local p = scene.proj[mapID]
    if p == nil then
        local minX, maxX, minY, maxY = Projection(mapID, scene.viewed)
        if minX then
            p = { ox = minX, oy = minY, sx = maxX - minX, sy = maxY - minY, mapID = mapID }
            p.far = p.sx < 0.25
        else
            p = false
        end
        scene.proj[mapID] = p
    end
    return p
end

-- since: only for replay; collects strokes (and runs) after that time, oldest first.
local function BuildScene(viewed, since)
    local scene = { viewed = viewed, proj = {}, zones = {}, since = since }
    for mapID, z in pairs(db.maps) do
        local p = Proj(scene, mapID)
        if p then scene.zones[#scene.zones + 1] = { z = z, p = p } end
    end
    if since then
        scene.strokes, scene.points = {}, 0
        for _, e in ipairs(scene.zones) do
            for _, list in ipairs({ e.z.strokes, e.z.runs }) do
                for _, s in ipairs(list) do
                    if s.e >= since and #s >= 4 then
                        scene.strokes[#scene.strokes + 1] = { s = s, p = e.p }
                        scene.points = scene.points + #s / 2
                    end
                end
            end
        end
        table.sort(scene.strokes, function(a, b) return a.s.t < b.s.t end)
    end
    return scene
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------

local function GetLine(i)
    local l = lines[i]
    if not l then
        l = overlay:CreateLine(nil, "ARTWORK")
        lines[i] = l
    end
    return l
end

-- One line from (x1,y1) to (x2,y2) in overlay pixels.
local function PutLine(i, sub, blend, thick, r, g, b, a, x1, y1, x2, y2)
    local l = GetLine(i)
    l:SetDrawLayer("ARTWORK", sub)
    l:SetBlendMode(blend or "BLEND")
    l:SetThickness(thick)
    l:SetColorTexture(r, g, b, a)
    l:SetStartPoint("TOPLEFT", overlay, x1, y1)
    l:SetEndPoint("TOPLEFT", overlay, x2, y2)
    l:Show()
    return l
end

local function GetDot(i)
    local d = dots[i]
    if not d then
        d = overlay:CreateTexture(nil, "BACKGROUND")
        d:SetTexture(C.TEX_DOT)
        d:SetBlendMode("BLEND")
        dots[i] = d
    end
    return d
end

local function GetGlow(i)
    local g = glows[i]
    if not g then
        g = overlay:CreateTexture(nil, "BORDER")
        g:SetTexture(C.TEX_GLOW)
        g:SetBlendMode("ADD")
        g:SetVertexColor(1, 0.12, 0.05)
        glows[i] = g
    end
    return g
end

local function GetGlint(i)
    local g = glints[i]
    if not g then
        g = overlay:CreateTexture(nil, "ARTWORK", nil, 3)
        g:SetTexture(C.TEX_GLOW)
        g:SetBlendMode("ADD")
        g:SetVertexColor(1, 0.74, 0.22)
        glints[i] = g
    end
    return g
end

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

local TAGS = { first = "First blood on this player", grudge = "Grudge settled", avenged = "Avenged",
    streak = "Streak" }

local function PinEnter(self)
    local d = self.d
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.kind == "death" or self.kind == "mob" then
        if d.pvp then
            GameTooltip:AddLine("You fell here", 1, 0.25, 0.2)
            if d.kn then
                GameTooltip:AddLine("Fighting " .. d.kn, ClassColor(d.kc))
                local who = ns.Foes.Describe(d.lv, d.ra, d.kc, d.gu)
                if who ~= "" then GameTooltip:AddLine(who, 0.8, 0.8, 0.8) end
            end
            if d.av then
                GameTooltip:AddLine(("Avenged %d sec later (a kill nearby)"):format(d.av), 1, 0.82, 0)
            end
        else
            GameTooltip:AddLine("You died here", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("No enemy player seen (a mob or a fall); not counted", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(date("%b %d, %H:%M", d[3]), 0.8, 0.8, 0.8)
    elseif self.kind == "kill" then
        GameTooltip:AddLine("Honorable kill", 1, 0.82, 0)
        if d.n then
            GameTooltip:AddLine(d.n, ClassColor(d.c))
            local who = ns.Foes.Describe(d.lv, d.ra, d.c, d.gu)
            if who ~= "" then GameTooltip:AddLine(who, 0.8, 0.8, 0.8) end
            local n = d.f and db.victims[d.f]
            if n and n > 1 then GameTooltip:AddLine(("Slain by you %d times"):format(n), 0.8, 0.8, 0.8) end
        end
        if d.tag and TAGS[d.tag] then
            GameTooltip:AddLine(d.tag == "streak" and ("Streak of " .. (d.streak or "?")) or TAGS[d.tag], 1, 0.62, 0.16)
        end
        GameTooltip:AddLine(date("%b %d, %H:%M", d[3]), 0.8, 0.8, 0.8)
        if d.shot then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(("Screenshot #%d"):format(d.shot), 1, 1, 1)
            if d.file then GameTooltip:AddLine(d.file, 0.62, 0.83, 1) end
        end
    elseif self.kind == "grudge" then
        local r = ns.Grudge.Get(d.full)
        GameTooltip:AddLine("Grudge: " .. d.short, 1, 0.3, 0.2)
        GameTooltip:AddLine("Seen here " .. Ago(d.t), 0.8, 0.8, 0.8)
        local hist = r and ns.Grudge.History(r) or ""
        if hist ~= "" then GameTooltip:AddLine(hist, 1, 0.62, 0.16) end
        if r and r.note then GameTooltip:AddLine('"' .. r.note .. '"', 1, 1, 1, true) end
    elseif self.kind == "sight" then
        GameTooltip:AddLine("Enemy sighted", foe.r, foe.g, foe.b)
        GameTooltip:AddLine((d.from and ("Reported by " .. d.from .. ", ") or "By you, ") .. Ago(d.t), 0.8, 0.8, 0.8)
    elseif self.kind == "many" then
        local kills = d.kind == "kill"
        if kills then
            GameTooltip:AddLine(("%d kills here"):format(d.n), 1, 0.82, 0)
        else
            GameTooltip:AddLine(("%d deaths here"):format(d.n), 1, 0.25, 0.2)
        end
        if d.guild > 0 then
            GameTooltip:AddLine(("Yours %d, guildmates' %d"):format(d.n - d.guild, d.guild), 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Zoom in to see each one", 0.6, 0.6, 0.6)
    elseif self.kind == "skill" then
        GameTooltip:AddLine(d.from .. " scored a kill here", 0.6, 0.8, 1)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    else -- shared death
        GameTooltip:AddLine(d.from .. " was killed here", 1, 0.5, 0.4)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

-- Pins don't take clicks (3.7.9): hovering shows the tooltip, and clicks fall
-- through to the map (zoom in / out). Waypoints are set from the chronicle,
-- the grudge ledger or /warpath waypoint.

local PIN_LEVEL = { sight = 1, mob = 2, kill = 3, death = 3, skill = 4, sdeath = 4, many = 5, grudge = 6 }

-- Pins hold a steady size on screen (3.7): sized in interface pixels and
-- divided by how much the map is scaled and zoomed, so a bigger map
-- (Leatrix Maps) or zooming in no longer blows them up. Times the icon size
-- setting (25% to 200%). Lines, footsteps and the haze still scale with the map.
local PIN_PX = 18
local activePins = 0
local function MapScale()
    local k = overlay and overlay:GetEffectiveScale() / UIParent:GetEffectiveScale() or 1
    return (k and k > 0.01) and k or 1
end
local function RescalePins()
    local k = MapScale() / ((cfg.iconScale or 100) / 100)
    for i = 1, activePins do
        local f = pins[i]
        if f and f.px then
            f:SetSize(f.px / k, f.px / k)
            f.halo:SetSize(f.px * 1.9 / k, f.px * 1.9 / k)
        end
    end
    for i = 1, activeTags do if tags[i] then TagAnchor(tags[i]) end end
end

local function GetPin(i)
    local f = pins[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f.halo = f:CreateTexture(nil, "ARTWORK")
        f.halo:SetTexture(C.TEX_DOT)
        f.halo:SetBlendMode("ADD")
        f.halo:SetVertexColor(1, 0.1, 0.05)
        f.halo:SetPoint("CENTER")
        f.halo:Hide()
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.label:SetPoint("LEFT", f, "RIGHT", 2, 0)
        f.label:SetTextColor(1, 0.35, 0.25)
        f.label:Hide()
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f:SetScript("OnEnter", PinEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)
        pins[i] = f
    end
    return f
end

-- Scores ("kills : deaths") on continent and world views (3.8.3): text on a
-- soft dark patch, like the area labels, drawn above the pins.
local function GetLabel(i)
    local f = labels[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f:SetSize(60, 16)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("CENTER")
        f.back = f:CreateTexture(nil, "BACKGROUND")
        f.back:SetTexture(C.TEX_DOT)
        f.back:SetVertexColor(0.06, 0.03, 0.02)
        f.back:SetAlpha(0.7)
        f.back:SetPoint("CENTER")
        labels[i] = f
    end
    return f
end

-- Blue when you're clearly ahead, red when clearly behind, yellow when it's
-- close: within one fight, or within a quarter of the fights (3.8.3).
local STANDING = { win = { 0.35, 0.65, 1.00 }, close = { 1.00, 0.82, 0.00 }, lose = { 1.00, 0.25, 0.20 } }
local function Standing(k, d)
    if math.abs(k - d) <= math.max(1, 0.25 * (k + d)) then return STANDING.close end
    return k > d and STANDING.win or STANDING.lose
end
ns.Standing = Standing

-- Time spent in a lingering area (3.8), above its outline. Steady on screen
-- like the pins; hover for the visits.
local function TagEnter(self)
    local a = self.ar and self.ar.a
    if not a then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.text:GetText() .. " here", 1, 0.82, 0)
    -- visits as a person would tell them (Linger.Visits merges and folds)
    local shown = ns.Linger and ns.Linger.Visits(a) or {}
    for i = math.max(1, #shown - 5), #shown do
        local v = shown[i]
        local mins = math.max(1, math.floor(v.t / 60 + 0.5))
        GameTooltip:AddLine(("%d min from %s"):format(mins, date("%H:%M", v.s)), 0.8, 0.8, 0.8)
    end
    if self.ar.live then
        GameTooltip:AddLine("You're here", faction.r, faction.g, faction.b)
    else
        GameTooltip:AddLine("Left " .. Ago(a.e), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

function TagAnchor(f)
    local k = MapScale()
    f:SetScale(1 / k)
    f:ClearAllPoints()
    f:SetPoint("BOTTOM", overlay, "TOPLEFT", f.px * k, f.py * k + 2)
end

local function GetTag(i)
    local f = tags[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f:SetSize(36, 14)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("CENTER")
        -- a soft dark patch behind the text, so it reads on any map art (3.8.3)
        f.back = f:CreateTexture(nil, "BACKGROUND")
        f.back:SetTexture(C.TEX_DOT)
        f.back:SetVertexColor(0.06, 0.03, 0.02)
        f.back:SetPoint("CENTER", f.text, "CENTER")
        f:EnableMouse(true)
        if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
        f:SetScript("OnEnter", TagEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)
        tags[i] = f
    end
    return f
end

function ns.PlaceTag(i, ar, text, r, g, b, a, px, py)
    local f = GetTag(i)
    f.ar, f.px, f.py = ar, px, py
    f.text:SetText(text)
    f.text:SetTextColor(r, g, b, a)
    f.back:SetSize((f.text:GetStringWidth() or 20) + 22, 26)
    f.back:SetAlpha(0.7 * a)
    f:SetFrameLevel(overlay:GetFrameLevel() + 1)
    TagAnchor(f)
    f:Show()
end

local function At(obj, p, x, y, w, h)
    obj:ClearAllPoints()
    obj:SetPoint("CENTER", overlay, "TOPLEFT", (p.ox + x * p.sx) * w, -(p.oy + y * p.sy) * h)
end

local function TrailColor(s)
    if s.k == "g" then return 0.55, 0.90, 1.00, 0.7, 0.7 end
    if s.k == "f" then return 1.00, 0.88, 0.52, 0.6, 0.6 end
    return faction.r, faction.g, faction.b, 0.95, 1
end

---------------------------------------------------------------------------
-- Drawing. D is the draw state: sizes, the time, and how many of each
-- pooled object are in use.
---------------------------------------------------------------------------

-- The battle haze: soft patches of one blood red where fighting happens,
-- drawn with normal blending (never additive, so it can't wash to white),
-- deepening from a faint rust to dark red as fights pile up. Strength comes
-- from ns.BattleField, which spreads each fight over the cells around it.
local function DrawHaze(D, scene)
    if not cfg.layers.battle then return end
    local w, h = D.w, D.h
    local span = C.BATTLE_FULL - C.BATTLE_MIN
    local a0, a1 = C.BATTLE_ALPHA[1], C.BATTLE_ALPHA[2]
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        local cell = p.sx * w / C.SW
        for c, v in pairs(ns.BattleField(z)) do
            if v >= C.BATTLE_MIN then
                if D.nd >= C.DOT_BUDGET then break end
                local t = Clamp((v - C.BATTLE_MIN) / span)
                D.nd = D.nd + 1
                local d = GetDot(D.nd)
                local x, y = CellXY(c, C.SW, C.SH)
                d:SetVertexColor(Lerp(0.62, 0.42, t), Lerp(0.20, 0.03, t), Lerp(0.09, 0.02, t))
                d:SetAlpha(a0 + (a1 - a0) * t)
                local size = math.max(6, cell * (2.8 + 1.4 * t))
                d:SetSize(size, size)
                At(d, p, x, y, w, h)
                d:Show()
            end
        end
    end
end

-- One gold or silver stretch: outline, body, and (once fully gold) a warm
-- centre stripe that brightens with wear. Returns the stripe, if any.
-- Gilt roads (3.7.12, C.ROAD_STYLE "gilt"): raised metal, like Blizzard's
-- gold frame trim. A dark edge, the body, shade on the far side and a warm
-- highlight on the side facing the light (top left). C.GILT_RELIEF sets how
-- strongly it stands out (0-1). The highlight stays warm and saturated,
-- never lightened to white.
--
-- Gold arrives in steps you can see rather than a blend through cream: a
-- pewter road first takes a thread of gold along its lit edge (over the
-- first 60% of the gilding band), then the body turns gold (from just past
-- the middle). The edge goes from iron to bronze as it does.
--
-- Past full gold, two tiers in your faction's deep colour: tier 1 a fine
-- streak down the middle; at tier 2 the shaded side takes your faction's
-- colour too (Joe's pick; enamel, banded and embossed lost on renders).
-- Tier 1 is complete at 12 (about two and a half weeks of daily use at the
-- default gold threshold), tier 2 at 16.4 (about four and a half weeks). worn is the share of the
-- band past full gold (9.6 to 20).
local function Gilt(D, g, wear, worn, alpha, thin, x1, y1, x2, y2)
    local core = thin * (1.1 + 1.9 * wear)
    local k = C.GILT_RELIEF
    local bodyT, lightT = Smooth((g - 0.55) / 0.45), Smooth(g / 0.6)
    local cr, cg, cb = Lerp(0.74, 0.96, bodyT), Lerp(0.74, 0.76, bodyT), Lerp(0.70, 0.26, bodyT)
    cr, cg, cb = Lerp(cr, 0.98, worn * 0.25), Lerp(cg, 0.62, worn * 0.25), Lerp(cb, 0.14, worn * 0.25)
    local hr, hg, hb = Lerp(0.90, 1.00, lightT), Lerp(0.89, 0.84, lightT), Lerp(0.84, 0.36, lightT)
    hg, hb = Lerp(hg, 0.90, worn), Lerp(hb, 0.48, worn)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local nx, ny = -dy / len, dx / len
    if nx * -1 + ny * 1 < 0 then nx, ny = -nx, -ny end -- towards the light (y grows upwards here)
    local off = core * 0.22
    local t1, t2 = Clamp((worn - 0.184) / 0.05), Clamp((worn - 0.605) / 0.05)
    local deep = faction.deep or { faction.r * 0.7, faction.g * 0.7, faction.b * 0.7 }
    -- the edge: iron, then bronze
    local er, eg, eb = Lerp(0.15, 0.24, g), Lerp(0.14, 0.15, g), Lerp(0.13, 0.05, g)
    D.nl = D.nl + 1
    PutLine(D.nl, 0, "BLEND", core + thin * 0.9, er, eg, eb, 0.9 * alpha, x1, y1, x2, y2)
    D.nl = D.nl + 1
    PutLine(D.nl, 1, "BLEND", core, cr, cg, cb, alpha, x1, y1, x2, y2)
    -- the shade; at tier 2 it takes your faction's colour
    local dark = 1 - 0.6 * k
    local sr, sg, sb = cr * dark, cg * dark * 0.92, cb * dark * 0.8
    sr, sg, sb = Lerp(sr, deep[1], t2), Lerp(sg, deep[2], t2), Lerp(sb, deep[3], t2)
    D.nl = D.nl + 1
    PutLine(D.nl, 2, "BLEND", core * (0.3 + 0.15 * k), sr, sg, sb, alpha,
        x1 - nx * off, y1 - ny * off, x2 - nx * off, y2 - ny * off)
    D.nl = D.nl + 1
    local stripe = PutLine(D.nl, 3, "BLEND", core * (0.25 + 0.12 * k), hr, hg, hb, alpha,
        x1 + nx * off, y1 + ny * off, x2 + nx * off, y2 + ny * off)
    -- the streak down the middle
    local streak = core * 0.2 * t1
    if streak > 0 then
        D.nl = D.nl + 1
        PutLine(D.nl, 4, "BLEND", streak, deep[1], deep[2], deep[3], alpha, x1, y1, x2, y2)
    end
    return stripe, hr, hg, hb
end

local function RoadSegment(D, g, wear, worn, alpha, thin, x1, y1, x2, y2)
    if C.ROAD_STYLE == "gilt" then return Gilt(D, g, wear, worn, alpha, thin, x1, y1, x2, y2) end
    local core = thin * (1.1 + 1.9 * wear)
    local casing = core + thin * 1.5
    local cr, cg, cb = Gild(g)
    D.nl = D.nl + 1
    PutLine(D.nl, 0, "BLEND", casing, Lerp(0.08, 0.30, worn), Lerp(0.05, 0.19, worn), Lerp(0.02, 0.07, worn),
        0.85 * alpha, x1, y1, x2, y2)
    D.nl = D.nl + 1
    PutLine(D.nl, 1, "BLEND", core, cr, cg, cb, alpha, x1, y1, x2, y2)
    if g >= 1 then
        D.nl = D.nl + 1
        local r, gg, b = Lerp(0.97, 1.00, worn), Lerp(0.80, 0.90, worn), Lerp(0.34, 0.46, worn)
        return PutLine(D.nl, 2, "BLEND", core * 0.42, r, gg, b, 1, x1, y1, x2, y2), r, gg, b
    end
end

-- Roads as chains (3.7.12): runs of stretches from one junction or end to
-- the next, so a road is drawn as one line with its corners eased, not as
-- separate sticks meeting at angles. Built from saved strengths alone, never
-- from the clock, so nothing moves while you look. A scrap of road on its own
-- (C.ROAD_SCRAP stretches or fewer, touching nothing) is a fragment, not a
-- road: it isn't drawn, but stays saved.
-- Gaps: where a road stops and another starts a few steps on (or a road's
-- end faces another road's end further on), and you have walked between them
-- (even on just one day), the road goes on through: you
-- obviously travel it, so the map shouldn't show a break. The way across is
-- ground you actually walked, never a straight-line guess, and it takes the
-- look of the weaker of the two roads it joins. Adds to adj and nodes.
local function Bridge(adj, weak, deg, nodes)
    -- Which road each point is on, and how long that road is. Scraps (see
    -- RoadChains) neither start nor end a join, or one-day wandering would
    -- chain scrap to scrap into roads that aren't there.
    local comp, size = {}, {}
    for _, n in ipairs(nodes) do
        if not comp[n] then
            local stack, ends = { n }, 0
            comp[n] = n
            while #stack > 0 do
                local u = table.remove(stack)
                ends = ends + deg[u]
                for v in pairs(adj[u]) do
                    if not comp[v] then comp[v] = n stack[#stack + 1] = v end
                end
            end
            size[n] = ends / 2
        end
    end
    local add = {}
    for _, d in ipairs(nodes) do
        if deg[d] == 1 and size[comp[d]] > C.ROAD_SCRAP then
            local from, frontier, found = { [d] = d }, { d }, nil
            for step = 1, math.max(C.ROAD_BRIDGE, C.ROAD_BRIDGE_END) do
                local ahead = {}
                for _, u in ipairs(frontier) do
                    -- Walked steps from here, and walked ground touching it
                    -- (a cell away), which a fold or a sharp bend can leave
                    -- without a recorded step between.
                    local out, ux, uy = {}, u % C.GW, math.floor(u / C.GW)
                    for v in pairs(weak[u] or {}) do out[#out + 1] = v end
                    for y = uy - 1, uy + 1 do
                        for x = ux - 1, ux + 1 do
                            local v = y * C.GW + x
                            if x >= 0 and x < C.GW and v ~= u and weak[v] and not (weak[u] and weak[u][v]) then
                                out[#out + 1] = v
                            end
                        end
                    end
                    table.sort(out)
                    for _, v in ipairs(out) do
                        if not from[v] then
                            from[v] = u
                            -- Onto any road within the short reach; further
                            -- on, only end to end: two roads stopping short of
                            -- each other along one walked line are one road.
                            if comp[v] and comp[v] ~= comp[d] and size[comp[v]] > C.ROAD_SCRAP
                                and (step <= C.ROAD_BRIDGE or deg[v] == 1) then
                                found = v break
                            end
                            if not comp[v] or size[comp[v]] <= C.ROAD_SCRAP then ahead[#ahead + 1] = v end
                        end
                    end
                    if found then break end
                end
                if found then break end
                frontier = ahead
            end
            if found then
                local far = 0
                for _, L in pairs(adj[found]) do if L > far then far = L end end
                local s = math.min(adj[d][next(adj[d])], far)
                local v = found
                while v ~= d do
                    local u = from[v]
                    add[#add + 1] = { u, v, math.max(s, weak[u] and weak[u][v] or 0) }
                    v = u
                end
            end
        end
    end
    for _, e in ipairs(add) do
        local a, b, L = e[1], e[2], e[3]
        if not adj[a] then adj[a] = {} nodes[#nodes + 1] = a end
        if not adj[b] then adj[b] = {} nodes[#nodes + 1] = b end
        if (adj[a][b] or 0) < L then adj[a][b], adj[b][a] = L, L end
    end
    table.sort(nodes)
end

-- Bubbles: a short side path that leaves a road and rejoins it a few steps
-- on (the line you took once or twice instead of the usual one) makes a thin
-- loop or a sliver of a triangle beside the road. Where the whole loop is
-- C.ROAD_BUBBLE stretches or fewer, it's one road: the weaker side isn't
-- drawn. Loops bigger than that (two ways round a hill) stay. Weakest
-- runs are settled first, so a road is never dropped in favour of its own
-- sliver. Takes edges out of adj.
local function Bubbles(adj, deg, nodes)
    local runs, seen = {}, {}
    local function Key(a, b) return math.min(a, b) * 10000 + math.max(a, b) end
    local function Run(a, b)
        local r = { a = a, edges = {}, sum = 0 }
        local prev, at = a, b
        while true do
            seen[Key(prev, at)] = true
            r.edges[#r.edges + 1] = prev
            r.edges[#r.edges + 1] = at
            r.sum = r.sum + adj[prev][at]
            if deg[at] ~= 2 or at == a then break end
            local nxt
            for m in pairs(adj[at]) do if m ~= prev then nxt = m end end
            if seen[Key(at, nxt)] then break end
            prev, at = at, nxt
        end
        r.b, r.n = at, #r.edges / 2
        r.mean = r.sum / r.n
        runs[#runs + 1] = r
    end
    for pass = 1, 2 do
        for _, n in ipairs(nodes) do
            if pass == 2 or deg[n] ~= 2 then
                local out = {}
                for m in pairs(adj[n]) do out[#out + 1] = m end
                table.sort(out)
                for _, m in ipairs(out) do
                    if not seen[Key(n, m)] then Run(n, m) end
                end
            end
        end
    end
    table.sort(runs, function(p, q)
        if p.mean ~= q.mean then return p.mean < q.mean end
        return p.edges[1] * 10000 + p.edges[2] < q.edges[1] * 10000 + q.edges[2]
    end)
    local function Drop(r)
        for i = 1, #r.edges, 2 do
            local a, b = r.edges[i], r.edges[i + 1]
            adj[a][b], adj[b][a] = nil, nil
        end
    end
    for _, r in ipairs(runs) do
        if r.n <= C.ROAD_BUBBLE and adj[r.edges[1]][r.edges[2]] then
            if r.a == r.b then
                Drop(r)
            else
                -- Another way from one end to the other, short enough to
                -- close a small loop, and at least as worn.
                local mine = {}
                for i = 1, #r.edges, 2 do mine[Key(r.edges[i], r.edges[i + 1])] = true end
                local from, frontier, found = { [r.a] = r.a }, { r.a }, false
                for _ = 1, C.ROAD_BUBBLE - r.n do
                    local ahead = {}
                    for _, u in ipairs(frontier) do
                        local out = {}
                        for v in pairs(adj[u]) do
                            if not mine[Key(u, v)] and not from[v] then out[#out + 1] = v end
                        end
                        table.sort(out)
                        for _, v in ipairs(out) do
                            if not from[v] then
                                from[v] = u
                                if v == r.b then found = true break end
                                ahead[#ahead + 1] = v
                            end
                        end
                        if found then break end
                    end
                    if found or #ahead == 0 then break end
                    frontier = ahead
                end
                if found then
                    local sum, n, v = 0, 0, r.b
                    while v ~= r.a do
                        sum, n = sum + adj[from[v]][v], n + 1
                        v = from[v]
                    end
                    if r.mean <= sum / n then Drop(r) end
                end
            end
        end
    end
end

-- The layout is settled as of your last visit (3.7.12). With nothing new
-- walked, every stretch loses strength at the same rate, so the rules above
-- (joins, scraps, stubs, loops) are decided on strengths as they stood when
-- you last travelled in the zone, and between visits the whole layout just
-- fades by that shared factor. Decided on today's strengths instead, a
-- stretch fading out opened a gap that a join filled at the brightness of
-- the roads either side: roads rewired and brightened with nothing walked.
-- Returns the chains (strengths as of the last visit) and the fade since.
local function RoadChains(z, faint, gold)
    local last = 0
    for _, rec in pairs(z.road) do
        if rec.l and rec.l > 0 and rec.tl and rec.tl > last then last = rec.tl end
    end
    local fade = math.min(1, math.exp(-C.LN2 * (PlayNow() - last) / (db.longDays * C.DAY)))
    if fade < 1e-6 then return {}, 0, {} end
    local adj, weak, nodes = {}, {}, {}
    for edge, rec in pairs(z.road) do
        local L = Long(rec) / fade
        local a, b = math.floor(edge / 10000), edge % 10000
        if L >= C.ROAD_WALKED then
            weak[a], weak[b] = weak[a] or {}, weak[b] or {}
            weak[a][b], weak[b][a] = L, L
        end
        if L >= faint then
            if not adj[a] then adj[a] = {} nodes[#nodes + 1] = a end
            if not adj[b] then adj[b] = {} nodes[#nodes + 1] = b end
            adj[a][b], adj[b][a] = L, L
        end
    end
    table.sort(nodes)
    local deg, comp, size = {}, {}, {}
    local function Degrees()
        local kept = {}
        for _, n in ipairs(nodes) do
            local d = 0
            for _ in pairs(adj[n]) do d = d + 1 end
            deg[n] = d
            if d > 0 then kept[#kept + 1] = n end
        end
        nodes = kept
    end
    Degrees()
    if C.ROAD_BRIDGE > 0 then
        Bridge(adj, weak, deg, nodes)
        Degrees()
    end
    if C.ROAD_BUBBLE > 0 then
        Bubbles(adj, deg, nodes)
        Degrees()
    end
    -- Stubs: a dead end of C.ROAD_SPUR stretches or fewer leaving a road,
    -- where you stepped aside for a quest or a herb, isn't drawn unless some
    -- of it is gold (somewhere you keep going). Decided in one pass over the
    -- saved roads, so it can't eat a road inward from its end.
    if C.ROAD_SPUR > 0 then
        local cut = {}
        for _, n in ipairs(nodes) do
            if deg[n] == 1 then
                local path, prev, at, strong = {}, n, next(adj[n]), false
                while true do
                    path[#path + 1] = prev
                    path[#path + 1] = at
                    if adj[prev][at] >= gold then strong = true end
                    if deg[at] ~= 2 or #path > 2 * C.ROAD_SPUR then break end
                    local nxt
                    for m in pairs(adj[at]) do if m ~= prev then nxt = m end end
                    prev, at = at, nxt
                end
                if deg[at] >= 3 and #path <= 2 * C.ROAD_SPUR and not strong then
                    for i = 1, #path do cut[#cut + 1] = path[i] end
                end
            end
        end
        for i = 1, #cut, 2 do
            adj[cut[i]][cut[i + 1]], adj[cut[i + 1]][cut[i]] = nil, nil
        end
        Degrees()
    end
    for _, n in ipairs(nodes) do
        if not comp[n] then
            local stack, ends = { n }, 0
            comp[n] = n
            while #stack > 0 do
                local u = table.remove(stack)
                ends = ends + deg[u]
                for v in pairs(adj[u]) do
                    if not comp[v] then comp[v] = n stack[#stack + 1] = v end
                end
            end
            size[n] = ends / 2
        end
    end
    local used, chains = {}, {}
    local function Walk(a, b)
        local pts, vals = { a }, {}
        local prev, at = a, b
        while true do
            used[math.min(prev, at) * 10000 + math.max(prev, at)] = true
            vals[#vals + 1] = adj[prev][at]
            pts[#pts + 1] = at
            if deg[at] ~= 2 or at == a then break end
            local nxt
            for m in pairs(adj[at]) do if m ~= prev then nxt = m end end
            if used[math.min(at, nxt) * 10000 + math.max(at, nxt)] then break end
            prev, at = at, nxt
        end
        chains[#chains + 1] = { pts = pts, vals = vals }
    end
    -- Ends and junctions first, then loops (from their lowest point).
    for pass = 1, 2 do
        for _, n in ipairs(nodes) do
            if size[comp[n]] > C.ROAD_SCRAP and (pass == 2 or deg[n] ~= 2) then
                local out = {}
                for m in pairs(adj[n]) do out[#out + 1] = m end
                table.sort(out)
                for _, m in ipairs(out) do
                    if not used[math.min(n, m) * 10000 + math.max(n, m)] then Walk(n, m) end
                end
            end
        end
    end
    return chains, fade, adj
end

-- Lynchpins (3.7.12): a stretch on the best way between two strong stretches
-- is held as a faint thread while the strongest stretch on each side of it is
-- still drawn, so the strong fragments a fading network leaves stay visibly
-- joined. "The best way" is the route whose weakest stretch is strongest:
-- round a loop, the better side is held and the other fades on its own. A
-- road's dead end is never held: there is nothing beyond it. These routes
-- make up the network's strongest spanning tree; a stretch on it is held by
-- the weaker of the strongest stretches on its two sides. Sets ch.hold[i]
-- (0: not held), as of the last visit, so like everything else in the layout
-- it fades by the shared factor and a thread only ever fades.
local function Lynchpins(chains, adj)
    local function Key(a, b) return math.min(a, b) * 10000 + math.max(a, b) end
    local edges, nodes, root = {}, {}, {}
    for u, near in pairs(adj) do
        nodes[#nodes + 1] = u
        root[u] = u
        for v, L in pairs(near) do
            if u < v then edges[#edges + 1] = { u, v, L } end
        end
    end
    table.sort(nodes)
    table.sort(edges, function(p, q)
        if p[3] ~= q[3] then return p[3] > q[3] end
        if p[1] ~= q[1] then return p[1] < q[1] end
        return p[2] < q[2]
    end)
    local function Find(x)
        while root[x] ~= x do root[x] = root[root[x]] x = root[x] end
        return x
    end
    -- The strongest spanning tree (Kruskal, strongest first).
    local tree = {}
    for _, e in ipairs(edges) do
        local a, b = Find(e[1]), Find(e[2])
        if a ~= b then
            root[a] = b
            tree[e[1]] = tree[e[1]] or {}
            tree[e[2]] = tree[e[2]] or {}
            tree[e[1]][e[2]], tree[e[2]][e[1]] = e[3], e[3]
        end
    end
    -- Root each tree; below[c]: strongest stretch under c; above[c]: strongest
    -- stretch anywhere else, apart from c's own stretch up to its parent.
    local held, up, seen = {}, {}, {}
    for _, r in ipairs(nodes) do
        if tree[r] and not seen[r] then
            local order, stack = {}, { r }
            seen[r] = true
            while #stack > 0 do
                local u = table.remove(stack)
                order[#order + 1] = u
                local kids = {}
                for v in pairs(tree[u]) do if not seen[v] then kids[#kids + 1] = v end end
                table.sort(kids)
                for _, v in ipairs(kids) do seen[v] = true up[v] = u stack[#stack + 1] = v end
            end
            local below = {}
            for i = #order, 1, -1 do
                local u = order[i]
                local m = 0
                for v, L in pairs(tree[u]) do
                    if up[v] == u then m = math.max(m, L, below[v]) end
                end
                below[u] = m
            end
            local above = { [r] = 0 }
            for _, u in ipairs(order) do
                -- the two best branches at u, so each child can take the best other one
                local best, second, bestKid = 0, 0, nil
                for v, L in pairs(tree[u]) do
                    if up[v] == u then
                        local b = math.max(L, below[v])
                        if b > best then best, second, bestKid = b, best, v elseif b > second then second = b end
                    end
                end
                local out = above[u]
                if up[u] then out = math.max(out, tree[u][up[u]]) end
                for v in pairs(tree[u]) do
                    if up[v] == u then
                        above[v] = math.max(out, v == bestKid and second or best)
                        held[Key(u, v)] = math.min(below[v], above[v])
                    end
                end
            end
        end
    end
    for _, ch in ipairs(chains) do
        local hold = {}
        for i = 1, #ch.vals do hold[i] = held[Key(ch.pts[i], ch.pts[i + 1])] or 0 end
        ch.hold = hold
    end
end

-- Is map point (x, y) on a road drawn on this zone (within C.ROAD_NEAR of
-- a cell)? From the pieces DrawGround kept in e.roadSegs.
local function OnRoad(e, x, y)
    local segs = e.roadSegs
    if not segs then return false end
    local GW, GH = C.GW, C.GH
    local cx, cy = math.floor(x * GW), math.floor(y * GH)
    local near2 = C.ROAD_NEAR * C.ROAD_NEAR
    for gy = cy - 1, cy + 1 do
        for gx = cx - 1, cx + 1 do
            for _, q in ipairs(segs[gy * GW + gx] or {}) do
                -- distance to the piece, in cells
                local ax, ay, bx, by = q[1] * GW, q[2] * GH, q[3] * GW, q[4] * GH
                local px, py = x * GW, y * GH
                local dx, dy = bx - ax, by - ay
                local L2 = dx * dx + dy * dy
                local t = L2 > 0 and Clamp(((px - ax) * dx + (py - ay) * dy) / L2) or 0
                local ex, ey = ax + dx * t - px, ay + dy * t - py
                if ex * ex + ey * ey < near2 then return true end
            end
        end
    end
    return false
end

local function DrawGround(D, scene)
    local L, w, h, now = cfg.layers, D.w, D.h, D.now
    if not L.roads then return end
    local gold = db.roadMin
    local silver = gold * C.SILVER_SHARE
    local faint = silver * 0.8           -- roads fade in before silver
    local gStart, gEnd = silver * 1.2, gold * 2 -- the gilding band
    local full = math.max(C.ROAD_FULL, gEnd + 4)
    if C.ROAD_STYLE == "gilt" then
        -- Bands by habit (3.7.12), not by how much anyone has played so far:
        -- a road used every k days played settles at 1 / (1 - 2^(-k/14)).
        -- At the default gold threshold (2.5): a gold thread from about twice
        -- a week (5.7, day 6.5 of daily use), fully gold at every 2 to 2.5
        -- days (9.6, day 12.5; Joe's middle ground), the faction mark's
        -- two tiers after about 2.5 and 4.5 weeks of daily use (12, 16.4),
        -- and the band's end at 20 (the ceiling is 20.7). Silver stays at two
        -- recent days.
        gStart, gEnd, full = gold * C.GILD_START, gold * C.GILD_FULL, gold * C.GILD_TOP
    end
    local roadCap = C.LINE_BUDGET - C.ROAD_RESERVE - 3
    local shine = cfg.shimmer
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        local thin = p.far and w * 0.0011 or w * 0.0020
        local candidates = {}
        local segs = {} -- pieces you can see, for the trail to give way to
        e.roadSegs = segs
        local chains, fade, adj = RoadChains(z, faint, gold)
        if C.ROAD_THREAD > 0 then Lynchpins(chains, adj) end
        -- How much of a stretch of this strength shows: all of it from
        -- silver, fading all the way out by the time it stops being drawn
        -- (3.7.12; it used to stop at a quarter and then vanish in one step).
        local function Seen(s) return s >= silver and 1 or s > faint and (s - faint) / (silver - faint) or 0 end
        -- One piece of a chain, from map point (ax, ay) to (bx, by), at its
        -- strength as of the last visit (and what holds it, if a lynchpin);
        -- drawn at that faded by the time since.
        -- look: the strength its colour, width and tier come from, smoothed
        -- along the road so a whole stretch gilds together (3.7.12); whether
        -- and how much it shows still comes from its own strength.
        -- joinA/joinB: that end meets another piece (not a road's dead end).
        local function Piece(long, look, hold, ax, ay, bx, by, joinA, joinB)
            long, look = long * fade, (look or long) * fade
            local alpha = math.max(Seen(long), C.ROAD_THREAD * Seen((hold or 0) * fade))
            if alpha > 0.3 then -- the trail gives way to roads you can see
                local k = math.floor((ay + by) / 2 * C.GH) * C.GW + math.floor((ax + bx) / 2 * C.GW)
                segs[k] = segs[k] or {}
                table.insert(segs[k], { ax, ay, bx, by })
            end
            local x1, y1, x2, y2 = ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy)
            if D.nl >= roadCap or alpha <= 0 then return end
            local g = Clamp((look - gStart) / (gEnd - gStart))
            local wear = Clamp((look - silver) / (full - silver))
            local worn = look >= gEnd and Clamp((look - gEnd) / (full - gEnd)) or 0
            -- Overlap the next piece a little, so the dark edge can't show
            -- through the outside of a bend as a notch. Only while fully
            -- drawn: overlapping faded pieces would bead at every join.
            if alpha >= 0.99 then
                local dx, dy = x2 - x1, y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    local e = thin * (1.1 + 1.9 * wear) * 0.5 / len
                    if joinA then x1, y1 = x1 - dx * e, y1 - dy * e end
                    if joinB then x2, y2 = x2 + dx * e, y2 + dy * e end
                end
            end
            local stripe, r, gg, bb = RoadSegment(D, g, wear, worn, alpha, thin, x1, y1, x2, y2)
            if stripe and worn > 0.05 and shine then
                shimmer[#shimmer + 1] = { l = stripe, u = (ax + bx) * 0.5 + (ay + by) * 0.3,
                    worn = worn, r = r, g = gg, b = bb }
                if worn > 0.6 then
                    candidates[#candidates + 1] = { x = (ax + bx) / 2, y = (ay + by) / 2, worn = worn }
                end
            end
        end
        for _, ch in ipairs(chains) do
            local px, py = {}, {}
            for i, c in ipairs(ch.pts) do
                px[i], py[i] = z.cx[c], z.cy[c]
                if not px[i] then px[i], py[i] = CellXY(c, C.GW, C.GH) end
            end
            -- Corners cut a quarter of the way along each side (Chaikin):
            -- each stretch is drawn straight through its middle half, and
            -- each bend as a short piece blending the two stretches it joins.
            -- Junctions and ends stay exactly where they are.
            local n, vals, hold = #ch.vals, ch.vals, ch.hold or {}
            -- a chain's end point meets other roads unless it's a dead end
            local function Joined(c)
                local k = 0
                for _ in pairs(adj[c] or {}) do k = k + 1 end
                return k > 1
            end
            -- The look, smoothed along the road: a weighted average of each
            -- stretch and up to C.ROAD_SMOOTH either side of it.
            local look, R = {}, C.ROAD_SMOOTH
            for i = 1, n do
                local sum, wt = 0, 0
                for j = math.max(1, i - R), math.min(n, i + R) do
                    local k = R + 1 - math.abs(i - j)
                    sum, wt = sum + vals[j] * k, wt + k
                end
                look[i] = sum / wt
            end
            local lx, ly
            for i = 1, n do
                local sx0, sy0 = px[i], py[i]
                if i > 1 then sx0, sy0 = 0.75 * px[i] + 0.25 * px[i + 1], 0.75 * py[i] + 0.25 * py[i + 1] end
                local ex, ey = px[i + 1], py[i + 1]
                if i < n then ex, ey = 0.25 * px[i] + 0.75 * px[i + 1], 0.25 * py[i] + 0.75 * py[i + 1] end
                if lx then
                    Piece((vals[i - 1] + vals[i]) / 2, (look[i - 1] + look[i]) / 2,
                        math.min(hold[i - 1] or 0, hold[i] or 0), lx, ly, sx0, sy0, true, true)
                end
                Piece(vals[i], look[i], hold[i], sx0, sy0, ex, ey, i > 1 or Joined(ch.pts[1]),
                    i < n or Joined(ch.pts[n + 1]))
                lx, ly = ex, ey
            end
        end
        -- Amber glints on the most worn roads, sparse.
        if #candidates > 0 then
            table.sort(candidates, function(a, b)
                if a.worn ~= b.worn then return a.worn > b.worn end
                if a.x ~= b.x then return a.x < b.x end
                return a.y < b.y
            end)
            local placed = {}
            for _, c in ipairs(candidates) do
                if #placed >= C.GLINT_CAP then break end
                local ok = true
                for _, q in ipairs(placed) do
                    if (q.x - c.x) ^ 2 + (q.y - c.y) ^ 2 < 0.06 * 0.06 then ok = false break end
                end
                if ok then
                    placed[#placed + 1] = c
                    D.ngl = D.ngl + 1
                    local gl = GetGlint(D.ngl)
                    local size = thin * 8
                    gl:SetSize(size, size)
                    At(gl, p, c.x, c.y, w, h)
                    gl:SetAlpha(0)
                    gl:Show()
                    twinkle[#twinkle + 1] = { tex = gl, phase = (c.x * 37 + c.y * 91) % 6.28, base = 0.35 + 0.5 * c.worn }
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Today's trail (3.8): where you lingered becomes an outlined area; the
-- trail between areas shows its age by colour and dash rhythm, and which
-- way you went by arrows. Everything is anchored to the ground and only
-- fades (an area grows only while you're in it).
---------------------------------------------------------------------------

local Linger = ns.Linger

-- Where an age sits between the solid line's end and the trail's end, on a scale that
-- moves fast early: 5 m, 15 m, 1 h, 4 h and 24 h are about evenly spaced.
local function TrailG(age, life)
    if age <= C.LINE_SOLID then return 0 end
    -- TRAIL_STEP: a jump along the gradient where the solid line turns to
    -- dashes, so the change is noticeable early; then the slow fade
    local step = C.TRAIL_STEP or 0
    return Clamp(step + (1 - step) * math.log(age / C.LINE_SOLID) / math.log(life / C.LINE_SOLID))
end

-- Colour, opacity, thickness and dash fill for trail of a given age.
-- Colour runs faction -> faction deep, then stays deep; the dashes go long
-- -> a little shorter; everything fades out over the last quarter.
-- 3.8.3 (Joe's pick, over his Dustwallow screenshot): old trail used to sink
-- to an earthy dusk and shrink to dots, which on marsh art drawn in that
-- same red-brown ink couldn't be followed. It now stays crimson, long
-- dashes, and fades less; the casing (TRAIL_CASE) keeps it off the map ink.
local function TrailLook(age, life)
    local g, d = TrailG(age, life), faction.deep
    local t = math.min(1, g / 0.55)
    local r, gg, b = Lerp(faction.r, d[1], t), Lerp(faction.g, d[2], t), Lerp(faction.b, d[3], t)
    local tail = 1 - Smooth((age - life * 0.75) / (life * 0.25))
    local fill = 0.85 - 0.20 * Smooth((g - 0.27) / 0.12)
    return r, gg, b, (0.95 - 0.15 * g) * tail, 1 - 0.1 * g, fill
end

-- Each zone's areas as drawn now, the clips they put on the trail, and
-- their visits in time order (for holding links). Kept on the scene entry.
local function AreaScene(e, now, life)
    local list, solid, dash, visits, hide, settled = {}, {}, {}, {}, {}, {}
    -- Linger.lua is new in 3.8: after a /reload without a restart the game
    -- hasn't loaded it, so draw the trail without areas rather than fail
    if not Linger then
        e.lg = { areas = list, solid = solid, dash = dash, visits = visits, hide = hide, settled = settled }
        return
    end
    local live = Linger.Live()
    for _, a in ipairs(e.z.areas or {}) do
        local isLive = a == live
        local age = isLive and 0 or now - (a.e or 0)
        if age < life and a.h and #a.h >= 2 and a.v and #a.v > 0 then
            local poly, box = Linger.Outline(a)
            list[#list + 1] = { a = a, poly = poly, box = box, age = age, live = isLive }
            -- Dashes inside are hidden, in the area you're in and after you
            -- leave alike: they were never shown there, so they mustn't come
            -- back when you go. Only the solid line, which shows inside while
            -- you're there, fades out over a minute after you leave.
            dash[#dash + 1] = { poly = poly, box = box, k = 0 }
            if not isLive then
                local c = { poly = poly, box = box, k = 1 - Smooth((now - a.e) / 60) }
                solid[#solid + 1], settled[#settled + 1] = c, c
            else
                -- in the area you're in, only your last few seconds of line
                -- show (SHOW, 3 s from 3.8.2; 45 s before): the area is
                -- there to stop the scribble
                settled[#settled + 1] = { poly = poly, box = box, k = 0 }
            end
            for _, v in ipairs(a.v) do visits[#visits + 1] = { s = v.s, e = v.e, age = age, a = a } end
            -- Every step taken during a visit joined the area, so trail from
            -- then is inside the outline: once hidden, skip it by its time
            -- alone, before any cutting (most of a tangle is here).
            do
                for vi, v in ipairs(a.v) do
                    -- only the visit you're in runs to now; earlier ones end
                    -- when they ended (or the trail between them vanishes)
                    local open = isLive and vi == #a.v
                    local hs, he = v.s + 20, (open and now or v.e) - Linger.LAG - 20
                    if he > hs then hide[#hide + 1] = hs hide[#hide + 1] = he end
                end
            end
        end
    end
    table.sort(visits, function(x, y) return x.s < y.s end)
    e.lg = { areas = list, solid = solid, dash = dash, visits = visits, hide = hide, settled = settled }
end

-- A link between two different areas stays at least as visible as the
-- older of them, so an area never hangs off a link that faded first. Only
-- its visibility is held: its colour and dashes still show its own age. A
-- loop out of an area and back into the same one isn't held (it joins
-- nothing else, and the area being live would hold it as new).
local function HeldAge(visits, t, age)
    local prev, nxt
    for _, v in ipairs(visits) do
        if v.e <= t then prev = v elseif v.s >= t then nxt = v break end
    end
    if prev and nxt and prev.a ~= nxt.a then return math.min(age, math.max(prev.age, nxt.age)) end
    return age
end

-- One piece of trail in zone coordinates, cut where it crosses an area's
-- outline: inside, it's drawn at that area's k (often not at all).
local ink = {}
local function InkPart(t0, t1, k)
    local q = ink
    local D = q.D
    if D.nl >= C.LINE_BUDGET or (q.count and D.ndash >= C.DASH_BUDGET) then return end
    local x1, y1 = q.x1 + (q.x2 - q.x1) * t0, q.y1 + (q.y2 - q.y1) * t0
    local x2, y2 = q.x1 + (q.x2 - q.x1) * t1, q.y1 + (q.y2 - q.y1) * t1
    D.nl = D.nl + 1
    if q.count then D.ndash = D.ndash + 1 end
    local p = q.p
    PutLine(D.nl, q.sub, "BLEND", q.thick, q.r, q.g, q.b, q.a * k,
        (p.ox + x1 * p.sx) * D.w, -(p.oy + y1 * p.sy) * D.h, (p.ox + x2 * p.sx) * D.w, -(p.oy + y2 * p.sy) * D.h)
end
local function InkOnce(D, p, clips, sub, thick, r, g, b, a, x1, y1, x2, y2, count)
    ink.D, ink.p, ink.sub, ink.thick, ink.r, ink.g, ink.b, ink.a = D, p, sub, thick, r, g, b, a
    ink.x1, ink.y1, ink.x2, ink.y2, ink.count = x1, y1, x2, y2, count
    if Linger then Linger.Clip(clips, x1, y1, x2, y2, InkPart) else InkPart(0, 1, 1) end
end
-- Trail dashes (count) sit on a dark casing, a layer below every dash's
-- colour, so they read over any map art (3.8.3, Joe's pick: 1.7 x the
-- width). The casing isn't counted against DASH_BUDGET, only LINE_BUDGET.
local function Ink(D, p, clips, sub, thick, r, g, b, a, x1, y1, x2, y2, count)
    if count then InkOnce(D, p, clips, sub - 1, thick * C.TRAIL_CASE, 0.10, 0.04, 0.03, a * 0.75, x1, y1, x2, y2) end
    InkOnce(D, p, clips, sub, thick, r, g, b, a, x1, y1, x2, y2, count)
end

-- The line: your last minutes, solid (LINE_SOLID: 2.5 min in 3.8). Trail recorded before 3.4
-- has no point times and isn't drawn.
local function DrawWalkLine(D, scene)
    local w, now = D.w, D.now
    local cutoff = now - C.LINE_SOLID
    for _, e in ipairs(scene.zones) do
        local p, strokes = e.p, e.z.strokes
        local thick = p.far and w * 0.0012 or w * 0.0022
        for si = #strokes, 1, -1 do -- newest first, so the budget drops the oldest
            local s = strokes[si]
            if s.e < cutoff or D.nl >= C.LINE_BUDGET then break end
            local n = #s / 2
            if s.ts and n >= 2 then
                for i = n - 1, 1, -1 do
                    local t2 = PointTime(s, i + 1)
                    if t2 < cutoff or D.nl >= C.LINE_BUDGET then break end
                    local t1 = PointTime(s, i)
                    local ax, ay, bx, by = s[2 * i - 1], s[2 * i], s[2 * i + 1], s[2 * i + 2]
                    if t1 < cutoff and t2 > t1 then -- trim the piece older than the line
                        local k = (cutoff - t1) / (t2 - t1)
                        ax, ay = ax + (bx - ax) * k, ay + (by - ay) * k
                        t1 = cutoff
                    end
                    -- older than a few seconds: settled, so hidden inside the area you're in too
                    -- (steps that haven't joined yet lie outside its outline, so they still show)
                    local settle = now - (Linger and Linger.SHOW or 3)
                    if t2 <= settle then
                        Ink(D, p, e.lg.settled, 7, thick, faction.r, faction.g, faction.b, 0.95, ax, ay, bx, by)
                    elseif t1 >= settle or t2 <= t1 then
                        Ink(D, p, e.lg.solid, 7, thick, faction.r, faction.g, faction.b, 0.95, ax, ay, bx, by)
                    else
                        local k = (settle - t1) / (t2 - t1)
                        local mx, my = ax + (bx - ax) * k, ay + (by - ay) * k
                        Ink(D, p, e.lg.settled, 7, thick, faction.r, faction.g, faction.b, 0.95, ax, ay, mx, my)
                        Ink(D, p, e.lg.solid, 7, thick, faction.r, faction.g, faction.b, 0.95, mx, my, bx, by)
                    end
                end
            end
        end
    end
end

-- The trail runs right up to you (3.8): one line from the end of the
-- trail as last drawn to where you are now, kept up to date while the map
-- is open (the trail itself is redrawn every 2 seconds at most), so no gap
-- opens behind your arrow as you move.
local tail = {}
local function UpdateTail()
    local l = tail.line
    if not l then return end
    local p = tail.p
    if not p or tail.stroke ~= cur.stroke or cur.mode then l:Hide() return end
    local mapID, x, y = ns.PlayerPos()
    if mapID ~= cur.map then l:Hide() return end
    local w, h = overlay:GetWidth(), overlay:GetHeight()
    l:SetStartPoint("TOPLEFT", overlay, (p.ox + tail.x * p.sx) * w, -(p.oy + tail.y * p.sy) * h)
    l:SetEndPoint("TOPLEFT", overlay, (p.ox + x * p.sx) * w, -(p.oy + y * p.sy) * h)
    l:Show()
end

local function SetTail(D, scene)
    local s = cur.stroke
    if not s or cur.mode or #s < 4 or not tail.line then return end -- a trail, not a lone point
    for _, e in ipairs(scene.zones) do
        if e.p.mapID == cur.map then
            tail.stroke, tail.p, tail.x, tail.y = s, e.p, s[#s - 1], s[#s]
            tail.line:SetThickness(e.p.far and D.w * 0.0012 or D.w * 0.0022)
            tail.line:SetColorTexture(faction.r, faction.g, faction.b, 0.95)
            return
        end
    end
end

-- Positions along a stroke by distance (s.d), and the time there.
local function SegAt(d, a)
    local lo, hi = 1, #d - 1
    while lo < hi do
        local m = math.floor((lo + hi + 1) / 2)
        if d[m] <= a then lo = m else hi = m - 1 end
    end
    return lo
end
local function OnStroke(s, d, a)
    local i = SegAt(d, a)
    local f = d[i + 1] > d[i] and Clamp((a - d[i]) / (d[i + 1] - d[i])) or 0
    local t1 = PointTime(s, i)
    return s[2 * i - 1] + (s[2 * i + 1] - s[2 * i - 1]) * f, s[2 * i] + (s[2 * i + 2] - s[2 * i]) * f,
        t1 + (PointTime(s, i + 1) - t1) * f, i
end

-- Dashes are drawn along the path smoothed along its own length (3.8):
-- each point is a weighted average of the path a little either side of it
-- (TRAIL_SMOOTH dash slots), so small kinks from recording don't read as
-- jaggies. It depends only on ground already walked, never on the time, so
-- dashes stay anchored. The window narrows evenly near a stroke's ends,
-- which on a straight path changes nothing as the stroke grows.
local SMOOTH_AT, SMOOTH_WT = { -1, -0.5, 0, 0.5, 1 }, { 1, 2, 3, 2, 1 }
local smoothW = 0
local function PathAt(s, d, a)
    local w = math.min(smoothW, a, d[#d] - a)
    if w <= 0 then
        local x, y = OnStroke(s, d, a)
        return x, y
    end
    local sx, sy, sw = 0, 0, 0
    for i = 1, 5 do
        local x, y = OnStroke(s, d, a + SMOOTH_AT[i] * w)
        local k = SMOOTH_WT[i]
        sx, sy, sw = sx + x * k, sy + y * k, sw + k
    end
    return sx / sw, sy / sw
end

-- The trail from distance a0 to a1, following its bends; returns the last
-- piece's ends (for an arrowhead).
local function Stretch(D, p, clips, thick, r, g, b, a, s, d, a0, a1)
    if smoothW > 0 then
        local n = math.max(1, math.ceil((a1 - a0) / (smoothW * 0.35)))
        local x0, y0 = PathAt(s, d, a0)
        local x1, y1
        for i = 1, n do
            x1, y1 = PathAt(s, d, a0 + (a1 - a0) * i / n)
            Ink(D, p, clips, 6, thick, r, g, b, a, x0, y0, x1, y1, true)
            if i < n then x0, y0 = x1, y1 end
        end
        return x0, y0, x1, y1
    end
    local x0, y0, _, j = OnStroke(s, d, a0)
    local px, py, qx, qy
    while true do
        local stop = math.min(a1, d[j + 1])
        local x1, y1 = OnStroke(s, d, stop)
        Ink(D, p, clips, 6, thick, r, g, b, a, x0, y0, x1, y1, true)
        px, py, qx, qy = x0, y0, x1, y1
        if stop >= a1 or j >= #d - 1 then break end
        x0, y0, j = x1, y1, j + 1
    end
    return px, py, qx, qy
end

-- Arrows: every third mark. The marks repeat in a fixed pattern on the
-- ground, every PERIOD dash slots: dash, dash, arrow, with even gaps
-- between all three (laid out at a fresh dash's length). An arrow's shaft is
-- 75% of a slot plus a dash (Joe's pick); its tip is fixed, so as it ages it
-- only shortens from the back, while dashes shorten about their centres.
-- None where the path bends sharply under it: a plain dash instead.
local ARROW_SHAFT, ARROW_HEAD, ARROW_BEND = 0.75, 0.6, math.cos(math.rad(35))
local PERIOD = 4                                       -- in dash slots
local SHAFT0 = ARROW_SHAFT * (1 + 0.85)                -- a fresh arrow's shaft, in slots
local GAP0 = (PERIOD - 2 * 0.85 - SHAFT0) / 3          -- the even gap
local MARKS = { PERIOD - SHAFT0 / 2, GAP0 * 2 + 0.85 * 1.5, GAP0 + 0.85 / 2 } -- centres: arrow, dash, dash
local GROW = (2 + ARROW_SHAFT) / 3                    -- each gap's share as marks shorten
local SHRINK = { 0.5, 2 * GROW - 1, GROW }           -- share lost at each mark's back (arrow fallback: even)

local function ArrowSpan(s, d, tip, slot, fill)
    if tip > d[#d] then return end
    local a0 = math.max(0, tip - ARROW_SHAFT * (slot + fill * slot))
    -- the bend is judged over the arrow at full length, which never changes,
    -- so an arrow can't switch on as it ages
    local full = math.max(0, tip - SHAFT0 * slot)
    local q = (tip - full) * 0.3
    local x0, y0 = PathAt(s, d, full)
    local x1, y1 = PathAt(s, d, full + q)
    local x2, y2 = PathAt(s, d, tip - q)
    local x3, y3 = PathAt(s, d, tip)
    local ux, uy, vx, vy = x1 - x0, (y1 - y0) * 668 / 1002, x3 - x2, (y3 - y2) * 668 / 1002
    local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
    if lu == 0 or lv == 0 or (ux * vx + uy * vy) / (lu * lv) < ARROW_BEND then return end
    return a0, tip
end

local HEAD_WINGS = { 2.6, -2.6 }
local function ArrowHead(D, p, clips, thick, r, g, b, a, px, py, qx, qy, size)
    local sx, sy = p.sx * D.w, p.sy * D.h
    local dx, dy = (qx - px) * sx, (qy - py) * sy
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end
    local ux, uy = dx / len, dy / len
    local wing = math.max(size, thick * 1.6)
    for _, sg in ipairs(HEAD_WINGS) do
        local c, sn = math.cos(sg), math.sin(sg)
        Ink(D, p, clips, 6, thick, r, g, b, a, qx, qy,
            qx + (ux * c - uy * sn) * wing / sx, qy + (ux * sn + uy * c) * wing / sy, true)
    end
end

-- One stroke's dashes, newest first. Each dash has a fixed place on the
-- ground, measured along the stroke from where it began (s.d), so walking
-- on and time passing never move it: it only shortens and fades.
local function Buried(hide, t)
    for i = 1, #hide, 2 do
        if t >= hide[i] and t <= hide[i + 1] then return true end
    end
end

local function MarkAge(D, e, s, d, at, life)
    if at > d[#d] then return end
    local _, _, t = OnStroke(s, d, at)
    if Buried(e.lg.hide, t) then return end
    local age = D.now - t
    if age < C.LINE_SOLID then return end
    local held = HeldAge(e.lg.visits, t, age)
    if held >= life then return false end
    return held, age
end

-- Older trail gives way to a newer pass along the same way (3.8.3, Joe's
-- pick D): walking out and back, or the same stretch twice, drew rails side
-- by side. A mark is hidden where a mark at least TRAIL_YIELD_T newer runs
-- alongside it (within TRAIL_YIELD slots, about the same direction either
-- way); crossings stay. Marks are drawn newest first, so the newer ones are
-- already in e.seen, a grid of pixel cells one radius across. Every newer
-- mark still on the trail counts, faded by a road or not, so nothing can
-- reappear as time passes: only walking there again hides anything.
local function Yields(D, e, s, d, at, slot, t)
    local p = e.p
    local sw, sh = p.sx * D.w, p.sy * D.h
    local x, y = OnStroke(s, d, at)
    local ax, ay = OnStroke(s, d, math.max(0, at - 0.3 * slot))
    local bx, by = OnStroke(s, d, math.min(d[#d], at + 0.3 * slot))
    local X, Y, dx, dy = x * sw, y * sh, (bx - ax) * sw, (by - ay) * sh
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then dx, dy = dx / len, dy / len end
    local R = C.TRAIL_YIELD * slot * sw
    local gx, gy = math.floor(X / R), math.floor(Y / R)
    local seen = e.seen
    for i = -1, 1 do
        for j = -1, 1 do
            local c = seen[(gx + i) * 65536 + gy + j]
            if c then
                for _, q in ipairs(c) do
                    if q.t >= t + C.TRAIL_YIELD_T and (q.x - X) ^ 2 + (q.y - Y) ^ 2 < R * R
                        and math.abs(q.dx * dx + q.dy * dy) > C.TRAIL_YIELD_COS then
                        return true
                    end
                end
            end
        end
    end
    local k = gx * 65536 + gy
    seen[k] = seen[k] or {}
    table.insert(seen[k], { x = X, y = Y, dx = dx, dy = dy, t = t })
end

-- Where a mark sits along the stroke at its full (fresh) length: the arrow
-- with its whole shaft, a dash 0.425 of a slot either side of its centre.
local function MarkExtent(base, i, slot)
    local at = base + MARKS[i] * slot
    local half = (i == 1 and SHAFT0 / 2 or 0.425) * slot
    return at - half, at + half
end

-- Sharp turns stay solid (3.8.3, Joe): at a hairpin the dashes broke into
-- scattered pieces, so where the path turns more than TURN_SHARP over a
-- slot either side, the trail never breaks into dashes. The solid stretch
-- runs TURN_PAD slots before and after the turn, out to the full length
-- of any mark it touches, so the next dash keeps the usual gap. Judged on
-- the smoothed path at fixed places along the stroke, only where the path
-- after it is already final, so a turn's stretch never moves.
local function TurnSpans(D, p, s, d, slot)
    local last, sw, sh = d[#d], p.sx * D.w, p.sy * D.h
    local function Turn(a)
        local x0, y0 = PathAt(s, d, a - slot)
        local x1, y1 = PathAt(s, d, a)
        local x2, y2 = PathAt(s, d, a + slot)
        local ux, uy, vx, vy = (x1 - x0) * sw, (y1 - y0) * sh, (x2 - x1) * sw, (y2 - y1) * sh
        local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
        if lu == 0 or lv == 0 then return 0 end
        return math.acos(math.max(-1, math.min(1, (ux * vx + uy * vy) / (lu * lv))))
    end
    local spans, pad, s0, s1 = {}, C.TURN_PAD * slot, nil, nil
    local stop = last - slot - 2 * smoothW
    for k = 4, math.huge do
        local a = k * 0.25 * slot
        local sharp = a <= stop and Turn(a) > C.TURN_SHARP
        if sharp then
            s0, s1 = s0 or a, a
        elseif s0 then
            local x0, x1 = s0 - pad, s1 + pad
            -- out to the full length of every mark it touches
            local per = PERIOD * slot
            for m = math.floor(x0 / per) - 1, math.floor(x1 / per) + 1 do
                for i = 1, #MARKS do
                    local lo, hi = MarkExtent(m * per, i, slot)
                    if hi > x0 and lo < x1 then x0, x1 = math.min(x0, lo), math.max(x1, hi) end
                end
            end
            local n = #spans
            if n > 0 and x0 <= spans[n] then
                spans[n] = math.max(spans[n], x1)
            else
                spans[n + 1], spans[n + 2] = math.max(0, x0), math.min(last, x1)
            end
            s0 = nil
        end
        if a > stop then break end
    end
    return spans
end

local function InTurn(spans, lo, hi)
    for j = 1, #spans, 2 do
        if hi > spans[j] and lo < spans[j + 1] then return true end
    end
end

-- One turn's solid stretch, in the look of its age at its middle.
local function DrawTurn(D, e, s, d, x0, x1, slot, life, line)
    local c = (x0 + x1) / 2
    local held, age = MarkAge(D, e, s, d, c, life)
    if not held or Yields(D, e, s, d, c, slot, D.now - age) then return end
    local r, g, b, _, tk = TrailLook(age, life)
    local _, _, _, a = TrailLook(held, life)
    if e.roadSegs and age > C.TRAIL_ROAD_KEEP then
        local x, y = OnStroke(s, d, c)
        if OnRoad(e, x, y) then a = a * (1 - Smooth((age - C.TRAIL_ROAD_KEEP) / C.TRAIL_ROAD_FADE)) end
    end
    if a >= 0.01 then Stretch(D, e.p, e.lg.dash, line * tk, r, g, b, a, s, d, x0, x1) end
end

local function StrokeDashes(D, e, s, life, slot, line)
    local p, clips = e.p, e.lg.dash
    local d = StrokeArc(s)
    local last = d[#d]
    smoothW = (C.TRAIL_SMOOTH or 0) * slot
    local turns = TurnSpans(D, p, s, d, slot)
    for j = #turns - 1, 1, -2 do -- newest first, like the marks
        if D.ndash >= C.DASH_BUDGET then return end
        DrawTurn(D, e, s, d, turns[j], turns[j + 1], slot, life, line)
    end
    for m = math.floor(last / (PERIOD * slot)), 0, -1 do
        local base = m * PERIOD * slot
        for i = 1, #MARKS do -- newest first: the arrow, then the two dashes
            if D.ndash >= C.DASH_BUDGET then return end
            local at = base + MARKS[i] * slot
            local held, age = MarkAge(D, e, s, d, at, life)
            if held == false then return end -- older than the trail: the rest is too
            if held and #turns > 0 and InTurn(turns, MarkExtent(base, i, slot)) then held = nil end
            if held and Yields(D, e, s, d, at, slot, D.now - age) then held = nil end
            local r, g, b, tk, fill, a, _
            if held then
                r, g, b, _, tk, fill = TrailLook(age, life)   -- how it looks: its own age
                _, _, _, a = TrailLook(held, life)              -- how visible: held by its areas
                -- Where it runs along a road you can see, older trail fades
                -- out and leaves the road to say it (3.8.3, Joe's pick): the
                -- same path drawn twice was most of the clutter. Decided by
                -- each dash's place and age alone, so nothing crawls.
                if e.roadSegs and age > C.TRAIL_ROAD_KEEP then
                    local x, y = OnStroke(s, d, at)
                    if OnRoad(e, x, y) then a = a * (1 - Smooth((age - C.TRAIL_ROAD_KEEP) / C.TRAIL_ROAD_FADE)) end
                end
                if a < 0.01 then held = nil end
            end
            if held then
                local a0, tip
                if i == 1 then a0, tip = ArrowSpan(s, d, base + PERIOD * slot, slot, fill) end
                if a0 then
                    local px, py, qx, qy = Stretch(D, p, clips, line * tk, r, g, b, a, s, d, a0, tip)
                    ArrowHead(D, p, clips, line * tk, r, g, b, a, px, py, qx, qy, fill * slot * p.sx * D.w * ARROW_HEAD)
                else
                    -- as marks shorten, every gap grows alike: the arrow loses
                    -- length at its back, so the dashes give up more at the
                    -- side facing it (front dash: SHRINK[2], back: SHRINK[3])
                    local lose = (0.85 - fill) * slot
                    local k = SHRINK[i]
                    Stretch(D, p, clips, line * tk, r, g, b, a, s, d,
                        math.max(0, at - 0.425 * slot + lose * k), math.min(last, at + 0.425 * slot - lose * (1 - k)))
                end
            end
        end
    end
end

local function DrawTrail(D, scene)
    local w, now = D.w, D.now
    local life = TrailSeconds()
    local oldest = now - life
    for _, e in ipairs(scene.zones) do
        local p, strokes = e.p, e.z.strokes
        local line = p.far and w * 0.0012 or w * 0.0022
        local thin = p.far and w * 0.0011 or w * 0.0020
        local slot = C.DASH_PERIOD * thin / (p.sx * w) -- one dash slot, in map widths
        e.seen = {} -- marks drawn so far this redraw, for Yields
        for si = #strokes, 1, -1 do -- newest first
            local s = strokes[si]
            if s.e < oldest or D.ndash >= C.DASH_BUDGET then break end
            if s.ts and #s >= 4 then StrokeDashes(D, e, s, life, slot, line) end
        end
    end
end

-- The outlines: the area you're in solid, the rest dashed in the rhythm and
-- colour of their age, with the time spent there above each.
local function Spent(sec)
    if sec < 3600 then return math.max(1, math.floor(sec / 60 + 0.5)) .. "m" end
    return (("%.1f"):format(sec / 3600):gsub("%.0$", "")) .. "h"
end

-- Past areas' outlines are drawn like the trail (3.8.3, Joe's pick C): the
-- trail's own dash, one per slot, on the same dark casing. The period never
-- changes with age, so each dash keeps its place and only shortens.
local function DrawOutline(D, p, poly, thick, r, g, b, a, dash, gap, cased)
    local pos = 0
    for i = 1, #poly / 2 - 1 do
        local x1, y1, x2, y2 = poly[2 * i - 1], poly[2 * i], poly[2 * i + 1], poly[2 * i + 2]
        local L = math.sqrt((x2 - x1) ^ 2 + ((y2 - y1) * 668 / 1002) ^ 2)
        local u = 0
        while u < L and D.nl < C.LINE_BUDGET do
            local ph = gap > 0 and (pos + u) % (dash + gap) or 0
            if gap == 0 or ph < dash then
                local v = gap == 0 and L or math.min(L, u + math.max(dash - ph, 1e-7))
                local f0, f1 = u / L, v / L
                local px0, py0 = (p.ox + (x1 + (x2 - x1) * f0) * p.sx) * D.w, -(p.oy + (y1 + (y2 - y1) * f0) * p.sy) * D.h
                local px1, py1 = (p.ox + (x1 + (x2 - x1) * f1) * p.sx) * D.w, -(p.oy + (y1 + (y2 - y1) * f1) * p.sy) * D.h
                if cased then
                    D.nl = D.nl + 1
                    PutLine(D.nl, 5, "BLEND", thick * C.TRAIL_CASE, 0.10, 0.04, 0.03, a * 0.75, px0, py0, px1, py1)
                end
                D.nl = D.nl + 1
                PutLine(D.nl, 6, "BLEND", thick, r, g, b, a, px0, py0, px1, py1)
                u = v
            else
                u = u + math.max(dash + gap - ph, 1e-7)
            end
        end
        pos = pos + L
    end
end

local function AreaTag(D, p, ar, a)
    local total = 0
    for _, v in ipairs(ar.a.v) do total = total + (v.t or 0) end
    local poly, top, ty = ar.poly, 1, math.huge
    for i = 2, #poly, 2 do if poly[i] < ty then top, ty = i - 1, poly[i] end end
    D.ntag = D.ntag + 1
    -- WoW's own yellow on a dark patch (Joe's pick, 3.8.3). The label stays
    -- full strength while the outline fades, and goes only in its last quarter.
    local y = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
    ns.PlaceTag(D.ntag, ar, Spent(total), y.r, y.g, y.b,
        math.min(1, 0.2 + 1.6 * a), (p.ox + poly[top] * p.sx) * D.w, -(p.oy + ty * p.sy) * D.h)
end

local function DrawAreas(D, scene)
    local w = D.w
    local life = TrailSeconds()
    for _, e in ipairs(scene.zones) do
        local p = e.p
        local line = p.far and w * 0.0012 or w * 0.0022
        local thin = p.far and w * 0.0011 or w * 0.0020
        local slot = C.DASH_PERIOD * thin / (p.sx * w)
        for _, ar in ipairs(e.lg.areas) do
            local r, g, b, a, tk, fill
            if ar.live then
                r, g, b, a = faction.r, faction.g, faction.b, 0.95
                DrawOutline(D, p, ar.poly, line * 1.05, r, g, b, a, 1, 0)
            else
                r, g, b, a, tk, fill = TrailLook(math.max(ar.age, C.LINE_SOLID + 1), life)
                DrawOutline(D, p, ar.poly, line * tk, r, g, b, a, slot * fill, slot * (1 - fill), true)
            end
            if not p.far and a > 0.05 then AreaTag(D, p, ar, a) end
        end
    end
end

local function DrawToday(D, scene)
    local life = TrailSeconds()
    for _, e in ipairs(scene.zones) do AreaScene(e, D.now, life) end
    DrawWalkLine(D, scene)
    DrawTrail(D, scene)
    DrawAreas(D, scene)
    SetTail(D, scene)
end

-- Dashes from (x1,y1) to (x2,y2), continuing the pattern from phase.
local function Dashes(D, sub, thick, r, g, b, a, dash, gap, phase, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return phase end
    local ux, uy = dx / len, dy / len
    local period = dash + gap
    local pos = 0
    while pos < len do
        local inPat = (phase + pos) % period
        if inPat < dash then
            local stop = math.min(len, pos + (dash - inPat))
            if D.nrun >= C.RUN_BUDGET then return phase + len end
            D.nrun, D.nl = D.nrun + 1, D.nl + 1
            PutLine(D.nl, sub, "BLEND", thick, r, g, b, a,
                x1 + ux * pos, y1 + uy * pos, x1 + ux * stop, y1 + uy * stop)
            pos = stop
        else
            pos = pos + (period - inPat)
        end
    end
    return phase + len
end

local RUN_LOOK = {
    g = { r = 0.55, g = 0.90, b = 1.00, top = 0.90, bottom = 0.15, dash = 7, gap = 5, thick = 1.4, glow = true },
}

-- Flight legs (3.8): dashed, so they read as flight paths and never as
-- roads (roads are the solid lines). Deeper and brighter with the days
-- you've flown them. Only legs flown on about two days show, so the hubs
-- you pass through don't spin a web. Runs of points with the same memory
-- (credited together) that lie within half a pixel of a straight line are
-- one line; grouping looks only at those, never at how faded they are, and
-- the dashes are measured from the start of the leg, so they stay put and
-- only ever fade.
-- Royal blue with a dark casing (Joe's pick, 2026-11-24, from renders over
-- his screenshots): the map art is yellow-gold parchment, so gold or earthy
-- colours vanish and a cool colour reads. Passes: t = thickness in line
-- widths, a = alpha, each from two days to well flown. A line width is a
-- fraction of the map's width: 65% of what was first rendered on both
-- (Joe found both a little thick in game, test6); continents 75% of that
-- again (3.8.3, Joe). simplify, hook and rail are in continent line widths
-- (see DrawLegsFar).
local AIR_LOOK = {
    dash = 10, gap = 9, far = 0.00088, zone = 0.0013,
    simplify = 3.4, smooth = 3, hook = 4.5, rail = 10.7, touch = 3.5, bend = 8, bendcos = 0.5, tiny = 16,
    { t0 = 3.2, t1 = 4.4, a0 = 0.75, a1 = 0.95, r = 0.08, g = 0.05, b = 0.10 },
    { t0 = 1.4, t1 = 2.2, a0 = 0.95, a1 = 1.00, r = 0.25, g = 0.45, b = 1.00 },
}
local function DrawLegs(D, z, far, sx, sy, ox, oy)
    local Strength, lo, look = ns.Flights.Strength, C.AIR_SHOW - C.AIR_FADE, AIR_LOOK
    local thin = D.w * (far and look.far or look.zone)
    local period, np = look.dash + look.gap, #look
    for _, L in ipairs(z.air) do
        local n = #L / 2
        local v, at = {}, { 0 } -- strength, and distance along the leg in pixels
        for i = 1, n do v[i] = Strength(L, i) end
        local function X(i) return ox + L[2 * i - 1] * sx end
        local function Y(i) return -(oy + L[2 * i] * sy) end
        for i = 2, n do at[i] = at[i - 1] + math.sqrt((X(i) - X(i - 1)) ^ 2 + (Y(i) - Y(i - 1)) ^ 2) end
        local function Same(i, j) return L.l[i] == L.l[j] and L.t[i] == L.t[j] end
        local a = 1
        while a < n do
            local sa = math.min(v[a], v[a + 1])
            if sa < lo then
                a = a + 1
            else
                -- grow the line while the next point is credited like this one
                -- and every point so far stays on the straight line
                local b = a + 1
                while b < n and b - a < 40 and Same(b, b + 1) and Same(a, a + 1) and Same(a, b) do
                    local x1, y1, x2, y2 = X(a), Y(a), X(b + 1), Y(b + 1)
                    local dx, dy = x2 - x1, y2 - y1
                    local len = math.sqrt(dx * dx + dy * dy)
                    local ok = true
                    for k = a + 1, b do
                        if len > 0 and math.abs((X(k) - x1) * dy - (Y(k) - y1) * dx) / len > 0.5 then ok = false break end
                    end
                    if not ok then break end
                    b = b + 1
                end
                local s = sa
                for k = a + 1, b - 1 do s = math.min(s, v[k + 1]) end
                local vis = Clamp((s - lo) / C.AIR_FADE)
                local x1, y1 = X(a), Y(a)
                local dx, dy = X(b) - x1, Y(b) - y1
                local len = math.sqrt(dx * dx + dy * dy)
                if vis > 0 and len > 0 then
                    local u = Clamp((s - C.AIR_SHOW) / (C.ROAD_FULL - C.AIR_SHOW))
                    local ux, uy = dx / len, dy / len
                    local pos = 0
                    while pos < len and D.nair + np <= C.AIR_BUDGET do
                        local inPat = (at[a] + pos) % period
                        if inPat < look.dash then
                            local stop = math.min(len, pos + look.dash - inPat)
                            for pi, P in ipairs(look) do -- casing, then the colour over it
                                D.nair, D.nl = D.nair + 1, D.nl + 1
                                PutLine(D.nl, pi - 3, "BLEND", thin * (P.t0 + (P.t1 - P.t0) * u),
                                    P.r, P.g, P.b, (P.a0 + (P.a1 - P.a0) * u) * vis,
                                    x1 + ux * pos, y1 + uy * pos, x1 + ux * stop, y1 + uy * stop)
                            end
                            pos = stop
                        else
                            pos = pos + period - inPat
                        end
                    end
                end
                a = b
            end
        end
    end
end

-- Flight legs on a continent or the world (3.8.3, Joe: "take a bit more
-- artistic liberty; keep the start, path and end as accurate as possible
-- without the dashes looking janky"). At continent scale a leg's points,
-- 30 yards apart, are under a pixel, so dashes drawn along them came out
-- as kinked shapes. Each leg is drawn from its own points alone:
--  * an end that doubles back (over 120 degrees) within a few pixels is dropped: a leg's ends
--    join the leg it left or met, which may not be shown, leaving a hook;
--  * simplified (points off the line by more than `simplify` line widths
--    stay; both ends always), then rounded (`smooth` passes of corner
--    cutting, ends fixed);
--  * dashed from the leg's start, each dash a straight stroke between its
--    two ends on that path;
--  * where two legs run side by side (within `rail` widths, within about
--    30 degrees, either way) the less-flown one gives way, like the trail's
--    older pass. All leg points fade at the same rate, so which is stronger
--    changes only when you fly, never as time passes.
-- The shape depends only on the leg's points, which change only when you
-- fly it, so dashes stay put and only fade. Zone maps are unchanged.
local function AirDP(px, py, i0, i1, tol, keep)
    local x0, y0, x1, y1 = px[i0], py[i0], px[i1], py[i1]
    local dx, dy = x1 - x0, y1 - y0
    local L = math.sqrt(dx * dx + dy * dy)
    local best, bi = 0, nil
    for i = i0 + 1, i1 - 1 do
        local d = L > 0 and math.abs((px[i] - x0) * dy - (py[i] - y0) * dx) / L
            or math.sqrt((px[i] - x0) ^ 2 + (py[i] - y0) ^ 2)
        if d > best then best, bi = d, i end
    end
    if bi and best > tol then
        keep[bi] = true
        AirDP(px, py, i0, bi, tol, keep)
        AirDP(px, py, bi, i1, tol, keep)
    end
end

-- A leg in pixels with its hooked ends dropped: x, y, strength, arc length.
local function AirPoints(L, sx, sy, ox, oy, hook)
    local Strength = ns.Flights.Strength
    local px, py, v = {}, {}, {}
    for i = 1, #L / 2 do px[i], py[i], v[i] = ox + L[2 * i - 1] * sx, -(oy + L[2 * i] * sy), Strength(L, i) end
    local function Hooked(a, b, c)
        local ux, uy, vx, vy = px[b] - px[a], py[b] - py[a], px[c] - px[b], py[c] - py[b]
        local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
        return lu > 0 and lv > 0 and lu < hook and (ux * vx + uy * vy) / (lu * lv) < -0.5
    end
    while #px >= 3 and Hooked(1, 2, 3) do
        table.remove(px, 1) table.remove(py, 1) table.remove(v, 1)
    end
    local n = #px
    while n >= 3 and Hooked(n, n - 1, n - 2) do
        px[n], py[n], v[n], n = nil, nil, nil, n - 1
    end
    local arc = { 0 }
    for i = 2, n do arc[i] = arc[i - 1] + math.sqrt((px[i] - px[i - 1]) ^ 2 + (py[i] - py[i - 1]) ^ 2) end
    return px, py, v, arc, n
end

-- The leg simplified and rounded: x, y and, per point, the arc on the
-- leg as recorded (to read its strength there).
local function AirPath(px, py, arc, n, tol, passes)
    local keep = { [1] = true, [n] = true }
    AirDP(px, py, 1, n, tol, keep)
    local qx, qy, qa = {}, {}, {}
    for i = 1, n do if keep[i] then qx[#qx + 1], qy[#qy + 1], qa[#qa + 1] = px[i], py[i], arc[i] end end
    for _ = 1, passes do
        local m = #qx
        if m < 3 then break end
        local rx, ry, ra = { qx[1] }, { qy[1] }, { qa[1] }
        for i = 1, m - 1 do
            for _, f in ipairs(i == 1 and { 0.75 } or i == m - 1 and { 0.25 } or { 0.25, 0.75 }) do
                rx[#rx + 1], ry[#ry + 1] = qx[i] + (qx[i + 1] - qx[i]) * f, qy[i] + (qy[i + 1] - qy[i]) * f
                ra[#ra + 1] = qa[i] + (qa[i + 1] - qa[i]) * f
            end
        end
        rx[#rx + 1], ry[#ry + 1], ra[#ra + 1] = qx[m], qy[m], qa[m]
        qx, qy, qa = rx, ry, ra
    end
    return qx, qy, qa
end

-- First k with d[k + 1] >= a (binary search over a growing list).
local function AirSeg(d, a)
    local lo, hi = 1, #d - 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if d[mid + 1] < a then lo = mid + 1 else hi = mid end
    end
    return lo
end

local function DrawLegsFar(D, z, sx, sy, ox, oy, queue)
    -- shown from halfway up the zone map's fade-in, drawn whole (one look)
    local lo, look = C.AIR_SHOW - C.AIR_FADE / 2, AIR_LOOK
    local thin = D.w * look.far
    local period = look.dash + look.gap
    for _, L in ipairs(z.air) do
        local px, py, v, arc, n = AirPoints(L, sx, sy, ox, oy, look.hook * thin)
        local wx0, wx1, wy0, wy1 = math.huge, -math.huge, math.huge, -math.huge
        for k = 1, n do
            wx0, wx1, wy0, wy1 = math.min(wx0, px[k]), math.max(wx1, px[k]), math.min(wy0, py[k]), math.max(wy1, py[k])
        end
        -- a leg under `tiny` widths across is a flight circling in to land
        -- or take off: noise at this scale
        if n >= 2 and arc[n] > 0 and math.max(wx1 - wx0, wy1 - wy0) >= look.tiny * thin then
            local qx, qy, qa = AirPath(px, py, arc, n, look.simplify * thin, look.smooth)
            local m, sa = #qx, { 0 }
            for k = 2, m do sa[k] = sa[k - 1] + math.sqrt((qx[k] - qx[k - 1]) ^ 2 + (qy[k] - qy[k - 1]) ^ 2) end
            local total = sa[m]
            local function At(a) -- on the rounded path, and the recorded arc there
                local k = AirSeg(sa, a)
                local f = sa[k + 1] > sa[k] and (a - sa[k]) / (sa[k + 1] - sa[k]) or 0
                return qx[k] + (qx[k + 1] - qx[k]) * f, qy[k] + (qy[k + 1] - qy[k]) * f, qa[k] + (qa[k + 1] - qa[k]) * f
            end
            local function StrengthAt(a)
                local k = AirSeg(arc, a)
                return math.min(v[k], v[k + 1])
            end
            -- cut at sharp bends (over about 60 degrees, judged `bend` widths
            -- either side), at the middle of each bend
            local cuts, w, b0, b1 = { 0 }, look.bend * thin, nil, nil
            for a = w, total - w do
                local x0, y0 = At(a - w)
                local x1, y1 = At(a)
                local x2, y2 = At(a + w)
                local ux, uy, vx, vy = x1 - x0, y1 - y0, x2 - x1, y2 - y1
                local lu, lv = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
                if lu > 0 and lv > 0 and (ux * vx + uy * vy) / (lu * lv) < look.bendcos then
                    b0, b1 = b0 or a, a
                elseif b0 then
                    cuts[#cuts + 1], b0 = (b0 + b1) / 2, nil
                end
            end
            if b0 then cuts[#cuts + 1] = (b0 + b1) / 2 end
            cuts[#cuts + 1] = total
            -- no piece shorter than a dash and its gap: drop a cut beside it
            local merged = true
            while merged and #cuts > 2 do
                merged = false
                for c = 1, #cuts - 1 do
                    if cuts[c + 1] - cuts[c] < period then
                        table.remove(cuts, c + 1 < #cuts and c + 1 or c)
                        merged = true
                        break
                    end
                end
            end
            -- each piece gets whole dashes of the usual length, the gaps share
            -- the rest evenly, with half a gap at both ends: every bend and
            -- every hand-over between legs is one ordinary gap
            for c = 1, #cuts - 1 do
                local c0, len = cuts[c], cuts[c + 1] - cuts[c]
                if len >= look.dash * 0.8 then
                    local nd = math.max(1, math.floor(len / period + 0.5))
                    local per = len / nd
                    local dl = math.min(look.dash, per - 2)
                    for k = 0, nd - 1 do
                        local pos = c0 + k * per + (per - dl) / 2
                        local x1, y1 = At(pos)
                        local _, _, ca = At(pos + dl / 2)
                        local x2, y2 = At(pos + dl)
                        local s = StrengthAt(ca)
                        local len2 = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
                        -- one look: every leg shown is drawn whole, no half-faded
                        -- grey pieces starting and stopping along a route
                        if s >= lo and len2 > 0 then
                            queue[#queue + 1] = { L = L, s = s, vis = 1, thin = thin,
                                edge = (c == 1 and k == 0) or (c == #cuts - 1 and k == nd - 1),
                                u = Clamp((s - C.AIR_SHOW) / (C.ROAD_FULL - C.AIR_SHOW)),
                                x1 = x1, y1 = y1, x2 = x2, y2 = y2, ux = (x2 - x1) / len2, uy = (y2 - y1) / len2 }
                        end
                    end
                end
            end
        end
    end
end

-- How far a point is from a drawn dash.
local function AirGap(px, py, o)
    local dx, dy = o.x2 - o.x1, o.y2 - o.y1
    local L2 = dx * dx + dy * dy
    local t = L2 > 0 and math.max(0, math.min(1, ((px - o.x1) * dx + (py - o.y1) * dy) / L2)) or 0
    return math.sqrt((px - o.x1 - t * dx) ^ 2 + (py - o.y1 - t * dy) ^ 2)
end

-- Draw the queued continent dashes, most-flown first; a dash beside a
-- stronger leg's dash (another leg) gives way.
local function FlushAir(D, queue)
    table.sort(queue, function(a, b) return a.s > b.s end)
    local seen = {}
    for _, k in ipairs(queue) do
        if D.nair + #AIR_LOOK > C.AIR_BUDGET then break end
        local X, Y, r = (k.x1 + k.x2) / 2, (k.y1 + k.y2) / 2, AIR_LOOK.rail * k.thin
        local gx, gy = math.floor(X / r), math.floor(Y / r)
        local beside = false
        for i = -1, 1 do
            for j = -1, 1 do
                for _, o in ipairs(seen[(gx + i) * 65536 + gy + j] or {}) do
                    if o.L ~= k.L and (o.X - X) ^ 2 + (o.Y - Y) ^ 2 < r * r then
                        -- alongside it, or touching it where legs meet (two
                        -- dashes at an angle read as an L or a V, not dashes)
                        -- (only a leg's first or last dash: mid-leg, it's a crossing)
                        local touch = AIR_LOOK.touch * k.thin
                        if math.abs(o.ux * k.ux + o.uy * k.uy) > C.TRAIL_YIELD_COS
                            or (k.edge or o.edge) and math.min(AirGap(k.x1, k.y1, o), AirGap(k.x2, k.y2, o),
                                AirGap(o.x1, o.y1, k), AirGap(o.x2, o.y2, k)) < touch then
                            beside = true
                        end
                    end
                end
            end
        end
        if not beside then
            local key = gx * 65536 + gy
            seen[key] = seen[key] or {}
            table.insert(seen[key], { L = k.L, X = X, Y = Y, ux = k.ux, uy = k.uy, x1 = k.x1, y1 = k.y1, x2 = k.x2, y2 = k.y2, edge = k.edge })
            for pi, P in ipairs(AIR_LOOK) do -- casing, then the colour over it
                D.nair, D.nl = D.nair + 1, D.nl + 1
                PutLine(D.nl, pi - 3, "BLEND", k.thin * (P.t0 + (P.t1 - P.t0) * k.u),
                    P.r, P.g, P.b, (P.a0 + (P.a1 - P.a0) * k.u) * k.vis, k.x1, k.y1, k.x2, k.y2)
            end
        end
    end
end

-- Corpse runs (dashed ice blue with a soft glow), fading along their length
-- over their lifetime; the flight legs you keep flying underneath. Today's
-- flights are no longer drawn on their own (3.8): they're in the legs.
local function DrawRuns(D, scene)
    local w, h, now = D.w, D.h, D.now
    -- on a continent or the world, its own legs (recorded while the game
    -- placed you on the continent map) are drawn the continent way too
    local info = scene.viewed and C_Map.GetMapInfo(scene.viewed)
    local wide = info and info.mapType and info.mapType <= 2
    local queue = {}
    for _, e in ipairs(scene.zones) do
        local p, z = e.p, e.z
        local thin = p.far and w * 0.0011 or w * 0.0020
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        if z.air and ns.Flights then
            if p.far or wide then DrawLegsFar(D, z, sx, sy, ox, oy, queue) else DrawLegs(D, z, p.far, sx, sy, ox, oy) end
        end
        for ri = #z.runs, 1, -1 do -- newest first
            local s = z.runs[ri]
            local look, life = RUN_LOOK[s.k], RunSeconds(s.k)
            local n = #s / 2
            if look and n >= 2 and s.ts and now - s.e < life then
                local phase = 0
                for i = 1, n - 1 do
                    local age = Clamp((now - PointTime(s, i + 1)) / life)
                    if age < 1 then
                        local a = look.bottom + (look.top - look.bottom) * (1 - age) ^ 1.5
                        local x1, y1 = ox + s[2 * i - 1] * sx, -(oy + s[2 * i] * sy)
                        local x2, y2 = ox + s[2 * i + 1] * sx, -(oy + s[2 * i + 2] * sy)
                        if look.glow and D.nrun < C.RUN_BUDGET then
                            D.nrun, D.nl = D.nrun + 1, D.nl + 1
                            PutLine(D.nl, 3, "ADD", thin * 6, 0.35, 0.75, 1.0, 0.16 * a / look.top, x1, y1, x2, y2)
                        end
                        phase = Dashes(D, 4, thin * look.thick, look.r, look.g, look.b, a, look.dash, look.gap,
                            phase, x1, y1, x2, y2)
                    end
                end
            end
        end
    end
    FlushAir(D, queue)
end

-- Replay: the march so far, as one line; returns the head and the time reached.
local function DrawReplay(D, scene, limit)
    local w, h = D.w, D.h
    local remaining, hx, hy, upTo = limit, nil, nil, scene.since
    for _, e in ipairs(scene.strokes) do
        if remaining <= 0 then break end
        local s, p = e.s, e.p
        local n = #s / 2
        local upto = math.min(n, math.ceil(remaining))
        local r, g, b, a, weight = TrailColor(s)
        local thick = (p.far and w * 0.0012 or w * 0.0022) * weight
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        for i = 1, upto - 1 do
            if D.nl >= C.LINE_BUDGET then break end
            D.nl = D.nl + 1
            PutLine(D.nl, 7, "BLEND", thick, r, g, b, a, ox + s[2 * i - 1] * sx, -(oy + s[2 * i] * sy),
                ox + s[2 * i + 1] * sx, -(oy + s[2 * i + 2] * sy))
        end
        hx, hy = ox + s[2 * upto - 1] * sx, -(oy + s[2 * upto] * sy)
        upTo = PointTime(s, upto) or (s.t + (s.e - s.t) * (upto / n))
        remaining = remaining - n
    end
    return hx, hy, upTo
end

-- Crowded pins on continent and world views (3.8.3). Every pin is still
-- drawn, but kills (yours and guildmates') within a pin's width of each other
-- chain into one group, and so do deaths; a group of C.CROWD_MIN or more is
-- one bigger sword or skull; its tooltip says how many. Groups come from the pins'
-- places alone, so a big pin only changes when pins are added or fade out.
-- Big pins that would overlap are pushed apart. Pin(...) draws one pin.
local CROWD = { kill = "kill", skill = "kill", death = "death", sdeath = "death" }
local FLAT = { ox = 0, oy = 0, sx = 1, sy = 1 }
local function Crowd(D, Pin, reach)
    local list = D.crowd
    if not list or #list == 0 then return end
    D.crowd = nil
    -- buckets a reach wide, so each pin only checks its neighbours
    local grid = {}
    local function Key(cx, cy) return cx * 100003 + cy end
    for i, q in ipairs(list) do
        q.cx, q.cy = math.floor(q.x / reach), math.floor(q.y / reach)
        local key = Key(q.cx, q.cy)
        grid[key] = grid[key] or {}
        table.insert(grid[key], i)
    end
    local seen, big = {}, {}
    for i, first in ipairs(list) do
        if not seen[i] then
            seen[i] = true
            local group, stack = {}, { i }
            while #stack > 0 do
                local q = list[table.remove(stack)]
                group[#group + 1] = q
                for gx = q.cx - 1, q.cx + 1 do
                    for gy = q.cy - 1, q.cy + 1 do
                        for _, m in ipairs(grid[Key(gx, gy)] or {}) do
                            local o = list[m]
                            if not seen[m] and CROWD[o.kind] == CROWD[first.kind]
                                and (o.x - q.x) ^ 2 + (o.y - q.y) ^ 2 < reach * reach then
                                seen[m] = true
                                stack[#stack + 1] = m
                            end
                        end
                    end
                end
            end
            if #group < C.CROWD_MIN then
                for _, q in ipairs(group) do
                    Pin(q.kind, q.d, FLAT, q.x / D.w, q.y / D.h, q.tex, q.size, q.r, q.g, q.b, q.a, true)
                end
            else
                local n, sx, sy, guild, size, a = #group, 0, 0, 0, 0, 0
                for _, q in ipairs(group) do
                    sx, sy = sx + q.x, sy + q.y
                    if q.kind == "skill" or q.kind == "sdeath" then guild = guild + 1 end
                    size, a = math.max(size, q.size), math.max(a, q.a)
                end
                -- a little bigger than one pin; the tooltip says how many (Joe, 3.8.3: smaller, no count)
                local grow = math.min(1.5, 1.1 + 0.04 * n)
                big[#big + 1] = { kind = CROWD[first.kind], x = sx / n, y = sy / n, n = n, guild = guild,
                    tex = first.tex, size = size * grow, a = a }
            end
        end
    end
    -- push overlapping big pins apart (twice over, for chains of three)
    table.sort(big, function(p, q) if p.x ~= q.x then return p.x < q.x end return p.y < q.y end)
    for _ = 1, 2 do
        for i = 1, #big do
            for j = i + 1, #big do
                local p, q = big[i], big[j]
                local dx, dy = q.x - p.x, q.y - p.y
                local dist, need = math.sqrt(dx * dx + dy * dy), (p.size + q.size) / 2 / D.k
                if dist < need then
                    if dist < 0.01 then dx, dy, dist = 1, 0, 1 end
                    local push = (need - dist) / 2
                    p.x, p.y = p.x - dx / dist * push, p.y - dy / dist * push
                    q.x, q.y = q.x + dx / dist * push, q.y + dy / dist * push
                end
            end
        end
    end
    for _, g in ipairs(big) do
        local tint = g.guild * 2 > g.n and 0.55 or 1
        Pin("many", g, FLAT, g.x / D.w, g.y / D.h, g.tex, g.size, tint, tint == 1 and 1 or 0.8, 1, g.a, true)
    end
end

-- A score on a continent or world view, stepped past any score already placed.
-- Pins don't move it: they come and fade, and a score that dodged them would
-- jump about (Joe, test5). It's drawn above every pin, on its dark patch.
local function Score(D, x, y, k, d, big)
    D.nb = D.nb + 1
    local f = GetLabel(D.nb)
    f.text:SetFontObject(big and GameFontNormal or GameFontNormalSmall)
    f.text:SetText(("%d : %d"):format(k, d))
    local c = Standing(k, d)
    f.text:SetTextColor(c[1], c[2], c[3])
    local tw, th = (f.text:GetStringWidth() or 30) + 8, big and 18 or 15
    -- nearest clear spot: down a step, up a step, down two, ...
    local y0 = y
    for i = 1, 24 do
        local clear = true
        for _, b in ipairs(D.placed) do
            if math.abs(x - b[1]) < (tw + b[3]) / 2 and math.abs(y - b[2]) < (th + b[4]) / 2 then clear = false break end
        end
        if clear then break end
        local n = math.ceil(i / 2)
        y = y0 + (i % 2 == 1 and n or -n) * th * 0.7
    end
    D.placed[#D.placed + 1] = { x, y, tw, th }
    f.back:SetSize(tw + 16, th + 14)
    f:SetFrameLevel(overlay:GetFrameLevel() + 7)
    f:ClearAllPoints()
    f:SetPoint("CENTER", overlay, "TOPLEFT", x, -y)
    f:Show()
end

local function DrawMarks(D, scene, from, upTo)
    local L, w, h, now = cfg.layers, D.w, D.h, D.now
    local base = PIN_PX * (cfg.iconScale or 100) / 100   -- interface pixels
    local k = MapScale()
    D.k, D.crowd, D.placed = k, {}, {}
    -- placed: drawn by Crowd, which has already grouped it
    local function Pin(kind, d, p, x, y, tex, size, r, g, b, a, placed)
        if not placed and p.far and CROWD[kind] then
            D.crowd[#D.crowd + 1] = { kind = kind, d = d, x = (p.ox + x * p.sx) * w, y = (p.oy + y * p.sy) * h,
                tex = tex, size = size, r = r, g = g, b = b, a = a or 1 }
            return
        end
        if D.np >= C.MARK_BUDGET then return end
        D.np = D.np + 1
        local f = GetPin(D.np)
        f.kind, f.d, f.mapID = kind, d, p.mapID
        f.tex:SetTexture(tex)
        if kind == "sight" or kind == "grudge" then f.tex:SetTexCoord(0, 0.62, 0, 0.62)
        elseif kind == "mob" then f.tex:SetTexCoord(0.5, 0.75, 0.25, 0.5) -- the cross on the raid-marker sheet
        else f.tex:SetTexCoord(0, 1, 0, 1) end
        f.tex:SetDesaturated(kind == "mob")
        f.px = size * 100 / (cfg.iconScale or 100) -- at 100%, for RescalePins
        if kind == "grudge" then
            f.halo:SetSize(size * 1.9 / k, size * 1.9 / k)
            f.halo:Show()
            f.label:SetText(d.short)
            f.label:Show()
        else
            f.halo:Hide()
            f.label:Hide()
        end
        f.tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        -- Stack by kind, not draw order: sightings at the bottom, kills and
        -- deaths above them, grudges on top.
        f:SetFrameLevel(overlay:GetFrameLevel() + (PIN_LEVEL[kind] or 2))
        f:SetSize(size / k, size / k)
        At(f, p, x, y, w, h)
        f:Show()
        return f
    end
    local reach = base * 1.4 / k -- about a pin and a half, in map units
    if L.marks then
        for _, e in ipairs(scene.zones) do
            for _, m in ipairs(e.z.marks) do
                -- faded pins are hidden, not deleted (a replay shows them all)
                local f = D.replay and 1 or ns.MarkFade(m, now)
                if f >= 0.03 and m[3] >= from and m[3] <= upTo then
                    if m[4] == "kill" then
                        Pin("kill", m, e.p, m[1], m[2], C.TEX_BLADES, base, 1, 1, 1, f)
                    elseif not m.pvp then -- mobs and falls: a small grey cross, not a skull (3.7.5)
                        Pin("mob", m, e.p, m[1], m[2], C.TEX_RAID, base * 0.7, 0.72, 0.72, 0.72, f)
                    elseif m.av then
                        Pin("death", m, e.p, m[1], m[2], C.TEX_SKULL, base, 1, 0.82, 0.2, f)
                    else
                        Pin("death", m, e.p, m[1], m[2], C.TEX_SKULL, base, 1, 1, 1, f)
                    end
                end
            end
        end
    end
    if D.replay then return Crowd(D, Pin, reach) end
    if L.sightings then
        for _, s in ipairs(recentSight) do
            local p = Proj(scene, s.mapID)
            if p and now - s.t <= C.SIGHT_LIVE then
                Pin("sight", s, p, s.x, s.y, foe.crest, base * 1.3, 1, 1, 1, 1 - 0.6 * (now - s.t) / C.SIGHT_LIVE)
            end
        end
    end
    if cfg.grudge.map then
        for _, g in ipairs(ns.Grudge.Live()) do
            local p = Proj(scene, g.mapID)
            if p then Pin("grudge", g, p, g.x, g.y, foe.crest, base * 1.3, 1, 1, 1, 1 - 0.5 * (now - g.t) / C.GRUDGE_SEEN) end
        end
    end
    if L.shared then
        for _, s in ipairs(shared) do
            local p = Proj(scene, s.mapID)
            if p and s.expire >= now and s.kind == "S" then
                Pin("sight", s, p, s.x, s.y, foe.crest, base * 1.3, 1, 1, 1, 0.85 - 0.45 * math.min(1, (now - s.t) / C.SIGHT_LIVE))
            end
        end
        -- guildmates' kills and deaths: full for 2 hours, then fading over 3 days
        for _, e in ipairs(scene.zones) do
            for _, g in ipairs(e.z.gmarks or {}) do
                local f = ns.GuildFade(g, now)
                if f >= 0.03 then
                    if g.kind == "K" then
                        Pin("skill", g, e.p, g.x, g.y, C.TEX_BLADES, base * 1.15, 0.55, 0.8, 1, f)
                    else
                        Pin("sdeath", g, e.p, g.x, g.y, C.TEX_SKULL, base * 1.1, 0.55, 0.8, 1, f)
                    end
                end
            end
        end
    end
    Crowd(D, Pin, reach)
    -- Scores (3.8.3). A zone's own map: in its top-left corner (MapButton.lua).
    -- A continent: each zone with a fight, small, at its centre. The world
    -- (both continents): one score per continent instead.
    -- no viewed map: the empty scene drawn while hidden or in a battleground.
    -- GetMapInfo(nil) raises in the client, which left the last drawing up.
    if not L.marks or not scene.viewed then return end
    local info = C_Map.GetMapInfo(scene.viewed)
    if info and info.mapType and info.mapType <= 1 then
        for _, c in ipairs(C.CONTINENTS) do
            local x0, x1, y0, y1 = Projection(c, scene.viewed)
            if x0 then
                local kills, deaths = 0, 0
                for _, e in ipairs(scene.zones) do
                    if e.p.mapID == c or Projection(e.p.mapID, c) then
                        kills, deaths = kills + e.z.kills, deaths + e.z.pdeaths
                    end
                end
                -- below the middle, clear of the continent's printed name
                if kills + deaths > 0 then Score(D, (x0 + x1) / 2 * w, (y0 + 0.62 * (y1 - y0)) * h, kills, deaths, true) end
            end
        end
        return
    end
    local far = {}
    for _, e in ipairs(scene.zones) do
        local z = e.z
        if e.p.mapID == scene.viewed and not e.p.far and (info and info.mapType or 3) >= 3 and z.kills + z.pdeaths >= 1 then
            D.standing = z
        elseif e.p.far and z.kills + z.pdeaths >= 1 then
            far[#far + 1] = e
        end
    end
    -- the most fought-over zone keeps its centre; neighbours step down past it
    table.sort(far, function(a, b)
        local na, nb = a.z.kills + a.z.pdeaths, b.z.kills + b.z.pdeaths
        if na ~= nb then return na > nb end
        return a.p.mapID < b.p.mapID
    end)
    for _, e in ipairs(far) do
        Score(D, (e.p.ox + 0.5 * e.p.sx) * w, (e.p.oy + 0.5 * e.p.sy) * h, e.z.kills, e.z.pdeaths)
    end
end

-- Shimmer: a slow band of warm light gliding over worn gold, and glints
-- twinkling. Runs only while the map is open (the overlay is hidden otherwise).
local function Animate(self, elapsed)
    self.acc = (self.acc or 0) + elapsed
    if self.acc < 0.066 then return end
    self.acc = 0
    local t = GetTime()
    local c = (t % 7) / 7 * 1.8 - 0.3
    for _, e in ipairs(shimmer) do
        local d = (e.u - c) / 0.08
        local k = e.worn * math.exp(-d * d)
        if k > 0.01 or e.lit then
            e.l:SetColorTexture(Lerp(e.r, 1.00, k), Lerp(e.g, 0.88, k), Lerp(e.b, 0.48, k), 1)
            e.lit = k > 0.01
        end
    end
    for _, g in ipairs(twinkle) do
        local s = 0.5 + 0.5 * math.sin(t * 1.7 + g.phase)
        g.tex:SetAlpha(g.base * s * s * s)
    end
end

local EMPTY = { proj = {}, zones = {} }

-- limit: number of trail points to draw (replay); nil = live view.
local function Draw(scene, limit)
    local D = { w = overlay:GetWidth(), h = overlay:GetHeight(), now = time(), replay = limit and true,
        nl = 0, nd = 0, ng = 0, np = 0, nb = 0, ns = 0, nr = 0, ngl = 0, nrun = 0, ndash = 0, ntag = 0, nair = 0 }
    local L = cfg.layers
    tail.stroke, tail.p = nil, nil
    for i = #shimmer, 1, -1 do shimmer[i] = nil end
    for i = #twinkle, 1, -1 do twinkle[i] = nil end

    DrawHaze(D, scene)
    local hx, hy
    local from, upTo = 0, math.huge -- time window for marks
    if limit then
        hx, hy, upTo = DrawReplay(D, scene, limit)
        from = scene.since
    else
        if L.roads then DrawGround(D, scene) end
        if L.runs then DrawRuns(D, scene) end
        if L.recent then DrawToday(D, scene) end
    end
    DrawMarks(D, scene, from, upTo)
    if ns.ZoneStanding then ns.ZoneStanding(D.standing) end

    for i = D.nl + 1, #lines do lines[i]:Hide() end
    for i = D.nd + 1, #dots do dots[i]:Hide() end
    for i = D.ng + 1, #glows do glows[i]:Hide() end
    for i = D.np + 1, #pins do pins[i]:Hide() end
    activePins = D.np
    for i = D.nb + 1, #labels do labels[i]:Hide() end
    for i = D.ntag + 1, #tags do tags[i]:Hide() end
    activeTags = D.ntag
    for i = D.ns + 1, #steps do steps[i]:Hide() end
    for i = D.nr + 1, #rims do rims[i]:Hide() end
    for i = D.ngl + 1, #glints do glints[i]:Hide() end
    overlay:SetScript("OnUpdate", (#shimmer > 0 or #twinkle > 0) and Animate or nil)
    UpdateTail()

    if hx then
        head:SetSize(D.w * 0.035, D.w * 0.035)
        head:ClearAllPoints()
        head:SetPoint("CENTER", overlay, "TOPLEFT", hx, hy)
        head:Show()
    else
        head:Hide()
    end
    return D
end

local function Redraw()
    if ns.MapButtonRefresh then ns.MapButtonRefresh() end
    if not overlay or not WorldMapFrame:IsShown() or replay.active then return end
    S.dirty, S.lastDraw = false, GetTime()
    local viewed = WorldMapFrame:GetMapID()
    if cfg.shown and not S.inInstance and viewed and overlay:GetWidth() > 0 then
        return Draw(BuildScene(viewed))
    else
        return Draw(EMPTY)
    end
end

---------------------------------------------------------------------------
-- Replay
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")

local function StopReplay()
    replay.active = false
    driver:SetScript("OnUpdate", nil)
    Redraw()
end

local function ReplayFrame(_, elapsed)
    if not WorldMapFrame:IsShown() then return StopReplay() end
    replay.clock = replay.clock + elapsed
    replay.acc = replay.acc + elapsed
    if replay.acc < 0.04 then return end
    replay.acc = 0
    local viewed = WorldMapFrame:GetMapID()
    if viewed ~= replay.viewed then
        replay.viewed = viewed
        replay.scene = viewed and BuildScene(viewed, replay.since) or nil
    end
    local progress = replay.clock / C.REPLAY_SECONDS
    if progress >= 1 + 3 / C.REPLAY_SECONDS then return StopReplay() end -- hold the last frame 3s
    if replay.scene and replay.scene.points >= 2 then
        Draw(replay.scene, math.max(1, math.min(1, progress) * replay.scene.points))
    else
        Draw(EMPTY)
    end
end

local function StartReplay(hours)
    if not overlay then return end
    hours = math.min(C.KEEP_HOURS, math.max(1, hours or 6))
    local mapID = C_Map.GetBestMapForUnit("player")
    if not WorldMapFrame:IsShown() then
        if InCombatLockdown() then Print("open your map first; I can't do that for you in combat.") return end
        ToggleWorldMap()
    end
    if mapID and not Secret(mapID) and not InCombatLockdown() then WorldMapFrame:SetMapID(mapID) end
    if cur.stroke then Simplify(cur.stroke) end

    replay.since = time() - hours * 3600
    replay.viewed = WorldMapFrame:GetMapID()
    replay.scene = replay.viewed and BuildScene(replay.viewed, replay.since) or nil
    if not replay.scene or replay.scene.points < 2 then
        Print(("nothing recorded on this map in the last %d hours."):format(hours))
        return
    end
    Print(("replaying the last %d hours. Zoom out to follow it across zones."):format(hours))
    replay.active, replay.clock, replay.acc = true, 0, 1
    driver:SetScript("OnUpdate", ReplayFrame)
end

---------------------------------------------------------------------------
-- World map hookup
---------------------------------------------------------------------------

local function SetupMap()
    if overlay or not WorldMapFrame then return end
    local canvas = WorldMapFrame:GetCanvas()
    overlay = CreateFrame("Frame", "WarpathOverlay", canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 2500)
    overlay:SetScript("OnSizeChanged", function() S.dirty = true end)
    head = overlay:CreateTexture(nil, "OVERLAY")
    head:SetTexture(C.TEX_GLOW)
    head:SetBlendMode("ADD")
    head:SetVertexColor(1, 0.9, 0.5)
    head:Hide()
    tail.line = overlay:CreateLine(nil, "ARTWORK")
    tail.line:SetDrawLayer("ARTWORK", 7)
    tail.line:Hide()
    -- keep pins steady while the map zooms or is rescaled; keep the trail
    -- joined to you
    local watcher = CreateFrame("Frame", nil, overlay)
    watcher.acc, watcher.k = 0, 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local k = MapScale()
        if math.abs(k - self.k) > 0.001 then self.k = k RescalePins() end
        UpdateTail()
    end)
    WorldMapFrame:HookScript("OnShow", Redraw)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Redraw)
    if ns.SetupMapButton then ns.SetupMapButton() end
end

-- Shared with the other files.
ns.Redraw = Redraw
ns.UpdateTail = UpdateTail
ns.RescalePins = RescalePins
ns.SetupMap = SetupMap
ns.StartReplay = StartReplay
ns.StopReplay = StopReplay
ns.replay = replay
