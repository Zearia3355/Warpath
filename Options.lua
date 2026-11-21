-- Warpath: Options
-- The options window, with tabs: General, Map, Screenshots, Chronicle & zones.
-- Opens once after each install or update; /warpath options any time.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Print, VERSION, UpdateHUD = ns.Print, ns.VERSION, ns.UpdateHUD

local db, gdb, cfg, faction
ns.OnBind(function() db, gdb, cfg, faction = ns.db, ns.gdb, ns.cfg, ns.faction end)

local ShowSetup, MaybeShowSetup, setup
do
local NEW_IN = {
    "A button on the world map (crossed swords, top right): left-click hides",
    "    Warpath, right-click picks layers.",
    "Roads gild gradually from silver to gold, and well-worn gold shines.",
    "Smaller footsteps, vivid when fresh; the solid line covers 5 minutes and fades.",
    "Corpse runs and flights: their own layer, distinct looks, 24 hours.",
    "Flight routes you keep taking are remembered on the map.",
    "The chronicle: /warpath chronicle opens your last 30 campaigns. Share one",
    "    with the Share button. A /reload no longer splits a night in two.",
    "Your record in a zone when you enter it, in chat and under the zone name.",
    "Simpler commands: /warpath help (everything: /warpath help all).",
}
local TABS = { "General", "Map", "Screenshots", "Chronicle & zones" }
local HOURS = { { 1, "1 hour" }, { 6, "6 hours" }, { 24, "24 hours" }, { 48, "48 hours" } }

local function MakeCheck(parent, label, hint)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb.label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    if hint then
        cb.hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        cb.hint:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -2)
        cb.hint:SetWidth(470)
        cb.hint:SetJustifyH("LEFT")
        cb.hint:SetText(hint)
    end
    return cb
end

local function MakeRadios(parent, label, options)
    local group = { buttons = {}, value = nil }
    group.label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    group.label:SetText(label)
    local prev
    for i, opt in ipairs(options) do
        local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        rb.value = opt[1]
        rb.text2 = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        rb.text2:SetPoint("LEFT", rb, "RIGHT", 3, 0)
        rb.text2:SetText(opt[2])
        if prev then
            rb:SetPoint("LEFT", prev.text2, "RIGHT", 14, 0)
        else
            rb:SetPoint("LEFT", group.label, "LEFT", 130, 0)
        end
        rb:SetScript("OnClick", function() group:Set(rb.value) end)
        group.buttons[i] = rb
        prev = rb
    end
    function group:Set(v)
        self.value = v
        for _, b in ipairs(self.buttons) do b:SetChecked(b.value == v) end
    end
    return group
end

local function SetupLoad(s, c)
    s.banners:SetChecked(not c.quiet)
    s.sound:SetChecked(c.sound)
    s.hud:SetChecked(c.hudShown)
    s.share:SetChecked(c.share)
    s.shown:SetChecked(c.shown)
    for key, cb in pairs(s.layers) do cb:SetChecked(c.layers[key]) end
    s.shimmer:SetChecked(c.shimmer)
    s.runHours:Set(c.runHours)
    s.flightHours:Set(c.flightHours)
    s.shotOn:SetChecked(c.shot.on)
    s.which:Set(c.shot.mode)
    s.caption:Set(c.shot.card)
    s.zoneChat:SetChecked(c.zoneChat)
    s.zoneText:SetChecked(c.zoneText)
    s.chronLogin:SetChecked(c.chronLogin)
    s.chronOpen:SetChecked(c.chronOpen)
end

local function On(cb) return cb:GetChecked() and true or false end

local function SetupSave(s)
    cfg.quiet = not s.banners:GetChecked()
    cfg.sound = On(s.sound)
    cfg.hudShown = On(s.hud)
    cfg.share = On(s.share)
    cfg.shown = On(s.shown)
    for key, cb in pairs(s.layers) do cfg.layers[key] = On(cb) end
    cfg.shimmer = On(s.shimmer)
    cfg.runHours = s.runHours.value or 24
    cfg.flightHours = s.flightHours.value or 24
    cfg.shot.on = On(s.shotOn)
    cfg.shot.mode = s.which.value or "all"
    cfg.shot.card = s.caption.value or "text"
    cfg.zoneChat = On(s.zoneChat)
    cfg.zoneText = On(s.zoneText)
    cfg.chronLogin = On(s.chronLogin)
    cfg.chronOpen = On(s.chronOpen)
    if S.hud then S.hud:SetShown(cfg.hudShown and not S.inInstance) end
    UpdateHUD()
    S.dirty = true
    ns.Redraw()
end

local function DefaultsView()
    local view = { layers = {}, shot = {} }
    for _, name in ipairs(C.LAYERS) do view.layers[name] = true end
    for k, v in pairs(C.SHOT_DEFAULTS) do view.shot[k] = v end
    for k, v in pairs(C.CFG_DEFAULTS) do view[k] = v end
    return view
end

-- A panel's controls are placed top to bottom; y counts down from its top.
local function Layout(panel)
    local L = { y = 0 }
    function L.Heading(text)
        local h = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", 0, -L.y)
        h:SetText(text)
        L.y = L.y + 20
    end
    function L.Place(widget, x, dy)
        widget:SetPoint("TOPLEFT", x or 0, -L.y)
        L.y = L.y + (dy or 26)
    end
    function L.Radios(group, dy)
        group.label:SetPoint("TOPLEFT", 28, -(L.y + 4))
        L.y = L.y + (dy or 22)
    end
    return L
end

-- Tabs are drawn by hand (gold text and underline when selected) rather
-- than from a Blizzard tab template: the template names differ between
-- client versions, and a missing one left plain red buttons.
local function SelectTab(s, id)
    s.tab = id
    for i, panel in ipairs(s.panels) do panel:SetShown(i == id) end
    for i, t in ipairs(s.tabs) do
        local on = i == id
        t.text:SetTextColor(on and 1 or 0.72, on and 0.82 or 0.72, on and 0 or 0.72)
        t.line:SetShown(on)
        t.bg:SetColorTexture(1, 0.82, 0, on and 0.10 or 0.03)
    end
end

local function MakeTabs(s)
    s.tabBar = CreateFrame("Frame", nil, s)
    s.tabBar:SetHeight(26)
    local rule = s.tabBar:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.62, 0.50, 0.28, 0.6)
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT")
    rule:SetPoint("BOTTOMRIGHT")
    s.tabs = {}
    local x = 0
    for i, name in ipairs(TABS) do
        local t = CreateFrame("Button", nil, s.tabBar)
        t.text = t:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t.text:SetPoint("CENTER", 0, 1)
        t.text:SetText(name)
        local w = math.max(70, math.floor((t.text:GetStringWidth() or 60) + 28))
        t:SetSize(w, 26)
        t:SetPoint("BOTTOMLEFT", x, 1)
        x = x + w + 4
        t.bg = t:CreateTexture(nil, "BACKGROUND")
        t.bg:SetAllPoints()
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetColorTexture(1, 0.82, 0, 1)
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT", 0, -1)
        t.line:SetPoint("BOTTOMRIGHT", 0, -1)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.82, 0, 0.08)
        t:SetScript("OnClick", function()
            if s.tab ~= i then ns.UISound("IG_CHARACTER_INFO_TAB", 841) end
            SelectTab(s, i)
        end)
        s.tabs[i] = t
    end
end

local function BuildGeneral(s, panel)
    local L = Layout(panel)
    L.Heading("ALERTS")
    s.banners = MakeCheck(panel, "Raid-warning banners and sounds", "Off: alerts become chat lines instead.")
    L.Place(s.banners, 0, 42)
    s.sound = MakeCheck(panel, "Sounds")
    L.Place(s.sound, 0, 34)
    L.Heading("WAR TABLE")
    s.hud = MakeCheck(panel, "Show the war table panel", "Kills, deaths, streak and this zone at a glance. Drag to move.")
    L.Place(s.hud, 0, 50)
    L.Heading("GUILD AND PARTY")
    s.share = MakeCheck(panel, "Share enemy sightings, my kills and my PvP deaths",
        "Sends map positions only, never names or your trail. Each player turns it on.")
    L.Place(s.share, 0, 46)
end

local function BuildMap(s, panel)
    local L = Layout(panel)
    s.shown = MakeCheck(panel, "Show Warpath on the world map",
        "Same as the crossed-swords button in the map's top-right corner. Recording never stops.")
    L.Place(s.shown, 0, 46)
    L.Heading("LAYERS")
    s.layers = {}
    for i, key in ipairs(C.LAYERS) do
        local cb = MakeCheck(panel, C.LAYER_LABELS[key])
        cb:SetPoint("TOPLEFT", (i - 1) % 2 == 0 and 0 or 250, -(L.y + math.floor((i - 1) / 2) * 26))
        s.layers[key] = cb
    end
    L.y = L.y + math.ceil(#C.LAYERS / 2) * 26 + 8
    s.shimmer = MakeCheck(panel, "Shimmer on well-worn gold roads")
    L.Place(s.shimmer, 0, 34)
    L.Heading("HOW LONG RUNS STAY ON THE MAP")
    s.runHours = MakeRadios(panel, "Corpse runs", HOURS)
    L.Radios(s.runHours)
    s.flightHours = MakeRadios(panel, "Today's flights", HOURS)
    L.Radios(s.flightHours)
end

local function BuildShots(s, panel)
    local L = Layout(panel)
    L.Heading("KILL SCREENSHOTS")
    s.shotOn = MakeCheck(panel, "Take a screenshot when I get an honorable kill")
    L.Place(s.shotOn)
    s.which = MakeRadios(panel, "Which kills", { { "all", "Every kill" }, { "notable", "Notable only" } })
    L.Radios(s.which)
    s.caption = MakeRadios(panel, "Caption", { { "text", "Floating text" }, { "strip", "Caption strip" }, { "none", "None" } })
    L.Radios(s.caption, 30)
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 0, -L.y)
    note:SetWidth(480)
    note:SetJustifyH("LEFT")
    note:SetText("Notable: first kill of a player, grudges, avenged deaths, streaks of 3, 5 and every 10, "
        .. "and anyone you've killed 5+ times. /warpath shot test takes a test picture.")
end

local function BuildChronicle(s, panel)
    local L = Layout(panel)
    L.Heading("ENTERING A ZONE")
    s.zoneChat = MakeCheck(panel, "Zone stats in chat", "Kills, deaths, miles, sightings, avenged, best streak, rank.")
    L.Place(s.zoneChat, 0, 42)
    s.zoneText = MakeCheck(panel, "Zone stats under the zone name", "A short line beneath the big zone name.")
    L.Place(s.zoneText, 0, 48)
    L.Heading("CHRONICLE")
    s.chronLogin = MakeCheck(panel, "Show the last campaign's headline in chat when I log in")
    L.Place(s.chronLogin)
    s.chronOpen = MakeCheck(panel, "Open the chronicle window when I log in",
        "Both only after a new campaign starts (2+ hours away) and the last one had fighting.")
    L.Place(s.chronOpen, 0, 50)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(150, 24)
    open:SetPoint("TOPLEFT", 0, -L.y)
    open:SetText("Open the chronicle")
    open:SetScript("OnClick", function() ns.Chronicle.Open() end)
end

local function BuildSetup()
    local s = CreateFrame("Frame", "WarpathSetup", UIParent, "BackdropTemplate")
    local newH = 26 + #NEW_IN * 15
    s.newH = newH
    s:SetSize(560, 430)
    s:SetPoint("TOP", 0, -90)
    s:SetFrameStrata("DIALOG")
    s:SetToplevel(true)
    s:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    -- a solid layer under the dialog texture, so the world doesn't show through
    local shade = s:CreateTexture(nil, "BACKGROUND", nil, -7)
    shade:SetColorTexture(0, 0, 0, 0.8)
    shade:SetPoint("TOPLEFT", 11, -12)
    shade:SetPoint("BOTTOMRIGHT", -12, 11)
    s:EnableMouse(true)
    s:SetMovable(true)
    s:SetClampedToScreen(true)
    s:RegisterForDrag("LeftButton")
    s:SetScript("OnDragStart", s.StartMoving)
    s:SetScript("OnDragStop", s.StopMovingOrSizing)
    -- Only "To war" or the close button count as seen. Escape, or the UI
    -- closing every window, shows it again next login.
    s.MarkSeen = function()
        gdb.seenVersion = VERSION
        gdb.installed = gdb.installed or VERSION
    end
    tinsert(UISpecialFrames, "WarpathSetup")

    local crest = s:CreateTexture(nil, "ARTWORK")
    crest:SetTexture(faction.crest)
    crest:SetTexCoord(0, 0.62, 0, 0.62)
    crest:SetSize(44, 44)
    crest:SetPoint("TOPLEFT", 22, -20)
    s.title = s:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    s.title:SetPoint("TOPLEFT", crest, "TOPRIGHT", 10, -2)
    s.sub = s:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    s.sub:SetPoint("TOPLEFT", s.title, "BOTTOMLEFT", 0, -4)

    local close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() s.MarkSeen() s:Hide() end)

    -- "New in" box (updates only)
    s.newBox = CreateFrame("Frame", nil, s, "BackdropTemplate")
    s.newBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    s.newBox:SetBackdropColor(0.14, 0.11, 0.08, 0.9)
    s.newBox:SetBackdropBorderColor(0.55, 0.45, 0.28, 0.9)
    s.newBox:SetPoint("TOPLEFT", 22, -76)
    s.newBox:SetPoint("TOPRIGHT", -22, -76)
    s.newBox:SetHeight(newH)
    local nh = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nh:SetPoint("TOPLEFT", 10, -8)
    nh:SetText("NEW IN 3.4")
    local prevLine = nh
    for _, line in ipairs(NEW_IN) do
        local fs = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", prevLine, "BOTTOMLEFT", 0, -3)
        fs:SetText(line)
        prevLine = fs
    end
    s.welcome = s:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    s.welcome:SetPoint("TOPLEFT", 22, -78)
    s.welcome:SetWidth(516)
    s.welcome:SetJustifyH("LEFT")
    s.welcome:SetText("Warpath draws your open-world PvP history on the world map. Pick how you want it; everything can be changed later.")

    s.body = CreateFrame("Frame", nil, s)
    s.panels = {}
    for i = 1, #TABS do
        local panel = CreateFrame("Frame", nil, s.body)
        panel:SetAllPoints()
        s.panels[i] = panel
    end
    BuildGeneral(s, s.panels[1])
    BuildMap(s, s.panels[2])
    BuildShots(s, s.panels[3])
    BuildChronicle(s, s.panels[4])
    MakeTabs(s)

    local foot = s:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    foot:SetPoint("BOTTOMLEFT", 24, 28)
    foot:SetWidth(270)
    foot:SetJustifyH("LEFT")
    foot:SetText("Type /warpath help for commands.")

    local go = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    go:SetSize(110, 26)
    go:SetPoint("BOTTOMRIGHT", -22, 20)
    go:SetText("To war")
    go:SetScript("OnClick", function()
        SetupSave(s)
        s.MarkSeen()
        Print("settings saved. /warpath options to change them.")
        s:Hide()
    end)
    local def = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    def:SetSize(100, 26)
    def:SetPoint("RIGHT", go, "LEFT", -8, 0)
    def:SetText("Defaults")
    def:SetScript("OnClick", function() SetupLoad(s, DefaultsView()) end)
    return s
end

-- Title, then the "new in" box (updates) or a welcome line (first install),
-- then the tabs, then the tab body, then the buttons.
local BODY_H = 285
local function Arrange(s, showNew, showWelcome)
    local tabTop = 78
    if showNew then tabTop = tabTop + s.newH + 10
    elseif showWelcome then tabTop = tabTop + 40 end
    s.tabBar:ClearAllPoints()
    s.tabBar:SetPoint("TOPLEFT", 22, -tabTop)
    s.tabBar:SetPoint("TOPRIGHT", -22, -tabTop)
    local bodyTop = tabTop + 26 + 14
    s:SetHeight(bodyTop + BODY_H + 56)
    s.body:ClearAllPoints()
    s.body:SetPoint("TOPLEFT", 22, -bodyTop)
    s.body:SetPoint("BOTTOMRIGHT", -22, 56)
end

function ShowSetup(isUpdate, tab)
    if not setup then setup = BuildSetup() end
    local s = setup
    if isUpdate then
        s.title:SetText("Warpath updated to " .. VERSION)
        s.sub:SetText("Your current settings are already filled in.")
        s.newBox:Show()
        s.welcome:Hide()
    else
        s.title:SetText(gdb.installed and "Warpath options" or "Welcome to Warpath")
        s.sub:SetText(gdb.installed and ("Version " .. VERSION .. ". Settings are shared by all your characters.")
            or "These are the defaults. Change anything you like.")
        s.newBox:Hide()
        s.welcome:SetShown(not gdb.installed)
    end
    Arrange(s, isUpdate, not isUpdate and not gdb.installed)
    SetupLoad(s, cfg)
    SelectTab(s, tab or s.tab or 1)
    s:Show()
end

-- "3.4" from "3.4.1": the window opens by itself for new features, not fix releases.
local function Minor(v) return type(v) == "string" and v:match("^(%d+%.%d+)") or nil end

-- Once per account per feature release (3.4, 3.5...), never in combat.
function MaybeShowSetup()
    if gdb.seenVersion == VERSION then return end
    if gdb.seenVersion and Minor(gdb.seenVersion) == Minor(VERSION) then return end
    if S.inInstance then S.setupWaiting = true return end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        S.setupWaiting = true
        return
    end
    S.setupWaiting = false
    local ok, err = pcall(ShowSetup, gdb.installed and true or false, 1)
    if not ok then
        Print("the options window failed to open: " .. tostring(err))
        Print("please send that line to whoever gave you Warpath. Settings are still at their defaults.")
        gdb.seenVersion = VERSION -- don't fail again on every login
    end
end

end

-- Entering a battleground: put the window away until you leave.
function ns.HideSetup()
    if setup and setup:IsShown() then setup:Hide() S.setupWaiting = true end
end

function ns.SetupShown() return setup and setup:IsShown() end

ns.MaybeShowSetup = MaybeShowSetup
ns.ShowSetup = ShowSetup
