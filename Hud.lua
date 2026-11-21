-- Warpath: Hud
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Long, MapName, Print, Recent, Secret, Waypoint = ns.Long, ns.MapName, ns.Print, ns.Recent, ns.Secret, ns.Waypoint
local recentSight, session, Fields, Campaign = ns.recentSight, ns.session, ns.Fields, ns.Campaign

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local UpdateHUD

---------------------------------------------------------------------------
-- War table (HUD)
---------------------------------------------------------------------------

local function CreateHUD()
    S.hud = CreateFrame("Frame", "WarpathHUD", UIParent, "BackdropTemplate")
    S.hud:SetSize(210, 108)
    S.hud:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    S.hud:SetBackdropColor(0.05, 0.03, 0.02, 0.85)
    S.hud:SetBackdropBorderColor(1, 0.82, 0, 0.9)
    local pos = db.hud
    S.hud:SetPoint(pos and pos[1] or "TOPLEFT", UIParent, pos and pos[1] or "TOPLEFT", pos and pos[2] or 20, pos and pos[3] or -180)

    S.hud:SetMovable(true)
    S.hud:SetClampedToScreen(true)
    S.hud:EnableMouse(true)
    S.hud:RegisterForDrag("LeftButton")
    S.hud:SetScript("OnDragStart", S.hud.StartMoving)
    S.hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        db.hud = { point, x, y }
    end)
    S.hud:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            local d = db.lastDeath
            if d then Waypoint(d[1], d[2], d[3], "where you last fell")
            else Print("you haven't died yet. Keep it that way.") end
        end
    end)
    S.hud:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine("Warpath", 1, 0.82, 0)
        GameTooltip:AddLine("Drag to move", 1, 1, 1)
        GameTooltip:AddLine("Right-click: waypoint to where you last fell", 1, 1, 1)
        GameTooltip:AddLine("/warpath help for everything else", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    S.hud:SetScript("OnLeave", GameTooltip_Hide)

    local crest = S.hud:CreateTexture(nil, "ARTWORK")
    crest:SetTexture(faction.crest)
    crest:SetTexCoord(0, 0.62, 0, 0.62)
    crest:SetSize(30, 30)
    crest:SetPoint("TOPRIGHT", -8, -8)

    S.hud.title = S.hud:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    S.hud.title:SetPoint("TOPLEFT", 12, -10)
    S.hud.title:SetText("Warpath")

    S.hud.rows = {}
    for i = 1, 5 do
        local fs = S.hud:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, -14 - i * 15)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(i >= 4 and 160 or 186) -- rows 4-5 leave room for the grudge button
        fs:SetWordWrap(false)
        S.hud.rows[i] = fs
    end
    ns.CreateGrudgeButton(S.hud)
    S.hud:SetShown(cfg.hudShown and not S.inInstance)
end

---------------------------------------------------------------------------
-- The grudge button on the war table: one click holds a grudge against
-- your target (or the player last offered in chat). Right-click opens
-- the ledger.
---------------------------------------------------------------------------

local gbtn

-- What a click would do now: "add", full, short | "held", full, short | nil.
local function GrudgeAction()
    if UnitExists("target") and UnitIsPlayer("target") then
        local full, short = ns.FullName("target")
        if full and short ~= myName then
            return ns.Grudge.Get(full) and "held" or "add", full, short
        end
    end
    local offer = ns.Grudge.Pending()
    if offer then return "add", offer.full, ns.Grudge.Short(offer.full) end
end

local function GrudgeButtonRefresh()
    if not gbtn then return end
    local action = GrudgeAction()
    gbtn.icon:SetDesaturated(action == nil)
    gbtn.icon:SetAlpha(action == nil and 0.55 or 1)
    if action == "held" then gbtn.icon:SetVertexColor(1, 0.35, 0.25) else gbtn.icon:SetVertexColor(1, 1, 1) end
    if gbtn:IsMouseOver() and gbtn:GetScript("OnEnter") then gbtn:GetScript("OnEnter")(gbtn) end
end

function ns.CreateGrudgeButton(hud)
    gbtn = CreateFrame("Button", nil, hud)
    gbtn:SetSize(24, 24)
    gbtn:SetPoint("BOTTOMRIGHT", -9, 9)
    gbtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local edge = gbtn:CreateTexture(nil, "BACKGROUND")
    edge:SetColorTexture(1, 0.82, 0, 0.6)
    edge:SetAllPoints()
    local bg = gbtn:CreateTexture(nil, "BORDER")
    bg:SetColorTexture(0.08, 0.04, 0.02, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    gbtn.icon = gbtn:CreateTexture(nil, "ARTWORK")
    gbtn.icon:SetTexture(C.TEX_SKULL)
    gbtn.icon:SetPoint("TOPLEFT", 3, -3)
    gbtn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    local hl = gbtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 0.82, 0, 0.18)
    hl:SetAllPoints()
    gbtn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then ns.Chronicle.Open(false, "grudges") return end
        local action, full, short = GrudgeAction()
        if action == "add" then
            ns.Dispatch("grudge")
        elseif action == "held" then
            Print(short .. " is already in your ledger. Right-click the skull to open it.")
        else
            Print("target a player to hold a grudge against them. Right-click the skull to open your ledger.")
        end
        GrudgeButtonRefresh()
    end)
    gbtn:SetScript("OnEnter", function(self)
        local action, _, short = GrudgeAction()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if action == "add" then
            GameTooltip:AddLine("Hold a grudge against " .. short, 1, 0.3, 0.2)
        elseif action == "held" then
            GameTooltip:AddLine(short .. " is in your ledger", 1, 0.3, 0.2)
        else
            GameTooltip:AddLine("Grudges", 1, 0.82, 0)
            GameTooltip:AddLine("Target a player, then click to hold a grudge.", 1, 1, 1)
        end
        GameTooltip:AddLine("Right-click: open your ledger", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    gbtn:SetScript("OnLeave", GameTooltip_Hide)
    GrudgeButtonRefresh()
end

ns.GrudgeButtonRefresh = GrudgeButtonRefresh

function UpdateHUD()
    Campaign.Save()
    if not S.hud or not S.hud:IsShown() then return end
    S.hud.rows[1]:SetText(("Kills |cff40ff40%d|r   Deaths |cffff4030%d|r"):format(session.kills, session.deaths))
    S.hud.rows[2]:SetText(("Streak %s%d|r   Best %s%d|r"):format(C.GOLD, session.streak, C.GOLD, db.bestStreak))
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID and not Secret(mapID) and not S.inInstance then
        local z = db.maps[mapID]
        S.hud.rows[3]:SetText(z and (z.kills + z.pdeaths > 0)
            and ("%s  %d : %d"):format(MapName(mapID), z.kills, z.pdeaths) or MapName(mapID))
        local seen, now = 0, time()
        for _, s in ipairs(recentSight) do
            if s.mapID == mapID and now - s.t <= 300 then seen = seen + 1 end
        end
        local fields = #Fields(mapID)
        if seen > 0 then
            S.hud.rows[4]:SetText(("|cffff8000%d enem%s seen in the last 5 min|r"):format(seen, seen == 1 and "y" or "ies"))
        elseif fields > 0 then
            S.hud.rows[4]:SetText(("|cffff4030%d killing field%s here|r"):format(fields, fields == 1 and "" or "s"))
        else
            S.hud.rows[4]:SetText("|cff808080No enemies seen lately|r")
        end
    else
        S.hud.rows[3]:SetText("|cff808080Not recording here|r")
        S.hud.rows[4]:SetText("")
    end
    S.hud.rows[5]:SetText(("%.1f miles marched"):format(db.yards / 1760))
    GrudgeButtonRefresh()
end

---------------------------------------------------------------------------
-- /warpath: your totals
---------------------------------------------------------------------------

local function Stats()
    local zones, farMap, farYards, deadMap, deadN = 0, nil, 0, nil, 0
    for mapID, z in pairs(db.maps) do
        zones = zones + 1
        if z.yards > farYards then farMap, farYards = mapID, z.yards end
        if z.pdeaths > deadN then deadMap, deadN = mapID, z.pdeaths end
    end
    Print(("%.1f miles marched, zones visited %d. Kills %d, deaths to players %d, best streak %d.")
        :format(db.yards / 1760, zones, db.kills, db.deaths, db.bestStreak))
    if farMap then Print(("Most marched: %s (%.1f mi)."):format(MapName(farMap), farYards / 1760)) end
    if deadMap then Print(("Deadliest ground: %s (%d deaths)."):format(MapName(deadMap), deadN)) end
    local who, most = nil, 0
    for name, n in pairs(db.victims) do
        if n > most then who, most = name, n end
    end
    if who then Print(("Favourite victim: %s (%d kills)."):format(who, most)) end
    Print("|cffa0a0a0Type /warpath help for commands.|r")
end

-- Shared with the other files.
ns.CreateHUD = CreateHUD
ns.Stats = Stats
ns.UpdateHUD = UpdateHUD
