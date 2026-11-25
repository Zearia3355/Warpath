-- Warpath: Options
-- The options window, with tabs: General, Map, Screenshots, Chronicle & zones, Grudges.
-- Opens once after each install or update; /warpath setup any time.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Print, VERSION, UpdateHUD = ns.Print, ns.VERSION, ns.UpdateHUD

local db, gdb, cfg, faction
ns.OnBind(function() db, gdb, cfg, faction = ns.db, ns.gdb, ns.cfg, ns.faction end)

local ShowSetup, MaybeShowSetup, setup
do
-- Every release gets an entry (Joe, 2026-11-24), newest last; the window
-- opens after each update and shows every entry newer than what this
-- account last saw, at most NEW_MAX lines. One line per change; the box
-- wraps them, with a bullet and a hanging indent.
local NEW_MAX = 8
local NEW_IN = {
  { "3.8.0", {
    "Roads rebuilt: one road for each way you really travel, raised like gold trim. A road turns from silver to gold as it becomes a habit, and your most-worn roads carry a streak of your faction's colour. They only ever fade, never jump.",
    "Today's trail: where you lingered (questing, a town) becomes an outlined area; hover it for when and how long. Between areas, a solid line turns to dashes with arrows showing which way you went.",
    "Flight paths: the routes you fly most, on two or more days, show as blue dashes.",
    "Your map settings were reset for this release: every layer is on and today's trail stays 12 hours. Change them on the Map tab.",
  } },
  { "3.8.1", {
    "When a guildmate runs a newer Warpath, you're told in chat once, so you know to update (both of you need guild sharing on).",
    "/warpath trail clear clears today's trail and lingering areas (as /warpath clear trail does).",
    "This window now opens after every update, small ones included.",
  } },
}

local Older = ns.VersionOlder

-- The entries this account hasn't seen: { version, line } pairs, oldest
-- first, the newest NEW_MAX of them.
local function Unseen(seen)
    local out = {}
    for _, rel in ipairs(NEW_IN) do
        if not seen or Older(seen, rel[1]) then
            for _, line in ipairs(rel[2]) do out[#out + 1] = { rel[1], line } end
        end
    end
    while #out > NEW_MAX do table.remove(out, 1) end
    return out
end
ns.NewIn = { Older = Older, Unseen = Unseen } -- for tests
local TABS = { "General", "Map", "Screenshots", "Chronicle & zones", "Grudges" }
local HOURS = { { 1, "1h" }, { 6, "6h" }, { 24, "24h" }, { 48, "48h" } }
local TRAIL = {}
for i, m in ipairs(C.TRAIL_MIN_CHOICES) do TRAIL[i] = { m, m < 60 and (m .. "m") or ((m / 60) .. "h") } end

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

local function MakeRadios(parent, label, options, labelWidth)
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
            rb:SetPoint("LEFT", group.label, "LEFT", labelWidth or 130, 0)
        end
        rb:SetScript("OnClick", function() group:Set(rb.value) end)
        group.buttons[i] = rb
        prev = rb
    end
    function group:Set(v)
        self.value = v
        for _, b in ipairs(self.buttons) do b:SetChecked(b.value == v) end
        if self.onChange then self.onChange(v) end
    end
    function group:SetEnabled(on)
        for _, b in ipairs(self.buttons) do
            if on then b:Enable() else b:Disable() end
            b.text2:SetTextColor(on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5)
        end
        self.label:SetTextColor(on and 1 or 0.5, on and 0.82 or 0.5, on and 0 or 0.5)
    end
    return group
end

local function SetupLoad(s, c)
    s.banners:SetChecked(not c.quiet)
    s.sound:SetChecked(c.sound)
    s.overlay:SetChecked(c.overlay)
    s.selfChat:SetChecked(c.selfChat)
    s.overlaySize:Set(c.overlaySize)
    s.groundScreen:SetChecked(c.groundScreen)
    s.groundChat:SetChecked(c.groundChat)
    s.groundAfter:Set(c.groundAfter)
    s.hud:SetChecked(c.hudShown)
    s.minimap:SetChecked(not (c.minimap and c.minimap.hide))
    s.share:SetChecked(c.share)
    s.shareHistory:SetChecked(c.shareHistory)
    s.shown:SetChecked(c.shown)
    s.showAll:SetChecked(c == cfg and S.showAll or false)
    for key, cb in pairs(s.layers) do cb:SetChecked(c.layers[key]) end
    s.guildHaze:SetChecked(c.guildHaze)
    s.iconScale.Set(c.iconScale or 100)
    s.shimmer:SetChecked(c.shimmer)
    s.trailMin:Set(c.trailMin)
    s.runHours:Set(c.runHours)
    s.shotOn:SetChecked(c.shot.on)
    s.which:Set(c.shot.mode)
    s.caption:Set(c.shot.card)
    s.zoneChat:SetChecked(c.zoneChat)
    s.zoneText:SetChecked(c.zoneText)
    s.chronLogin:SetChecked(c.chronLogin)
    s.chronOpen:SetChecked(c.chronOpen)
    local g = c.grudge
    s.gAlert:SetChecked(g.alert)
    s.gAgain:Set(g.again)
    s.gMap:SetChecked(g.map)
    s.gPlates:SetChecked(g.plates)
    s.gAfter:Set(g.after)
    s.gAuto:Set(g.auto)
end

local function On(cb) return cb:GetChecked() and true or false end

local function SetupSave(s)
    cfg.quiet = not s.banners:GetChecked()
    cfg.sound = On(s.sound)
    cfg.overlay = On(s.overlay)
    cfg.selfChat = On(s.selfChat)
    cfg.overlaySize = s.overlaySize.value or "medium"
    cfg.groundScreen, cfg.groundChat = On(s.groundScreen), On(s.groundChat)
    cfg.groundAfter = s.groundAfter.value or 2
    cfg.fieldAlert = cfg.groundScreen or cfg.groundChat
    if ns.Ground then ns.Ground.Forget() end
    cfg.hudShown = On(s.hud)
    ns.Minimap.SetShown(On(s.minimap))
    cfg.share = On(s.share)
    cfg.shareHistory = On(s.shareHistory)
    cfg.shown = On(s.shown)
    if S.showAll ~= On(s.showAll) then S.showAll = On(s.showAll) S.dirty = true end
    for key, cb in pairs(s.layers) do cfg.layers[key] = On(cb) end
    cfg.guildHaze = On(s.guildHaze)
    cfg.iconScale = s.iconScale.value or 100
    cfg.shimmer = On(s.shimmer)
    cfg.trailMin = s.trailMin.value or cfg.trailMin or 60
    cfg.runHours = s.runHours.value or 24
    cfg.shot.on = On(s.shotOn)
    cfg.shot.mode = s.which.value or "all"
    cfg.shot.card = s.caption.value or "text"
    cfg.zoneChat = On(s.zoneChat)
    cfg.zoneText = On(s.zoneText)
    cfg.chronLogin = On(s.chronLogin)
    cfg.chronOpen = On(s.chronOpen)
    local g = cfg.grudge
    g.alert, g.map, g.plates = On(s.gAlert), On(s.gMap), On(s.gPlates)
    g.again, g.auto, g.after = s.gAgain.value or 1, s.gAuto.value or "off", s.gAfter.value or 3
    ns.Grudge.RefreshMarks()
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
    view.minimap = { hide = false }
    view.grudge = {}
    for k, v in pairs(C.GRUDGE_DEFAULTS) do view.grudge[k] = v end
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
    s.banners = MakeCheck(panel, "Raid-warning banners and sounds")
    s.sound = MakeCheck(panel, "Sounds")
    s.banners:SetPoint("TOPLEFT", 0, -L.y)
    s.sound:SetPoint("TOPLEFT", 250, -L.y)
    L.y = L.y + 26
    s.overlay = MakeCheck(panel, "Big text on screen")
    s.selfChat = MakeCheck(panel, "My kills and deaths in chat")
    s.overlay:SetPoint("TOPLEFT", 0, -L.y)
    s.selfChat:SetPoint("TOPLEFT", 250, -L.y)
    L.y = L.y + 24
    s.overlaySize = MakeRadios(panel, "Big text size", { { "small", "Small" }, { "medium", "Medium" }, { "large", "Large" } })
    L.Radios(s.overlaySize, 26)
    s.groundScreen = MakeCheck(panel, "Ground warnings on screen")
    s.groundChat = MakeCheck(panel, "Ground warnings in chat")
    s.groundScreen:SetPoint("TOPLEFT", 0, -L.y)
    s.groundChat:SetPoint("TOPLEFT", 250, -L.y)
    L.y = L.y + 24
    s.groundAfter = MakeRadios(panel, "Warn after", { { 1, "1 death" }, { 2, "2 deaths" }, { 3, "3 deaths" } })
    L.Radios(s.groundAfter, 28)
    L.Heading("WAR TABLE AND MINIMAP")
    s.hud = MakeCheck(panel, "War table panel")
    s.minimap = MakeCheck(panel, "Minimap button")
    s.hud:SetPoint("TOPLEFT", 0, -L.y)
    s.minimap:SetPoint("TOPLEFT", 250, -L.y)
    L.y = L.y + 32
    L.Heading("GUILD AND PARTY")
    s.share = MakeCheck(panel, "Share enemy sightings, my kills and my PvP deaths",
        "Map positions, plus the names on kill lines. Never your trail. Each player turns it on.")
    L.Place(s.share, 0, 42)
    s.shareHistory = MakeCheck(panel, "Share my battle history with guildmates",
        "Your battle haze, so their maps show where you've fought. Needs sharing on.")
    L.Place(s.shareHistory, 0, 42)
end

-- "Map icon size": a slider (25%-200%, steps of 5), or -/+ buttons where
-- the client has no slider template. Changes show at once on an open map.
local function IconSize(panel, x, y)
    local ctl = { value = 100 }
    local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", x + 4, -y)
    local function Apply(v, fromUser)
        v = math.max(25, math.min(200, math.floor(v / 5 + 0.5) * 5))
        ctl.value = v
        label:SetText(("Map icon size: %d%%"):format(v))
        if fromUser then
            cfg.iconScale = v
            if ns.RescalePins then ns.RescalePins() end
        end
        return v
    end
    local ok, sl = pcall(CreateFrame, "Slider", "WarpathIconSize", panel, "OptionsSliderTemplate")
    -- a client without the template still makes a bare, invisible slider: check for its thumb
    if ok and sl and not (sl.GetThumbTexture and sl:GetThumbTexture()) then sl:Hide() sl = nil end
    if ok and sl then
        sl:SetPoint("TOPLEFT", x + 6, -(y + 16))
        sl:SetWidth(200)
        sl:SetMinMaxValues(25, 200)
        sl:SetValueStep(5)
        if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
        for _, part in ipairs({ "Low", "High", "Text" }) do
            local fs = _G["WarpathIconSize" .. part] or sl[part]
            if fs then fs:SetText(part == "Low" and "25%" or part == "High" and "200%" or "") end
        end
        sl:SetScript("OnValueChanged", function(_, v, user)
            if ctl.loading then Apply(v) return end
            Apply(v, true)
        end)
        function ctl.Set(v) ctl.loading = true sl:SetValue(v) Apply(v) ctl.loading = false end
    else
        local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        minus:SetSize(26, 20)
        minus:SetPoint("TOPLEFT", x + 150, -(y - 3))
        minus:SetText("-")
        local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        plus:SetSize(26, 20)
        plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        plus:SetText("+")
        minus:SetScript("OnClick", function() Apply(ctl.value - 10, true) end)
        plus:SetScript("OnClick", function() Apply(ctl.value + 10, true) end)
        function ctl.Set(v) Apply(v) end
    end
    return ctl
end

local function BuildMap(s, panel)
    local L = Layout(panel)
    s.shown = MakeCheck(panel, "Show Warpath on the world map",
        "Same as the crossed-swords button in the map's top-right corner. Recording never stops.")
    s.showAll = MakeCheck(panel, "Show all pin history")
    s.showAll:SetPoint("TOPLEFT", 300, -L.y)
    L.Place(s.shown, 0, 46)
    L.Heading("LAYERS")
    s.layers = {}
    for i, key in ipairs(C.LAYERS) do
        local cb = MakeCheck(panel, C.LAYER_LABELS[key])
        cb:SetPoint("TOPLEFT", (i - 1) % 2 == 0 and 0 or 250, -(L.y + math.floor((i - 1) / 2) * 26))
        s.layers[key] = cb
    end
    local n = #C.LAYERS + 1
    s.guildHaze = MakeCheck(panel, "Guildmates' battle haze")
    s.guildHaze:SetPoint("TOPLEFT", (n - 1) % 2 == 0 and 0 or 250, -(L.y + math.floor((n - 1) / 2) * 26))
    L.y = L.y + math.ceil(n / 2) * 26 + 8
    s.shimmer = MakeCheck(panel, "Shimmer on well-worn gold roads")
    s.shimmer:SetPoint("TOPLEFT", 0, -L.y)
    s.iconScale = IconSize(panel, 250, L.y)
    L.y = L.y + 40
    L.Heading("HOW LONG THINGS STAY ON THE MAP")
    s.trailMin = MakeRadios(panel, "Today's trail", TRAIL)
    L.Radios(s.trailMin)
    s.runHours = MakeRadios(panel, "Corpse runs", HOURS)
    L.Radios(s.runHours)
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

local function BuildGrudges(s, panel)
    local L = Layout(panel)
    L.Heading("WHEN I SEE A GRUDGE")
    s.gAlert = MakeCheck(panel, "Banner and sound")
    L.Place(s.gAlert, 0, 26)
    s.gAgain = MakeRadios(panel, "Remind me again after", { { 1, "1 min" }, { 5, "5 min" }, { 15, "15 min" } }, 150)
    L.Radios(s.gAgain, 26)
    s.gMap = MakeCheck(panel, "Show where on the map (their crest and name, for 15 minutes)")
    L.Place(s.gMap)
    s.gPlates = MakeCheck(panel, "Mark them with a skull on nameplates and the target frame")
    L.Place(s.gPlates, 0, 34)
    L.Heading("MAKING GRUDGES")
    s.gAuto = MakeRadios(panel, "When a player kills me",
        { { "off", "Do nothing" }, { "offer", "Offer one in chat" }, { "add", "Add one automatically" } }, 150)
    L.Radios(s.gAuto, 24)
    s.gAfter = MakeRadios(panel, "...after they kill me", { { 2, "2 times" }, { 3, "3 times" }, { 5, "5 times" } }, 150)
    L.Radios(s.gAfter, 30)
    s.gAuto.onChange = function(v) s.gAfter:SetEnabled(v ~= "off") end
    L.Heading("SETTLING AND FORGIVING")
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 0, -L.y)
    note:SetWidth(500)
    note:SetJustifyH("LEFT")
    note:SetText("Killing a grudge counts it as settled. A grudge only leaves your ledger when you forgive it, "
        .. "in the chronicle or with /warpath grudge forgive.")
    L.y = L.y + 34
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(170, 24)
    open:SetPoint("TOPLEFT", 0, -L.y)
    open:SetText("Open the ledger")
    open:SetScript("OnClick", function() ns.Chronicle.Open(false, "grudges") end)
end

local function BuildSetup()
    local s = CreateFrame("Frame", "WarpathSetup", UIParent, "BackdropTemplate")
    local TEXT_W = 516 - 12 - 14 - 12  -- box width less padding and the bullet
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
    local nh = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    nh:SetPoint("TOPLEFT", 12, -10)
    local news = Unseen(gdb.seenVersion)
    local first, last = news[1] and news[1][1], news[#news] and news[#news][1]
    nh:SetText(first and first ~= last and ("NEW IN " .. first .. " TO " .. last) or ("NEW IN " .. (last or VERSION)))
    local y = 10 + 14 + 6
    for _, item in ipairs(news) do
        local line = item[2]
        -- a small gold square as the bullet (a bullet glyph may draw as a box in the game font)
        local dot = s.newBox:CreateTexture(nil, "ARTWORK")
        dot:SetColorTexture(1, 0.82, 0, 0.9)
        dot:SetSize(4, 4)
        dot:SetPoint("TOPLEFT", 14, -(y + 4))
        local fs = s.newBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12 + 14, -y)
        fs:SetWidth(TEXT_W)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        if fs.SetSpacing then fs:SetSpacing(2) end
        fs:SetText(line)
        local h = fs:GetStringHeight() or 0
        if h < 10 then -- not measured yet: estimate from the length
            h = math.ceil(#line * 5.6 / TEXT_W) * 14
        end
        y = y + h + 6
    end
    s.newH = y + 6
    s.newBox:SetHeight(s.newH)
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
    BuildGrudges(s, s.panels[5])
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
        Print("settings saved. /warpath setup to change them.")
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
local BODY_H = 330
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
        s.sub:SetText(S.mapWasReset and "Your settings are kept, except the map's: see the Map tab."
            or "Your current settings are already filled in.")
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

-- Once per account per release (every release since 3.8.1; before, only
-- feature releases), never in combat. Not for going back to an older one.
function MaybeShowSetup()
    if gdb.seenVersion == VERSION then return end
    if gdb.seenVersion and not Older(gdb.seenVersion, VERSION) then return end
    if S.inInstance then S.setupWaiting = true return end
    if InCombatLockdown() or UnitAffectingCombat("player") then
        S.setupWaiting = true
        return
    end
    S.setupWaiting = false
    local ok, err = pcall(ShowSetup, gdb.installed and true or false, S.mapWasReset and gdb.installed and 2 or 1)
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
