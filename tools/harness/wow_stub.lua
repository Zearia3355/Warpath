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
widget_mt.__index = function(self, key)
    local m = Widget[key]
    if m ~= nil then return m end
    if type(key) == "string" and key:match("^%u") then
        H.unknownMethods[key] = (H.unknownMethods[key] or 0) + 1
        return function() end
    end
    return nil
end

local function NewWidget(kind, name, parent)
    local w = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = true,
        __scripts = {}, __events = {}, __points = {}, __children = {}, __w = 0, __h = 0,
        __alpha = 1, __text = nil }, widget_mt)
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
function Widget:GetScale() return 1 end
function Widget:GetEffectiveScale() return 1 end
function Widget:GetFrameLevel() return self.__level or 1 end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameStrata() return "MEDIUM" end
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
function Widget:SetFontObject(font) self.__font = font and font.__name end
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
function Widget:SetText(t) self.__text = t ~= nil and tostring(t) or nil end -- the client takes numbers too
function Widget:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return #(self.__text or "") * 6 end
function Widget:GetStringHeight() return 12 end
function Widget:GetUnboundedStringWidth() return #(self.__text or "") * 6 end
function Widget:GetNumLines() return 1 end
function Widget:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Widget:SetTextColor(r, g, b, a) self.__textColor = { r, g, b, a or 1 } end
function Widget:GetTextColor() return unpack(self.__textColor or { 1, 1, 1, 1 }) end
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

local seq = 0
local function child(kind)
    -- CreateTexture(name, layer, inherits, sublevel), CreateLine(name, layer, ...)
    return function(self, name, layer, inherits, sub)
        local w = NewWidget(kind, name, self)
        w.__layer = true
        if kind == "FontString" then w.__font = inherits end
        w.__drawLayer, w.__sub = layer or "ARTWORK", sub or 0
        seq = seq + 1
        w.__seq = seq   -- creation order breaks ties within a layer, as in the client
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

function CreateFrame(kind, name, parent, template)
    local w = NewWidget(kind or "Frame", name, parent)
    w.__template = template
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
    local r = H.rects and H.rects[child] and H.rects[child][parent]
    if r then return r[1], r[2], r[3], r[4] end
    -- Both maps were in a capture: the client said 0,0,0,0, i.e. no overlap.
    if H.rectsKnown and H.rectsKnown[child] and H.rectsKnown[parent] then return 0, 0, 0, 0 end
    H.rectMisses = H.rectMisses or {}
    H.rectMisses[child .. ">" .. parent] = true
    return nil
end
C_Map.GetMapChildrenInfo = function() return {} end
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
RAID_CLASS_COLORS = setmetatable({}, { __index = function()
    return { r = 1, g = 1, b = 1, colorStr = "ffffffff", GenerateHexColor = function() return "ffffffff" end }
end })
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
GameFontNormal = NewWidget("Font", "GameFontNormal")
GameFontHighlight = NewWidget("Font", "GameFontHighlight")
GameFontNormalLarge = NewWidget("Font", "GameFontNormalLarge")
GameFontHighlightSmall = NewWidget("Font", "GameFontHighlightSmall")
GameFontNormalSmall = NewWidget("Font", "GameFontNormalSmall")

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
