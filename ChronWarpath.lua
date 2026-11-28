-- Warpath: the chronicle's Warpath tab (3.8.3: the welcome and What's New),
-- moved out of Chronicle.lua unchanged for 3.8.5; its redesign is a later
-- phase (docs/design/chronicle-warpath.md).
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

---------------------------------------------------------------------------
-- Warpath (3.8.3): a welcome and the way to the settings (left), what's new
-- in each release, newest first (right). Opens by itself after an update
-- (Options.lua, MaybeShowSetup), marking what this account hasn't seen.
---------------------------------------------------------------------------

local NEWS_TOP, NEWS_FLOOR = 66, PH - 44   -- the right page's notes run between these
local NEWS_SIZE = 13                       -- the notes' type: smaller than the welcome, as in Joe's pick (C)

-- The sharing switch on the welcome page (3.8.3), the same as Settings, Guild.
local function ShareCheck(L)
    local cb = CreateFrame("CheckButton", nil, L, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("BOTTOMLEFT", 32, 74)
    cb.label = Font(L, QuestFont, GameFontHighlight, INK)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText("Guild sharing")
    cb.hint = Font(L, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    cb.hint:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 24, 1)
    cb.hint:SetWidth(PW - 64 - 24)
    cb.hint:SetSpacing(1)
    cb.hint:SetText("Guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on. Never your trail.")
    cb:SetScript("OnClick", function(self)
        if view.preview then self:SetChecked(cfg.share) return end
        ns.Dispatch("share " .. (self:GetChecked() and "on" or "off"))
    end)
    return cb
end

local function BuildNewsPages(f)
    local L = CreateFrame("Frame", nil, f.left)
    L:SetAllPoints()
    local R = CreateFrame("Frame", nil, f.right)
    R:SetAllPoints()
    f.news = { L = L, R = R, heads = {}, lines = {}, topics = {} }
    local n = f.news
    local inner = PW - 64

    n.version = Font(L, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    n.version:SetPoint("TOP", 0, -30)
    n.version:SetJustifyH("CENTER")
    n.headline = Font(L, QuestTitleFont, GameFontNormalLarge, INK)
    n.headline:SetPoint("TOP", 0, -46)
    n.headline:SetWidth(inner)
    n.headline:SetJustifyH("CENTER")
    Ornament(L, -80)
    n.prose = Font(L, QuestFont, GameFontHighlight, INK)
    n.prose:SetPoint("TOPLEFT", 32, -96)
    n.prose:SetWidth(inner)
    n.prose:SetJustifyV("TOP")
    n.prose:SetSpacing(3)
    n.share = ShareCheck(L) -- 3.8.3: the Settings tab is beside this one, so no Settings button
    n.measure = Font(R, QuestFont, GameFontHighlight, INK, NEWS_SIZE) -- measures notes for the page count
    n.measure:SetWidth(PW - 64 - 14)
    n.measure:SetSpacing(2)
    n.measure:Hide()

    local head = Font(R, QuestTitleFont, GameFontNormal, RUBRIC, 15)
    head:SetPoint("TOP", 0, -30)
    head:SetText("What's New")
    Ornament(R, -54)
    n.earlier = TurnButton(R, "Earlier", true)
    n.earlier:SetPoint("BOTTOMLEFT", 24, 8)
    n.earlier:SetScript("OnClick", function()
        if view.newsNext then
            table.insert(view.newsStack, { view.newsStart, view.newsLine })
            view.newsStart, view.newsLine = view.newsNext[1], view.newsNext[2]
            UISound("IG_ABILITY_PAGE_TURN", 836)
            Render()
        end
    end)
    n.later = TurnButton(R, "Later", false)
    n.later:SetPoint("BOTTOMRIGHT", -24, 8)
    n.later:SetScript("OnClick", function()
        if #view.newsStack > 0 then
            local p = table.remove(view.newsStack)
            view.newsStart, view.newsLine = p[1], p[2]
            UISound("IG_ABILITY_PAGE_TURN", 836)
            Render()
        end
    end)
end

local function Welcome()
    return table.concat({
        "Warpath draws your war on the world map: the roads you travel, today's trail, where you fought, killed and fell, and the enemies you've seen.",
        "This book keeps a campaign for each time you ride out, and your ledger of grudges. Open it from the minimap button or with /warpath chronicle.",
        "On the world map, the crossed swords in the top-right corner hide Warpath or choose what it shows. Everything else is on the Settings tab.",
    }, "\n\n")
end

-- Pooled pieces of the notes page: release headings (the version in red,
-- its title faded, a "new" mark on the right, a rule under), topics, and
-- lines with a diamond.
local function NewsHead(n, i)
    local h = n.heads[i]
    if not h then
        h = { ver = Font(n.R, QuestTitleFont, GameFontNormal, RUBRIC, 18),
            title = Font(n.R, QuestFontNormalSmall, GameFontNormalSmall, FADED, 11),
            badge = Solid(n.R, "ARTWORK", RUBRIC[1], RUBRIC[2], RUBRIC[3], 1),
            new = Font(n.R, QuestFontNormalSmall, GameFontNormalSmall, { 0.94, 0.80, 0.51 }, 10),
            rule = Solid(n.R, "ARTWORK", RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.5) }
        h.title:SetPoint("BOTTOMLEFT", h.ver, "BOTTOMRIGHT", 8, 1)
        h.title:SetWordWrap(false)
        h.new:SetText("NEW")
        h.new:SetPoint("TOPRIGHT", n.R, "TOPRIGHT", -38, 0)
        h.badge:SetPoint("TOPLEFT", h.new, "TOPLEFT", -5, 3)
        h.badge:SetPoint("BOTTOMRIGHT", h.new, "BOTTOMRIGHT", 5, -3)
        h.rule:SetHeight(1)
        n.heads[i] = h
    end
    return h
end

local function PlaceHead(n, h, y, ver, title, new)
    h.ver:ClearAllPoints()
    h.ver:SetPoint("TOPLEFT", 32, -y)
    h.ver:SetText(ver)
    h.title:SetText(title or "")
    h.title:SetWidth(PW - 64 - ((h.ver:GetStringWidth() or #ver * 8) + 8) - (new and 44 or 0))
    h.new:ClearAllPoints()
    h.new:SetPoint("TOPRIGHT", n.R, "TOPLEFT", PW - 37, -(y + 3))
    h.new:SetShown(new)
    h.badge:SetShown(new)
    h.rule:ClearAllPoints()
    h.rule:SetPoint("TOPLEFT", 32, -(y + 24))
    h.rule:SetWidth(PW - 64)
    for _, part in ipairs({ h.ver, h.title, h.rule }) do part:Show() end
end

local function HideHead(h) for _, part in pairs(h) do part:Hide() end end

local function NewsLine(n, i)
    local l = n.lines[i]
    if not l then
        l = Font(n.R, QuestFont, GameFontHighlight, INK, NEWS_SIZE)
        l:SetWidth(PW - 64 - 14)
        l:SetJustifyV("TOP")
        l:SetSpacing(2)
        l.dot = Diamond(n.R, 5)
        n.lines[i] = l
    end
    l:Show()
    l.dot:Show()
    return l
end

local function NewsTopic(n, i)
    n.topics[i] = n.topics[i] or Topic(n.R, nil)
    return n.topics[i]
end

-- A line's height once wrapped (measured, or guessed before it's drawn).
local function LineHeight(l, text)
    local lh = l:GetStringHeight() or 0
    local guess = math.ceil(((l:GetStringWidth() or #text * 6)) / (PW - 78)) * (NEWS_SIZE + 2)
    return math.max(lh, guess)
end

-- 3.8.3: grouped by topic ("## " lines) under each release's heading. A
-- page starts at a release and an item within it; a release too long for
-- what's left of the page carries on to the next. Lay() draws one page, or
-- with draw false only measures it (for the page count); it returns where
-- the next page starts, or nil on the last.
local function Lay(n, list, i, j, draw)
    local Older = ns.NewIn and ns.NewIn.Older
    local y, nh, nl, nt, placed, nxt = NEWS_TOP, 0, 0, 0, 0, nil
    while i >= 1 and not nxt do
        local rel = list[i]
        local items = rel[2]
        if y + 30 + 30 > NEWS_FLOOR and placed > 0 then nxt = { i, j } break end -- no room for a heading and a line
        if draw then
            nh = nh + 1
            local new = view.newSince and Older and Older(view.newSince, rel[1]) and true or false
            PlaceHead(n, NewsHead(n, nh), y, rel[1] .. (j > 1 and " (continued)" or ""), rel.title, new)
        end
        y = y + 34
        while j <= #items do
            local text = items[j]
            local topic = text:sub(1, 3) == "## " and text:sub(4)
            if topic then
                if y + 20 + 30 > NEWS_FLOOR and placed > 0 then nxt = { i, j } break end
                if draw then
                    nt = nt + 1
                    NewsTopic(n, nt):Set(topic, 32, y)
                end
                y = y + 20
            else
                local l = draw and NewsLine(n, nl + 1) or n.measure
                l:SetText(text)
                local lh = LineHeight(l, text)
                if y + lh > NEWS_FLOOR and placed > 0 then
                    if draw then l:Hide() l.dot:Hide() end
                    nxt = { i, j }
                    break
                end
                if draw then
                    nl = nl + 1
                    l:ClearAllPoints()
                    l:SetPoint("TOPLEFT", 46, -y)
                    l.dot:ClearAllPoints()
                    l.dot:SetPoint("CENTER", n.R, "TOPLEFT", 38, -(y + 7))
                end
                y = y + lh + 4
                placed = placed + 1
            end
            j = j + 1
            if items[j] and items[j]:sub(1, 3) == "## " then y = y + 4 end
        end
        y = y + 12
        if not nxt then i, j = i - 1, 1 end
    end
    if draw then
        for k = nh + 1, #n.heads do HideHead(n.heads[k]) end
        for k = nl + 1, #n.lines do n.lines[k]:Hide() n.lines[k].dot:Hide() end
        for k = nt + 1, #n.topics do n.topics[k]:SetShown(false) end
    end
    return nxt
end

local function RenderNews()
    local f, n = Chron.book, Chron.book.news
    local list = ns.NewIn and ns.NewIn.List or {}
    f.left.number:SetText("")
    n.version:SetText("Version " .. tostring(ns.VERSION))
    n.headline:SetText(gdb.installed and "Warpath" or "Welcome to Warpath")
    n.prose:SetText(Welcome())
    n.share:SetChecked(cfg.share and true or false)
    view.newsStart = math.min(view.newsStart or #list, #list)
    view.newsLine = view.newsLine or 1
    view.newsNext = Lay(n, list, view.newsStart, view.newsLine, true)
    -- "1 of 2" under the notes, as in the mock (pages open newest first)
    local page, pages, at = #view.newsStack + 1, #view.newsStack + 1, view.newsNext
    while at and pages < 50 do
        pages = pages + 1
        at = Lay(n, list, at[1], at[2], false)
    end
    f.right.number:SetText(pages > 1 and (page .. " of " .. pages) or "")
    if view.newsNext then n.earlier:Enable() else n.earlier:Disable() end
    if #view.newsStack > 0 then n.later:Enable() else n.later:Disable() end
end

Chron.pages.warpath = { Build = BuildNewsPages, Render = RenderNews }
