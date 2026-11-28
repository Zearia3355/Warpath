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
-- plain line per change, for players: short, one line on the page where it
-- can be (Joe's layout C, 2026-11-26: the mock's lines were short, which is
-- what made it fit), under "## Topic" lines.
local NEW_MAX = 8
local NEW_IN = {
  { "3.8.0", title = "Roads, trails and flights", {
    "Roads turn from silver to gold as they become habits.",
    "Your most-worn roads carry your faction's colour.",
    "Where you linger, the trail becomes an outlined area.",
    "Between areas, dashes and arrows show your way.",
    "Flights taken on two or more days show as blue dashes.",
    "Map settings reset: every layer on, trail kept 12 hours.",
  } },
  { "3.8.1", {
    "You're told once when a guildmate runs a newer Warpath.",
    "/warpath trail clear clears today's trail.",
    "This page opens after every update.",
  } },
  { "3.8.2", {
    "Inside your current area, only a short tail of trail shows.",
  } },
  { "3.8.3", title = "Scores and a clearer trail", {
    "## On the map",
    "Scores everywhere: blue ahead, yellow close, red behind.",
    "Crowded pins combine into one sword or skull; hover for the count.",
    "Flight paths on continents are thinner and smoother.",
    "In a battleground, your other maps still draw.",
    "## Your trail",
    "Older trail is crimson dashes, easy to follow.",
    "Along roads it fades after 10 minutes.",
    "Lingering areas fit the land; touching ones merge.",
    "The tail behind you fades like a comet.",
    "## This book",
    "Settings live here now, on the Settings tab.",
    "\"Announce on screen\" replaces quiet mode and big text.",
    "Guildmates' chat lines can be switched off.",
    "Recent flights get their own length on the map.",
    "## Fixes",
    "Ground warnings cover hunting and contested ground too.",
    "Warnings stay up longer; a shared kill is pinned once.",
    "/killshot is gone: use /warpath shot.",
    "The book's close button works in combat.",
  } },
  { "3.8.4", {
    "Spirit healers show on their own zone's map, with the corpse runs.",
    "A Horde or Alliance badge marks one-faction graveyards.",
    "Warpath learns each graveyard your characters release to.",
    "A kill several of you share names everyone in chat.",
  } },
  { "3.8.5", {
    "## The chronicle",
    "The chronicle is a new book: crimson leather, gilt and parchment.",
    "Each campaign is written up by a chronicler, with a route map.",
    "Deeds fold by zone and scroll inside the page.",
    "Quiet nights (patrols, no fighting) can be hidden.",
    "A new Ledger tab: your whole war in figures, over seven spreads.",
    "Grudges keep one log of every encounter, newest first.",
    "This page scrolls, with a key to the map's marks.",
    "Settings read more easily, with a live preview of kill captions.",
    "## The map",
    "Corpse runs, flights and spirit healers are separate layers.",
    "Guildmates' pins and sightings each have a switch, under yours.",
    "With guild sharing off, guildmates' marks are hidden, not deleted.",
    "Fixed a rare hang while drawing dashed lines.",
    "## The Ledger",
    "Warpath now counts flights, corpse runs and what kills you.",
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
    { "alerts",  "Alerts",         "What happens when you kill, die, or walk where you've fought" },
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

-- Off hides guildmates' marks and stops their deaths counting toward
-- dangerous ground (3.8.5); their saved data is kept for when it's back on.
local function ShareChanged()
    if ns.Ground then ns.Ground.Forget() end
    if cfg.share then return end
    for i = #ns.shared, 1, -1 do ns.shared[i] = nil end
    for i = #ns.outQ, 1, -1 do ns.outQ[i] = nil end
end

local function On(path) return function() return Path(cfg, path) and true or false end end

-- Kinds: topic, note, check, pair (two checks on a row), radios, layer (a
-- compact check with an inline hint), icons; for Screenshots, stacked (one
-- choice a line), captions (with the preview) and ledger. when: the row is
-- greyed out unless it's true. after: runs on a change. indent: a
-- sub-setting (smaller, indented). gap: px above a topic (default 6).
local function Both(a, b) return function() return a() and b() end end
local Shared = On("share")
local SPEC = {
    alerts = {
        { "topic", "Your kills and deaths" },
        { "check", "announce", "Announce on screen", "Banners at the top of the screen for kills and grudge sightings; big text for multi-kills, streaks and ground warnings." },
        { "radios", "overlaySize", "Big text size", { { "small", "Small" }, { "medium", "Medium" }, { "large", "Large" } }, indent = 24, when = On("announce") },
        { "check", "selfChat", "Kills and deaths in chat", "One line each, worded as your guild sees it. With this and Announce on screen both off, a kill still gets a short line." },
        { "topic", "Sound" },
        { "check", "sound", "Play sounds", "For kills, dangerous or contested ground, grudge sightings, and this book's pages." },
        { "topic", "Ground you've fought on" },
        { "note", "When you walk where you've fought before, Warpath says what it's been for you: your hunting ground, contested, or dangerous. On screen needs Announce on screen; without it, the warning goes to chat." },
        { "pair", { "groundScreen", "On screen" }, { "groundChat", "In chat" }, after = GroundChanged },
        { "radios", "groundAfter", "Warn after", { { 1, "1 fight" }, { 2, "2 fights" }, { 3, "3 fights" } }, indent = 24,
            after = GroundChanged, when = function() return cfg.groundScreen or cfg.groundChat end },
    },
    -- 3.8.5: corpse runs, flights and spirit healers are layers of their
    -- own; each length sits under its layer; guildmates' rows sit under the
    -- layer they belong to and grey while sharing (or that layer) is off.
    map = {
        { "check", "shown", "Show Warpath on the world map", "Same as the crossed swords on the map. Warpath records either way." },
        { "topic", "Layers" },
        { "layer", "layers.battle", nil, "where fighting happened" },
        { "layer", "guildHaze", "with guildmates' fighting", indent = 24, when = Both(Shared, On("layers.battle")) },
        { "layer", "layers.roads", nil, "the ways you travel most" },
        { "layer", "layers.recent" },
        { "radios", "trailMin", "kept for", TRAIL, indent = 24, when = On("layers.recent") },
        { "layer", "layers.runs" },
        { "radios", "runHours", "kept for", HOURS, indent = 24, when = On("layers.runs") },
        { "layer", "layers.flights", nil, "the legs you fly most" },
        { "radios", "flightHours", "kept for", HOURS, indent = 24, when = On("layers.flights") },
        { "layer", "layers.spirits", nil, "on their own zone's map" },
        { "layer", "layers.marks" },
        { "layer", "layers.guildMarks", "with guildmates' kills and deaths", indent = 24, when = Both(Shared, On("layers.marks")) },
        { "layer", "layers.sightings", nil, "the last 15 minutes" },
        { "layer", "layers.guildSights", "with guildmates' sightings", indent = 24, when = Both(Shared, On("layers.sightings")) },
        { "icons" },
    },
    guild = {
        { "check", "share", "Guild sharing", "Works both ways: guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. Only between guildmates who have it on. Never your trail. Off: theirs are hidden from your map, not deleted.", after = ShareChanged },
        { "check", "shareHistory", "Share my battle haze", "Sent to guildmates at login and when they ask, so their maps show where you've fought.", indent = 24, when = Shared },
        { "check", "guildChat", "Guildmates' kills and deaths in chat", "One line each. Their pins stay on the map either way.", indent = 24, when = Shared },
    },
    -- Screenshots has its own layout (Joe: S2, then "One large preview"):
    -- stacked choices, the caption names over a preview of the caption, and
    -- the pictures taken.
    shots = {
        { "check", "shot.on", "Screenshot my kills", "Saved to the game's Screenshots folder, one picture per burst of kills. /warpath shot test takes a test picture." },
        { "topic", "Which kills" },
        { "stacked", "shot.mode", { { "all", "Every kill" }, { "notable", "Notable only", "A first kill of a player, grudges, avenged deaths, multi-kills and feats, streaks of 3, 5 and every 10, and anyone you've killed 5 or more times." } }, when = On("shot.on") },
        { "topic", "Caption", gap = 2 },
        { "captions", "shot.card", { { "text", "Floating text" }, { "strip", "Caption strip" }, { "none", "None" } }, when = On("shot.on") },
        { "ledger", "Pictures taken" },
    },
    zones = {
        { "topic", "Entering a zone" },
        { "check", "zoneChat", "A line in chat with my history there", "Kills, deaths, miles, sightings, avenged deaths, best streak, and how it ranks among your zones." },
        { "check", "zoneText", "A line under the zone's name" },
        { "topic", "Panels and buttons" },
        { "check", "hudShown", "War table", "A small panel: enemies seen lately, dangerous ground nearby, and the skull for making a grudge." },
        { "check", "minimap", "Minimap button", "Click opens this book; right-click opens Settings." },
        { "topic", "This book" },
        { "check", "chronLogin", "Last campaign's headline in chat at login" },
        { "check", "chronOpen", "Open this book at login" },
        { "note", "Both only when a new campaign starts (after two hours or more away) and the last one had fighting." },
    },
    grudges = {
        { "topic", "When I see a grudge" },
        { "check", "grudge.alert", "Announce it, with a sound", "A banner and a sound. Follows Announce on screen and Play sounds on the Alerts tab." },
        { "radios", "grudge.again", "Again after", { { 1, "1 min" }, { 5, "5 min" }, { 15, "15 min" } }, indent = 24, when = On("grudge.alert") },
        { "check", "grudge.map", "Show where on the map", "Their crest and name, for 15 minutes." },
        { "check", "grudge.plates", "Skull on their nameplate and target frame" },
        { "topic", "Making grudges" },
        { "note", "When one player has killed my characters:", ink = true },
        { "radios", "grudge.auto", nil, { { "off", "Do nothing" }, { "offer", "Offer a grudge" }, { "add", "Add one" } } },
        { "radios", "grudge.after", "after", { { 2, "2 deaths" }, { 3, "3 deaths" }, { 5, "5 deaths" } },
            when = function() return cfg.grudge.auto ~= "off" end },
        { "note", "Killing a grudge settles it. A name is struck off only when you forgive it, on the Grudges tab." },
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

---------------------------------------------------------------------------
-- The page (3.8.5), as docs/design/chronicle-settings.md sets it: the
-- sections on the left page (wash, chevron, bar and diamond, rule), the
-- open section's controls on an inset sheet on the right, Screenshots with
-- its own layout and a caption preview drawn by the screenshots' own code.
--
-- Every position is the spec's, in render px (Book.X/Y convert; y are
-- baselines), and the spec's tables are G below, which a test checks the
-- built page against. Rows are laid out at each render, from what the
-- client measures, so wrapping follows the real faces.
---------------------------------------------------------------------------

local Book = ns.Book
local Str, Put, Set, Wpx = Book.Str, Book.Put, Book.Set, Book.Wpx
local INK, FADED, RUBRIC, SHADOW = Book.INK, Book.FADED, Book.RUBRIC, Book.SHADOW
local GREY, HOVER = { 133, 115, 87 }, { 150, 90, 30 }

local G = {
    L0 = 82, LR = 510, CX = 296, R0 = 586, RR = 1017, RCX = 801,
    head = { y = 120, px = 25, orn = 133, half = 110 },
    subline = { y = 164, px = 17 },
    rows = { y = 228, step = 70, x = 100, px = 21, desc = 22, descPx = 16 },
    open = { x0 = 70, x1 = 516, top = 28, bottom = 32, a = 0.12, fade = 60 },
    hover = { top = 26, bottom = 32, a = 0.08 },
    chevron = { x = 86, dy = -7, w = 8, h = 12 },
    bar = { dy = 4, h = 3, a = 0.9, past = 6, diamond = 12, ddy = 5, r = 4 },
    rule = { dy = 34, a = 0.85 },
    help = { y = 668, px = 15 },
    folio = { y = 694, px = 17 },
    sheet = { 576, 152, 1009, 650 },
    x0 = 586, x1 = 999, first = 184,
    topic = { px = 17, gap = 6, pad = 6, after = 30, ruleGap = 10, r1 = -6, a1 = 0.5, r2 = -3, a2 = 0.25 },
    check = { box = 24, label = 32, px = 17, hint = 19, hintPx = 15, lead = 16, after = 29 },
    layer = { box = 22, label = 30, px = 17, hintPx = 15, hintGap = 8, after = 25 },
    sub = { indent = 26, lift = 2, box = 18, label = 24, px = 15, hint = 17, hintPx = 15, lead = 16, after = 25, layerAfter = 23 },
    radios = { labelPx = 16, col = 98, pad = 10, r = 8, text = 19, px = 16, gap = 10, dy = -6, after = 29 },
    subRadios = { labelPx = 15, col = 72, r = 7, text = 17, px = 15, after = 24 },
    pair = { second = 190 },
    slider = { pad = 6, t0 = 140, t1 = 330, dy = -7, h = 20, value = 14, valuePx = 19, after = 30 },
    note = { px = 16, lead = 17, after = 26, inkPx = 17, inkAfter = 28 },
    restore = { x = 1015, y = 694, px = 15, dot = 9, ddy = -5, r = 3, under = 3, ua = 0.7 },
    shots = {
        choice = 22, choicePx = 17, hint = 18, hintPx = 15, lead = 16, after = 26, plain = 30,
        name = 20, namePx = 16, nameGap = 22, wash = { -6, 6, -18, 7 }, washA = 0.12, washFade = 8,
        preview = { gap = 14, dx = 2, w = 409, h = 124 },
        ledger = { y = 628, px = 17 },
    },
}

-- The caption preview: a strip of a loading screen (client art, loaded at
-- run time; the probe found both Arathi Basin and Warsong Gulch), with the
-- real caption over it at the size it has on a screenshot. The window shows
-- what the design's crops showed: box (1000,180)-(1560,350) of a 2560x1440
-- screenshot, as shares of the screen. Claude's call: Arathi Basin, and
-- this strip of it; Joe picks in game.
local PREVIEW = {
    art = "Interface\\Glues\\LoadingScreens\\LoadScreenArathiBasin",
    coords = { 0.1, 0.9, 0.36, 0.68 },
    crop = { 1000 / 2560, 1560 / 2560, 180 / 1440, 350 / 1440 },
}

local function Caps(parent, px, col, shadow)
    return Book.Caps(parent, "morph", px, col, { ratio = 0.78, track = 0.028 * px, shadow = shadow })
end

-- A 1 px rule's texture, placed again at each layout.
local function Line(t, x0, x1, y)
    x0, x1, y = math.floor(x0), math.floor(x1), math.floor(y)
    Book.Box(t, x0, y, math.max(x0 + 0.01, x1), y + 1)
end

-- Greedy word wrap to `width` px, measured in the face.
local function Wrap(face, px, text, width)
    local lines, line = {}, nil
    for word in text:gmatch("%S+") do
        local cand = line and (line .. " " .. word) or word
        if not line or Book.Measure(face, px, cand) <= width then
            line = cand
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line then lines[#lines + 1] = line end
    return lines
end

-- Wrapped text, one string a line: :Lay(x, y, width, lead) returns the
-- last line's baseline.
local Lines = {}
Lines.__index = Lines
local function NewLines(parent, face, px, col, text)
    return setmetatable({ parent = parent, face = face, px = px, col = col, text = text, fs = {}, n = 0 }, Lines)
end
function Lines:Lay(x, y, width, lead)
    local out = Wrap(self.face, self.px, self.text, width)
    for i, s in ipairs(out) do
        local fs = self.fs[i]
        if not fs then
            fs = Str(self.parent, self.face, self.px, self.col)
            self.fs[i] = fs
        end
        Set(fs, s)
        Put(fs, x, y + (i - 1) * lead, "l")
        fs:Show()
    end
    for i = #out + 1, #self.fs do self.fs[i]:Hide() end
    self.n = #out
    return y + (#out - 1) * lead
end
function Lines:Color(col)
    self.col = col
    for _, fs in ipairs(self.fs) do Book.Color(fs, col) end
end

-- A wash: a tinted band fading in and out over `fade` px at each end.
local Wash = {}
Wash.__index = Wash
local function NewWash(parent, col, a, fade)
    local w = setmetatable({ col = col, a = a, fade = fade, t = {} }, Wash)
    for i = 1, 3 do
        w.t[i] = parent:CreateTexture(nil, "BACKGROUND")
        w.t[i]:SetColorTexture(1, 1, 1, 1)
    end
    return w
end
function Wash:Set(x0, x1, y0, y1)
    local r, g, b = Book.RGB(self.col)
    local f = math.min(self.fade, (x1 - x0) / 2)
    self.t[1]:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, self.a))
    Book.Box(self.t[1], x0, y0, x0 + f, y1)
    self.t[2]:SetColorTexture(r, g, b, self.a)
    Book.Box(self.t[2], x0 + f, y0, x1 - f, y1)
    self.t[3]:SetGradient("HORIZONTAL", CreateColor(r, g, b, self.a), CreateColor(r, g, b, 0))
    Book.Box(self.t[3], x1 - f, y0, x1, y1)
    self.box = { x0, x1, y0, y1 }
end
function Wash:SetShown(on) for _, t in ipairs(self.t) do t:SetShown(on) end self.shown = on end

local P = { section = "alerts", panels = {}, items = {} }

local function Apply()
    if ns.Grudge then ns.Grudge.RefreshMarks() end
    if S.hud then S.hud:SetShown(cfg.hudShown and not S.inInstance) end
    UpdateHUD()
    S.dirty = true
    ns.Redraw()
end

---------------------------------------------------------------------------
-- Controls: the game's templates at the spec's sizes, labels in the book's
-- faces, the whole label clickable (SetHitRectInsets; Claude's call)
---------------------------------------------------------------------------

-- size: G.check, G.layer or G.sub (with layer: the compact row)
local function NewCheck(panel, g, label, hint, inline)
    local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cb:SetSize(g.box / 1.2, g.box / 1.2)
    cb.g = g
    cb.label = Str(panel, "friz", g.px, INK)
    Set(cb.label, label)
    if hint then cb.hint = NewLines(panel, "gari", g.hintPx, FADED, hint) end
    if inline then
        cb.inline = Str(panel, "gari", g.hintPx, FADED)
        Set(cb.inline, inline)
    end
    return cb
end

-- The box with its label's baseline at y: the box from y-size+5 to y+5.
local function PlaceCheck(cb, x, y)
    local g = cb.g
    local top = y - g.box + 5
    Book.Box(cb, x, top, x + g.box, top + g.box)
    Put(cb.label, x + g.label, y, "l", cb, x, top)
    cb:SetHitRectInsets(0, -math.max(0, g.label + Wpx(cb.label) - g.box) / 1.2, 0, 0)
    return x + g.label + Wpx(cb.label)
end

local function NewRadio(panel, g, value, text)
    local rb = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
    rb:SetSize(2 * g.r / 1.2, 2 * g.r / 1.2)
    rb.value, rb.g = value, g
    rb.text2 = Book.Bold(Str(panel, "friz", g.px, INK))
    Set(rb.text2, text)
    return rb
end

-- The dot centred 6 px above the baseline y; the label `text` px after the
-- button's left edge. Returns the label's right end.
local function PlaceRadio(rb, x, y, text)
    local r = rb.g.r
    local top = y + G.radios.dy - r
    Book.Box(rb, x, top, x + 2 * r, top + 2 * r)
    Put(rb.text2, x + text, y, "l", rb, x, top)
    rb:SetHitRectInsets(0, -math.max(0, text + Wpx(rb.text2) - 2 * r) / 1.2, 0, 0)
    return x + text + Wpx(rb.text2)
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
                local chosen = rb.value == v
                rb:SetChecked(chosen)
                if on then rb:Enable() else rb:Disable() end
                Book.Color(rb.text2, (not on and GREY) or (chosen and RUBRIC) or INK)
                rb.text2.twin:SetShown(chosen and on)
            end
            if widget.label then Book.Color(widget.label, on and FADED or GREY) end
            if widget.hints then for _, h in pairs(widget.hints) do h:Color(on and FADED or GREY) end end
            if widget.chosen then widget.chosen(v) end
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
        Book.Color(widget.label, on and INK or GREY)
        if widget.hint then widget.hint:Color(on and FADED or GREY) end
        if widget.inline then Book.Color(widget.inline, on and FADED or GREY) end
    end)
end

---------------------------------------------------------------------------
-- Rows. Each builds its widgets once and lays them out with lay(y, first),
-- y the baseline where the row starts, returning where the next starts.
---------------------------------------------------------------------------

local x0, x1 = G.x0, G.x1

local function TopicRow(panel, item, spec)
    local g = G.topic
    local caps = Caps(panel, g.px, RUBRIC)
    local r1 = Book.Solid(panel, "ARTWORK", RUBRIC, g.a1)
    local r2 = Book.Solid(panel, "ARTWORK", RUBRIC, g.a2)
    item.caps, item.rules = caps, { r1, r2 }
    function item.lay(y, first)
        if not first then y = y + (spec.gap or g.gap) end
        y = y + g.pad
        local w = caps:Set(spec[2], x0, y, "l")
        Line(r1, x0 + w + g.ruleGap, x1, y + g.r1)
        Line(r2, x0 + w + g.ruleGap, x1, y + g.r2)
        item.y = y
        return y + g.after
    end
end

local function NoteRow(panel, item, spec)
    local g = G.note
    if spec.ink then
        local fs = Str(panel, "friz", g.inkPx, INK)
        Set(fs, spec[2])
        item.fs = fs
        function item.lay(y) Put(fs, x0, y, "l") item.y = y return y + g.inkAfter end
        return
    end
    local lines = NewLines(panel, "gari", g.px, FADED, spec[2])
    item.lines = lines
    function item.lay(y)
        item.y = y
        return lines:Lay(x0, y, x1 - x0, g.lead) + g.after
    end
end

local function CheckRow(panel, item, spec)
    local sub = spec.indent
    local cb = NewCheck(panel, sub and G.sub or G.check, spec[3], spec[4])
    Bind(item, cb, spec[2], spec.after)
    item.cb = cb
    function item.lay(y)
        local g, x = cb.g, x0
        if sub then x, y = x0 + G.sub.indent, y - G.sub.lift end
        PlaceCheck(cb, x, y)
        item.y = y
        if cb.hint then
            y = cb.hint:Lay(x + g.label, y + g.hint, x1 - x - g.label, g.lead)
        end
        return y + g.after
    end
end

local function LayerRow(panel, item, spec)
    local sub = spec.indent
    local key = spec[2]:match("^layers%.(.+)$")
    local label = spec[3] or C.LAYER_LABELS[key or ""] or spec[2]
    local cb = NewCheck(panel, sub and G.sub or G.layer, label, nil, spec[4])
    Bind(item, cb, spec[2], spec.after)
    item.cb = cb
    function item.lay(y)
        local x = x0
        if sub then x, y = x0 + G.sub.indent, y - G.sub.lift end
        local right = PlaceCheck(cb, x, y)
        if cb.inline then Put(cb.inline, right + G.layer.hintGap, y, "l") end
        item.y = y
        return y + (sub and G.sub.layerAfter or G.layer.after)
    end
end

local function PairRow(panel, item, spec)
    local a = NewCheck(panel, G.check, spec[2][2])
    local b = NewCheck(panel, G.check, spec[3][2])
    Bind(item, a, spec[2][1], spec.after)
    Bind(item, b, spec[3][1], spec.after)
    item.cbs = { a, b }
    function item.lay(y)
        PlaceCheck(a, x0, y)
        PlaceCheck(b, x0 + G.pair.second, y)
        item.y = y
        return y + G.check.after
    end
end

local function RadiosRow(panel, item, spec)
    local sub = spec.indent
    local g = sub and G.subRadios or G.radios
    local grp = { buttons = {} }
    if spec[3] then grp.label = Str(panel, "gari", g.labelPx, FADED) Set(grp.label, spec[3]) end
    for i, opt in ipairs(spec[4]) do grp.buttons[i] = NewRadio(panel, g, opt[1], opt[2]) end
    Bind(item, grp, spec[2], spec.after)
    item.grp = grp
    function item.lay(y)
        local x = sub and x0 + G.sub.indent or x0
        if grp.label then
            Put(grp.label, x, y, "l")
            local w = Wpx(grp.label) + G.radios.pad
            if spec[3]:match("^%u") then w = math.max(g.col, w) end
            x = x + w
        end
        for _, rb in ipairs(grp.buttons) do x = PlaceRadio(rb, x, y, g.text) + G.radios.gap end
        item.y = y
        return y + g.after
    end
end

-- "Map icon size": a slider (25%-200%, steps of 5), or -/+ buttons where
-- the client has no slider template. Changes show at once on an open map.
local function IconsRow(panel, item)
    local g = G.slider
    local label = Str(panel, "friz", 17, INK)
    Set(label, "Map icon size")
    local value = Book.Bold(Str(panel, "garb", g.valuePx, RUBRIC))
    item.label, item.value = label, value
    local function Show(v, fromUser)
        v = math.max(25, math.min(200, math.floor(v / 5 + 0.5) * 5))
        Set(value, ("%d%%"):format(v))
        if fromUser then
            cfg.iconScale = v
            if ns.RescalePins then ns.RescalePins() end
        end
    end
    local ok, sl = pcall(CreateFrame, "Slider", "WarpathIconSize", panel, "OptionsSliderTemplate")
    -- a client without the template still makes a bare, invisible slider: check for its thumb
    if ok and sl and not (sl.GetThumbTexture and sl:GetThumbTexture()) then sl:Hide() sl = nil end
    local set, minus, plus
    if ok and sl then
        sl:SetMinMaxValues(25, 200)
        sl:SetValueStep(5)
        if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
        for _, part in ipairs({ "Low", "High", "Text" }) do
            local fs = _G["WarpathIconSize" .. part] or sl[part]
            if fs then fs:SetText("") end
        end
        local loading
        sl:SetScript("OnValueChanged", function(_, v) Show(v, not loading) end)
        function set(v) loading = true sl:SetValue(v) Show(v) loading = false end
        item.slider = sl
    else
        minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        minus:SetText("-")
        plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        plus:SetText("+")
        minus:SetScript("OnClick", function() Show((cfg.iconScale or 100) - 10, true) end)
        plus:SetScript("OnClick", function() Show((cfg.iconScale or 100) + 10, true) end)
        function set(v) Show(v) end
    end
    item.refresh = { function() set(cfg.iconScale or 100) end }
    item.paths = { "iconScale" }
    function item.lay(y)
        y = y + g.pad
        Put(label, x0, y, "l")
        local t0, t1, mid = x0 + g.t0, x0 + g.t1, y + g.dy
        if sl then
            Book.Box(sl, t0, mid - g.h / 2, t1, mid + g.h / 2)
        else
            Book.Box(minus, t0, mid - 12, t0 + 31, mid + 12)
            Book.Box(plus, t0 + 36, mid - 12, t0 + 67, mid + 12)
            t1 = t0 + 67
        end
        Put(value, t1 + g.value, y, "l")
        item.y = y
        return y + g.after
    end
end

---------------------------------------------------------------------------
-- Screenshots: stacked choices, the caption names over one large preview,
-- and the pictures-taken line
---------------------------------------------------------------------------

local function StackedRow(panel, item, spec)
    local g = G.shots
    local grp = { buttons = {}, hints = {} }
    for i, opt in ipairs(spec[3]) do
        grp.buttons[i] = NewRadio(panel, { r = G.radios.r, px = g.choicePx }, opt[1], opt[2])
        if opt[3] then grp.hints[i] = NewLines(panel, "gari", g.hintPx, FADED, opt[3]) end
    end
    Bind(item, grp, spec[2], spec.after)
    item.grp = grp
    function item.lay(y)
        item.y = y
        for i, rb in ipairs(grp.buttons) do
            PlaceRadio(rb, x0, y, g.choice)
            local h = grp.hints[i]
            if h then
                y = h:Lay(x0 + g.choice, y + g.hint, x1 - x0 - g.choice, g.lead) + g.after
            else
                y = y + g.plain
            end
        end
        return y
    end
end

-- The kill the preview shows: what /warpath shot test pictures.
local function SampleKill()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zone = mapID and not ns.Secret(mapID) and ns.MapName(mapID) or ""
    return { name = ns.myName or UnitName("player"), class = select(2, UnitClass("player")), zone = zone,
        times = 4, streak = 3, when = time() }
end

local function CaptionsRow(panel, item, spec)
    local g = G.shots
    local grp = { buttons = {}, washes = {} }
    for i, opt in ipairs(spec[3]) do
        grp.buttons[i] = NewRadio(panel, { r = G.radios.r, px = g.namePx }, opt[1], opt[2])
        grp.washes[i] = NewWash(panel, HOVER, g.washA, g.washFade)
        grp.washes[i]:SetShown(false)
    end
    -- the preview: client art, and the caption the screenshots draw
    local pv = CreateFrame("Frame", nil, panel)
    if pv.SetClipsChildren then pv:SetClipsChildren(true) end
    pv.art = pv:CreateTexture(nil, "BACKGROUND")
    pv.art:SetAllPoints()
    pv.art:SetTexture(PREVIEW.art)
    pv.art:SetTexCoord(unpack(PREVIEW.coords))
    pv.edge = {}
    for i = 1, 4 do pv.edge[i] = Book.Solid(panel, "ARTWORK", INK, 1) end
    pv.holder = CreateFrame("Frame", nil, pv)
    pv.holder:SetSize(1, 1)
    item.preview, item.grp = pv, grp
    local chosen, hovered
    local function Show(kind)
        pv.kind = kind
        local cards = pv.holder.warpathCards or {}
        for _, f in pairs(cards) do f:Hide() end
        if kind ~= "text" and kind ~= "strip" then return end
        local W, H = UIParent:GetWidth(), UIParent:GetHeight()
        local crop = PREVIEW.crop
        local scale = (g.preview.w / 1.2) / ((crop[2] - crop[1]) * W)
        local down = (-ns.CardTop() - crop[3] * H) * scale
        pv.holder:ClearAllPoints()
        pv.holder:SetPoint("TOP", pv, "TOP", 0, -down)
        local k = SampleKill()
        pv.card = (kind == "text" and ns.KillCard.Text or ns.KillCard.Strip)(k, pv.holder, scale)
    end
    P.ShowPreview = Show
    for i, rb in ipairs(grp.buttons) do
        rb:SetScript("OnEnter", function()
            hovered = rb.value
            grp.washes[i]:SetShown(rb.value ~= chosen)
            Show(rb.value)
        end)
        rb:SetScript("OnLeave", function()
            hovered = nil
            grp.washes[i]:SetShown(false)
            Show(chosen)
        end)
    end
    function grp.chosen(v)
        chosen = v
        if not hovered then Show(v) end
    end
    Bind(item, grp, spec[2], spec.after)
    function item.lay(y)
        item.y = y
        local x = x0
        for i, rb in ipairs(grp.buttons) do
            local right = PlaceRadio(rb, x, y, g.name)
            local wsh = g.wash
            grp.washes[i]:Set(x + wsh[1], right + wsh[2], y + wsh[3], y + wsh[4])
            x = right + g.nameGap
        end
        local p = g.preview
        local top, left = y + p.gap, x0 + p.dx
        Book.Box(pv, left, top, left + p.w, top + p.h)
        -- a 1 px ink edge just outside the picture
        Book.Box(pv.edge[1], left - 1, top - 1, left + p.w + 1, top)
        Book.Box(pv.edge[2], left - 1, top + p.h, left + p.w + 1, top + p.h + 1)
        Book.Box(pv.edge[3], left - 1, top - 1, left, top + p.h + 1)
        Book.Box(pv.edge[4], left + p.w, top - 1, left + p.w + 1, top + p.h + 1)
        Show(hovered or chosen)
        return top + p.h
    end
end

local function LedgerRow(panel, item, spec)
    local r = Book.Reckon(panel, G.shots.ledger.px)
    item.reckon = r
    function item.lay(y)
        r:Set(spec[2], tostring(gdb and gdb.shotCount or 0), x0, x1, G.shots.ledger.y)
        return y
    end
end

local ROWS = { topic = TopicRow, note = NoteRow, check = CheckRow, layer = LayerRow, pair = PairRow,
    radios = RadiosRow, icons = IconsRow, stacked = StackedRow, captions = CaptionsRow, ledger = LedgerRow }

local function BuildSection(R, key)
    local panel = CreateFrame("Frame", nil, R)
    panel:SetAllPoints(R)
    local items = {}
    for i, spec in ipairs(SPEC[key]) do
        local item = { spec = spec }
        ROWS[spec[1]](panel, item, spec)
        items[i] = item
    end
    P.panels[key], P.items[key] = panel, items
end

-- Lay a section out; returns where its content ends (the next row's y).
local function Lay(key)
    local y = G.first
    for i, item in ipairs(P.items[key] or {}) do y = item.lay(y, i == 1) end
    P.panels[key].bottom = y
    return y
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

---------------------------------------------------------------------------
-- The left page: the sections
---------------------------------------------------------------------------

-- The open section's chevron: a rubric triangle pointing right, 8 x 12,
-- from 1 px rows.
local function Chevron(parent)
    local c = { rows = {} }
    local g = G.chevron
    for j = 1, g.h do c.rows[j] = Book.Solid(parent, "ARTWORK", RUBRIC, 1) end
    function c.Place(cx, cy)
        for j = 0, g.h - 1 do
            local dy = (j + 0.5) - g.h / 2
            local w = g.w * (1 - math.abs(dy) / (g.h / 2))
            Book.Box(c.rows[j + 1], cx - 3, cy - g.h / 2 + j, cx - 3 + w, cy - g.h / 2 + j + 1)
        end
    end
    function c.SetShown(on) for _, t in ipairs(c.rows) do t:SetShown(on) end end
    return c
end

local function SectionRow(L, i, sec)
    local g = G.rows
    local row = { key = sec[1], y = g.y + (i - 1) * g.step }
    local y = row.y
    row.open = NewWash(L, RUBRIC, G.open.a, G.open.fade)
    row.open:Set(G.open.x0, G.open.x1, y - G.open.top, y + G.open.bottom)
    row.hover = NewWash(L, HOVER, G.hover.a, G.open.fade)
    row.hover:Set(G.open.x0, G.open.x1, y - G.hover.top, y + G.hover.bottom)
    row.hover:SetShown(false)
    row.chevron = Chevron(L)
    row.chevron.Place(G.chevron.x, y + G.chevron.dy)
    row.ink = Caps(L, g.px, INK)
    row.lit = Caps(L, g.px, RUBRIC, SHADOW)
    row.desc = Str(L, "gari", g.descPx, FADED)
    Set(row.desc, sec[3])
    Put(row.desc, g.x, y + g.desc, "l")
    row.bar = Book.Solid(L, "ARTWORK", RUBRIC, G.bar.a)
    row.diamond = Book.Diamond(L, 0, 0, G.bar.r, RUBRIC)
    row.rule = { Book.Solid(L, "ARTWORK", RUBRIC, G.rule.a), Book.Solid(L, "ARTWORK", RUBRIC, G.rule.a) }
    -- the click area: the band the washes cover
    row.button = CreateFrame("Button", nil, L)
    Book.Box(row.button, G.open.x0, y - G.open.top, G.open.x1, y + G.open.bottom)
    row.button:SetScript("OnClick", function()
        if P.section ~= row.key then
            P.section = row.key
            row.hover:SetShown(false)
            UISound("IG_ABILITY_PAGE_TURN", 836)
            P.Render()
        end
    end)
    row.button:SetScript("OnEnter", function() row.hover:SetShown(P.section ~= row.key) end)
    row.button:SetScript("OnLeave", function() row.hover:SetShown(false) end)
    return row
end

local function LayRow(row)
    local on = row.key == P.section
    local g, y = G.rows, row.y
    local name = SectionName(row.key)
    local w = (on and row.lit or row.ink):Set(name, g.x, y, "l")
    row.ink:SetShown(not on)
    row.lit:SetShown(on)
    row.open:SetShown(on)
    row.chevron.SetShown(on)
    if on then row.hover:SetShown(false) end
    local b = G.bar
    Book.Box(row.bar, g.x, y + b.dy, g.x + w + b.past, y + b.dy + b.h)
    Book.MoveDiamond(row.diamond, g.x + w + b.diamond, y + b.ddy)
    Line(row.rule[1], g.x, G.LR, y + G.rule.dy)
    Line(row.rule[2], g.x, G.LR, y + G.rule.dy + 1)
    row.bar:SetShown(on)
    Book.ShowDiamond(row.diamond, on)
    row.rule[1]:SetShown(on)
    row.rule[2]:SetShown(on)
    row.width = w
end

local function Folio(parent, text, x)
    local fs = Str(parent, "gari", G.folio.px, FADED)
    Set(fs, "\226\128\148 " .. text .. " \226\128\148")
    Put(fs, x, G.folio.y, "m")
    return fs
end

local function RestoreLink(R)
    local g = G.restore
    local b = CreateFrame("Button", nil, R)
    b.label = Str(R, "narrow", g.px, INK)
    Set(b.label, "Restore defaults")
    b.dot = Book.Diamond(R, 0, 0, g.r, RUBRIC)
    b.under = Book.Solid(R, "ARTWORK", RUBRIC, g.ua)
    b.under:Hide()
    function b.Lay()
        Put(b.label, g.x, g.y, "r")
        local w = Wpx(b.label)
        Book.MoveDiamond(b.dot, g.x - w - g.dot, g.y + g.ddy)
        Line(b.under, g.x - w, g.x, g.y + g.under)
        Book.Box(b, g.x - w - g.dot - g.r - 2, g.y - g.px, g.x + 2, g.y + 5)
    end
    b:SetScript("OnEnter", function() Book.Color(b.label, RUBRIC) b.under:Show() end)
    b:SetScript("OnLeave", function() Book.Color(b.label, INK) b.under:Hide() end)
    b:SetScript("OnClick", function()
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
    return b
end

-- Called by the chronicle when it builds its pages. L, R: the settings'
-- frames for the left and right pages, each covering the whole book (its
-- top-left is the book's, as Book.X/Y expect).
local function Build(L, R)
    P.L, P.R = L, R
    P.title = Caps(L, G.head.px, RUBRIC, SHADOW)
    Book.Ornament(L, G.CX, G.head.orn, G.head.half)
    P.subline = Str(L, "gari", G.subline.px, FADED)
    Set(P.subline, "Shared by all your characters. Changes apply at once.")
    P.rows = {}
    for i, sec in ipairs(SECTIONS) do P.rows[i] = SectionRow(L, i, sec) end
    P.help = Str(L, "narrow", G.help.px, FADED)
    Set(P.help, "/warpath help lists every command.")
    P.folioL = Folio(L, "xi", G.CX)

    P.head = Caps(R, G.head.px, RUBRIC, SHADOW)
    Book.Ornament(R, G.RCX, G.head.orn, G.head.half)
    local s = G.sheet
    P.sheet = Book.Sheet(R, s, { s[1] + 2, s[2] + 2, s[3] - 1, s[4] - 1 }, { s[3] - 8, s[2] + 10, s[4] - 10 })
    P.sheet:SetContent(0)   -- nothing scrolls here: no bar
    for _, sec in ipairs(SECTIONS) do BuildSection(R, sec[1]) end
    P.folioR = Folio(R, "xii", G.RCX)
    P.restore = RestoreLink(R)
end

function P.Render()
    if not P.rows then return end
    P.title:Set("Settings", G.CX, G.head.y, "m")
    Put(P.subline, G.CX, G.subline.y, "m")
    Put(P.help, G.CX, G.help.y, "m")
    for _, row in ipairs(P.rows) do LayRow(row) end
    P.head:Set(SectionName(P.section) or "", G.RCX, G.head.y, "m")
    for key, panel in pairs(P.panels) do panel:SetShown(key == P.section) end
    P.Refresh()
    Lay(P.section)
    P.restore.Lay()
end

-- The settings, open on a section ("alerts", "map", ..., or an old tab number).
function ShowSetup(_, section)
    if type(section) == "number" then section = OLD_TABS[section] end
    if section and SPEC[section] then P.section = section end
    ns.Chronicle.Open(false, "settings")
end

ns.Settings = { Build = Build, Render = function() P.Render() end, Refresh = function() P.Refresh() end,
    Restore = function() P.Restore() end, Sections = SECTIONS, GEOMETRY = G, PREVIEW = PREVIEW,
    Open = function(key) if SPEC[key] then P.section = key end end,
    -- where a section's content ends (render px; the sheet's foot is 650)
    Bottom = function(key) return P.items[key] and Lay(key) end,
    Frames = function() return P end,
    -- for tests: whether the open section's row bound to path is live (not greyed)
    Enabled = function(path)
        for _, item in ipairs(P.items[P.section] or {}) do
            for _, p in ipairs(item.paths or {}) do
                if p == path then return not item.spec.when or (item.spec.when() and true or false) end
            end
        end
    end }

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
