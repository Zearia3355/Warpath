-- Warpath: the Ledger's second spread (3.8.5): The Hours | The Calendar
-- docs/design/chronicle-ledger.md, "2. The Hours | The Calendar" (F2).
local ADDON, ns = ...
local Book, LG, Chron = ns.Book, ns.ChronLedger, ns.Chron
local Put, Set, Str, Wpx = Book.Put, Book.Set, Book.Str, Book.Wpx
local INK, FADED, RUBRIC = Book.INK, Book.FADED, Book.RUBRIC
local L0, LR, CX, R0, RR, RCX = LG.G.L0, LG.G.LR, LG.G.CX, LG.G.R0, LG.G.RR, LG.G.RCX
local DEEP = LG.DEEP

local myFull
ns.OnBind(function() myFull = ns.myFull end)

local G = {
    wheel = { cx = 296, cy = 296, r = 108, inner = 0.42, slice = 4,
              fill = { 140, 40, 20 }, edge = { 90, 20, 10 }, rings = { 0.55, 0.25, 0.45 } },
    week = { head = 478, names = 508, figs = 532, px = 19, inset = 40, under = 5 },
    line = { 590, 612, px = 17 },
    cal = { title = 162, titlePx = 19, arrowY = 143, left = 44, right = 17, names = 194,
            top = 202, ch = 62, kpx = 21, dpx = 19, fig = 44, under = 50, dash = 38 },
}
LG.HOURS = G

local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
local state = LG.state
local P

---------------------------------------------------------------------------
-- The wheel
---------------------------------------------------------------------------

local function Pt(r, t) return G.wheel.cx + r * math.sin(t), G.wheel.cy - r * math.cos(t) end

local function BuildWheel(L)
    local w = G.wheel
    P.rings = {}
    for i, a in ipairs(w.rings) do
        local ring = LG.Ring(L, 96)
        local rad = i == 1 and w.r or i == 2 and w.r - 3 or w.r * w.inner
        ring:Set(w.cx, w.cy, rad, INK, a, 1)
        P.rings[i] = ring
    end
    for h = 0, 23 do
        local t = 2 * math.pi * h / 24
        local tick = h % 6 == 0 and 7 or 3
        local tex = Book.Solid(L, "ARTWORK", FADED, 1)
        local ax, ay = Pt(w.r + 1, t)
        local bx, by = Pt(w.r + 1 + tick, t)
        LG.Line(tex, ax, ay, bx, by, 1)
    end
    for h, s in pairs({ [0] = "midnight", [6] = "dawn", [12] = "noon", [18] = "dusk" }) do
        local fs = Str(L, "gari", 15, FADED)
        Set(fs, s)
        local x, y = Pt(w.r + 20, 2 * math.pi * h / 24)
        Put(fs, x, y + 5, "m")
    end
    for h = 3, 21, 6 do
        local fs = Str(L, "narrow", 14, FADED)
        Set(fs, tostring(h))
        local x, y = Pt(w.r + 16, 2 * math.pi * h / 24)
        Put(fs, x, y + 5, "m")
    end
    P.wedges = {}
    for h = 0, 23 do
        P.wedges[h] = { tex = {}, hot = LG.Hot(L, function(self) LG.HourTip(self.h, self.n) end) }
        P.wedges[h].hot.h = h
    end
    Book.Diamond(L, w.cx, w.cy, 4, RUBRIC, { 60, 10, 4 }, "OVERLAY")
end

-- A wedge from the inner ring outward: inner corners at +-0.6w, outer at
-- +-w (w = 0.38 of an hour), drawn as turned slices, the edge first.
local function LayWedge(wd, h, v, top, busiest)
    local w = G.wheel
    local t = 2 * math.pi * h / 24
    local half = 2 * math.pi / 24 * 0.38
    local r0 = w.r * w.inner + 2
    local r1 = r0 + (w.r * (1 - w.inner) - 6) * v / top
    local hw0, hw1 = r0 * math.sin(half * 0.6), r1 * math.sin(half)
    local fill, edge = busiest and DEEP or w.fill, busiest and LG.DEEP_EDGE or w.edge
    local n = math.max(1, math.ceil((r1 - r0) / w.slice))
    local k = 0
    local function Slice(a, b, wid, col)
        k = k + 1
        local tex = wd.tex[k]
        if not tex then tex = P.wheelFrame:CreateTexture(nil, "ARTWORK") wd.tex[k] = tex end
        tex:SetColorTexture(Book.RGB(col))
        tex:SetDrawLayer("ARTWORK", col == edge and 1 or 2)
        local ax, ay = Pt(a, t)
        local bx, by = Pt(b, t)
        LG.Line(tex, ax, ay, bx, by, wid)
    end
    for pass = 1, 2 do
        for j = 1, n do
            local a, b = r0 + (r1 - r0) * (j - 1) / n, r0 + (r1 - r0) * j / n
            local hw = hw0 + (hw1 - hw0) * ((j - 0.5) / n)
            if pass == 1 then
                Slice(j == 1 and a - 1 or a, j == n and b + 1 or b, 2 * hw + 2, edge)
            else
                Slice(a, b, 2 * hw, fill)
            end
        end
    end
    for i = k + 1, #wd.tex do wd.tex[i]:Hide() end
    local mx, my = Pt((r0 + w.r) / 2, t)
    Book.Box(wd.hot, mx - 9, my - 9, mx + 9, my + 9)
end

local function BuildLeft(L)
    LG.Heading(L, "The Hours", CX, LG.G.head.y)
    P.wheelFrame = L
    BuildWheel(L)
    local wk = G.week
    local head = LG.Head(L, 11, FADED)
    head:Set("BY DAY OF THE WEEK", CX, wk.head, "m")
    P.days, P.dayFigs = {}, {}
    local step = (LR - L0 - 2 * wk.inset) / 6
    for i, d in ipairs(DAYS) do
        local x = L0 + wk.inset + (i - 1) * step
        local fs = Str(L, "gari", 16, FADED)
        Set(fs, d)
        Put(fs, x, wk.names, "m")
        P.dayFigs[i] = LG.Num(L, wk.px, RUBRIC)
    end
    P.dayRule = Book.Solid(L, "ARTWORK", DEEP, 0.9)
    P.line = LG.Lines(L, G.line.px, FADED)
end

local function LayLeft(ctx)
    local s = ctx.s
    local hours, top, busiest = s.hours or {}, 0, nil
    for h = 0, 23 do
        local v = hours[h] or 0
        if v > top then top, busiest = v, h end
    end
    for h = 0, 23 do
        local wd, v = P.wedges[h], hours[h] or 0
        wd.hot.n = v
        if v > 0 then
            LayWedge(wd, h, v, top, h == busiest)
        else
            for _, t in ipairs(wd.tex) do t:Hide() end
            local mx, my = Pt((G.wheel.r * G.wheel.inner + 2 + G.wheel.r) / 2, 2 * math.pi * h / 24)
            Book.Box(wd.hot, mx - 9, my - 9, mx + 9, my + 9)
        end
    end
    local wk = G.week
    local days, dtop, dbest = s.weekdays or {}, 0, nil
    for i = 1, 7 do if (days[i] or 0) > dtop then dtop, dbest = days[i], i end end
    local step = (LR - L0 - 2 * wk.inset) / 6
    for i = 1, 7 do
        local x = L0 + wk.inset + (i - 1) * step
        P.dayFigs[i]:Set(days[i] or 0, x, wk.figs, "m", i == dbest and DEEP or RUBRIC)
    end
    P.dayRule:SetShown(dbest ~= nil)
    if dbest then
        local x = L0 + wk.inset + (dbest - 1) * step
        Book.Box(P.dayRule, math.floor(x - 10), wk.figs + wk.under, math.floor(x + 10), wk.figs + wk.under + 1)
    end
    if busiest then
        local blade = ctx.plural and (ctx.poss .. " blades are") or (ctx.poss .. " blade is")
        P.line:Set({ LG.Cap(blade) .. " busiest at " .. LG.HourWords(busiest) .. ",",
            "with " .. ns.NumberWord(top) .. " slain in that hour, and on " .. ns.DayName(dbest % 7 + 1) .. "s." },
            CX, G.line[1], nil, G.line[2] - G.line[1])
    else
        P.line:Set({ LG.Cap(ctx.who) .. (ctx.plural and " have" or " has") .. " drawn no blood yet." }, CX, G.line[1])
    end
end

---------------------------------------------------------------------------
-- The calendar
---------------------------------------------------------------------------

local function MonthOf(t)
    local d = date("*t", t)
    return d.year, d.month
end

local function Shift(y, m, by)
    m = m + by
    while m < 1 do m, y = m + 12, y - 1 end
    while m > 12 do m, y = m - 12, y + 1 end
    return y, m
end

local function Bounds(s)
    local ny, nm = MonthOf(time())
    local fy, fm = ny, nm
    if s.first then fy, fm = MonthOf(s.first) end
    return fy * 12 + fm, ny * 12 + nm
end

local function TurnMonth(by)
    local s = P.s
    if not s then return end
    local lo, hi = Bounds(s)
    local y, m = Shift(state.month[1], state.month[2], by)
    if y * 12 + m < lo or y * 12 + m > hi then return end
    state.month = { y, m }
    ns.UISound("IG_ABILITY_PAGE_TURN", 836)
    Chron.Render()
end

local function CellTip(self)
    local c = self.cell
    LG.Tip(LG.Day(self.t))
    if not c or (c.k == 0 and c.d == 0) then
        LG.Tip(c and c.field and "In the field, no blood." or "Not in the field.", 0.8, 0.8, 0.8)
        return
    end
    LG.Tip(c.k .. " slain, " .. c.d .. " fallen", 1, 0.82, 0)
    local zones = {}
    for z in pairs(c.zones or {}) do zones[#zones + 1] = ns.MapName(z) or "?" end
    table.sort(zones)
    if #zones > 0 then LG.Tip(table.concat(zones, ", "), 0.8, 0.8, 0.8, true) end
end

local function BuildRight(R)
    local c = G.cal
    LG.Heading(R, "The Calendar", RCX, LG.G.head.y)
    P.title = Book.Caps(R, "morph", c.titlePx, INK, { ratio = 0.78, track = 0.6 })
    P.prevM = LG.Arrow(R, true, function() TurnMonth(-1) end)
    P.nextM = LG.Arrow(R, false, function() TurnMonth(1) end)
    P.prevName, P.nextName = Str(R, "gari", 15, FADED), Str(R, "gari", 15, FADED)
    local cw = (RR - R0) / 7
    for i, d in ipairs(DAYS) do
        local fs = Str(R, "gari", 15, FADED)
        Set(fs, d)
        Put(fs, R0 + cw * (i - 1) + cw / 2, c.names, "m")
    end
    P.weekRules = {}
    for i = 1, 7 do P.weekRules[i] = Book.Solid(R, "ARTWORK", FADED, 0.22) end
    P.cells = {}
    for i = 1, 31 do
        local cell = {
            day = Str(R, "narrow", 13, FADED),
            k = Book.Bold(Str(R, "garb", c.kpx, RUBRIC)),
            colon = Str(R, "garb", c.kpx, FADED),
            d = Book.Bold(Str(R, "garb", c.dpx, INK)),
            under = Book.Solid(R, "ARTWORK", DEEP, 0.9),
            dash = Book.Solid(R, "ARTWORK", FADED, 0.5),
            hot = LG.Hot(R, CellTip),
        }
        Set(cell.colon, ":")
        P.cells[i] = cell
    end
    P.today = LG.Ring(R, 24)
    P.key = Str(R, "gari", 15, FADED)
    Set(P.key, "kills : deaths.  A dash: in the field, no blood.")
    P.sum = Str(R, "gari", 16, FADED)
    P.night = Str(R, "gari", 16, FADED)
    P.nightArrow = Book.Chevron(R)
    P.nightHot = LG.Hot(R, function(self)
        if not self.start then return false end
        LG.Tip("Open that campaign")
    end, function(self) LG.OpenCampaign(self.start) end)
end

local function LayCell(cell, x0, y0, cw, day, info, best, field, isToday)
    local c = G.cal
    Set(cell.day, tostring(day))
    Book.Color(cell.day, field and INK or FADED)
    Put(cell.day, x0 + 5, y0 + 15, "l")
    cell.day:Show()
    local k, d = info and info.k or 0, info and info.d or 0
    local fought = k + d > 0
    LG.Show(cell.k, fought)
    cell.colon:SetShown(fought)
    LG.Show(cell.d, fought)
    cell.under:SetShown(fought and k == best and best > 0)
    cell.dash:SetShown(not fought and field)
    if fought then
        local ks, ds = tostring(k), tostring(d)
        Set(cell.k, ks)
        Set(cell.d, ds)
        local wk = Book.Measure("garb", c.kpx, ks)
        local wc = Book.Measure("garb", c.kpx, ":")
        local w = wk + wc + Book.Measure("garb", c.dpx, ds) + 4
        local x = x0 + cw / 2 - w / 2
        Book.Color(cell.k, k == best and best > 0 and DEEP or RUBRIC)
        Put(cell.k, x, y0 + c.fig, "l")
        Put(cell.colon, x + wk + 2, y0 + c.fig, "l")
        Put(cell.d, x + wk + 2 + wc + 2, y0 + c.fig, "l")
        if k == best and best > 0 then
            Book.Box(cell.under, math.floor(x0 + cw / 2 - 14), y0 + c.under, math.floor(x0 + cw / 2 + 14), y0 + c.under + 1)
        end
    elseif field then
        Book.Box(cell.dash, math.floor(x0 + cw / 2 - 6), y0 + c.dash, math.floor(x0 + cw / 2 + 6), y0 + c.dash + 1)
    end
    if isToday then P.today:Set(x0 + 12, y0 + 11, 11, RUBRIC, 1, 1) end
    cell.hot.cell = info
    Book.Box(cell.hot, x0, y0, x0 + cw, y0 + c.ch)
    cell.hot:Show()
end

local function LayRight(ctx)
    local s, c = ctx.s, G.cal
    P.s = s
    local lo, hi = Bounds(s)
    if not state.month then state.month = { MonthOf(time()) } end
    local cur = state.month[1] * 12 + state.month[2]
    if cur < lo or cur > hi then state.month = { MonthOf(time()) } end
    local year, month = state.month[1], state.month[2]
    local mname = ns.MonthName(month)
    local tw = P.title:Set(mname .. " " .. year, RCX, c.title, "m")
    local lx, rx = math.floor(RCX - tw / 2 - c.left), math.floor(RCX + tw / 2 + c.right)
    local key = year * 12 + month
    P.prevM:SetShown(key > lo)
    P.prevName:SetShown(key > lo)
    P.nextM:SetShown(key < hi)
    P.nextName:SetShown(key < hi)
    LG.PlaceArrow(P.prevM, true, lx, c.arrowY)
    LG.PlaceArrow(P.nextM, false, rx, c.arrowY)
    local py, pm = Shift(year, month, -1)
    local ny, nm = Shift(year, month, 1)
    Set(P.prevName, ns.MonthName(pm))
    Put(P.prevName, lx - 6, c.title, "r")
    Set(P.nextName, ns.MonthName(nm))
    Put(P.nextName, rx + 33, c.title, "l")

    local first = time({ year = year, month = month, day = 1, hour = 12 })
    local col0 = (date("*t", first).wday + 5) % 7
    local ndays = date("*t", time({ year = ny, month = nm, day = 1, hour = 12 }) - 86400).day
    local rows = math.floor((col0 + ndays + 6) / 7)
    local cw = (RR - R0) / 7
    for r = 1, #P.weekRules do
        local rule = P.weekRules[r]
        rule:SetShown(r <= rows + 1)
        Book.Box(rule, R0 + 2, c.top + (r - 1) * c.ch, RR - 2, c.top + (r - 1) * c.ch + 1)
    end
    local cal = s.calendar or {}
    local best, days, kills, deaths = 0, 0, 0, 0
    for d = 1, ndays do
        local info = cal[("%04d-%02d-%02d"):format(year, month, d)]
        if info then
            best = math.max(best, info.k)
            if info.k + info.d > 0 then days, kills, deaths = days + 1, kills + info.k, deaths + info.d end
        end
    end
    local now = date("*t")
    P.today:SetShown(false)
    for d = 1, 31 do
        local cell = P.cells[d]
        if d <= ndays then
            local i = col0 + d - 1
            local x0, y0 = R0 + (i % 7) * cw, c.top + math.floor(i / 7) * c.ch
            local info = cal[("%04d-%02d-%02d"):format(year, month, d)]
            local isToday = now.year == year and now.month == month and now.day == d
            if isToday then P.today:SetShown(true) end
            cell.hot.t = time({ year = year, month = month, day = d, hour = 12 })
            LayCell(cell, x0, y0, cw, d, info, best, info and info.field, isToday)
        else
            cell.day:Hide() LG.Show(cell.k, false) cell.colon:Hide() LG.Show(cell.d, false)
            cell.under:Hide() cell.dash:Hide() cell.hot:Hide()
        end
    end
    local y = c.top + rows * c.ch + 24
    Put(P.key, RCX, y, "m")
    if days > 0 then
        Set(P.sum, LG.Cap(ns.NumberWord(days)) .. (days == 1 and " day" or " days") .. " of war in " .. mname .. ": "
            .. kills .. " slain, " .. deaths .. " fallen.")
    else
        Set(P.sum, "No fights in " .. mname .. ".")
    end
    Put(P.sum, RCX, y + 24, "m")
    -- the bloodiest night, when it began this month
    local b = s.records and s.records.bloodiest
    local show = b and b.start and select(2, MonthOf(b.start)) == month and MonthOf(b.start) == year
    P.night:SetShown(show and true or false)
    P.nightArrow:SetShown(show and true or false)
    P.nightHot:SetShown(show and true or false)
    if show then
        Set(P.night, "The bloodiest night: " .. LG.Day(b.start) .. ", " .. ns.NumberWord(b.kills) .. " slain")
        local w = Wpx(P.night)
        Put(P.night, RCX - 10, y + 48, "m")
        local xx = RCX - 10 + w / 2 + 8
        P.nightArrow:Set(false, xx - 2, y + 48)
        P.nightHot.start = (not ctx.account or b.char == myFull) and b.start or nil
        Book.Box(P.nightHot, RCX - 10 - w / 2, y + 48 - 14, xx + 8, y + 48 + 4)
    end
end

local function Build(F)
    P = {}
    LG.HOURS.P = P
    BuildLeft(F.L)
    BuildRight(F.R)
end

local function Render(F, ctx)
    LayLeft(ctx)
    LayRight(ctx)
end

LG.spreads[2] = { Build = Build, Render = Render }
