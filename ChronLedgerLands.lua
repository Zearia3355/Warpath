-- Warpath: the Ledger's fourth spread (3.8.5): My Lands
-- docs/design/chronicle-ledger.md, "4. My Lands" (F4): the continent's art
-- printed as the Campaigns route map is, lightened, with a mark on each land
-- fought in (left); the continent's lands on a sheet, and the chosen land's
-- account (right).
local ADDON, ns = ...
local Book, LG, Chron = ns.Book, ns.ChronLedger, ns.Chron
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC, SHADOW = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW
local L0, LR, CX, R0, RR, RCX = LG.G.L0, LG.G.LR, LG.G.CX, LG.G.R0, LG.G.RR, LG.G.RCX

local db, myFull
ns.OnBind(function() db, myFull = ns.db, ns.myFull end)

local G = {
    buttons = { y = 140, w = 150, h = 26, gap = 4, conts = { { 1414, "Kalimdor" }, { 1415, "Eastern Kingdoms" } } },
    map = { maxw = 428, maxh = 500, top = 166, cx = 296 },
    -- the landmass on each continent's map (its layer's fractions: left,
    -- right, top, bottom), the design's crops (geo.py CROPS) carried through
    -- the continents' fitted rects (Claude's call: check in game)
    crop = { [1414] = { 0.3365, 0.6804, 0.1307, 0.9791 }, [1415] = { 0.3872, 0.7006, 0.0464, 0.9853 } },
    mark = { col = { 150, 26, 14 }, w = 3, kpx = 16, dpx = 15, label = { 58, 32, 10 }, labelPx = 15, ring = 7 },
    key = 664,
    list = { sheet = { 576, 104, 1025, 300 }, win = { 578, 108, 1023, 296 }, cord = { 1016, 114, 290 },
             heads = 122, first = 146, step = 25, name = 590, kills = 947, deaths = 995, px = 17 },
    land = { head = 340, px = 23, figs = 404, figPx = 38, caps = 424, rule = { 376, 430 }, rows = 460, step = 24,
             x0 = 610, x1 = 993, top = 10 },
}
LG.LANDS = G

-- The print (ChronCampaigns' route map: page x (a + b x grey)), lightened 40%
-- toward the page: each layer at 0.6, plus 0.4 of the page's tone.
local PAGE = { 226 / 255, 161 / 255, 78 / 255 }
local K = 0.6
local PRINT_MOD = { 0.89 * K, 1 * K, 1 * K }
local PRINT_ADDART = { 0, 0.158 * K, 0.141 * K }
local PRINT_ADD = { 0.398 * K, 0.133 * K, 0.021 * K }

local state = LG.state
local P

local function Fought(l) return l and (l.kills + l.deaths) > 0 end

local function Choose(cont, land)
    state.cont, state.land = cont, land
    ns.UISound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    Chron.Render()
end

local function LandTip(self)
    local l = self.land and P.s.lands[self.land]
    LG.Tip(ns.MapName(self.land) or "?")
    if not l then return end
    LG.Tip(l.kills .. " slain, " .. l.deaths .. " fallen", 1, 0.82, 0)
    LG.Tip("Best streak here: " .. ((l.best or 0) > 0 and l.best or "none"), 0.8, 0.8, 0.8)
    LG.Tip("Click to open its account", 0.1, 1, 0.1)
end

---------------------------------------------------------------------------
-- Left: the continent and its marks
---------------------------------------------------------------------------

local function BuildLeft(L)
    LG.Heading(L, "My Lands", CX, LG.G.head.y)
    local b = G.buttons
    P.contBtns = {}
    for i, c in ipairs(b.conts) do
        P.contBtns[i] = LG.Button(L, function()
            if state.cont ~= c[1] then
                local cont = P.s.continents[c[1]]
                Choose(c[1], cont and (cont.bloodiest or cont.lands[1]) or nil)
            end
        end)
    end
    P.map = CreateFrame("Frame", nil, L)
    P.map:SetAllPoints(L)
    P.mask = P.map:CreateMaskTexture()
    P.mask:SetTexture(Book.ART .. "map-mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    P.art, P.strokes, P.marks = {}, {}, {}
    P.ring = LG.Ring(P.map, 32, "OVERLAY")
    local key = Str(L, "gari", 15, FADED)
    Set(key, "slain \194\183 fallen.  Choose a land to open its account.")
    Put(key, CX, G.key, "m")
end

local function ArtTex(i, blend)
    local t = P.art[i]
    if not t then
        t = P.map:CreateTexture(nil, "ARTWORK", nil, 1)
        t:AddMaskTexture(P.mask)
        P.art[i] = t
    end
    t:SetBlendMode(blend)
    t:SetDesaturated(false)
    t:SetVertexColor(1, 1, 1, 1)
    t:Show()
    return t
end

-- The continent's tiles cut to the landmass; returns the picture's rect.
local function LayArt(cont)
    local crop = G.crop[cont]
    local m = G.map
    local lw, lh = 1002 * (crop[2] - crop[1]), 668 * (crop[4] - crop[3])
    local k = math.min(m.maxw / lw, m.maxh / lh)
    local pw, ph = lw * k, lh * k
    local x0, y0 = m.cx - pw / 2, m.top
    Book.Box(P.mask, x0, y0, x0 + pw, y0 + ph, P.L)
    local i = 0
    local files = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(cont, 1)
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(cont)
    local L1 = layers and layers[1]
    if files and L1 then
        local tw, th = L1.tileWidth or 256, L1.tileHeight or 256
        local W, H = L1.layerWidth or 1002, L1.layerHeight or 668
        local cols = math.ceil(W / tw)
        local cx0, cx1, cy0, cy1 = crop[1] * W, crop[2] * W, crop[3] * H, crop[4] * H
        local sx, sy = pw / (cx1 - cx0), ph / (cy1 - cy0)
        for n, file in ipairs(files) do
            local c, r = (n - 1) % cols, math.floor((n - 1) / cols)
            local lx0, ly0 = math.max(cx0, c * tw), math.max(cy0, r * th)
            local lx1, ly1 = math.min(cx1, (c + 1) * tw), math.min(cy1, (r + 1) * th)
            if lx1 > lx0 and ly1 > ly0 then
                for pass = 1, 2 do
                    i = i + 1
                    local t = ArtTex(i, pass == 1 and "MOD" or "ADD")
                    t:SetTexture(file)
                    t:SetTexCoord((lx0 - c * tw) / tw, (lx1 - c * tw) / tw, (ly0 - r * th) / th, (ly1 - r * th) / th)
                    t:SetDesaturated(true)
                    local v = pass == 1 and PRINT_MOD or PRINT_ADDART
                    t:SetVertexColor(v[1], v[2], v[3], 1)
                    Book.Box(t, x0 + (lx0 - cx0) * sx, y0 + (ly0 - cy0) * sy, x0 + (lx1 - cx0) * sx, y0 + (ly1 - cy0) * sy, P.L)
                end
            end
        end
        i = i + 1
        local t = ArtTex(i, "ADD")
        t:SetColorTexture(PRINT_ADD[1], PRINT_ADD[2], PRINT_ADD[3], 1)
        Book.Box(t, x0, y0, x0 + pw, y0 + ph, P.L)
        -- lightened toward the page: an ADD of 40% of its tone, where the
        -- MOD layers took that much away
        i = i + 1
        t = ArtTex(i, "ADD")
        t:SetColorTexture(PAGE[1] * 0.4, PAGE[2] * 0.4, PAGE[3] * 0.4, 1)
        Book.Box(t, x0, y0, x0 + pw, y0 + ph, P.L)
    end
    for n = i + 1, #P.art do P.art[n]:Hide() end
    return { x0, y0, pw, ph, crop }
end

-- Where a land sits in the picture: its rect's centre on the continent.
local function Spot(id, cont, pic)
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, id, cont)
    if not (ok and l and r and (r - l) > 0) then return end
    local crop = pic[5]
    local fx, fy = (l + r) / 2, (t + b) / 2
    return pic[1] + (fx - crop[1]) / (crop[2] - crop[1]) * pic[3], pic[2] + (fy - crop[3]) / (crop[4] - crop[3]) * pic[4]
end
LG.LANDS.Spot = Spot

local function Stroke(i, ax, ay, bx, by)
    local t = P.strokes[i]
    if not t then t = P.map:CreateTexture(nil, "OVERLAY") P.strokes[i] = t end
    t:SetColorTexture(Book.RGB(G.mark.col))
    LG.Line(t, ax, ay, bx, by, G.mark.w, P.L)
    return i + 1
end

local function Mark(i)
    local m = P.marks[i]
    if not m then
        m = { k = Book.Bold(Str(P.map, "garb", G.mark.kpx, RUBRIC)), d = Str(P.map, "garb", G.mark.dpx, FADED),
              label = Str(P.map, "gari", G.mark.labelPx, G.mark.label),
              hot = LG.Hot(P.map, LandTip, function(self) Choose(state.cont, self.land) end),
              hotLabel = LG.Hot(P.map, LandTip, function(self) Choose(state.cont, self.land) end) }
        P.marks[i] = m
    end
    return m
end

local function Free(box, taken)
    for _, t in ipairs(taken) do
        if not (box[3] < t[1] or box[1] > t[3] or box[4] < t[2] or box[2] > t[4]) then return false end
    end
    return true
end

local function LayMarks(cont, pic)
    local s = P.s
    local c = s.continents[cont]
    local placed, si = {}, 1
    for _, id in ipairs(c and c.lands or {}) do
        local l = s.lands[id]
        if Fought(l) then
            local x, y = Spot(id, cont, pic)
            if x then
                local r = 3 + math.min(4, math.floor((l.kills + l.deaths) / 2))
                si = Stroke(si, x - r, y - r, x + r, y + r)
                si = Stroke(si, x - r, y + r, x + r, y - r)
                placed[#placed + 1] = { id = id, x = x, y = y, r = r, l = l }
            end
        end
    end
    for n = si, #P.strokes do P.strokes[n]:Hide() end
    -- labels: below the mark, or above, left or right, whichever is free
    -- (lround3.py lands_map)
    local taken = {}
    for _, p in ipairs(placed) do taken[#taken + 1] = { p.x - p.r - 4, p.y - p.r - 4, p.x + p.r + 60, p.y + p.r + 4 } end
    local ring = false
    for n, p in ipairs(placed) do
        local m = Mark(n)
        Set(m.k, tostring(p.l.kills))
        Put(m.k, p.x + p.r + 5, p.y - 2, "l")
        LG.Show(m.k, true)
        Set(m.d, " \194\183 " .. p.l.deaths)
        Put(m.d, p.x + p.r + 6 + Wpx(m.k), p.y - 2, "l")
        m.d:Show()
        local name = ns.MapName(p.id) or "?"
        Set(m.label, name)
        local w = Book.Measure("gari", G.mark.labelPx, name)
        local box
        for _, try in ipairs({ { p.x - w / 2, p.y + p.r + 4 }, { p.x - w / 2, p.y - p.r - 22 },
                { p.x - w - p.r - 6, p.y - 8 }, { p.x + p.r + 40, p.y - 8 } }) do
            box = { try[1], try[2], try[1] + w, try[2] + 14 }
            if Free(box, taken) then break end
        end
        taken[#taken + 1] = box
        Put(m.label, box[1], box[2] + 12, "l")
        m.label:Show()
        m.hot.land, m.hotLabel.land = p.id, p.id
        Book.Box(m.hot, p.x - p.r - 3, p.y - p.r - 3, p.x + p.r + 40, p.y + p.r + 3)
        Book.Box(m.hotLabel, box[1], box[2], box[3], box[4])
        m.hot:Show()
        m.hotLabel:Show()
        if p.id == state.land then
            P.ring:Set(p.x, p.y, p.r + G.mark.ring, RUBRIC, 1, 2, P.L)
            ring = true
        end
    end
    for n = #placed + 1, #P.marks do
        local m = P.marks[n]
        LG.Show(m.k, false) m.d:Hide() m.label:Hide() m.hot:Hide() m.hotLabel:Hide()
    end
    P.ring:SetShown(ring)
    P.placed = placed
end

---------------------------------------------------------------------------
-- Right: the lands on a sheet, the chosen land's account
---------------------------------------------------------------------------

local function BuildRight(R)
    local g = G.list
    P.sheet = Book.Sheet(R, g.sheet, g.win, g.cord)
    local ch, ox, oy = P.sheet.child, g.win[1], g.win[2]
    P.heads = { LG.Head(ch, 11, RUBRIC), LG.Head(ch, 11, FADED) }
    P.rows = {}
    local h = G.land
    P.title = Book.Caps(R, "morph", h.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    Book.Ornament(R, RCX, h.head + 13, 100)
    P.figs, P.caps = {}, {}
    local third = (RR - R0) / 3
    for i = 1, 3 do
        local fs = Book.Bold(Str(R, "garb", h.figPx, RUBRIC))
        Book.Shadow(fs, SHADOW)
        P.figs[i], P.caps[i] = fs, LG.Head(R, 11, FADED)
        if i > 1 then
            local x = math.floor(R0 + third * (i - 1))
            Book.Rect(R, "ARTWORK", RUBRIC, 0.35, x, h.rule[1], x + 1, h.rule[2])
        end
    end
    P.reck = {}
    for i = 1, 6 do P.reck[i] = LG.Row(R, 17, 19) end
    P.topLabel = Str(R, "friz", 16, INK)
    Set(P.topLabel, "Slain most here")
    P.topName = LG.NameStr(R, 17)
    P.topCount = Book.Bold(Str(R, "garb", 17, RUBRIC))
    P.topNone = Str(R, "gari", 16, FADED)
    P.topHot = LG.Hot(R, function(self) if not self.f then return false end LG.FoeTip(self.f, self.e) end,
        function(self) if self.f and ns.Grudge.Get(self.f) then LG.OpenGrudge(self.f) end end)
end

local function ListRow(i)
    local r = P.rows[i]
    if not r then
        local g = G.list
        local ch, ox, oy = P.sheet.child, g.win[1], g.win[2]
        r = LG.Hot(ch, LandTip, function(self) Choose(state.cont, self.land) end)
        r.band = Book.Band(r, ch, ox, oy, LG.BAND, 70 / 255)
        r.name = Str(r, "gari", g.px, INK)
        r.k = LG.Num(r, 18, RUBRIC, ch, ox, oy)
        r.d = LG.Num(r, 17, INK, ch, ox, oy)
        P.rows[i] = r
    end
    return r
end

local function LayList(cont)
    local g = G.list
    local s, sheet = P.s, P.sheet
    local ch, ox, oy = sheet.child, g.win[1], g.win[2]
    sheet:Clear()
    P.heads[1]:Set("KILLS", g.kills, g.heads, "r", ch, ox, oy)
    P.heads[2]:Set("DEATHS", g.deaths, g.heads, "r", ch, ox, oy)
    local c = s.continents[cont]
    local y = g.first
    local lands = c and c.lands or {}
    for i, id in ipairs(lands) do
        local l, r = s.lands[id], ListRow(i)
        r.land = id
        local chosen = id == state.land
        Book.Box(r, R0 - 4, y - 19, RR - 10, y + 6, ch, ox, oy)
        if chosen then r.band:Set(R0 - 4, RR - 10, y - 19, y + 6, true, true) else r.band:Hide() end
        Set(r.name, ns.MapName(id) or "?")
        r.name:SetFont(Book.FACES[chosen and "friz" or "gari"], g.px / 1.2, "")
        r.name.bface = chosen and "friz" or "gari"
        if chosen and not r.name.twin then Book.Bold(r.name) end
        if r.name.twin then
            r.name.twin:SetFont(Book.FACES[r.name.bface], g.px / 1.2, "")
            Set(r.name, ns.MapName(id) or "?")
            r.name.twin:SetShown(chosen)
        end
        Book.Color(r.name, chosen and RUBRIC or (Fought(l) and INK or FADED))
        Put(r.name, g.name, y, "l", ch, ox, oy)
        r.k:Set(l.kills, g.kills, y, "r")
        r.d:Set(l.deaths, g.deaths, y, "r")
        sheet:Add(r, y - 19 - oy, y + 6 - oy)
        r:Show()
        y = y + g.step
    end
    for i = #lands + 1, #P.rows do P.rows[i]:Hide() end
    sheet:SetContent(#lands > 0 and (y - g.heads + 12) or 0)
end

-- This character's foe slain most here, with class and level from the marks.
local function TopFoe(id, top)
    local z = db and db.maps and db.maps[id]
    for _, m in ipairs(z and z.marks or {}) do
        if m[4] == "kill" and ((top.f and m.f == top.f) or (not top.f and m.n == top.n)) then
            return { c = m.c, lv = m.lv, ra = m.ra, gu = m.gu, n = m.n }
        end
    end
    return { n = top.n }
end

local function LayLand(ctx)
    local h, id = G.land, state.land
    local l = id and P.s.lands[id]
    local shown = l ~= nil
    P.title:Set(shown and (ns.MapName(id) or "?") or "", RCX, h.head, "m")
    local third = (RR - R0) / 3
    local figs = { { l and l.kills or 0, "SLAIN HERE" }, { l and l.deaths or 0, "FALLEN HERE" }, { l and l.best or 0, "BEST STREAK" } }
    for i, f in ipairs(figs) do
        local cx = R0 + third * (i - 1) + third / 2
        Set(P.figs[i], tostring(f[1]))
        Put(P.figs[i], cx, h.figs, "m")
        P.caps[i]:Set(f[2], cx, h.caps, "m")
    end
    local function V(v, fmt)
        if not v or v == 0 then return "none", true end
        return fmt and fmt:format(v) or LG.Comma(v), false
    end
    local rows = {
        { "Different foes slain here", l and l.foes },
        { "Fell to the wilds here", l and l.wilds },
        { "Miles travelled here", l and l.yards and l.yards / 1760 or 0, "%.1f" },
        { "Enemies sighted here", l and l.sightings },
        { "Guildmates' kills here", l and l.gkills },
        { "Corpse runs here", l and l.runs, nil, "none yet" },
    }
    local y = h.rows
    for i, r in ipairs(rows) do
        local v, quiet = V(r[2], r[3])
        if i == 3 and l and l.yards and l.yards > 0 and l.yards / 1760 < 0.05 then v, quiet = "none", true end
        if quiet and r[4] then v = r[4] end
        if i == 1 and ctx.account then v, quiet = "this character only", true end
        P.reck[i]:Set(r[1], v, h.x0, h.x1, y, quiet)
        y = y + h.step
    end
    y = y + h.top
    Put(P.topLabel, h.x0, y, "l")
    local x = h.x0 + Wpx(P.topLabel) + 12
    local top = not ctx.account and l and l.top
    P.topNone:SetShown(not top)
    LG.Show(P.topCount, top and true or false)
    if top then
        local e = TopFoe(id, top)
        local w = P.topName:Set(LG.Name(top.f) or top.n or "Unknown", e.c, nil, x, y)
        Set(P.topCount, "\195\151" .. top.count)
        Put(P.topCount, x + w + 6, y, "l")
        P.topHot.f, P.topHot.e = top.f, e
        Book.Box(P.topHot, x, y - 16, x + w, y + 5)
        P.topHot:Show()
    else
        P.topName:Hide()
        P.topHot:Hide()
        Set(P.topNone, ctx.account and "this character only" or "none yet")
        Put(P.topNone, x, y, "l")
    end
end

---------------------------------------------------------------------------

local function Pick(s)
    local conts = s.continents or {}
    local cont = state.cont
    if not cont then
        local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        cont = here and (ns.Ledger.ContinentOf(here) or (here == 1414 or here == 1415) and here) or nil
        if cont ~= 1414 and cont ~= 1415 then
            local best = -1
            for id, c in pairs(conts) do if c.kills + c.deaths > best then cont, best = id, c.kills + c.deaths end end
        end
        cont = (cont == 1414 or cont == 1415) and cont or 1415
    end
    local c = conts[cont]
    local land = state.land
    if not (land and s.lands[land] and c) then land = nil end
    if land then
        local on = false
        for _, id in ipairs(c.lands) do if id == land then on = true end end
        if not on then land = nil end
    end
    if not land and c then land = c.bloodiest or c.lands[1] end
    state.cont, state.land = cont, land
end

local function Build(F)
    P = { L = F.L }
    LG.LANDS.P = P
    BuildLeft(F.L)
    BuildRight(F.R)
end

local function Render(F, ctx)
    P.s = ctx.s
    -- the account view and this character's share a choice only while the
    -- land exists in both
    Pick(ctx.s)
    local b = G.buttons
    local x = G.map.cx - (2 * b.w + b.gap) / 2
    for i, c in ipairs(b.conts) do
        P.contBtns[i]:Set(c[2], x + (i - 1) * (b.w + b.gap), b.y, b.w, b.h, state.cont == c[1] and "on" or "off")
    end
    local pic = LayArt(state.cont)
    P.pic = pic
    LayMarks(state.cont, pic)
    LayList(state.cont)
    LayLand(ctx)
end

LG.spreads[4] = { Build = Build, Render = Render }
