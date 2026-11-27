-- Warpath: Options
-- What's new in each release (NEW_IN), and the settings: from 3.8.3 a tab
-- of the chronicle (/warpath setup, the minimap button's right-click), not a
-- window of their own. After each install or update the chronicle opens on
-- its Warpath tab: a welcome and what's new.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Print, VERSION, UpdateHUD, UISound = ns.Print, ns.VERSION, ns.UpdateHUD, ns.UISound

local db, gdb, cfg, faction
ns.OnBind(function() db, gdb, cfg, faction = ns.db, ns.gdb, ns.cfg, ns.faction end)

local ShowSetup, MaybeShowSetup, setup
do
-- Every release gets an entry (Joe, 2026-11-24), newest last. The
-- chronicle's Warpath tab shows them all, newest first, and opens by itself
-- after each update, marking the releases this account hasn't seen. One
-- plain line per change, for players.
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
  { "3.8.2", {
    "Inside the area you're lingering in, only a short tail of trail shows behind you, not a scribble of the last 45 seconds.",
  } },
  { "3.8.3", title = "Scores, a clearer trail, settings in this book", {
    "## On the map",
    "Scores everywhere: one for each continent on the world map, one for each zone on continent maps, and a zone's own in its map's corner. Blue when you're ahead, yellow when it's close, red when you're behind.",
    "Where pins crowd on continent and world maps, they combine into one larger sword or skull. Hover it for how many, and how many were yours.",
    "Flight paths on Kalimdor and Eastern Kingdoms are thinner and smoother.",
    "In a battleground your other maps still show your war; only the battleground's own map stays clean.",
    "## Your trail",
    "Older trail stays crimson in long dashes with a dark edge, solid through sharp turns. Where you went the same way twice, only the newer pass shows.",
    "Along roads your trail fades after 10 minutes, so the roads read clean.",
    "Inside the area you're lingering in, the short tail behind you fades out like a comet instead of ending sharply.",
    "Lingering areas are wider in the open world and tighter in cities, and areas that touch become one. Their labels stay readable longer.",
    "## This book",
    "Settings live here now, on the Settings tab, in plain words. The separate options window is gone.",
    "What's new opens here after each update. Campaigns list their deeds by zone, and grudges their encounters by day.",
    "## Settings that changed",
    "\"Announce on screen\" replaces the banner, big-text and quiet switches. If you had quiet mode on, announcing, sounds and the zone line stay off.",
    "Guildmates' kill and death lines in chat can be turned off without turning off sharing.",
    "Recent flights get their own length on the map, beside corpse runs.",
    "Guild sharing starts on for new players. Yours stays as you set it, with a switch on this page.",
    "## Fixes",
    "Dangerous-ground warnings stay up long enough to read. A kill several guildmates get credit for is announced and pinned once (guildmates need 3.8.3 too). The map button no longer prints a chat line.",
    "/killshot and /pks are gone; use /warpath shot.",
  } },
}

local Older = ns.VersionOlder

-- The entries this account hasn't seen: { version, line } pairs, oldest
-- first, the newest NEW_MAX of them.
local function Unseen(seen)
    local out = {}
    for _, rel in ipairs(NEW_IN) do
        if not seen or Older(seen, rel[1]) then
            for _, line in ipairs(rel[2]) do
                if line:sub(1, 3) ~= "## " then out[#out + 1] = { rel[1], line } end -- "## ": a topic
            end
        end
    end
    while #out > NEW_MAX do table.remove(out, 1) end
    return out
end
ns.NewIn = { Older = Older, Unseen = Unseen, List = NEW_IN } -- List: for the chronicle
local HOURS = { { 1, "1h" }, { 6, "6h" }, { 24, "24h" }, { 48, "48h" } }
local TRAIL = {}
for i, m in ipairs(C.TRAIL_MIN_CHOICES) do TRAIL[i] = { m, m < 60 and (m .. "m") or ((m / 60) .. "h") } end

---------------------------------------------------------------------------
-- Settings (3.8.3): a tab of the chronicle, replacing the options window.
-- Left page: the sections. Right page: the open section's controls, built
-- from SPEC below. Every change applies at once; "Restore defaults" resets
-- the open section only (after a confirm).
---------------------------------------------------------------------------

local SECTIONS = {
    { "alerts",  "Alerts",         "What happens when you kill, die, or walk into danger" },
    { "map",     "Map",            "What the world map shows, and for how long" },
    { "guild",   "Guild",          "Your war shared with guildmates, and theirs with you" },
    { "shots",   "Screenshots",    "Kill screenshots and their captions" },
    { "zones",   "Zones & panels", "Zone stats, the war table, the minimap button, this book" },
    { "grudges", "Grudges",        "Grudge alerts, and making grudges" },
}
local OLD_TABS = { "alerts", "map", "shots", "zones", "grudges" } -- the options window's tab numbers

local function Path(t, path)
    for k in path:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[k]
    end
    return t
end

local function Put(t, path, v)
    local keys = {}
    for k in path:gmatch("[^.]+") do keys[#keys + 1] = k end
    for i = 1, #keys - 1 do
        t[keys[i]] = t[keys[i]] or {}
        t = t[keys[i]]
    end
    t[keys[#keys]] = v
end

local function Defaults()
    local d = { layers = {}, shot = {}, grudge = {} }
    for _, name in ipairs(C.LAYERS) do d.layers[name] = true end
    for k, v in pairs(C.SHOT_DEFAULTS) do d.shot[k] = v end
    for k, v in pairs(C.CFG_DEFAULTS) do d[k] = v end
    for k, v in pairs(C.GRUDGE_DEFAULTS) do d.grudge[k] = v end
    return d
end

local function GroundChanged()
    cfg.fieldAlert = cfg.groundScreen or cfg.groundChat
    if ns.Ground then ns.Ground.Forget() end
end

local function ShareChanged()
    if cfg.share then return end
    for i = #ns.shared, 1, -1 do ns.shared[i] = nil end
    for i = #ns.outQ, 1, -1 do ns.outQ[i] = nil end
end

local function On(path) return function() return Path(cfg, path) and true or false end end

-- Kinds: topic, note, check, pair (two checks on a row), radios, layers,
-- icons. when: the row is greyed out unless it's true. after: runs on a change.
local LAYER_HINT = { battle = "where fighting happened", roads = "the ways you travel most",
    sightings = "the last few minutes" }
local SPEC = {
    alerts = {
        { "topic", "Your kills and deaths" },
        { "check", "announce", "Announce on screen", "A line at the top of the screen for each kill, and big text for multi-kills and streaks. Off: they go to chat instead." },
        { "radios", "overlaySize", "Big text", { { "small", "Small" }, { "medium", "Medium" }, { "large", "Large" } }, indent = 24, when = On("announce") },
        { "check", "selfChat", "Also in chat", "One line for each kill or death, worded as your guild sees it." },
        { "topic", "Sound" },
        { "check", "sound", "Play sounds", "For kills, dangerous ground and grudge sightings, and this book's pages." },
        { "topic", "Dangerous ground" },
        { "note", "A warning when you walk where you've died before: dangerous, contested, or your hunting ground." },
        { "pair", { "groundScreen", "Warn on screen" }, { "groundChat", "Warn in chat" }, after = GroundChanged },
        { "radios", "groundAfter", "After", { { 1, "1 death" }, { 2, "2 deaths" }, { 3, "3 deaths" } }, indent = 24,
            after = GroundChanged, when = function() return cfg.groundScreen or cfg.groundChat end },
    },
    map = {
        { "check", "shown", "Show Warpath on the world map", "Same as the crossed swords on the map. Warpath keeps recording either way." },
        { "topic", "Layers" },
        { "layers" },
        { "icons" },
        { "topic", "Keep on the map for" },
        { "radios", "trailMin", "Today's trail", TRAIL, lw = 86, gap = 7 },
        { "radios", "runHours", "Corpse runs", HOURS, lw = 86 },
        { "radios", "flightHours", "Recent flights", HOURS, lw = 86 },
    },
    guild = {
        { "check", "share", "Guild sharing", "Works both ways: guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on. Never your trail.", after = ShareChanged },
        { "check", "shareHistory", "Share my battle history", "Your battle haze, sent at login, so guildmates' maps show where you've fought.", indent = 24, when = On("share") },
        { "check", "guildChat", "Guildmates' kills and deaths in chat", "One line each. Their pins stay on the map either way.", indent = 24, when = On("share") },
    },
    shots = {
        { "check", "shot.on", "Screenshot my kills", "Saved to the game's Screenshots folder." },
        { "radios", "shot.mode", "Which kills", { { "all", "Every kill" }, { "notable", "Notable only" } }, lw = 70, indent = 24, when = On("shot.on") },
        { "note", "Notable: a first kill of a player, grudges, avenged deaths, streaks of 3, 5 and every 10, and anyone you've killed 5 or more times.", indent = 24 },
        { "radios", "shot.card", "Caption", { { "text", "Floating text" }, { "strip", "Caption strip" }, { "none", "None" } }, lw = 70, indent = 24, when = On("shot.on") },
        { "note", "/warpath shot test takes a test picture." },
    },
    zones = {
        { "topic", "Entering a zone" },
        { "check", "zoneChat", "A line in chat with my history there", "Kills, deaths, miles, sightings, best streak and rank." },
        { "check", "zoneText", "A line under the zone's name" },
        { "topic", "On screen" },
        { "check", "hudShown", "War table", "A small panel: enemies seen lately, dangerous ground nearby, and the skull for making a grudge." },
        { "check", "minimap", "Minimap button", "Click opens this book; right-click opens Settings." },
        { "topic", "This book" },
        { "check", "chronLogin", "Last campaign's headline in chat at login" },
        { "check", "chronOpen", "Open this book at login" },
        { "note", "Both only when a new campaign starts (after two hours or more away) and the last one had fighting." },
    },
    grudges = {
        { "topic", "When I see a grudge" },
        { "check", "grudge.alert", "Announce it, with a sound" },
        { "radios", "grudge.again", "Again after", { { 1, "1 min" }, { 5, "5 min" }, { 15, "15 min" } }, indent = 24, when = On("grudge.alert") },
        { "check", "grudge.map", "Show where on the map", "Their crest and name, for 15 minutes." },
        { "check", "grudge.plates", "Skull on their nameplate and target frame" },
        { "topic", "Making grudges" },
        { "note", "When the same player keeps killing me:", ink = true },
        { "radios", "grudge.auto", nil, { { "off", "Do nothing" }, { "offer", "Offer a grudge" }, { "add", "Add one" } } },
        { "radios", "grudge.after", "after", { { 2, "2 deaths" }, { 3, "3 deaths" }, { 5, "5 deaths" } }, lw = 40,
            when = function() return cfg.grudge.auto ~= "off" end },
        { "note", "Killing a grudge settles it. A name leaves your ledger only when you forgive it, on the Grudges tab." },
    },
}

-- The minimap button keeps its own saved shape.
local SPECIAL = {
    minimap = { get = function() return ns.Minimap.Shown() end, set = function(v) ns.Minimap.SetShown(v) end, def = true },
}

local function Getter(path)
    if SPECIAL[path] then return SPECIAL[path].get end
    return function() return Path(cfg, path) end
end
local function Setter(path)
    if SPECIAL[path] then return SPECIAL[path].set end
    return function(v) Put(cfg, path, v) end
end
local function Default(path)
    if SPECIAL[path] then return SPECIAL[path].def end
    return Path(Defaults(), path)
end

local K -- the chronicle's kit: Font, Topic, Diamond, Ornament, colours, INNER
local P = { section = "alerts", panels = {}, items = {} }

local function Apply()
    if ns.Grudge then ns.Grudge.RefreshMarks() end
    if S.hud then S.hud:SetShown(cfg.hudShown and not S.inInstance) end
    UpdateHUD()
    S.dirty = true
    ns.Redraw()
end

local function Grey(fs, on, color)
    color = on and (color or K.INK) or K.GREY
    fs:SetTextColor(color[1], color[2], color[3])
end

-- Text height once wrapped to `width`: the client measures 0 before a
-- string is drawn and the stub never wraps, so whichever is taller.
local function Tall(fs, width, line)
    local n = math.max(1, math.ceil((fs:GetStringWidth() or 0) / width))
    return math.max(fs:GetStringHeight() or 0, n * line)
end

local function MakeCheck(panel, x, y, label, hint)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, -y)
    cb.label = K.Font(panel, QuestFont, GameFontHighlight, K.INK)
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
    cb.label:SetText(label)
    local h = 24
    if hint then
        local w = K.INNER - (x - 32) - 24
        cb.hint = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
        cb.hint:SetPoint("TOPLEFT", x + 24, -(y + 21))
        cb.hint:SetWidth(w)
        cb.hint:SetSpacing(1)
        cb.hint:SetText(hint)
        h = 24 + Tall(cb.hint, w, 13) + 4
    end
    return cb, h
end

local function MakeRadios(panel, x, y, label, opts, lw, gap)
    local g = { buttons = {} }
    local start = x
    if label then
        g.label = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
        g.label:SetPoint("TOPLEFT", x, -(y + 4))
        g.label:SetText(label)
        start = x + (lw or 80)
    end
    local prev
    for i, opt in ipairs(opts) do
        local rb = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
        rb:SetSize(16, 16)
        rb.value = opt[1]
        rb.text2 = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.INK)
        rb.text2:SetPoint("LEFT", rb, "RIGHT", 2, 0)
        rb.text2:SetText(opt[2])
        if prev then rb:SetPoint("LEFT", prev.text2, "RIGHT", gap or 10, 0) else rb:SetPoint("TOPLEFT", start, -(y + 2)) end
        g.buttons[i] = rb
        prev = rb
    end
    return g, 24
end

-- One control, bound to a saved path.
local function Bind(item, widget, path, after)
    local get, set = Getter(path), Setter(path)
    item.refresh = item.refresh or {}
    item.paths = item.paths or {}
    table.insert(item.paths, path)
    if widget.buttons then
        for _, rb in ipairs(widget.buttons) do
            rb:SetScript("OnClick", function()
                set(rb.value)
                if after then after() end
                Apply()
                P.Refresh()
            end)
        end
        table.insert(item.refresh, function(on)
            local v = get()
            for _, rb in ipairs(widget.buttons) do
                rb:SetChecked(rb.value == v)
                if on then rb:Enable() else rb:Disable() end
                Grey(rb.text2, on)
            end
            if widget.label then Grey(widget.label, on, K.FADED) end
        end)
        return
    end
    widget:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        set(v)
        UISound(v and "IG_MAINMENU_OPTION_CHECKBOX_ON" or "IG_MAINMENU_OPTION_CHECKBOX_OFF", 856)
        if after then after() end
        Apply()
        P.Refresh()
    end)
    table.insert(item.refresh, function(on)
        widget:SetChecked(get() and true or false)
        if on then widget:Enable() else widget:Disable() end
        Grey(widget.label, on)
        if widget.hint then Grey(widget.hint, on, K.FADED) end
    end)
end

-- "Map icon size": a slider (25%-200%, steps of 5), or -/+ buttons where
-- the client has no slider template. Changes show at once on an open map.
local function IconSize(panel, item, x, y)
    local label = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
    label:SetPoint("TOPLEFT", x, -(y + 4))
    label:SetText("Map icon size")
    local value = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.INK)
    local function Show(v, fromUser)
        v = math.max(25, math.min(200, math.floor(v / 5 + 0.5) * 5))
        value:SetText(("%d%%"):format(v))
        if fromUser then
            cfg.iconScale = v
            if ns.RescalePins then ns.RescalePins() end
        end
    end
    local ok, sl = pcall(CreateFrame, "Slider", "WarpathIconSize", panel, "OptionsSliderTemplate")
    -- a client without the template still makes a bare, invisible slider: check for its thumb
    if ok and sl and not (sl.GetThumbTexture and sl:GetThumbTexture()) then sl:Hide() sl = nil end
    local set
    if ok and sl then
        sl:SetPoint("TOPLEFT", x + 92, -(y + 2))
        sl:SetWidth(170)
        sl:SetMinMaxValues(25, 200)
        sl:SetValueStep(5)
        if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
        for _, part in ipairs({ "Low", "High", "Text" }) do
            local fs = _G["WarpathIconSize" .. part] or sl[part]
            if fs then fs:SetText("") end
        end
        value:SetPoint("LEFT", sl, "RIGHT", 8, 0)
        local loading
        sl:SetScript("OnValueChanged", function(_, v) Show(v, not loading) end)
        function set(v) loading = true sl:SetValue(v) Show(v) loading = false end
    else
        local minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        minus:SetSize(26, 20)
        minus:SetPoint("TOPLEFT", x + 92, -y)
        minus:SetText("-")
        local plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        plus:SetSize(26, 20)
        plus:SetPoint("LEFT", minus, "RIGHT", 4, 0)
        plus:SetText("+")
        value:SetPoint("LEFT", plus, "RIGHT", 8, 0)
        minus:SetScript("OnClick", function() Show((cfg.iconScale or 100) - 10, true) end)
        plus:SetScript("OnClick", function() Show((cfg.iconScale or 100) + 10, true) end)
        function set(v) Show(v) end
    end
    item.refresh = { function() set(cfg.iconScale or 100) end }
    item.paths = { "iconScale" }
    return 32
end

local function Layers(panel, item, x, y)
    local h = 0
    for _, key in ipairs(C.LAYERS) do
        local cb = MakeCheck(panel, x, y + h, C.LAYER_LABELS[key])
        if LAYER_HINT[key] then
            local hint = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
            hint:SetPoint("LEFT", cb.label, "RIGHT", 6, 0)
            hint:SetText(LAYER_HINT[key])
        end
        Bind(item, cb, "layers." .. key)
        h = h + 22
        -- guildmates' fighting is part of the one haze, not a layer of its own
        if key == "battle" then
            Bind(item, MakeCheck(panel, x + 24, y + h, "with guildmates' fighting"), "guildHaze")
            h = h + 22
        end
    end
    return h + 6
end

local function Row(panel, spec, y)
    local kind, item = spec[1], { spec = spec }
    local x = 32 + (spec.indent or 0)
    local h
    if kind == "topic" then
        K.Topic(panel, spec[2], x, y)
        h = 24
    elseif kind == "note" then
        local fs = K.Font(panel, QuestFontNormalSmall, GameFontNormalSmall, spec.ink and K.INK or K.FADED)
        local w = K.INNER - (x - 32)
        fs:SetPoint("TOPLEFT", x, -y)
        fs:SetWidth(w)
        fs:SetSpacing(1)
        fs:SetText(spec[2])
        h = Tall(fs, w, 13) + 8
    elseif kind == "check" then
        local cb
        cb, h = MakeCheck(panel, x, y, spec[3], spec[4])
        Bind(item, cb, spec[2], spec.after)
    elseif kind == "pair" then
        Bind(item, (MakeCheck(panel, x, y, spec[2][2])), spec[2][1], spec.after)
        Bind(item, (MakeCheck(panel, x + K.INNER / 2, y, spec[3][2])), spec[3][1], spec.after)
        h = 24
    elseif kind == "radios" then
        local g
        g, h = MakeRadios(panel, x, y, spec[3], spec[4], spec.lw, spec.gap)
        Bind(item, g, spec[2], spec.after)
    elseif kind == "layers" then
        h = Layers(panel, item, x, y)
    else
        h = IconSize(panel, item, x, y)
    end
    return item, h
end

local function BuildSection(R, key)
    local panel = CreateFrame("Frame", nil, R)
    panel:SetAllPoints()
    local items, y = {}, 70
    for i, spec in ipairs(SPEC[key]) do
        if spec[1] == "topic" and i > 1 then y = y + 8 end -- room above a heading
        local item, h = Row(panel, spec, y)
        items[#items + 1] = item
        y = y + h
    end
    panel.bottom = y
    P.panels[key], P.items[key] = panel, items
end

function P.Refresh()
    for _, item in ipairs(P.items[P.section] or {}) do
        local when = item.spec.when
        local on = not when or (when() and true or false)
        for _, fn in ipairs(item.refresh or {}) do fn(on) end
    end
end

local function Restore()
    for _, item in ipairs(P.items[P.section] or {}) do
        for _, path in ipairs(item.paths or {}) do
            local d = Default(path)
            if d ~= nil then Setter(path)(d) end
        end
        if item.spec.after then item.spec.after() end
    end
    if ns.RescalePins then ns.RescalePins() end
    Apply()
    P.Refresh()
end
P.Restore = Restore

local function SectionName(key)
    for _, s in ipairs(SECTIONS) do if s[1] == key then return s[2] end end
end

local function ContentsRow(L, i, sec)
    local row = CreateFrame("Button", nil, L)
    row:SetSize(K.INNER + 8, 44)
    row:SetPoint("TOPLEFT", 28, -100 - (i - 1) * 50)
    row:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetColorTexture(K.RUBRIC[1], K.RUBRIC[2], K.RUBRIC[3], 0.12)
    row.sel:SetAllPoints()
    row.mark = K.Diamond(row, 7)
    row.mark:SetPoint("RIGHT", row, "LEFT", -3, 8)
    row.name = K.Font(row, QuestTitleFont, GameFontNormal, K.INK, 15)
    row.name:SetPoint("TOPLEFT", 4, -4)
    row.name:SetText(sec[2])
    row.desc = K.Font(row, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
    row.desc:SetPoint("TOPLEFT", 4, -24)
    row.desc:SetWidth(K.INNER)
    row.desc:SetWordWrap(false)
    row.desc:SetText(sec[3])
    row.key = sec[1]
    row:SetScript("OnClick", function(self)
        if P.section ~= self.key then
            P.section = self.key
            UISound("IG_ABILITY_PAGE_TURN", 836)
            P.Render()
        end
    end)
    return row
end

-- Called by the chronicle when it builds its pages. L, R: the settings'
-- frames on the left and right pages; kit: its drawing helpers.
local function Build(L, R, kit)
    K = kit
    local title = K.Font(L, QuestTitleFont, GameFontNormalLarge, K.INK)
    title:SetPoint("TOP", 0, -32)
    title:SetJustifyH("CENTER")
    title:SetText("Settings")
    K.Ornament(L, -60)
    local sub = K.Font(L, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
    sub:SetPoint("TOP", 0, -70)
    sub:SetJustifyH("CENTER")
    sub:SetText("Shared by all your characters. Changes apply at once.")
    P.rows = {}
    for i, sec in ipairs(SECTIONS) do P.rows[i] = ContentsRow(L, i, sec) end
    local foot = K.Font(L, QuestFontNormalSmall, GameFontNormalSmall, K.FADED)
    foot:SetPoint("BOTTOM", 0, 40)
    foot:SetJustifyH("CENTER")
    foot:SetText("/warpath help lists every command.")

    P.head = K.Font(R, QuestTitleFont, GameFontNormal, K.RUBRIC, 15)
    P.head:SetPoint("TOP", 0, -30)
    K.Ornament(R, -54)
    for _, sec in ipairs(SECTIONS) do BuildSection(R, sec[1]) end
    local restore = CreateFrame("Button", nil, R, "UIPanelButtonTemplate")
    restore:SetSize(130, 22)
    restore:SetPoint("BOTTOMRIGHT", -28, 12)
    restore:SetText("Restore defaults")
    restore:SetScript("OnClick", function()
        if StaticPopupDialogs and not StaticPopupDialogs.WARPATH_RESTORE then
            StaticPopupDialogs.WARPATH_RESTORE = {
                text = "Put the %s settings back to their defaults?",
                button1 = OKAY or "Okay", button2 = CANCEL or "Cancel",
                OnAccept = function() P.Restore() end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
        end
        StaticPopup_Show("WARPATH_RESTORE", SectionName(P.section))
    end)
end

function P.Render()
    for key, panel in pairs(P.panels) do panel:SetShown(key == P.section) end
    for _, row in ipairs(P.rows or {}) do
        local c = row.key == P.section and K.RUBRIC or K.INK
        row.sel:SetShown(row.key == P.section)
        row.mark:SetShown(row.key == P.section)
        row.name:SetTextColor(c[1], c[2], c[3])
    end
    if P.head then P.head:SetText(SectionName(P.section) or "") end
    P.Refresh()
end

-- The settings, open on a section ("alerts", "map", ..., or an old tab number).
function ShowSetup(_, section)
    if type(section) == "number" then section = OLD_TABS[section] end
    if section and SPEC[section] then P.section = section end
    ns.Chronicle.Open(false, "settings")
end

ns.Settings = { Build = Build, Render = function() P.Render() end, Refresh = function() P.Refresh() end,
    Restore = function() P.Restore() end, Sections = SECTIONS,
    Open = function(key) if SPEC[key] then P.section = key end end,
    Bottom = function(key) return P.panels[key] and P.panels[key].bottom end }

-- Once per account per release (every release since 3.8.1; before, only
-- feature releases), never in combat or a battleground: the chronicle on
-- its Warpath tab (3.8.3; the options window before). Closing the book
-- marks the release seen. Not for going back to an older one.
function MaybeShowSetup()
    if gdb.seenVersion == VERSION then return end
    if gdb.seenVersion and not Older(gdb.seenVersion, VERSION) then return end
    if S.inInstance or InCombatLockdown() or UnitAffectingCombat("player") then
        S.setupWaiting = true
        return
    end
    S.setupWaiting = false
    local ok, err = pcall(ns.Chronicle.News, gdb.seenVersion)
    if not ok then
        Print("the chronicle failed to open: " .. tostring(err))
        Print("please send that line to whoever gave you Warpath. Your settings are unchanged.")
        gdb.seenVersion = VERSION -- don't fail again on every login
    end
end

end

-- The options window is gone (3.8.3): the settings are a page of the book.
function ns.HideSetup() end
function ns.SetupShown() return ns.Chronicle.Shown() == "settings" end

ns.MaybeShowSetup = MaybeShowSetup
ns.ShowSetup = ShowSetup
