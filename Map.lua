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

local PIN_LEVEL = { sight = 1, mob = 2, kill = 3, death = 3, skill = 4, sdeath = 4, grudge = 6 }

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

local function DrawGround(D, scene)
    local L, w, h, now = cfg.layers, D.w, D.h, D.now
    if not L.roads then return end
    local gold = db.roadMin
    local silver = gold * C.SILVER_SHARE
    local faint = silver * 0.8           -- roads fade in before silver
    local gStart, gEnd = silver * 1.2, gold * 2 -- the gilding band
    local full = math.max(C.ROAD_FULL, gEnd + 4)
    local roadCap = C.LINE_BUDGET - C.ROAD_RESERVE - 3
    local shine = cfg.shimmer
    for _, e in ipairs(scene.zones) do
        local z, p = e.z, e.p
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        local thin = p.far and w * 0.0011 or w * 0.0020
        local candidates = {}
        local chains, fade, adj = RoadChains(z, faint, gold)
        if C.ROAD_THREAD > 0 then Lynchpins(chains, adj) end
        -- How much of a stretch of this strength shows: all of it from
        -- silver, fading all the way out by the time it stops being drawn
        -- (3.7.12; it used to stop at a quarter and then vanish in one step).
        local function Seen(s) return s >= silver and 1 or s > faint and (s - faint) / (silver - faint) or 0 end
        -- One piece of a chain, from map point (ax, ay) to (bx, by), at its
        -- strength as of the last visit (and what holds it, if a lynchpin);
        -- drawn at that faded by the time since.
        local function Piece(long, hold, ax, ay, bx, by)
            long = long * fade
            local alpha = math.max(Seen(long), C.ROAD_THREAD * Seen((hold or 0) * fade))
            if D.nl >= roadCap or alpha <= 0 then return end
            local x1, y1, x2, y2 = ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy)
            local g = Clamp((long - gStart) / (gEnd - gStart))
            local wear = Clamp((long - silver) / (full - silver))
            local worn = long >= gEnd and Clamp((long - gEnd) / (full - gEnd)) or 0
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
            local lx, ly
            for i = 1, n do
                local sx0, sy0 = px[i], py[i]
                if i > 1 then sx0, sy0 = 0.75 * px[i] + 0.25 * px[i + 1], 0.75 * py[i] + 0.25 * py[i + 1] end
                local ex, ey = px[i + 1], py[i + 1]
                if i < n then ex, ey = 0.25 * px[i] + 0.75 * px[i + 1], 0.25 * py[i] + 0.75 * py[i + 1] end
                if lx then
                    Piece((vals[i - 1] + vals[i]) / 2, math.min(hold[i - 1] or 0, hold[i] or 0), lx, ly, sx0, sy0)
                end
                Piece(vals[i], hold[i], sx0, sy0, ex, ey)
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

-- The line: your last 5 minutes, solid (3.7.6). After that the trail
-- breaks into dashes (DrawTrail). Trail recorded before 3.4 has no point
-- times and isn't drawn.
local function DrawWalkLine(D, scene)
    local w, h, now = D.w, D.h, D.now
    local cutoff = now - C.LINE_SOLID
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
                    if t1 < cutoff and t2 > t1 then -- trim the piece older than the line
                        local k = (cutoff - t1) / (t2 - t1)
                        ax, ay = ax + (bx - ax) * k, ay + (by - ay) * k
                    end
                    D.nl = D.nl + 1
                    PutLine(D.nl, 7, "BLEND", thick, faction.r, faction.g, faction.b, 0.95,
                        ox + ax * sx, -(oy + ay * sy), ox + bx * sx, -(oy + by * sy))
                end
            end
        end
    end
end

-- How a dash looks at a given age: how much of its slot it fills, its
-- thickness and its opacity. Long dashes where the solid line hands over,
-- shortening, thinning and fading evenly to nothing at the trail's end, so
-- the oldest part is the faintest (3.7.7: over the trail length you pick).
local function DashLook(age, life)
    local u = Clamp((age - C.LINE_SOLID) / math.max(1, life - C.LINE_SOLID))
    return Lerp(0.85, 0.5, Smooth(u)), Lerp(1, 0.55, u), 0.95 * (1 - u)
end

-- Today's trail after the solid line (3.7.6): from 5 minutes old it breaks
-- into dashes that fade out over the trail length (3.7.7), then it's gone. Each dash has a fixed
-- place on the ground, measured along the stroke from where it began (s.d),
-- so walking on and time passing never move a dash: it only shortens and
-- fades where it is.
local function DrawTrail(D, scene)
    local w, h, now = D.w, D.h, D.now
    local life = TrailSeconds()
    local oldest = now - life
    local fr, fg, fb = faction.r, faction.g, faction.b
    for _, e in ipairs(scene.zones) do
        local p, strokes = e.p, e.z.strokes
        local line = p.far and w * 0.0012 or w * 0.0022
        local thin = p.far and w * 0.0011 or w * 0.0020
        local sx, sy, ox, oy = p.sx * w, p.sy * h, p.ox * w, p.oy * h
        local slot = C.DASH_PERIOD * thin / sx -- one dash slot, in map widths
        -- the point at distance a along stroke s, on segment i
        local function Along(s, d, i, a)
            local f = d[i + 1] > d[i] and (a - d[i]) / (d[i + 1] - d[i]) or 0
            return s[2 * i - 1] + (s[2 * i + 1] - s[2 * i - 1]) * f, s[2 * i] + (s[2 * i + 2] - s[2 * i]) * f, f
        end
        for si = #strokes, 1, -1 do -- newest first
            local s = strokes[si]
            if s.e < oldest or D.ndash >= C.DASH_BUDGET then break end
            local n = #s / 2
            if s.ts and n >= 2 then
                local d = StrokeArc(s)
                local i = n - 1
                for k = math.floor(d[n] / slot), 0, -1 do
                    local mid = (k + 0.5) * slot
                    while i > 1 and d[i] > mid do i = i - 1 end
                    if mid <= d[n] then
                        local _, _, f = Along(s, d, i, mid)
                        local t1 = PointTime(s, i)
                        local age = now - (t1 + (PointTime(s, i + 1) - t1) * f)
                        if age >= life or D.ndash >= C.DASH_BUDGET then break end
                        if age >= C.LINE_SOLID then
                            local fill, tk, alpha = DashLook(age, life)
                            -- the dash, from mid - half to mid + half, following the path's bends
                            local half = fill * slot / 2
                            local a0, a1 = math.max(0, mid - half), math.min(d[n], mid + half)
                            local j = i
                            while j > 1 and d[j] > a0 do j = j - 1 end
                            local x0, y0 = Along(s, d, j, a0)
                            while j <= n - 1 and D.ndash < C.DASH_BUDGET do
                                local stop = math.min(a1, d[j + 1])
                                local x1, y1 = Along(s, d, j, stop)
                                D.ndash, D.nl = D.ndash + 1, D.nl + 1
                                PutLine(D.nl, 6, "BLEND", line * tk, fr, fg, fb, alpha,
                                    ox + x0 * sx, -(oy + y0 * sy), ox + x1 * sx, -(oy + y1 * sy))
                                if stop >= a1 then break end
                                x0, y0, j = x1, y1, j + 1
                            end
                        end
                    end
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
    local base = PIN_PX * (cfg.iconScale or 100) / 100   -- interface pixels
    local k = MapScale()
    local function Pin(kind, d, p, x, y, tex, size, r, g, b, a)
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
    end
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
        nl = 0, nd = 0, ng = 0, np = 0, nb = 0, ns = 0, nr = 0, ngl = 0, nrun = 0, ndash = 0 }
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
        if L.roads then DrawGround(D, scene) end
        if L.runs then DrawRuns(D, scene) end
        if L.recent then
            DrawWalkLine(D, scene)
            DrawTrail(D, scene)
        end
    end
    DrawMarks(D, scene, from, upTo)

    for i = D.nl + 1, #lines do lines[i]:Hide() end
    for i = D.nd + 1, #dots do dots[i]:Hide() end
    for i = D.ng + 1, #glows do glows[i]:Hide() end
    for i = D.np + 1, #pins do pins[i]:Hide() end
    activePins = D.np
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
    -- keep pins steady while the map zooms or is rescaled
    local watcher = CreateFrame("Frame", nil, overlay)
    watcher.acc, watcher.k = 0, 0
    watcher:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        if self.acc < 0.05 then return end
        self.acc = 0
        local k = MapScale()
        if math.abs(k - self.k) > 0.001 then self.k = k RescalePins() end
    end)
    WorldMapFrame:HookScript("OnShow", Redraw)
    hooksecurefunc(WorldMapFrame, "OnMapChanged", Redraw)
    if ns.SetupMapButton then ns.SetupMapButton() end
end

-- Shared with the other files.
ns.Redraw = Redraw
ns.RescalePins = RescalePins
ns.SetupMap = SetupMap
ns.StartReplay = StartReplay
ns.StopReplay = StopReplay
ns.replay = replay
