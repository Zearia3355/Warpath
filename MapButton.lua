-- Warpath: MapButton
-- A small round button in the world map's top-right corner. Left-click hides
-- or shows everything Warpath draws; right-click picks layers. Shift-drag
-- moves it; the spot is saved.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Print = ns.Print

local cfg
ns.OnBind(function() cfg = ns.cfg end)

local button

local function SetShown(on)
    cfg.shown = on and true or false
    Print("Warpath on the map " .. (cfg.shown and "shown." or "hidden (still recording)."))
    ns.Redraw()
end

local function SetLayer(key, on)
    cfg.layers[key] = on and true or false
    S.dirty = true
    ns.Redraw()
end

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Warpath", 1, 0.82, 0)
    if S.inInstance then
        GameTooltip:AddLine("Off in battlegrounds", 0.7, 0.7, 0.7)
    else
        GameTooltip:AddLine(cfg.shown and "Shown on the map" or "Hidden (still recording)", 1, 1, 1)
        GameTooltip:AddLine(cfg.shown and "Left-click: hide" or "Left-click: show", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: layers", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift-drag: move this button", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- A small menu: items = { { text, checked = fn|nil, func } }. Uses the newer
-- menu API when the client has it, else the classic dropdown.
local dropdown, dropItems, dropTitle
local function Menu(owner, title, items)
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(owner, function(_, root)
            root:CreateTitle(title)
            for _, it in ipairs(items) do
                if it.checked then
                    root:CreateCheckbox(it.text, it.checked, it.func)
                else
                    root:CreateButton(it.text, it.func)
                end
            end
        end)
        return true
    end
    if not (UIDropDownMenu_Initialize and ToggleDropDownMenu and UIDropDownMenu_AddButton) then return false end
    dropItems, dropTitle = items, title
    if not dropdown then
        dropdown = CreateFrame("Frame", "WarpathMenu", UIParent, "UIDropDownMenuTemplate")
        UIDropDownMenu_Initialize(dropdown, function(_, level)
            local head = UIDropDownMenu_CreateInfo()
            head.text, head.isTitle, head.notCheckable = dropTitle, true, true
            UIDropDownMenu_AddButton(head, level)
            for _, it in ipairs(dropItems) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = it.text
                if it.checked then
                    info.checked = it.checked()
                    info.isNotRadio = true
                    info.keepShownOnClick = true
                else
                    info.notCheckable = true
                end
                info.func = function() it.func() end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
    end
    ToggleDropDownMenu(1, nil, dropdown, owner, 0, 0)
    return true
end

local function LayerMenu(owner)
    local items = {}
    for _, key in ipairs(C.LAYERS) do
        items[#items + 1] = { text = C.LAYER_LABELS[key],
            checked = function() return cfg.layers[key] end,
            func = function() SetLayer(key, not cfg.layers[key]) end }
    end
    if not Menu(owner, "Warpath layers", items) then Print("layers: /warpath layer <name> [on|off]") end
end

local function Place()
    local host = WorldMapFrame.ScrollContainer or WorldMapFrame
    button:ClearAllPoints()
    local pos = cfg.mapButton
    if pos and pos.x and pos.y then
        button:SetPoint("TOPRIGHT", host, "TOPRIGHT", pos.x, pos.y)
    else
        button:SetPoint("TOPRIGHT", host, "TOPRIGHT", -6, -6)
    end
end

local function Refresh()
    if not button then return end
    local off = S.inInstance or not cfg.shown
    button.icon:SetDesaturated(off)
    button.icon:SetVertexColor(S.inInstance and 0.5 or 1, S.inInstance and 0.5 or 1, S.inInstance and 0.5 or 1)
end

-- The first time you open the map after the update: a short pulse and the tooltip, once.
local function Introduce()
    if cfg.mapButtonSeen or not button:IsVisible() then return end
    cfg.mapButtonSeen = true
    local ag = button.pulse
    if ag then ag:Play() end
    Tooltip(button)
    C_Timer.After(5, function()
        if GameTooltip:GetOwner() == button and not button:IsMouseOver() then GameTooltip:Hide() end
    end)
end

local function SetupMapButton()
    if button or not WorldMapFrame then return end
    local host = WorldMapFrame.ScrollContainer or WorldMapFrame
    button = CreateFrame("Button", "WarpathMapButton", host)
    button:SetSize(31, 31)
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel(host:GetFrameLevel() + 3000)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)
    button:SetClampedToScreen(true)

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetTexture(C.TEX_SWORDS)
    button.icon:SetSize(19, 19)
    button.icon:SetPoint("CENTER", 0, 1)
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    -- pulse for the first showing
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 2)
    glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    glow:SetBlendMode("ADD")
    glow:SetAllPoints()
    glow:SetAlpha(0)
    if glow.CreateAnimationGroup or button.CreateAnimationGroup then
        local ag = button:CreateAnimationGroup()
        ag:SetLooping("NONE")
        for i = 1, 3 do
            local up = ag:CreateAnimation("Alpha")
            up:SetTarget(glow)
            up:SetFromAlpha(0)
            up:SetToAlpha(1)
            up:SetDuration(0.4)
            up:SetOrder(i * 2 - 1)
            local down = ag:CreateAnimation("Alpha")
            down:SetTarget(glow)
            down:SetFromAlpha(1)
            down:SetToAlpha(0)
            down:SetDuration(0.4)
            down:SetOrder(i * 2)
        end
        button.pulse = ag
    end

    button:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, 0) end)
    button:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 1) end)
    button:SetScript("OnClick", function(self, which)
        if S.inInstance then return end
        if which == "RightButton" then
            GameTooltip:Hide()
            LayerMenu(self)
        else
            SetShown(not cfg.shown)
            Tooltip(self)
        end
    end)
    button:SetScript("OnEnter", Tooltip)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then self:StartMoving() end
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local h = WorldMapFrame.ScrollContainer or WorldMapFrame
        local right, top = self:GetRight(), self:GetTop()
        local hr, ht = h:GetRight(), h:GetTop()
        if right and top and hr and ht then
            local scale = self:GetEffectiveScale() / h:GetEffectiveScale()
            cfg.mapButton = { x = right * scale - hr, y = top * scale - ht }
        end
        Place()
    end)
    Place()
    Refresh()
    WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0.3, Introduce) end)
end

ns.SetupMapButton = SetupMapButton
ns.MapButtonRefresh = Refresh
ns.SetMapShown = SetShown
ns.Menu = Menu
