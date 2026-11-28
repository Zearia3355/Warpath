-- Warpath: the chronicle's Grudges tab (3.8.5)
-- As docs/design/chronicle-grudges.md sets it (look R2a, empty page E1):
-- the grudges on an inset sheet with the chosen one's ribbon bookmark
-- (left); the chosen grudge's portrait, account and note, then every
-- grudge's encounters merged on a second sheet, the chosen one's lines
-- washed (right). With no grudge held, the left page is prose with a drop
-- cap and the right keeps the portrait's place, blind-tooled.
--
-- Every position is the spec's, in render px (Book.X/Y convert), and the
-- spec's tables are GEOMETRY below, which a test checks the built page
-- against. Names are shown only through ns.DisplayName; the saved keys are
-- never changed here.
local ADDON, ns = ...
local C = ns.C
local MapName, UISound, Waypoint = ns.MapName, ns.UISound, ns.Waypoint
local Grudge = ns.Grudge
local Book, Chron = ns.Book, ns.Chron
local view = Chron.view
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC, SHADOW, LEVEL = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW, Book.LEVEL

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local Page = {}
ns.ChronGrudges = Page

-- The spec's geometry (render px on the 1092x748 design canvas; y are
-- baselines unless named top). Code and spec are compared by a test.
local G = {
    L0 = 82, LR = 510, CX = 296, R0 = 586, RR = 1017, RCX = 801,
    head = { y = 120, px = 25, orn = 133, half = 110 },
    kicker = { y = 158, px = 12, track = 1.2, rule = 18, gap = 12, dy = -4, empty = 40 },
    sheet = { 72, 176, 518, 652 },
    win = { 74, 197, 516, 649 },
    cord = { 509, 203, 643 },
    legend = { x = 496, y = 194, px = 14 },
    row = { h = 46, first = 213, pad = 16, tail = 8, x0 = 76, x1 = 498, wash = 44, tile = 84, tdy = 8, size = 26,
        name = 120, ndy = 22, gap = 6, sdy = 39, tally = 494, side = 6, rdy = 45 },
    ribbon = { x = 72, dy0 = 4, dy1 = 40, min = 196, max = 622 },
    inscribe = { 211, 676, 381, 698 },
    portrait = { x = 769, y = 92, size = 64 },
    name = { y = 192, px = 31, min = 25, fit = 411 },
    orn = { y = 209, half = 120 },
    who = { y = 233, px = 18 },
    since = { y = 254, rule = 24 },
    acct = { x0 = 616, x1 = 987, y = 284, lh = 26 },
    note = { y = 394, rule = 400, w = 380 },
    enc = { y = 428, px = 21, orn = 441, half = 90 },
    lsheet = { 576, 446, 1025, 662 },
    lwin = { 578, 449, 1023, 659 },
    lcord = { 1016, 455, 653 },
    log = { x0 = 586, x1 = 1001, start = 445, day = 18, dayAfter = 4, line = 23, tail = 14, glyph = 593, gdy = -5,
        time = 606, text = 644, slewGap = 5, band = { 580, 1005, -17, 6 } },
    way = { 592, 676, 792, 698 },
    forgive = { 901, 676, 1011, 698 },
    empty = { x0 = 92, width = 408, y = 262, lh = 22, px = 18, capPx = 80, orn = 16, half = 70, offer = 58,
        offerLh = 22, offerGap = 12, nothing = 560 },
    blind = { x = 769, y = 92, size = 64 },
    noname = { y = 192, px = 25, lines = { 250, 272, 294 } },
}
Page.GEOMETRY = G

local WASH = { 70, 50, 44 }            -- the chosen wash: 16% toward it (hover 8%)
local GILT_A = 150 / 255               -- the gilt band's strength
local NEAR = 3600                      -- a sighting under an hour old: the sub-line in rubric
local WEEK = 7 * 86400

-- The drop cap's stem as a share of its width (ChronCampaigns' table,
-- type.py stem()): lines 1-2 tuck to the stem for L, T, F and P.
local STEM = { L = 0.583, T = 0.981, F = 0.933, P = 0.959 }

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

local function Cap(s) return (s:gsub("^%l", string.upper)) end

local function Times(n) return n == 1 and "once" or n == 2 and "twice" or (ns.NumberWord(n) .. " times") end

local function Me()
    local me = ns.DisplayName and ns.DisplayName(myName or "") or myName
    return (me and me:match("^%S+")) or "You"
end

local function MonthDay(t)
    local d = date("*t", t)
    return ns.MonthName(d.month) .. " " .. d.day
end

-- "Nov 19"
local function ShortDate(t)
    local d = date("*t", t)
    return ns.MonthName(d.month):sub(1, 3) .. " " .. d.day
end

-- "Saturday, November 21"
local function LongDate(t)
    local d = date("*t", t)
    return ns.DayName(d.wday) .. ", " .. ns.MonthName(d.month) .. " " .. d.day
end

local function Clock(t) return date("%H:%M", t) end

-- "20 minutes ago", "an hour ago", "3 hours ago", "yesterday", "5 days ago"
local function AgoWords(t)
    local s = math.max(0, time() - t)
    if s < 3600 then return math.max(1, math.floor(s / 60)) .. " minutes ago" end
    if s < 86400 then return s >= 7200 and (math.floor(s / 3600) .. " hours ago") or "an hour ago" end
    local d = math.floor(s / 86400)
    return d == 1 and "yesterday" or (d .. " days ago")
end

local function Zone(z) return z and Cap(MapName(z) or "") or "" end

local function LastSeen(r)
    if r.seen then return Zone(r.seen.z) .. ", " .. AgoWords(r.seen.t) end
    return "not seen since " .. ShortDate(r.added or time())
end
Page.LastSeen = LastSeen

local function WhoLine(r)
    local bits = {}
    if r.lv then bits[#bits + 1] = "Level " .. (r.lv == -1 and "??" or tostring(r.lv)) end
    if r.ra then bits[#bits + 1] = r.ra end
    if r.class then bits[#bits + 1] = ns.ClassName(r.class) end
    local s = #bits > 0 and table.concat(bits, " ") or "Class unknown"
    if r.gu then s = s .. "  \194\183  <" .. r.gu .. ">" end
    return s
end
Page.WhoLine = WhoLine

local function SettledLately(r)
    local now = time()
    for _, e in ipairs(r.log or {}) do
        if e.k == "k" and now - (e.t or 0) < WEEK then return true end
    end
    return false
end
Page.SettledLately = SettledLately

---------------------------------------------------------------------------
-- The data: the list, the global log
---------------------------------------------------------------------------

local Samples

local function GrudgeList()
    if view.preview then return Samples(time()) end
    local list = Grudge.List()
    table.sort(list, function(a, b)
        local ta = a.r.seen and a.r.seen.t or a.r.added or 0
        local tb = b.r.seen and b.r.seen.t or b.r.added or 0
        if ta ~= tb then return ta > tb end
        return a.full < b.full
    end)
    return list
end
Page.List = GrudgeList

-- Every grudge's encounters, newest first (ties keep the list's order). A
-- grudge whose log has no inscription (from before the log, 3.5) gets one
-- line, dated when it was added (Claude's call).
local function GlobalLog(list)
    local ev = {}
    for i, item in ipairs(list) do
        local r, has = item.r, false
        for j, e in ipairs(r.log or {}) do
            if e.k == "g" or e.k == "a" then has = true end
            ev[#ev + 1] = { t = e.t or 0, k = e.k, z = e.z, item = item, i = i, j = j }
        end
        if not has then
            ev[#ev + 1] = { t = r.added or 0, k = r.auto and "a" or "g", item = item, i = i, j = math.huge }
        end
    end
    table.sort(ev, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        if a.i ~= b.i then return a.i < b.i end
        return a.j < b.j
    end)
    return ev
end
Page.GlobalLog = GlobalLog

-- The log as rows under day headings, each with its baseline (render px,
-- unscrolled), and the content's height.
local function LogRows(ev)
    local L = G.log
    local rows, day, y = {}, nil, L.start
    local today = date("%Y%m%d")
    for _, e in ipairs(ev) do
        local d = date("%Y%m%d", e.t)
        if d ~= day then
            day = d
            y = y + L.day
            rows[#rows + 1] = { day = d == today and "Today" or MonthDay(e.t), y = y }
            y = y + L.dayAfter
        end
        y = y + L.line
        rows[#rows + 1] = { e = e, y = y }
    end
    return rows, #ev > 0 and (y + L.tail - G.lwin[2]) or 0
end
Page.LogRows = LogRows

---------------------------------------------------------------------------
-- Small shapes from 1 px rows (the glyphs, the ribbon): too small for any
-- texture to beat, as the kit's chevron
---------------------------------------------------------------------------

local Spans = {}
Spans.__index = Spans

local function NewSpans(parent, layer, sub)
    return setmetatable({ parent = parent, layer = layer or "OVERLAY", sub = sub, tex = {}, n = 0 }, Spans)
end

function Spans:Begin(rel, ox, oy) self.n, self.rel, self.ox, self.oy = 0, rel, ox, oy end

function Spans:Add(x0, y0, x1, y1, col, a)
    if x1 - x0 < 0.05 then return end
    self.n = self.n + 1
    local t = self.tex[self.n]
    if not t then
        t = self.parent:CreateTexture(nil, self.layer, nil, self.sub)
        self.tex[self.n] = t
    end
    local r, g, b = Book.RGB(col)
    t:SetColorTexture(r, g, b, a or 1)
    Book.Box(t, x0, y0, x1, y1, self.rel, self.ox, self.oy)
    t:Show()
end

function Spans:End() for i = self.n + 1, #self.tex do self.tex[i]:Hide() end end
function Spans:Hide() self.n = 0 self:End() end

-- A polygon filled row by row, each row sampled at its middle.
function Spans:Poly(pts, col, a)
    local y0, y1 = math.huge, -math.huge
    for _, p in ipairs(pts) do y0, y1 = math.min(y0, p[2]), math.max(y1, p[2]) end
    for r = math.floor(y0), math.ceil(y1) - 1 do
        local yc, xs = r + 0.5, {}
        for i = 1, #pts do
            local p, q = pts[i], pts[i % #pts + 1]
            if (p[2] <= yc and q[2] > yc) or (q[2] <= yc and p[2] > yc) then
                xs[#xs + 1] = p[1] + (yc - p[2]) * (q[1] - p[1]) / (q[2] - p[2])
            end
        end
        table.sort(xs)
        for i = 1, #xs - 1, 2 do self:Add(xs[i], r, xs[i + 1], r + 1, col, a) end
    end
end

-- An ellipse in the box [x0,x1] x [y0,y1]; ring: an outline that wide.
function Spans:Ellipse(x0, y0, x1, y1, col, a, ring)
    local cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    for r = math.floor(y0), math.ceil(y1) - 1 do
        local d = (r + 0.5 - cy) / ry
        if math.abs(d) < 1 then
            local hw = rx * math.sqrt(1 - d * d)
            local di = ring and (r + 0.5 - cy) / (ry - ring)
            if ring and ry > ring and math.abs(di) < 1 then
                local ihw = (rx - ring) * math.sqrt(1 - di * di)
                self:Add(cx - hw, r, cx - ihw, r + 1, col, a)
                self:Add(cx + ihw, r, cx + hw, r + 1, col, a)
            else
                self:Add(cx - hw, r, cx + hw, r + 1, col, a)
            end
        end
    end
end

-- The log's glyphs, 12 px, centred on (x, y) (gparts.glyph): d a skull in
-- rubric, s an eye in faded ink, g/a a quill nib in faded ink. (k, the gilt
-- diamond, is a kit diamond.)
local HOLE = { 236, 200, 140 }
local function Glyph(sp, kind, x, y)
    local s = 12
    if kind == "d" then
        sp:Ellipse(x - s * 0.42, y - s * 0.5, x + s * 0.42, y + s * 0.22, RUBRIC)
        sp:Poly({ { x - s * 0.24, y + s * 0.1 }, { x + s * 0.24, y + s * 0.1 }, { x + s * 0.24, y + s * 0.42 },
            { x - s * 0.24, y + s * 0.42 } }, RUBRIC)
        for _, ex in ipairs({ -0.17, 0.17 }) do
            sp:Ellipse(x + ex * s - s * 0.11, y - s * 0.17, x + ex * s + s * 0.11, y + s * 0.05, HOLE)
        end
    elseif kind == "s" then
        sp:Ellipse(x - s * 0.5, y - s * 0.26, x + s * 0.5, y + s * 0.26, FADED, 1, 1)
        sp:Ellipse(x - s * 0.15, y - s * 0.15, x + s * 0.15, y + s * 0.15, FADED)
    elseif kind == "g" or kind == "a" then
        sp:Poly({ { x - s * 0.1, y + s * 0.5 }, { x + s * 0.45, y - s * 0.5 }, { x + s * 0.12, y - s * 0.1 } }, FADED)
    end
end

-- The chosen row's bookmark (directions.ribbon): a crimson ribbon end
-- across the sheet's left edge at x, with a V notch.
local function Ribbon(sp, x, y0, y1)
    local mid = (y0 + y1) / 2
    sp:Poly({ { x - 9, y0 }, { x + 5, y0 }, { x + 5, y1 }, { x - 9, y1 }, { x - 4, mid } }, { 46, 6, 4 })
    sp:Poly({ { x - 8, y0 + 1 }, { x + 4, y0 + 1 }, { x + 4, y1 - 1 }, { x - 8, y1 - 1 }, { x - 3, mid } }, { 146, 24, 14 })
    sp:Add(x - 6, y0 + 2, x + 4, y0 + 3, { 206, 72, 48 })
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

-- The query tile's "?" sized to the tile (gparts.tile): Morpheus at 70%.
local function QueryFit(tile, x, y, size, class)
    if class then return end
    local px = math.floor(size * 0.7)
    if tile.q.bpx ~= px then Book.Face(tile.q, "morph", px) end
    Book.Shadow(tile.q, { 40, 6, 4 })
    Put(tile.q, x + size / 2, y + size * 0.8, "m", tile.rel, tile.ox, tile.oy)
end

-- A kicker: letterspaced capitals with a short rubric rule each side.
local function Kicker(parent)
    return { caps = Book.Caps(parent, "friz", G.kicker.px, FADED, { track = G.kicker.track }),
        rules = { Book.Rule(parent, 0, 1, 0, RUBRIC, 0.55), Book.Rule(parent, 0, 1, 0, RUBRIC, 0.55) } }
end

local function SetKicker(k, text, cx, y, half)
    local w = k.caps:Set(text:upper(), cx, y, "m")
    local g, ry = G.kicker, y + G.kicker.dy
    Book.Box(k.rules[1], math.floor(cx - w / 2 - g.gap - half), ry, math.floor(cx - w / 2 - g.gap), ry + 1)
    Book.Box(k.rules[2], math.floor(cx + w / 2 + g.gap), ry, math.floor(cx + w / 2 + g.gap + half), ry + 1)
    k.width = w
    return w
end

local function Tip(owner, item, coords)
    if not (item and GameTooltip) then return end
    local r = item.r
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local cr, cg, cb = 0.9, 0.9, 0.9
    if r.class then cr, cg, cb = ns.ClassColor(r.class) end
    GameTooltip:AddLine(ns.DisplayName(item.full), cr, cg, cb)
    GameTooltip:AddLine(WhoLine(r), 1, 1, 1)
    GameTooltip:AddLine(("Slain %s \194\183 fell %s \194\183 settled %s"):format(Times(r.kills or 0), Times(r.deaths or 0),
        Times(r.settled or 0)), 1, 0.82, 0)
    local seen = "Last seen: " .. LastSeen(r)
    if coords and r.seen and r.seen.x and r.seen.y then
        seen = seen .. (" (%.1f, %.1f)"):format(r.seen.x * 100, r.seen.y * 100)
    end
    GameTooltip:AddLine(seen, 0.8, 0.8, 0.8)
    if r.note then GameTooltip:AddLine("\226\128\156" .. r.note .. "\226\128\157", 1, 1, 1, true) end
    GameTooltip:Show()
end
Page.Tip = Tip

local Render
local function Choose(i, scrollList)
    local item = view.grudges[i]
    if not item then return end
    view.pick, P.pickKey = i, item.full
    if scrollList then
        local s, top = P.lsheet, G.row.pad + (i - 1) * G.row.h
        local h = s:Height()
        if top - G.row.pad < s.scroll then s.scroll = top - G.row.pad
        elseif top + G.row.h + G.row.tail > s.scroll + h then s.scroll = top + G.row.h + G.row.tail - h end
    end
    UISound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
    Render()
end
Page.Choose = Choose

local function BuildLeft(L)
    P.head = Book.Caps(L, "morph", G.head.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    P.head:Set("Grudges", G.CX, G.head.y, "m")
    Book.Ornament(L, G.CX, G.head.orn, G.head.half)
    P.kicker = Kicker(L)

    -- the list, on its sheet (hidden with the sheet when nothing is held)
    local F = CreateFrame("Frame", nil, L)
    F:SetAllPoints(L)
    P.listF = F
    P.lsheet = Book.Sheet(F, G.sheet, G.win, G.cord)
    P.lsheet.step = G.row.h
    P.legend = Str(F, "gari", G.legend.px, FADED)
    Set(P.legend, "slew \194\183 fell")
    Put(P.legend, G.legend.x, G.legend.y, "r")
    P.rows = {}
    local rf = CreateFrame("Frame", nil, F)
    rf:SetAllPoints(F)
    rf:SetFrameLevel(P.lsheet.frame:GetFrameLevel() + 3)
    P.ribbon = NewSpans(rf, "OVERLAY")

    -- the empty page: prose round a drop cap, an ornament, the ways in
    local E = CreateFrame("Frame", nil, L)
    E:SetAllPoints(L)
    P.emptyL = E
    P.cap = Str(E, "morph", G.empty.capPx, RUBRIC)
    Book.Shadow(P.cap, SHADOW)
    P.prose, P.offer, P.orns = {}, {}, {}

    local ins = CreateFrame("Button", nil, L, "UIPanelButtonTemplate")
    Book.Box(ins, G.inscribe[1], G.inscribe[2], G.inscribe[3], G.inscribe[4])
    ins:SetText("Inscribe a name...")
    ins:SetScript("OnClick", function() if not view.preview then StaticPopup_Show("WARPATH_GRUDGE_NAME") end end)
    P.inscribe = ins
end

local function BuildNote(E)
    local n = G.note
    P.noteText = Str(E, "gari", 18, INK)
    P.noteHint = Str(E, "gari", 17, FADED)
    Set(P.noteHint, "Click to write a note about them...")
    Put(P.noteHint, G.RCX, n.y, "m")
    P.noteRule = Book.Rule(E, G.RCX - n.w / 2, G.RCX + n.w / 2, n.rule, FADED, 0.3)
    local hit = CreateFrame("Button", nil, E)
    Book.Box(hit, G.RCX - n.w / 2, n.y - 20, G.RCX + n.w / 2, n.rule + 2)
    P.noteHit = hit
    local box = CreateFrame("EditBox", nil, E)
    Book.Box(box, G.RCX - n.w / 2, n.y - 20, G.RCX + n.w / 2, n.rule)
    box:SetAutoFocus(false)
    box:SetMaxLetters(120)
    Book.Face(box, "gari", 18)        -- a game font first; Garamond once it loads
    box:SetTextColor(Book.RGB(INK))
    box:SetJustifyH("CENTER")
    box:Hide()
    P.noteBox = box
    hit:SetScript("OnClick", function()
        if view.preview or not P.item then return end
        box.full, box.cancel = P.item.full, nil
        box:SetText(P.item.r.note or "")
        P.noteText:Hide()
        P.noteHint:Hide()
        box:Show()
        box:SetFocus()
    end)
    local function Done(self)
        if not self:IsShown() then return end
        if not self.cancel and self.full and not view.preview then Grudge.SetNote(self.full, self:GetText()) end
        self:Hide()
        Render()
    end
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() Done(self) end)
    box:SetScript("OnEscapePressed", function(self) self.cancel = true self:ClearFocus() Done(self) end)
    box:SetScript("OnEditFocusLost", Done)
end

local function BuildEntry(R)
    local E = CreateFrame("Frame", nil, R)
    E:SetAllPoints(R)
    P.entry = E
    P.portrait = Book.Tile(E, E, Book.OX, Book.OY)
    P.titles = {}
    P.who = Str(E, "gari", G.who.px, FADED)
    P.since = Kicker(E)
    P.acct = {}
    for i = 1, 3 do P.acct[i] = Book.Reckon(E) end
    P.seenLab = Str(E, "friz", 18, INK)
    P.seenVal = Str(E, "gari", 18, INK)
    P.seenRule = Book.Solid(E, "ARTWORK", INK, 0.38)
    P.seenHit = CreateFrame("Button", nil, E)
    P.seenHit:SetScript("OnEnter", function(self) if not view.preview then Tip(self, P.item, true) end end)
    P.seenHit:SetScript("OnLeave", GameTooltip_Hide)
    BuildNote(E)

    local way = CreateFrame("Button", nil, E, "UIPanelButtonTemplate")
    Book.Box(way, G.way[1], G.way[2], G.way[3], G.way[4])
    way:SetText("Waypoint to last sighting")
    way:SetScript("OnClick", function()
        local s = P.item and P.item.r.seen
        if s and not view.preview then Waypoint(s.z, s.x, s.y, "where you last saw " .. ns.DisplayName(P.item.full)) end
    end)
    P.way = way
    local forgive = CreateFrame("Button", nil, E, "UIPanelButtonTemplate")
    Book.Box(forgive, G.forgive[1], G.forgive[2], G.forgive[3], G.forgive[4])
    forgive:SetText("Forgive")
    forgive:SetScript("OnClick", function()
        if P.item and not view.preview then
            StaticPopup_Show("WARPATH_GRUDGE_FORGIVE", ns.DisplayName(P.item.full), nil, P.item.full)
        end
    end)
    P.forgive = forgive
end

local function BuildEmptyRight(R)
    local E = CreateFrame("Frame", nil, R)
    E:SetAllPoints(R)
    P.emptyR = E
    local b = G.blind
    local x, y, s = b.x, b.y, b.size
    local dark, lit = { 90, 56, 24 }, { 255, 236, 190 }
    P.blind = Book.Rect(E, "ARTWORK", { 150, 100, 50 }, 0.18, x, y, x + s, y + s)
    Book.Rect(E, "ARTWORK", dark, 0.55, x, y, x + s, y + 1, 1)
    Book.Rect(E, "ARTWORK", dark, 0.55, x, y, x + 1, y + s, 1)
    Book.Rect(E, "ARTWORK", lit, 0.5, x + s - 1, y, x + s, y + s, 1)
    Book.Rect(E, "ARTWORK", lit, 0.5, x, y + s - 1, x + s, y + s, 1)
    Book.Diamond(E, x + s / 2, y + s / 2, 4, Book.GILT, Book.GILT_EDGE, "OVERLAY")
    P.noname = Book.Caps(E, "morph", G.noname.px, FADED, { ratio = 0.78, track = 0.6 })
    P.noname:Set("No Name Yet", G.RCX, G.noname.y, "m")
    P.nonameLines = {}
    local text = { "When a name is set down,", "its account is kept on this page:",
        "the blood between you, and where it was last seen." }
    for i, line in ipairs(text) do
        local fs = Str(E, "gari", 18, FADED)
        Set(fs, line)
        Put(fs, G.RCX, G.noname.lines[i], "m")
        P.nonameLines[i] = fs
    end
end

local function BuildRight(R)
    BuildEntry(R)
    BuildEmptyRight(R)
    Book.Ornament(R, G.RCX, G.orn.y, G.orn.half)
    P.enc = Book.Caps(R, "morph", G.enc.px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    P.enc:Set("Encounters", G.RCX, G.enc.y, "m")
    Book.Ornament(R, G.RCX, G.enc.orn, G.enc.half)
    P.log = Book.Sheet(R, G.lsheet, G.lwin, G.lcord)
    P.log.step = G.log.line
    P.lines, P.days = {}, {}
    P.nothing = Str(P.log.child, "gari", 17, FADED)
    Set(P.nothing, "Nothing yet.")
    Put(P.nothing, G.RCX, G.empty.nothing, "m", P.log.child, G.lwin[1], G.lwin[2])
end

-- The sheets lay out only what's in view, again at each scroll.
local LayRows, LayLines
local function OnScroll(sheet, lay)
    local base = sheet.SetScroll
    sheet.SetScroll = function(self, px)
        self.scroll = math.max(0, math.min(px or 0, self:Range()))
        lay(self.scroll)
        base(self, self.scroll)
    end
end

local function Build(book)
    local L = CreateFrame("Frame", nil, book)
    L:SetAllPoints(book)
    local R = CreateFrame("Frame", nil, book)
    R:SetAllPoints(book)
    P = { L = L, R = R, list = {}, rowsData = {}, logRows = {} }
    book.gr = P
    BuildLeft(L)
    BuildRight(R)
    OnScroll(P.lsheet, function(s) LayRows(s) end)
    OnScroll(P.log, function(s) LayLines(s) end)
end

---------------------------------------------------------------------------
-- Left page: the list
---------------------------------------------------------------------------

local function ListRow(i)
    return Pooled(P.rows, i, function()
        local ch, ox, oy = P.lsheet.child, G.win[1], G.win[2]
        local r = CreateFrame("Button", nil, ch)
        r.band = Book.Band(r, ch, ox, oy)
        r.hover = Book.Solid(r, "BACKGROUND", WASH, 0.08, 3)
        r.wash = Book.Solid(r, "BACKGROUND", WASH, 0.16, 3)
        r.hair = { Book.Solid(r, "BORDER", RUBRIC, 0.75), Book.Solid(r, "BORDER", RUBRIC, 0.75) }
        r.tile = Book.Tile(r, ch, ox, oy)
        r.name = Str(r, "friz", 18, INK)
        r.level = Str(r, "friz", 15, LEVEL)
        r.sub = Str(r, "gari", 15, FADED)
        r.kills = Book.Bold(Str(r, "garb", 19, INK))
        r.dot = Str(r, "gari", 17, FADED)
        Set(r.dot, "\194\183")
        r.deaths = Book.Bold(Str(r, "garb", 19, RUBRIC))
        r.none = Str(r, "gari", 15, FADED)
        Set(r.none, "no blood yet")
        r.rule = Book.Solid(r, "ARTWORK", FADED, 0.16)
        local function Over(on) r.hover:SetShown(on and not r.chosen) end
        r:SetScript("OnEnter", function() Over(true) end)
        r:SetScript("OnLeave", function() Over(false) end)
        r:SetScript("OnClick", function(self) Choose(self.index) end)
        local hit = CreateFrame("Button", nil, r)
        hit:SetPoint("TOPLEFT", r.name, "TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", r.name, "BOTTOMRIGHT")
        hit:SetScript("OnEnter", function(self) Over(true) if not view.preview then Tip(self, r.item) end end)
        hit:SetScript("OnLeave", function() Over(false) GameTooltip_Hide() end)
        hit:SetScript("OnClick", function() Choose(r.index) end)
        r.hit = hit
        return r
    end)
end

local function LayTally(r, rr, y)
    local ch, ox, oy = P.lsheet.child, G.win[1], G.win[2]
    local x = G.row.tally
    local blood = (rr.kills or 0) + (rr.deaths or 0) > 0
    r.none:SetShown(not blood)
    r.kills:SetShown(blood) r.kills.twin:SetShown(blood)
    r.deaths:SetShown(blood) r.deaths.twin:SetShown(blood)
    r.dot:SetShown(blood)
    if not blood then
        Put(r.none, x, y, "r", ch, ox, oy)
        return
    end
    Set(r.deaths, tostring(rr.deaths or 0))
    Put(r.deaths, x, y, "r", ch, ox, oy)
    x = x - Wpx(r.deaths) - G.row.side
    Put(r.dot, x, y, "r", ch, ox, oy)
    x = x - Wpx(r.dot) - G.row.side
    Set(r.kills, tostring(rr.kills or 0))
    Put(r.kills, x, y, "r", ch, ox, oy)
end

local function LayRow(r, i, item, n)
    local g, ch, ox, oy = G.row, P.lsheet.child, G.win[1], G.win[2]
    local top = g.first + (i - 1) * g.h
    local rr = item.r
    r.index, r.item = i, item
    Book.Box(r, g.x0, top, g.x1, top + g.h, ch, ox, oy)
    local gilt, prev, nxt = P.gilt[i], P.gilt[i - 1], P.gilt[i + 1]
    if gilt then
        r.band:Set(g.x0, g.x1, prev and top - (g.h - g.wash) or top, top + g.wash, not prev, not nxt, GILT_A)
    else
        r.band:Hide()
    end
    r.chosen = i == view.pick
    for _, t in ipairs({ r.wash, r.hover }) do Book.Box(t, g.x0, top, g.x1, top + g.wash, ch, ox, oy) end
    Book.Box(r.hair[1], g.x0, top, g.x1, top + 1, ch, ox, oy)
    Book.Box(r.hair[2], g.x0, top + g.wash - 1, g.x1, top + g.wash, ch, ox, oy)
    r.wash:SetShown(r.chosen)
    r.hair[1]:SetShown(r.chosen)
    r.hair[2]:SetShown(r.chosen)
    r.hover:Hide()
    r.tile:Set(rr.class and gilt and "gold" or "red", rr.class, g.tile, top + g.tdy, g.size)
    QueryFit(r.tile, g.tile, top + g.tdy, g.size, rr.class)
    Set(r.name, ns.DisplayName(item.full))
    Book.NameColor(r.name, rr.class)
    Put(r.name, g.name, top + g.ndy, "l", ch, ox, oy)
    Set(r.level, rr.lv and (rr.lv == -1 and "??" or tostring(rr.lv)) or "")
    Put(r.level, g.name + Wpx(r.name) + g.gap, top + g.ndy, "l", ch, ox, oy)
    Set(r.sub, LastSeen(rr) .. (rr.auto and "  \194\183  added automatically" or ""))
    Book.Color(r.sub, rr.seen and time() - rr.seen.t < NEAR and RUBRIC or FADED)
    Put(r.sub, g.name, top + g.sdy, "l", ch, ox, oy)
    LayTally(r, rr, top + g.ndy)
    Book.Box(r.rule, g.name, top + g.rdy, g.tally, top + g.rdy + 1, ch, ox, oy)
    r.rule:SetShown(i < n)
    r:Show()
end

-- The rows in view at this scroll, and the ribbon on the chosen one.
function LayRows(scroll)
    local list, g, s = P.list, G.row, P.lsheet
    s:Clear()
    local h, k = s:Height(), 0
    for i, item in ipairs(list) do
        local top = g.pad + (i - 1) * g.h
        if top + g.h > scroll - g.h and top < scroll + h + g.h then
            k = k + 1
            local r = ListRow(k)
            LayRow(r, i, item, #list)
            s:Add(r, top, top + g.h)
        end
    end
    for j = k + 1, #P.rows do P.rows[j]:Hide() end
    P.ribbon:Begin(P.listF, Book.OX, Book.OY)
    local y = g.first + (view.pick - 1) * g.h - scroll
    if list[view.pick] and y > G.ribbon.min and y < G.ribbon.max then
        Ribbon(P.ribbon, G.ribbon.x, y + G.ribbon.dy0, y + G.ribbon.dy1)
    end
    P.ribbon:End()
    P.ribbonY = y
end

local function LayList(list)
    P.list = list
    P.gilt = {}
    for i, item in ipairs(list) do P.gilt[i] = SettledLately(item.r) end
    P.lsheet:SetContent(#list * G.row.h + G.row.pad + G.row.tail)
end

---------------------------------------------------------------------------
-- Left page: the heading's kicker, and the empty page
---------------------------------------------------------------------------

local function Summary(list)
    local now, week = time(), 0
    for _, item in ipairs(list) do
        for _, e in ipairs(item.r.log or {}) do
            if e.k == "k" and now - (e.t or 0) < WEEK then week = week + 1 end
        end
    end
    if #list == 0 then return "No grudges held", week end
    local held = #list == 1 and "One grudge" or (Cap(ns.NumberWord(#list)) .. " grudges")
    return held .. " held  \194\183  " .. (week == 0 and "none settled this week" or ("settled " .. Times(week) .. " this week")), week
end
Page.Summary = Summary

local function Ornament(y, half)
    local key = y .. ":" .. half
    for k, f in pairs(P.orns) do f:SetShown(k == key) end
    if not P.orns[key] then
        local f = CreateFrame("Frame", nil, P.emptyL)
        f:SetAllPoints(P.emptyL)
        Book.Ornament(f, G.CX, y, half)
        P.orns[key] = f
    end
end

local function OfferLines()
    local auto = cfg and cfg.grudge and cfg.grudge.auto or "offer"
    local lines = { "Target an enemy and click the skull", "on the war table, or inscribe a name below." }
    if auto ~= "off" then
        lines[3] = false
        lines[4] = "A foe who kills you again and again"
        lines[5] = auto == "add" and "will be added for you." or "will be offered to you."
    end
    return lines
end
Page.OfferLines = OfferLines

-- The prose wrapped round the drop cap (gparts.dropcap_prose).
local function LayEmpty()
    local e = G.empty
    local text = Me() .. " held no grudge. No foe had yet done enough to be remembered by name, and the pages that follow stood empty, waiting."
    local letter = text:sub(1, 1):upper()
    Set(P.cap, letter)
    Put(P.cap, e.x0 - 1, e.y + 2 * e.lh, "l", P.emptyL)
    local cw = Wpx(P.cap)
    local ind
    if STEM[letter] then
        ind = { STEM[letter] * cw + 5, STEM[letter] * cw + 5, cw + 6 }
    else
        local i = cw + (letter == "I" and 2 or 6)
        ind = { i, i, i }
    end
    local space = Book.Measure("friz", e.px, " ")
    local lines, line, lw = {}, {}, 0
    for word in text:sub(2):gmatch("%S+") do
        local w = Book.Measure("friz", e.px, word)
        local width = e.width - (ind[#lines + 1] or 0)
        if #line == 0 or lw + space + w <= width then
            lw = #line == 0 and w or (lw + space + w)
            line[#line + 1] = word
        else
            lines[#lines + 1] = table.concat(line, " ")
            line, lw = { word }, w
        end
    end
    if #line > 0 then lines[#lines + 1] = table.concat(line, " ") end
    local y = e.y
    for i, s in ipairs(lines) do
        local fs = Pooled(P.prose, i, function() return Str(P.emptyL, "friz", e.px, INK) end)
        Set(fs, s)
        Put(fs, e.x0 + (ind[i] or 0), y, "l", P.emptyL)
        fs:Show()
        y = y + e.lh
    end
    for i = #lines + 1, #P.prose do P.prose[i]:Hide() end
    P.proseEnd = y
    Ornament(y + e.orn, e.half)
    local yy, n = y + e.offer, 0
    for _, s in ipairs(OfferLines()) do
        if s then
            n = n + 1
            local fs = Pooled(P.offer, n, function() return Str(P.emptyL, "gari", 18, FADED) end)
            Set(fs, s)
            Put(fs, G.CX, yy, "m", P.emptyL)
            fs:Show()
            yy = yy + e.offerLh
        else
            yy = yy + e.offerGap
        end
    end
    for i = n + 1, #P.offer do P.offer[i]:Hide() end
end

---------------------------------------------------------------------------
-- Right page: the chosen grudge
---------------------------------------------------------------------------

local function Title(px)
    return Pooled(P.titles, px, function()
        return Book.Caps(P.entry, "morph", px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    end)
end

-- The name's size: 31 down to 25 until it fits (Claude's call).
local function TitleSize(name)
    local n = G.name
    local px = n.px
    while px > n.min and Book.Measure("morph", px, name) * 1.05 > n.fit do px = px - 1 end
    return px
end
Page.TitleSize = TitleSize

local function LayAccount(r)
    local a, me = G.acct, P.me
    local function V(n) return (n or 0) == 0 and "none" or tostring(n) end
    local rows = { { me .. " slew them", V(r.kills) }, { "They slew " .. me, V(r.deaths) }, { "Settled", V(r.settled) } }
    for i, row in ipairs(rows) do P.acct[i]:Set(row[1], row[2], a.x0, a.x1, a.y + (i - 1) * a.lh) end
    local y = a.y + 3 * a.lh
    Set(P.seenLab, "Last seen")
    Put(P.seenLab, a.x0, y, "l")
    Set(P.seenVal, (LastSeen(r):gsub("^not seen since", "not since")))
    Put(P.seenVal, a.x1, y, "r")
    local lx = math.floor(a.x0 + Wpx(P.seenLab) + 10)
    local rx = math.floor(a.x1 - Wpx(P.seenVal) - 10)
    Book.Box(P.seenRule, lx, y - 1, math.max(lx + 0.01, rx), y)
    P.seenRule:SetShown(rx > lx)
    Book.Box(P.seenHit, a.x1 - Wpx(P.seenVal), y - 18, a.x1, y + 5)
end

local function LayNote(r)
    local editing = P.noteBox:IsShown()
    local has = (r.note or "") ~= ""
    if has then
        Set(P.noteText, "\226\128\156" .. r.note .. "\226\128\157")
        Put(P.noteText, G.RCX, G.note.y, "m")
    end
    P.noteText:SetShown(has and not editing)
    P.noteHint:SetShown(not has and not editing)
    if view.preview then P.noteHit:Disable() else P.noteHit:Enable() end
end

local function LayEntry(item)
    local r = item.r
    P.item = item
    local p = G.portrait
    P.portrait:Set(r.class and SettledLately(r) and "gold" or "red", r.class, p.x, p.y, p.size)
    QueryFit(P.portrait, p.x, p.y, p.size, r.class)
    local name = ns.DisplayName(item.full)
    local px = TitleSize(name)
    for size, caps in pairs(P.titles) do if size ~= px then caps:SetShown(false) end end
    local t = Title(px)
    t:Set(name, G.RCX, G.name.y, "m")
    P.title, P.titlePx = t, px
    Set(P.who, WhoLine(r))
    Put(P.who, G.RCX, G.who.y, "m")
    SetKicker(P.since, "Held since " .. LongDate(r.added or time()) .. (r.auto and ", added automatically" or ""),
        G.RCX, G.since.y, G.since.rule)
    LayAccount(r)
    LayNote(r)
    if r.seen and not view.preview then P.way:Enable() else P.way:Disable() end
    if view.preview then P.forgive:Disable() else P.forgive:Enable() end
end

---------------------------------------------------------------------------
-- Right page: the encounters
---------------------------------------------------------------------------

local VERB = { g = { "Inscribed ", "" }, a = { "", " added automatically" }, s = { "", " sighted" },
    k = { "", "" }, d = { "Fell to ", "" } }
Page.VERB = VERB

local function LogLine(i)
    return Pooled(P.lines, i, function()
        local ch, ox, oy = P.log.child, G.lwin[1], G.lwin[2]
        local l = CreateFrame("Frame", nil, ch)
        l.band = Book.Band(l, ch, ox, oy)
        l.wash = Book.Solid(l, "BACKGROUND", WASH, 0.16, 3)
        l.hair = { Book.Solid(l, "BORDER", RUBRIC, 0.75), Book.Solid(l, "BORDER", RUBRIC, 0.75) }
        l.glyph = NewSpans(l, "ARTWORK", 1)
        l.dia = Book.Diamond(l, 0, 0, 4, Book.GILT, Book.GILT_EDGE, "ARTWORK", ch, ox, oy)
        l.time = Str(l, "narrow", 15, FADED)
        l.slew = Book.Caps(l, "morph", 15, RUBRIC, { ratio = 0.74, track = 0.6, shadow = SHADOW })
        l.pre = Str(l, "friz", 16, INK)
        l.name = Str(l, "friz", 16, INK)
        l.post = Str(l, "friz", 16, INK)
        l.zone = Str(l, "gari", 15, FADED)
        local hit = CreateFrame("Button", nil, l)
        hit:SetPoint("TOPLEFT", l.name, "TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", l.name, "BOTTOMRIGHT")
        hit:SetScript("OnEnter", function(self) if not view.preview then Tip(self, l.e and l.e.item) end end)
        hit:SetScript("OnLeave", GameTooltip_Hide)
        hit:SetScript("OnClick", function()
            local item = l.e and l.e.item
            for k, it in ipairs(view.grudges) do if it == item then Choose(k, true) return end end
        end)
        l.hit = hit
        return l
    end)
end

local function DayLine(i)
    return Pooled(P.days, i, function()
        local l = CreateFrame("Frame", nil, P.log.child)
        l.text = Str(l, "gari", 16, FADED)
        l.rule = Book.Solid(l, "ARTWORK", FADED, 0.3)
        return l
    end)
end

local function LayDay(l, row)
    local L, ch, ox, oy = G.log, P.log.child, G.lwin[1], G.lwin[2]
    local y = row.y
    Book.Box(l, G.lwin[1], y - 16, G.lwin[3], y + 4, ch, ox, oy)
    Set(l.text, row.day)
    Put(l.text, L.x0, y, "l", ch, ox, oy)
    local from = math.floor(L.x0 + Wpx(l.text) + 8)
    Book.Box(l.rule, from, y - 4, math.max(from + 0.01, L.x1), y - 3, ch, ox, oy)
    l.row = row
    l:Show()
end

local function LayLine(l, row)
    local L, ch, ox, oy = G.log, P.log.child, G.lwin[1], G.lwin[2]
    local e, y = row.e, row.y
    local item, b = e.item, L.band
    l.e, l.row = e, row
    Book.Box(l, G.lwin[1], y + b[3], G.lwin[3], y + b[4], ch, ox, oy)
    if e.k == "k" then l.band:Set(b[1], b[2], y + b[3], y + b[4], true, true, GILT_A) else l.band:Hide() end
    local chosen = item == P.item
    Book.Box(l.wash, b[1], y + b[3], b[2], y + b[4], ch, ox, oy)
    Book.Box(l.hair[1], b[1], y + b[3], b[2], y + b[3] + 1, ch, ox, oy)
    Book.Box(l.hair[2], b[1], y + b[4] - 1, b[2], y + b[4], ch, ox, oy)
    l.wash:SetShown(chosen)
    l.hair[1]:SetShown(chosen)
    l.hair[2]:SetShown(chosen)
    l.glyph:Begin(ch, ox, oy)
    Glyph(l.glyph, e.k, L.glyph, y + L.gdy)
    l.glyph:End()
    Book.MoveDiamond(l.dia, L.glyph, y + L.gdy)
    Book.ShowDiamond(l.dia, e.k == "k")
    Set(l.time, Clock(e.t))
    Put(l.time, L.time, y, "l", ch, ox, oy)
    local x = L.text
    if e.k == "k" then
        x = x + l.slew:Set("slew", x, y, "l", ch, ox, oy) + L.slewGap
        l.slew:SetShown(true)
    else
        l.slew:Set("", x, y, "l", ch, ox, oy)
    end
    local verb = VERB[e.k] or { "", "" }
    Set(l.pre, verb[1])
    Put(l.pre, x, y, "l", ch, ox, oy)
    x = x + Wpx(l.pre)
    Set(l.name, ns.DisplayName(item.full))
    Book.NameColor(l.name, item.r.class)
    Put(l.name, x, y, "l", ch, ox, oy)
    x = x + Wpx(l.name)
    Set(l.post, verb[2])
    Put(l.post, x, y, "l", ch, ox, oy)
    Set(l.zone, (e.k ~= "g" and e.k ~= "a") and Zone(e.z) or "")
    Put(l.zone, L.x1, y, "r", ch, ox, oy)
    l:Show()
end

function LayLines(scroll)
    local s, top0 = P.log, G.lwin[2]
    s:Clear()
    local h, nl, nd = s:Height(), 0, 0
    for _, row in ipairs(P.logRows) do
        local a, b = row.y - 17 - top0, row.y + 6 - top0
        if b > scroll - 30 and a < scroll + h + 30 then
            if row.day then
                nd = nd + 1
                local l = DayLine(nd)
                LayDay(l, row)
                s:Add(l, a, b)
            else
                nl = nl + 1
                local l = LogLine(nl)
                LayLine(l, row)
                s:Add(l, a, b)
            end
        end
    end
    for j = nl + 1, #P.lines do P.lines[j]:Hide() end
    for j = nd + 1, #P.days do P.days[j]:Hide() end
end

local function LayLog(list)
    local rows, content = LogRows(GlobalLog(list))
    P.logRows = rows
    P.nothing:SetShown(#rows == 0)
    P.log:SetContent(content)
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

-- The chosen grudge stays chosen by its key while the list re-sorts; when
-- it's forgiven, the one after it is chosen.
local function ResolvePick(list)
    if P.pickKey then
        for i, it in ipairs(list) do if it.full == P.pickKey then view.pick = i return end end
        local at
        for i, k in ipairs(P.order or {}) do if k == P.pickKey then at = i end end
        for j = (at or math.huge) + 1, #(P.order or {}) do
            for i, it in ipairs(list) do if it.full == P.order[j] then view.pick = i return end end
        end
    end
    view.pick = math.max(1, math.min(view.pick or 1, #list))
end

function Render()
    if not P then return end
    local list = GrudgeList()
    view.grudges = list
    ResolvePick(list)
    P.pickKey = list[view.pick] and list[view.pick].full
    P.order = {}
    for i, it in ipairs(list) do P.order[i] = it.full end
    P.me = Me()
    local book = Chron.book
    book.left.number:SetText("")
    book.right.number:SetText("")
    local empty = #list == 0
    SetKicker(P.kicker, (Summary(list)), G.CX, G.kicker.y, empty and G.kicker.empty or G.kicker.rule)
    P.listF:SetShown(not empty)
    P.emptyL:SetShown(empty)
    P.entry:SetShown(not empty)
    P.emptyR:SetShown(empty)
    P.item = list[view.pick]
    if empty then
        P.list = {}
        LayEmpty()
    else
        LayList(list)
        LayEntry(list[view.pick])
    end
    LayLog(list)
    if view.preview then P.inscribe:Disable() else P.inscribe:Enable() end
end

Chron.pages.grudges = {
    Build = Build,
    Render = function() Render() end,
    Open = function() if P then P.pickKey, P.order = nil, nil end end,
    Reset = function()
        if not P then return end
        P.lsheet.scroll, P.log.scroll = 0, 0
        if P.noteBox:IsShown() then P.noteBox.cancel = true P.noteBox:ClearFocus() P.noteBox:Hide() end
    end,
}

function Page.Frames() return P end

---------------------------------------------------------------------------
-- The samples (the book's preview): the design's made-up busy list
-- (grudges/gdata.py BUSY), First Last names, times from now
---------------------------------------------------------------------------

local BUSY = {
    -- name, class, level, race, guild, kills, deaths, settled, added (days ago), seen {ago, zone}, note, auto, log
    { "Wreckless-Dawnmere", "ROGUE", 60, "Human", "Stormwind Guard", 3, 5, 3, 6, { 20 * 60, 1424 },
        "Camped me at the Tarren Mill flight master. Twice.", nil,
        { { 6 * 86400 + 7200, "d", 1424 }, { 6 * 86400 + 7140, "g" }, { 5 * 86400, "s", 1424 },
            { 5 * 86400 - 600, "d", 1424 }, { 4 * 86400, "k", 1416 }, { 3 * 86400 + 18000, "s", 1417 },
            { 3 * 86400 + 14400, "d", 1417 }, { 2 * 86400, "k", 1424 }, { 2 * 86400 - 1800, "d", 1424 },
            { 86400 + 10800, "s", 1424 }, { 86400 + 7200, "k", 1424 }, { 45 * 60, "d", 1424 }, { 20 * 60, "s", 1424 } } },
    { "Thornhelm-Ironjaw", "PALADIN", 60, "Dwarf", "Ironforge Vanguard", 2, 1, 2, 3, { 3 * 3600, 1423 }, nil, nil,
        { { 3 * 86400, "d", 1423 }, { 3 * 86400 - 60, "g" }, { 2 * 86400, "k", 1423 }, { 3 * 3600, "k", 1423 } } },
    { "Elowen-Starfall", "PRIEST", 58, "Night Elf", nil, 0, 3, 0, 2, { 86400 + 6 * 3600, 1440 }, nil, true,
        { { 2 * 86400, "a" }, { 86400 + 6 * 3600, "s", 1440 } } },
    { "Brask-Holloway", "WARRIOR", 60, "Human", "Lions of Lordaeron", 1, 2, 1, 9, { 2 * 86400, 1434 },
        "Always with a healer.", nil,
        { { 9 * 86400, "g" }, { 2 * 86400 + 3 * 3600, "d", 1434 }, { 2 * 86400 + 2 * 3600, "k", 1434 },
            { 2 * 86400, "s", 1434 }, { 8 * 86400, "d", 1434 } } },
    { "Mirielle-Cogsworth", "MAGE", 59, "Gnome", nil, 4, 0, 4, 12, { 3 * 86400, 1452 }, nil, nil,
        { { 12 * 86400, "g" }, { 3 * 86400, "s", 1452 }, { 11 * 86400, "k", 1452 } } },
    { "Corvane-Ashby", "WARLOCK", 60, "Human", "Shadowfall", 0, 2, 0, 4, { 4 * 86400, 1448 }, nil, nil,
        { { 4 * 86400 + 3600, "d", 1448 }, { 4 * 86400 + 3540, "g" }, { 4 * 86400, "d", 1448 } } },
    { "Hask-Stonebeard", "HUNTER", 57, "Dwarf", nil, 1, 1, 1, 10, { 5 * 86400, 1425 }, nil, nil, {} },
    { "Lyssa-Moonbrook", "DRUID", 60, "Night Elf", "Moonwardens", 0, 0, 0, 8, nil, nil, nil, {} },
    { "Tobren-Fizzlewick", "ROGUE", 55, "Gnome", nil, 2, 4, 2, 14, { 8 * 86400, 1445 }, nil, nil, {} },
    { "Aldric-Vale", "PALADIN", 60, "Human", "Stormwind Guard", 0, 1, 0, 15, { 9 * 86400, 1424 }, nil, nil, {} },
    { "Vexa-Thorne", "MAGE", 60, "Human", nil, 1, 0, 1, 16, nil, nil, nil, {} },
}

-- As saved records { full, r } (the design's order, which is the sort's).
function Samples(now)
    local out = {}
    for i, s in ipairs(BUSY) do
        local r = { class = s[2], lv = s[3], ra = s[4], gu = s[5], kills = s[6], deaths = s[7], settled = s[8],
            added = now - s[9] * 86400, note = s[11], auto = s[12], log = {} }
        for j, e in ipairs(s[13]) do
            r.log[j] = { t = now - e[1], k = e[2], z = e[3] }
            if e[2] == "g" or e[2] == "a" then r.added = now - e[1] end
        end
        if s[10] then r.seen = { t = now - s[10][1], z = s[10][2], x = 0.5, y = 0.5 } end
        out[i] = { full = s[1], r = r }
    end
    return out
end
Page.Samples = Samples
