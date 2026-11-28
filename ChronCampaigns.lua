-- Warpath: the chronicle's Campaigns tab (3.8.5)
-- One spread per campaign, as docs/design/chronicle-campaigns.md sets it:
-- the date line, the two-line title, the prose hand-wrapped round a sunk
-- drop cap with each foe's name its own string, and the route map (left);
-- Deeds and Losses on an inset sheet that scrolls, folding zone lines and
-- S3b rows, then The Reckoning (right); the footer with Earlier/Later,
-- folios, "campaign N of M" and the quiet filter.
--
-- Every position is the spec's, in render px (Book.X/Y convert), and the
-- spec's table is GEOMETRY below, which a test checks the built page against.
local ADDON, ns = ...
local C = ns.C
local MapName, UISound, Waypoint = ns.MapName, ns.UISound, ns.Waypoint
local Campaign = ns.Campaign
local Book, Chron = ns.Book, ns.Chron
local view = Chron.view
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC, SHADOW, LEVEL = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW, Book.LEVEL

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local Page = {}
ns.ChronCampaigns = Page

-- The spec's geometry (render px on the 1092x748 design canvas; y are
-- baselines unless named top). Code and spec are compared by a test.
local G = {
    L0 = 82, LR = 510, CX = 296, R0 = 586, RR = 1017, RCX = 801,
    date = { y = 107, px = 12, track = 1.2, rule = 40, gap = 12, dy = -4 },
    title = { y = 150, lh = 35, px = 31, ratio = 0.78, track = 0.6 },
    orn = { below = 17, half = 120 },
    prose = { gap = 40, px = 18, lh = 22 },
    cap = { lines = 3, px = 80, x = 81, stem = 5, foot = 6 },
    map = { w = 372, h = 180, top = 478, cx = 296 },
    head = { x = 802, y = 120, px = 25, orn = 133, half = 110 },
    share = { 938, 95, 1023, 121 },
    sheet = { 576, 142, 1025, 420 },
    win = { 578, 146, 1023, 416 },
    cord = { 1016, 152, 410 },
    col = { 584, 1005 },
    first = 162, row = 27, zone = 22, after = 4, folded = 26,
    reck = { head = 448, px = 23, orn = 461, half = 100, x0 = 616, x1 = 987, y = 488, lh = 26 },
    foot = { y = 694, earlier = 106, later = 990, navY = 692, folioL = 200, folioR = 801 },
}
Page.GEOMETRY = G

-- The drop cap's stem (the right edge of the letter's upper half) and foot
-- as shares of its width, measured on the design's face (type.py stem()):
-- lines 1-2 tuck to the stem, line 3 clears the foot.
local STEM = { A = 0.758, B = 0.887, C = 0.966, D = 0.955, E = 0.917, F = 0.933, G = 0.881, H = 0.970, I = 0.903,
    J = 0.935, K = 0.952, L = 0.583, M = 0.975, N = 0.970, O = 0.940, P = 0.959, Q = 0.940, R = 0.842, S = 0.878,
    T = 0.981, U = 0.984, V = 0.984, W = 1, X = 0.981, Y = 1, Z = 0.943 }

-- The map print (spec, "The route map"): the world map's art, desaturated,
-- MOD-blended, plus an ADD layer of the art and one of a flat colour, so the
-- page comes out as page x (a + b x grey) per channel, the straight line
-- nearest the design's sepia ramp (fitted on Joe's world map, land kept at
-- or under the paper's tone).
local PRINT_MOD = { 0.89, 1, 1 }
local PRINT_ADDART = { 0, 0.158, 0.141 }
local PRINT_ADD = { 0.398, 0.133, 0.021 }   -- the fit plus 5% of the page, matched to the design render
-- The design's crop of the world map layer (1002 x 668 px).
local CROP = { 58.2, 144.9, 855.2, 530.7 }
-- Ink on the map, already multiplied by the page's tone under it
-- (226,161,78), as the design's print multiplies its labels.
local MAP_RED, MAP_INK, MAP_LABEL, MAP_COUNT = { 150, 26, 14 }, { 70, 40, 14 }, { 62, 25, 4 }, { 133, 16, 4 }

local TAGS = { first = "first blood", grudge = "grudge", avenged = "revenge" }

---------------------------------------------------------------------------
-- The list: newest first, quiet campaigns hidden unless asked for
---------------------------------------------------------------------------

local quietOf = setmetatable({}, { __mode = "k" })

local function Quiet(c)
    if quietOf[c] == nil then
        local ok, p = pcall(ns.Chronicler.Write, c, myName)
        quietOf[c] = ok and p.quiet or false
    end
    return quietOf[c]
end

-- The newest always shows, so the book never opens on nothing.
local function Filter(all, showQuiet)
    local out, hidden = {}, 0
    for i, c in ipairs(all) do
        if i == 1 or showQuiet or not Quiet(c) then out[#out + 1] = c else hidden = hidden + 1 end
    end
    return out, hidden
end
Page.Filter = Filter

local function Load(preview)
    local all = preview and { Campaign.Sample() } or Campaign.List()
    if #all == 0 then all = { db.campaign } end
    view.all = all
    local keep = view.list and view.list[view.page]
    local quietN = 0
    for i = 2, #all do if Quiet(all[i]) then quietN = quietN + 1 end end
    view.quietN = quietN
    view.list = Filter(all, preview or (cfg and cfg.chronQuiet))
    view.page = 1
    for i, c in ipairs(view.list) do if c == keep then view.page = i end end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local P   -- the page's frames and pools, once built

local function Turn(delta)
    local n = #view.list
    local to = view.page + delta
    if to < 1 or to > n then return end
    view.page = to
    P.folded, P.sheet.scroll = {}, 0
    UISound("IG_ABILITY_PAGE_TURN", 836)
    Chron.Render()
end

local function BuildLeft(L)
    P.date = Book.Caps(L, "friz", G.date.px, FADED, { track = G.date.track })
    P.dateRules = { Book.Rule(L, 0, 1, 0, RUBRIC, 0.55), Book.Rule(L, 0, 1, 0, RUBRIC, 0.55) }
    P.title = {}
    for i = 1, 2 do
        P.title[i] = Book.Caps(L, "morph", G.title.px, RUBRIC, { ratio = G.title.ratio, track = G.title.track, shadow = SHADOW })
    end
    P.cap = Str(L, "morph", G.cap.px, RUBRIC)
    Book.Shadow(P.cap, SHADOW)
    P.lines, P.hovers = {}, {}
    P.map = CreateFrame("Frame", nil, L)
    P.map:SetAllPoints(L)
end

local function BuildRight(R)
    local h = Book.Caps(R, "morph", G.head.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    h:Set("Deeds and Losses", G.head.x, G.head.y, "m")
    P.head = h
    Book.Ornament(R, G.head.x, G.head.orn, G.head.half)

    local share = CreateFrame("Button", nil, R, "UIPanelButtonTemplate")
    Book.Box(share, G.share[1], G.share[2], G.share[3], G.share[4])
    share:SetText("Share")
    share:SetScript("OnClick", function(self) ns.ChronicleShareMenu(self) end)
    share:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Share this campaign")
        GameTooltip:AddLine("Two lines in guild, party, say or a whisper.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    share:SetScript("OnLeave", GameTooltip_Hide)
    P.share = share

    P.sheet = Book.Sheet(R, G.sheet, G.win, G.cord)
    P.zones, P.rows = {}, {}
    P.empty = Str(P.sheet.child, "gari", 17, FADED)

    local rh = Book.Caps(R, "morph", G.reck.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    rh:Set("The Reckoning", G.RCX, G.reck.head, "m")
    P.reckHead = rh
    Book.Ornament(R, G.RCX, G.reck.orn, G.reck.half)
    P.reck = {}
    for i = 1, 6 do P.reck[i] = Book.Reckon(R) end
end

local function BuildFooter(L)
    local O = Book.Old
    P.earlier = O.TurnButton(L, "Earlier", true, 18)
    Book.Box(P.earlier, 70.9, 671.6, 70.9 + 96 * 1.2, 705.2)
    Put(P.earlier.label, G.foot.earlier, G.foot.navY, "l", L)
    P.earlier:SetScript("OnClick", function() Turn(1) end)
    P.later = O.TurnButton(L, "Later", false, 18)
    Book.Box(P.later, 1026.1 - 96 * 1.2, 671.6, 1026.1, 705.2)
    Put(P.later.label, G.foot.later, G.foot.navY, "r", L)
    P.later:SetScript("OnClick", function() Turn(-1) end)

    P.folioL = Str(L, "gari", 17, FADED)
    P.folioR = Str(L, "gari", 17, FADED)
    P.count = Str(L, "narrow", 15, FADED)
    P.quiet = CreateFrame("Button", nil, L)
    P.quiet.box = Book.Solid(P.quiet, "ARTWORK", { 168, 132, 64 }, 1)
    P.quiet.fill = Book.Solid(P.quiet, "ARTWORK", { 26, 18, 10 }, 1, 1)
    P.quiet.check = P.quiet:CreateTexture(nil, "OVERLAY")
    P.quiet.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    P.quiet.label = Str(P.quiet, "narrow", 15, INK)
    P.quiet:SetScript("OnClick", function()
        if view.preview or not cfg then return end
        cfg.chronQuiet = not cfg.chronQuiet or nil
        UISound(cfg.chronQuiet and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF", 856)
        Load(false)
        P.folded, P.sheet.scroll = {}, 0
        Chron.Render()
    end)
    P.quiet:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quiet campaigns")
        GameTooltip:AddLine("Patrols and clashes: rides with little or no fighting. Hidden, never deleted.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    P.quiet:SetScript("OnLeave", GameTooltip_Hide)
end

local function Build(book)
    local L = CreateFrame("Frame", nil, book)
    L:SetAllPoints(book)
    local R = CreateFrame("Frame", nil, book)
    R:SetAllPoints(book)
    P = { L = L, R = R, folded = {} }
    book.camp = P
    BuildLeft(L)
    BuildRight(R)
    BuildFooter(L)
end

---------------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------------

local function Pooled(list, i, make)
    local x = list[i]
    if not x then x = make() list[i] = x end
    return x
end

local function ProseStr(i)
    return Pooled(P.lines, i, function() return Str(P.L, "friz", G.prose.px, INK) end)
end

local function Hover(i)
    return Pooled(P.hovers, i, function()
        local b = CreateFrame("Button", nil, P.L)
        b:SetScript("OnEnter", function(self) if not view.preview then Book.FoeTooltip(self, self.who, P.me) end end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        return b
    end)
end

---------------------------------------------------------------------------
-- Left page
---------------------------------------------------------------------------

local function Status(camp)
    if view.preview then return "  \194\183  sample pages" end
    if Campaign.IsOpen(camp) then return "  \194\183  in progress" end
    if camp.old then return "  \194\183  before 3.4: totals only" end
    return ""
end

local function LayHead(camp, w)
    local d = w.date
    local text = (d.weekday .. ", " .. d.month .. " " .. d.day .. "  \194\183  " .. d.tag .. Status(camp)):upper()
    local dw = P.date:Set(text, G.CX, G.date.y, "m")
    local g = G.date
    local y = G.date.y + g.dy
    Book.Box(P.dateRules[1], math.floor(G.CX - dw / 2 - g.gap - g.rule), y, math.floor(G.CX - dw / 2 - g.gap), y + 1)
    Book.Box(P.dateRules[2], math.floor(G.CX + dw / 2 + g.gap), y, math.floor(G.CX + dw / 2 + g.gap + g.rule), y + 1)
    local ty = G.title.y
    for i = 1, 2 do
        local line = w.title[i]
        P.title[i]:Set(line or "", G.CX, ty, "m")
        if line then ty = ty + G.title.lh end
    end
    local orn = ty - G.title.lh + G.orn.below
    P.orns = P.orns or {}
    for at, f in pairs(P.orns) do f:SetShown(at == orn) end
    if not P.orns[orn] then
        local f = CreateFrame("Frame", nil, P.L)
        f:SetAllPoints(P.L)
        Book.Ornament(f, G.CX, orn, G.orn.half)
        P.orns[orn] = f
    end
    return orn + G.prose.gap
end

-- Words of the prose, each a list of pieces { text, run }; a piece is cut
-- off a foe's name when punctuation follows it in the same word.
local function Words(runs, skip)
    local words, cur = {}, nil
    for ri, run in ipairs(runs) do
        local text = run.text
        if ri == 1 and skip then text = text:sub(skip + 1) end
        local pos = 1
        while pos <= #text do
            local sp = text:find(" ", pos, true)
            local piece = text:sub(pos, (sp or #text + 1) - 1)
            if piece ~= "" then
                if not cur then cur = {} words[#words + 1] = cur end
                cur[#cur + 1] = { piece, run.name and run or nil }
            end
            if sp then cur = nil pos = sp + 1 else pos = #text + 1 end
        end
    end
    return words
end

local function WordText(wd)
    local s = ""
    for _, p in ipairs(wd) do s = s .. p[1] end
    return s
end

-- The prose, wrapped by hand: indents[i] is line i's left indent (the drop
-- cap's tuck). Returns the baseline after the last line.
local function LayProse(runs, top, indents)
    local x0, width, lh = G.L0, G.LR - G.L0, G.prose.lh
    local lines, line = {}, {}
    local function Ind() return indents[#lines + 1] or 0 end
    for _, wd in ipairs(Words(runs, 1)) do
        local cand = {}
        for _, w in ipairs(line) do cand[#cand + 1] = WordText(w) end
        cand[#cand + 1] = WordText(wd)
        if #line == 0 or Book.Measure("friz", G.prose.px, table.concat(cand, " ")) <= width - Ind() then
            line[#line + 1] = wd
        else
            lines[#lines + 1] = { Ind(), line }
            line = { wd }
        end
    end
    if #line > 0 then lines[#lines + 1] = { Ind(), line } end

    -- one string per word piece, placed as the design sets them: each
    -- word's measured width, then a space's
    local space = Book.Measure("friz", G.prose.px, " ")
    local ns_, nh, y = 0, 0, top
    for _, ln in ipairs(lines) do
        local x = x0 + ln[1]
        for _, wd in ipairs(ln[2]) do
            for _, piece in ipairs(wd) do
                ns_ = ns_ + 1
                local fs = ProseStr(ns_)
                Set(fs, piece[1])
                if piece[2] then
                    Book.NameColor(fs, piece[2].class)
                    nh = nh + 1
                    local hv = Hover(nh)
                    hv.who = piece[2]
                    hv:ClearAllPoints()
                    hv:SetPoint("TOPLEFT", fs, "TOPLEFT")
                    hv:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT")
                    hv:Show()
                else
                    Book.Color(fs, INK)
                    fs:SetShadowOffset(0, 0)
                end
                Put(fs, x, y, "l", P.L)
                fs:Show()
                x = x + Book.Measure("friz", G.prose.px, piece[1])
            end
            x = x + space
        end
        y = y + lh
    end
    for i = ns_ + 1, #P.lines do P.lines[i]:Hide() end
    for i = nh + 1, #P.hovers do P.hovers[i]:Hide() end
    return y, #lines
end

local function LayChronicle(w, top)
    local runs = w.runs or {}
    local first = runs[1] and runs[1].text or ""
    local letter = first:sub(1, 1)
    local lh = G.prose.lh
    Set(P.cap, letter:upper())
    Put(P.cap, G.cap.x, top + (G.cap.lines - 1) * lh, "l", P.L)
    P.cap:SetShown(letter ~= "")
    local cw = Wpx(P.cap)
    local stem = (STEM[letter:upper()] or 1) * cw
    local indents = {}
    for i = 1, G.cap.lines - 1 do indents[i] = stem + G.cap.stem end
    indents[G.cap.lines] = cw + G.cap.foot
    return LayProse(runs, top, indents)
end

---------------------------------------------------------------------------
-- The route map
---------------------------------------------------------------------------

-- Where a zone sits on the world map (947), as a fraction: its rect's
-- centre, or through its continent.
local function OnWorld(z)
    if not (C_Map and C_Map.GetMapRectOnMap) then return end
    local ok, l, r, t, b = pcall(C_Map.GetMapRectOnMap, z, 947)
    if ok and l and r and (r - l) > 0 then return (l + r) / 2, (t + b) / 2 end
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(z)
    local cont = info and info.parentMapID
    if not cont or cont == 947 then return end
    local ok1, zl, zr, zt, zb = pcall(C_Map.GetMapRectOnMap, z, cont)
    local ok2, cl, cr, ct, cb = pcall(C_Map.GetMapRectOnMap, cont, 947)
    if ok1 and ok2 and zl and cl and (zr - zl) > 0 and (cr - cl) > 0 then
        return cl + (cr - cl) * (zl + zr) / 2, ct + (cb - ct) * (zt + zb) / 2
    end
end

-- The campaign's zones in the order first fought in, with what fell there.
local function Route(camp)
    local ev = {}
    for _, k in ipairs(camp.kl or {}) do ev[#ev + 1] = k end
    for _, d in ipairs(camp.dl or {}) do ev[#ev + 1] = d end
    table.sort(ev, function(a, b) return (a.t or 0) < (b.t or 0) end)
    local order, n = {}, {}
    for _, e in ipairs(ev) do
        if e.z then
            if not n[e.z] then order[#order + 1] = e.z n[e.z] = 0 end
            n[e.z] = n[e.z] + 1
        end
    end
    local out = {}
    for _, z in ipairs(order) do
        local x, y = OnWorld(z)
        if x then
            local px = (x * 1002 - CROP[1]) * G.map.w / (CROP[3] - CROP[1])
            local py = (y * 668 - CROP[2]) * G.map.h / (CROP[4] - CROP[2])
            out[#out + 1] = { z = z, x = px, y = py, n = n[z] }
        end
    end
    return out
end
Page.Route = Route

local function MapTex(i, blend)
    local m = P.mapPool
    local t = m.tex[i]
    if not t then
        t = P.map:CreateTexture(nil, "ARTWORK", nil, 1)
        t:AddMaskTexture(m.mask)
        m.tex[i] = t
    end
    t:SetBlendMode(blend or "MOD")
    t:SetDesaturated(false)
    t:SetVertexColor(1, 1, 1, 1)
    t:SetRotation(0)
    t:Show()
    return t
end

-- A straight piece from (ax, ay) to (bx, by), w px thick, as a turned
-- texture (the map's coordinates: px from the picture's top-left).
local function Stroke(i, ax, ay, bx, by, w, col, x0, y0)
    local t = MapTex(i)
    t:SetColorTexture(Book.RGB(col))
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    t:SetSize(math.max(0.01, len / 1.2), w / 1.2)
    t:ClearAllPoints()
    t:SetPoint("CENTER", P.L, "TOPLEFT", Book.X(x0 + (ax + bx) / 2), Book.Y(y0 + (ay + by) / 2))
    t:SetRotation(-math.atan2(by - ay, bx - ax))
    return i + 1
end

local LABEL_TRY = { { 14, 18, "l" }, { 0, 22, "m" }, { 12, -4, "l" }, { -14, -16, "r" }, { -14, 18, "r" } }

local function Overlaps(a, list)
    for _, b in ipairs(list) do
        if a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] then return true end
    end
    return false
end

local function LayMap(camp, top)
    local m = P.mapPool
    local x0 = G.map.cx - G.map.w / 2
    local y0 = top
    local w, h = G.map.w, G.map.h
    if not m then
        m = { tex = {}, labels = {}, counts = {} }
        P.mapPool = m
        m.mask = P.map:CreateMaskTexture()
        m.mask:SetTexture(Book.ART .. "map-mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
    Book.Box(m.mask, x0, y0, x0 + w, y0 + h, P.L)
    local i = 1
    -- the art: the world map's tiles, cropped to the design's window
    local files = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(947, 1)
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(947)
    local L1 = layers and layers[1]
    if files and L1 then
        local tw, th = L1.tileWidth or 256, L1.tileHeight or 256
        local cols = math.ceil((L1.layerWidth or 1002) / tw)
        local sx, sy = w / (CROP[3] - CROP[1]), h / (CROP[4] - CROP[2])
        for k, file in ipairs(files) do
            local c, r = (k - 1) % cols, math.floor((k - 1) / cols)
            local lx0, ly0 = math.max(CROP[1], c * tw), math.max(CROP[2], r * th)
            local lx1, ly1 = math.min(CROP[3], (c + 1) * tw), math.min(CROP[4], (r + 1) * th)
            if lx1 > lx0 and ly1 > ly0 then
                for pass = 1, 2 do
                    local add = pass == 2
                    if not add or PRINT_ADDART[2] + PRINT_ADDART[3] + PRINT_ADDART[1] > 0 then
                        local t = MapTex(i, add and "ADD" or "MOD")
                        i = i + 1
                        t:SetTexture(file)
                        t:SetTexCoord((lx0 - c * tw) / tw, (lx1 - c * tw) / tw, (ly0 - r * th) / th, (ly1 - r * th) / th)
                        t:SetDesaturated(true)
                        local v = add and PRINT_ADDART or PRINT_MOD
                        t:SetVertexColor(v[1], v[2], v[3], 1)
                        Book.Box(t, x0 + (lx0 - CROP[1]) * sx, y0 + (ly0 - CROP[2]) * sy,
                            x0 + (lx1 - CROP[1]) * sx, y0 + (ly1 - CROP[2]) * sy, P.L)
                    end
                end
            end
        end
        local t = MapTex(i, "ADD")
        i = i + 1
        t:SetColorTexture(PRINT_ADD[1], PRINT_ADD[2], PRINT_ADD[3], 1)
        Book.Box(t, x0, y0, x0 + w, y0 + h, P.L)
    end

    -- the route: a dashed red road, bowed, 20 dashes a leg
    local pts = Route(camp)
    local boxes = {}
    for k = 1, #pts - 1 do
        local a, b = pts[k], pts[k + 1]
        local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
        local nx, ny = -(b.y - a.y), b.x - a.x
        local len = math.sqrt(nx * nx + ny * ny)
        if len > 0 then
            local bow = ((k - 1) % 2 == 1 and 0.12 or -0.10) * len
            local cx, cy = mx + nx / len * bow, my + ny / len * bow
            local function At(u)
                return (1 - u) ^ 2 * a.x + 2 * (1 - u) * u * cx + u * u * b.x, (1 - u) ^ 2 * a.y + 2 * (1 - u) * u * cy + u * u * b.y
            end
            for j = 0, 76, 4 do
                local ax, ay = At(j / 80)
                local mx_, my_ = At((j + 1) / 80)
                local bx, by = At((j + 2) / 80)
                i = Stroke(i, ax, ay, mx_, my_, 2.2, MAP_RED, x0, y0)
                i = Stroke(i, mx_, my_, bx, by, 2.2, MAP_RED, x0, y0)
                boxes[#boxes + 1] = { math.min(ax, bx) - 1, math.min(ay, by) - 1, math.max(ax, bx) + 1, math.max(ay, by) + 1 }
            end
        end
    end
    -- crosses where something fell, a ring at the start, a flag at the end
    for k, p in ipairs(pts) do
        i = Stroke(i, p.x - 6, p.y - 6, p.x + 6, p.y + 6, 2.6, MAP_RED, x0, y0)
        i = Stroke(i, p.x - 6, p.y + 6, p.x + 6, p.y - 6, 2.6, MAP_RED, x0, y0)
        boxes[#boxes + 1] = { p.x - 7, p.y - 7, p.x + 7, p.y + 7 }
        if k == 1 then
            for s = 0, 23 do
                local a1, a2 = s / 24 * 2 * math.pi, (s + 1) / 24 * 2 * math.pi
                i = Stroke(i, p.x + 11 * math.cos(a1), p.y + 11 * math.sin(a1), p.x + 11 * math.cos(a2),
                    p.y + 11 * math.sin(a2), 1.6, MAP_RED, x0, y0)
            end
        end
    end
    local last = pts[#pts]
    if last then
        i = Stroke(i, last.x, last.y, last.x, last.y - 26, 1.6, MAP_INK, x0, y0)
        for r = 0, 9 do       -- the pennant: (x, y-26), (x+14, y-21), (x, y-16)
            local d = 5 - math.abs(r + 0.5 - 5)
            local t = MapTex(i)
            i = i + 1
            t:SetColorTexture(Book.RGB(MAP_RED))
            Book.Box(t, x0 + last.x, y0 + last.y - 26 + r, x0 + last.x + d * 14 / 5, y0 + last.y - 25 + r, P.L)
        end
        boxes[#boxes + 1] = { last.x - 1, last.y - 28, last.x + 16, last.y - 14 }
    end
    for k = i, #m.tex do m.tex[k]:Hide() end

    -- labels (Claude's call: the first place that fits) and counts
    local nl = 0
    for k, p in ipairs(pts) do
        nl = nl + 1
        local fs = Pooled(m.labels, nl, function() return Str(P.map, "friz", 15, MAP_LABEL) end)
        Set(fs, MapName(p.z) or "")
        local lw = Wpx(fs)
        local placed
        for _, try in ipairs(LABEL_TRY) do
            local bx = p.x + try[1]
            local l = try[3] == "l" and bx or (try[3] == "r" and bx - lw or bx - lw / 2)
            local base = p.y + try[2]
            local box = { l - 1, base - 12, l + lw + 1, base + 3 }
            if box[1] >= 14 and box[3] <= w - 14 and box[2] >= 8 and box[4] <= h - 8 and not Overlaps(box, boxes) then
                placed = { bx, base, try[3] }
                boxes[#boxes + 1] = box
                break
            end
        end
        placed = placed or { p.x, p.y + 22, "m" }
        Put(fs, x0 + placed[1], y0 + placed[2], placed[3], P.L)
        fs:Show()
        local cnt = Pooled(m.counts, k, function() return Str(P.map, "friz", 13, MAP_COUNT) end)
        Set(cnt, "\195\151" .. p.n)
        Put(cnt, x0 + p.x + 9, y0 + p.y + 4, "l", P.L)
        cnt:SetShown(p.n > 1)
    end
    for k = nl + 1, #m.labels do m.labels[k]:Hide() end
    for k = #pts + 1, #m.counts do m.counts[k]:Hide() end
    P.mapRect = { x0, y0, x0 + w, y0 + h }
end

---------------------------------------------------------------------------
-- Right page: deeds on the sheet
---------------------------------------------------------------------------

-- What a deed's tag says, split into the plain part and the raised part
-- (spec, "What a deed's tag says").
local function Tags(item)
    local e = item.e
    if not item.kill then return { "fell" }, {} end
    local plain, raised = {}, {}
    if e.tag == "first" then plain[#plain + 1] = TAGS.first
    elseif e.tag == "streak" and e.st then raised[#raised + 1] = "streak of " .. e.st
    elseif e.tag == "grudge" then raised[#raised + 1] = TAGS.grudge
    elseif e.tag == "avenged" then raised[#raised + 1] = TAGS.avenged end
    if e.mk and e.mk >= 2 then raised[#raised + 1] = Campaign.Burst(e.mk):lower() end
    local feat = e.ft and ns.Phrases.FEATS[e.ft]
    if feat and not (e.ft == "grudge" and e.tag == "grudge") and not (e.ft == "avenged" and e.tag == "avenged") then
        raised[#raised + 1] = feat[1]:lower()
    end
    return plain, raised
end
Page.Tags = Tags

-- The deeds in order, grouped under the zone they happened in (a new
-- group each time the zone changes, so the night still reads in order).
local function Groups(camp)
    local ev = {}
    for _, k in ipairs(camp.kl or {}) do ev[#ev + 1] = { e = k, kill = true } end
    for _, d in ipairs(camp.dl or {}) do ev[#ev + 1] = { e = d } end
    table.sort(ev, function(a, b) return (a.e.t or 0) < (b.e.t or 0) end)
    local groups, last = {}, false
    for _, it in ipairs(ev) do
        if it.e.z ~= last or #groups == 0 then
            groups[#groups + 1] = { z = it.e.z, items = {}, slain = 0, fell = 0, honours = 0 }
            last = it.e.z
        end
        local g = groups[#groups]
        local plain, raised = Tags(it)
        it.plain, it.raised = plain, raised
        it.honour = #raised > 0
        g.items[#g.items + 1] = it
        if it.kill then g.slain = g.slain + 1 else g.fell = g.fell + 1 end
        if it.honour then g.honours = g.honours + 1 end
    end
    return groups
end
Page.Groups = Groups

local function Clock(t)
    if not t then return "" end
    return (date("%H:%M", t):gsub("^0(%d)", "%1"))
end

local function ZoneLine(i)
    return Pooled(P.zones, i, function()
        local ch = P.sheet.child
        local z = CreateFrame("Button", nil, ch)
        z.chev = Book.Chevron(z, ch, G.win[1], G.win[2])
        z.name = Str(z, "gari", 17, FADED)
        z.tally = Str(z, "gari", 15, FADED)
        z.rule = Book.Solid(z, "ARTWORK", FADED, 0.3)
        z.dia = {}
        z:SetScript("OnClick", function(self)
            P.folded[self.index] = not P.folded[self.index] or nil
            UISound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
            Chron.Render()
        end)
        return z
    end)
end

local function Row(i)
    return Pooled(P.rows, i, function()
        local ch = P.sheet.child
        local o = { ch, G.win[1], G.win[2] }
        local r = CreateFrame("Button", nil, ch)
        r.band = Book.Band(r, o[1], o[2], o[3])
        r.tile = Book.Tile(r, o[1], o[2], o[3])
        r.time = Str(r, "narrow", 15, FADED)
        r.name = Str(r, "friz", 18, INK)
        r.level = Str(r, "friz", 15, LEVEL)
        r.plain = Str(r, "gari", 17, FADED)
        r.raised = Book.Caps(r, "morph", 16, RUBRIC, { ratio = 0.74, track = 0.6, shadow = SHADOW })
        r.dia = Book.Diamond(r, 0, 0, 3, Book.GILT, Book.GILT_EDGE, "OVERLAY", o[1], o[2], o[3])
        r:SetScript("OnEnter", function(self)
            local it = self.item
            if not it or view.preview then return end
            local e = it.e
            Book.FoeTooltip(self, { name = e.f and ns.DisplayName(e.f) or e.n and ns.DisplayName(e.n) or nil,
                text = e.n, key = e.f or e.n, class = e.c, level = e.lv, race = e.ra, guild = e.gu, shot = e.shot,
                waypoint = e.z and e.x and true }, P.me)
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        r:SetScript("OnClick", function(self)
            local e = self.item and self.item.e
            if e and e.z and e.x and not view.preview then
                Waypoint(e.z, e.x, e.y, self.item.kill and "a kill from your chronicle" or "a death from your chronicle")
            end
        end)
        return r
    end)
end

local function LayZoneLine(z, g, y, open)
    local x0, x1 = G.col[1], G.col[2]
    local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
    Book.Box(z, G.win[1], y - 16, G.win[3], y + 6, ch, ox, oy)
    z.chev:Set(open, x0, y)
    Set(z.name, MapName(g.z) or "Somewhere unknown")
    Put(z.name, x0 + 14, y, "l", ch, ox, oy)
    local tally = {}
    if g.slain > 0 then tally[#tally + 1] = g.slain .. " slain" end
    if g.fell > 0 then tally[#tally + 1] = g.fell .. " fell" end
    Set(z.tally, table.concat(tally, ", "))
    Put(z.tally, x1, y, "r", ch, ox, oy)
    local rx = x1 - Wpx(z.tally) - 10
    for k = 1, math.max(g.honours, #z.dia) do
        local d = z.dia[k]
        if k <= g.honours then
            if not d then
                d = Book.Diamond(z, 0, 0, 3, Book.GILT, Book.GILT_EDGE, "ARTWORK", ch, ox, oy)
                z.dia[k] = d
            end
            Book.MoveDiamond(d, rx - 3, y - 5)
            Book.ShowDiamond(d, true)
            rx = rx - 11
        elseif d then
            Book.ShowDiamond(d, false)
        end
    end
    local from = math.floor(x0 + 14 + Wpx(z.name) + 8)
    Book.Box(z.rule, from, y - 4, math.max(from + 0.01, math.floor(rx - 4)), y - 3, ch, ox, oy)
    z.rule:SetShown(rx - 4 > from)
end

local function LayRow(r, it, y, prevHonour, nextHonour)
    local x0, x1 = G.col[1], G.col[2]
    local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
    local e = it.e
    r.item = it
    Book.Box(r, x0 - 6, y - 20, x1 + 4, y + 7, ch, ox, oy)
    if it.honour then
        r.band:Set(x0 - 6, x1 + 4, prevHonour and y - 21 or y - 20, y + 7, not prevHonour, not nextHonour)
    else
        r.band:Hide()
    end
    r.tile:Set(not it.kill and "dark" or (it.honour and "gold" or "red"), e.c, x0 + 2, y - 17, 22)
    Set(r.time, Clock(e.t))
    Put(r.time, x0 + 32, y, "l", ch, ox, oy)
    local nx = x0 + 32 + 42
    if e.n then
        Set(r.name, e.n:match("^[^%-]+"))
        r.name:SetFont(Book.FACES.friz, 18 / 1.2, "")
        r.name.bface, r.name.bpx = "friz", 18
        Book.NameColor(r.name, e.c)
    else
        Set(r.name, "someone unseen")
        r.name:SetFont(Book.FACES.gari, 17 / 1.2, "")
        r.name.bface, r.name.bpx = "gari", 17
        Book.Color(r.name, FADED)
        r.name:SetShadowOffset(0, 0)
    end
    Put(r.name, nx, y, "l", ch, ox, oy)
    local lv = e.n and e.lv and (e.lv == -1 and "??" or tostring(e.lv)) or ""
    Set(r.level, lv)
    Put(r.level, nx + Wpx(r.name) + 6, y, "l", ch, ox, oy)
    local x = x1
    if #it.raised > 0 then
        local rw = r.raised:Set(table.concat(it.raised, ", "), x1, y, "r", ch, ox, oy)
        r.raised:SetShown(true)
        x = x - rw - 9
        Book.MoveDiamond(r.dia, x, y - 5)
        Book.ShowDiamond(r.dia, true)
        x = x - 6 - 4
    else
        r.raised:Set("", x1, y, "r", ch, ox, oy)
        Book.ShowDiamond(r.dia, false)
    end
    Set(r.plain, table.concat(it.plain, ", "))
    Book.Color(r.plain, it.kill and FADED or RUBRIC)
    Put(r.plain, x, y, "r", ch, ox, oy)
    r:Show()
end

local function LayDeeds(camp)
    local sheet = P.sheet
    sheet:Clear()
    local groups = Groups(camp)
    local y = G.first
    local nz, nr = 0, 0
    for gi, g in ipairs(groups) do
        nz = nz + 1
        local z = ZoneLine(nz)
        z.index = gi
        local open = not P.folded[gi]
        LayZoneLine(z, g, y, open)
        z:Show()
        sheet:Add(z, y - 16 - G.win[2], y + 6 - G.win[2])
        if open then
            local ry = y + G.zone
            for k, it in ipairs(g.items) do
                nr = nr + 1
                local r = Row(nr)
                local prev, nxt = g.items[k - 1], g.items[k + 1]
                LayRow(r, it, ry, prev and prev.honour, nxt and nxt.honour)
                sheet:Add(r, ry - 20 - G.win[2], ry + 7 - G.win[2])
                ry = ry + G.row
            end
            y = ry - G.row + G.row + G.after
        else
            y = y + G.folded
        end
    end
    for k = nz + 1, #P.zones do P.zones[k]:Hide() end
    for k = nr + 1, #P.rows do P.rows[k]:Hide() end
    local empty = #groups == 0
    if empty then
        Set(P.empty, camp.old and "Kills and deaths weren't listed before 3.4." or "No blood spilled yet.")
        Put(P.empty, (G.win[1] + G.win[3]) / 2, 190, "m", sheet.child, G.win[1], G.win[2])
    end
    P.empty:SetShown(empty)
    -- the content runs from the window's top to 16 px under the first zone
    -- line's place before it and after the last (combo.py's total)
    sheet:SetContent(empty and 0 or (y - G.win[2]))
    P.groups = groups
end

---------------------------------------------------------------------------
-- The Reckoning and the footer
---------------------------------------------------------------------------

local function Me()
    local me = ns.DisplayName and ns.DisplayName(myName or "") or myName or "You"
    return (me and me:match("^%S+")) or "You"
end

local function LayReckoning(camp)
    local s = Campaign.Summary(camp)
    local foe = ns.faction and ns.faction.foe
    foe = (foe == "Alliance" or foe == "Horde") and foe or "Foes"
    local shots = "none"
    if s.shotLo then shots = s.shotLo == s.shotHi and ("#" .. s.shotLo) or ("#" .. s.shotLo .. "\226\128\147#" .. s.shotHi) end
    local rows = {
        { foe .. " slain", tostring(s.kills) },
        { P.me .. " fell", s.deaths == 0 and "none" or tostring(s.deaths) },
        { "Best streak", s.best == 0 and "none" or tostring(s.best) },
        { "Miles ridden", ("%.1f"):format(s.miles or 0) },
        { "In the field", Campaign.Duration(s.played) },
        { "Screenshots", shots },
    }
    for i, r in ipairs(P.reck) do r:Set(rows[i][1], rows[i][2], G.reck.x0, G.reck.x1, G.reck.y + (i - 1) * G.reck.lh) end
end

local function LayFooter()
    local n = #view.list
    local number = n - view.page + 1        -- 1 = the oldest shown
    local fy = G.foot.y
    Set(P.folioL, "\226\128\148 " .. Book.Roman(number * 2 - 1) .. " \226\128\148")
    Put(P.folioL, G.foot.folioL, fy, "l", P.L)
    local x = G.foot.folioL + Wpx(P.folioL) + 14
    Set(P.count, "campaign " .. number .. " of " .. n)
    Put(P.count, x, fy, "l", P.L)
    x = x + Wpx(P.count) + 16
    local q = P.quiet
    local quietN = view.quietN or 0
    q:SetShown(quietN > 0 and not view.preview)
    if quietN > 0 then
        local o = { q, x, fy - 12 }
        Book.Box(q, x, fy - 12, x + 20 + Book.Measure("narrow", 15, "show " .. quietN .. " quiet") + 2, fy + 4, P.L)
        Book.Box(q.box, x, fy - 12, x + 15, fy + 3, o[1], o[2], o[3])
        Book.Box(q.fill, x + 1, fy - 11, x + 14, fy + 2, o[1], o[2], o[3])
        Book.Box(q.check, x - 3, fy - 15, x + 18, fy + 6, o[1], o[2], o[3])
        q.check:SetShown(cfg and cfg.chronQuiet and true or false)
        Set(q.label, "show " .. quietN .. " quiet")
        Put(q.label, x + 20, fy, "l", q, o[2], o[3])
    end
    Set(P.folioR, "\226\128\148 " .. Book.Roman(number * 2) .. " \226\128\148")
    Put(P.folioR, G.foot.folioR, fy, "m", P.L)
    if view.page < n then P.earlier:Enable() else P.earlier:Disable() end
    if view.page > 1 then P.later:Enable() else P.later:Disable() end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function Render()
    local camp = view.list[view.page]
    if not camp then return end
    P.me = Me()
    local w = ns.Chronicler.Write(camp, myName)
    P.written = w
    local top = LayHead(camp, w)
    local after = LayChronicle(w, top)
    LayMap(camp, math.max(G.map.top, after + 2))
    LayDeeds(camp)
    LayReckoning(camp)
    LayFooter()
    if view.preview then P.share:Disable() else P.share:Enable() end
end

Chron.pages.campaigns = {
    Build = Build,
    Render = Render,
    Open = function(preview) Load(preview) end,
    Reset = function() if P then P.folded = {} P.sheet.scroll = 0 end end,
    Refresh = function() Load(false) end,
}

function Page.Frames() return P end
