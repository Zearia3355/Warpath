-- A stand-in for the WoW client, enough to load Warpath and drive it.
--
-- Two rules shape it:
--
--   * Widgets accept ANY method. UI code calls hundreds of SetPoint/SetText
--     style methods whose effect we don't need, so an unknown method is a
--     recorded no-op. Methods whose return value matters are implemented.
--
--   * Unknown GLOBALS stay nil, exactly as in the client. Warpath guards
--     optional APIs with `if C_AddOns and C_AddOns.X then`, so a catch-all
--     would make those guards lie. A missing stub fails loudly instead, with
--     a traceback naming it.
--
-- The harness (harness.py) drives time, events and timers through the
-- __H table at the bottom.

local H = {
    now = 1795400000,     -- time(): wall clock, seconds since epoch
    gt = 1000,            -- GetTime(): seconds since the client started
    chat = {},            -- every line printed to chat
    sent = {},            -- every addon message sent
    timers = {},          -- C_Timer queue
    frames = {},          -- every frame, for event dispatch
    unknownMethods = {},  -- widget methods we answered with a no-op
    player = { name = "Tester", realm = "", faction = "Horde", class = "WARRIOR",
               race = "Orc", level = 60, guild = "Test Guild", mapID = 1448, x = 0.5, y = 0.5 },
    instance = false,
}
__H = H

-- Lua 5.1 aliases WoW provides ----------------------------------------------
strsplit = function(sep, s, limit)
    local out, start = {}, 1
    while true do
        if limit and #out == limit - 1 then out[#out + 1] = s:sub(start) break end
        local a, b = s:find(sep, start, true)
        if not a then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, a - 1)
        start = b + 1
    end
    return unpack(out)
end
strtrim = function(s, chars)
    chars = chars and ("[" .. chars:gsub("%p", "%%%0") .. "]") or "%s"
    return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strmatch, strfind, strsub, strlen, strlower, strupper, strrep, strbyte, strchar, gsub, format =
    string.match, string.find, string.sub, string.len, string.lower, string.upper, string.rep,
    string.byte, string.char, string.gsub, string.format
tinsert, tremove, tContains, sort = table.insert, table.remove, nil, table.sort
tContains = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
max, min, floor, ceil, abs, sqrt = math.max, math.min, math.floor, math.ceil, math.abs, math.sqrt
mod = math.fmod
CopyTable = function(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
Ambiguate = function(name, _) return (name:gsub("%-.*$", "")) end

-- Time -------------------------------------------------------------------------
time = function(t) if t then return os.time(t) end return H.now end
date = function(fmt, t) return os.date(fmt, t or H.now) end
GetTime = function() return H.gt end
GetServerTime = function() return H.now end

C_Timer = {}
local function queue(delay, fn, interval, iterations)
    local t = { due = H.gt + delay, fn = fn, interval = interval, left = iterations, cancelled = false }
    t.Cancel = function(self) self.cancelled = true end
    t.IsCancelled = function(self) return self.cancelled end
    H.timers[#H.timers + 1] = t
    return t
end
C_Timer.After = function(delay, fn) queue(delay, fn) end
C_Timer.NewTimer = function(delay, fn) return queue(delay, fn) end
C_Timer.NewTicker = function(interval, fn, iterations) return queue(interval, fn, interval, iterations) end

-- Chat ---------------------------------------------------------------------------
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    H.chat[#H.chat + 1] = table.concat(parts, " ")
end

-- Widgets ------------------------------------------------------------------------
local Widget = {}
local widget_mt = {}
-- Methods the Forever client does NOT have (checked in game by the 3.8.4
-- probe), so calling one errors there and must error here too, instead of
-- being swallowed by the catch-all below.
local NOT_IN_CLIENT = { SetGradientAlpha = true }
widget_mt.__index = function(self, key)
    local m = Widget[key]
    if m ~= nil then return m end
    if NOT_IN_CLIENT[key] then return nil end
    if type(key) == "string" and key:match("^%u") then
        H.unknownMethods[key] = (H.unknownMethods[key] or 0) + 1
        return function() end
    end
    return nil
end

H.seq = 0
local function NewWidget(kind, name, parent)
    H.seq = H.seq + 1   -- creation order: the client draws same-level frames and same-layer regions in it
    local w = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = true,
        __scripts = {}, __events = {}, __points = {}, __children = {}, __w = 0, __h = 0,
        __alpha = 1, __text = nil, __seq = H.seq }, widget_mt)
    if parent and parent.__children then parent.__children[#parent.__children + 1] = w end
    if name then _G[name] = w end
    return w
end
H.NewWidget = NewWidget

function Widget:GetObjectType() return self.__kind end
function Widget:IsObjectType(t) return self.__kind == t end
function Widget:GetName() return self.__name end
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p) self.__parent = p end
function Widget:Show() self.__shown = true end
-- as in the client, hiding a shown frame runs its OnHide
function Widget:Hide()
    local was = self.__shown
    self.__shown = false
    if was and self.__scripts and self.__scripts.OnHide then self.__scripts.OnHide(self) end
end
function Widget:SetShown(v) self.__shown = not not v end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible()
    local w = self
    while w do
        if w.__shown == false then return false end
        w = w.__parent
    end
    return true
end
function Widget:SetSize(w, h) self.__w, self.__h = w, h end
function Widget:SetWidth(w) self.__w = w end
function Widget:SetHeight(h) self.__h = h end
function Widget:GetWidth() return self.__w end
function Widget:GetHeight() return self.__h end
function Widget:GetSize() return self.__w, self.__h end
-- Scale is kept as __uiscale (render.py's map collector reads a different
-- field, __scale, which nothing sets): the book renderer draws with it.
function Widget:SetScale(s) self.__uiscale = s end
function Widget:GetScale() return self.__uiscale or 1 end
function Widget:GetEffectiveScale()
    local s, w = 1, self
    while w do s = s * (w.__uiscale or 1) w = w.__parent end
    return s
end
-- As in the client: a frame sits one level above its parent unless set.
function Widget:GetFrameLevel()
    if self.__level then return self.__level end
    return self.__parent and self.__parent.GetFrameLevel and (self.__parent:GetFrameLevel() + 1) or 0
end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetFrameStrata()
    if self.__strata then return self.__strata end
    return self.__parent and self.__parent.GetFrameStrata and self.__parent:GetFrameStrata() or "MEDIUM"
end
function Widget:GetAlpha() return self.__alpha end
function Widget:SetAlpha(a) self.__alpha = a end
function Widget:GetCenter() return 400, 300 end
function Widget:GetLeft() return 0 end
function Widget:GetRight() return self.__w end
function Widget:GetTop() return self.__h end
function Widget:GetBottom() return 0 end
function Widget:GetRect() return 0, 0, self.__w, self.__h end
function Widget:GetNumPoints() return #self.__points end
function Widget:SetPoint(...) self.__points[#self.__points + 1] = { ... } end
-- Fill the target: the real client sizes the region from it, and Map.lua
-- won't draw at all onto an overlay whose width reads 0.
function Widget:SetAllPoints(target)
    target = target or self.__parent
    self.__points = { { "ALL", target } }
    if target then self.__w, self.__h = target.__w, target.__h end
end
function Widget:SetDrawLayer(layer, sub) self.__drawLayer, self.__sub = layer, sub or 0 end
function Widget:GetDrawLayer() return self.__drawLayer or "ARTWORK", self.__sub or 0 end
function Widget:SetBlendMode(mode) self.__blend = mode end
function Widget:GetBlendMode() return self.__blend or "BLEND" end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:SetFontObject(font)
    if type(font) == "string" then font = _G[font] end
    self.__font = font and font.__name
    self.__fontObj = font
    self.__fontPath, self.__fontSize, self.__fontFlags = nil, nil, nil
end
function Widget:GetFontObject() return self.__fontObj end
function Widget:GetPoint(i) local p = self.__points[i or 1] if p then return unpack(p) end end
function Widget:IsMouseOver() return false end
function Widget:IsEnabled() return not self.__disabled end
function Widget:Enable()
    self.__disabled = false
    if self.__scripts.OnEnable then self.__scripts.OnEnable(self) end
end
function Widget:Disable()
    self.__disabled = true
    if self.__scripts.OnDisable then self.__scripts.OnDisable(self) end
end
function Widget:SetEnabled(on) if on then self:Enable() else self:Disable() end end
function Widget:GetChildren() return unpack(self.__children) end
function Widget:GetRegions() return end
function Widget:GetID() return self.__id or 0 end
function Widget:SetID(id) self.__id = id end

function Widget:SetScript(name, fn) self.__scripts[name] = fn end
function Widget:GetScript(name) return self.__scripts[name] end
function Widget:HasScript() return true end
function Widget:HookScript(name, fn)
    local old = self.__scripts[name]
    self.__scripts[name] = function(...) if old then old(...) end return fn(...) end
end
function Widget:RegisterEvent(ev) self.__events[ev] = true end
function Widget:RegisterUnitEvent(ev) self.__events[ev] = true end
function Widget:UnregisterEvent(ev) self.__events[ev] = nil end
function Widget:RegisterAllEvents() self.__allEvents = true end
function Widget:UnregisterAllEvents() self.__events = {} self.__allEvents = nil end
function Widget:IsEventRegistered(ev) return self.__events[ev] == true end

-- text
-- A font string with no font errors on SetText, as in the client ("Font
-- not set"; 3.8.5-test1's first opening broke on exactly that).
local function hasFont(w)
    local o = w
    for _ = 1, 8 do
        if not o then return false end
        if o.__fontPath then return true end
        if o ~= w and o.__name then return true end -- a font object (GameFontNormal...)
        o = o.__fontObj or (type(o.__font) == "string" and o.__font ~= o.__name and _G[o.__font]) or nil
    end
    return false
end
H.hasFont = hasFont
function Widget:SetText(t)
    if self.__kind == "FontString" and t ~= nil and not hasFont(self) then
        error("FontString:SetText(): Font not set", 2)
    end
    self.__text = t ~= nil and tostring(t) or nil -- the client takes numbers too
end
function Widget:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function Widget:GetText() return self.__text end
-- Text metrics. Plain tests keep the old fixed guess (6 units a character,
-- one 12-unit line), which their layouts were written against. The book
-- renderer (book_render.py) sets H.measure and H.lines to real font
-- metrics, so the code lays itself out as it would in the client.
local function fontOf(w)
    local o = w
    for _ = 1, 8 do
        if not o then break end
        if o.__fontPath then return o.__fontPath, o.__fontSize, o.__fontFlags or "" end
        o = o.__fontObj or (type(o.__font) == "string" and o.__font ~= o.__name and _G[o.__font]) or nil
    end
    return "Fonts\\FRIZQT__.TTF", 12, ""
end
H.fontOf = fontOf
function Widget:GetStringWidth()
    if H.measure and self.__text then
        local path, size = fontOf(self)
        return H.measure(path, size, self.__text)
    end
    return #(self.__text or "") * 6
end
Widget.GetUnboundedStringWidth = Widget.GetStringWidth
function Widget:GetNumLines()
    if H.lines and self.__text then
        local path, size = fontOf(self)
        return H.lines(path, size, self.__text, self.__w or 0, self.__wrap ~= false)
    end
    return 1
end
function Widget:GetStringHeight()
    if H.lines and self.__text then
        local _, size = fontOf(self)
        local n = self:GetNumLines()
        if H.height then return H.height(n, size, self.__spacing or 0) end
        return n * size + (n - 1) * (self.__spacing or 0)
    end
    return 12
end
function Widget:GetFont() return fontOf(self) end
-- The client's SetFont returned false for the addon's own .ttf files even
-- though they drew (3.8.4 probe), so nothing may rely on its result.
-- And it didn't apply them either: an addon's own .ttf starts loading at
-- its first SetFont, which returns false and leaves the string as it was;
-- once loaded (here: from the next call on), SetFont works.
H.fontsLoaded = {}
function Widget:SetFont(path, size, flags)
    if type(path) == "string" and path:lower():find("interface\\addons\\", 1, true) then
        local key = path:lower()
        if not H.fontsLoaded[key] then
            H.fontsLoaded[key] = true
            return false
        end
    end
    self.__fontPath, self.__fontSize, self.__fontFlags = path, size, flags or ""
    return true
end
function Widget:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a or 1 } end
function Widget:GetTextColor()
    local o = self
    while o and not o.__textColor do o = o.__fontObj end
    return unpack(o and o.__textColor or { 1, 1, 1, 1 })
end
function Widget:SetShadowColor(r, g, b, a) self.__shadowColor = { r, g, b, a or 1 } end
function Widget:GetShadowColor() return unpack(self.__shadowColor or { 0, 0, 0, 1 }) end
function Widget:SetShadowOffset(x, y) self.__shadowOffset = { x or 0, y or 0 } end
function Widget:GetShadowOffset() local o = self.__shadowOffset or { 0, 0 } return o[1], o[2] end
function Widget:SetJustifyH(j) self.__justifyH = j end
function Widget:GetJustifyH() return self.__justifyH or "CENTER" end
function Widget:SetJustifyV(j) self.__justifyV = j end
function Widget:GetJustifyV() return self.__justifyV or "MIDDLE" end
function Widget:SetSpacing(s) self.__spacing = s end
function Widget:GetSpacing() return self.__spacing or 0 end
function Widget:SetWordWrap(on) self.__wrap = not not on end
function Widget:GetWordWrap() return self.__wrap ~= false end
function Widget:GetNumber() return tonumber(self.__text) or 0 end
-- checks / sliders
function Widget:SetChecked(v) self.__checked = not not v end
function Widget:GetChecked() return self.__checked or false end
function Widget:SetValue(v) self.__value = v end
function Widget:GetValue() return self.__value or 0 end
function Widget:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function Widget:SetMinMaxValues(a, b) self.__min, self.__max = a, b end

-- drawing: recorded so a render can be produced from them
function Widget:SetTexture(t) self.__texture = t end
function Widget:GetTexture() return self.__texture end
function Widget:SetColorTexture(r, g, b, a) self.__color = { r, g, b, a or 1 } self.__texture = "color" end
function Widget:SetVertexColor(r, g, b, a) self.__vertex = { r, g, b, a or 1 } end
function Widget:GetVertexColor() local v = self.__vertex or { 1, 1, 1, 1 } return unpack(v) end
function Widget:SetTexCoord(...) self.__texcoord = { ... } end
function Widget:SetStartPoint(rel, frame, x, y) self.__start = { x or 0, y or 0 } end
function Widget:SetEndPoint(rel, frame, x, y) self.__end = { x or 0, y or 0 } end
function Widget:SetThickness(t) self.__thick = t end
function Widget:GetThickness() return self.__thick or 1 end
function Widget:SetRotation(r) self.__rotation = r end
function Widget:GetRotation() return self.__rotation or 0 end
function Widget:GetTexCoord() return unpack(self.__texcoord or { 0, 1, 0, 1 }) end
function Widget:SetDesaturated(on) self.__desat = not not on end
function Widget:IsDesaturated() return self.__desat or false end
function Widget:SetAtlas(name) self.__texture = "atlas:" .. tostring(name) end
-- SetGradient(orientation, minColor, maxColor) with CreateColor objects: the
-- probe found this works on Forever (SetGradientAlpha doesn't exist).
function Widget:SetGradient(orient, a, b)
    self.__gradient = { orient, { a.r, a.g, a.b, a.a or 1 }, { b.r, b.g, b.b, b.a or 1 } }
end
function Widget:AddMaskTexture(m)
    self.__masks = self.__masks or {}
    self.__masks[#self.__masks + 1] = m
end
function Widget:RemoveMaskTexture(m)
    for i, x in ipairs(self.__masks or {}) do if x == m then table.remove(self.__masks, i) break end end
end
-- ScrollFrame: the child is drawn at the frame's top-left, moved up by the
-- scroll, and clipped to the frame (book_render.py does both).
function Widget:SetScrollChild(c) self.__scrollChild = c c.__scrollParent = self end
function Widget:GetScrollChild() return self.__scrollChild end
function Widget:SetVerticalScroll(v) self.__vscroll = v end
function Widget:GetVerticalScroll() return self.__vscroll or 0 end
function Widget:GetNumMaskTextures() return #(self.__masks or {}) end
-- BackdropTemplate
function Widget:SetBackdrop(t) self.__backdrop = t end
function Widget:GetBackdrop() return self.__backdrop end
function Widget:SetBackdropColor(r, g, b, a) self.__backdropColor = { r, g, b, a or 1 } end
function Widget:SetBackdropBorderColor(r, g, b, a) self.__backdropBorder = { r, g, b, a or 1 } end

local function child(kind)
    -- CreateTexture(name, layer, inherits, sublevel), CreateLine(name, layer, ...)
    return function(self, name, layer, inherits, sub)
        -- NewWidget numbers it (__seq): creation order breaks ties within a layer, as in the client
        local w = NewWidget(kind, name, self)
        w.__layer = true
        if kind == "FontString" then w.__font = inherits w.__fontObj = inherits and _G[inherits] end
        w.__drawLayer, w.__sub = layer or "ARTWORK", sub or 0
        return w
    end
end
Widget.CreateTexture = child("Texture")
Widget.CreateMaskTexture = child("MaskTexture")
Widget.CreateFontString = child("FontString")
Widget.CreateLine = child("Line")
Widget.CreateAnimationGroup = child("AnimationGroup")
-- CreateAnimation takes the animation TYPE first ("Alpha", "Scale"...), then
-- the name. Treating the type as a name would invent globals called Alpha.
function Widget:CreateAnimation(animType, name)
    local w = NewWidget(animType or "Animation", name, self)
    w.__layer = true
    return w
end

-- Sizes the client's templates give a frame before the addon sizes it.
local TEMPLATE_SIZE = { UIPanelCloseButton = { 32, 32 }, UICheckButtonTemplate = { 32, 32 },
    UIRadioButtonTemplate = { 16, 16 } }
function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind or "Frame", name, parent)
    w.__template = template
    local size = template and TEMPLATE_SIZE[template]
    if size then w.__w, w.__h = size[1], size[2] end
    H.frames[#H.frames + 1] = w
    if template and template:find("Slider") then w.__min, w.__max = 0, 1 end
    if template and template:find("CheckButton") then w.Text = NewWidget("FontString", nil, w) end
    -- the client's close button hides its parent through HideUIPanel
    if template == "UIPanelCloseButton" then
        w:SetScript("OnClick", function(self) HideUIPanel(self:GetParent()) end)
    end
    return w
end

-- the secure panel manager won't act in combat (silently, as in the client)
HideUIPanel = function(f) if not InCombatLockdown() then f:Hide() end end

hooksecurefunc = function(a, b, c)
    local tbl, name, fn = a, b, c
    if type(a) == "string" then tbl, name, fn = _G, a, b end
    local old = tbl[name]
    tbl[name] = function(...)
        local r = { old(...) }
        fn(...)
        return unpack(r)
    end
end

-- Standard frames the addon reaches for.
UIParent = NewWidget("Frame", "UIParent")
UIParent.__w, UIParent.__h = 1920, 1080
WorldFrame = NewWidget("Frame", "WorldFrame")
Minimap = NewWidget("Minimap", "Minimap")
GameTooltip = NewWidget("GameTooltip", "GameTooltip", UIParent)
DEFAULT_CHAT_FRAME = NewWidget("ScrollingMessageFrame", "ChatFrame1")
function DEFAULT_CHAT_FRAME:AddMessage(msg) H.chat[#H.chat + 1] = tostring(msg) end
ZoneTextFrame = NewWidget("Frame", "ZoneTextFrame", UIParent)
ZoneTextString = NewWidget("FontString", "ZoneTextString", ZoneTextFrame)
SubZoneTextString = NewWidget("FontString", "SubZoneTextString", ZoneTextFrame)
RaidWarningFrame = NewWidget("Frame", "RaidWarningFrame", UIParent)
-- On-screen notices (Warpath's banners fall back to UIErrorsFrame): recorded, not chat.
H.notices = {}
UIErrorsFrame = NewWidget("MessageFrame", "UIErrorsFrame", UIParent)
function UIErrorsFrame:AddMessage(msg) H.notices[#H.notices + 1] = tostring(msg) end

-- The world map: a canvas Warpath draws onto, in map-relative coordinates.
WorldMapFrame = NewWidget("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.ScrollContainer = NewWidget("ScrollFrame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = NewWidget("Frame", nil, WorldMapFrame.ScrollContainer)
WorldMapFrame.ScrollContainer.Child.__w, WorldMapFrame.ScrollContainer.Child.__h = 1002, 668
WorldMapFrame.ScrollContainer.__w, WorldMapFrame.ScrollContainer.__h = 1002, 668
WorldMapFrame.__shown = false
function WorldMapFrame:GetMapID() return H.mapShown or H.player.mapID end
function WorldMapFrame:GetCanvas() return self.ScrollContainer.Child end
function WorldMapFrame:GetCanvasContainer() return self.ScrollContainer end
function WorldMapFrame.ScrollContainer:GetCanvasScale() return 1 end
function WorldMapFrame:AddDataProvider() end
function WorldMapFrame:RemoveDataProvider() end

-- Units and the player --------------------------------------------------------------
local function isPlayer(u) return u == "player" end
UnitName = function(u) if isPlayer(u) then return H.player.name end return H.units and H.units[u] and H.units[u].name end
UnitFullName = function(u) if isPlayer(u) then return H.player.name, H.player.realm end end
UnitGUID = function(u) if isPlayer(u) then return "Player-0-00000001" end end
UnitFactionGroup = function(u) if isPlayer(u) then return H.player.faction, H.player.faction end end
UnitClass = function(u) if isPlayer(u) then return H.player.class, H.player.class end end
UnitRace = function(u) if isPlayer(u) then return H.player.race, H.player.race end end
UnitLevel = function(u) if isPlayer(u) then return H.player.level end return 0 end
UnitExists = function(u) return isPlayer(u) or (H.units and H.units[u] ~= nil) or false end
UnitIsPlayer = function(u) return isPlayer(u) end
UnitIsDeadOrGhost = function(u) return isPlayer(u) and (H.dead or H.ghost) or false end
UnitIsDead = function() return false end
UnitIsGhost = function(u) return isPlayer(u) and H.ghost or false end
UnitIsEnemy = function() return false end
UnitIsFriend = function() return true end
UnitCanAttack = function() return false end
UnitIsPVP = function() return false end
UnitHealth = function() return 100 end
UnitHealthMax = function() return 100 end
UnitAffectingCombat = function() return H.combat or false end
UnitOnTaxi = function() return false end
UnitPosition = function() return 0, 0, 0, 0 end
UnitInParty = function() return false end
UnitInRaid = function() return nil end
UnitIsUnit = function(a, b) return a == b end
InCombatLockdown = function() return false end
IsInGuild = function() return H.player.guild ~= nil end
GetGuildInfo = function(u) if isPlayer(u) then return H.player.guild, "Member", 1 end end
GetNormalizedRealmName = function() return "" end   -- WoW Forever: empty
GetRealmName = function() return "" end
IsInInstance = function() if H.instance then return true, "pvp" end return false, "none" end
GetInstanceInfo = function() if H.instance then return "Alterac Valley", "pvp" end return "Kalimdor", "none" end
IsInGroup = function() return false end
IsInRaid = function() return false end
GetNumGroupMembers = function() return 0 end
GetZoneText = function() return H.zone or "Felwood" end
GetRealZoneText = GetZoneText
GetSubZoneText = function() return H.subzone or "" end
GetMinimapZoneText = GetSubZoneText
GetZonePVPInfo = function() return H.pvpType end
GetPVPLifetimeStats = function() return H.hk or 0, 0, 0 end
GetPVPSessionStats = function() return 0, 0 end
GetStatistic = function() return "0" end
IsResting = function() return false end
IsMounted = function() return false end
IsFlying = function() return false end
IsFalling = function() return false end
GetUnitSpeed = function() return 0 end
GetFramerate = function() return 60 end
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "00000", "Nov 1 2026", 16001 end
issecretvalue = nil

-- Maps --------------------------------------------------------------------------------
C_Map = {}
local MAPS = {
    [1448] = { name = "Felwood", mapType = 3, parentMapID = 1414 },
    [1414] = { name = "Kalimdor", mapType = 2, parentMapID = 947 },
    [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [947] = { name = "Azeroth", mapType = 1 },
    [1440] = { name = "Ashenvale", mapType = 3, parentMapID = 1414 },
    [1424] = { name = "Hillsbrad Foothills", mapType = 3, parentMapID = 1415 },
    [1416] = { name = "Alterac Mountains", mapType = 3, parentMapID = 1415 },
    [2482] = { name = "Mount Hyjal", mapType = 3, parentMapID = 1414 },
}
H.maps = MAPS
-- The other zones of the vanilla world, by their client uiMapIDs, so text
-- built from map names (campaign titles, deed headings) reads as in game.
-- Mount Hyjal (2482) is Forever's own (CLAUDE.local.md).
local ZONES = {
    [1411] = "Durotar", [1412] = "Mulgore", [1413] = "The Barrens", [1417] = "Arathi Highlands",
    [1418] = "Badlands", [1419] = "Blasted Lands", [1420] = "Tirisfal Glades", [1421] = "Silverpine Forest",
    [1422] = "Western Plaguelands", [1423] = "Eastern Plaguelands", [1425] = "The Hinterlands",
    [1426] = "Dun Morogh", [1427] = "Searing Gorge", [1428] = "Burning Steppes", [1429] = "Elwynn Forest",
    [1430] = "Deadwind Pass", [1431] = "Duskwood", [1432] = "Loch Modan", [1433] = "Redridge Mountains",
    [1434] = "Stranglethorn Vale", [1435] = "Swamp of Sorrows", [1436] = "Westfall", [1437] = "Wetlands",
    [1438] = "Teldrassil", [1439] = "Darkshore", [1441] = "Thousand Needles", [1442] = "Stonetalon Mountains",
    [1443] = "Desolace", [1444] = "Feralas", [1445] = "Dustwallow Marsh", [1446] = "Tanaris", [1447] = "Azshara",
    [1449] = "Un'Goro Crater", [1450] = "Moonglade", [1451] = "Silithus", [1452] = "Winterspring",
    [1453] = "Stormwind City", [1454] = "Orgrimmar", [1455] = "Ironforge", [1456] = "Thunder Bluff",
    [1457] = "Darnassus", [1458] = "Undercity", [1459] = "Alterac Valley", [1460] = "Warsong Gulch",
    [1461] = "Arathi Basin",
}
local EASTERN = { [1416] = true, [1417] = true, [1418] = true, [1419] = true, [1420] = true, [1421] = true,
    [1422] = true, [1423] = true, [1424] = true, [1425] = true, [1426] = true, [1427] = true, [1428] = true,
    [1429] = true, [1430] = true, [1431] = true, [1432] = true, [1433] = true, [1434] = true, [1435] = true,
    [1436] = true, [1437] = true, [1453] = true, [1455] = true, [1458] = true }
for id, name in pairs(ZONES) do
    if not MAPS[id] then MAPS[id] = { name = name, mapType = 3, parentMapID = EASTERN[id] and 1415 or 1414 } end
end
C_Map.GetBestMapForUnit = function(u) if isPlayer(u) then return H.player.mapID end end
C_Map.GetMapInfo = function(id)
    -- The client raises on a missing map ID rather than returning nil
    -- (3.8.3-test6's hidden map broke on exactly that).
    if type(id) ~= "number" then error("bad argument #1 to 'GetMapInfo' (number expected)", 2) end
    local m = MAPS[id]
    if not m then
        -- Real saved data mentions maps we don't list; answer generically
        -- rather than pretend they don't exist.
        if type(id) == "number" and id > 0 then return { mapID = id, name = "Map " .. id, mapType = 3, parentMapID = 1414 } end
        return nil
    end
    return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID }
end
local function vec(x, y)
    return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end
CreateVector2D = vec
C_Map.GetPlayerMapPosition = function(id, u) if isPlayer(u) then return vec(H.player.x, H.player.y) end end
-- Every map 4000 yards wide (about a zone) unless a test says otherwise
-- (H.mapYards[id], e.g. a city): Linger.lua measures areas in yards.
C_Map.GetWorldPosFromMapPos = function(id, pos)
    local w = (H.mapYards and H.mapYards[id]) or 4000
    return 0, vec(pos.x * w, pos.y * w * 2 / 3)
end
-- Where one map sits on another. Map.lua draws EVERY zone with data onto
-- the viewed map through this, so a wrong answer stacks other zones' trails
-- on top of the one you're looking at. (The first version of this stub
-- returned "fills the whole map" for every pair, and a Felwood render came
-- out 95% other zones.) So: only real rects, captured from the client into
-- H.rects; for any pair we don't know, say "no overlap", which leaves that
-- zone out of the render instead of putting it in the wrong place.
-- The inverse, onto a chosen map (Spirits.lua places world spots this way).
-- Off unless a test sets H.worldMaps: every stub map sits at the same world
-- place, so the built-in graveyards would land on every map and in every
-- other test's drawing.
C_Map.GetMapPosFromWorldPos = function(cont, pos, id)
    if not H.worldMaps then return nil end
    local w = (H.mapYards and H.mapYards[id]) or 4000
    return id, vec(pos.x / w, pos.y / (w * 2 / 3))
end
-- Death (Spirits.lua): where you'll release to, H.release = { x, y } on the map asked about.
C_DeathInfo = {
    GetDeathReleasePosition = function(id) if H.release then return vec(H.release[1], H.release[2]) end end,
    GetGraveyardsForMap = function() return {} end,
}
C_Map.GetMapRectOnMap = function(child, parent)
    if child == parent then return 0, 1, 0, 1 end
    if parent == 947 and not (H.rects and H.rects[child] and H.rects[child][947]) and H.worldRects[child] then
        local r = H.worldRects[child]
        return r[1], r[2], r[3], r[4]
    end
    local r = H.rects and H.rects[child] and H.rects[child][parent]
    if r then return r[1], r[2], r[3], r[4] end
    -- Both maps were in a capture: the client said 0,0,0,0, i.e. no overlap.
    if H.rectsKnown and H.rectsKnown[child] and H.rectsKnown[parent] then return 0, 0, 0, 0 end
    H.rectMisses = H.rectMisses or {}
    H.rectMisses[child .. ">" .. parent] = true
    return nil
end
-- Which map is at a point of another (Spirits.lua: which zone a graveyard is
-- in). Off unless a test sets H.zoneAt(id, x, y); nil means "can't say".
C_Map.GetMapInfoAtPosition = function(id, x, y)
    local z = H.zoneAt and H.zoneAt(id, x, y)
    if z then return C_Map.GetMapInfo(z) end
end
C_Map.GetMapChildrenInfo = function() return {} end
-- Zones and continents on the world map (947), which the 2026-11-23 capture
-- didn't cover. NOT captured: the four zones of Lethality's 25 November
-- campaign are where the design render placed them by eye on Joe's world
-- map screenshot (book/refine.py ROUTE, its canvas at 208-1792 x 61-1117 of
-- world.png), each as a tiny rect round that point; the continents are
-- fitted to those points through their zones' captured rects on 1414/1415.
-- Re-capture in game for the real values (see the build report).
H.worldRects = {
    [1427] = { 0.7470, 0.7480, 0.5308, 0.5318 },   -- Searing Gorge (1392, 622)
    [1443] = { 0.1636, 0.1646, 0.5743, 0.5753 },   -- Desolace (468, 668)
    [1452] = { 0.2874, 0.2884, 0.2940, 0.2950 },   -- Winterspring (664, 372)
    [1445] = { 0.2899, 0.2909, 0.6292, 0.6302 },   -- Dustwallow Marsh (668, 726)
    [1414] = { -0.182, 0.644, 0.071, 0.897 },      -- Kalimdor, fitted
    [1415] = { 0.338, 1.164, 0.027, 0.854 },       -- Eastern Kingdoms, fitted
}
-- The world map's art (probe: 12 tiles of 256 px, layer 1002 x 668). The
-- client gives file ids; here, names the book renderer cuts from Joe's
-- world map screenshot when it has one.
C_Map.GetMapArtLayers = function(id)
    return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256, minScale = 1, maxScale = 1 } }
end
C_Map.GetMapArtLayerTextures = function(id, layer)
    local out = {}
    for i = 1, 12 do out[i] = "worldmap:" .. id .. ":" .. i end
    return out
end
GetCursorPosition = function() return 0, 0 end
C_Map.GetMapGroupID = function() return nil end
C_Map.SetUserWaypoint = function(p) H.waypoint = p end
C_Map.ClearUserWaypoint = function() H.waypoint = nil end
C_Map.CanSetUserWaypointOnMap = function() return true end
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, position = vec(x, y) } end }
C_TaxiMap = { GetAllTaxiNodes = function() return {} end }

C_NamePlate = {
    GetNamePlates = function() return {} end,
    GetNamePlateForUnit = function() return nil end,
}

-- Addon messages -----------------------------------------------------------------------
C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    IsAddonMessagePrefixRegistered = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target)
        H.sent[#H.sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }
        return true
    end,
    InChatMessagingLockdown = function() return H.lockdown or false end,
}
SendAddonMessage = C_ChatInfo.SendAddonMessage
SendChatMessage = function(msg, channel, _, target)
    H.said = H.said or {}
    H.said[#H.said + 1] = { msg = msg, channel = channel, target = target }
end

-- Addons ----------------------------------------------------------------------------------
C_AddOns = {
    GetAddOnMetadata = function(addon, field) return H.meta and H.meta[field] end,
    IsAddOnLoaded = function(name) return H.loaded and H.loaded[name] or false end,
    GetAddOnEnableState = function() return 0 end,
}
GetAddOnMetadata = C_AddOns.GetAddOnMetadata
IsAddOnLoaded = C_AddOns.IsAddOnLoaded

-- Sound, screenshots, misc ------------------------------------------------------------------
PlaySound = function(id) H.sounds = H.sounds or {} H.sounds[#H.sounds + 1] = id end
PlaySoundFile = function(f) H.sounds = H.sounds or {} H.sounds[#H.sounds + 1] = f end
Screenshot = function() H.shots = (H.shots or 0) + 1 end
SOUNDKIT = setmetatable({}, { __index = function(_, k) return k end })
geterrorhandler = function() return function(e) H.errors = H.errors or {} H.errors[#H.errors + 1] = e end end
securecall = function(f, ...) return f(...) end
-- The game's class colours (the design renders' TRUE table uses the same),
-- so names in class colour render as in game; any other token reads white.
local function ClassCol(r, g, b)
    local hex = ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
    return { r = r, g = g, b = b, colorStr = hex, GenerateHexColor = function() return hex end }
end
RAID_CLASS_COLORS = setmetatable({
    WARRIOR = ClassCol(0.78, 0.61, 0.43), ROGUE = ClassCol(1, 0.96, 0.41), MAGE = ClassCol(0.41, 0.8, 0.94),
    DRUID = ClassCol(1, 0.49, 0.04), SHAMAN = ClassCol(0, 0.44, 0.87), PALADIN = ClassCol(0.96, 0.55, 0.73),
    PRIEST = ClassCol(1, 1, 1), HUNTER = ClassCol(0.67, 0.83, 0.45), WARLOCK = ClassCol(0.58, 0.51, 0.79),
}, { __index = function() return ClassCol(1, 1, 1) end })
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
FACTION_HORDE, FACTION_ALLIANCE = "Horde", "Alliance"
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
FauxScrollFrame_Update = function(frame, numItems, numToDisplay)
    frame.__fauxTotal, frame.__fauxShown = numItems, numToDisplay
end
FauxScrollFrame_GetOffset = function(frame) return frame.__fauxOffset or 0 end
FauxScrollFrame_SetOffset = function(frame, offset) frame.__fauxOffset = offset end
FauxScrollFrame_OnVerticalScroll = function(frame, value, itemHeight, update)
    frame.__fauxOffset = math.floor(value / itemHeight + 0.5)
    if update then update() end
end
SlashCmdList = {}
hash_SlashCmdList = {}
StaticPopupDialogs = {}
StaticPopup_Show = function() end
Settings = nil      -- the modern Settings panel isn't in this client
MenuUtil = nil      -- let Warpath fall back to UIDropDownMenu
UIDropDownMenu_Initialize = function() end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
ToggleDropDownMenu = function() end
CloseDropDownMenus = function() end
-- The client's font objects. Paths and sizes as the 3.8.4 probe read them
-- in game; GameFontNormalHuge, GameFontHighlight*, GameFontDisable and the
-- colours and shadows are the stock FontStyles values, not probed.
local function FontObject(name, path, size, flags, color, shadow)
    local f = NewWidget("Font", name)
    f.__fontPath, f.__fontSize, f.__fontFlags = path, size, flags or ""
    f.__textColor = color
    if shadow then f.__shadowOffset, f.__shadowColor = { 1, -1 }, { 0, 0, 0, 1 } end
    return f
end
local FRIZ, MORPH = "Fonts\\FRIZQT__.TTF", "Fonts\\MORPHEUS.ttf"
local GOLD, WHITE, BLACK = { 1, 0.82, 0, 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 1 }
FontObject("GameFontNormal", FRIZ, 12, "", GOLD, true)
FontObject("GameFontHighlight", FRIZ, 12, "", WHITE, true)
FontObject("GameFontNormalSmall", FRIZ, 10, "", GOLD, true)
FontObject("GameFontHighlightSmall", FRIZ, 10, "", WHITE, true)
FontObject("GameFontNormalLarge", FRIZ, 16, "", GOLD, true)
FontObject("GameFontNormalHuge", FRIZ, 20, "", GOLD, true)
FontObject("GameFontDisable", FRIZ, 12, "", { 0.5, 0.5, 0.5, 1 }, true)
FontObject("QuestFont", FRIZ, 13, "", BLACK)
FontObject("QuestTitleFont", MORPH, 18, "", BLACK)
FontObject("QuestFontNormalSmall", FRIZ, 12, "", BLACK)
FontObject("Fancy22Font", MORPH, 22, "", BLACK)
FontObject("SystemFont_Med1", FRIZ, 12, "", WHITE)
FontObject("NumberFontNormal", "Fonts\\ARIALN.TTF", 14, "OUTLINE", WHITE)
-- Colours for SetGradient (the probe found CreateColor on Forever).
CreateColor = function(r, g, b, a)
    local c = { r = r, g = g, b = b, a = a or 1 }
    function c:GetRGBA() return self.r, self.g, self.b, self.a end
    function c:GetRGB() return self.r, self.g, self.b end
    return c
end

-- Harness controls -----------------------------------------------------------------------------
function H.Fire(event, ...)
    for _, f in ipairs(H.frames) do
        if (f.__events[event] or f.__allEvents) and f.__scripts.OnEvent then
            f.__scripts.OnEvent(f, event, ...)
        end
    end
end

-- Advance both clocks, running due timers in order. OnUpdate scripts are not
-- driven: Warpath does its sampling on a C_Timer ticker.
function H.Advance(seconds)
    local target = H.gt + seconds
    while true do
        local nextT, nextI
        for i, t in ipairs(H.timers) do
            if not t.cancelled and t.due <= target and (not nextT or t.due < nextT.due) then nextT, nextI = t, i end
        end
        if not nextT then break end
        H.now = H.now + (nextT.due - H.gt)
        H.gt = nextT.due
        if nextT.interval and (nextT.left == nil or nextT.left > 1) then
            nextT.due = nextT.due + nextT.interval
            if nextT.left then nextT.left = nextT.left - 1 end
        else
            table.remove(H.timers, nextI)
        end
        nextT.fn(nextT)
    end
    H.now = H.now + (target - H.gt)
    H.gt = target
end
