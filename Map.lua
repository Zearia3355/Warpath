-- Warpath: Map
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Ago, CellXY, Long, Print, Recent, Secret = ns.Ago, ns.CellXY, ns.Long, ns.Print, ns.Recent, ns.Secret
local Simplify, StepLook, Waypoint, cur, recentSight, shared = ns.Simplify, ns.StepLook, ns.Waypoint, ns.cur, ns.recentSight, ns.shared
local Fields, PointTime, RunSeconds, ClassColor = ns.Fields, ns.PointTime, ns.RunSeconds, ns.ClassColor

local db, gdb, cfg, faction, foe
ns.OnBind(function()
    db, gdb, cfg, faction, foe = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe
end)

local overlay, head
local lines, dots, glows, pins, labels, steps, rims, glints = {}, {}, {}, {}, {}, {}, {}, {}
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

-- The same hue at full saturation (Horde red -> pure red, Alliance blue -> pure blue).
local function Saturate(r, g, b)
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    if hi - lo < 0.01 then return r, g, b end
    local k = hi / (hi - lo)
    return (r - lo) * k, (g - lo) * k, (b - lo) * k
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

local function GetStep(pool, i, sub)
    local d = pool[i]
    if not d then
        d = overlay:CreateTexture(nil, "ARTWORK", nil, sub)
        d:SetTexture(C.TEX_STEP)
        d:SetBlendMode("BLEND")
        pool[i] = d
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
    if self.kind == "death" then
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
            GameTooltip:AddLine("No enemy player seen; not counted", 0.6, 0.6, 0.6)
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
    elseif self.kind == "skill" then
        GameTooltip:AddLine(d.from .. " scored a kill here", 0.6, 0.8, 1)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    else -- shared death
        GameTooltip:AddLine(d.from .. " was killed here", 1, 0.5, 0.4)
        GameTooltip:AddLine(Ago(d.t), 0.8, 0.8, 0.8)
    end
    GameTooltip:AddLine("Click to set a waypoint", 0.1, 1, 0.1)
    GameTooltip:Show()
end

local function PinClick(self, button)
    if button ~= "LeftButton" then return end
    local d = self.d
    Waypoint(self.mapID, d[1] or d.x, d[2] or d.y,
        self.kind == "death" and "where you fell" or self.kind == "kill" and "your kill"
        or self.kind == "sight" and "enemy sighting" or self.kind == "skill" and "an ally's kill"
        or self.kind == "grudge" and ("where you saw " .. (d.short or "a grudge")) or "a fallen ally")
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
        f:SetScript("OnEnter", PinEnter)
        f:SetScript("OnLeave", GameTooltip_Hide)
        f:SetScript("OnMouseUp", PinClick)
        pins[i] = f
    end
    return f
end

local function GetLabel(i)
    local f = labels[i]
    if not f then
        f = CreateFrame("Frame", nil, overlay)
        f:SetSize(70, 20)
        f.crest = f:CreateTexture(nil, "OVERLAY")
        f.crest:SetSize(22, 22)
        f.crest:SetPoint("LEFT")
        f.crest:SetTexCoord(0, 0.62, 0, 0.62)
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.text:SetPoint("LEFT", f.crest, "RIGHT", 1, 0)
        labels[i] = f
    end
    return f
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
-- deepening from a faint rust to dark red as fights pile up.
local function DrawHaze(D, scene)
    if not cfg.layers.battle then return end
    local w, h = D.w, D.h
    local span = C.BATTLE_FULL - C.BATTLE_MIN
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        local cell = p.sx * w / C.SW
        for c, rec in pairs(z.battle) do
            local v = Long(rec)
            if v >= C.BATTLE_MIN then
                if D.nd >= C.DOT_BUDGET then break end
                local t = Clamp((v - C.BATTLE_MIN) / span)
                D.nd = D.nd + 1
                local d = GetDot(D.nd)
                local x, y = CellXY(c, C.SW, C.SH)
                d:SetVertexColor(Lerp(0.62, 0.42, t), Lerp(0.20, 0.03, t), Lerp(0.09, 0.02, t))
                d:SetAlpha(0.07 + 0.25 * t)
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
local function RoadSegment(D, g, wear, worn, alpha, thin, x1, y1, x2, y2)
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

local function DrawGround(D, scene)
    local L, w, h, now = cfg.layers, D.w, D.h, D.now
    local gold = db.roadMin
    local silver = gold * C.SILVER_SHARE
    local faint = silver * 0.8           -- roads fade in before silver
    local gStart, gEnd = silver * 1.2, gold * 2 -- the gilding band
    local full = math.max(C.ROAD_FULL, gEnd + 4)
    local roadCap = C.LINE_BUDGET - C.ROAD_RESERVE - 3
    local fr, fg, fb = faction.r, faction.g, faction.b
    local vr, vg, vb = Saturate(fr, fg, fb)
    local shine = cfg.shimmer
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        local thin = p.far and w * 0.0011 or w * 0.0020
        local spacing = math.max(5, thin * 4.5)
        local dot = math.max(2, thin * 1.5)
        local candidates = {}
        for edge, rec in pairs(z.road) do
            local long = L.roads and Long(rec, now) or 0
            local recent = L.recent and Recent(rec, now) or 0
            if long >= faint or recent >= C.RECENT_MIN then
                local a, b = math.floor(edge / 10000), edge % 10000
                local ax, ay = z.cx[a], z.cy[a]
                local bx, by = z.cx[b], z.cy[b]
                if not ax then ax, ay = CellXY(a, C.GW, C.GH) end
                if not bx then bx, by = CellXY(b, C.GW, C.GH) end
                local x1, y1, x2, y2 = ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy)
                if long >= faint and D.nl < roadCap then
                    local g = Clamp((long - gStart) / (gEnd - gStart))
                    local wear = Clamp((long - silver) / (full - silver))
                    local worn = long >= gEnd and Clamp((long - gEnd) / (full - gEnd)) or 0
                    local alpha = long >= silver and 1 or 0.25 + 0.75 * (long - faint) / (silver - faint)
                    local stripe, r, gg, bb = RoadSegment(D, g, wear, worn, alpha, thin, x1, y1, x2, y2)
                    if stripe and worn > 0.05 and shine then
                        shimmer[#shimmer + 1] = { l = stripe, u = (ax + bx) * 0.5 + (ay + by) * 0.3,
                            worn = worn, r = r, g = gg, b = bb }
                        if worn > 0.6 then
                            candidates[#candidates + 1] = { x = (ax + bx) / 2, y = (ay + by) / 2, worn = worn }
                        end
                    end
                end
                if recent >= C.RECENT_MIN then
                    -- Footsteps: vivid faction colour with a dark rim when fresh.
                    local alpha, scale, vivid = StepLook(rec, now)
                    local r, g, b = Lerp(fr, vr, vivid), Lerp(fg, vg, vivid), Lerp(fb, vb, vivid)
                    alpha = alpha + (1 - alpha) * vivid
                    local size = dot * scale
                    local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
                    local n = math.max(1, math.floor(len / spacing + 0.5))
                    for k = 0, n - 1 do
                        if D.ns >= C.STEP_BUDGET then break end
                        local t = (k + 0.5) / n
                        local px, py = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
                        D.ns = D.ns + 1
                        local d = GetStep(steps, D.ns, 6)
                        d:SetVertexColor(r, g, b)
                        d:SetAlpha(alpha)
                        d:SetSize(size, size)
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
                        d:Show()
                        if vivid > 0.02 and D.nr < C.STEP_BUDGET then
                            D.nr = D.nr + 1
                            local rim = GetStep(rims, D.nr, 5)
                            rim:SetVertexColor(0.03, 0.02, 0.02)
                            rim:SetAlpha(0.7 * vivid)
                            rim:SetSize(size + 2, size + 2)
                            rim:ClearAllPoints()
                            rim:SetPoint("CENTER", overlay, "TOPLEFT", px, py)
                            rim:Show()
                        end
                    end
                end
            end
        end
        -- Amber glints on the most worn roads, sparse.
        if #candidates > 0 then
            table.sort(candidates, function(a, b) return a.worn > b.worn end)
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

-- The solid line: your last five minutes, each piece shaded by its own age.
-- Trail recorded before 3.4 has no point times and shows as footsteps only.
local function DrawWalkLine(D, scene)
    local w, h, now = D.w, D.h, D.now
    local cutoff = now - C.FRESH_SECONDS
    for _, e in ipairs(scene.zones) do
        local p, strokes = e.p, e.z.strokes
        local thick = p.far and w * 0.0012 or w * 0.0022
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
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
                    if t1 < cutoff and t2 > t1 then -- trim the piece that is older than five minutes
                        local k = (cutoff - t1) / (t2 - t1)
                        ax, ay = ax + (bx - ax) * k, ay + (by - ay) * k
                    end
                    local age = Clamp((now - (t1 + t2) / 2) / C.FRESH_SECONDS)
                    D.nl = D.nl + 1
                    PutLine(D.nl, 7, "BLEND", thick, faction.r, faction.g, faction.b, 0.95 - 0.55 * age,
                        ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy))
                end
            end
        end
    end
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
    -- today's flights: thin, softer gold, fading out over their lifetime
    f = { r = 0.96, g = 0.84, b = 0.55, top = 0.45, bottom = 0.08, dash = 10, gap = 9, thick = 0.85 },
}

-- Corpse runs (dashed ice blue with a soft glow) and flights (long gold
-- dashes), fading along their length over their lifetime; flight routes you
-- keep taking underneath.
local function DrawRuns(D, scene)
    local w, h, now = D.w, D.h, D.now
    local bar = C.ROUTE_MIN
    for _, e in ipairs(scene.zones) do
        local p, z = e.p, e.z
        local thin = p.far and w * 0.0011 or w * 0.0020
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        local f = RUN_LOOK.f
        for _, r in ipairs(z.routes) do
            local long = Long(r, now)
            -- A route appears at ROUTE_MIN but only goes below ROUTE_OFF, fading
            -- out in between, so a few days away never makes it blink out.
            if long >= bar then r.on = true elseif long < C.ROUTE_OFF then r.on = nil end
            if r.on then
                -- Quiet on purpose: short, sparse, muted dashes that stay well
                -- under roads and today's flights.
                local use = Clamp((long - bar) / (C.ROAD_FULL - bar))
                local a = (0.14 + 0.26 * use) * Clamp((long - C.ROUTE_OFF) / (bar - C.ROUTE_OFF))
                local phase = 0
                for i = 1, #r / 2 - 1 do
                    phase = Dashes(D, 3, thin * (0.8 + 0.5 * use), 0.86, 0.74, 0.50, a,
                        6, 10, phase, ox + r[2 * i - 1] * sx, -(oy + r[2 * i] * sy),
                        ox + r[2 * i + 1] * sx, -(oy + r[2 * i + 2] * sy))
                end
            end
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

local function DrawMarks(D, scene, from, upTo)
    local L, w, h, now = cfg.layers, D.w, D.h, D.now
    local base = math.max(14, w * 0.018)
    local function Pin(kind, d, p, x, y, tex, size, r, g, b, a)
        if D.np >= C.MARK_BUDGET then return end
        D.np = D.np + 1
        local f = GetPin(D.np)
        f.kind, f.d, f.mapID = kind, d, p.mapID
        f.tex:SetTexture(tex)
        if kind == "sight" or kind == "grudge" then f.tex:SetTexCoord(0, 0.62, 0, 0.62) else f.tex:SetTexCoord(0, 1, 0, 1) end
        if kind == "grudge" then
            f.halo:SetSize(size * 1.9, size * 1.9)
            f.halo:Show()
            f.label:SetText(d.short)
            f.label:Show()
        else
            f.halo:Hide()
            f.label:Hide()
        end
        f.tex:SetVertexColor(r or 1, g or 1, b or 1, a or 1)
        f:SetSize(size, size)
        At(f, p, x, y, w, h)
        f:Show()
    end
    if L.marks then
        for _, e in ipairs(scene.zones) do
            for _, m in ipairs(e.z.marks) do
                if m[3] >= from and m[3] <= upTo then
                    if m[4] == "kill" then
                        Pin("kill", m, e.p, m[1], m[2], C.TEX_BLADES, base)
                    elseif not m.pvp then
                        Pin("death", m, e.p, m[1], m[2], C.TEX_SKULL, base * 0.7, 0.6, 0.6, 0.6, 0.5)
                    elseif m.av then
                        Pin("death", m, e.p, m[1], m[2], C.TEX_SKULL, base, 1, 0.82, 0.2)
                    else
                        Pin("death", m, e.p, m[1], m[2], C.TEX_SKULL, base)
                    end
                end
            end
        end
    end
    if D.replay then return end
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
            if p and s.expire >= now then
                if s.kind == "S" then
                    Pin("sight", s, p, s.x, s.y, foe.crest, base * 1.3, 1, 1, 1, 0.85)
                elseif s.kind == "K" then
                    Pin("skill", s, p, s.x, s.y, C.TEX_BLADES, base * 0.9, 0.6, 0.8, 1, 0.9)
                else
                    Pin("sdeath", s, p, s.x, s.y, C.TEX_SKULL, base, 0.6, 0.8, 1, 0.9)
                end
            end
        end
    end
    -- Zone standing, on continent-scale views.
    if L.marks then
        for _, e in ipairs(scene.zones) do
            local z = e.z
            if e.p.far and z.kills + z.pdeaths >= 3 then
                D.nb = D.nb + 1
                local f = GetLabel(D.nb)
                local c = z.kills >= z.pdeaths and faction or foe
                f.crest:SetTexture(c.crest)
                f.text:SetText(("%d : %d"):format(z.kills, z.pdeaths))
                f.text:SetTextColor(c.r, c.g, c.b)
                At(f, e.p, 0.5, 0.5, w, h)
                f:Show()
            end
        end
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
        nl = 0, nd = 0, ng = 0, np = 0, nb = 0, ns = 0, nr = 0, ngl = 0, nrun = 0 }
    local L = cfg.layers
    for i = #shimmer, 1, -1 do shimmer[i] = nil end
    for i = #twinkle, 1, -1 do twinkle[i] = nil end

    DrawHaze(D, scene)
    local hx, hy
    local from, upTo = 0, math.huge -- time window for marks
    if limit then
        hx, hy, upTo = DrawReplay(D, scene, limit)
        from = scene.since
    else
        if L.roads or L.recent then DrawGround(D, scene) end
        if L.runs then DrawRuns(D, scene) end
        if L.recent then DrawWalkLine(D, scene) end
    end
    DrawMarks(D, scene, from, upTo)

    for i = D.nl + 1, #lines do lines[i]:Hide() end
    for i = D.nd + 1, #dots do dots[i]:Hide() end
    for i = D.ng + 1, #glows do glows[i]:Hide() end
    for i = D.np + 1, #pins do pins[i]:Hide() end
    for i = D.nb + 1, #labels do labels[i]:Hide() end
    for i = D.ns + 1, #steps do steps[i]:Hide() end
    for i = D.nr + 1, #rims do rims[i]:Hide() end
    for i = D.ngl + 1, #glints do glints[i]:Hide() end
    overlay:SetScript("OnUpdate", (#shimmer > 0 or #twinkle > 0) and Animate or nil)

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
    WorldMapFrame:HookScript("OnShow", Redraw)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Redraw)
    if ns.SetupMapButton then ns.SetupMapButton() end
end

-- Shared with the other files.
ns.Redraw = Redraw
ns.SetupMap = SetupMap
ns.StartReplay = StartReplay
ns.StopReplay = StopReplay
ns.replay = replay
