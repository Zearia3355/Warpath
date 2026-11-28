-- Warpath: Events
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Migrate, Print, Prune, Simplify, VERSION, cur = ns.Migrate, ns.Print, ns.Prune, ns.Simplify, ns.VERSION, ns.cur
local outQ, session, Foes, FlushShare, OnComm = ns.outQ, ns.session, ns.Foes, ns.FlushShare, ns.OnComm
local FinishShot, OnDeath, Sample, See, CloseStroke = ns.FinishShot, ns.OnDeath, ns.Sample, ns.See, ns.CloseStroke
local Redraw, SetupMap, CreateHUD, UpdateHUD, MaybeShowSetup = ns.Redraw, ns.SetupMap, ns.CreateHUD, ns.UpdateHUD, ns.MaybeShowSetup
local Campaign, Zone, Chronicle = ns.Campaign, ns.Zone, ns.Chronicle

local db, gdb, cfg, faction, foe, myName, myFull
ns.OnBind(function()
    db, gdb, cfg, faction, foe, myName, myFull = ns.db, ns.gdb, ns.cfg, ns.faction, ns.foe, ns.myName, ns.myFull
end)

local tick = 0

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local DEFAULTS = {
    yards = 0, kills = 0, deaths = 0, bestStreak = 0, recentHours = 3, longDays = 14, roadMin = 2.5,
}

-- Battlegrounds, arenas, dungeons and raids. Any one of these is enough;
-- each is wrapped so a missing or hidden API just counts as "no".
local function InsideMatch()
    local ok, inside, kind = pcall(IsInInstance)
    if ok and (inside == true or (type(kind) == "string" and kind ~= "none")) then return true end
    if UnitInBattleground and Foes.Safe(UnitInBattleground, "player") then return true end
    if C_PvP then
        for _, fn in ipairs({ C_PvP.IsBattleground, C_PvP.IsArena, C_PvP.IsActiveBattlefield,
                              C_PvP.IsRatedBattleground, C_PvP.IsInBrawl }) do
            if fn and Foes.Safe(fn) == true then return true end
        end
    end
    local zoneKind = GetZonePVPInfo and Foes.Safe(GetZonePVPInfo)
    if zoneKind == "arena" or zoneKind == "combat" then return true end
    return false
end

-- While inside: no recording, no banners or sounds, no kill shots, no
-- sharing, no war table, nothing drawn, no setup window. All of it comes
-- back when you leave.
local function RefreshInstance()
    local was = S.inInstance
    S.inInstance = InsideMatch()
    if S.inInstance and cur.stroke then CloseStroke() end
    if was ~= S.inInstance and ns.Minimap then ns.Minimap.Refresh() end
    if was ~= S.inInstance and db then
        if S.hud then S.hud:SetShown(cfg.hudShown and not S.inInstance) end
        if S.inInstance then
            for i = #outQ, 1, -1 do outQ[i] = nil end
            ns.HideSetup()
            Chronicle.Hide()
            Zone.HideHeader()
        elseif S.ready then
            C_Timer.After(3, MaybeShowSetup)
        end
        S.dirty = true
        Redraw()
    end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_PVP_KILLS_CHANGED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED",
    "CHAT_MSG_ADDON", "PLAYER_REGEN_ENABLED", "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "PVP_MATCH_ACTIVE", "PVP_MATCH_COMPLETE", "CHAT_MSG_SYSTEM",
    "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "PLAYER_LOGOUT",
}) do f:RegisterEvent(ev) end

-- "No player named '%s' is currently playing." as a pattern.
local notFound
local function NotFoundName(msg)
    if not notFound then
        local fmt = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
        notFound = "^" .. fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$"
    end
    return type(msg) == "string" and msg:match(notFound)
end

-- 3.7.1: forget battle-history layers 3.7.0 filed under your own name (your
-- guild messages echoing back), and what it "sent" to you. They were a
-- second copy of your own kills and deaths, not anyone else's history.
local function DropSelfLayers()
    for _, z in pairs(db.maps) do
        for _, key in ipairs({ "guildBattle", "guildDeaths" }) do
            for who in pairs(z[key] or {}) do
                if ns.IsMe(who) or ns.IsMe((who:gsub("%-$", ""))) then z[key][who] = nil end
            end
        end
    end
    for who in pairs(db.syncSent or {}) do
        if ns.IsMe(who) or ns.IsMe((who:gsub("%-$", ""))) then db.syncSent[who] = nil end
    end
end

f:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            WarpathDB = WarpathDB or {}
            WarpathGlobal = WarpathGlobal or {}
            db, gdb = WarpathDB, WarpathGlobal
            ns.db, ns.gdb = db, gdb
            ns.Rebind()
            db.maps = db.maps or {}
            db.victims = db.victims or {}
            for k, v in pairs(DEFAULTS) do
                if db[k] == nil then db[k] = v end
            end
            gdb.kos = gdb.kos or {}
            -- 3.3: the key settings are account-wide. Seed them from this
            -- character's old settings the first time.
            if not gdb.cfg then
                gdb.cfg = {
                    layers = db.layers or {},
                    share = db.share or false, quiet = db.quiet or false,
                    sound = db.sound ~= false, hudShown = db.hudShown ~= false,
                }
                -- 3.8.3: a brand-new install takes the default (sharing on);
                -- an older character's settings keep theirs (off if never set)
                if next(db.maps) == nil and db.share == nil then gdb.cfg.share = nil end
            end
            cfg = gdb.cfg
            ns.cfg = cfg
            ns.Rebind()
            -- 3.4: the map on/off switch is shared by all characters.
            if cfg.shown == nil and db.shown ~= nil then cfg.shown = db.shown end
            cfg.layers = cfg.layers or {}
            cfg.layers.heat = nil -- 3.6: the lingering haze became the battle haze
            for _, name in ipairs(C.LAYERS) do
                if cfg.layers[name] == nil then cfg.layers[name] = true end
            end
            -- 3.5: today's trail length, from this character's old half-life.
            if cfg.trailHours == nil then
                local want, best = (db.recentHours or 3) * C.LOG2_5, 7
                for _, h in ipairs(C.TRAIL_CHOICES) do
                    if math.abs(h - want) < math.abs(best - want) then best = h end
                end
                cfg.trailHours = best
            end
            -- 3.7: dangerous ground replaces killing fields; if those warnings
            -- were turned off, the new ones start off too.
            if cfg.groundScreen == nil and cfg.fieldAlert == false then
                cfg.groundScreen, cfg.groundChat = false, false
            end
            -- 3.8.3: quiet mode and the big-text switch became "Announce on
            -- screen". Quiet mode also stopped sounds and the zone line, so an
            -- account that had it on keeps all three off. Settings only.
            if cfg.announce == nil and cfg.quiet ~= nil then
                cfg.announce = not cfg.quiet
                if cfg.quiet then cfg.sound, cfg.zoneText = false, false end
            end
            cfg.quiet, cfg.overlay = nil, nil
            for k, v in pairs(C.CFG_DEFAULTS) do
                if cfg[k] == nil then cfg[k] = v end
            end
            -- 3.8: roads, the trail and flights were reworked, so every map
            -- layer comes back on once and the trail takes the new 12 h
            -- default (Joe's call). Icon size, the map switch and corpse-run
            -- hours are kept. Settings only; no history is touched.
            if cfg.mapReset == nil then
                local ok, err = pcall(function()
                    local changed = cfg.trailMin ~= C.CFG_DEFAULTS.trailMin or not cfg.guildHaze
                    for _, name in ipairs(C.LAYERS) do
                        if not cfg.layers[name] then changed = true end
                        cfg.layers[name] = true
                    end
                    cfg.guildHaze = true
                    cfg.trailMin = C.CFG_DEFAULTS.trailMin
                    S.mapWasReset = changed
                end)
                if not ok then Print("couldn't reset the map settings for 3.8: " .. tostring(err)) end
                cfg.mapReset = "3.8"
            end
            if type(cfg.minimap) ~= "table" then cfg.minimap = { hide = false } end
            cfg.grudge = cfg.grudge or {}
            for k, v in pairs(C.GRUDGE_DEFAULTS) do
                if cfg.grudge[k] == nil then cfg.grudge[k] = v end
            end
            cfg.shot = cfg.shot or {}
            for k, v in pairs(C.SHOT_DEFAULTS) do
                if cfg.shot[k] == nil then cfg.shot[k] = v end
            end
            gdb.shotCount = gdb.shotCount or 0
            if gdb.installed == nil then
                gdb.installed = (db.v ~= nil or next(db.maps) ~= nil) and VERSION or false
            end
            Migrate()
            if db.roadMin == nil or db.roadMin > 10 then db.roadMin = DEFAULTS.roadMin end
            if db.recentHours > 24 then db.recentHours = DEFAULTS.recentHours end
            ns.Grudge.Upgrade()
        elseif arg1 == "Blizzard_WorldMap" and db then
            SetupMap()
        end
    elseif event == "PLAYER_LOGIN" then
        local group = UnitFactionGroup("player")
        faction = C.FACTION[group or "Neutral"] or C.FACTION.Neutral
        foe = C.FACTION[faction.foe]
        myName = UnitName("player")
        local fn, fr = UnitFullName("player")
        local realm = (type(fr) == "string" and fr ~= "" and fr) or GetNormalizedRealmName() or ""
        myFull = (fn or myName) .. "-" .. realm
        ns.faction, ns.foe, ns.myName, ns.myFull = faction, foe, myName, myFull
        ns.Rebind()
        ns.Phrases.Seed(myFull)
        pcall(DropSelfLayers)
        session.start = time()
        local newCampaign = Campaign.Begin()
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, C.COMM)
        RefreshInstance()
        Prune()
        SetupMap()
        CreateHUD()
        UpdateHUD()
        pcall(ns.Minimap.Setup)
        ns.Ledger.Summarize() -- this character's line in the Ledger's "All characters" (3.8.5)
        C_Timer.NewTicker(C.SAMPLE_INTERVAL, function()
            tick = tick + 1
            Sample()
            Foes.NoteFalling()
            if tick % 4 == 0 then ns.Ground.Check() ns.TownSweep() end
            if tick % 2 == 0 then Foes.Track() Foes.NoteCreature("target") end
            if UnitAffectingCombat("player") or GetTime() - S.lastCombatEnd < 10 then Foes.ScanDead() end
            if Foes.dead and not UnitIsDeadOrGhost("player") then Foes.dead = false ns.Feats.OnAlive() end
            if tick % 10 == 0 then RefreshInstance() UpdateHUD() end
            if tick % 2 == 0 then FlushShare() elseif #outQ == 0 and cfg.share then ns.Sync.FlushOne() end
            if tick % 1200 == 0 then Prune() end
            if S.dirty and GetTime() - S.lastDraw > 2 then Redraw() end
        end)
        -- The kill-count event can fire while honor data loads; ignore that.
        C_Timer.After(5, function()
            S.ready = true
            Foes.hk = Foes.ReadHK() -- the honorable-kill counter we count from
            Foes.dead = UnitIsDeadOrGhost("player") and true or false
            ns.Sync.Start()
            Zone.Enter()
            C_Timer.After(2, MaybeShowSetup)
            -- A new campaign began and the last one had fighting.
            local last = db.campaigns[1]
            if newCampaign and last and (last.kills or 0) + (last.deaths or 0) > 0 then
                if cfg.chronLogin then Campaign.LoginLine() end
                if cfg.chronOpen then
                    -- wait for a quiet moment: out of combat, options window closed
                    local tries = 0
                    local function TryOpen()
                        tries = tries + 1
                        if S.inInstance or tries > 40 then return end
                        if Chronicle.Shown() then return end -- already open (an update's notes, say)
                        if InCombatLockdown() or UnitAffectingCombat("player") or (ns.SetupShown and ns.SetupShown()) then
                            C_Timer.After(3, TryOpen)
                        else
                            Chronicle.Open()
                        end
                    end
                    C_Timer.After(4, TryOpen)
                end
            end
        end)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PVP_MATCH_ACTIVE" or event == "PVP_MATCH_COMPLETE" then
        RefreshInstance()
    elseif event == "PLAYER_DEAD" then
        if S.ready and not Foes.dead then
            Foes.dead = true
            OnDeath()
        end
        if S.ready then pcall(ns.Spirits.OnDead) end
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        -- released: you're at the spirit healer (a moment to settle first)
        if event == "PLAYER_ALIVE" and S.ready then C_Timer.After(1, function() pcall(ns.Spirits.OnRelease) end) end
        if event == "PLAYER_UNGHOST" and S.ready then pcall(ns.OnUnghost) end
        if not UnitIsDeadOrGhost("player") then
            Foes.dead = false
            ns.Feats.OnAlive()
        end
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        if S.ready and (arg1 == nil or arg1 == "player") then Foes.OnCredit() end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        RefreshInstance()
        C_Timer.After(1, function() Zone.Enter() UpdateHUD() end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Foes.SawDead("target")
        See("target")
        Foes.Track()
        Foes.NoteCreature("target")
        ns.Grudge.OnTarget()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        Foes.SawDead("mouseover")
        See("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        See(arg1)
        ns.Grudge.OnPlate(arg1, true)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        ns.Grudge.OnPlate(arg1, false)
    elseif event == "CHAT_MSG_SYSTEM" then
        local who = NotFoundName(arg1)
        if who and ns.Sync then ns.Sync.Unreachable(who) end
    elseif event == "CHAT_MSG_ADDON" then
        if db then OnComm(arg1, arg2, arg3, arg4) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.lastCombatEnd = GetTime()
        if S.setupWaiting then C_Timer.After(2, MaybeShowSetup) end
    elseif event == "MIRROR_TIMER_START" or event == "MIRROR_TIMER_STOP" then
        Foes.OnMirror(event, arg1, arg2, arg3, arg4)
    elseif event == "PLAYER_LOGOUT" then
        if db and ns.myFull then ns.Ledger.Summarize() end
    elseif event == "SCREENSHOT_SUCCEEDED" then
        FinishShot(true)
    elseif event == "SCREENSHOT_FAILED" then
        FinishShot(false)
    end
end)

