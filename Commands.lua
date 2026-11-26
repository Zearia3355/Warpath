-- Warpath: Commands
-- One table drives /warpath help, /warpath help all, the old names (kept as
-- hidden aliases so nobody's macros break) and dispatch.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local MapName, PlayerPos, Print, Secret, VERSION, Waypoint = ns.MapName, ns.PlayerPos, ns.Print, ns.Secret, ns.VERSION, ns.Waypoint
local cur, outQ, shared, Foes, FlushShare, Share = ns.cur, ns.outQ, ns.shared, ns.Foes, ns.FlushShare, ns.Share
local shareStats, TakeKillShot, Grudge, FullName = ns.shareStats, ns.TakeKillShot, ns.Grudge, ns.FullName
local Redraw, StartReplay, StopReplay, replay = ns.Redraw, ns.StartReplay, ns.StopReplay, ns.replay
local Stats, UpdateHUD, ShowSetup = ns.Stats, ns.UpdateHUD, ns.ShowSetup
local Campaign, Zone, Chronicle = ns.Campaign, ns.Zone, ns.Chronicle

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local WHITE, GREY = "|cffffffff", "|cffa0a0a0"

-- "on", "off" or nil (toggle). Returns the new value, or nil for a bad word.
local function OnOff(word, current)
    word = (word or ""):lower()
    if word == "" then return not current end
    if word == "on" or word == "show" or word == "yes" then return true end
    if word == "off" or word == "hide" or word == "no" then return false end
end

local function State(v) return v and "|cff40ff40on|r" or "|cffff4030off|r" end

-- Typed layer names to saved keys.
local LAYER_KEYS = { battle = "battle", heat = "battle", haze = "battle", roads = "roads", trail = "recent", recent = "recent", runs = "runs",
    marks = "marks", sightings = "sightings", guild = "shared", shared = "shared" }

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------

local H = {}

function H.stats() Stats() end
function H.zone(arg)
    local sub, val = arg:lower():match("^(%S*)%s*(.-)$")
    if sub == "chat" or sub == "text" then
        local key = sub == "chat" and "zoneChat" or "zoneText"
        local v = OnOff(val, cfg[key])
        if v == nil then Print("usage: /warpath zone " .. sub .. " [on|off]") return end
        cfg[key] = v
        Print((sub == "chat" and "zone stats in chat " or "zone stats under the zone name ") .. State(v) .. ".")
    elseif sub == "test" then
        Zone.Enter(true)
    else
        Zone.Report()
    end
end

function H.chronicle(arg)
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    sub = sub:lower()
    if sub == "chat" then
        Campaign.Save()
        Campaign.ChatReport(db.campaign, "This campaign")
        if db.campaigns[1] then Campaign.ChatReport(db.campaigns[1], "Last campaign") end
    elseif sub == "share" then
        local where, who = rest:match("^(%S*)%s*(.-)$")
        local c = Chronicle.Current()
        if not c then
            Campaign.Save()
            c = (db.campaign and (db.campaign.kills + db.campaign.deaths > 0)) and db.campaign or db.campaigns[1] or db.campaign
        end
        Campaign.Share(c, where, who)
    elseif sub == "preview" then
        Chronicle.Open(true)
    elseif sub == "" then
        Chronicle.Toggle()
    else
        Print("usage: /warpath chronicle [chat | share [guild|party|say|whisper <name>] | preview]")
    end
end

function H.map(arg)
    local v = OnOff(arg, cfg.shown)
    if v == nil then Print("usage: /warpath map [on|off]") return end
    ns.SetMapShown(v)
    Print("Warpath on the map " .. (cfg.shown and "shown." or "hidden (still recording)."))
end

function H.layer(arg)
    local name, val = arg:lower():match("^(%S*)%s*(.-)$")
    local key = LAYER_KEYS[name]
    if not key then
        local names = {}
        for _, k in ipairs(C.LAYERS) do names[#names + 1] = C.LAYER_NAMES[k] end
        Print("layers: " .. table.concat(names, ", ") .. ". Usage: /warpath layer <name> [on|off]")
        return
    end
    local v = OnOff(val, cfg.layers[key])
    if v == nil then Print("usage: /warpath layer " .. name .. " [on|off]") return end
    cfg.layers[key] = v
    Print(C.LAYER_LABELS[key] .. ": " .. (v and "shown." or "hidden."))
    Redraw()
end

function H.replay(arg)
    if replay.active then StopReplay() else StartReplay(tonumber(arg)) end
end

function H.waypoint(arg)
    arg = arg:lower()
    if arg == "death" then
        local d = db.lastDeath
        if d then Waypoint(d[1], d[2], d[3], "where you last fell") else Print("no deaths recorded.") end
    elseif arg == "kill" then
        local k = db.lastKill
        if k then Waypoint(k[1], k[2], k[3], "your last kill") else Print("no kills recorded.") end
    else
        Print("usage: /warpath waypoint death|kill")
    end
end

function H.table(arg)
    local v = OnOff(arg, cfg.hudShown)
    if v == nil then Print("usage: /warpath table [on|off]") return end
    cfg.hudShown = v
    if S.hud then S.hud:SetShown(cfg.hudShown and not S.inInstance) end
    UpdateHUD()
    Print("war table " .. State(v) .. ".")
end

-- A typed name: "Name" (your realm) or "Name-Realm".
local function TypedName(word)
    if not word or word == "" then return end
    return word:find("-", 1, true) and word or (word .. "-" .. (GetNormalizedRealmName() or ""))
end

-- The target, if it's another player: full, class.
local function TargetPlayer()
    if not (UnitExists("target") and UnitIsPlayer("target")) then return end
    local full, short = FullName("target")
    if not full or short == myName then return end
    local _, class = UnitClass("target")
    return full, class
end

function H.grudge(arg)
    local sub, rest = arg:match("^(%S*)%s*(.-)$")
    if sub:lower() == "forgive" then
        local full = TypedName(rest) or TargetPlayer()
        if not full then Print("usage: /warpath grudge forgive <name> (or target them)") return end
        Grudge.Forgive(full)
        return
    end
    if arg ~= "" then
        Grudge.Add(TypedName(arg))
        return
    end
    local full, class = TargetPlayer()
    if full then
        if Grudge.Get(full) then
            Print(Grudge.Short(full) .. " is already in your ledger. /warpath grudge forgive to strike them out.")
        else
            Grudge.Add(full, class)
        end
        return
    end
    local offer = Grudge.Pending()
    if offer then Grudge.Add(offer.full, offer.class) return end
    Print("target a player, or use /warpath grudge <name>.")
end

function H.grudges(arg)
    if arg:lower() ~= "chat" then Chronicle.Open(false, "grudges") return end
    local list = Grudge.List()
    if #list == 0 then Print("you hold no grudges.") return end
    table.sort(list, function(a, b) return a.full < b.full end)
    for _, g in ipairs(list) do
        local hist = Grudge.History(g.r)
        Print(("%s%s|r: you %d, them %d%s%s"):format(C.GOLD, Grudge.Short(g.full), g.r.kills, g.r.deaths,
            g.r.seen and (", last seen " .. MapName(g.r.seen.z) .. " " .. ns.Ago(g.r.seen.t)) or "",
            g.r.note and (". \"" .. g.r.note .. "\"") or ""))
    end
end

function H.shot(arg)
    local sub, val = arg:lower():match("^(%S*)%s*(.-)$")
    local c = cfg.shot
    if sub == "on" or sub == "off" then
        c.on = sub == "on"
    elseif sub == "all" or sub == "notable" then
        c.mode = sub
    elseif sub == "caption" and (val == "text" or val == "strip" or val == "none") then
        c.card = val
    elseif sub == "text" or sub == "strip" or sub == "none" then
        c.card = sub
    elseif sub == "combat" and (val == "on" or val == "off") then
        c.combat = val == "on"
    elseif sub == "delay" then
        local n = tonumber(val)
        if n and n >= 0 and n <= 5 then c.delay = n else Print("usage: /warpath shot delay <0-5>") return end
    elseif sub == "test" then
        local mapID = C_Map.GetBestMapForUnit("player")
        TakeKillShot({
            name = myName, class = select(2, UnitClass("player")),
            zone = mapID and not Secret(mapID) and MapName(mapID) or "", times = 4, streak = 3, when = time(),
        }, nil, nil, true)
        return
    elseif sub ~= "" then
        Print("usage: /warpath shot [on|off] | all|notable | caption text|strip|none | test")
        return
    end
    local names = { text = "floating text", strip = "caption strip", none = "no caption" }
    Print(("kill screenshots %s, %s, %s. %d taken so far.")
        :format(State(c.on), c.mode == "all" and "every kill" or "notable kills only", names[c.card] or c.card, gdb.shotCount))
end

function H.share(arg)
    arg = arg:lower()
    if arg == "test" or arg == "status" then
        if not cfg.share then
            Print("sharing is off. /warpath share on turns it on.")
        elseif arg == "test" then
            local mapID, x, y = PlayerPos()
            if not mapID then Print("can't send from here (instances are blocked).") return end
            Share("T", mapID, x, y, true)
            FlushShare()
            Print(("test ping sent (guild %s, group %s). Guildmates with sharing on should see a chat line within seconds.")
                :format(IsInGuild() and "yes" or "no", IsInGroup() and "yes" or "no"))
        end
        Print(("this session: %d sent, %d refused by the game, %d received.%s")
            :format(shareStats.sent, shareStats.refused, shareStats.got,
                shareStats.lastRefusal and (" Last refusal: " .. shareStats.lastRefusal) or ""))
        if shareStats.lastEvent then Print("last guild kill or death received: " .. shareStats.lastEvent .. ".") end
        if ns.DiagStatus then ns.DiagStatus() end
        if cfg.share then ns.Sync.Status() end
        return
    end
    if arg == "sync" then ns.Sync.Request() return end
    if arg == "history" or arg:match("^history ") then
        local v = OnOff(arg:match("^history%s*(.-)$"), cfg.shareHistory)
        if v == nil then Print("usage: /warpath share history [on|off]") return end
        cfg.shareHistory = v
        Print("sharing your battle history with guildmates " .. State(v) .. ".")
        return
    end
    local v = OnOff(arg, cfg.share)
    if v == nil then Print("usage: /warpath share [on|off] | test | status") return end
    cfg.share = v
    Print(cfg.share
        and "sharing ON. Guild and party members running Warpath get your enemy sightings, kills and PvP deaths (with the enemy's name), and you get theirs. Your trail is never sent."
        or "sharing off.")
    if not cfg.share then
        for i = #shared, 1, -1 do shared[i] = nil end
        for i = #outQ, 1, -1 do outQ[i] = nil end
    end
    Redraw()
end

function H.quiet(arg)
    local v = OnOff(arg, cfg.quiet)
    if v == nil then Print("usage: /warpath quiet [on|off]") return end
    cfg.quiet = v
    Print(cfg.quiet and "quiet: banners become chat lines, sounds off." or "banners and sounds back on.")
end

function H.sound(arg)
    local v = OnOff(arg, cfg.sound)
    if v == nil then Print("usage: /warpath sound [on|off]") return end
    cfg.sound = v
    Print("sounds " .. State(v) .. ".")
end

-- Dangerous-ground warnings, on screen and in chat (3.7: replaces killing fields).
function H.fields(arg)
    local v = OnOff(arg, cfg.groundScreen or cfg.groundChat)
    if v == nil then Print("usage: /warpath fields [on|off]") return end
    cfg.groundScreen, cfg.groundChat, cfg.fieldAlert = v, v, v
    Print("dangerous-ground warnings " .. State(v) .. ".")
end

-- Every stored pin at full strength, faded or not. Off again at login.
function H.history(arg)
    local v = OnOff(arg, S.showAll)
    if v == nil then Print("usage: /warpath history [on|off]") return end
    S.showAll = v
    S.dirty = true
    Redraw()
    Print(v and "showing all pin history, faded pins too (until you log out, or /warpath history off)."
        or "pins fade again: yours over a week, guildmates' over 3 days.")
end

function H.icons(arg)
    local n = tonumber(arg)
    if n and n >= 25 and n <= 200 then
        cfg.iconScale = math.floor(n / 5 + 0.5) * 5
        ns.RescalePins()
        Print(("map icons at %d%%."):format(cfg.iconScale))
    else
        Print(("map icons at %d%%. Usage: /warpath icons <25-200>"):format(cfg.iconScale or 100))
    end
end

function H.minimap(arg)
    local v = OnOff(arg, ns.Minimap.Shown())
    if v == nil then Print("usage: /warpath minimap [on|off]") return end
    ns.Minimap.SetShown(v)
    Print("minimap button " .. State(v) .. ".")
end

function H.overlay(arg)
    arg = arg:lower()
    if arg == "test" then
        local fac = ns.faction
        ns.Overlay.Show({ title = "TRIPLE KILL", sub = "Ilyssa  \194\183  Bloodthirsty: 3 without dying",
            r = fac.r, g = fac.g, b = fac.b, sound = "triple" })
        return
    end
    local v = OnOff(arg, cfg.overlay)
    if v == nil then Print("usage: /warpath overlay [on|off|test]") return end
    cfg.overlay = v
    Print("big text for multi-kills and streaks " .. State(v) .. ".")
end

function H.setup()
    local ok, err = pcall(ShowSetup, false)
    if not ok then Print("the options window failed to open: " .. tostring(err)) end
end

-- 3.7.6: today's trail is a fixed 15 minutes, so only long memory is set
-- here. The old "<hours> <days>" form still works (the hours are ignored).
function H.memory(arg)
    local days = tonumber(arg:match("(%S+)%s*$") or "")
    if days and days >= 2 and days <= 90 then
        db.longDays = days
        Print(("long memory (roads, battle haze, flight paths) halves every %g days you play."):format(days))
        Redraw()
    else
        Print(("long memory halves every %g days you play. Usage: /warpath memory <days 2-90>"):format(db.longDays))
    end
end

-- How long today's trail stays (3.7.7): "/warpath trail 1h", "30m", "90" (minutes).
function H.trail(arg)
    arg = (arg or ""):lower():gsub("%s+", "")
    if arg == "clear" then return H.clear("trail") end -- 3.8.1: the same as /warpath clear trail
    local n, unit = arg:match("^(%d+%.?%d*)([mh]?)$")
    n = tonumber(n)
    if not n then
        local m = cfg.trailMin or 60
        Print(("today's trail stays %s. Usage: /warpath trail <15m to 24h>, or /warpath trail clear"):format(m < 60 and (m .. " minutes") or ((m / 60) .. (m == 60 and " hour" or " hours"))))
        return
    end
    local minutes = unit == "h" and n * 60 or n
    minutes = math.floor(math.max(15, math.min(1440, minutes)) + 0.5)
    cfg.trailMin = minutes
    Print(("today's trail now stays %s; the oldest part is the faintest."):format(minutes < 60 and (minutes .. " minutes")
        or ((minutes / 60) .. (minutes == 60 and " hour" or " hours"))))
    Redraw()
end

-- Your own kills and deaths in chat, worded as your guild sees them (3.7.6).
function H.chat(arg)
    local v = OnOff(arg, cfg.selfChat)
    if v == nil then Print("usage: /warpath chat [on|off]") return end
    cfg.selfChat = v
    Print("your own kills and deaths in chat " .. State(v) .. ".")
end

-- 3.8: db.roadMin scales every band of the gilt roads (silver, the gold
-- thread, full gold, the faction mark). Said as days of daily use to full
-- gold: a road walked every day holds sum 2^(-i/half) after d days.
local function DaysToGold(m)
    local half = db.longDays or 14
    local left = 1 - m * C.GILD_FULL * (1 - 2 ^ (-1 / half))
    if left <= 0 then return nil end
    return -half * math.log(left) / math.log(2)
end

local function GoldText(m)
    local d = DaysToGold(m)
    return d and ("a road you walk every day turns fully gold in about %d days"):format(math.floor(d + 0.5))
        or "even a road you walk every day never turns fully gold"
end

function H.roads(arg)
    local n = tonumber(arg)
    if n and n >= 1.5 and n <= 10 then
        db.roadMin = n
        Print(("roads gild at %g (default 2.5): %s."):format(n, GoldText(n)))
        Redraw()
    else
        Print(("roads gild at %g (default 2.5): %s. Lower is sooner. Usage: /warpath roads <1.5-10>. Hide them with /warpath layer roads off.")
            :format(db.roadMin, GoldText(db.roadMin)))
    end
end

local clearAsked = -1000
function H.clear(arg)
    arg = arg:lower()
    if arg == "all" then
        if GetTime() - clearAsked > 10 then
            clearAsked = GetTime()
            Print("This forgets every road, mark and stat on this character. Type /warpath clear all again within 10 seconds to confirm.")
            return
        end
        clearAsked = -1000
        db.maps, db.yards, db.victims = {}, 0, {}
        db.syncSent = nil
        db.kills, db.deaths, db.bestStreak = 0, 0, 0
        db.lastDeath, db.lastKill = nil, nil
        cur.stroke, cur.cell, cur.rc = nil, nil, nil
        ns.ResetRecording()
        Print("the slate is clean. Your grudges and chronicle are kept; settle the grudges one by one.")
    elseif arg == "zone" then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and db.maps[mapID] then
            db.yards = math.max(0, db.yards - db.maps[mapID].yards)
            db.maps[mapID], cur.stroke, cur.cell, cur.rc = nil, nil, nil, nil
            ns.ForgetFields(mapID)
            Print("forgot " .. MapName(mapID) .. ".")
        else
            Print("nothing recorded in this zone.")
        end
    elseif arg == "trail" then
        -- 3.8: today's trail and lingering areas, on every map, including the
        -- stroke being recorded (clearing z.strokes by hand left it orphaned,
        -- so nothing drew until a /reload). Roads, marks and runs are kept.
        for _, z in pairs(db.maps) do
            if z.strokes then z.strokes = {} end
            if z.areas then z.areas = {} end
        end
        cur.map, cur.stroke, cur.mode, cur.x, cur.y = nil, nil, nil, nil, nil
        ns.Linger.Reset()
        Print("today's trail is cleared. Roads, kills, deaths and corpse runs are kept.")
    else
        Print("usage: /warpath clear trail | zone | all")
        return
    end
    Redraw()
    UpdateHUD()
end

-- /warpath debug haze: the strongest battle-haze spots in this zone, so the
-- haze can be checked against what you remember.
local function DebugHaze()
    local mapID, px, py = PlayerPos()
    local z = mapID and db.maps[mapID]
    if not z then Print("no battle haze recorded in this zone.") return end
    local field, list, stored, drawn = ns.BattleField(z), {}, 0, 0
    for c, v in pairs(field) do
        stored = stored + 1
        if v >= C.BATTLE_MIN then drawn = drawn + 1 end
        list[#list + 1] = { c = c, v = v, own = z.battle[c] and ns.Long(z.battle[c]) or 0 }
    end
    table.sort(list, function(a, b) return a.v > b.v end)
    local towns = 0
    for c in pairs(z.town or {}) do if z.battle[c] then towns = towns + 1 end end
    Print(("battle haze in %s: %d spots with heat, %d drawn (from %.1f, darkest at %d)%s%s")
        :format(MapName(mapID), stored, drawn, C.BATTLE_MIN, C.BATTLE_FULL,
            towns > 0 and (" | %d town spots hidden, still saved"):format(towns) or "",
            cfg.layers.battle and "" or " | the battle layer is OFF"))
    for i = 1, math.min(5, #list) do
        local e = list[i]
        local x, y = ns.CellXY(e.c, C.SW, C.SH)
        Print(("  %.1f, %.1f: heat %.2f (%.2f on the spot itself)"):format(x * 100, y * 100, e.v, e.own))
    end
    if px then
        local here = field[ns.Cell(px, py, C.SW, C.SH)]
        Print(("  where you stand (%.1f, %.1f): %s"):format(px * 100, py * 100, here and ("%.2f"):format(here) or "none"))
    end
end

-- /warpath debug kills: the last honorable-kill credits and what was counted.
local function DebugKills()
    Print(("this session: %d credit events, %d kills counted | the game's counter: %s%s")
        :format(Foes.credits, Foes.kills, tostring(Foes.ReadHK() or "not readable"),
            Foes.counterWorks and " (seen moving)" or ""))
    if #Foes.log == 0 then Print("  no kill credits yet this session.") return end
    for i = math.max(1, #Foes.log - 11), #Foes.log do
        local e = Foes.log[i]
        local hk = (e.before or e.after) and (" HKs %s>%s"):format(tostring(e.before or "?"), tostring(e.after or "?")) or ""
        Print(("  %s%s  %s"):format(date("%H:%M:%S", e.t), hk, e.text))
    end
end

function H.debug(arg)
    if (arg or ""):lower():match("^%s*haze") then DebugHaze() return end
    if (arg or ""):lower():match("^%s*kill") then DebugKills() return end
    Print(("in a battleground or instance: %s"):format(S.inInstance and "yes, Warpath is resting" or "no"))
    Print(("in a neutral town: %s (zone PvP type %s, subzone \"%s\")"):format(
        ns.InNeutralTown() and "yes, sightings aren't recorded" or "no",
        tostring(GetZonePVPInfo and Foes.Safe(GetZonePVPInfo)), tostring(GetSubZoneText and Foes.Safe(GetSubZoneText))))
    Print(("version %s | data v%s | options seen %s | install %s | PvPKillShot loaded %s")
        :format(VERSION, tostring(db.v), tostring(gdb.seenVersion), tostring(gdb.installed),
            tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PvPKillShot"))))
    Print(("sharing %s | %d sent, %d refused, %d received%s")
        :format(cfg.share and "on" or "off", shareStats.sent, shareStats.refused, shareStats.got,
            shareStats.lastRefusal and (" | last refusal " .. shareStats.lastRefusal) or ""))
    Print(("this session: %d honorable-kill credits, counted as %d kills (/warpath debug kills for the log)")
        :format(Foes.credits, Foes.kills))
    local last = Foes.last
    local known = 0
    for _ in pairs(Foes.known) do known = known + 1 end
    Print(("last kill name: %s | last enemy target: %s | enemies known: %d")
        :format(Foes.miss and ("not read, because " .. Foes.miss) or "read fine",
            last and (last.short .. ", " .. math.floor(GetTime() - last.at) .. "s ago") or "none", known))
    local c = db.campaign
    if c then
        Print(("campaign: started %s, %d closed campaigns kept, played %s")
            :format(date("%b %d %H:%M", c.start), #db.campaigns, Campaign.Duration((c.played or 0) + (c.cur or 0))))
    end
end

---------------------------------------------------------------------------
-- The command table
---------------------------------------------------------------------------

-- { typed, usage, description, group, everyday, handler }
local LIST = {
    { "",          "",                              "your totals",                        "Stats", true, H.stats },
    { "zone",      "zone",                          "this zone's stats",                  "Stats", true, H.zone },
    { "chronicle", "chronicle [chat]",              "your campaigns (window, or chat)",   "Stats", true, H.chronicle },
    { nil,         "chronicle share [guild|party|say|whisper <name>]", "share a campaign", "Stats" },
    { "map",       "map [on|off]",                  "show / hide everything Warpath draws", "Map", true, H.map },
    { "layer",     "layer <name> [on|off]",         "battle, roads, trail, runs, marks, sightings, guild", "Map", false, H.layer },
    { "replay",    "replay [hours]",                "replay your recent march (up to 24)", "Map", false, H.replay },
    { "waypoint",  "waypoint death|kill",           "waypoint to your last death or kill", "Map", false, H.waypoint },
    { "table",     "table [on|off]",                "the war table",                      "Map", false, H.table },
    { "minimap",   "minimap [on|off]",              "the minimap button",                 "Map", false, H.minimap },
    { "history",   "history [on|off]",              "show every stored pin, faded ones too (off at login)", "Map", false, H.history },
    { "icons",     "icons <25-200>",                "map icon size, in percent",          "Map", false, H.icons },
    { "trail",     "trail <15m-24h>",               "how long today's trail stays (default 12h)", "Map", false, H.trail },
    { nil,         "trail clear",                   "clear today's trail and lingering areas", "Map" },
    { "grudge",    "grudge [name]",                 "hold a grudge (default: your target)", "Grudges", true, H.grudge },
    { nil,         "grudge forgive [name]",         "strike a grudge from your ledger",   "Grudges" },
    { "grudges",   "grudges [chat]",                "your ledger of grudges (book, or chat)", "Grudges", false, H.grudges },
    { "shot",      "shot [on|off]",                 "take kill screenshots",              "Kill screenshots", false, H.shot },
    { nil,         "shot all|notable",              "every kill, or notable kills only",  "Kill screenshots" },
    { nil,         "shot caption text|strip|none",  "the caption in the picture",         "Kill screenshots" },
    { nil,         "shot test",                     "take a test screenshot",             "Kill screenshots" },
    { "share",     "share [on|off]",                "share sightings, kills and deaths with your guild", "Guild sharing", false, H.share },
    { nil,         "share test",                    "send a test ping",                   "Guild sharing" },
    { nil,         "share history [on|off]",        "share your battle haze with guildmates", "Guild sharing" },
    { nil,         "share sync",                    "ask guildmates for their battle history again", "Guild sharing" },
    { "quiet",     "quiet [on|off]",                "banners become chat lines, no sounds", "Alerts", false, H.quiet },
    { "sound",     "sound [on|off]",                "sounds only",                        "Alerts", false, H.sound },
    { "overlay",   "overlay [on|off|test]",         "big text for your multi-kills and streaks", "Alerts", false, H.overlay },
    { "chat",      "chat [on|off]",                 "your own kills and deaths in chat", "Alerts", false, H.chat },
    { "fields",    "fields [on|off]",               "dangerous-ground warnings", "Alerts", false, H.fields },
    { nil,         "zone chat|text [on|off]",       "zone stats in chat / under the zone name", "Alerts" },
    { "setup",     "setup",                         "all settings",                       "Settings", true, H.setup },
    { "memory",    "memory <days>",                 "how fast long memory (roads, haze, routes) fades", "Settings", false, H.memory },
    { "roads",     "roads <days>",                  "how soon roads turn gold (default 2.5; lower is sooner)", "Settings", false, H.roads },
    { "clear",     "clear zone",                    "forget this zone",                   "Data", false, H.clear },
    { nil,         "clear all",                     "forget everything (asks you to confirm)", "Data" },
    { "debug",     "debug [haze|kills]",            "what Warpath can and can't see (haze: this zone's haze; kills: the kill-credit log)", "Troubleshooting", false, H.debug },
    { nil,         "share status",                  "guild messages sent, refused, received", "Troubleshooting" },
}
local GROUPS = { "Stats", "Map", "Grudges", "Kill screenshots", "Guild sharing", "Alerts", "Settings", "Data", "Troubleshooting" }

-- Old names keep working. Value: the new command line.
local ALIASES = {
    stats = "", toggle = "map", hud = "table", revenge = "waypoint death", lastkill = "waypoint kill",
    options = "setup", config = "setup", settings = "setup",
}

local HANDLERS = {}
for _, row in ipairs(LIST) do
    if row[1] and row[6] then HANDLERS[row[1]] = row[6] end
end

-- Chat uses a proportional font, so columns can't line up; a clear gap instead.
local function Line(usage, desc)
    local cmd = "/warpath" .. (usage ~= "" and (" " .. usage) or "")
    return "  " .. C.GOLD .. cmd .. "|r   " .. WHITE .. desc .. "|r"
end

local function Help(all)
    if not all then
        print(C.GOLD .. "Warpath commands:|r")
        for _, row in ipairs(LIST) do
            if row[5] then
                local usage = row[2]
                if row[1] == "chronicle" then usage = "chronicle" end
                print(Line(usage, row[1] == "chronicle" and "your campaigns" or row[3], 22))
            end
        end
        print(Line("help all", "every command", 22))
        return
    end
    for _, group in ipairs(GROUPS) do
        print(C.GOLD .. group .. "|r")
        for _, row in ipairs(LIST) do
            if row[4] == group then print(Line(row[2], row[3], 32)) end
        end
    end
end

-- Edit distance, for "Did you mean ...?"
local function Distance(a, b)
    if math.abs(#a - #b) > 3 then return 99 end
    local prev = {}
    for j = 0, #b do prev[j] = j end
    for i = 1, #a do
        local row = { [0] = i }
        for j = 1, #b do
            local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
            row[j] = math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = row
    end
    return prev[#b]
end

local function Unknown(cmd)
    local best, bestD = nil, 3
    local function Try(name)
        if name ~= "" then
            local d = Distance(cmd, name)
            if d < bestD then best, bestD = name, d end
        end
    end
    for name in pairs(HANDLERS) do Try(name) end
    for name in pairs(ALIASES) do Try(name) end
    if cmd:sub(1, 1) ~= "" then
        for name in pairs(HANDLERS) do
            if not best and #cmd >= 3 and name:sub(1, #cmd) == cmd then best = name end
        end
    end
    local hint = best and (" Did you mean " .. C.GOLD .. "/warpath " .. (ALIASES[best] or best) .. "|r?") or ""
    Print(("unknown command '%s'.%s Type /warpath help."):format(cmd, hint))
end

local function Dispatch(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "help" or cmd == "?" then
        Help(arg:lower() == "all")
        return
    end
    local alias = ALIASES[cmd]
    if alias then
        local acmd, aarg = alias:match("^(%S*)%s*(.-)$")
        cmd, arg = acmd, (aarg ~= "" and (aarg .. (arg ~= "" and (" " .. arg) or "")) or arg)
    end
    local fn = HANDLERS[cmd]
    if fn then fn(arg or "") else Unknown(cmd) end
end

SLASH_WARPATH1, SLASH_WARPATH2 = "/warpath", "/wpath"
SlashCmdList.WARPATH = Dispatch

-- /killshot and /pks keep working for anyone used to PvPKillShot, unless that
-- addon is still installed and owns them.
local pksLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("PvPKillShot")
if not pksLoaded then
    SLASH_WARPATHSHOT1, SLASH_WARPATHSHOT2 = "/killshot", "/pks"
    SlashCmdList.WARPATHSHOT = function(msg)
        local m = (msg or ""):lower():gsub("^%s+", "")
        if m == "toggle" then m = cfg.shot.on and "off" or "on" end
        if m == "status" then m = "" end
        Dispatch("shot " .. m)
    end
end

ns.Dispatch = Dispatch
