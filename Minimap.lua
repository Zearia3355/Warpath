-- Warpath: Minimap
-- The minimap button (3.7), through LibDataBroker and LibDBIcon so button
-- bag addons (MBB) and Titan Panel pick it up too. Left-click: the
-- chronicle. Right-click: settings. Drag it around the minimap's edge.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Print = ns.Print

local cfg
ns.OnBind(function() cfg = ns.cfg end)

local Minimap = {}
local Icon, obj

local function Tooltip(tt)
    tt:AddLine("Warpath", 1, 0.82, 0)
    if S.inInstance then
        tt:AddLine("Off in battlegrounds", 0.7, 0.7, 0.7)
        return
    end
    tt:AddLine("Left-click: open the chronicle", 1, 1, 1)
    tt:AddLine("Right-click: settings", 1, 1, 1)
    tt:AddLine("Drag: move around the minimap", 0.6, 0.6, 0.6)
end

local function Click(_, button)
    if S.inInstance then return end
    if button == "RightButton" then
        ns.Dispatch("setup")
    else
        ns.Chronicle.Toggle()
    end
end

function Minimap.Setup()
    if obj then return end
    if type(cfg.minimap) ~= "table" then cfg.minimap = { hide = false } end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end
    obj = LDB:NewDataObject("Warpath", {
        type = "launcher", label = "Warpath", icon = C.TEX_SWORDS,
        OnClick = Click, OnTooltipShow = Tooltip,
    })
    Icon = LibStub("LibDBIcon-1.0", true)
    if Icon and obj then
        local ok, err = pcall(Icon.Register, Icon, "Warpath", obj, cfg.minimap)
        if not ok then Icon = nil Print("the minimap button couldn't be made: " .. tostring(err)) end
    end
    Minimap.Refresh()
end

-- Greyed in battlegrounds, rather than gone.
function Minimap.Refresh()
    local b = Icon and Icon.GetMinimapButton and Icon:GetMinimapButton("Warpath")
    if b and b.icon then
        b.icon:SetDesaturated(S.inInstance and true or false)
        local v = S.inInstance and 0.6 or 1
        b.icon:SetVertexColor(v, v, v)
    end
end

function Minimap.SetShown(on)
    cfg.minimap = cfg.minimap or {}
    cfg.minimap.hide = not on
    if Icon then
        if on then Icon:Show("Warpath") else Icon:Hide("Warpath") end
    end
end

function Minimap.Shown() return not (cfg.minimap and cfg.minimap.hide) end
function Minimap.Available() return Icon ~= nil end

ns.Minimap = Minimap
