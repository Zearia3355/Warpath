-- Warpath: the chronicle's Grudges tab, as it was in 3.8.3 (moved out of
-- Chronicle.lua unchanged for 3.8.5; its redesign is a later phase,
-- docs/design/chronicle-grudges.md).
local ADDON, ns = ...
local C = ns.C
local MapName, Print, UISound, Waypoint, Ago, ClassColor = ns.MapName, ns.Print, ns.UISound, ns.Waypoint, ns.Ago, ns.ClassColor
local Campaign, Grudge, Foes = ns.Campaign, ns.Grudge, ns.Foes
local Book, Chron = ns.Book, ns.Chron
local O = Book.Old
local Font, Solid, Ink, Colored, Diamond, Ornament, Topic, DropCap, TurnButton =
    O.Font, O.Solid, O.Ink, O.Colored, O.Diamond, O.Ornament, O.Topic, O.DropCap, O.TurnButton
local INK, FADED, RUBRIC = O.INK, O.FADED, O.RUBRIC
local PW, PH = Book.PW, Book.PH
local TEX = { hilite = "Interface\Buttons\UI-Common-MouseHilight" }
local view = Chron.view
local function Render() Chron.Render() end

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)
local INDEX_ROWS, LOG_ROWS = 9, 11

local SAMPLE_GRUDGES

local function GrudgeList()
    if view.preview then return SAMPLE_GRUDGES end
    local list = Grudge.List()
    table.sort(list, function(a, b)
        local ta = a.r.seen and a.r.seen.t or a.r.added or 0
        local tb = b.r.seen and b.r.seen.t or b.r.added or 0
        if ta ~= tb then return ta > tb end
        return a.full < b.full
    end)
    return list
end

local function LastSeen(r)
    if r.seen then return MapName(r.seen.z) .. ", " .. Ago(r.seen.t) end
    return "not seen since " .. date("%b %d", r.added or time())
end

local LOG_TEXT = {
    g = function() return "Grudge inscribed." end,
    a = function() return "Grudge added after repeated deaths." end,
    s = function(z) return "Sighted" .. z .. "." end,
    k = function(z) return "Slew them" .. z .. ". |cff7a1f0fSettled.|r" end,
    d = function(z) return "Fell to them" .. z .. "." end,
}

local function BuildGrudgePages(f)
    local L = CreateFrame("Frame", nil, f.left)
    L:SetAllPoints()
    local R = CreateFrame("Frame", nil, f.right)
    R:SetAllPoints()
    f.gr = { L = L, R = R }
    local g = f.gr
    local inner = PW - 64

    local title = Font(L, QuestTitleFont, GameFontNormalLarge, INK)
    title:SetPoint("TOP", 0, -32)
    title:SetJustifyH("CENTER")
    title:SetText("The Ledger of Grudges")
    Ornament(L, -60)
    g.summary = Font(L, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    g.summary:SetPoint("TOP", 0, -70)
    g.summary:SetJustifyH("CENTER")

    g.rows = {}
    for i = 1, INDEX_ROWS do
        local row = CreateFrame("Button", nil, L)
        row:SetSize(inner + 8, 38)
        row:SetPoint("TOPLEFT", 28, -142 - (i - 1) * 40)
        row:SetHighlightTexture(TEX.hilite, "ADD")
        row.sel = Solid(row, "BACKGROUND", 0.48, 0.12, 0.06, 0.12)
        row.sel:SetAllPoints()
        row.mark = Diamond(row, 7)
        row.mark:SetPoint("RIGHT", row, "LEFT", -3, 8)
        row.name = Font(row, QuestFont, GameFontHighlight, INK)
        row.name:SetPoint("TOPLEFT", 4, -3)
        row.tally = Font(row, QuestFont, GameFontHighlight, INK)
        row.tally:SetPoint("TOPRIGHT", -4, -3)
        row.tally:SetJustifyH("RIGHT")
        row.sub = Font(row, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        row.sub:SetPoint("TOPLEFT", 4, -21)
        row.sub:SetWidth(inner)
        row.sub:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            view.pick = self.index
            UISound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
            Render()
        end)
        g.rows[i] = row
    end
    g.scroll = CreateFrame("ScrollFrame", "WarpathChronicleLedger", L, "FauxScrollFrameTemplate")
    g.scroll:SetPoint("TOPLEFT", 28, -142)
    g.scroll:SetSize(inner + 4, INDEX_ROWS * 40)
    g.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 40, Render)
    end)
    g.empty = Font(L, QuestFont, GameFontHighlight, FADED)
    g.empty:SetPoint("TOP", 0, -160)
    g.empty:SetWidth(inner)
    g.empty:SetJustifyH("CENTER")
    g.empty:SetText("No grudges held.\n\nTarget an enemy and click the skull\non the war table, or inscribe a name.")

    local legend = Font(L, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    legend:SetPoint("TOPRIGHT", -36, -126)
    legend:SetJustifyH("RIGHT")
    legend:SetText("|cff2e5a1cyou|r \194\183 |cff7a1f0fthem|r")
    g.legend = legend
    local byName = CreateFrame("Button", nil, L, "UIPanelButtonTemplate")
    byName:SetSize(160, 24)
    byName:SetPoint("TOP", L, "TOP", 0, -92)
    byName:SetText("Inscribe a name...")
    byName:SetScript("OnClick", function() if not view.preview then StaticPopup_Show("WARPATH_GRUDGE_NAME") end end)

    -- right page: the chosen grudge
    local E = CreateFrame("Frame", nil, R)
    E:SetAllPoints()
    g.entry = E
    g.cap = DropCap(E, 48)
    g.cap:SetPoint("TOPLEFT", 32, -34)
    g.name = Font(E, QuestTitleFont, GameFontNormalHuge, INK, 26)
    g.name:SetPoint("BOTTOMLEFT", g.cap, "BOTTOMRIGHT", 2, 6)
    g.who = Font(E, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    g.who:SetPoint("TOPLEFT", g.cap, "BOTTOMLEFT", 0, -6)
    g.who:SetWidth(inner)
    g.since = Font(E, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    g.since:SetPoint("TOPLEFT", g.who, "BOTTOMLEFT", 0, -2)
    g.since:SetWidth(inner)

    local top = Solid(E, "ARTWORK", FADED[1], FADED[2], FADED[3], 0.45)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", 32, -130)
    top:SetPoint("TOPRIGHT", -32, -130)
    local bottom = Solid(E, "ARTWORK", FADED[1], FADED[2], FADED[3], 0.45)
    bottom:SetHeight(1)
    bottom:SetPoint("TOPLEFT", 32, -178)
    bottom:SetPoint("TOPRIGHT", -32, -178)
    g.tallies = {}
    local labels = { "you slew them", "they slew you", "settled" }
    local colors = { { 0.18, 0.35, 0.11 }, RUBRIC, INK }
    for i = 1, 3 do
        local v = Font(E, QuestTitleFont, GameFontNormalLarge, colors[i], 20)
        v:SetPoint("TOP", E, "TOPLEFT", 32 + inner / 3 * (i - 0.5), -136)
        v:SetJustifyH("CENTER")
        local lab = Font(E, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        lab:SetPoint("TOP", v, "BOTTOM", 0, -2)
        lab:SetJustifyH("CENTER")
        lab:SetText(labels[i])
        g.tallies[i] = v
    end

    -- the note: click to write, Enter to keep
    local note = CreateFrame("EditBox", nil, E)
    note:SetSize(inner, 24)
    note:SetPoint("TOPLEFT", 32, -190)
    note:SetAutoFocus(false)
    note:SetMaxLetters(120)
    if not pcall(note.SetFontObject, note, QuestFont) then note:SetFontObject(GameFontHighlight) end
    note:SetTextColor(INK[1], INK[2], INK[3])
    local underline = Solid(note, "BORDER", FADED[1], FADED[2], FADED[3], 0.35)
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT")
    underline:SetPoint("BOTTOMRIGHT")
    note.hint = Font(note, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    note.hint:SetPoint("LEFT", 2, 0)
    note.hint:SetText("Click to write a note about them...")
    local function Keep(self)
        if self.full and not view.preview then Grudge.SetNote(self.full, self:GetText()) end
        self:ClearFocus()
    end
    note:SetScript("OnEnterPressed", Keep)
    note:SetScript("OnEditFocusLost", function(self)
        if self.full and not view.preview then Grudge.SetNote(self.full, self:GetText()) end
        self.hint:SetShown(self:GetText() == "")
    end)
    note:SetScript("OnEditFocusGained", function(self) self.hint:Hide() end)
    note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    g.note = note

    local enc = Font(E, QuestTitleFont, GameFontNormal, RUBRIC, 14)
    enc:SetPoint("TOPLEFT", 32, -266)
    enc:SetText("Encounters")
    -- 3.8.3: newest first under a heading for each day, the time beside each
    g.log = {}
    for i = 1, LOG_ROWS do
        local t = Font(E, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        t:SetPoint("TOPLEFT", 32, -290 - (i - 1) * 19)
        t:SetWidth(44)
        local text = Font(E, QuestFont, GameFontHighlight, INK)
        text:SetPoint("TOPLEFT", 80, -288 - (i - 1) * 19)
        text:SetWidth(inner - 48)
        text:SetWordWrap(false)
        g.log[i] = { t = t, text = text, topic = Topic(E, nil) }
        g.log[i].topic:SetShown(false)
    end

    local way = CreateFrame("Button", nil, E, "UIPanelButtonTemplate")
    way:SetSize(190, 24)
    way:SetPoint("TOP", E, "TOP", -60, -226)
    way:SetText("Waypoint to last sighting")
    way:SetScript("OnClick", function()
        local item = view.grudges[view.pick]
        local s = item and item.r.seen
        if s and not view.preview then Waypoint(s.z, s.x, s.y, "where you last saw " .. Grudge.Short(item.full)) end
    end)
    g.way = way
    local forgive = CreateFrame("Button", nil, E, "UIPanelButtonTemplate")
    forgive:SetSize(110, 24)
    forgive:SetPoint("TOP", E, "TOP", 100, -226)
    forgive:SetText("Forgive")
    forgive:SetScript("OnClick", function()
        local item = view.grudges[view.pick]
        if item and not view.preview then
            StaticPopup_Show("WARPATH_GRUDGE_FORGIVE", Grudge.Short(item.full), nil, item.full)
        end
    end)
    g.forgive = forgive
end

local function RenderGrudges()
    local f, g = Chron.book, Chron.book.gr
    local list = GrudgeList()
    view.grudges = list
    if view.pick > #list then view.pick = math.max(1, #list) end
    local settledWeek = 0
    for _, item in ipairs(list) do
        for _, e in ipairs(item.r.log or {}) do
            if e.k == "k" and time() - e.t < 7 * C.DAY then settledWeek = settledWeek + 1 end
        end
    end
    local held = #list == 1 and "One grudge" or (Campaign.Word(#list):gsub("^%l", string.upper) .. " grudges")
    g.summary:SetText(#list == 0 and "" or (held .. " held  \194\183  " .. (settledWeek == 0 and "none" or Campaign.Word(settledWeek))
        .. " settled this week  \194\183  last seen first"))
    g.empty:SetShown(#list == 0)
    g.legend:SetShown(#list > 0)

    FauxScrollFrame_Update(g.scroll, #list, INDEX_ROWS, 40)
    local offset = FauxScrollFrame_GetOffset(g.scroll)
    for i, row in ipairs(g.rows) do
        local item = list[i + offset]
        if item then
            local r = item.r
            row.index = i + offset
            row.name:SetText(Colored(Grudge.Short(item.full), r.class))
            -- 3.8.3: no dot leaders; a grudge with no blood either way says so
            row.tally:SetText(((r.kills or 0) + (r.deaths or 0) == 0) and "|cff6a5030no blood yet|r"
                or ("|cff2e5a1c%d|r |cff8a6c44\194\183|r |cff7a1f0f%d|r"):format(r.kills or 0, r.deaths or 0))
            local tags = {}
            if r.auto then tags[#tags + 1] = "added automatically" end
            row.sub:SetText(LastSeen(r) .. (#tags > 0 and ("  \194\183  " .. table.concat(tags, ", ")) or ""))
            local picked = row.index == view.pick
            row.sel:SetShown(picked)
            row.mark:SetShown(picked)
            row:Show()
        else
            row:Hide()
        end
    end

    local item = list[view.pick]
    g.entry:SetShown(item ~= nil)
    f.right.number:SetText("")
    f.left.number:SetText("")
    if not item then return end
    local r, short = item.r, Grudge.Short(item.full)
    g.cap.letter:SetText(short:sub(1, 1))
    local cr, cg, cb = INK[1], INK[2], INK[3]
    if r.class then cr, cg, cb = Ink(ClassColor(r.class)) end
    g.name:SetTextColor(cr, cg, cb)
    g.name:SetText(short:sub(2))
    local who = Foes.Describe(r.lv, r.ra, r.class, nil)
    who = who ~= "" and ((r.lv and "Level " or "") .. who) or "Class unknown"
    local realm = item.full:match("%-(.+)$")
    if realm == GetNormalizedRealmName() then realm = nil end
    g.who:SetText(who .. (r.gu and ("  \194\183  <" .. r.gu .. ">") or "") .. (realm and ("  \194\183  " .. realm) or ""))
    g.since:SetText("Held since " .. date("%B %d", r.added or time()):gsub(" 0(%d)", " %1")
        .. (r.auto and ", added automatically" or ""))
    g.tallies[1]:SetText(r.kills or 0)
    g.tallies[2]:SetText(r.deaths or 0)
    g.tallies[3]:SetText(r.settled or 0)
    g.note.full = item.full
    g.note:SetText(r.note or "")
    g.note.hint:SetShown((r.note or "") == "")
    local log, rows, day = r.log or {}, {}, nil
    for k = #log, 1, -1 do
        local e = log[k]
        local d = date("%Y%m%d", e.t)
        if d ~= day then
            day = d
            rows[#rows + 1] = { day = d == date("%Y%m%d") and "Today" or (date("%B %d", e.t):gsub(" 0(%d)", " %1")) }
        end
        rows[#rows + 1] = e
        if #rows >= LOG_ROWS then break end
    end
    if rows[#rows] and rows[#rows].day then rows[#rows] = nil end -- never a day with nothing under it
    for i, line in ipairs(g.log) do
        local e = rows[i]
        line.topic:SetShown(e and e.day and true or false)
        if e and e.day then
            line.t:SetText("")
            line.text:SetText("")
            line.topic:Set(e.day, 32, 290 + (i - 1) * 19)
        elseif e then
            line.t:SetText(date("%H:%M", e.t))
            local fn = LOG_TEXT[e.k]
            line.text:SetText(fn and fn(e.z and (" in " .. MapName(e.z)) or "") or "")
        else
            line.t:SetText("")
            line.text:SetText(i == 1 and "|cff6a5030Nothing yet.|r" or "")
        end
    end
    if r.seen and not view.preview then g.way:Enable() else g.way:Disable() end
    if view.preview then g.forgive:Disable() else g.forgive:Enable() end
end

-- Sample grudges for the preview.
SAMPLE_GRUDGES = {
    { full = "Wreckless-Sample", r = { class = "ROGUE", lv = 60, ra = "Human", gu = "Stormwind Guard", kills = 1, deaths = 4,
        settled = 1, added = time() - 2 * C.DAY, note = "Camped me at the flight master.",
        seen = { t = time() - 1200, z = 1424, x = 0.5, y = 0.5 },
        log = { { t = time() - 2 * C.DAY, k = "d", z = 1424 }, { t = time() - 2 * C.DAY + 60, k = "g" },
            { t = time() - C.DAY, k = "k", z = 1424 }, { t = time() - 1800, k = "d", z = 1424 },
            { t = time() - 1200, k = "s", z = 1424 } } } },
    { full = "Thrall-Sample", r = { class = "SHAMAN", lv = 58, ra = "Dwarf", kills = 3, deaths = 2, settled = 3,
        added = time() - 5 * C.DAY, seen = { t = time() - 2 * C.DAY, z = 1416, x = 0.5, y = 0.5 }, log = {} } },
    { full = "Jaina-Sample", r = { class = "MAGE", lv = -1, ra = "Gnome", kills = 5, deaths = 1, settled = 5,
        added = time() - 9 * C.DAY, note = "Sheeps, then runs. Every time.", seen = { t = time() - C.DAY, z = 1424, x = 0.5, y = 0.5 }, log = {} } },
    { full = "Varian-Sample", r = { class = "WARRIOR", kills = 0, deaths = 3, settled = 0, auto = true,
        added = time() - 7 * C.DAY, log = {} } },
}

Chron.pages.grudges = {
    Build = BuildGrudgePages,
    Render = RenderGrudges,
    Reset = function(b) b.gr.scroll:SetVerticalScroll(0) end,
}
