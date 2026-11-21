-- Warpath: Chronicle
-- The chronicle as a book: an open two-page spread on a leather cover, with
-- two sections (Campaigns and Grudges) on tabs at the book's right edge.
-- Built only from the game's own textures and fonts.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local ClassColor, MapName, Print, UISound, Waypoint, Ago = ns.ClassColor, ns.MapName, ns.Print, ns.UISound, ns.Waypoint, ns.Ago
local Campaign, Grudge, Foes = ns.Campaign, ns.Grudge, ns.Foes

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local W, H = 880, 580
local PAD = 18                       -- leather around the pages
local PW = (W - 2 * PAD) / 2         -- one page
local PH = H - 2 * PAD
local INK, FADED, RUBRIC = { 0.18, 0.11, 0.04 }, { 0.30, 0.22, 0.12 }, { 0.48, 0.12, 0.06 }
local LEATHER = { 0.27, 0.14, 0.06 }
local GILT = { 0.84, 0.66, 0.32 }
local DEED_ROWS, INDEX_ROWS, LOG_ROWS = 13, 9, 11
local NONE = "|cff4d3a20\226\128\148|r"
local TEX = {
    border  = "Interface\\DialogFrame\\UI-DialogBox-Border",
    header  = "Interface\\DialogFrame\\UI-DialogBox-Header",
    page    = "Interface\\QuestFrame\\QuestBG",
    classes = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
    sword   = "Interface\\Icons\\INV_Sword_04",
    prev    = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
    next    = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    hilite  = "Interface\\Buttons\\UI-Common-MouseHilight",
}
local TAG_TEXT = { first = "first blood", grudge = "a grudge settled", avenged = "avenged", streak = "streak" }

local book
local view = { section = "campaigns", list = {}, page = 1, preview = false, grudges = {}, pick = 1 }

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Font(parent, object, fallback, color, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    if not (object and pcall(fs.SetFontObject, fs, object)) then fs:SetFontObject(fallback) end
    if size then
        local path, _, flags = fs:GetFont()
        if path then pcall(fs.SetFont, fs, path, size, flags or "") end
    end
    color = color or INK
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Solid(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Class colours darkened to ink so every class reads on parchment.
local function Ink(r, g, b)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    local k = lum > 0.28 and 0.28 / lum or 1
    return r * k, g * k, b * k
end

local function Colored(name, class)
    if not name then return "|cff4d3a20someone unseen|r" end
    local r, g, b = INK[1], INK[2], INK[3]
    if class then r, g, b = Ink(ClassColor(class)) end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

local ROMAN = { { 1000, "m" }, { 900, "cm" }, { 500, "d" }, { 400, "cd" }, { 100, "c" }, { 90, "xc" },
    { 50, "l" }, { 40, "xl" }, { 10, "x" }, { 9, "ix" }, { 5, "v" }, { 4, "iv" }, { 1, "i" } }
local function Roman(n)
    local out = ""
    for _, p in ipairs(ROMAN) do while n >= p[1] do out, n = out .. p[2], n - p[1] end end
    return out
end

-- A small red diamond (a square turned 45 degrees).
local function Diamond(parent, size)
    local t = Solid(parent, "ARTWORK", RUBRIC[1], RUBRIC[2], RUBRIC[3], 1)
    t:SetSize(size, size)
    pcall(t.SetRotation, t, math.pi / 4)
    return t
end

-- A thin rule with a small red diamond in the middle.
local function Ornament(parent, y)
    local l = Solid(parent, "ARTWORK", RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.7)
    l:SetSize(70, 1)
    l:SetPoint("TOP", parent, "TOP", -46, y)
    local r = Solid(parent, "ARTWORK", RUBRIC[1], RUBRIC[2], RUBRIC[3], 0.7)
    r:SetSize(70, 1)
    r:SetPoint("TOP", parent, "TOP", 46, y)
    local d = Diamond(parent, 7)
    d:SetPoint("CENTER", parent, "TOP", 0, y)
end

-- A big red initial on a gilt-edged square.
local function DropCap(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size + 4)
    local edge = Solid(f, "BORDER", GILT[1], GILT[2], GILT[3], 1)
    edge:SetAllPoints()
    local fill = Solid(f, "ARTWORK", 0.45, 0.08, 0.04, 1)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    f.letter = Font(f, QuestTitleFont, GameFontNormalHuge, { 0.95, 0.78, 0.38 }, math.floor(size * 0.8))
    f.letter:SetPoint("CENTER", 0, -1)
    f.letter:SetJustifyH("CENTER")
    return f
end

-- A quiet page-turn control: the spellbook arrow and a word in ink.
local function TurnButton(parent, text, onLeft)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(96, 28)
    local arrow = b:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(onLeft and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    arrow:SetSize(28, 28)
    arrow:SetPoint(onLeft and "LEFT" or "RIGHT")
    b.label = Font(b, QuestFont, GameFontHighlight, INK)
    if onLeft then b.label:SetPoint("LEFT", arrow, "RIGHT", 2, 0) else b.label:SetPoint("RIGHT", arrow, "LEFT", -2, 0) end
    b.label:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(arrow)
    b:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    b:SetScript("OnDisable", function(self) self:SetAlpha(0.3) end)
    return b
end

local function ClassIcon(tex, class)
    local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if c then
        tex:SetTexture(TEX.classes)
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
        tex:Show()
    else
        tex:Hide()
    end
end

---------------------------------------------------------------------------
-- The book: cover, two pages, spine, title, section tabs
---------------------------------------------------------------------------

local Render

local function Page(f, left)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(PW, PH)
    if left then p:SetPoint("TOPLEFT", PAD, -PAD) else p:SetPoint("TOPRIGHT", -PAD, -PAD) end
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(TEX.page)
    if left then bg:SetTexCoord(0, 0.5859375, 0, 0.65625) else bg:SetTexCoord(0.5859375, 0, 0, 0.65625) end
    bg:SetAllPoints()
    -- stacked page edges on the outer side
    for i, a in ipairs({ 0.55, 0.35, 0.55 }) do
        local e = Solid(p, "BORDER", 0.78, 0.66, 0.45, a)
        e:SetWidth(1)
        e:SetPoint(left and "TOPRIGHT" or "TOPLEFT", p, left and "TOPLEFT" or "TOPRIGHT", left and -i * 2 + 1 or i * 2 - 1, -2 - i)
        e:SetPoint(left and "BOTTOMRIGHT" or "BOTTOMLEFT", p, left and "BOTTOMLEFT" or "BOTTOMRIGHT", left and -i * 2 + 1 or i * 2 - 1, 2 + i)
    end
    -- the inner margin darkens into the spine
    for i = 1, 7 do
        local s = Solid(p, "BORDER", 0.20, 0.11, 0.03, 0.05 * (8 - i))
        s:SetWidth(3)
        s:SetPoint(left and "TOPRIGHT" or "TOPLEFT", p, left and "TOPRIGHT" or "TOPLEFT", left and -(i - 1) * 3 or (i - 1) * 3, 0)
        s:SetPoint(left and "BOTTOMRIGHT" or "BOTTOMLEFT", p, left and "BOTTOMRIGHT" or "BOTTOMLEFT", left and -(i - 1) * 3 or (i - 1) * 3, 0)
    end
    p.number = Font(p, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    p.number:SetPoint("BOTTOM", 0, 14)
    p.number:SetJustifyH("CENTER")
    return p
end

-- Section tabs stand on the top edge of the book, left of the title plate,
-- dark with a gilt edge like the plate. The open section's tab is taller.
local function SectionTab(f, label, key, x)
    local t = CreateFrame("Button", nil, f)
    t:SetSize(116, 26)
    t:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, -8)
    t:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    t.edge = Solid(t, "BACKGROUND", GILT[1], GILT[2], GILT[3], 0.9)
    t.edge:SetAllPoints()
    t.bg = Solid(t, "BORDER", 0.10, 0.07, 0.04, 1)
    t.bg:SetPoint("TOPLEFT", 2, -2)
    t.bg:SetPoint("BOTTOMRIGHT", -2, 0)
    t.text = Font(t, GameFontNormal, GameFontNormal, { 0.85, 0.78, 0.62 })
    t.text:SetPoint("CENTER", 0, 3)
    t.text:SetJustifyH("CENTER")
    t.text:SetText(label)
    local hl = Solid(t, "HIGHLIGHT", 1, 0.82, 0, 0.10)
    hl:SetPoint("TOPLEFT", 2, -2)
    hl:SetPoint("BOTTOMRIGHT", -2, 0)
    t:SetScript("OnClick", function()
        if view.section ~= key then
            view.section = key
            UISound("IG_ABILITY_PAGE_TURN", 836)
            Render()
        end
    end)
    t.key = key
    return t
end

local function BuildBook()
    local f = CreateFrame("Frame", "WarpathChronicle", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER", -40, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WarpathChronicle")
    f:SetScript("OnHide", function() UISound("IG_QUEST_LOG_CLOSE", 845) end)

    -- leather cover with a gilt tooled line
    local leather = Solid(f, "BACKGROUND", LEATHER[1], LEATHER[2], LEATHER[3], 1, -8)
    leather:SetPoint("TOPLEFT", 6, -6)
    leather:SetPoint("BOTTOMRIGHT", -6, 6)
    local shade = Solid(f, "BACKGROUND", 0, 0, 0, 0.25, -7)
    shade:SetPoint("BOTTOMLEFT", 6, 6)
    shade:SetPoint("BOTTOMRIGHT", -6, 6)
    shade:SetHeight(H / 2)
    f:SetBackdrop({ edgeFile = TEX.border, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    f:SetBackdropBorderColor(GILT[1], GILT[2], GILT[3], 1)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 10, -10, -10, -10, true }, { "BOTTOMLEFT", "BOTTOMRIGHT", 10, 10, -10, 10, true },
        { "TOPLEFT", "BOTTOMLEFT", 10, -10, 10, 10 }, { "TOPRIGHT", "BOTTOMRIGHT", -10, -10, -10, 10 } }) do
        local l = Solid(f, "BORDER", GILT[1], GILT[2], GILT[3], 0.45)
        l:SetPoint(side[1], side[3], side[4])
        l:SetPoint(side[2], side[5], side[6])
        if side[7] then l:SetHeight(1) else l:SetWidth(1) end
    end

    f.left, f.right = Page(f, true), Page(f, false)

    -- title plate and close button
    local plate = f:CreateTexture(nil, "OVERLAY")
    plate:SetTexture(TEX.header)
    plate:SetSize(380, 64)
    plate:SetPoint("TOP", 0, 14)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", plate, "TOP", 0, -14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    f.tabs = { SectionTab(f, "Campaigns", "campaigns", 36), SectionTab(f, "Grudges", "grudges", 158) }
    return f
end

---------------------------------------------------------------------------
-- Campaigns: the night written up (left), its deeds (right)
---------------------------------------------------------------------------

local function BuildCampaignPages(f)
    local L = CreateFrame("Frame", nil, f.left)
    L:SetAllPoints()
    local R = CreateFrame("Frame", nil, f.right)
    R:SetAllPoints()
    f.camp = { L = L, R = R }
    local c = f.camp
    local inner = PW - 64

    c.date = Font(L, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    c.date:SetPoint("TOP", 0, -30)
    c.date:SetJustifyH("CENTER")
    c.headline = Font(L, QuestTitleFont, GameFontNormalLarge, INK)
    c.headline:SetPoint("TOP", 0, -46)
    c.headline:SetWidth(inner)
    c.headline:SetJustifyH("CENTER")
    Ornament(L, -80)

    c.prose = Font(L, QuestFont, GameFontHighlight, INK)
    c.prose:SetPoint("TOPLEFT", 32, -96)
    c.prose:SetWidth(inner)
    c.prose:SetJustifyV("TOP")
    c.prose:SetSpacing(2)

    -- numbers and highlights follow straight on from the paragraph
    local box = CreateFrame("Frame", nil, L)
    box:SetSize(inner, 48)
    box:SetPoint("TOPLEFT", c.prose, "BOTTOMLEFT", 0, -16)
    c.statsBox = box
    c.stats = {}
    local labels = { "kills", "deaths", "best streak", "miles", "in the field" }
    local cw = math.floor(inner / 5)
    local top = Solid(box, "ARTWORK", FADED[1], FADED[2], FADED[3], 0.45)
    top:SetHeight(1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    local bottom = Solid(box, "ARTWORK", FADED[1], FADED[2], FADED[3], 0.45)
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    for i = 1, 5 do
        local v = Font(box, QuestTitleFont, GameFontNormalLarge, INK, 17)
        v:SetPoint("TOP", box, "TOPLEFT", cw * (i - 0.5), -6)
        v:SetJustifyH("CENTER")
        local lab = Font(box, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        lab:SetPoint("TOP", v, "BOTTOM", 0, -2)
        lab:SetJustifyH("CENTER")
        lab:SetText(labels[i])
        c.stats[i] = v
    end

    c.high = {}
    for i = 1, 6 do
        local lab = Font(L, QuestFontNormalSmall, GameFontNormalSmall, RUBRIC)
        lab:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -12 - (i - 1) * 21)
        lab:SetWidth(128)
        lab:SetWordWrap(false)
        local val = Font(L, QuestFont, GameFontHighlight, INK)
        val:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 130, -10 - (i - 1) * 21)
        val:SetWidth(inner - 130)
        val:SetWordWrap(false)
        c.high[i] = { label = lab, value = val }
    end

    c.earlier = TurnButton(L, "Earlier", true)
    c.earlier:SetPoint("BOTTOMLEFT", 24, 8)
    c.earlier:SetScript("OnClick", function()
        if view.page < #view.list then view.page = view.page + 1 UISound("IG_ABILITY_PAGE_TURN", 836) Render() end
    end)

    -- right page: deeds and losses
    local head = Font(R, QuestTitleFont, GameFontNormal, RUBRIC, 15)
    head:SetPoint("TOP", 0, -30)
    head:SetText("Deeds and Losses")
    Ornament(R, -54)
    c.rows = {}
    for i = 1, DEED_ROWS do
        local row = CreateFrame("Button", nil, R)
        row:SetSize(inner + 8, 20)
        row:SetPoint("TOPLEFT", 28, -64 - (i - 1) * 21)
        row:SetHighlightTexture(TEX.hilite, "ADD")
        row.time = Font(row, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        row.time:SetPoint("LEFT", 2, 0)
        row.time:SetWidth(40)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(14, 14)
        row.icon:SetPoint("LEFT", 44, 0)
        row.text = Font(row, QuestFont, GameFontHighlight, INK)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetWidth(inner - 62)
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if e and e.z and e.x and not view.preview then
                Waypoint(e.z, e.x, e.y, self.kill and "a kill from your chronicle" or "a death from your chronicle")
            end
        end)
        row:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e or view.preview then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.n then
                GameTooltip:AddLine(e.n, ClassColor(e.c))
                local who = Foes.Describe(e.lv, e.ra, e.c, e.gu)
                if who ~= "" then GameTooltip:AddLine(who, 0.8, 0.8, 0.8) end
            end
            if e.shot then GameTooltip:AddLine(("Screenshot #%d"):format(e.shot), 1, 1, 1) end
            GameTooltip:AddLine("Click to set a waypoint here", 0.1, 1, 0.1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        c.rows[i] = row
    end
    c.scroll = CreateFrame("ScrollFrame", "WarpathChronicleDeeds", R, "FauxScrollFrameTemplate")
    c.scroll:SetPoint("TOPLEFT", 28, -64)
    c.scroll:SetSize(inner + 4, DEED_ROWS * 21)
    c.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 21, Render)
    end)
    c.finis = Font(R, QuestFontNormalSmall, GameFontNormalSmall, FADED)
    c.finis:SetJustifyH("CENTER")

    -- Share: a small plain button beside the page heading
    local share = CreateFrame("Button", nil, R, "UIPanelButtonTemplate")
    share:SetSize(72, 22)
    share:SetPoint("TOPRIGHT", -26, -26)
    share:SetText("Share")
    share:SetScript("OnClick", function(self) ns.ChronicleShareMenu(self) end)
    share:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Share this campaign")
        GameTooltip:AddLine("Two lines in guild, party, say or a whisper.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    share:SetScript("OnLeave", GameTooltip_Hide)
    c.share = share

    c.later = TurnButton(R, "Later", false)
    c.later:SetPoint("BOTTOMRIGHT", -24, 8)
    c.later:SetScript("OnClick", function()
        if view.page > 1 then view.page = view.page - 1 UISound("IG_ABILITY_PAGE_TURN", 836) Render() end
    end)
end

local function Entries(camp)
    local list = {}
    for _, k in ipairs(camp.kl or {}) do list[#list + 1] = { e = k, kill = true } end
    for _, d in ipairs(camp.dl or {}) do list[#list + 1] = { e = d } end
    table.sort(list, function(a, b) return (a.e.t or 0) < (b.e.t or 0) end)
    return list
end

local function DeedText(item)
    local e = item.e
    local where = e.z and (" in " .. MapName(e.z)) or ""
    if item.kill then
        local tag = e.tag and TAG_TEXT[e.tag]
        if e.tag == "streak" and e.st then tag = "a streak of " .. e.st end
        local lv = e.lv and ("|cff6a5030 " .. (e.lv == -1 and "??" or e.lv) .. "|r") or ""
        return "Slew " .. Colored(e.n or "an enemy", e.c) .. lv .. where .. "." ..
            (tag and (" |cff7a1f0f" .. tag:sub(1, 1):upper() .. tag:sub(2) .. ".|r") or "")
    end
    return "Fell" .. (e.n and (" to " .. Colored(e.n, e.c)) or "") .. where .. "."
end

local function RenderCampaign()
    local f, c = book, book.camp
    local camp = view.list[view.page]
    if not camp then return end
    local s = Campaign.Summary(camp)
    local n = #view.list
    local number = n - view.page + 1   -- 1 = the oldest kept

    local status = view.preview and "  \194\183  sample pages"
        or Campaign.IsOpen(camp) and "  \194\183  in progress"
        or (camp.old and "  \194\183  before 3.4: totals only") or ""
    c.date:SetText(date("%A, %B %d", camp.start):gsub(" 0(%d)", " %1") .. status)
    c.headline:SetText(s.title)
    local prose = Campaign.Prose(s)
    c.prose:SetText(prose)

    local values = { s.kills, s.deaths, s.best, ("%.1f"):format(s.miles), Campaign.Duration(s.played) }
    for i, v in ipairs(c.stats) do v:SetText(values[i]) end
    for i, h in ipairs(Campaign.Highlights(s)) do
        local row = c.high[i]
        row.label:SetText(h[1])
        local text = h[2]
        if i == 1 and s.nemesis then text = text:gsub("^" .. s.nemesis:gsub("%p", "%%%0"), Colored(s.nemesis, s.nemesisClass)) end
        if i == 2 and s.victim then text = text:gsub("^" .. s.victim:gsub("%p", "%%%0"), Colored(s.victim, s.victimClass)) end
        row.value:SetText(text or NONE)
    end

    local list = Entries(camp)
    FauxScrollFrame_Update(c.scroll, #list, DEED_ROWS, 21)
    local offset = FauxScrollFrame_GetOffset(c.scroll)
    local shown = 0
    for i, row in ipairs(c.rows) do
        local item = list[i + offset]
        if item then
            local e = item.e
            row.entry, row.kill = e, item.kill
            row.time:SetText(e.t and date("%H:%M", e.t) or "")
            if item.kill then
                row.icon:SetTexture(TEX.sword)
                row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.icon:SetVertexColor(1, 1, 1)
            else
                row.icon:SetTexture(C.TEX_SKULL)
                row.icon:SetTexCoord(0, 1, 0, 1)
                row.icon:SetVertexColor(0.75, 0.15, 0.1)
            end
            row.text:SetText(DeedText(item))
            row:Show()
            shown = i
        else
            row.entry = nil
            row:Hide()
        end
    end
    c.finis:ClearAllPoints()
    c.finis:SetPoint("TOP", c.R, "TOP", 0, -64 - shown * 21 - 8)
    c.finis:SetText(#list == 0 and (camp.old and "Kills and deaths weren't listed before 3.4." or "No blood spilled yet.")
        or (shown < DEED_ROWS and "here the entries end" or ""))

    if view.page < n then c.earlier:Enable() else c.earlier:Disable() end
    if view.page > 1 then c.later:Enable() else c.later:Disable() end
    if view.preview then c.share:Disable() else c.share:Enable() end
    f.right.number:SetText("\226\128\148 " .. Roman(number * 2) .. " \226\128\148")
    f.left.number:SetText("\226\128\148 " .. Roman(number * 2 - 1) .. " \226\128\148    campaign " .. number .. " of " .. n)
end

---------------------------------------------------------------------------
-- Grudges: the ledger (left), one grudge (right)
---------------------------------------------------------------------------

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
        row.dots = Font(row, QuestFont, GameFontHighlight, FADED)
        row.dots:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
        row.dots:SetPoint("RIGHT", row.tally, "LEFT", -4, 0)
        row.dots:SetWordWrap(false)
        row.dots:SetText((" ."):rep(60))
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
    g.log = {}
    for i = 1, LOG_ROWS do
        local t = Font(E, QuestFontNormalSmall, GameFontNormalSmall, FADED)
        t:SetPoint("TOPLEFT", 32, -288 - (i - 1) * 19)
        t:SetWidth(80)
        local text = Font(E, QuestFont, GameFontHighlight, INK)
        text:SetPoint("TOPLEFT", 116, -286 - (i - 1) * 19)
        text:SetWidth(inner - 84)
        text:SetWordWrap(false)
        g.log[i] = { t = t, text = text }
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
    local f, g = book, book.gr
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
            row.tally:SetText(("|cff2e5a1c%d|r |cff8a6c44\194\183|r |cff7a1f0f%d|r"):format(r.kills or 0, r.deaths or 0))
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
    local log = r.log or {}
    for i, line in ipairs(g.log) do
        local e = log[#log - i + 1]
        if e then
            line.t:SetText(date("%b %d, %H:%M", e.t))
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

---------------------------------------------------------------------------
-- Rendering and opening
---------------------------------------------------------------------------

function Render()
    if not book then return end
    book.title:SetText("Chronicle of " .. (myName or "you"))
    local camp = view.section == "campaigns"
    book.camp.L:SetShown(camp)
    book.camp.R:SetShown(camp)
    book.gr.L:SetShown(not camp)
    book.gr.R:SetShown(not camp)
    for _, t in ipairs(book.tabs) do
        local on = t.key == view.section
        t:SetHeight(on and 32 or 26)
        t.bg:SetColorTexture(on and 0.16 or 0.08, on and 0.09 or 0.06, on and 0.04 or 0.04, 1)
        t.text:SetTextColor(on and 1 or 0.62, on and 0.82 or 0.58, on and 0 or 0.50)
    end
    if camp then RenderCampaign() else RenderGrudges() end
end

local function Popups()
    if not StaticPopupDialogs or StaticPopupDialogs.WARPATH_GRUDGE_NAME then return end
    local function EditBoxOf(self) return self.editBox or self.EditBox end
    StaticPopupDialogs.WARPATH_GRUDGE_NAME = {
        text = "Inscribe a grudge against whom?\n(Name, or Name-Realm)",
        button1 = "Inscribe", button2 = CANCEL or "Cancel",
        hasEditBox = true, maxLetters = 60,
        OnAccept = function(self)
            local name = EditBoxOf(self):GetText():gsub("%s", "")
            if name ~= "" then ns.Dispatch("grudge " .. name) end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local name = self:GetText():gsub("%s", "")
            if name ~= "" then ns.Dispatch("grudge " .. name) end
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs.WARPATH_GRUDGE_FORGIVE = {
        text = "Forgive %s?\nTheir name is struck from your ledger.",
        button1 = "Forgive", button2 = CANCEL or "Cancel",
        OnAccept = function(_, full) if full then Grudge.Forgive(full) end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local function Build()
    book = BuildBook()
    BuildCampaignPages(book)
    BuildGrudgePages(book)
    Popups()
end

local Chronicle = {}

-- section: "campaigns" (default) or "grudges".
function Chronicle.Open(preview, section)
    if S.inInstance and not preview then Print("the chronicle waits until you leave the battleground.") return end
    if not book then Build() end
    view.preview = preview and true or false
    view.section = section or (preview and view.section) or "campaigns"
    view.list = preview and { Campaign.Sample() } or Campaign.List()
    view.page, view.pick = 1, 1
    if #view.list == 0 then view.list = { db.campaign } end
    book.camp.scroll:SetVerticalScroll(0)
    book.gr.scroll:SetVerticalScroll(0)
    Render()
    if not book:IsShown() then UISound("IG_QUEST_LOG_OPEN", 844) end
    book:Show()
end

function Chronicle.Toggle()
    if book and book:IsShown() and not view.preview then book:Hide() else Chronicle.Open() end
end

function Chronicle.Hide() if book then book:Hide() end end

function Chronicle.Refresh()
    if book and book:IsShown() and not view.preview then
        if view.section == "campaigns" then view.list = Campaign.List() end
        Render()
    end
end

-- The campaign on the open page (for /warpath chronicle share).
function Chronicle.Current()
    if book and book:IsShown() and not view.preview and view.section == "campaigns" then return view.list[view.page] end
end

function ns.ChronicleShareMenu(owner)
    if view.preview then Print("these are sample pages; there's nothing real to share.") return end
    local c = view.list[view.page]
    local function To(where, who) return function() Campaign.Share(c, where, who) end end
    local items = {
        { text = "Guild", func = To("guild") },
        { text = "Party / raid", func = To("party") },
        { text = "Say", func = To("say") },
    }
    local target = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
    if target and target ~= myName then
        items[#items + 1] = { text = "Whisper " .. target, func = To("whisper", target) }
    end
    if not ns.Menu(owner, "Share this campaign", items) then Campaign.Share(c, "guild") end
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

ns.Chronicle = Chronicle
