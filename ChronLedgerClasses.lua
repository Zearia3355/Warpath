-- Warpath: the Ledger's third and fifth spreads (3.8.5):
-- Classes Slain | Classes That Slew (F3), Foes of Note | Who They Were (F5).
-- docs/design/chronicle-ledger.md, spreads 3 and 5.
local ADDON, ns = ...
local Book, LG, Chron = ns.Book, ns.ChronLedger, ns.Chron
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC = Book.INK, Book.FADED, Book.RUBRIC
local L0, LR, CX, R0, RR, RCX = LG.G.L0, LG.G.LR, LG.G.CX, LG.G.R0, LG.G.RR, LG.G.RCX

local G = {
    classes = { y = 170, step = 42, tile = 30, name = 42, namePx = 18, bar = 190, room = 40, after = 28,
                zero = 10, px = 20, foot = 12, footPx = 17, footLh = 21 },
    foes = { y = 162, heads = 24, rows = 24, step = 26, gap = 22, name = 114, guild = 290, last = 466, count = 510,
             guildRoom = 96, namePx = 17, px = 19, max = 6 },
    who = { sheet = { 576, 146, 1025, 668 }, win = { 578, 150, 1023, 664 }, cord = { 1016, 156, 658 },
            first = 164, x0 = 584, x1 = 999, inset = 14, section = 26, lh = 24, after = 8,
            labw = { 90, 180, 180 }, guildless = 190 },
}
LG.CLASSES = G

local CLASSES = ns.Ledger.CLASSES
local state = LG.state

-- "Paladins"; a client without localised names gives the token: title-case it.
local function Plural(c)
    if c == "unknown" then return "Unknown" end
    local n = ns.ClassName(c) or c
    if n == n:upper() then n = n:sub(1, 1) .. n:sub(2):lower() end
    return n .. "s"
end

local function List(words)
    if #words == 1 then return words[1] end
    return table.concat(words, ", ", 1, #words - 1) .. " and " .. words[#words]
end

---------------------------------------------------------------------------
-- Spread 3: the classes
---------------------------------------------------------------------------

local P3

local function ClassTable(F, side)
    local x0 = side == "L" and L0 or R0
    local parent = F[side]
    local t = { rows = {}, x0 = x0, x1 = side == "L" and LR or RR, cx = side == "L" and CX or RCX }
    t.head = LG.Heading(parent, side == "L" and "Classes Slain" or "Classes That Slew", t.cx, LG.G.head.y)
    local col = side == "L" and RUBRIC or LG.DEATH
    for i = 1, 10 do
        t.rows[i] = { tile = LG.Tile(parent), name = Str(parent, "friz", G.classes.namePx, INK),
            bar = LG.Bar(parent, col, side == "L" and 0.78 or 0.55), num = LG.Num(parent, G.classes.px, col) }
    end
    t.foot = LG.Lines(parent, G.classes.footPx, FADED)
    return t
end

local function Sorted(counts)
    local rows = {}
    for _, c in ipairs(CLASSES) do rows[#rows + 1] = { c, counts[c] or 0 } end
    rows[#rows + 1] = { "unknown", counts.unknown or 0 }
    table.sort(rows, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        if (a[1] == "unknown") ~= (b[1] == "unknown") then return b[1] == "unknown" end
        return Plural(a[1]) < Plural(b[1])
    end)
    return rows
end

local function LayTable(t, counts)
    local g = G.classes
    local rows = Sorted(counts)
    local top = 1
    for _, r in ipairs(rows) do top = math.max(top, r[2]) end
    local y = g.y
    for i, r in ipairs(rows) do
        local row, c, n = t.rows[i], r[1], r[2]
        LG.SetTile(row.tile, c, t.x0 + 2, y - 23, g.tile)
        Set(row.name, Plural(c))
        if n > 0 and c ~= "unknown" then
            Book.NameColor(row.name, c)
        else
            Book.Color(row.name, FADED)
            row.name:SetShadowOffset(0, 0)
        end
        Put(row.name, t.x0 + g.name, y - 2, "l")
        local bx = t.x0 + g.bar
        local span = t.x1 - bx - g.room
        local ex = bx + math.floor(span * n / top)
        row.bar:Set(bx, n > 0 and ex or bx, y - 5)
        row.num:Set(n, n > 0 and ex + g.after or bx + g.zero, y - 2, "r")
        y = y + g.step
    end
    return rows, y
end

-- The top known classes and their count.
local function Leaders(rows)
    local best, names = 0, {}
    for _, r in ipairs(rows) do
        if r[1] ~= "unknown" and r[2] > 0 then
            if r[2] > best then best, names = r[2], { Plural(r[1]):lower() }
            elseif r[2] == best then names[#names + 1] = Plural(r[1]):lower() end
        end
    end
    return names, best
end

local function SlainLine(ctx, rows)
    local names, n = Leaders(rows)
    local blade = ctx.poss .. (ctx.plural and " blades" or " blade")
    if n == 0 then
        local unknown = rows[#rows][1] == "unknown" and 0 or nil
        for _, r in ipairs(rows) do if r[1] == "unknown" then unknown = r[2] end end
        if (unknown or 0) > 0 then return "The game hid the class of every foe to fall to " .. blade .. "." end
        return "None has fallen to " .. blade .. " yet."
    end
    local tail = #names > 1 and (ns.NumberWord(n) .. " of each") or (ns.NumberWord(n) .. " in all")
    return LG.Cap(List(names)) .. " have fallen most often to " .. blade .. ", " .. tail .. "."
end

local function SlewLine(ctx, rows, unknown)
    local names, n = Leaders(rows)
    if n == 0 then
        if unknown > 0 then return "Every hand that struck " .. ctx.who .. " down went unseen." end
        return "No one has struck " .. ctx.who .. " down yet."
    end
    local times = LG.Times(n) .. (#names > 1 and " each" or "")
    if unknown > n then
        return "Most who struck " .. ctx.who .. " down went unseen; of those seen, " .. List(names) .. " struck " .. times .. "."
    end
    return "Of those who struck " .. ctx.who .. " down, " .. List(names) .. " struck most often, " .. times .. "."
end

local function Build3(F)
    P3 = { L = ClassTable(F, "L"), R = ClassTable(F, "R") }
    LG.CLASSES.P3 = P3
end

local function Render3(F, ctx)
    local s = ctx.s
    local g = G.classes
    local rows, y = LayTable(P3.L, s.slain or {})
    P3.L.foot:Set(SlainLine(ctx, rows), CX, y + g.foot, LR - L0 - 30, g.footLh)
    rows, y = LayTable(P3.R, s.slew or {})
    P3.R.foot:Set(SlewLine(ctx, rows, (s.slew or {}).unknown or 0), RCX, y + g.foot, RR - R0 - 30, g.footLh)
end

LG.spreads[3] = { Build = Build3, Render = Render3 }

---------------------------------------------------------------------------
-- Spread 5, left: Foes of Note
---------------------------------------------------------------------------

local P5

local function Block(L)
    local b = { sub = LG.Sub(L), heads = {}, rows = {}, none = Str(L, "gari", 16, FADED) }
    Set(b.none, "None yet.")
    for i = 1, 4 do b.heads[i] = LG.Head(L, 10, FADED) end
    for i = 1, G.foes.max do
        local hot = LG.Hot(L, function(self) LG.FoeTip(self.f, self.e) end,
            function(self) if self.f and ns.Grudge.Get(self.f) then LG.OpenGrudge(self.f) end end)
        b.rows[i] = { tile = LG.Tile(L), name = LG.NameStr(L, G.foes.namePx), guild = Str(L, "gari", 15, FADED),
            last = Str(L, "narrow", 14, FADED), count = LG.Num(L, G.foes.px, RUBRIC), hot = hot }
    end
    return b
end

-- Shorten with "…" to fit a width.
local function Fit(fs, text, face, px, width)
    local s = text
    while Book.Measure(face, px, s) > width and #s > 3 do
        s = s:gsub("\226\128\166$", ""):gsub("[%z\1-\127\194-\244][\128-\191]*$", "") .. "\226\128\166"
    end
    Set(fs, s)
end

local function LayBlock(b, y, title, list, col, head)
    local g = G.foes
    b.sub:Set(title, L0, y, LR)
    y = y + g.heads
    local heads = { { "FOE", g.name, "l" }, { "GUILD", g.guild, "l" }, { "LAST", g.last, "r" }, { head, g.count, "r" } }
    for i, h in ipairs(heads) do b.heads[i]:Set(h[1], h[2], y, h[3]) end
    y = y + g.rows
    b.none:SetShown(#list == 0)
    if #list == 0 then Put(b.none, g.name, y, "l") end
    for i = 1, g.max do
        local r, e = b.rows[i], list[i]
        if e then
            LG.SetTile(r.tile, e.c, L0 + 2, y - 17, 22)
            r.name:Set(LG.Name(e.f) or e.n or "Unknown", e.c ~= "unknown" and e.c or nil, e.lv, g.name, y)
            r.guild:SetShown(e.gu ~= nil)
            if e.gu then
                Fit(r.guild, e.gu, "gari", 15, LR - g.guildRoom - g.guild)
                Put(r.guild, g.guild, y, "l")
            end
            r.last:SetShown(e.last ~= nil)
            if e.last then
                Set(r.last, LG.Day(e.last, "abbr"))
                Put(r.last, g.last, y, "r")
            end
            r.count:Set(e.count, g.count, y, "r", col)
            r.hot.f, r.hot.e = e.f, e
            Book.Box(r.hot, L0, y - 19, LR, y + 6)
            r.hot:Show()
            y = y + g.step
        else
            r.tile:Hide() r.name:Hide() r.guild:Hide() r.last:Hide() r.count:Hide() r.hot:Hide()
        end
    end
    if #list == 0 then y = y + g.step end
    return y
end

---------------------------------------------------------------------------
-- Spread 5, right: Who They Were, on a sheet with folding sections
---------------------------------------------------------------------------

local SECTIONS = { "Their levels", "Their races", "Guilds humbled" }

local function Pool(list, i, make)
    if not list[i] then list[i] = make() end
    return list[i]
end

local function BuildWho(R)
    local w = G.who
    LG.Heading(R, "Who They Were", RCX, LG.G.head.y)
    P5.sheet = Book.Sheet(R, w.sheet, w.win, w.cord)
    P5.secs, P5.bars = {}, {}
    local ch = P5.sheet.child
    for i, title in ipairs(SECTIONS) do
        local f = CreateFrame("Button", nil, ch)
        f.chev = Book.Chevron(f, ch, w.win[1], w.win[2])
        f.caps = Book.Caps(f, "morph", 16, RUBRIC, { ratio = 0.76, track = 0.6, shadow = Book.SHADOW })
        f.rule = Book.Solid(f, "ARTWORK", FADED, 0.3)
        f.title, f.index = title, i
        f:SetScript("OnClick", function(self)
            state.whoFolded = state.whoFolded or {}
            state.whoFolded[self.index] = not state.whoFolded[self.index] or nil
            ns.UISound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
            Chron.Render()
        end)
        P5.secs[i] = f
    end
end

local function BarRow(i)
    return Pool(P5.bars, i, function()
        local ch, w = P5.sheet.child, G.who
        local f = CreateFrame("Frame", nil, ch)
        local o = { ch, w.win[1], w.win[2] }
        return { frame = f, label = Str(f, "friz", 16, INK), italic = Str(f, "gari", 16, FADED),
            bar = LG.Bar(f, RUBRIC, 0.78, o[1], o[2], o[3]), num = LG.Num(f, 18, RUBRIC, o[1], o[2], o[3]),
            faded = LG.Num(f, 17, FADED, o[1], o[2], o[3]) }
    end)
end

-- rows: { label, n }; extra: { label, n } as a faded figure-only row.
local function LayBars(k, y, rows, extra, labw, nonePlain)
    local w = G.who
    local ch, ox, oy = P5.sheet.child, w.win[1], w.win[2]
    local x0 = w.x0 + w.inset
    local maxn = 1
    for _, r in ipairs(rows) do maxn = math.max(maxn, r[2]) end
    local span = w.x1 - x0 - labw - 34
    local function Place(r, f) Book.Box(f, w.x0, y - 18, w.x1, y + 6, ch, ox, oy) P5.sheet:Add(f, y - 18 - oy, y + 6 - oy) end
    if #rows == 0 and not extra then
        k = k + 1
        local r = BarRow(k)
        r.label:Hide() r.bar:Hide() r.num:Hide() r.faded:Hide()
        Set(r.italic, "None yet.")
        Put(r.italic, x0, y, "l", ch, ox, oy)
        r.italic:Show()
        Place(r, r.frame)
        r.frame:Show()
        return k, y + w.lh
    end
    for _, row in ipairs(rows) do
        k = k + 1
        local r = BarRow(k)
        Set(r.label, row[1])
        Put(r.label, x0, y, "l", ch, ox, oy)
        r.label:Show()
        r.italic:Hide()
        r.faded:Hide()
        local ex = x0 + labw + math.floor(span * row[2] / maxn)
        r.bar:Set(x0 + labw, row[2] > 0 and ex or x0 + labw, y - 3)
        r.num:Set(row[2], row[2] > 0 and ex + 26 or x0 + labw + 10, y, "r")
        Place(r, r.frame)
        r.frame:Show()
        y = y + w.lh
    end
    if extra and extra[2] > 0 then
        k = k + 1
        local r = BarRow(k)
        r.label:Hide() r.bar:Hide() r.num:Hide()
        Set(r.italic, extra[1])
        Put(r.italic, x0, y, "l", ch, ox, oy)
        r.italic:Show()
        r.faded:Set(extra[2], x0 + (nonePlain or (labw + 10)), y, "l")
        Place(r, r.frame)
        r.frame:Show()
        y = y + w.lh
    end
    return k, y
end

local function Ranked(counts, skip)
    local rows = {}
    for k, n in pairs(counts or {}) do if k ~= skip and n > 0 then rows[#rows + 1] = { k, n } end end
    table.sort(rows, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    return rows
end

local function LayWho(ctx)
    local w, who = G.who, ctx.s.who or {}
    local sheet = P5.sheet
    local ch, ox, oy = sheet.child, w.win[1], w.win[2]
    sheet:Clear()
    local folded = state.whoFolded or {}
    local levels = {}
    for _, b in ipairs(ns.Ledger.BANDS) do
        if b ~= "unknown" then levels[#levels + 1] = { (b:gsub("%-", "\226\128\147")), (who.levels or {})[b] or 0 } end
    end
    local anyLevel = false
    for _, r in ipairs(levels) do if r[2] > 0 then anyLevel = true end end
    if not anyLevel and ((who.levels or {}).unknown or 0) == 0 then levels = {} end
    local data = {
        { levels, { "unknown", (who.levels or {}).unknown or 0 } },
        { Ranked(who.races, "unknown"), { "unknown", (who.races or {}).unknown or 0 } },
        { Ranked(who.guilds, "none"), { "No guild", (who.guilds or {}).none or 0 } },
    }
    local y, k = w.first, 0
    for i, f in ipairs(P5.secs) do
        local open = not folded[i]
        Book.Box(f, w.win[1], y - 16, w.win[3], y + 6, ch, ox, oy)
        f.chev:Set(open, w.x0, y)
        local tw = f.caps:Set(f.title, w.x0 + 14, y, "l", ch, ox, oy)
        local a = math.floor(w.x0 + 22 + tw)
        Book.Box(f.rule, a, y - 4, math.max(a + 0.01, w.x1 - 10), y - 3, ch, ox, oy)
        sheet:Add(f, y - 16 - oy, y + 6 - oy)
        y = y + w.section
        if open then
            local d = data[i]
            k, y = LayBars(k, y, d[1], d[2], w.labw[i], i == 3 and w.guildless or nil)
            y = y + w.after
        end
    end
    for i = k + 1, #P5.bars do P5.bars[i].frame:Hide() end
    sheet:SetContent(y - w.first + 12)
end

local function Build5(F)
    P5 = { slain = Block(F.L), struck = Block(F.L) }
    LG.CLASSES.P5 = P5
    LG.Heading(F.L, "Foes of Note", CX, LG.G.head.y)
    BuildWho(F.R)
end

local function Render5(F, ctx)
    local foes = ctx.s.foes or {}
    local y = LayBlock(P5.slain, G.foes.y, "Slain most", foes.slain or {}, RUBRIC, "SLAIN")
    LayBlock(P5.struck, y + G.foes.gap, "Struck " .. ctx.who .. " down", foes.struck or {}, INK, "TIMES")
    LayWho(ctx)
end

LG.spreads[5] = { Build = Build5, Render = Render5 }
