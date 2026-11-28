-- Warpath: the chronicle's Ledger tab (3.8.5)
-- Seven spreads, as docs/design/chronicle-ledger.md sets them. This file is
-- the frame they share: the footer (the game's page-turn arrows with the
-- neighbouring spreads' names, "page N of 7", the account toggle), the
-- navigation and its memory, the figures (Ledger.Stats or Ledger.Account),
-- and the drawing pieces every spread uses. Each spread is its own file
-- (ChronLedgerTally, ChronLedgerHours, ChronLedgerClasses, ChronLedgerLands,
-- ChronLedgerWilds), registers in ChronLedger.spreads[n] and is built the
-- first time it's turned to.
--
-- Every position is the spec's, in render px on the 1092x748 design canvas
-- (Book.X/Y convert); each spread keeps its numbers as data (GEOMETRY),
-- which tests compare with the built frames.
local ADDON, ns = ...
local UISound = ns.UISound
local Book, Chron = ns.Book, ns.Chron
local view = Chron.view
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC, SHADOW, LEVEL = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW, Book.LEVEL

local db, gdb, myName
ns.OnBind(function() db, gdb, myName = ns.db, ns.gdb, ns.myName end)

local LG = { spreads = {} }
ns.ChronLedger = LG

-- The spec's colours beyond the canon's.
LG.DEEP, LG.DEEP_EDGE = { 96, 14, 8 }, { 40, 6, 2 }   -- "the most": the busiest hour, day, calendar day
LG.DEATH = { 70, 46, 22 }                             -- deaths' bars and figures
LG.BAND = { 150, 34, 16 }                             -- the chosen row's band
LG.TOP_FIG = { 120, 80, 20 }                          -- an hours strip's busiest figure

local G = {
    L0 = 82, LR = 510, CX = 296, R0 = 586, RR = 1017, RCX = 801,
    head = { y = 120, px = 25, orn = 13, half = 110 },
    foot = { y = 694, navY = 692, prev = 106, next = 990, page = 801,
             arrowL = { 70.9, 671.6, 705.2 }, arrowR = 1026.1 },
    toggle = { x = 250, y = 675, w = 118, h = 26, gap = 4, px = 14 },
    only = { y = 88, px = 16 },
}
LG.G = G
LG.NAMES = { "The Tally", "The Hours", "The Classes", "My Lands", "The Foes", "The Wilds", "The Guild" }
LG.GUILD = 7       -- the spread the account view doesn't apply to

-- Memory only: the spread you left, the toggle, each spread's choices
-- (month, continent, land, folds). Gone at a /reload (Claude's call).
local state = { page = 1, account = false }
LG.state = state

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

local function Me()
    local me = ns.DisplayName and ns.DisplayName(myName or "") or myName or "You"
    return (me and me:match("^%S+")) or "You"
end
LG.Me = Me

local function Cap(s) return (s:gsub("^%l", string.upper)) end
LG.Cap = Cap

function LG.Times(n)
    if n == 1 then return "once" elseif n == 2 then return "twice" end
    return ns.NumberWord(n) .. " times"
end

-- 22 -> "ten at night", 19 -> "seven in the evening" (Claude's call on
-- where the evening ends).
function LG.HourWords(h)
    if h == 0 then return "midnight" elseif h == 12 then return "noon" end
    local twelve = h % 12
    local part = h < 12 and "in the morning" or h < 18 and "in the afternoon" or h < 22 and "in the evening" or "at night"
    return ns.NumberWord(twelve) .. " " .. part
end

-- "Tuesday, November 24"; short: "November 24"; abbr: "Nov 24".
function LG.Day(t, how)
    local d = date("*t", t)
    local month = ns.MonthName(d.month)
    if how == "short" then return month .. " " .. d.day end
    if how == "abbr" then return month:sub(1, 3) .. " " .. d.day end
    return ns.DayName(d.wday) .. ", " .. month .. " " .. d.day
end

-- 1402.6 -> "1,402.6"; 1696 -> "1,696"
function LG.Comma(v, places)
    local s = places and ("%." .. places .. "f"):format(v) or tostring(math.floor(v + 0.5))
    local int, frac = s:match("^(%d+)(.*)$")
    if not int then return s end
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return int .. frac
end

function LG.Name(key) return key and (ns.DisplayName(key) or key) or nil end

---------------------------------------------------------------------------
-- The figures: this character's, or every character's added together
---------------------------------------------------------------------------

local cache = {}

function LG.Invalidate() cache = {} end

-- account: Ledger.Account; otherwise Ledger.Stats. Inside pcall: on an
-- error the page says the Ledger couldn't be read.
function LG.Data(account)
    local k = account and "all" or "me"
    if cache[k] == nil then
        local ok, s
        if account then ok, s = pcall(ns.Ledger.Account, gdb)
        else ok, s = pcall(ns.Ledger.Stats, db, gdb) end
        if not ok then ns.Print("couldn't read the Ledger: " .. tostring(s)) end
        cache[k] = ok and s or false
    end
    return cache[k] or nil
end

-- Whose ledger it is, for the chronicler's lines: who ("Lethality", or "all
-- three characters"), poss ("Lethality's", "all three characters'"),
-- plural (the account's several characters).
function LG.Context(s, account)
    local ctx = { s = s, account = account, me = Me() }
    local n = account and #(s.chars or {}) or 1
    if n > 1 then
        ctx.who = "all " .. ns.NumberWord(n) .. " characters"
        ctx.poss, ctx.plural = ctx.who .. "'", true
    else
        local only = account and s.chars and s.chars[1]
        ctx.who = only and ((ns.DisplayName(only) or only):match("^%S+")) or ctx.me
        ctx.poss = ctx.who .. "'s"
    end
    ctx.only = account and n == 1 and ctx.who or nil
    return ctx
end

---------------------------------------------------------------------------
-- Drawing pieces. Every Set takes render px; rel/ox/oy (a scroll child and
-- its window's top-left) default to the book's top-left.
---------------------------------------------------------------------------

local function Show(fs, on)
    fs:SetShown(on)
    if fs.twin then fs.twin:SetShown(on) end
end
LG.Show = Show

function LG.Str(parent, face, px, col) return Str(parent, face, px, col) end

-- A page heading: Morpheus small caps in rubric with the 1 px shadow, the
-- ornament 13 px below (half-width 110, or 100 under a smaller heading).
function LG.Heading(parent, text, cx, y, px, half)
    px = px or G.head.px
    local h = Book.Caps(parent, "morph", px, RUBRIC, { ratio = 0.78, track = 0.6, shadow = SHADOW })
    h:Set(text, cx, y, "m")
    Book.Ornament(parent, cx, y + G.head.orn, half or (px > 24 and G.head.half or 100))
    return h
end

-- A sub-heading: Morpheus small caps 16 (lower case at 0.76), rubric, with
-- a faded hairline (0.3) to x1, 5 px above the baseline.
local Sub = {}
Sub.__index = Sub
function LG.Sub(parent, rel, ox, oy)
    return setmetatable({ caps = Book.Caps(parent, "morph", 16, RUBRIC, { ratio = 0.76, track = 0.6, shadow = SHADOW }),
        rule = Book.Solid(parent, "ARTWORK", FADED, 0.3), rel = rel, ox = ox, oy = oy }, Sub)
end
function Sub:Set(text, x, y, x1)
    local w = self.caps:Set(text, x, y, "l", self.rel, self.ox, self.oy)
    local a = math.floor(x + w + 10)
    if x1 and x1 > a then
        Book.Box(self.rule, a, y - 5, math.floor(x1), y - 4, self.rel, self.ox, self.oy)
        self.rule:Show()
    else
        self.rule:Hide()
    end
    self.width = w
    return w
end
function Sub:SetShown(on) self.caps:SetShown(on) self.rule:SetShown(on and self.width ~= nil) end

-- Friz letterspaced capitals, faded, between short rubric rules.
local Kicker = {}
Kicker.__index = Kicker
function LG.Kicker(parent, px)
    return setmetatable({ caps = Book.Caps(parent, "friz", px, FADED, { track = 1.2 }),
        rules = { Book.Rule(parent, 0, 1, 0, RUBRIC, 0.55), Book.Rule(parent, 0, 1, 0, RUBRIC, 0.55) } }, Kicker)
end
function Kicker:Set(text, cx, y, rules)
    local w = self.caps:Set(text:upper(), cx, y, "m")
    Book.Box(self.rules[1], math.floor(cx - w / 2 - rules - 12), y - 4, math.floor(cx - w / 2 - 12), y - 3)
    Book.Box(self.rules[2], math.floor(cx + w / 2 + 12), y - 4, math.floor(cx + w / 2 + rules + 12), y - 3)
    self.width = w
end

-- Column heads: Friz capitals, letterspaced 1.0.
function LG.Head(parent, px, col) return Book.Caps(parent, "friz", px or 10, col or FADED, { track = 1.0 }) end

-- A figure: EB Garamond Bold, faux bold; a zero is an en dash in EB
-- Garamond Italic, faded, two px smaller.
local Num = {}
Num.__index = Num
function LG.Num(parent, px, col, rel, ox, oy)
    local n = setmetatable({ px = px, col = col or RUBRIC, rel = rel, ox = ox, oy = oy }, Num)
    n.fig = Book.Bold(Str(parent, "garb", px, n.col))
    n.dash = Str(parent, "gari", px - 2, FADED)
    Set(n.dash, "\226\128\147")
    return n
end
-- v: a number (0 or nil: the dash) or text; align "r" (default), "l", "m"
function Num:Set(v, x, y, align, col)
    align = align or "r"
    local zero = v == nil or v == 0
    Show(self.fig, not zero)
    self.dash:SetShown(zero)
    if zero then
        Put(self.dash, x, y, align, self.rel, self.ox, self.oy)
        self.w = Wpx(self.dash)
    else
        Book.Color(self.fig, col or self.col)
        Set(self.fig, tostring(v))
        Put(self.fig, align == "r" and x - 1 or x, y, align, self.rel, self.ox, self.oy)
        self.w = Wpx(self.fig) + 1
    end
    return self.w
end
function Num:Hide() Show(self.fig, false) self.dash:Hide() end

-- A reckoning row: Friz label, hairline leader, EB Garamond Bold value in
-- rubric; or a value not yet counted ("none yet", "none") in faded italic
-- at the label's size, the leader fainter.
local Row = {}
Row.__index = Row
function LG.Row(parent, lpx, vpx, rel, ox, oy)
    local r = setmetatable({ rel = rel, ox = ox, oy = oy }, Row)
    r.label = Str(parent, "friz", lpx, INK)
    r.value = Book.Bold(Str(parent, "garb", vpx, RUBRIC))
    r.quiet = Str(parent, "gari", lpx, FADED)
    r.rule = Book.Solid(parent, "ARTWORK", INK, 0.38)
    return r
end
function Row:Set(label, value, x0, x1, y, quiet)
    local o = { self.rel, self.ox, self.oy }
    Set(self.label, label)
    Put(self.label, x0, y, "l", o[1], o[2], o[3])
    self.label:Show()
    local vw
    Show(self.value, not quiet)
    self.quiet:SetShown(quiet and true or false)
    if quiet then
        Set(self.quiet, value)
        Put(self.quiet, x1, y, "r", o[1], o[2], o[3])
        vw = Wpx(self.quiet)
    else
        Set(self.value, value)
        Put(self.value, x1 - 1, y, "r", o[1], o[2], o[3])
        vw = Wpx(self.value) + 1
    end
    local lx = math.floor(x0 + Wpx(self.label) + 10)
    local rx = math.floor(x1 - vw - 10)
    self.rule:SetAlpha(quiet and 0.25 / 0.38 or 1)
    Book.Box(self.rule, lx, y - 1, math.max(lx + 0.01, rx), y, o[1], o[2], o[3])
    self.rule:SetShown(rx > lx)
    self.y = y
end
function Row:Hide() self.label:Hide() Show(self.value, false) self.quiet:Hide() self.rule:Hide() end

-- An inked bar, 9 px tall, ending 1 px above y (directions.py bar()): the
-- top row lighter.
local Bar = {}
Bar.__index = Bar
function LG.Bar(parent, col, a, rel, ox, oy)
    local b = setmetatable({ rel = rel, ox = ox, oy = oy }, Bar)
    b.top = Book.Solid(parent, "ARTWORK", col or RUBRIC, (a or 0.78) * 0.75)
    b.body = Book.Solid(parent, "ARTWORK", col or RUBRIC, a or 0.78)
    return b
end
function Bar:Set(x0, x1, y)
    x0, x1 = math.floor(x0), math.floor(x1)
    local on = x1 > x0
    self.top:SetShown(on)
    self.body:SetShown(on)
    if on then
        Book.Box(self.top, x0, y - 9, x1, y - 8, self.rel, self.ox, self.oy)
        Book.Box(self.body, x0, y - 8, x1, y, self.rel, self.ox, self.oy)
    end
    self.x0, self.x1 = x0, x1
end
function Bar:Hide() self.top:Hide() self.body:Hide() end

-- A class tile: the canon's red tile with the client's class icon; the
-- unknown class shows the question-mark icon.
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
function LG.Tile(parent, rel, ox, oy) return Book.Tile(parent, rel, ox, oy) end
function LG.SetTile(t, class, x, y, size)
    local known = class and class ~= "unknown" and class ~= "UNKNOWN"
    t:Set("red", known and class or nil, x, y, size)
    if not known then
        t.q:Hide()
        t.icon:SetTexture(QMARK)
        t.icon:SetTexCoord(0, 1, 0, 1)
        t.icon:SetAlpha(1)
        Book.Box(t.icon, x + 2, y + 2, x + size - 2, y + size - 2, t.rel, t.ox, t.oy)
        t.icon:Show()
    end
end

-- A name in N2 class colour with a black shadow, then its level in Friz 3
-- pt smaller in the level colour. An unknown class: faded, no shadow.
local Nm = {}
Nm.__index = Nm
function LG.NameStr(parent, px, rel, ox, oy)
    local n = setmetatable({ px = px, rel = rel, ox = ox, oy = oy }, Nm)
    n.name = Str(parent, "friz", px, INK)
    n.level = Str(parent, "friz", px - 3, LEVEL)
    return n
end
function Nm:Set(text, class, lv, x, y)
    Set(self.name, text or "")
    local col = class and Book.N2(class)
    if col then
        Book.Color(self.name, col)
        Book.Shadow(self.name)
    else
        Book.Color(self.name, FADED)
        self.name:SetShadowOffset(0, 0)
    end
    Put(self.name, x, y, "l", self.rel, self.ox, self.oy)
    self.name:Show()
    local w = Wpx(self.name)
    local lv_ = type(lv) == "number" and (lv == -1 and "??" or lv > 0 and tostring(lv)) or nil
    self.level:SetShown(lv_ ~= nil)
    if lv_ then
        Set(self.level, lv_)
        Put(self.level, x + w + 5, y, "l", self.rel, self.ox, self.oy)
        w = w + 5 + Wpx(self.level)
    end
    self.w = w
    return w
end
function Nm:Hide() self.name:Hide() self.level:Hide() end

-- Centred italic lines wrapped to a width: Set returns the baseline after
-- the last line.
local Lines = {}
Lines.__index = Lines
function LG.Lines(parent, px, col, rel, ox, oy)
    return setmetatable({ parent = parent, px = px, col = col or FADED, strs = {}, rel = rel, ox = ox, oy = oy }, Lines)
end
function Lines:Set(text, cx, y, width, lh, align)
    local lines, line = {}, ""
    if type(text) == "table" then
        lines = text
    else
        for word in (text or ""):gmatch("%S+") do
            local cand = line == "" and word or (line .. " " .. word)
            if line ~= "" and Book.Measure("gari", self.px, cand) > width then
                lines[#lines + 1] = line
                line = word
            else
                line = cand
            end
        end
        if line ~= "" then lines[#lines + 1] = line end
    end
    for i, s in ipairs(lines) do
        local fs = self.strs[i]
        if not fs then fs = Str(self.parent, "gari", self.px, self.col) self.strs[i] = fs end
        Set(fs, s)
        Put(fs, cx, y, align or "m", self.rel, self.ox, self.oy)
        fs:Show()
        y = y + (lh or 21)
    end
    for i = #lines + 1, #self.strs do self.strs[i]:Hide() end
    self.n = #lines
    return y
end
function Lines:Hide() for _, fs in ipairs(self.strs) do fs:Hide() end end

-- A straight piece from (ax, ay) to (bx, by), w px thick: a turned texture.
function LG.Line(t, ax, ay, bx, by, w, rel, ox, oy)
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    t:SetSize(math.max(0.01, len / 1.2), w / 1.2)
    t:ClearAllPoints()
    t:SetPoint("CENTER", rel or t:GetParent(), "TOPLEFT", Book.X((ax + bx) / 2, ox), Book.Y((ay + by) / 2, oy))
    t:SetRotation(-math.atan2(by - ay, bx - ax))
    t:Show()
end

-- A circle of n short turned pieces.
local Ring = {}
Ring.__index = Ring
function LG.Ring(parent, n, layer, sub)
    local r = setmetatable({ tex = {}, n = n }, Ring)
    for i = 1, n do r.tex[i] = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub) end
    return r
end
function Ring:Set(cx, cy, rad, col, a, w, rel, ox, oy)
    local cr, cg, cb = Book.RGB(col)
    for i = 1, self.n do
        local a1, a2 = (i - 1) / self.n * 2 * math.pi, i / self.n * 2 * math.pi
        local t = self.tex[i]
        t:SetColorTexture(cr, cg, cb, a)
        -- each piece a touch long so the joins don't open
        local ext = 0.12 / self.n * 2 * math.pi
        LG.Line(t, cx + rad * math.sin(a1 - ext), cy - rad * math.cos(a1 - ext),
            cx + rad * math.sin(a2 + ext), cy - rad * math.cos(a2 + ext), w or 1, rel, ox, oy)
    end
end
function Ring:SetShown(on) for _, t in ipairs(self.tex) do t:SetShown(on) end end

-- A frame that shows a tooltip and answers a click.
function LG.Hot(parent, tip, click)
    local b = CreateFrame("Button", nil, parent)
    b.tip, b.click = tip, click
    b:SetScript("OnEnter", function(self)
        if self.tip and GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tip(self) ~= false then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self) if self.click then self.click(self) end end)
    return b
end

-- The game's red button (UIPanelButtonTemplate) with its label in Friz 14;
-- the off state is the template's disabled art (darkened, greyed) with a
-- grey label, still clickable through a catcher; "dead" is off and inert.
local Btn = {}
Btn.__index = Btn
function LG.Button(parent, onClick)
    local b = setmetatable({ parent = parent }, Btn)
    b.frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b.frame:SetScript("OnClick", function() if onClick then onClick() end end)
    b.label = Str(b.frame, "friz", G.toggle.px, { 255, 209, 0 })
    Book.Shadow(b.label)
    b.catch = CreateFrame("Button", nil, b.frame)
    b.catch:SetAllPoints(b.frame)
    b.catch:SetScript("OnClick", function() if onClick then onClick() end end)
    return b
end
-- (x, y) top-left, w x h render px; how: "on", "off" or "dead"
function Btn:Set(text, x, y, w, h, how)
    Book.Box(self.frame, x, y, x + w, y + h)
    Set(self.label, text)
    Put(self.label, x + w / 2, y + h / 2 + 5, "m", self.parent)
    if how == "on" then self.frame:Enable() else self.frame:Disable() end
    self.catch:SetShown(how == "off")
    Book.Color(self.label, how == "on" and { 255, 209, 0 } or how == "off" and { 150, 150, 150 } or { 92, 86, 78 })
    self.how = how
end

-- The game's page-turn arrow (the Campaigns footer's), its visible square's
-- top-left at (vx, vy): the texture has a margin round it.
function LG.Arrow(parent, left, onClick)
    local b = Book.Old.TurnButton(parent, "", left, 18)
    b:SetScript("OnClick", onClick)
    return b
end
function LG.PlaceArrow(b, left, vx, vy)
    local dx = left and 3.0 or 4.4
    Book.Box(b, vx - dx, vy - 4.4, vx - dx + 33.6, vy - 4.4 + 33.6)
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------

local function Tip(line, r, g, b, wrap) GameTooltip:AddLine(line, r or 1, g or 1, b or 1, wrap) end
LG.Tip = Tip

-- A foe: name, level, class, race and guild, then this character's kills
-- of them and deaths to them, and the grudge state.
function LG.FoeTip(f, e)
    local r, g, b = 0.9, 0.9, 0.9
    if e.c and e.c ~= "unknown" and ns.ClassColor then r, g, b = ns.ClassColor(e.c) end
    Tip(LG.Name(f) or e.n or "Unknown", r, g, b)
    local desc = ns.Foes.Describe(type(e.lv) == "number" and e.lv > 0 and e.lv or nil, e.ra,
        e.c ~= "unknown" and e.c or nil, nil)
    if desc ~= "" then Tip((type(e.lv) == "number" and e.lv > 0 and "Level " or "") .. desc) end
    if e.gu then Tip("<" .. e.gu .. ">", 0.8, 0.8, 0.8) end
    local slain = f and db and db.victims and db.victims[f] or 0
    local slew = f and gdb and gdb.killers and gdb.killers[f] or 0
    if slain > 0 then Tip(Me() .. " slew them " .. LG.Times(slain), 1, 0.82, 0) end
    if slew > 0 then Tip("They slew " .. Me() .. " " .. LG.Times(slew), 1, 0.5, 0.4) end
    if f and ns.Grudge.Get(f) then Tip("Grudge held: click to open it", 0.8, 0.25, 0.2) end
end

function LG.HourTip(h, n, what)
    Tip(("%d:00\226\128\147%d:59 \226\128\148 %d %s"):format(h, h, n or 0, what or "slain"))
end

---------------------------------------------------------------------------
-- Other tabs: a campaign, a grudge
---------------------------------------------------------------------------

-- Open the campaign that started at `start` on the Campaigns tab.
function LG.OpenCampaign(start)
    if view.preview or not start then return end
    local camp = Chron.pages.campaigns
    view.section = "campaigns"
    if camp and camp.Open then camp.Open(false) end
    if camp and camp.Reset then camp.Reset(Chron.book) end
    for i, c in ipairs(view.list or {}) do if c.start == start then view.page = i end end
    UISound("IG_ABILITY_PAGE_TURN", 836)
    Chron.Render()
end

-- Open a grudge on the Grudges tab (the page's own hook when it has one).
function LG.OpenGrudge(f)
    if view.preview or not f then return end
    local key = ns.Grudge.Key(f)
    if not key then return end
    UISound("IG_ABILITY_PAGE_TURN", 836)
    if Chron.OpenGrudge then return Chron.OpenGrudge(key) end
    view.section = "grudges"
    Chron.Render()
    for i, item in ipairs(view.grudges or {}) do if item.full == key then view.pick = i end end
    Chron.Render()
end

---------------------------------------------------------------------------
-- The frame: two page frames, the footer, the spreads
---------------------------------------------------------------------------

local P   -- the tab's frames, once built

local Render

local function Turn(to)
    if to < 1 or to > #LG.NAMES or to == state.page then return end
    state.page = to
    UISound("IG_ABILITY_PAGE_TURN", 836)
    Chron.Render()
end
LG.Turn = Turn

local function SetAccount(on)
    if state.page == LG.GUILD or state.account == on then return end
    state.account = on
    UISound(on and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF", 856)
    Chron.Render()
end

local function BuildFooter(L)
    local f = G.foot
    P.prev = LG.Arrow(L, true, function() Turn(state.page - 1) end)
    P.next = LG.Arrow(L, false, function() Turn(state.page + 1) end)
    P.count = Str(L, "narrow", 15, FADED)
    P.me = LG.Button(L, function() SetAccount(false) end)
    P.all = LG.Button(L, function() SetAccount(true) end)
    P.all.frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if state.page == LG.GUILD then
            Tip("All characters")
            Tip("The guild's war is this character's own: characters can be in different guilds.", 0.8, 0.8, 0.8, true)
        else
            Tip("All characters")
            Tip("Every character's ledger added together.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    P.all.frame:SetScript("OnLeave", GameTooltip_Hide)
    P.all.catch:SetScript("OnEnter", function() P.all.frame:GetScript("OnEnter")(P.all.frame) end)
    P.all.catch:SetScript("OnLeave", GameTooltip_Hide)
    P.only = { Str(L, "gari", G.only.px, FADED), Str(L, "gari", G.only.px, FADED) }
    P.failed = Str(L, "gari", 18, FADED)
    Set(P.failed, "The Ledger couldn't be read.")
    Put(P.failed, G.CX, 380, "m")
end

local function Build(book)
    local L = CreateFrame("Frame", nil, book)
    L:SetAllPoints(book)
    local R = CreateFrame("Frame", nil, book)
    R:SetAllPoints(book)
    P = { L = L, R = R, built = {} }
    book.ledger = P
    BuildFooter(L)
end

-- A spread's frames, built the first time it's shown.
local function Spread(n)
    local F = P.built[n]
    if not F then
        local sp = LG.spreads[n]
        if not sp then return end
        F = { L = CreateFrame("Frame", nil, P.L), R = CreateFrame("Frame", nil, P.R), n = n }
        F.L:SetAllPoints(P.L)
        F.R:SetAllPoints(P.R)
        sp.Build(F)
        P.built[n] = F
    end
    return F
end
LG.Spread = function(n) return P and Spread(n) end

local function LayFooter(n)
    local f, t = G.foot, G.toggle
    local names = LG.NAMES
    P.prev:SetShown(n > 1)
    if n > 1 then
        local text = names[n - 1]
        Set(P.prev.label, text)
        local w = Book.Measure("friz", 18, text)
        Book.Box(P.prev, f.arrowL[1], f.arrowL[2], math.max(f.arrowL[1] + 96 * 1.2, f.prev + w + 4), f.arrowL[3])
        Put(P.prev.label, f.prev, f.navY, "l", P.L)
    end
    P.next:SetShown(n < #names)
    if n < #names then
        local text = names[n + 1]
        Set(P.next.label, text)
        local w = Book.Measure("friz", 18, text)
        Book.Box(P.next, math.min(f.arrowR - 96 * 1.2, f.next - w - 4), f.arrowL[2], f.arrowR, f.arrowL[3])
        Put(P.next.label, f.next, f.navY, "r", P.L)
    end
    Set(P.count, "page " .. n .. " of " .. #names)
    Put(P.count, f.page, f.y, "m")
    local guild = n == LG.GUILD
    local account = state.account and not guild
    P.me:Set(Me(), t.x, t.y, t.w, t.h, account and "off" or "on")
    P.all:Set("All characters", t.x + t.w + t.gap, t.y, t.w, t.h, guild and "dead" or (account and "on" or "off"))
end

function Render()
    if not P then return end
    local book = Chron.book
    book.left.number:SetText("")
    book.right.number:SetText("")
    local n = state.page
    local guild = n == LG.GUILD
    local account = state.account and not guild
    local s = LG.Data(account)
    for k, F in pairs(P.built) do
        F.L:SetShown(k == n and s ~= nil)
        F.R:SetShown(k == n and s ~= nil)
    end
    P.failed:SetShown(s == nil)
    local ctx = s and LG.Context(s, account)
    local F = s and Spread(n)
    if F then
        F.L:Show()
        F.R:Show()
        LG.spreads[n].Render(F, ctx)
    end
    local only = ctx and ctx.only
    for i, fs in ipairs(P.only) do
        fs:SetShown(only ~= nil)
        if only then
            Set(fs, "Only " .. only .. " has opened the chronicle since 3.8.5.")
            Put(fs, i == 1 and G.CX or G.RCX, G.only.y, "m")
        end
    end
    LayFooter(n)
end
LG.Render = Render

-- The guild roster's notes, ranks and levels: ask the client for them when
-- the book opens, and draw again when they arrive while the Guild spread shows.
local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function()
    if state.page == LG.GUILD and Chron.book and Chron.book:IsShown() and view.section == "ledger" then
        cache.me = nil
        Chron.Render()
    end
end)
if ev.RegisterEvent then pcall(ev.RegisterEvent, ev, "GUILD_ROSTER_UPDATE") end

local function AskRoster()
    if not (IsInGuild and IsInGuild()) then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster)
    elseif GuildRoster then pcall(GuildRoster) end
end

Chron.pages.ledger = {
    Build = Build,
    Render = Render,
    Open = function() LG.Invalidate() AskRoster() end,
    Refresh = function() LG.Invalidate() end,
}

function LG.Frames() return P end
