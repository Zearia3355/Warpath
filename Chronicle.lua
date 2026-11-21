-- Warpath: Chronicle
-- The chronicle window: one campaign per page, built only from the game's
-- own textures, fonts and sounds.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local ClassColor, MapName, Print, UISound, Waypoint = ns.ClassColor, ns.MapName, ns.Print, ns.UISound, ns.Waypoint
local Campaign = ns.Campaign

local db, cfg, myName
ns.OnBind(function() db, cfg, myName = ns.db, ns.cfg, ns.myName end)

local W, H = 540, 620
local INK, FADED, RUBRIC = { 0.18, 0.11, 0.04 }, { 0.30, 0.22, 0.12 }, { 0.48, 0.12, 0.06 }
local NONE = "|cff4d3a20\226\128\148|r"  -- an em dash in faded ink, for "nothing yet"
local ROWS = 9
local TEX = {
    border = "Interface\\DialogFrame\\UI-DialogBox-Border",
    header = "Interface\\DialogFrame\\UI-DialogBox-Header",
    page   = "Interface\\QuestFrame\\QuestBG",
    classes = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes",
    sword  = "Interface\\Icons\\INV_Sword_04",
    prev   = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-",
    next   = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-",
    hilite = "Interface\\Buttons\\UI-Common-MouseHilight",
}
local TAG_TEXT = { first = "first blood", grudge = "grudge", avenged = "avenged", streak = "streak" }

local frame
local view = { list = {}, page = 1, preview = false }

local function Font(parent, object, fallback, r, g, b)
    local fs = parent:CreateFontString(nil, "ARTWORK")
    if not (object and pcall(fs.SetFontObject, fs, object)) then fs:SetFontObject(fallback) end
    fs:SetTextColor(r or INK[1], g or INK[2], b or INK[3])
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Rule(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(FADED[1], FADED[2], FADED[3], 0.35)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 28, y)
    t:SetPoint("TOPRIGHT", -28, y)
    return t
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

-- Class colours are made for dark backgrounds; on parchment the light ones
-- (priest white, rogue yellow, mage blue) vanish. Darken each to the same
-- low brightness, keeping its hue, so every class reads as ink.
local function Ink(r, g, b)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    local k = lum > 0.28 and 0.28 / lum or 1
    return r * k, g * k, b * k
end

local function Colored(name, class)
    if not name then return "|cff4d3a20unknown|r" end
    local r, g, b = INK[1], INK[2], INK[3]
    if class then r, g, b = Ink(ClassColor(class)) end
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local function ArrowButton(parent, base)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(32, 32)
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture(TEX.hilite, "ADD")
    return b
end

local function OptionCheck(parent, label, key)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.text2 = Font(parent, QuestFontNormalSmall, GameFontNormalSmall)
    cb.text2:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.text2:SetText(label)
    cb:SetScript("OnClick", function(self) cfg[key] = self:GetChecked() and true or false end)
    cb.key = key
    return cb
end

local Render

local function ShareMenu(owner)
    local c = view.list[view.page]
    if view.preview then Print("this is a preview; there's nothing real to share.") return end
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

local function Build()
    local f = CreateFrame("Frame", "WarpathChronicle", UIParent, "BackdropTemplate")
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ edgeFile = TEX.border, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    tinsert(UISpecialFrames, "WarpathChronicle")
    f:SetScript("OnHide", function() UISound("IG_QUEST_LOG_CLOSE", 845) end)

    local page = f:CreateTexture(nil, "BACKGROUND")
    page:SetTexture(TEX.page)
    page:SetTexCoord(0, 0.5859375, 0, 0.65625)
    page:SetPoint("TOPLEFT", 11, -12)
    page:SetPoint("BOTTOMRIGHT", -12, 11)

    local plate = f:CreateTexture(nil, "ARTWORK")
    plate:SetTexture(TEX.header)
    plate:SetSize(380, 64)
    plate:SetPoint("TOP", 0, 12)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", plate, "TOP", 0, -14)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Headline
    f.headline = Font(f, QuestTitleFont, GameFontNormalLarge)
    f.headline:SetPoint("TOPLEFT", 30, -44)
    f.headline:SetWidth(W - 60)
    f.when = Font(f, QuestFont, GameFontHighlight, FADED[1], FADED[2], FADED[3])
    f.when:SetPoint("TOPLEFT", f.headline, "BOTTOMLEFT", 0, -4)
    f.when:SetWidth(W - 60)
    Rule(f, -98)

    -- Five stat boxes
    f.stats = {}
    local labels = { "Kills", "Deaths", "Best streak", "Miles", "Played" }
    local bw = math.floor((W - 60 - 4 * 8) / 5)
    for i = 1, 5 do
        local box = CreateFrame("Frame", nil, f)
        box:SetSize(bw, 50)
        box:SetPoint("TOPLEFT", 30 + (i - 1) * (bw + 8), -106)
        local bg = box:CreateTexture(nil, "BORDER")
        bg:SetAllPoints()
        bg:SetColorTexture(0.35, 0.22, 0.08, 0.10)
        box.value = Font(box, QuestTitleFont, GameFontNormalLarge)
        box.value:SetPoint("TOP", 0, -6)
        box.value:SetJustifyH("CENTER")
        box.label = Font(box, QuestFontNormalSmall, GameFontNormalSmall, FADED[1], FADED[2], FADED[3])
        box.label:SetPoint("BOTTOM", 0, 6)
        box.label:SetJustifyH("CENTER")
        box.label:SetText(labels[i])
        f.stats[i] = box
    end

    -- Six highlights, two columns
    f.highlights = {}
    local colW = math.floor((W - 60 - 16) / 2)
    for i = 1, 6 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = 30 + col * (colW + 16), -170 - row * 40
        local lab = Font(f, QuestFontNormalSmall, GameFontNormalSmall, RUBRIC[1], RUBRIC[2], RUBRIC[3])
        lab:SetPoint("TOPLEFT", x, y)
        local val = Font(f, QuestFont, GameFontHighlight)
        val:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -3)
        val:SetWidth(colW)
        val:SetWordWrap(false)
        f.highlights[i] = { label = lab, value = val }
    end
    Rule(f, -292)

    -- Kills and deaths, newest first
    f.listTitle = Font(f, QuestFontNormalSmall, GameFontNormalSmall, RUBRIC[1], RUBRIC[2], RUBRIC[3])
    f.listTitle:SetPoint("TOPLEFT", 30, -300)
    local scroll = CreateFrame("ScrollFrame", "WarpathChronicleScroll", f, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 26, -318)
    scroll:SetSize(W - 80, ROWS * 20)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 20, Render)
    end)
    f.scroll = scroll
    f.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, f)
        r:SetSize(W - 84, 20)
        r:SetPoint("TOPLEFT", 28, -318 - (i - 1) * 20)
        r:SetHighlightTexture(TEX.hilite, "ADD")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", 2, 0)
        r.class = r:CreateTexture(nil, "ARTWORK")
        r.class:SetSize(16, 16)
        r.class:SetPoint("LEFT", r.icon, "RIGHT", 4, 0)
        r.name = Font(r, QuestFont, GameFontHighlight)
        r.name:SetPoint("LEFT", r.class, "RIGHT", 5, 0)
        r.name:SetWidth(150)
        r.name:SetWordWrap(false)
        r.where = Font(r, QuestFontNormalSmall, GameFontNormalSmall, FADED[1], FADED[2], FADED[3])
        r.where:SetPoint("LEFT", r.name, "RIGHT", 4, 0)
        r.where:SetWidth(150)
        r.where:SetWordWrap(false)
        r.time = Font(r, QuestFontNormalSmall, GameFontNormalSmall, FADED[1], FADED[2], FADED[3])
        r.time:SetPoint("LEFT", r.where, "RIGHT", 4, 0)
        r.time:SetWidth(46)
        r.tag = Font(r, QuestFontNormalSmall, GameFontNormalSmall, RUBRIC[1], RUBRIC[2], RUBRIC[3])
        r.tag:SetPoint("LEFT", r.time, "RIGHT", 4, 0)
        r.tag:SetWidth(80)
        r:SetScript("OnClick", function(self)
            local e = self.entry
            if e and e.z and e.x and not view.preview then
                Waypoint(e.z, e.x, e.y, self.kill and "a kill from your chronicle" or "a death from your chronicle")
            end
        end)
        r:SetScript("OnEnter", function(self)
            if not self.entry or view.preview then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Click to set a waypoint here", 0.1, 1, 0.1)
            if self.entry.shot then GameTooltip:AddLine(("Screenshot #%d"):format(self.entry.shot), 1, 1, 1) end
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", GameTooltip_Hide)
        f.rows[i] = r
    end
    f.empty = Font(f, QuestFont, GameFontHighlight, FADED[1], FADED[2], FADED[3])
    f.empty:SetPoint("TOPLEFT", 34, -326)
    Rule(f, -506)

    -- Options and controls
    f.optLogin = OptionCheck(f, "Headline in chat when I log in", "chronLogin")
    f.optLogin:SetPoint("TOPLEFT", 26, -514)
    f.optOpen = OptionCheck(f, "Open the chronicle when I log in", "chronOpen")
    f.optOpen:SetPoint("TOPLEFT", f.optLogin, "BOTTOMLEFT", 0, 2)

    f.share = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.share:SetSize(90, 24)
    f.share:SetPoint("TOPRIGHT", -28, -516)
    f.share:SetText("Share")
    f.share:SetScript("OnClick", function(self) ShareMenu(self) end)

    f.prev = ArrowButton(f, TEX.prev)
    f.prev:SetPoint("BOTTOMLEFT", 24, 18)
    f.next = ArrowButton(f, TEX.next)
    f.next:SetPoint("BOTTOMRIGHT", -24, 18)
    f.pageText = Font(f, QuestFontNormalSmall, GameFontNormalSmall, FADED[1], FADED[2], FADED[3])
    f.pageText:SetPoint("BOTTOM", 0, 28)
    f.pageText:SetJustifyH("CENTER")
    -- Previous goes back in time (older campaigns), next towards now.
    f.prev:SetScript("OnClick", function()
        if view.page < #view.list then view.page = view.page + 1 UISound("IG_ABILITY_PAGE_TURN", 836) Render() end
    end)
    f.next:SetScript("OnClick", function()
        if view.page > 1 then view.page = view.page - 1 UISound("IG_ABILITY_PAGE_TURN", 836) Render() end
    end)
    return f
end

---------------------------------------------------------------------------
-- Filling a page
---------------------------------------------------------------------------

local function Entries(c)
    local list = {}
    for _, k in ipairs(c.kl or {}) do list[#list + 1] = { e = k, kill = true } end
    for _, d in ipairs(c.dl or {}) do list[#list + 1] = { e = d } end
    table.sort(list, function(a, b) return (a.e.t or 0) > (b.e.t or 0) end)
    return list
end

function Render()
    local f, c = frame, view.list[view.page]
    if not f or not c then return end
    local s = Campaign.Summary(c)
    f.title:SetText("Chronicle of " .. (myName or "you"))
    f.headline:SetText(s.headline)
    local status = view.preview and "Preview with sample data"
        or Campaign.IsOpen(c) and "in progress"
        or (c.old and "before 3.4: totals only")
        or (c.partial and "began before 3.4") or nil
    f.when:SetText(date("%a %b %d, %H:%M", c.start) .. "  \194\183  " .. (s.zones == 1 and "1 zone" or (s.zones .. " zones"))
        .. "  \194\183  " .. s.sightings .. " enemies sighted" .. (status and ("  \194\183  " .. status) or ""))

    local values = { s.kills, s.deaths, s.best, ("%.1f"):format(s.miles), Campaign.Duration(s.played) }
    for i, box in ipairs(f.stats) do box.value:SetText(values[i]) end

    for i, h in ipairs(Campaign.Highlights(s)) do
        local row = f.highlights[i]
        row.label:SetText(h[1])
        local text = h[2]
        if i == 1 and s.nemesis then text = text:gsub("^" .. s.nemesis:gsub("%p", "%%%0"), Colored(s.nemesis, s.nemesisClass)) end
        if i == 2 and s.victim then text = text:gsub("^" .. s.victim:gsub("%p", "%%%0"), Colored(s.victim, s.victimClass)) end
        row.value:SetText(text or NONE)
    end

    local list = Entries(c)
    f.listTitle:SetText(("KILLS AND DEATHS  (%d)"):format(#list))
    FauxScrollFrame_Update(f.scroll, #list, ROWS, 20)
    local offset = FauxScrollFrame_GetOffset(f.scroll)
    for i, r in ipairs(f.rows) do
        local item = list[i + offset]
        if item then
            local e = item.e
            r.entry, r.kill = e, item.kill
            if item.kill then
                r.icon:SetTexture(TEX.sword)
                r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                r.icon:SetVertexColor(1, 1, 1)
            else
                r.icon:SetTexture(C.TEX_SKULL)
                r.icon:SetTexCoord(0, 1, 0, 1)
                r.icon:SetVertexColor(0.8, 0.15, 0.1)
            end
            ClassIcon(r.class, e.c)
            r.name:SetText(item.kill and Colored(e.n or "Enemy player", e.c)
                or ("Fell" .. (e.n and (" to " .. Colored(e.n, e.c)) or "")))
            r.where:SetText(e.z and MapName(e.z) or "")
            r.time:SetText(e.t and date("%H:%M", e.t) or "")
            local tag = item.kill and e.tag and TAG_TEXT[e.tag]
            if tag == "streak" and e.st then tag = "streak of " .. e.st end
            r.tag:SetText(tag or "")
            r:Show()
        else
            r.entry = nil
            r:Hide()
        end
    end
    f.empty:SetText(#list == 0 and (c.old and "Kills and deaths weren't listed before 3.4." or "No blood spilled yet.") or "")

    f.optLogin:SetChecked(cfg.chronLogin)
    f.optOpen:SetChecked(cfg.chronOpen)
    f.pageText:SetText(view.preview and "Preview" or ("Campaign %d of %d"):format(#view.list - view.page + 1, #view.list))
    if view.page < #view.list then f.prev:Enable() else f.prev:Disable() end
    if view.page > 1 then f.next:Enable() else f.next:Disable() end
    if view.preview then f.share:Disable() else f.share:Enable() end
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------

local Chronicle = {}

function Chronicle.Open(preview)
    if S.inInstance and not preview then Print("the chronicle waits until you leave the battleground.") return end
    if not frame then frame = Build() end
    view.preview = preview and true or false
    view.list = preview and { Campaign.Sample() } or Campaign.List()
    view.page = 1
    if #view.list == 0 then Print("no campaign recorded yet.") return end
    frame.scroll:SetVerticalScroll(0)
    Render()
    if not frame:IsShown() then UISound("IG_QUEST_LOG_OPEN", 844) end
    frame:Show()
end

function Chronicle.Toggle()
    if frame and frame:IsShown() and not view.preview then frame:Hide() else Chronicle.Open() end
end

function Chronicle.Hide() if frame then frame:Hide() end end

-- The campaign on the open page (for /warpath chronicle share).
function Chronicle.Current()
    if frame and frame:IsShown() and not view.preview then return view.list[view.page] end
end

ns.Chronicle = Chronicle
