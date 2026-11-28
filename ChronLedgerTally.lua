-- Warpath: the Ledger's first spread (3.8.5): The Tally | Records
-- docs/design/chronicle-ledger.md, "1. The Tally | Records" (F1).
local ADDON, ns = ...
local Book, LG = ns.Book, ns.ChronLedger
local Put, Set, Str = Book.Put, Book.Set, Book.Str
local INK, FADED, RUBRIC, SHADOW = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW
local L0, LR, CX, R0, RR, RCX = LG.G.L0, LG.G.LR, LG.G.CX, LG.G.R0, LG.G.RR, LG.G.RCX

local myFull
ns.OnBind(function() myFull = ns.myFull end)

-- The spec's numbers (render px; y are baselines).
local G = {
    kicker = { y = 104, px = 12, rules = 40 },
    head = 140,
    great = { y = 214, px = 46, cap = 234, capPx = 11, rule = { 182, 240 } },
    rows = { x0 = 106, x1 = 486, y = 266, step = 21, lpx = 16, vpx = 18 },
    tiers = { gap = 6, fig = 30, px = 20, name = 15, namePx = 13, lh = 12, howPx = 13, after = 58, streaks = -2 },
    rec = { head = 120, y = 162, x0 = 600, x1 = 1003, lpx = 17, vpx = 19, dx = 612, dy = 17, dpx = 14,
            step = 44, plain = 30, bottom = 660, empty = 180 },
}
LG.TALLY = G

local MULTI = { { "Double kill", 2, "2 kills" }, { "Triple kill", 3, "3 kills" }, { "Quad kill", 4, "4 kills" },
    { "Bloodbath", 5, "5 or more" } }
local STREAKS = { { "Bloodthirsty", 3 }, { "Rampage", 5 }, { "Warmonger", 10 }, { "Unstoppable", 15 },
    { "Legend of the Warpath", 20 } }
for _, t in ipairs(STREAKS) do t[1] = ns.Phrases.STREAKS[t[2]] or t[1] t[3] = t[2] .. " in a row" end

-- The Tally's rows: label, value, definition (the spec's table).
local function TallyRows(s)
    local t = s.tally
    local function N(v) return v > 0 and LG.Comma(v) or nil end
    local kd
    if t.deaths > 0 then kd = ("%.2f"):format(t.kills / t.deaths) elseif t.kills > 0 then kd = "\226\128\148" end
    return {
        { "Kill-death ratio", kd, "Kills for each PvP death." },
        { "Different foes slain", N(t.foes), "How many different enemies you've slain." },
        { "Kills avenged", N(t.avenged), "Kills that avenged your own fresh death." },
        { "Fell to the wilds", N(t.wilds), "Deaths not counted as PvP: to creatures, falls and the world." },
        { "Miles travelled", t.yards >= 1760 * 0.05 and LG.Comma(t.yards / 1760, 1) or nil, "Walked, ridden and flown." },
        { "Enemies sighted", N(t.sightings), "Enemy players seen." },
        { "Screenshots taken", N(t.shots), "Kill screenshots, on every character." },
        { "Flights taken", N(t.flights), "Flights started at a flight master.", true },
        { "Corpse runs", N(t.runs), "Walks back to your body.", true },
        { "Released at a spirit healer", N(t.spirit), "Resurrections taken at a spirit healer.", true },
        { "Miles walked as a ghost", t.ghostYards >= 1760 * 0.05 and LG.Comma(t.ghostYards / 1760, 1) or nil,
          "The length of your corpse runs.", true },
    }
end

local P

local function Tiers(F, list, n)
    local cols = {}
    for i = 1, n do
        cols[i] = { fig = LG.Num(F.L, G.tiers.px, RUBRIC), names = { Str(F.L, "narrow", G.tiers.namePx, INK),
            Str(F.L, "narrow", G.tiers.namePx, INK) }, how = Str(F.L, "gari", G.tiers.howPx, FADED),
            hot = LG.Hot(F.L, function(self)
                LG.Tip(self.title)
                LG.Tip(self.last and ("Last reached " .. LG.Day(self.last)) or "Not reached yet", 0.8, 0.8, 0.8)
            end) }
    end
    return cols
end

local function Build(F)
    P = {}
    LG.TALLY.P = P
    local L, R = F.L, F.R
    P.kicker = LG.Kicker(L, G.kicker.px)
    P.head = LG.Heading(L, "The Tally", CX, G.head)
    P.great, P.caps = {}, {}
    local third = (LR - L0) / 3
    for i = 1, 3 do
        local fs = Book.Bold(Str(L, "garb", G.great.px, RUBRIC))
        Book.Shadow(fs, SHADOW)
        P.great[i] = fs
        P.caps[i] = LG.Head(L, G.great.capPx, FADED)
        if i > 1 then
            local x = math.floor(L0 + third * (i - 1))
            Book.Rect(L, "ARTWORK", RUBRIC, 0.35, x, G.great.rule[1], x + 1, G.great.rule[2])
        end
    end
    P.rows, P.rowHot = {}, {}
    for i = 1, 11 do
        P.rows[i] = LG.Row(L, G.rows.lpx, G.rows.vpx)
        P.rowHot[i] = LG.Hot(L, function(self) LG.Tip(self.label) LG.Tip(self.def, 0.8, 0.8, 0.8, true) end)
    end
    P.multiSub, P.streakSub = LG.Sub(L), LG.Sub(L)
    P.multiHow, P.streakHow = Str(L, "gari", 15, FADED), Str(L, "gari", 15, FADED)
    P.multi, P.streaks = Tiers(F, MULTI, 4), Tiers(F, STREAKS, 5)

    LG.Heading(R, "Records", RCX, G.rec.head)
    P.recs, P.details, P.recHot = {}, {}, {}
    for i = 1, 13 do
        P.recs[i] = LG.Row(R, G.rec.lpx, G.rec.vpx)
        P.details[i] = Str(R, "gari", G.rec.dpx, FADED)
        P.recHot[i] = LG.Hot(R, function(self)
            LG.Tip(self.label)
            LG.Tip(self.def, 0.8, 0.8, 0.8, true)
            if self.shot then LG.Tip(("Screenshot #%d"):format(self.shot), 1, 1, 1) end
            if self.start then LG.Tip("Click to open that campaign", 0.1, 1, 0.1) end
        end, function(self) if self.start then LG.OpenCampaign(self.start) end end)
    end
    P.noRecords = Str(R, "gari", 17, FADED)
    Set(P.noRecords, "No records yet. The first blood will be written here.")
    Put(P.noRecords, RCX, G.rec.empty, "m")
end

local function LayTiers(cols, list, counts, last, y)
    local n = #list
    local step = (LR - L0) / n
    local t = G.tiers
    for i, tier in ipairs(list) do
        local c = cols[i]
        local cx = L0 + step * (i - 1) + step / 2
        local v = counts[tier[2]] or 0
        c.fig:Set(v, cx, y, "m")
        local lines = tier[1]:find("^Legend of") and { "Legend of", "the Warpath" } or { tier[1] }
        local yy = y + t.name
        for k = 1, 2 do
            local fs = c.names[k]
            fs:SetShown(lines[k] ~= nil)
            if lines[k] then
                Set(fs, lines[k])
                Book.Color(fs, v > 0 and INK or FADED)
                Put(fs, cx, yy, "m")
                yy = yy + t.lh
            end
        end
        Set(c.how, tier[3])
        Put(c.how, cx, yy + 1, "m")
        c.hot.title, c.hot.last = tier[1], last[tier[2]]
        Book.Box(c.hot, cx - step / 2 + 2, y - 20, cx + step / 2 - 2, yy + 4)
    end
end

local function Faction(ctx)
    if not ctx.account then
        local foe = ns.faction and ns.faction.foe
        return (foe == "Alliance" or foe == "Horde") and foe or "Foes"
    end
    local gdb, one = ns.gdb, nil
    for _, key in ipairs(ctx.s.chars or {}) do
        local f = gdb.chars[key] and gdb.chars[key].faction
        if one and f ~= one then return "Foes" end
        one = f
    end
    return one == "Horde" and "Alliance" or one == "Alliance" and "Horde" or "Foes"
end

local function LayTally(ctx)
    local s = ctx.s
    local t = s.tally
    local since = s.first and ("  \194\183  since " .. LG.Day(s.first, "short")) or ""
    P.kicker:Set("The war of " .. ctx.who .. since, CX, G.kicker.y, G.kicker.rules)
    local third = (LR - L0) / 3
    local figs = { { t.kills, Faction(ctx) .. " slain" }, { t.deaths, "times fallen" }, { t.best, "best streak" } }
    for i, f in ipairs(figs) do
        local cx = L0 + third * (i - 1) + third / 2
        Set(P.great[i], tostring(f[1]))
        Put(P.great[i], cx, G.great.y, "m")
        P.caps[i]:Set(f[2]:upper(), cx, G.great.cap, "m")
    end
    local r = G.rows
    local y = r.y
    for i, row in ipairs(TallyRows(s)) do
        local value = row[2] or (row[4] and "none yet" or "none")
        P.rows[i]:Set(row[1], value, r.x0, r.x1, y, row[2] == nil)
        local hot = P.rowHot[i]
        hot.label, hot.def = row[1], row[3]
        Book.Box(hot, r.x0, y - 16, r.x1, y + 5)
        y = y + r.step
    end
    -- y is now where a twelfth row would sit
    local sy = y - r.step + r.step + G.tiers.gap
    local w = P.multiSub:Set("Multi-kills", L0, sy, nil)
    Set(P.multiHow, "each within two minutes of the last")
    Put(P.multiHow, L0 + w + 12, sy, "l")
    LayTiers(P.multi, MULTI, s.multi, s.multiLast or {}, sy + G.tiers.fig)
    sy = sy + G.tiers.fig + G.tiers.after + G.tiers.streaks
    w = P.streakSub:Set("Streaks", L0, sy, nil)
    Set(P.streakHow, "kills without dying")
    Put(P.streakHow, L0 + w + 12, sy, "l")
    LayTiers(P.streaks, STREAKS, s.streaks, s.streakLast or {}, sy + G.tiers.fig)
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local VANILLA = { Human = true, Dwarf = true, ["Night Elf"] = true, Gnome = true, Orc = true, Undead = true,
    Tauren = true, Troll = true }

local function Where(map) return map and ns.Chronicler.ZoneName(map) or "somewhere unknown" end
local function Short(key) return key and (LG.Name(key) or key) or nil end

-- "a mage of the High Order Skyborne"; "a dwarf mage" (Claude's call on the
-- wording: the game's races read before the class, others as a people).
local function Who(r)
    local class = r.c and r.c ~= "unknown" and ns.ClassName(r.c):lower() or nil
    if r.ra and VANILLA[r.ra] then
        local s = r.ra:lower() .. (class and (" " .. class) or "")
        return (s:find("^[aeiou]") and "an " or "a ") .. s
    end
    local s = class and ((class:find("^[aeiou]") and "an " or "a ") .. class) or "a foe"
    if r.ra then s = s .. " of the " .. r.ra end
    return s
end

-- Each record: label, value, detail, definition, campaign start, screenshot.
-- `always`: shown as "none yet" until set; the rest only once set.
local RECORDS = {
    { "firstBlood", "First blood", true, "The earliest kill.", function(r)
        return LG.Day(r.t, "short"), ns.MapName(r.map) .. ", " .. (Short(r.f or r.n) or "the foe unnamed") end },
    { "bloodiest", "Bloodiest night", true, "The campaign with the most kills.", function(r)
        return r.kills .. " slain", LG.Day(r.start), r.start end },
    { "hour", "Most in one hour", true, "The most kills in any sixty minutes, starting at a kill.", function(r)
        return tostring(r.n), LG.Day(r.t) .. ", from " .. date("%H:%M", r.t) end },
    { "longest", "Longest streak", true, "The best streak: where and when it peaked.", function(r)
        local d = r.t and (ns.MapName(r.map) .. ", " .. LG.Day(r.t, "short")) or nil
        if d and r.shot then d = d .. "  \194\183  screenshot #" .. r.shot end
        return tostring(r.n), d, nil, r.shot end },
    { "worst", "Worst night", true, "The campaign with the most PvP deaths (on a tie, the fewer kills).", function(r)
        return r.deaths .. " fallen", LG.Day(r.start), r.start end },
    { "smallest", "Smallest prey", true, "The lowest-level foe slain.", function(r)
        return "level " .. r.lv, (Short(r.f or r.n) or "a foe unnamed") .. ", " .. Who(r) .. ", in " .. Where(r.map) end },
    { "longNight", "Longest night", true, "The longest campaign.", function(r)
        local h, m = math.floor(r.played / 3600), math.floor(r.played % 3600 / 60)
        return h .. "h " .. m .. "m", LG.Day(r.start), r.start end },
    { "farthest", "Farthest ridden", true, "The most miles in one campaign.", function(r)
        return ("%.1f mi"):format(r.yards / 1760), LG.Day(r.start), r.start end },
    { "mostSeen", "Most enemies seen", true, "The most enemies sighted in one campaign.", function(r)
        return LG.Comma(r.n), "in one night, " .. LG.Day(r.start), r.start end },
    { "revenge", "Fastest revenge", true, "The quickest kill avenging your own death.", function(r)
        return r.av .. " s", (Short(r.f or r.n) or "a foe") .. ", in " .. Where(r.map) .. ", " .. LG.Day(r.t, "short") end },
    { "closest", "Closest call", false, "The kill made at your lowest health.", function(r)
        return r.hp .. "% health", (Short(r.f or r.n) or "a foe") .. ", in " .. Where(r.map) .. ", " .. LG.Day(r.t, "short") end },
    { "odds", "Worst odds won", false, "The kill with the most enemies to allies near (a count the game can only undercount).",
      function(r)
        return "at least " .. r.foes .. " against " .. r.friends,
            (Short(r.f or r.n) or "a foe") .. ", in " .. Where(r.map) .. ", " .. LG.Day(r.t, "short") end },
    { "gap", "Widest gap in levels", false, "The kill with the foe most levels above you.", function(r)
        return r.gap .. (r.gap == 1 and " level" or " levels"),
            (Short(r.f or r.n) or "a foe") .. ", level " .. r.lv .. " to your " .. r.my .. ", " .. LG.Day(r.t, "short") end },
}
LG.RECORDS = RECORDS

local function LayRecords(ctx)
    local recs = ctx.s.records or {}
    local list = {}
    if next(recs) then
        for _, spec in ipairs(RECORDS) do
            local r = recs[spec[1]]
            if r then
                local value, detail, start, shot = spec[5](r)
                if ctx.account and ctx.plural and r.char and detail then
                    detail = detail .. "  \194\183  " .. ((LG.Name(r.char) or r.char):match("^%S+"))
                end
                -- a campaign opens only from this character's own book
                if start and ctx.account and r.char ~= myFull then start = nil end
                list[#list + 1] = { spec[2], value, detail, spec[4], start, shot }
            elseif spec[3] then
                list[#list + 1] = { spec[2], "none yet", nil, spec[4] }
            end
        end
    end
    P.noRecords:SetShown(#list == 0)
    -- 44 apart with a detail, 30 without; closer if all thirteen are set
    -- (Claude's call: the page holds at most thirteen without a sheet)
    local g = G.rec
    local need = 0
    for _, e in ipairs(list) do need = need + (e[3] and g.step or g.plain) end
    local bottom = g.bottom - (ctx.only and 28 or 0)   -- room for the line under the records
    local k = math.min(1, (bottom - g.y) / math.max(1, need - g.step + g.dy + 4))
    local y = g.y
    for i = 1, #P.recs do
        local e = list[i]
        local row, d, hot = P.recs[i], P.details[i], P.recHot[i]
        if e then
            row:Set(e[1], e[2], g.x0, g.x1, y, e[2] == "none yet")
            d:SetShown(e[3] ~= nil)
            if e[3] then
                -- a long detail is cut short with "..." at the value's right edge
                local text = e[3]
                while Book.Measure("gari", g.dpx, text) > g.x1 - g.dx and #text > 4 do
                    text = LG.Shorten(text)
                end
                Set(d, text)
                Put(d, g.dx, y + g.dy, "l")
            end
            hot.label, hot.def, hot.start, hot.shot = e[1], e[4], e[5], e[6]
            Book.Box(hot, g.x0, y - 17, g.x1, y + (e[3] and g.dy + 5 or 5))
            hot:Show()
            y = y + math.floor((e[3] and g.step or g.plain) * k + 0.5)
        else
            row:Hide()
            d:Hide()
            hot:Hide()
        end
    end
end

local function Render(F, ctx)
    LayTally(ctx)
    LayRecords(ctx)
end

LG.spreads[1] = { Build = Build, Render = Render, only = { 801, 664 } }
