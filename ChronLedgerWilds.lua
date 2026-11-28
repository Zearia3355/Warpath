-- Warpath: the Ledger's sixth and seventh spreads (3.8.5):
-- The Wilds | Where the Wilds Strike (F6), The Guild's War | The Guild's
-- Lands (F7). docs/design/chronicle-ledger.md, spreads 6 and 7.
local ADDON, ns = ...
local Book, LG = ns.Book, ns.ChronLedger
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC, SHADOW = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW
local L0, LR, CX, R0, RR, RCX = LG.G.L0, LG.G.LR, LG.G.CX, LG.G.R0, LG.G.RR, LG.G.RCX

local G = {
    strip = { labels = 15, figure = 5 },
    wilds = { fig = 200, figPx = 50, cap = 222, sub = 262,
              sheet = { 72, 276, 518, 668 }, win = { 74, 280, 516, 664 }, cord = { 509, 286, 658 },
              head = 290, first = 316, step = 25, name = 86, count = 490 },
    where = { sheet = { 576, 146, 1025, 452 }, win = { 578, 150, 1023, 448 }, cord = { 1016, 156, 442 },
              head = 160, first = 186, step = 24, name = 590, leader = 967, count = 995,
              sub = 490, strip = { 606, 997, 580, 56 }, line = 630 },
    guild = { kicker = 156, sheet = { 72, 172, 518, 664 }, win = { 74, 176, 516, 660 }, cord = { 509, 182, 654 },
              head = 186, first = 216, step = 46, tile = 84, name = 114, slain = 426, fallen = 490, none = 200 },
    glands = { sheet = { 576, 146, 1025, 430 }, win = { 578, 150, 1023, 426 }, cord = { 1016, 156, 420 },
               head = 160, first = 186, step = 24, name = 590, slain = 947, fallen = 995,
               sub = 466, strip = { 606, 997, 560, 56 }, line = 612 },
}
LG.WILDS = G

---------------------------------------------------------------------------
-- The hours strip: 24 bars on a baseline, the busiest in deep rubric with
-- its figure above (directions.py hours_strip, deep rubric for gilt).
---------------------------------------------------------------------------

local Strip = {}
Strip.__index = Strip

function LG.Strip(parent, x0, x1, base, hgt, what)
    local s = setmetatable({ x0 = x0, x1 = x1, base = base, hgt = hgt, bars = {}, what = what }, Strip)
    Book.Rect(parent, "ARTWORK", INK, 0.45, x0, base + 1, x1, base + 2)
    local step = (x1 - x0) / 24
    for h = 0, 23 do
        local b = { bar = Book.Solid(parent, "ARTWORK", RUBRIC, 0.72), dot = Book.Solid(parent, "ARTWORK", FADED, 0.4),
            hot = LG.Hot(parent, function(self) LG.HourTip(self.h, self.n, s.what) end) }
        b.hot.h = h
        local bx = x0 + h * step
        Book.Box(b.dot, math.floor(bx + step / 2 - 1), base, math.floor(bx + step / 2 + 1), base + 1)
        Book.Box(b.hot, bx, base - hgt - 4, bx + step, base + 4)
        s.bars[h] = b
    end
    s.top = Book.Solid(parent, "ARTWORK", LG.TOP_FIG, 0.9)
    s.fig = Book.Bold(Str(parent, "garb", 15, LG.TOP_FIG))
    for h, label in pairs({ [0] = "midnight", [6] = "6", [12] = "noon", [18] = "18" }) do
        local fs = Str(parent, "narrow", 13, FADED)
        Set(fs, label)
        Put(fs, x0 + h * step + step / 2, base + G.strip.labels, "m")
    end
    return s
end

function Strip:Set(hours)
    local top, busiest = 0, nil
    for h = 0, 23 do if (hours[h] or 0) > top then top, busiest = hours[h], h end end
    local step = (self.x1 - self.x0) / 24
    for h = 0, 23 do
        local b, v = self.bars[h], hours[h] or 0
        b.hot.n = v
        b.dot:SetShown(v == 0)
        b.bar:SetShown(v > 0)
        if v > 0 then
            local hh = math.max(3, math.floor(self.hgt * v / top))
            local bx = self.x0 + h * step
            Book.Box(b.bar, math.floor(bx + 2), self.base - hh + 1, math.floor(bx + step - 2), self.base + 1)
            local deep = h == busiest
            local r, g, bl = Book.RGB(deep and LG.DEEP or RUBRIC)
            b.bar:SetColorTexture(r, g, bl, deep and 0.95 or 0.72)
            if deep then
                Book.Box(self.top, math.floor(bx + 2), self.base - hh, math.floor(bx + step - 2), self.base - hh + 1)
                Set(self.fig, tostring(v))
                Put(self.fig, bx + step / 2, self.base - hh - G.strip.figure, "m")
            end
        end
    end
    self.top:SetShown(busiest ~= nil)
    LG.Show(self.fig, busiest ~= nil)
    return busiest, top
end

---------------------------------------------------------------------------
-- Sheet rows: a frame per row (for the sheet's fades), its strings placed
-- on the scroll child
---------------------------------------------------------------------------

local function Pool(list, i, make)
    if not list[i] then list[i] = make() end
    return list[i]
end

---------------------------------------------------------------------------
-- Spread 6: The Wilds | Where the Wilds Strike
---------------------------------------------------------------------------

local P6

local CAUSE = { fall = "A fall", drown = "Drowning", fatigue = "Fatigue" }

local function Build6(F)
    local L, R = F.L, F.R
    local w, g = G.wilds, G.where
    P6 = {}
    LG.WILDS.P6 = P6
    LG.Heading(L, "The Wilds", CX, LG.G.head.y)
    P6.fig = Book.Bold(Str(L, "garb", w.figPx, RUBRIC))
    Book.Shadow(P6.fig, SHADOW)
    LG.Head(L, 11, FADED):Set("DEATHS TO BEAST AND WORLD, NOT TO PLAYERS", CX, w.cap, "m")
    P6.sub = LG.Sub(L)
    P6.causes = Book.Sheet(L, w.sheet, w.win, w.cord)
    P6.causeHead = LG.Head(P6.causes.child, 10, FADED)
    P6.causeRows = {}
    LG.Heading(R, "Where the Wilds Strike", RCX, LG.G.head.y)
    P6.lands = Book.Sheet(R, g.sheet, g.win, g.cord)
    P6.landHead = LG.Head(P6.lands.child, 10, FADED)
    P6.landRows = {}
    LG.Sub(R):Set("At what hour", R0, g.sub, RR)
    P6.strip = LG.Strip(R, g.strip[1], g.strip[2], g.strip[3], g.strip[4], "fell to the wilds")
    P6.line = LG.Lines(R, 16, FADED)
end

local function CauseRow(i)
    return Pool(P6.causeRows, i, function()
        local w = G.wilds
        local ch, ox, oy = P6.causes.child, w.win[1], w.win[2]
        local f = CreateFrame("Frame", nil, ch)
        return { frame = f, name = Str(f, "friz", 17, INK), kind = Str(f, "gari", 14, FADED),
            quiet = Str(f, "gari", 16, FADED), quiet17 = Str(f, "gari", 17, FADED), num = LG.Num(f, 18, RUBRIC, ch, ox, oy), o = { ch, ox, oy } }
    end)
end

local function LayCauses(wilds)
    local w = G.wilds
    local sheet = P6.causes
    local ch, ox, oy = sheet.child, w.win[1], w.win[2]
    sheet:Clear()
    local causes = wilds.causes or {}
    P6.causeHead:Set("DEATHS", w.count, w.head, "r", ch, ox, oy)
    local y, n = w.first, 0
    for _, c in ipairs(causes) do
        n = n + 1
        local r = CauseRow(n)
        Set(r.name, c.how == "beast" and (c.cause or "A creature") or CAUSE[c.how] or c.cause or "?")
        Put(r.name, w.name, y, "l", ch, ox, oy)
        r.name:Show()
        Set(r.kind, c.how == "beast" and "beast" or "the world")
        Put(r.kind, w.name + 6 + Wpx(r.name), y, "l", ch, ox, oy)
        r.kind:Show()
        r.quiet:Hide()
        r.quiet17:Hide()
        r.num:Set(c.n, w.count, y, "r", RUBRIC)
        Book.Box(r.frame, w.win[1], y - 18, w.win[3], y + 6, ch, ox, oy)
        sheet:Add(r.frame, y - 18 - oy, y + 6 - oy)
        r.frame:Show()
        y = y + w.step
    end
    if (wilds.unrecorded or 0) > 0 then
        n = n + 1
        local r = CauseRow(n)
        -- 16 under recorded causes, 17 alone (two strings: no face changes)
        local q = #causes > 0 and r.quiet or r.quiet17
        local other = q == r.quiet and r.quiet17 or r.quiet
        Set(q, #causes > 0 and "Not recorded (before this version)" or "Not recorded")
        Put(q, w.name, y, "l", ch, ox, oy)
        q:Show()
        other:Hide()
        r.name:Hide()
        r.kind:Hide()
        r.num:Set(wilds.unrecorded, w.count, y, "r", FADED)
        Book.Box(r.frame, w.win[1], y - 18, w.win[3], y + 6, ch, ox, oy)
        sheet:Add(r.frame, y - 18 - oy, y + 6 - oy)
        r.frame:Show()
        y = y + w.step
    end
    for i = n + 1, #P6.causeRows do P6.causeRows[i].frame:Hide() end
    sheet:SetContent(n > 0 and (y - w.head + 12) or 0)
end

local function LandRow(i, sheet, list, win, leader)
    return Pool(list, i, function()
        local ch, ox, oy = sheet.child, win[1], win[2]
        local f = LG.Hot(ch, function(self)
            LG.Tip(ns.MapName(self.land) or "?")
            LG.Tip(self.text, 1, 0.82, 0)
        end)
        local r = { frame = f, name = Str(f, "gari", 17, INK), a = LG.Num(f, 18, RUBRIC, ch, ox, oy),
            b = LG.Num(f, 17, INK, ch, ox, oy) }
        if leader then r.rule = Book.Solid(f, "ARTWORK", FADED, 0.3) end
        return r
    end)
end

local function Ranked(map, total)
    local list = {}
    for id, v in pairs(map or {}) do
        local n = total(v)
        if n > 0 then list[#list + 1] = { id, v, n } end
    end
    table.sort(list, function(a, b)
        if a[3] ~= b[3] then return a[3] > b[3] end
        return (ns.MapName(a[1]) or "") < (ns.MapName(b[1]) or "")
    end)
    return list
end

local function LayWhere(wilds)
    local g = G.where
    local sheet = P6.lands
    local ch, ox, oy = sheet.child, g.win[1], g.win[2]
    sheet:Clear()
    P6.landHead:Set("DEATHS TO THE WILDS", g.count, g.head, "r", ch, ox, oy)
    local list = Ranked(wilds.lands, function(v) return v end)
    local y = g.first
    for i, e in ipairs(list) do
        local r = LandRow(i, sheet, P6.landRows, g.win, true)
        r.frame.land, r.frame.text = e[1], e[3] .. (e[3] == 1 and " death" or " deaths") .. " to the wilds"
        Set(r.name, ns.MapName(e[1]) or "?")
        Put(r.name, g.name, y, "l", ch, ox, oy)
        local a = math.floor(g.name + 6 + Wpx(r.name))
        Book.Box(r.rule, a, y - 4, math.max(a + 0.01, g.leader), y - 3, ch, ox, oy)
        r.a:Set(e[3], g.count, y, "r")
        r.b:Hide()
        Book.Box(r.frame, g.win[1], y - 18, g.win[3], y + 6, ch, ox, oy)
        sheet:Add(r.frame, y - 18 - oy, y + 6 - oy)
        r.frame:Show()
        y = y + g.step
    end
    for i = #list + 1, #P6.landRows do P6.landRows[i].frame:Hide() end
    sheet:SetContent(#list > 0 and (y - g.head + 12) or 0)
end

local function Render6(F, ctx)
    local wilds = ctx.s.wilds or {}
    local w, g = G.wilds, G.where
    Set(P6.fig, tostring(wilds.total or 0))
    Put(P6.fig, CX, w.fig, "m")
    P6.sub:Set("What killed " .. ctx.who, L0, w.sub, LR)
    LayCauses(wilds)
    LayWhere(wilds)
    local busiest = P6.strip:Set(wilds.hours or {})
    if busiest then
        P6.line:Set({ "The wilds take " .. ctx.who .. " most often at " .. LG.HourWords(busiest) .. "." }, RCX, g.line)
    else
        P6.line:Set({ "The wilds have not taken " .. ctx.who .. " yet." }, RCX, g.line)
    end
end

LG.spreads[6] = { Build = Build6, Render = Render6, only = { 801, 664 } }

---------------------------------------------------------------------------
-- Spread 7: The Guild's War | The Guild's Lands (this character only)
---------------------------------------------------------------------------

local P7

local function MateTip(self)
    local e = self.e
    if not e then return false end
    local r, g, b = 0.9, 0.9, 0.9
    if e.class and ns.ClassColor then r, g, b = ns.ClassColor(e.class) end
    LG.Tip(LG.Name(e.name) or e.name, r, g, b)
    local desc = ns.Foes.Describe(e.level, nil, e.class, nil)
    if desc ~= "" then LG.Tip((e.level and "Level " or "") .. desc) end
    if e.rank then LG.Tip(e.rank, 0.8, 0.8, 0.8) end
    LG.Tip(e.kills .. " slain, " .. e.deaths .. " fallen", 1, 0.82, 0)
    if #(e.victims or {}) > 0 then
        LG.Tip("Slew:", 1, 1, 1)
        for i = 1, math.min(10, #e.victims) do
            local v = e.victims[i]
            local name = LG.Name(v.n) or "someone unseen"
            if v.c and ns.ClassName then name = name .. " (" .. ns.ClassName(v.c) .. ")" end
            LG.Tip("  " .. name, 0.8, 0.8, 0.8)
        end
    end
end

local function Build7(F)
    local L, R = F.L, F.R
    local g, gl = G.guild, G.glands
    P7 = {}
    LG.WILDS.P7 = P7
    LG.Heading(L, "The Guild's War", CX, LG.G.head.y)
    LG.Heading(R, "The Guild's Lands", RCX, LG.G.head.y)
    P7.none = Str(L, "gari", 17, FADED)
    P7.inner = { CreateFrame("Frame", nil, L), CreateFrame("Frame", nil, R) }
    for _, f in ipairs(P7.inner) do f:SetAllPoints(f:GetParent()) end
    local IL, IR = P7.inner[1], P7.inner[2]
    P7.kicker = LG.Kicker(IL, 11)
    P7.sheet = Book.Sheet(IL, g.sheet, g.win, g.cord)
    local ch = P7.sheet.child
    local o = { ch, g.win[1], g.win[2] }
    P7.heads = { LG.Head(ch, 10, RUBRIC), LG.Head(ch, 10, FADED) }
    P7.rows = {}
    P7.lands = Book.Sheet(IR, gl.sheet, gl.win, gl.cord)
    local lc = P7.lands.child
    P7.landHeads = { LG.Head(lc, 10, RUBRIC), LG.Head(lc, 10, FADED) }
    P7.landRows = {}
    P7.noWord = Str(lc, "gari", 16, FADED)
    Set(P7.noWord, "No word from the guild yet.")
    Put(P7.noWord, gl.name, gl.first, "l", lc, gl.win[1], gl.win[2])
    LG.Sub(IR):Set("The guild's hours", R0, gl.sub, RR)
    P7.strip = LG.Strip(IR, gl.strip[1], gl.strip[2], gl.strip[3], gl.strip[4], "slain by the guild")
    P7.line = LG.Lines(IR, 15, FADED)
end

local function MateRow(i)
    return Pool(P7.rows, i, function()
        local g = G.guild
        local ch, ox, oy = P7.sheet.child, g.win[1], g.win[2]
        local f = LG.Hot(ch, MateTip)
        return { frame = f, band = Book.Band(f, ch, ox, oy, LG.BAND, 64 / 255), pointer = Book.Chevron(f, ch, ox, oy),
            tile = LG.Tile(f, ch, ox, oy), name = LG.NameStr(f, 18, ch, ox, oy), you = Str(f, "gari", 15, RUBRIC),
            detail = Str(f, "gari", 14, FADED), k = LG.Num(f, 19, RUBRIC, ch, ox, oy), d = LG.Num(f, 18, INK, ch, ox, oy) }
    end)
end

local function LayMates(guild)
    local g = G.guild
    local sheet = P7.sheet
    local ch, ox, oy = sheet.child, g.win[1], g.win[2]
    sheet:Clear()
    local y = g.first
    for i, e in ipairs(guild.mates or {}) do
        local r = MateRow(i)
        r.frame.e = e
        Book.Box(r.frame, g.win[1], y - 22, g.win[3], y + 24, ch, ox, oy)
        if e.me then r.band:Set(L0 - 6, LR - 10, y - 21, y + 23, true, true) else r.band:Hide() end
        r.pointer:SetShown(e.me and true or false)
        if e.me then r.pointer:Set(false, L0 - 8, y - 2) end
        LG.SetTile(r.tile, e.class, g.tile, y - 17, 22)
        local w = r.name:Set(LG.Name(e.name) or e.name, e.class, e.level, g.name, y)
        r.you:SetShown(e.me and true or false)
        if e.me then
            Set(r.you, "(you)")
            Put(r.you, g.name + w + 6, y, "l", ch, ox, oy)
        end
        local note = e.note and e.note ~= "" and ("\194\183 \226\128\156" .. e.note .. "\226\128\157") or nil
        local detail = e.rank and (e.rank .. (note and (" " .. note) or "")) or (note and note:sub(4)) or ""
        Set(r.detail, detail)
        Put(r.detail, g.name, y + 17, "l", ch, ox, oy)
        r.k:Set(e.kills, g.slain, y, "r")
        r.d:Set(e.deaths, g.fallen, y, "r")
        sheet:Add(r.frame, y - 22 - oy, y + 24 - oy)
        r.frame:Show()
        y = y + g.step
    end
    for i = #(guild.mates or {}) + 1, #P7.rows do P7.rows[i].frame:Hide() end
    sheet:SetContent(y - g.head + 12 - g.step + 24)
end

local function LayGuildLands(guild)
    local gl = G.glands
    local sheet = P7.lands
    local ch, ox, oy = sheet.child, gl.win[1], gl.win[2]
    sheet:Clear()
    local list = Ranked(guild.lands, function(v) return v.kills + v.deaths end)
    P7.noWord:SetShown(#list == 0)
    local y = gl.first
    for i, e in ipairs(list) do
        local r = LandRow(i, sheet, P7.landRows, gl.win)
        r.frame.land, r.frame.text = e[1], e[2].kills .. " slain, " .. e[2].deaths .. " fallen"
        Set(r.name, ns.MapName(e[1]) or "?")
        Put(r.name, gl.name, y, "l", ch, ox, oy)
        r.a:Set(e[2].kills, gl.slain, y, "r")
        r.b:Set(e[2].deaths, gl.fallen, y, "r")
        Book.Box(r.frame, gl.win[1], y - 18, gl.win[3], y + 6, ch, ox, oy)
        sheet:Add(r.frame, y - 18 - oy, y + 6 - oy)
        r.frame:Show()
        y = y + gl.step
    end
    for i = #list + 1, #P7.landRows do P7.landRows[i].frame:Hide() end
    sheet:SetContent(#list > 0 and (y - gl.head + 12) or 0)
end

local function Render7(F, ctx)
    local guild = ctx.s.guild or { mates = {}, lands = {}, hours = {} }
    local inGuild = guild.inGuild or #(guild.mates or {}) > 1
    for _, f in ipairs(P7.inner) do f:SetShown(inGuild and true or false) end
    P7.none:SetShown(not inGuild)
    if not inGuild then
        Set(P7.none, ctx.who .. " rides with no guild.")
        Put(P7.none, CX, G.guild.none, "m")
        return
    end
    local g, gl = G.guild, G.glands
    local since = guild.first and ("  \194\183  since " .. LG.Day(guild.first, "short")) or ""
    P7.kicker:Set("As it reached " .. ctx.who .. since, CX, g.kicker, 28)
    -- the heads are laid out at each draw, with the faces as they measure now
    LG.HeadPair(P7.heads[1], "SLAIN", g.slain, P7.heads[2], "FALLEN", g.fallen, g.head, P7.sheet.child, g.win[1], g.win[2])
    LG.HeadPair(P7.landHeads[1], "SLAIN", gl.slain, P7.landHeads[2], "FALLEN", gl.fallen, gl.head,
        P7.lands.child, gl.win[1], gl.win[2])
    LayMates(guild)
    LayGuildLands(guild)
    P7.strip:Set(guild.hours or {})
    P7.line:Set({ "Only what reached " .. ctx.who .. " while in the field is written here." }, RCX, gl.line)
end

LG.spreads[7] = { Build = Build7, Render = Render7 }
