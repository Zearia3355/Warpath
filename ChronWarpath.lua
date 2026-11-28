-- Warpath: the chronicle's Warpath tab (3.8.5)
-- The book's front page, as docs/design/chronicle-warpath.md sets it. Left:
-- the kicker, the title and a one-paragraph welcome for a first install, an
-- update (the versions as figures) or a later visit, under a sunk initial;
-- a teaching picture of the world map with Warpath's marks, drawn with the
-- map's own looks (ns.MapLook) so the key can't drift from the map; the
-- key, the two how-to lines, the Guild sharing switch. Right: What's New,
-- every release newest first on one inset sheet that scrolls, new releases
-- flanked by gilt diamonds and a "read before" divider after an update.
--
-- Every position is the spec's, in render px (Book.X/Y convert), and the
-- spec's tables are GEOMETRY below, which a test checks the built page against.
local ADDON, ns = ...
local C = ns.C
local Book, Chron = ns.Book, ns.Chron
local view = Chron.view
local Put, Set, Str, Wpx, Measure = Book.Put, Book.Set, Book.Str, Book.Wpx, Book.Measure
local INK, FADED, RUBRIC, SHADOW = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local Page = {}
ns.ChronWarpath = Page

-- The spec's geometry (render px on the 1092x748 design canvas; y are
-- baselines unless named top). Code and spec are compared by a test.
local G = {
    L0 = 82, LR = 510, CX = 296, R0 = 586, RR = 1017, RCX = 801,
    kicker = { y = 107, px = 12, track = 1.2, rule = 40, gap = 12, dy = -4 },
    title = { y = 150, px = 31, ratio = 0.78, track = 0.6, orn = 167, half = 120 },
    welcome = { top = 210, px = 18, lh = 22, fig = 20, width = 428, lines = 4 },  -- 4 lines: ends by y 290
    cap = { lines = 3, px = 80, x = 81, stem = 5, foot = 6 },
    pic = { w = 392, h = 140, top = 288, cx = 296 },
    key = { cols = { 86, 330 }, y = { 448, 469, 490, 511 }, sw = 26, sh = 18, text = 34, px = 15, gloss = 5,
        pins = { kill = 20, death = 17, sight = 20 } },
    button = { cx = 95, cy = 535, size = 24, x = 120, y = 540, px = 16, lh = 22, right = 510, last = 584 },
    share = { box = { 82, 603 }, size = 18, x = 110, y = 618, px = 18, state = 19, gap = 10,
        hint = { y = 640, px = 16, lh = 19, width = 400 } },
    folio = { y = 694, px = 17 },
    head = { y = 120, px = 25, orn = 133, half = 110 },
    sheet = { 576, 150, 1025, 668 },
    win = { 578, 154, 1023, 664 },
    cord = { 1016, 160, 658 },
    col = { 590, 1003 },
    first = 22,                                  -- the first baseline below the window's top
    rel = { px = 21, after = 26, titled = 44, title = 20, rule = 12, dy = -6, dia = 22 },
    topic = { x = 606, px = 11, track = 1.4, step = 22, before = 6, dy = 2 },
    note = { mark = 594, x = 606, px = 16, lh = 20, mw = 8, mh = 10 },
    between = 18,
    divider = { before = 4, band = { -20, 10 }, rule = 9, after = 40, px = 17, inset = 20 },
    tail = 6,                                    -- the content runs this far past the last release
    footer = { x = 1017, y = 694, px = 15 },
}
Page.GEOMETRY = G

-- Read releases, after the divider (spec, "Read releases").
local READ_HEAD, READ_NOTE, READ_MARK = { 150, 80, 56 }, { 104, 82, 56 }, { 150, 90, 60 }
local GILT_RULE = { 176, 128, 52 }

-- The two how-to lines beside the map button. Each wraps inside the column
-- if the faces run wide; "~" holds two words together. The map line was
-- "On the world map, top right: choose what Warpath shows.", which ran into
-- the gutter in game (3.8.5-test4); the shorter one is Claude's call.
local HOWTO = {
    "World map, top right: choose Warpath's marks.",
    "This book: the minimap button, or~/warpath~chronicle.",
}
local SHARE_HINT = "Guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. "
    .. "Only between guildmates who have it on."

-- The key (spec, "Map key"): kind, label, gloss.
local KEY = {
    { "road", "Your roads", "builds over days" }, { "kill", "A kill" },
    { "trail", "Today's trail" }, { "death", "Where you fell" },
    { "area", "Where you lingered" }, { "sight", "An enemy seen" },
    { "flight", "A flight you take often" }, { "haze", "Where you fought" },
}
Page.KEY = KEY

---------------------------------------------------------------------------
-- The teaching picture (spec, "The map picture"): the World map's art
-- round the Arathi and Hinterlands coast, printed in sepia, with a fixed
-- scene of marks drawn as the map draws them. Places are fractions of the
-- picture, as the design's generator (warpath/r3.py) sets them.
---------------------------------------------------------------------------

-- The design's crop of world.png (1250-1690 x 452-610), in the World
-- map's layer px (1002 x 668; the screenshot's canvas 208-1792 x 61-1117).
local CROP = { 659.2, 247.3, 937.5, 347.3 }

local SCENE = {
    haze = { { 0.55, 0.62, 36, 1 }, { 0.29, 0.62, 18, 200 / 255 } },   -- x, y, radius px, strength
    road = { { 0.17, 0.88 }, { 0.26, 0.74 }, { 0.38, 0.70 }, { 0.50, 0.60 }, { 0.62, 0.52 }, { 0.74, 0.50 } },
    flight = { { 0.08, 0.14 }, { 0.24, 0.10 }, { 0.42, 0.14 }, { 0.57, 0.26 } },
    trail = { { 0.36, 0.95 }, { 0.42, 0.86 }, { 0.45, 0.78 }, { 0.52, 0.74 }, { 0.60, 0.72 } },
    arrow = { 0.45, 0.80 },
    area = { 0.67, 0.70, 32, 20 },              -- centre, radii in px
    pins = { { "kill", 0.56, 0.55, 18 }, { "kill", 0.48, 0.66, 18 }, { "kill", 0.72, 0.68, 18 },
        { "death", 0.30, 0.62, 15 }, { "sight", 0.74, 0.32, 21 } },
}
Page.SCENE = SCENE

-- How the marks are set in the picture and the key (Claude's call, from
-- the design's widths: a road 3 px of gold on a 5 px casing, 2 px trail
-- and flight dashes, 1.6 px outlines): the map's looks at these sizes.
local MARK = {
    road = { thin = 1.5, wear = 0.5 },           -- full gold, not yet worn into your colours
    trail = { thick = 2, slot = 7, age = 60 },   -- a dash slot in px; trail this many s past the solid line
    area = { thick = 1.6 },
    flight = { thin = 1.1, u = 0.5 },
    life = 12 * 3600,                            -- the default trail length
    haze = { { 0, 0, 1.0, 0, 0.85 }, { -0.35, 0.1, 0.7, 0.2, 0.75 }, { 0.3, -0.15, 0.55, 1, 1 } }, -- dx, dy, r, t, a
    dot = 3.6,                                   -- C.TEX_DOT's size per patch radius (its soft edge)
}

-- A pen: Look's put, drawing each piece as a turned solid on `frame`
-- (masked by `mask` when given). Coordinates are the map's: px from the
-- drawing's origin (render px ox, oy), y negative downward.
local function Pen(frame, mask, ox, oy)
    local pen = { n = 0, tex = {}, dots = {}, nd = 0, pins = {}, np = 0 }
    function pen.put(sub, blend, thick, r, g, b, a, x1, y1, x2, y2)
        pen.n = pen.n + 1
        local t = pen.tex[pen.n]
        if not t then
            t = frame:CreateTexture(nil, "ARTWORK")
            if mask then t:AddMaskTexture(mask) end
            pen.tex[pen.n] = t
        end
        t:SetDrawLayer("ARTWORK", math.max(-8, math.min(7, sub or 0)))
        t:SetBlendMode(blend or "BLEND")
        t:SetColorTexture(r, g, b, a)
        local ax, ay, bx, by = ox + x1, oy - y1, ox + x2, oy - y2
        local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        t:SetSize(math.max(0.01, len / 1.2), thick / 1.2)
        t:ClearAllPoints()
        t:SetPoint("CENTER", frame, "TOPLEFT", Book.X((ax + bx) / 2), Book.Y((ay + by) / 2))
        t:SetRotation(-math.atan2(by - ay, bx - ax))
        t:Show()
        return t
    end
    function pen.dot(x, y, size, r, g, b, a)
        pen.nd = pen.nd + 1
        local d = pen.dots[pen.nd]
        if not d then
            d = frame:CreateTexture(nil, "BORDER")
            d:SetTexture(C.TEX_DOT)
            d:SetBlendMode("BLEND")
            if mask then d:AddMaskTexture(mask) end
            pen.dots[pen.nd] = d
        end
        d:SetVertexColor(r, g, b)
        d:SetAlpha(a)
        Book.Box(d, ox + x - size / 2, oy + y - size / 2, ox + x + size / 2, oy + y + size / 2, frame)
        d:Show()
        return d
    end
    -- a pin as DrawMarks pins it (Look.Pin, Look.PinCoords), size px square
    function pen.pin(kind, x, y, size, fac)
        pen.np = pen.np + 1
        local p = pen.pins[pen.np]
        if not p then
            p = frame:CreateTexture(nil, "OVERLAY")
            if mask then p:AddMaskTexture(mask) end
            pen.pins[pen.np] = p
        end
        local tex, r, g, b = ns.MapLook.Pin(kind, fac)
        p:SetTexture(tex)
        p:SetTexCoord(ns.MapLook.PinCoords(kind))
        p:SetVertexColor(r, g, b, 1)
        p.kind = kind
        Book.Box(p, ox + x - size / 2, oy + y - size / 2, ox + x + size / 2, oy + y + size / 2, frame)
        p:Show()
        return p
    end
    function pen.reset() pen.n, pen.nd, pen.np = 0, 0, 0 end
    function pen.finish()
        for i = pen.n + 1, #pen.tex do pen.tex[i]:Hide() end
        for i = pen.nd + 1, #pen.dots do pen.dots[i]:Hide() end
        for i = pen.np + 1, #pen.pins do pen.pins[i]:Hide() end
    end
    return pen
end

-- The marks, each from points in px (x right, y down) of the drawing.

local function Road(pen, pts, k, fac)
    local m = MARK.road
    local thin = m.thin * (k or 1)
    local core = thin * (1.1 + 1.9 * m.wear)
    for i = 1, #pts - 1 do
        local x1, y1, x2, y2 = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
        -- corners eased as RoadChains joins them: each stretch runs on half
        -- its width into the next
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        local e = len > 0 and core * 0.5 / len or 0
        if i > 1 then x1, y1 = x1 - dx * e, y1 - dy * e end
        if i < #pts - 1 then x2, y2 = x2 + dx * e, y2 + dy * e end
        ns.MapLook.Road(pen.put, 1, m.wear, 0, 1, thin, x1, -y1, x2, -y2, fac)
    end
end

-- Dashes along a path, carried across its corners (Look.Dashes); draw is
-- the put each dash goes through.
local function Along(pts, dash, gap, draw)
    local phase = 0
    for i = 1, #pts - 1 do
        phase = ns.MapLook.Dashes(draw, 6, 1, 0, 0, 0, 1, dash, gap, phase,
            pts[i][1], -pts[i][2], pts[i + 1][1], -pts[i + 1][2])
    end
end

local function Flight(pen, pts)
    local m, look = MARK.flight, ns.MapLook.AIR
    Along(pts, look.dash, look.gap, function(_, _, _, _, _, _, _, x1, y1, x2, y2)
        ns.MapLook.Air(pen.put, m.thin, m.u, 1, x1, y1, x2, y2)
    end)
end

-- Where along a path a point lies nearest, as a distance from its start.
local function Nearest(pts, x, y)
    local best, at, run = math.huge, 0, 0
    for i = 1, #pts - 1 do
        local ax, ay, bx, by = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
        local dx, dy = bx - ax, by - ay
        local L2 = dx * dx + dy * dy
        local u = L2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2)) or 0
        local px, py = ax + dx * u, ay + dy * u
        local d = (px - x) ^ 2 + (py - y) ^ 2
        if d < best then best, at = d, run + u * math.sqrt(L2) end
        run = run + math.sqrt(L2)
    end
    return at
end

-- The point and heading at distance s along a path.
local function PointAt(pts, s)
    for i = 1, #pts - 1 do
        local ax, ay, bx, by = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
        local L = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        if s <= L or i == #pts - 1 then
            local u = L > 0 and math.min(1, s / L) or 0
            return ax + (bx - ax) * u, ay + (by - ay) * u, (bx - ax) / math.max(L, 1e-6), (by - ay) / math.max(L, 1e-6)
        end
        s = s - L
    end
end

-- A sub-path from distance s0 to s1.
local function Cut(pts, s0, s1)
    local out, run = {}, 0
    local x, y = PointAt(pts, s0)
    out[1] = { x, y }
    for i = 2, #pts do
        local L = math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
        run = run + L
        if run > s0 and run < s1 then out[#out + 1] = { pts[i][1], pts[i][2] } end
    end
    x, y = PointAt(pts, s1)
    out[#out + 1] = { x, y }
    return out
end

local function Length(pts)
    local n = 0
    for i = 2, #pts do n = n + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
    return n
end

-- Today's trail: cased dashes in the trail's rhythm (Look.RHYTHM) and its
-- colour a minute into the dashes (Look.Trail, your faction's), with one
-- arrow whose tip is at distance `tip` along the path.
local function Trail(pen, pts, tip, fac)
    local Look, rh, m = ns.MapLook, ns.MapLook.RHYTHM, MARK.trail
    local r, g, b, a, tk, fill = Look.Trail(C.LINE_SOLID + m.age, MARK.life, fac)
    local slot, thick = m.slot, m.thick * tk
    local function Cased(_, _, _, _, _, _, _, x1, y1, x2, y2) Look.Cased(pen.put, thick, r, g, b, a, true, x1, y1, x2, y2) end
    local total = Length(pts)
    local back = tip - rh.shaft * slot
    if back > 0 then Along(Cut(pts, 0, math.max(0, back - rh.gap * slot)), fill * slot, rh.gap * slot, Cased) end
    if tip < total then Along(Cut(pts, math.min(total, tip + rh.gap * slot), total), fill * slot, rh.gap * slot, Cased) end
    -- the arrow: its shaft, then the head's wings from the tip
    local ax, ay = PointAt(pts, math.max(0, back))
    local qx, qy, ux, uy = PointAt(pts, tip)
    Cased(nil, nil, nil, nil, nil, nil, nil, ax, -ay, qx, -qy)
    for i = 1, 2 do
        local wx, wy = Look.Wing(i, ux, -uy, fill * slot * rh.head, thick)
        Cased(nil, nil, nil, nil, nil, nil, nil, qx, -qy, qx + wx, -qy + wy)
    end
    return r, g, b
end

-- A lingering area you've left: its outline dashed like the trail, on the
-- trail's casing (DrawOutline's look).
local function Area(pen, cx, cy, rx, ry, fac)
    local Look = ns.MapLook
    local r, g, b, a, tk, fill = Look.Trail(C.LINE_SOLID + MARK.trail.age, MARK.life, fac)
    local pts = {}
    for i = 0, 40 do
        local t = i / 40 * 2 * math.pi
        pts[#pts + 1] = { cx + math.cos(t) * rx * (1 + 0.12 * math.sin(3 * t)), cy + math.sin(t) * ry * (1 + 0.1 * math.cos(2 * t)) }
    end
    local slot, thick = MARK.trail.slot, MARK.area.thick * tk
    Along(pts, slot * fill, slot * (1 - fill), function(_, _, _, _, _, _, _, x1, y1, x2, y2)
        Look.Cased(pen.put, thick, r, g, b, a, true, x1, y1, x2, y2)
    end)
end

-- Battle haze, exaggerated for teaching (spec): soft patches of the map's
-- blood red (Look.Haze) from rust to dark, at full strength.
local function Haze(pen, x, y, R, strength)
    for _, h in ipairs(MARK.haze) do
        local r, g, b = ns.MapLook.Haze(h[4])
        pen.dot(x + h[1] * R, y + h[2] * R, R * h[3] * MARK.dot, r, g, b, h[5] * strength)
    end
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local P   -- the page's frames and pools, once built

local function Pooled(list, i, make)
    local x = list[i]
    if not x then x = make() list[i] = x end
    return x
end

-- The Guild sharing switch, as Settings' Guild (3.8.3): the game's check
-- button; a preview never changes the setting.
local function ShareCheck(L)
    local g = G.share
    local cb = CreateFrame("CheckButton", nil, L, "UICheckButtonTemplate")
    Book.Box(cb, g.box[1], g.box[2], g.box[1] + g.size + 1, g.box[2] + g.size + 1)
    cb.label = Str(L, "friz", g.px, INK)
    Set(cb.label, "Guild sharing")
    Put(cb.label, g.x, g.y, "l")
    cb.state = Book.Bold(Str(L, "garb", g.state, RUBRIC))
    cb.hint = {}
    cb:SetScript("OnClick", function(self)
        if view.preview then self:SetChecked(cfg.share) return end
        ns.Dispatch("share " .. (self:GetChecked() and "on" or "off"))
        Page.LayShare()
    end)
    return cb
end

local function BuildLeft(L)
    P.kicker = Book.Caps(L, "friz", G.kicker.px, FADED, { track = G.kicker.track })
    P.kickerRules = { Book.Rule(L, 0, 1, 0, RUBRIC, 0.55), Book.Rule(L, 0, 1, 0, RUBRIC, 0.55) }
    P.title = Book.Caps(L, "morph", G.title.px, RUBRIC, { ratio = G.title.ratio, track = G.title.track, shadow = SHADOW })
    Book.Ornament(L, G.CX, G.title.orn, G.title.half)
    P.cap = Str(L, "morph", G.cap.px, RUBRIC)
    Book.Shadow(P.cap, SHADOW)
    P.words, P.figs = {}, {}

    -- the picture: its own frame, masked
    local pg = G.pic
    local x0 = pg.cx - pg.w / 2
    P.picRect = { x0, pg.top, x0 + pg.w, pg.top + pg.h }
    P.pic = CreateFrame("Frame", nil, L)
    P.pic:SetAllPoints(L)
    P.mask = P.pic:CreateMaskTexture()
    P.mask:SetTexture(Book.ART .. "map-mask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    Book.Box(P.mask, x0, pg.top, x0 + pg.w, pg.top + pg.h, P.pic)
    P.ground = {}
    P.picPen = Pen(P.pic, P.mask, x0, pg.top)

    -- the key
    P.keyFrame = CreateFrame("Frame", nil, L)
    P.keyFrame:SetAllPoints(L)
    P.keyPen = Pen(P.keyFrame, nil, 0, 0)
    P.keyLabels, P.keyGloss = {}, {}
    for i, row in ipairs(KEY) do
        local x, y = G.key.cols[(i - 1) % 2 + 1], G.key.y[math.floor((i - 1) / 2) + 1]
        local fs = Str(L, "friz", G.key.px, INK)
        Set(fs, row[2])
        Put(fs, x + G.key.text, y, "l")
        P.keyLabels[i] = fs
        if row[3] then
            local gl = Str(L, "gari", G.key.px, FADED)
            Set(gl, "(" .. row[3] .. ")")
            P.keyGloss[i] = gl
        end
    end

    -- the map button, at 24 px, and the two how-to lines
    local bt = G.button
    local half = bt.size / 2
    P.mapButton = CreateFrame("Frame", nil, L)
    Book.Box(P.mapButton, bt.cx - half, bt.cy - half, bt.cx + half, bt.cy + half, L)
    ns.MapButtonArt(P.mapButton, bt.size / 1.2 / 31)
    P.howTo = {}

    P.share = ShareCheck(L)
    P.folioL = Str(L, "gari", G.folio.px, FADED)
    Set(P.folioL, "\226\128\148 i \226\128\148")
    Put(P.folioL, G.CX, G.folio.y, "m")
end

local function BuildRight(R)
    local h = Book.Caps(R, "morph", G.head.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    h:Set("What's New", G.RCX, G.head.y, "m")
    P.head = h
    Book.Ornament(R, G.RCX, G.head.orn, G.head.half)
    P.sheet = Book.Sheet(R, G.sheet, G.win, G.cord)
    P.heads, P.topics, P.notes = {}, {}, {}
    P.footer = Str(R, "narrow", G.footer.px, FADED)
    P.folioR = Str(R, "gari", G.folio.px, FADED)
    Set(P.folioR, "\226\128\148 ii \226\128\148")
    Put(P.folioR, G.RCX, G.folio.y, "m")
end

local function Build(book)
    local L = CreateFrame("Frame", nil, book)
    L:SetAllPoints(book)
    local R = CreateFrame("Frame", nil, book)
    R:SetAllPoints(book)
    P = { L = L, R = R }
    book.news = P
    BuildLeft(L)
    BuildRight(R)
end

---------------------------------------------------------------------------
-- Left page
---------------------------------------------------------------------------

-- The first word of your name ("Lethality").
local function Me()
    local me = ns.DisplayName and ns.DisplayName(myName or "") or myName or "you"
    return (me and me:match("^%S+")) or "you"
end

-- Which page this is (spec, "The three states"), from what News knows.
local function State(list)
    local Older = ns.NewIn and ns.NewIn.Older
    local new = 0
    for _, rel in ipairs(list) do
        if view.newSince and Older and Older(view.newSince, rel[1]) then new = new + 1 end
    end
    if not (gdb and gdb.installed) then return "first", new end
    if view.newSince and new > 0 then return "update", new end
    return "settled", new
end
Page.State = State

-- The welcome's words: { text, figure } pieces; "{3.8.2}" marks a figure.
-- Wordings, the spec's first, each shorter; LayWelcome lays the first that
-- fits its four lines. Long test-build versions, a long name or a long date
-- push it down the list; the last has none of them, so it always fits
-- (Claude's call, 2026-11-28, after 3.8.5-test4's ran into the picture).
local function Welcome(state)
    local me = Me()
    if state == "first" then
        local day = ns.DateWords(time())
        return {
            ("Here begins the chronicle of %s, opened on %s. Warpath keeps it, and draws the war on the world "
                .. "map as it is fought, in these marks."):format(me, day),
            ("Here begins the chronicle of %s, opened on %s. Warpath keeps it, and draws the war on the world "
                .. "map in these marks."):format(me, day),
            ("Here begins the chronicle of %s. Warpath keeps it, and draws the war on the world map in these "
                .. "marks."):format(me),
            "Here begins your chronicle. Warpath keeps it, and draws the war on the world map in these marks.",
        }
    elseif state == "update" then
        local from, to = view.newSince, tostring(ns.VERSION)
        return {
            ("Warpath was just updated, from {%s} to {%s}. What changed is on the facing page, marked new. On "
                .. "the world map it draws %s's war in these marks."):format(from, to, me),
            ("Warpath was just updated, from {%s} to {%s}. What changed is marked new on the facing page. On "
                .. "the world map it draws these marks."):format(from, to),
            ("Warpath was updated from {%s} to {%s}. What changed is marked new on the facing page; on the "
                .. "world map, these marks."):format(from, to),
            "Warpath was just updated. What changed is marked new on the facing page. On the world map it "
                .. "draws these marks.",
        }
    end
    return {
        ("This is the chronicle of %s, kept by Warpath. On the world map it draws the war as it is fought, "
            .. "in these marks."):format(me),
        "This is your chronicle, kept by Warpath. On the world map it draws the war as it is fought, in these "
            .. "marks.",
    }
end
Page.Welcome = Welcome

-- Pieces: figures alone; a piece starting with punctuation right after a
-- figure stays joined to it.
local function Pieces(text)
    local out = {}
    local pos = 1
    while pos <= #text do
        local a, b, fig = text:find("{([^}]*)}", pos)
        local plain = text:sub(pos, (a or #text + 1) - 1)
        local first = true
        for w in plain:gmatch("%S+") do
            local glued = first and plain:sub(1, 1) ~= " " and #out > 0 and out[#out][2] or false
            out[#out + 1] = { w, false, glued }
            first = false
        end
        if not a then break end
        out[#out + 1] = { fig, true, false }
        pos = b + 1
    end
    return out
end
Page.Pieces = Pieces

local function LayHead(state, new)
    local g = G.kicker
    local text = "VERSION " .. tostring(ns.VERSION)
    if state == "first" then
        text = text .. "  \194\183  A NEW CHRONICLE"
    elseif state == "update" then
        text = text .. "  \194\183  " .. ns.NumberWord(new):upper() .. " NEW RELEASE" .. (new == 1 and "" or "S")
    end
    local w = P.kicker:Set(text:upper(), G.CX, g.y, "m")
    local y = g.y + g.dy
    Book.Box(P.kickerRules[1], math.floor(G.CX - w / 2 - g.gap - g.rule), y, math.floor(G.CX - w / 2 - g.gap), y + 1)
    Book.Box(P.kickerRules[2], math.floor(G.CX + w / 2 + g.gap), y, math.floor(G.CX + w / 2 + g.gap + g.rule), y + 1)
    P.kickerText = text
    P.title:Set(state == "first" and "Welcome to Warpath" or (state == "update" and "Welcome Back" or "Warpath"),
        G.CX, G.title.y, "m")
end

-- The welcome under its sunk initial, wrapped by hand (the design's
-- rich_dropcap): each piece its own string, figures in EB Garamond Bold.
local function LayOne(text)
    local wg, cg = G.welcome, G.cap
    local letter = text:sub(1, 1)
    Set(P.cap, letter:upper())
    Put(P.cap, cg.x, wg.top + (cg.lines - 1) * wg.lh, "l")
    local cw = Wpx(P.cap)
    local ind = {}
    for i = 1, cg.lines - 1 do ind[i] = (Book.STEM[letter:upper()] or 1) * cw + cg.stem end
    ind[cg.lines] = cw + cg.foot
    local function Wide(pc) return pc[2] and Measure("garb", wg.fig, pc[1]) + 1 or Measure("friz", wg.px, pc[1]) end
    local sp = Measure("friz", wg.px, " ")
    local x1 = G.L0 + wg.width
    local n, y = 1, wg.top
    local x = G.L0 + ind[1]
    local nw, nf = 0, 0
    for i, pc in ipairs(Pieces(text:sub(2))) do
        local first = i == 1
        local need = Wide(pc) + ((first or pc[3]) and 0 or sp)
        if x + need > x1 and not first then
            n, y = n + 1, y + wg.lh
            x = G.L0 + (ind[n] or 0)
        elseif not first and not pc[3] then
            x = x + sp
        end
        local fs
        if pc[2] then
            nf = nf + 1
            fs = Pooled(P.figs, nf, function() return Book.Bold(Str(P.L, "garb", wg.fig, RUBRIC)) end)
        else
            nw = nw + 1
            fs = Pooled(P.words, nw, function() return Str(P.L, "friz", wg.px, INK) end)
        end
        Set(fs, pc[1])
        Put(fs, x, y, "l")
        fs:Show()
        if fs.twin then fs.twin:Show() end
        fs.line = n
        x = x + Wide(pc)
    end
    for k = nw + 1, #P.words do P.words[k]:Hide() end
    for k = nf + 1, #P.figs do P.figs[k]:Hide() P.figs[k].twin:Hide() end
    P.welcomeLines, P.welcomeEnd = n, y
    return n <= wg.lines
end

Page.LayOne = function(text) return LayOne(text) end

-- The first wording that fits; the last one if none does.
local function LayWelcome(list)
    for i, text in ipairs(list) do
        if LayOne(text) or i == #list then
            P.welcome, P.welcomeChoice = text, i
            return
        end
    end
end

local function LayPicture()
    local pen, r = P.picPen, P.picRect
    local w, h = r[3] - r[1], r[4] - r[2]
    local function At(p) return p[1] * w, p[2] * h end
    -- the ground, printed in sepia
    P.printN = Book.WorldPrint(function(i, blend)
        local t = P.ground[i]
        if not t then
            t = P.pic:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:AddMaskTexture(P.mask)
            P.ground[i] = t
        end
        t:SetBlendMode(blend or "MOD")
        t:SetDesaturated(false)
        t:SetVertexColor(1, 1, 1, 1)
        t:Show()
        return t
    end, 1, CROP, r[1], r[2], w, h, P.pic)
    for k = P.printN, #P.ground do P.ground[k]:Hide() end
    -- the marks
    local fac = ns.faction
    pen.reset()
    for _, hz in ipairs(SCENE.haze) do
        local x, y = At(hz)
        Haze(pen, x, y, hz[3], hz[4])
    end
    local function Pts(list)
        local out = {}
        for i, p in ipairs(list) do out[i] = { At(p) } end
        return out
    end
    Road(pen, Pts(SCENE.road), 1, fac)
    Flight(pen, Pts(SCENE.flight))
    local trail = Pts(SCENE.trail)
    Trail(pen, trail, Nearest(trail, At(SCENE.arrow)), fac)
    Area(pen, SCENE.area[1] * w, SCENE.area[2] * h, SCENE.area[3], SCENE.area[4], fac)
    P.scenePins = {}
    for _, pin in ipairs(SCENE.pins) do
        local x, y = At({ pin[2], pin[3] })
        P.scenePins[#P.scenePins + 1] = pen.pin(pin[1], x, y, pin[4], fac)
    end
    pen.finish()
end

-- The key's samples, each in its 26 x 18 box, drawn with the same pieces.
local function LayKey()
    local pen, k, fac = P.keyPen, G.key, ns.faction
    pen.reset()
    P.keyPins, P.trailColor = {}, nil
    for i, row in ipairs(KEY) do
        local x, y = k.cols[(i - 1) % 2 + 1], G.key.y[math.floor((i - 1) / 2) + 1]
        local bx, by = x, y - 13
        local kind = row[1]
        if k.pins[kind] then
            P.keyPins[kind] = pen.pin(kind, x + 13, y - 5, k.pins[kind], fac)
        elseif kind == "road" then
            Road(pen, { { bx + 2, by + 13 }, { bx + 12, by + 8 }, { bx + 24, by + 6 } }, 1, fac)
        elseif kind == "trail" then
            local pts = { { bx + 1, by + 12 }, { bx + 25, by + 6 } }
            P.trailColor = { Trail(pen, pts, Nearest(pts, bx + 14, by + 9) + 4, fac) }
        elseif kind == "area" then
            Area(pen, bx + 13, by + 9, 10, 6, fac)
        elseif kind == "flight" then
            Flight(pen, { { bx + 1, by + 12 }, { bx + 25, by + 6 } })
        elseif kind == "haze" then
            Haze(pen, bx + 13, by + 9, 7.5, 1)
        end
        local gl = P.keyGloss[i]
        if gl then Put(gl, x + k.text + Wpx(P.keyLabels[i]) + k.gloss, y, "l") end
    end
    pen.finish()
end

-- Wrapped by hand at a width; "~" joins two words that mustn't part.
local function Wrap(face, px, text, width)
    local lines, line = {}, ""
    for w in text:gmatch("%S+") do
        local cand = line == "" and w or (line .. " " .. w)
        if line ~= "" and Measure(face, px, (cand:gsub("~", " "))) > width then
            lines[#lines + 1] = line
            line = w
        else
            line = cand
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    for i, l in ipairs(lines) do lines[i] = l:gsub("~", " ") end
    return lines
end
Page.Wrap = Wrap

-- The how-to lines: each starts a line of its own; a wrapped one carries on
-- below, at the same indent, and the next follows it. If that would reach
-- Guild sharing, a pixel smaller, then another (Claude's call).
local function HowToLines(px)
    local out = {}
    for k, text in ipairs(HOWTO) do
        for i, line in ipairs(Wrap("friz", px, text, G.button.right - G.button.x)) do
            out[#out + 1] = { line, k, i == 1 }
        end
    end
    return out
end

local function LayHowTo()
    local bt = G.button
    local px = bt.px
    local lines = HowToLines(px)
    while bt.y + (#lines - 1) * bt.lh > bt.last and px > bt.px - 3 do
        px = px - 1
        lines = HowToLines(px)
    end
    P.mapLine, P.bookLine, P.howToPx = nil, nil, px
    for n, l in ipairs(lines) do
        local fs = Pooled(P.howTo, n, function() return Str(P.L, "friz", bt.px, INK) end)
        Book.Face(fs, "friz", px)
        Set(fs, l[1])
        Put(fs, bt.x, bt.y + (n - 1) * bt.lh, "l")
        fs:Show()
        if l[3] then
            if l[2] == 1 then P.mapLine = fs else P.bookLine = fs end
        end
    end
    for k = #lines + 1, #P.howTo do P.howTo[k]:Hide() end
    P.howToEnd = bt.y + (#lines - 1) * bt.lh
end
Page.HOWTO = HOWTO

function Page.LayShare()
    local cb, g = P.share, G.share
    cb:SetChecked(cfg and cfg.share and true or false)
    Set(cb.state, cfg and cfg.share and "on" or "off")
    local sx = g.x + Wpx(cb.label) + g.gap
    Put(cb.state, sx, g.y, "l")
    -- the label and its state click the box too
    pcall(cb.SetHitRectInsets, cb, 0, -((sx + Wpx(cb.state) - (g.box[1] + g.size + 1)) / 1.2), 0, 0)
    local hint = g.hint
    for i, line in ipairs(Wrap("gari", hint.px, SHARE_HINT, hint.width)) do
        local fs = Pooled(cb.hint, i, function() return Str(P.L, "gari", hint.px, FADED) end)
        Set(fs, line)
        Put(fs, g.x, hint.y + (i - 1) * hint.lh, "l")
        fs:Show()
    end
end

---------------------------------------------------------------------------
-- Right page: What's New on the sheet
---------------------------------------------------------------------------

local function Recolor(caps, col, shadow)
    caps.col, caps.shadow = col, shadow
    for _, l in ipairs(caps.letters) do
        Book.Color(l, col)
        if shadow then Book.Shadow(l, shadow) else l:SetShadowOffset(0, 0) end
    end
end

local function Head(i)
    return Pooled(P.heads, i, function()
        local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
        local h = CreateFrame("Frame", nil, ch)
        h.caps = Book.Caps(h, "morph", G.rel.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
        h.ruleL = Book.Solid(h, "ARTWORK", RUBRIC, 0.5)
        h.ruleR = Book.Solid(h, "ARTWORK", RUBRIC, 0.5)
        h.dia = { Book.Diamond(h, 0, 0, 3, Book.GILT, Book.GILT_EDGE, "ARTWORK", ch, ox, oy),
            Book.Diamond(h, 0, 0, 3, Book.GILT, Book.GILT_EDGE, "ARTWORK", ch, ox, oy) }
        h.title = Str(h, "gari", 17, FADED)
        return h
    end)
end

local function Topic(i)
    return Pooled(P.topics, i, function()
        local t = CreateFrame("Frame", nil, P.sheet.child)
        t.caps = Book.Caps(t, "friz", G.topic.px, FADED, { track = G.topic.track })
        t.rule = Book.Solid(t, "ARTWORK", FADED, 0.3)
        return t
    end)
end

local function Note(i)
    return Pooled(P.notes, i, function()
        local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
        local n = CreateFrame("Frame", nil, ch)
        n.mark = Book.Lozenge(n, G.note.mw, G.note.mh, RUBRIC, "ARTWORK", ch, ox, oy)
        n.lines = {}
        return n
    end)
end

local function Divider()
    if not P.divider then
        local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
        local d = CreateFrame("Frame", nil, ch)
        d.band = Book.Band(d, ch, ox, oy, 150 / 255)
        d.text = Str(d, "gari", G.divider.px, RUBRIC)
        d.rule = Book.Solid(d, "ARTWORK", GILT_RULE, 0.9)
        P.divider = d
    end
    return P.divider
end

local function LayRelease(rel, y, new, read, nh)
    local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
    local x0, x1 = G.col[1], G.col[2]
    local cx = (x0 + x1) / 2
    local g = G.rel
    local h = Head(nh)
    local col = read and READ_HEAD or RUBRIC
    Recolor(h.caps, col, not read and SHADOW or nil)
    local w = h.caps:Set("Version " .. rel[1], cx, y, "m", ch, ox, oy)
    Recolor(h.caps, col, not read and SHADOW or nil)
    local r, gg, b = Book.RGB(col)
    h.ruleL:SetColorTexture(r, gg, b, 0.5)
    h.ruleR:SetColorTexture(r, gg, b, 0.5)
    Book.Box(h.ruleL, math.floor(x0 + 8), y + g.dy, math.floor(cx - w / 2 - g.rule), y + g.dy + 1, ch, ox, oy)
    Book.Box(h.ruleR, math.floor(cx + w / 2 + g.rule), y + g.dy, math.floor(x1 - 8), y + g.dy + 1, ch, ox, oy)
    for k, d in ipairs(h.dia) do
        Book.MoveDiamond(d, cx + (k == 1 and -1 or 1) * (w / 2 + g.dia), y + g.dy)
        Book.ShowDiamond(d, new)
    end
    h.new, h.read, h.version = new, read, rel[1]
    local bottom = y + 8
    if rel.title then
        Set(h.title, rel.title)
        Put(h.title, cx, y + g.title, "m", ch, ox, oy)
        h.title:Show()
        bottom = y + g.title + 6
    else
        h.title:Hide()
    end
    Book.Box(h, x0, y - 22, x1, bottom, ch, ox, oy)
    h:Show()
    P.sheet:Add(h, y - 22 - oy, bottom - oy)
    return y + (rel.title and g.titled or g.after)
end

local function LayNotes(rel, y, read, counts)
    local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
    local x1, ng, tg = G.col[2], G.note, G.topic
    local first = true
    for _, text in ipairs(rel[2]) do
        local topic = text:sub(1, 3) == "## " and text:sub(4)
        if topic then
            y = y + (first and 0 or tg.before)
            counts.t = counts.t + 1
            local t = Topic(counts.t)
            local ty = y + tg.dy
            local w = t.caps:Set(topic:upper(), tg.x, ty, "l", ch, ox, oy)
            Book.Box(t.rule, math.floor(tg.x + w + 8), ty - 4, math.max(math.floor(tg.x + w + 8) + 0.01, x1), ty - 3, ch, ox, oy)
            Book.Box(t, tg.x, ty - 12, x1, ty + 4, ch, ox, oy)
            t:Show()
            P.sheet:Add(t, ty - 12 - oy, ty + 4 - oy)
            y = y + tg.step
        else
            counts.n = counts.n + 1
            local n = Note(counts.n)
            n.mark:Color(read and READ_MARK or RUBRIC)
            n.mark:Move(ng.mark, y - ng.px * 0.34)
            local lines = Wrap("friz", ng.px, text, x1 - ng.x)
            for i, line in ipairs(lines) do
                local fs = Pooled(n.lines, i, function() return Str(n, "friz", ng.px, INK) end)
                Set(fs, line)
                Book.Color(fs, read and READ_NOTE or INK)
                Put(fs, ng.x, y + (i - 1) * ng.lh, "l", ch, ox, oy)
                fs:Show()
            end
            for i = #lines + 1, #n.lines do n.lines[i]:Hide() end
            n.text, n.read = text, read
            Book.Box(n, ng.mark - 5, y - 16, x1, y + (#lines - 1) * ng.lh + 5, ch, ox, oy)
            n:Show()
            P.sheet:Add(n, y - 16 - oy, y + (#lines - 1) * ng.lh + 5 - oy)
            y = y + #lines * ng.lh
        end
        first = false
    end
    return y
end

local function LayDivider(y, since)
    local ch, ox, oy = P.sheet.child, G.win[1], G.win[2]
    local x0, x1, dg = G.col[1], G.col[2], G.divider
    local d = Divider()
    y = y + dg.before
    d.band:Set(x0 - 8, x1 + 6, y + dg.band[1], y + dg.band[2], true, true)
    Set(d.text, "read before, at version " .. since)
    Put(d.text, (x0 + x1) / 2, y, "m", ch, ox, oy)
    Book.Box(d.rule, x0 + dg.inset, y + dg.rule, x1 - dg.inset, y + dg.rule + 1, ch, ox, oy)
    Book.Box(d, x0 - 8, y + dg.band[1], x1 + 6, y + dg.band[2], ch, ox, oy)
    d.y = y
    d:Show()
    P.sheet:Add(d, y + dg.band[1] - oy, y + dg.band[2] - oy)
    return y + dg.after
end

local function LayNews(list, state, new)
    local Older = ns.NewIn and ns.NewIn.Older
    local sheet = P.sheet
    sheet:Clear()
    local y = G.win[2] + G.first
    local counts = { h = 0, t = 0, n = 0 }
    local crossed = false
    P.order = {}
    for i = #list, 1, -1 do
        local rel = list[i]
        local isNew = state == "update" and Older and Older(view.newSince, rel[1]) and true or false
        local read = state == "update" and not isNew
        if read and not crossed then
            crossed = true
            y = LayDivider(y, view.newSince)
        end
        counts.h = counts.h + 1
        y = LayRelease(rel, y, isNew, read, counts.h)
        y = LayNotes(rel, y, read, counts) + G.between
        P.order[#P.order + 1] = rel[1]
    end
    if P.divider then P.divider:SetShown(crossed) end
    P.dividerShown = crossed
    for k = counts.h + 1, #P.heads do P.heads[k]:Hide() end
    for k = counts.t + 1, #P.topics do P.topics[k]:Hide() end
    for k = counts.n + 1, #P.notes do P.notes[k]:Hide() end
    P.contentEnd = y
    sheet:SetContent(y - G.win[2] + G.tail)
    local n = #list
    Set(P.footer, n .. " release" .. (n == 1 and "" or "s") .. (state == "update" and ("  \194\183  " .. new .. " new") or ""))
    Put(P.footer, G.footer.x, G.footer.y, "r")
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function Render()
    local book = Chron.book
    book.left.number:SetText("")
    book.right.number:SetText("")
    local list = ns.NewIn and ns.NewIn.List or {}
    local state, new = State(list)
    P.state = state
    LayHead(state, new)
    LayWelcome(Welcome(state))
    LayPicture()
    LayKey()
    LayHowTo()
    Page.LayShare()
    LayNews(list, state, new)
end

Chron.pages.warpath = {
    Build = Build,
    Render = Render,
    -- it opens at the top, where the newest release is
    Reset = function() if P then P.sheet.scroll = 0 end end,
}

function Page.Frames() return P end
