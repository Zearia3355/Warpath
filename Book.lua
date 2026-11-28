-- Warpath: Book
-- The chronicle's kit (3.8.5): the art and type every page of the book
-- shares, built to the canon in docs/design/chronicle.md.
--
-- Positions are written in render pixels, copied straight from the page
-- specs (docs/design/chronicle-*.md: the 1092x748 design canvas, 1.2 px a
-- UI unit), and converted here by one pair of functions, Book.X and Book.Y.
-- A page's content frame covers the whole book (SetAllPoints), so its
-- top-left is the book's, at render (20.5, 40.4); a scroll child passes its
-- own origin instead.
--
-- Also here: the old page helpers (Font, Solid, Topic, ...) that today's
-- Grudges and Warpath pages and the Settings tab still use until their own
-- redesign phases.
local ADDON, ns = ...
local C = ns.C

local Book = {}
ns.Book = Book

Book.PX = 1.2                         -- render px a UI unit (Joe's screen)
Book.OX, Book.OY = 20.5, 40.4         -- the book's top-left on the design canvas
Book.W, Book.H = 880, 580             -- the book frame, in units
Book.PAD = 18                         -- leather round the pages
Book.PW = (Book.W - 2 * Book.PAD) / 2 -- one page
Book.PH = Book.H - 2 * Book.PAD

-- The canon's colours, 0-255 as the specs write them.
Book.INK, Book.FADED, Book.RUBRIC = { 46, 28, 10 }, { 77, 56, 31 }, { 122, 31, 15 }
Book.SHADOW, Book.LEVEL = { 70, 12, 6 }, { 106, 80, 48 }
Book.GILT, Book.GILT_EDGE = { 176, 128, 52 }, { 70, 40, 8 }

local ART = "Interface\\AddOns\\Warpath\\Art\\book\\"
Book.ART = ART
Book.FACES = {
    friz = "Fonts\\FRIZQT__.TTF",
    morph = "Fonts\\MORPHEUS.TTF",
    narrow = "Fonts\\ARIALN.TTF",
    gari = "Interface\\AddOns\\Warpath\\Fonts\\EBGaramond-Italic.ttf",
    garb = "Interface\\AddOns\\Warpath\\Fonts\\EBGaramond-Bold.ttf",
}
-- Where the baseline sits below a string's top, as a share of its size:
-- Friz and Morpheus measured on Joe's screenshot, Arial Narrow and EB
-- Garamond from their own ascent (to be checked in game).
Book.ASC = { friz = 0.875, morph = 0.88, narrow = 0.905, gari = 1.01, garb = 1.01 }

---------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------

function Book.U(px) return px / 1.2 end
function Book.X(px, ox) return (px - (ox or Book.OX)) / 1.2 end
function Book.Y(py, oy) return -(py - (oy or Book.OY)) / 1.2 end

local function RGB(c) return c[1] / 255, c[2] / 255, c[3] / 255 end
Book.RGB = RGB

---------------------------------------------------------------------------
-- Type
---------------------------------------------------------------------------

-- Fonts the client hasn't loaded yet. On Forever SetFont returns false
-- for an addon's own .ttf until the file has loaded, and leaves the string
-- with no font at all: SetText on it then errors ("Font not set"), which
-- broke 3.8.5-test1's first opening. So every string gets a game font
-- first, and a face that didn't take is set again by Book.Refont().
local pending = {}

-- fs in a face at a size in render px. A size alone may change later.
function Book.Face(fs, face, px)
    if not fs.bface then fs:SetFontObject(GameFontHighlight) end
    fs.bface, fs.bpx = face, px
    if fs:SetFont(Book.FACES[face], px / 1.2, "") then
        pending[fs] = nil
    else
        pending[fs] = true
    end
end

-- Set again every face that hadn't taken; true if any took now.
function Book.Refont()
    local took = false
    for fs in pairs(pending) do
        if fs:SetFont(Book.FACES[fs.bface], fs.bpx / 1.2, "") then
            pending[fs] = nil
            took = true
        end
    end
    return took
end
function Book.Pending() local n = 0 for _ in pairs(pending) do n = n + 1 end return n end

-- A font string in a face at a size in render px, coloured, no shadow.
function Book.Str(parent, face, px, col, layer, sub)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", nil, sub)
    Book.Face(fs, face, px)
    local r, g, b = RGB(col or Book.INK)
    fs:SetTextColor(r, g, b)
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

-- The 1 px shadow (dark red for rubric, black for names).
function Book.Shadow(fs, col)
    local r, g, b = 0, 0, 0
    if col then r, g, b = RGB(col) end
    fs:SetShadowColor(r, g, b, 1)
    fs:SetShadowOffset(1 / 1.2, -1 / 1.2)
    if fs.twin then Book.Shadow(fs.twin, col) end
end

-- Faux bold: the same string again 1 px to the right.
function Book.Bold(fs)
    local twin = fs:GetParent():CreateFontString(nil, fs:GetDrawLayer())
    Book.Face(twin, fs.bface, fs.bpx)
    twin:SetTextColor(fs:GetTextColor())
    twin:SetShadowOffset(0, 0)
    twin:SetWordWrap(false)
    fs.twin = twin
    return fs
end

function Book.Set(fs, text)
    fs:SetText(text)
    if fs.twin then fs.twin:SetText(text) end
end

function Book.Color(fs, col)
    local r, g, b = RGB(col)
    fs:SetTextColor(r, g, b)
    if fs.twin then fs.twin:SetTextColor(r, g, b) end
end

-- Width in render px, as the client measures it.
function Book.Wpx(fs) return (fs:GetStringWidth() or 0) * 1.2 end

local POINT = { l = "TOPLEFT", r = "TOPRIGHT", m = "TOP" }
local JUST = { l = "LEFT", r = "RIGHT", m = "CENTER" }

-- Put a string's baseline at (x, y) render px: align "l" (x is its left),
-- "r" (its right) or "m" (its centre). rel/ox/oy: the frame it's placed on
-- and where that frame's top-left is (default: the string's parent, the
-- book's top-left).
function Book.Put(fs, x, y, align, rel, ox, oy)
    align = align or "l"
    rel = rel or fs:GetParent()
    local top = y - (Book.ASC[fs.bface] or 0.875) * fs.bpx
    fs:ClearAllPoints()
    fs:SetPoint(POINT[align], rel, "TOPLEFT", Book.X(x, ox), Book.Y(top, oy))
    fs:SetJustifyH(JUST[align])
    fs.bx, fs.by = x, y
    if fs.twin then
        fs.twin:ClearAllPoints()
        fs.twin:SetPoint(POINT[align], rel, "TOPLEFT", Book.X(x + 1, ox), Book.Y(top, oy))
        fs.twin:SetJustifyH(JUST[align])
    end
end

-- Measuring in a face without a visible string: one hidden string per face
-- and size, on the preload frame (below).
local measure = {}
local pre
function Book.Measure(face, px, text)
    local k = face .. px
    local fs = measure[k]
    if not fs then
        fs = Book.Str(pre, face, px)
        measure[k] = fs
    end
    fs:SetText(text)
    return (fs:GetStringWidth() or 0) * 1.2
end

-- Letter by letter (small caps and letterspaced capitals), as the design
-- sets them: each letter its own string, upper case; a lower-case letter is
-- its capital at int(px * ratio); each followed by `track` px. Returns an
-- object: :Set(text, x, y, align) lays it out and returns its width in px.
local Caps = {}
Caps.__index = Caps

function Book.Caps(parent, face, px, col, opt)
    opt = opt or {}
    return setmetatable({ parent = parent, face = face, px = px, col = col, letters = {},
        ratio = opt.ratio or 1, track = opt.track or 0, shadow = opt.shadow, layer = opt.layer }, Caps)
end

function Caps:Letter(i, small)
    local px = small and math.floor(self.px * self.ratio) or self.px
    local l = self.letters[i]
    if not l or l.bpx ~= px then
        if l then l:Hide() end
        l = Book.Str(self.parent, self.face, px, self.col, self.layer)
        if self.shadow then Book.Shadow(l, self.shadow) end
        self.letters[i] = l
    end
    return l
end

function Caps:Set(text, x, y, align, rel, ox, oy)
    text = text or ""
    local n, w = 0, 0
    local parts = {}
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local small = ch:match("^%l$") ~= nil
        n = n + 1
        local l = self:Letter(n, small)
        l:SetText(ch:upper())
        l:Show()
        local lw = Book.Wpx(l)
        parts[n] = lw
        w = w + lw + self.track
    end
    for i = n + 1, #self.letters do self.letters[i]:Hide() end
    local cx = x
    if align == "m" then cx = x - w / 2 elseif align == "r" then cx = x - w end
    for i = 1, n do
        Book.Put(self.letters[i], cx, y, "l", rel, ox, oy)
        cx = cx + parts[i] + self.track
    end
    self.width, self.x0 = w, (align == "m" and x - w / 2) or (align == "r" and x - w) or x
    return w
end

function Caps:SetShown(on)
    for _, l in ipairs(self.letters) do l:SetShown(on and l:GetText() ~= nil) end
end

---------------------------------------------------------------------------
-- Art: solids, rules, diamonds, the ornament
---------------------------------------------------------------------------

function Book.Solid(parent, layer, col, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    local r, g, b = RGB(col)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Place a region over the render-px rect [x0, x1) x [y0, y1).
function Book.Box(t, x0, y0, x1, y1, rel, ox, oy)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", rel or t:GetParent(), "TOPLEFT", Book.X(x0, ox), Book.Y(y0, oy))
    t:SetSize(math.max(0.01, (x1 - x0) / 1.2), math.max(0.01, (y1 - y0) / 1.2))
end

function Book.Rect(parent, layer, col, a, x0, y0, x1, y1, sub)
    local t = Book.Solid(parent, layer, col, a, sub)
    Book.Box(t, x0, y0, x1, y1)
    return t
end

-- A 1 px rule, as the design's rule(x0, x1, y): pixels x0..x1-1 of row y.
function Book.Rule(parent, x0, x1, y, col, a, layer, rel, ox, oy)
    local t = Book.Solid(parent, layer or "ARTWORK", col or Book.FADED, a or 0.45)
    Book.Box(t, math.floor(x0), math.floor(y), math.max(math.floor(x0) + 0.01, math.floor(x1)), math.floor(y) + 1, rel, ox, oy)
    return t
end

-- A diamond of radius r (a square turned 45 degrees), centred on (x, y),
-- with an optional edge one px wider all round.
function Book.Diamond(parent, x, y, r, col, edge, layer, rel, ox, oy)
    local d = {}
    local function sq(c, rad, sub)
        local t = Book.Solid(parent, layer or "ARTWORK", c, 1, sub)
        local s = rad * math.sqrt(2) / 1.2
        t:SetSize(s, s)
        pcall(t.SetRotation, t, math.pi / 4)
        return t
    end
    if edge then d.edge = sq(edge, r + 1, 1) end
    d.fill = sq(col or Book.RUBRIC, r, 2)
    d.rel, d.ox, d.oy = rel, ox, oy
    Book.MoveDiamond(d, x, y)
    return d
end

function Book.MoveDiamond(d, x, y)
    for _, t in pairs({ edge = d.edge, fill = d.fill }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER", d.rel or t:GetParent(), "TOPLEFT", Book.X(x, d.ox), Book.Y(y, d.oy))
    end
    d.x, d.y = x, y
end

function Book.ShowDiamond(d, on)
    if d.edge then d.edge:SetShown(on) end
    d.fill:SetShown(on)
end

-- The canon's ornament: two rules each side of a rubric diamond, with small
-- diamonds at +-11 (mock4.ornament): the upper rule at 55%, the lower at 30%.
function Book.Ornament(parent, cx, y, half)
    for _, dy in ipairs({ -1, 2 }) do
        local a = dy < 0 and 0.55 or 0.3
        Book.Rule(parent, cx - half, cx - 16, y + dy, Book.RUBRIC, a)
        Book.Rule(parent, cx + 16, cx + half, y + dy, Book.RUBRIC, a)
    end
    Book.Diamond(parent, cx, y, 5)
    Book.Diamond(parent, cx - 11, y, 2)
    Book.Diamond(parent, cx + 11, y, 2)
end

-- A filled triangle from 1 px rows (the chevron: 8 px, too small for any
-- texture to beat). open: pointing down; else pointing right.
local Chevron = {}
Chevron.__index = Chevron

function Book.Chevron(parent, rel, ox, oy)
    local c = setmetatable({ rows = {}, rel = rel, ox = ox, oy = oy }, Chevron)
    for i = 1, 6 do c.rows[i] = Book.Solid(parent, "ARTWORK", Book.RUBRIC, 1) end
    return c
end

-- (x, y) as the design's zone line: x = x0 (the column's left), y the baseline.
function Chevron:Set(open, x, y)
    for k = 0, 5 do
        local t = self.rows[k + 1]
        if open then        -- (x, y-8), (x+8, y-8), (x+4, y-2)
            local hw = 4 * (1 - k / 6)
            Book.Box(t, x + 4 - hw, y - 8 + k, x + 4 + hw, y - 7 + k, self.rel, self.ox, self.oy)
        else                -- (x+2, y-10), (x+8, y-6), (x+2, y-2)
            local hh = 4 * (1 - k / 6)
            Book.Box(t, x + 2 + k, y - 6 - hh, x + 3 + k, y - 6 + hh, self.rel, self.ox, self.oy)
        end
    end
end

function Chevron:SetShown(on) for _, t in ipairs(self.rows) do t:SetShown(on) end end

---------------------------------------------------------------------------
-- Names (N2) and their tooltip
---------------------------------------------------------------------------

-- Class colour taken halfway from the parchment-inked tone (luminance at
-- most 0.28) toward the game's colour. Nil class: ink.
function Book.N2(class)
    if not class or not ns.ClassColor then return nil end
    local r, g, b = ns.ClassColor(class)
    if not r then return nil end
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    local k = lum > 0.28 and 0.28 / lum or 1
    return { math.floor((r * k + (r - r * k) * 0.5) * 255), math.floor((g * k + (g - g * k) * 0.5) * 255),
        math.floor((b * k + (b - b * k) * 0.5) * 255) }
end

-- A name string: N2 with a black shadow, or plain ink for an unknown class.
function Book.NameColor(fs, class)
    local col = Book.N2(class)
    Book.Color(fs, col or Book.INK)
    if col then Book.Shadow(fs) else fs:SetShadowOffset(0, 0) end
end

-- What a foe's tooltip says (prose and rows alike). who: Chronicler's
-- name run, or a kill/death entry turned into one.
function Book.FoeTooltip(owner, who, me)
    if not who or not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local name = who.name or ns.DisplayName(who.key) or who.text or "Unknown"
    local r, g, b = 0.9, 0.9, 0.9
    if who.class and ns.ClassColor then r, g, b = ns.ClassColor(who.class) end
    GameTooltip:AddLine(name, r, g, b)
    local desc = ns.Foes and ns.Foes.Describe and ns.Foes.Describe(who.level, who.race, who.class, who.guild) or ""
    if desc ~= "" then GameTooltip:AddLine((who.level and "Level " or "") .. desc, 1, 1, 1) end
    local function Times(n) return n == 1 and "once" or n == 2 and "twice" or (ns.NumberWord(n) .. " times") end
    if (who.slain or 0) > 0 then GameTooltip:AddLine("Slain " .. Times(who.slain) .. " this campaign", 1, 0.82, 0) end
    if (who.slew or 0) > 0 then GameTooltip:AddLine("Slew " .. (me or "you") .. " " .. Times(who.slew), 1, 0.5, 0.4) end
    if who.key and ns.Grudge and ns.Grudge.Get and ns.Grudge.Get(who.key) then
        GameTooltip:AddLine("Grudge held", 0.8, 0.25, 0.2)
    end
    if who.shot then GameTooltip:AddLine(("Screenshot #%d"):format(who.shot), 1, 1, 1) end
    if who.waypoint then GameTooltip:AddLine("Click to set a waypoint here", 0.1, 1, 0.1) end
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Class tiles: red; bevelled gold for an honour; dark for a death
---------------------------------------------------------------------------

local Tile = {}
Tile.__index = Tile

function Book.Tile(parent, rel, ox, oy)
    local t = setmetatable({ rel = rel, ox = ox, oy = oy, parts = {} }, Tile)
    for i = 1, 5 do t.parts[i] = Book.Solid(parent, "ARTWORK", Book.INK, 1, i - 4) end
    t.icon = parent:CreateTexture(nil, "ARTWORK", nil, 3)
    t.q = Book.Str(parent, "morph", 15, { 214, 168, 82 }, "OVERLAY")
    return t
end

local function Fill(t, col, x0, y0, x1, y1, tile)
    local r, g, b = RGB(col)
    t:SetColorTexture(r, g, b, 1)
    Book.Box(t, x0, y0, x1, y1, tile.rel, tile.ox, tile.oy)
    t:Show()
end

-- kind: "red", "gold" or "dark"; (x, y) the tile's top-left; size in px
-- (the design's 22: rects as PIL draws them, edges inclusive).
function Tile:Set(kind, class, x, y, size)
    local p = self.parts
    local inner
    if kind == "gold" then
        Fill(p[1], { 52, 28, 6 }, x - 4, y - 4, x + size + 5, y + size + 5, self)
        Fill(p[2], { 246, 206, 112 }, x - 3, y - 3, x + size + 4, y + size + 4, self)
        Fill(p[3], { 150, 98, 30 }, x + size + 1, y, x + size + 4, y + size + 4, self)
        Fill(p[4], { 150, 98, 30 }, x, y + size + 1, x + size + 4, y + size + 4, self)
        Fill(p[5], { 70, 40, 8 }, x, y, x + size + 1, y + size + 1, self)
        inner = { x + 1, y + 1, size - 2 }
    else
        local rim, ground = { 176, 128, 52 }, { 110, 16, 10 }
        if kind == "dark" then rim, ground = Book.FADED, Book.INK end
        Fill(p[1], { 60, 30, 10 }, x - 1, y - 1, x + size + 2, y + size + 2, self)
        Fill(p[2], rim, x, y, x + size + 1, y + size + 1, self)
        Fill(p[3], ground, x + 2, y + 2, x + size - 1, y + size - 1, self)
        p[4]:Hide()
        p[5]:Hide()
        inner = { x + 2, y + 2, size - 4 }
    end
    local tex = class and ("Interface\\Icons\\ClassIcon_" .. class)
    if kind == "dark" and not class then tex = C and C.TEX_SKULL end
    if tex then
        self.icon:SetTexture(tex)
        self.icon:SetTexCoord(0, 1, 0, 1)
        self.icon:SetAlpha(kind == "dark" and 0.6 or 1)
        Book.Box(self.icon, inner[1], inner[2], inner[1] + inner[3], inner[2] + inner[3], self.rel, self.ox, self.oy)
        self.icon:Show()
        self.q:Hide()
    else
        self.icon:Hide()
        self.q:SetText("?")
        self.q:Show()
        Book.Put(self.q, x + size / 2 + 0.5, y + size / 2 + 6, "m", self.rel, self.ox, self.oy)
    end
end

function Tile:Hide()
    for _, t in ipairs(self.parts) do t:Hide() end
    self.icon:Hide()
    self.q:Hide()
end

---------------------------------------------------------------------------
-- The gilt band behind an honour row (S3b): (222,150,44) at 160/255; in
-- over the first 6% of its width, out from 55% to the end on a power of
-- 1.4 (three straight pieces); top and bottom soften over 4 px unless it
-- joins a neighbouring band.
---------------------------------------------------------------------------

local BAND_U = { 0, 0.06, 0.55, 0.70, 0.85, 1 }
local BAND_V = { 0, 1, 1, (2 / 3) ^ 1.4, (1 / 3) ^ 1.4, 0 }
local BAND_COL, BAND_A = { 222, 150, 44 }, 160 / 255

local Band = {}
Band.__index = Band

function Book.Band(parent, rel, ox, oy)
    return setmetatable({ parent = parent, rel = rel, ox = ox, oy = oy, strips = {}, n = 0 }, Band)
end

function Band:Strip(i)
    local s = self.strips[i]
    if not s then
        s = {}
        for k = 1, #BAND_U - 1 do
            s[k] = self.parent:CreateTexture(nil, "BACKGROUND", nil, 2)
            s[k]:SetColorTexture(1, 1, 1, 1)
        end
        self.strips[i] = s
    end
    return s
end

function Band:Set(x0, x1, y0, y1, roundTop, roundBot)
    local r, g, b = RGB(BAND_COL)
    local rows = {}
    local h = y1 - y0
    local t0, t1 = y0, y1
    if roundTop then for i = 0, 3 do rows[#rows + 1] = { y0 + i, y0 + i + 1, (i + 0.5) / 4 } end t0 = y0 + 4 end
    if roundBot then t1 = y1 - 4 end
    if t1 > t0 then rows[#rows + 1] = { t0, t1, 1 } end
    if roundBot then for i = 3, 0, -1 do rows[#rows + 1] = { y1 - i - 1, y1 - i, (i + 0.5) / 4 } end end
    if h <= 8 then rows = { { y0, y1, 0.5 } } end
    for i, row in ipairs(rows) do
        local s = self:Strip(i)
        for k = 1, #BAND_U - 1 do
            local xa, xb = x0 + (x1 - x0) * BAND_U[k], x0 + (x1 - x0) * BAND_U[k + 1]
            local a = BAND_A * row[3]
            s[k]:SetGradient("HORIZONTAL", CreateColor(r, g, b, a * BAND_V[k]), CreateColor(r, g, b, a * BAND_V[k + 1]))
            Book.Box(s[k], xa, row[1], xb, row[2], self.rel, self.ox, self.oy)
            s[k]:Show()
        end
    end
    for i = #rows + 1, #self.strips do for _, t in ipairs(self.strips[i]) do t:Hide() end end
end

function Band:Hide()
    for _, s in ipairs(self.strips) do for _, t in ipairs(s) do t:Hide() end end
end

---------------------------------------------------------------------------
-- The inset sheet: a pasted sheet a touch paler than the page, with a soft
-- shadow and no stack, a fixed size, scrolling inside with the crimson bar.
-- rect: the sheet {x0, y0, x1, y1} (PIL's, edges inclusive); win: the
-- window the rows scroll in {x0, y0, x1, y1}; cord: {x, y0, y1} of the bar.
---------------------------------------------------------------------------

local Sheet = {}
Sheet.__index = Sheet
Book.FADE = 16                     -- px of fade at an edge with more beyond

-- A texture piece over [x0,x1) x [y0,y1) with texcoords [u0,u1] x [v0,v1],
-- less a hole (a rect it must not cover): up to four pieces.
local function Piece(parent, file, x0, y0, x1, y1, u0, u1, v0, v1, hole)
    local function Tex(a, b, c, d)
        if c - a < 0.01 or d - b < 0.01 then return end
        local t = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetTexture(file)
        local fu = function(x) return u0 + (u1 - u0) * (x - x0) / (x1 - x0) end
        local fv = function(y) return v0 + (v1 - v0) * (y - y0) / (y1 - y0) end
        t:SetTexCoord(fu(a), fu(c), fv(b), fv(d))
        Book.Box(t, a, b, c, d)
    end
    if not hole or hole[1] >= x1 or hole[3] <= x0 or hole[2] >= y1 or hole[4] <= y0 then
        return Tex(x0, y0, x1, y1)
    end
    local hx0, hy0, hx1, hy1 = math.max(x0, hole[1]), math.max(y0, hole[2]), math.min(x1, hole[3]), math.min(y1, hole[4])
    Tex(x0, y0, x1, hy0)          -- above the hole
    Tex(x0, hy1, x1, y1)          -- below
    Tex(x0, hy0, hx0, hy1)        -- left
    Tex(hx1, hy0, x1, hy1)        -- right
end

-- A 9-slice drawn 1:1 (a texture px is a render px), cut at `cut` px, over
-- [x0,x1) x [y0,y1); hole: a rect left uncovered (the sheet over its shadow).
local function NineSlice(parent, file, size, cut, x0, y0, x1, y1, hole)
    local xs, ys = { x0, x0 + cut, x1 - cut, x1 }, { y0, y0 + cut, y1 - cut, y1 }
    local ts = { 0, cut / size, 1 - cut / size, 1 }
    for j = 1, 3 do
        for i = 1, 3 do
            Piece(parent, file, xs[i], ys[j], xs[i + 1], ys[j + 1], ts[i], ts[i + 1], ts[j], ts[j + 1], hole)
        end
    end
end
Book.NineSlice = NineSlice

function Book.Sheet(parent, rect, win, cord)
    local s = setmetatable({ rect = rect, win = win, cord = cord, scroll = 0, content = 0, items = {} }, Sheet)
    local x0, y0, x1, y1 = rect[1], rect[2], rect[3], rect[4]
    -- the shadow (60,30,10) at 51%, offset (2,3), blurred 3: a 9-slice whose
    -- shape edge is 16 px in from the texture's
    NineSlice(parent, ART .. "sheet-shadow", 64, 26, x0 + 2 - 16, y0 + 3 - 16, x1 + 1 + 2 + 16, y1 + 1 + 3 + 16,
        { x0, y0, x1 + 1, y1 + 1 })
    s.paper = Book.Rect(parent, "BACKGROUND", { 240, 208, 146 }, 0.30, x0, y0, x1 + 1, y1 + 1, 2)
    local edge = { 130, 84, 40 }
    Book.Rect(parent, "BORDER", edge, 1, x0, y0, x1 + 1, y0 + 1)
    Book.Rect(parent, "BORDER", edge, 1, x0, y1, x1 + 1, y1 + 1)
    Book.Rect(parent, "BORDER", edge, 1, x0, y0, x0 + 1, y1 + 1)
    Book.Rect(parent, "BORDER", edge, 1, x1, y0, x1 + 1, y1 + 1)
    for _, c in ipairs({ { x0 + 6, y0 + 6 }, { x1 - 6, y0 + 6 }, { x0 + 6, y1 - 6 }, { x1 - 6, y1 - 6 } }) do
        Book.Rule(parent, c[1] - 3, c[1] + 3, c[2], { 150, 100, 40 }, 0.25, "BORDER")
    end
    -- the window and its scroll child, whose top-left is the window's at scroll 0
    local sf = CreateFrame("ScrollFrame", nil, parent)
    Book.Box(sf, win[1], win[2], win[3], win[4])
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize((win[3] - win[1]) / 1.2, (win[4] - win[2]) / 1.2)
    sf:SetScrollChild(child)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta) s:SetScroll(s.scroll - delta * (s.step or 27)) end)
    s.frame, s.child = sf, child
    -- the bar: a cord and a crimson thumb, inside the sheet's right edge
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetFrameLevel(sf:GetFrameLevel() + 2)
    Book.Box(bar, cord[1] - 4, cord[2] - 6, cord[1] + 6, cord[3] + 6)
    s.bar = bar
    s.cordTex = Book.Solid(bar, "ARTWORK", { 110, 30, 18 }, 0.4)
    s.thumb = CreateFrame("Button", nil, bar)
    s.thumb:SetFrameLevel(bar:GetFrameLevel() + 1)
    s.thumbEdge = Book.Solid(s.thumb, "ARTWORK", { 46, 6, 4 }, 1, 1)
    s.thumbFill = Book.Solid(s.thumb, "ARTWORK", { 146, 24, 14 }, 1, 2)
    s.thumbLit = Book.Solid(s.thumb, "ARTWORK", { 206, 72, 48 }, 1, 3)
    s.thumbCut = {}
    for i = 1, 4 do s.thumbCut[i] = Book.Solid(s.thumb, "ARTWORK", { 0, 0, 0 }, 0, 4) end
    s.thumb:RegisterForDrag("LeftButton")
    s.thumb:SetScript("OnDragStart", function(self)
        local _, cy = GetCursorPosition()
        s.drag = { cy = cy / (self:GetEffectiveScale() or 1), at = s.scroll }
        self:SetScript("OnUpdate", function(me)
            local _, y = GetCursorPosition()
            y = y / (me:GetEffectiveScale() or 1)
            local d = s.drag
            if not d then return end
            local track = (s.cord[3] - s.cord[2]) - s.th
            if track > 0 then s:SetScroll(d.at + (d.cy - y) * 1.2 / track * s:Range()) end
        end)
    end)
    s.thumb:SetScript("OnDragStop", function(self) s.drag = nil self:SetScript("OnUpdate", nil) end)
    return s
end

function Sheet:Height() return self.win[4] - self.win[2] end
function Sheet:Range() return math.max(0, self.content - self:Height()) end

-- Rows register their place in the content (px from its top) so the sheet
-- can fade them at an edge: item = { frame, top, bottom }.
function Sheet:Clear() self.items = {} end
function Sheet:Add(frame, top, bottom) self.items[#self.items + 1] = { frame, top, bottom } end

function Sheet:SetContent(h)
    self.content = h
    self.child:SetHeight(math.max(h, self:Height()) / 1.2)
    self:SetScroll(self.scroll)
end

function Sheet:SetScroll(px)
    px = math.max(0, math.min(px or 0, self:Range()))
    self.scroll = px
    self.frame:SetVerticalScroll(px / 1.2)
    self:Update()
end

-- The bar (only while the content overflows) and the fades (only at an
-- edge with more beyond it).
function Sheet:Update()
    local h, range = self:Height(), self:Range()
    local over = range > 0
    self.bar:SetShown(over)
    if over then
        local cx, c0, c1 = self.cord[1], self.cord[2], self.cord[3]
        Book.Box(self.cordTex, cx, c0, cx + 1, c1, self.bar, cx - 4, c0 - 6)
        local len = c1 - c0
        local th = math.max(22, math.floor(len * math.min(1, h / self.content)))
        local ty = c0 + math.floor((len - th) * (self.scroll / range))
        self.th = th
        Book.Box(self.thumb, cx - 3, ty, cx + 5, ty + th + 1, self.bar, cx - 4, c0 - 6)
        local o = { self.thumb, cx - 3, ty }
        local function Part(t, a, b, c, d) Book.Box(t, a, b, c, d, o[1], o[2], o[3]) end
        Part(self.thumbEdge, cx - 3, ty, cx + 5, ty + th + 1)
        Part(self.thumbFill, cx - 2, ty + 1, cx + 4, ty + th)
        Part(self.thumbLit, cx - 1, ty + 3, cx, ty + th - 3)
    end
    local fadeTop, fadeBot = self.scroll > 0.5, self.scroll < range - 0.5
    local top, bot = self.scroll, self.scroll + h
    for _, it in ipairs(self.items) do
        local f, a0, a1 = it[1], it[2], it[3]
        local a = 1
        local mid = (a0 + a1) / 2
        if fadeTop then a = math.min(a, math.max(0, (mid - top) / Book.FADE)) end
        if fadeBot then a = math.min(a, math.max(0, (bot - mid) / Book.FADE)) end
        f:SetAlpha(math.min(1, a))
    end
end

---------------------------------------------------------------------------
-- Reckoning rows: label, hairline leader, value (EB Garamond Bold, rubric,
-- faux bold)
---------------------------------------------------------------------------

local Reckon = {}
Reckon.__index = Reckon

function Book.Reckon(parent)
    local r = setmetatable({}, Reckon)
    r.label = Book.Str(parent, "friz", 18, Book.INK)
    r.value = Book.Bold(Book.Str(parent, "garb", 21, Book.RUBRIC))
    r.rule = Book.Solid(parent, "ARTWORK", Book.INK, 0.38)
    return r
end

-- labels at x0, values right at x1 (the bold copy 1 px further), baseline y
function Reckon:Set(label, value, x0, x1, y)
    Book.Set(self.label, label)
    Book.Set(self.value, value)
    Book.Put(self.label, x0, y, "l")
    Book.Put(self.value, x1 - 1, y, "r")
    local lx = math.floor(x0 + Book.Wpx(self.label) + 10)
    local rx = math.floor(x1 - (Book.Wpx(self.value) + 1) - 10)
    Book.Box(self.rule, lx, y - 1, math.max(lx + 0.01, rx), y)
    self.rule:SetShown(rx > lx)
end

---------------------------------------------------------------------------
-- The book's own art
---------------------------------------------------------------------------

-- book.tga: the art is 1062x704 px with the frame at its top-left (18, 40),
-- so it's anchored 2.1 units left and 0.3 up of the book; packed as four
-- pieces (tools/art/README.md).
local PIECES = {
    { 0, 0, 1024, 704, 0, 0 },
    { 1024, 0, 1062, 235, 2, 710 },
    { 1024, 235, 1062, 470, 48, 710 },
    { 1024, 470, 1062, 704, 94, 710 },
}

function Book.Art(f)
    local ox, oy = 18, 40               -- the art's top-left on the canvas
    for _, p in ipairs(PIECES) do
        local t = f:CreateTexture(nil, "BACKGROUND", nil, -6)
        t:SetTexture(ART .. "book")
        local w, h = p[3] - p[1], p[4] - p[2]
        t:SetTexCoord(p[5] / 1024, (p[5] + w) / 1024, p[6] / 1024, (p[6] + h) / 1024)
        Book.Box(t, ox + p[1], oy + p[2], ox + p[3], oy + p[4], f)
    end
    -- the drop shadow on the scene: the leather rect (22,44)-(1070,733)
    -- moved (6,10) and 4 px taller; the shape's edge is 48 px in
    local sh = CreateFrame("Frame", nil, f)
    sh:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    sh:SetAllPoints(f)
    NineSlice(sh, ART .. "book-shadow", 256, 104, 28 - 48, 54 - 48, 1076 + 48, 747 + 48)
    return sh
end

---------------------------------------------------------------------------
-- Fonts load late on this client: the probe saw SetFont return false for
-- EB Garamond and GetStringWidth measure Friz, yet the text drew in
-- Garamond later. Set every face on strings as soon as the addon loads (so
-- the client has them by the time the book opens), and give pages a
-- signature of measured widths: when it changes, lay out again.
---------------------------------------------------------------------------

pre = CreateFrame("Frame", nil, UIParent)
pre:SetSize(1, 1)
pre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
pre:SetAlpha(0)
Book.pre = pre
local SAMPLE = "Winterspring \226\128\148 21 slain, #11\226\128\147#31"
for _, face in ipairs({ "gari", "garb", "friz", "morph", "narrow" }) do
    local fs = Book.Str(pre, face, 18)
    fs:SetText(SAMPLE)
    fs:SetPoint("BOTTOMLEFT")
end

function Book.FontSig()
    local out = {}
    for i, face in ipairs({ "gari", "garb", "morph" }) do
        out[i] = math.floor(Book.Measure(face, 18, SAMPLE) * 10 + 0.5)
    end
    return table.concat(out, ",")
end

-- After the book opens: check the faces a few times over the next seconds
-- and call relayout() whenever what they measure has changed.
function Book.Settle(relayout)
    local last = Book.FontSig()
    local tries = 0
    local function Check()
        tries = tries + 1
        local took = Book.Refont()
        local now = Book.FontSig()
        if took or now ~= last then
            last = now
            relayout()
        end
        if tries < 6 then C_Timer.After(0.25 * tries, Check) end
    end
    C_Timer.After(0, Check)
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

local ROMAN = { { 1000, "m" }, { 900, "cm" }, { 500, "d" }, { 400, "cd" }, { 100, "c" }, { 90, "xc" },
    { 50, "l" }, { 40, "xl" }, { 10, "x" }, { 9, "ix" }, { 5, "v" }, { 4, "iv" }, { 1, "i" } }
function Book.Roman(n)
    local out = ""
    for _, p in ipairs(ROMAN) do while n >= p[1] do out, n = out .. p[2], n - p[1] end end
    return out
end

---------------------------------------------------------------------------
-- The old page helpers (3.8.3), for the pages not yet redesigned
---------------------------------------------------------------------------

local O = {}
Book.Old = O
O.INK, O.FADED, O.RUBRIC = { 0.18, 0.11, 0.04 }, { 0.30, 0.22, 0.12 }, { 0.48, 0.12, 0.06 }
O.GREY = { 0.52, 0.45, 0.34 }
O.GILT = { 0.84, 0.66, 0.32 }

function O.Font(parent, object, fallback, color, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not (object and pcall(fs.SetFontObject, fs, object)) then fs:SetFontObject(fallback) end
    if size then
        local path, _, flags = fs:GetFont()
        if path then pcall(fs.SetFont, fs, path, size, flags or "") end
    end
    color = color or O.INK
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

function O.Solid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Class colours darkened to ink so every class reads on parchment.
function O.Ink(r, g, b)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    local k = lum > 0.28 and 0.28 / lum or 1
    return r * k, g * k, b * k
end

function O.Colored(name, class)
    if not name then return "|cff4d3a20someone unseen|r" end
    local r, g, b = O.INK[1], O.INK[2], O.INK[3]
    if class then r, g, b = O.Ink(ns.ClassColor(class)) end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

function O.Diamond(parent, size)
    local t = O.Solid(parent, "ARTWORK", O.RUBRIC[1], O.RUBRIC[2], O.RUBRIC[3], 1)
    t:SetSize(size, size)
    pcall(t.SetRotation, t, math.pi / 4)
    return t
end

function O.Ornament(parent, y)
    local l = O.Solid(parent, "ARTWORK", O.RUBRIC[1], O.RUBRIC[2], O.RUBRIC[3], 0.7)
    l:SetSize(70, 1)
    l:SetPoint("TOP", parent, "TOP", -46, y)
    local r = O.Solid(parent, "ARTWORK", O.RUBRIC[1], O.RUBRIC[2], O.RUBRIC[3], 0.7)
    r:SetSize(70, 1)
    r:SetPoint("TOP", parent, "TOP", 46, y)
    local d = O.Diamond(parent, 7)
    d:SetPoint("CENTER", parent, "TOP", 0, y)
end

-- A topic heading (3.8.3): small faded capitals, then a thin rule running
-- on to `right` (parent's x; default the page's text edge).
function O.Topic(parent, text, x, y, right)
    local t = { fs = O.Font(parent, QuestFontNormalSmall, GameFontNormalSmall, O.FADED, 11),
        rule = O.Solid(parent, "ARTWORK", O.FADED[1], O.FADED[2], O.FADED[3], 0.4) }
    t.rule:SetHeight(1)
    function t:Set(s, tx, ty, tr)
        s = s:upper()
        self.fs:ClearAllPoints()
        self.fs:SetPoint("TOPLEFT", tx, -ty)
        self.fs:SetText(s)
        local w = self.fs:GetStringWidth() or 0
        if w < 1 then w = #s * 7 end
        local from = tx + w + 8
        self.rule:ClearAllPoints()
        self.rule:SetPoint("TOPLEFT", from, -(ty + 6))
        self.rule:SetWidth(math.max(1, (tr or (Book.PW - 32)) - from))
        self:SetShown(true)
    end
    function t:SetShown(on) self.fs:SetShown(on) self.rule:SetShown(on) end
    if text then t:Set(text, x, y, right) end
    return t
end

-- A big red initial on a gilt-edged square.
function O.DropCap(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size + 4)
    local edge = O.Solid(f, "BORDER", O.GILT[1], O.GILT[2], O.GILT[3], 1)
    edge:SetAllPoints()
    local fill = O.Solid(f, "ARTWORK", 0.45, 0.08, 0.04, 1)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    f.letter = O.Font(f, QuestTitleFont, GameFontNormalHuge, { 0.95, 0.78, 0.38 }, math.floor(size * 0.8))
    f.letter:SetPoint("CENTER", 0, -1)
    f.letter:SetJustifyH("CENTER")
    return f
end

-- A quiet page-turn control: the spellbook arrow and a word in ink.
-- size: the word's font size (default QuestFont's).
function O.TurnButton(parent, text, onLeft, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(96, 28)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(onLeft and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    arrow:SetSize(28, 28)
    arrow:SetPoint(onLeft and "LEFT" or "RIGHT")
    b.arrow = arrow
    if size then
        b.label = Book.Str(b, "friz", size, Book.INK)
    else
        b.label = O.Font(b, QuestFont, GameFontHighlight, O.INK)
        if onLeft then b.label:SetPoint("LEFT", arrow, "RIGHT", 2, 0) else b.label:SetPoint("RIGHT", arrow, "LEFT", -2, 0) end
    end
    b.label:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(arrow)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.3) end)
    return b
end
