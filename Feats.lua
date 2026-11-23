-- Warpath: Feats
-- Multi-kills (each kill within 2 minutes of the one before extends the
-- chain), streak milestones and feats. Each kill makes exactly one line:
-- the tier, plus the one extra that ranks highest. Guildmates get the same
-- line, built from numbers in the kill message.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local P = ns.Phrases

local db, cfg, faction, myName
ns.OnBind(function() db, cfg, faction, myName = ns.db, ns.cfg, ns.faction, ns.myName end)

local Feats = {
    chain = { n = 0, at = -1000 },
    lastKiller = nil,   -- { full, short, at }: who last killed you
    rezAt = nil,        -- when you came back after a PvP death
    deadPvp = false,    -- the death you're coming back from was PvP
    deathRun = 0,       -- PvP deaths in a row without a kill
    lastKill = nil,     -- { short, at }: for "took one with them"
    guildDeaths = {},   -- { killer (full), ally (short), at }: for Guardian
}

local function Safe(fn, ...) return ns.Foes.Safe(fn, ...) end

-- The next kill in the chain: 1 = a lone kill, 2 = double...
function Feats.Chain()
    local now, ch = GetTime(), Feats.chain
    if now - ch.at <= C.CHAIN then ch.n = ch.n + 1 else ch.n = 1 end
    ch.at = now
    return ch.n
end

local function HealthPct()
    local hp, max = Safe(UnitHealth, "player"), Safe(UnitHealthMax, "player")
    if type(hp) == "number" and type(max) == "number" and max > 0 then return hp / max end
end

-- Enemies and allies seen in the last 10 seconds (you count as an ally).
local function Odds()
    local now, foes, friends = GetTime(), 0, 1
    for _, t in pairs(ns.Foes.near) do if now - t <= 10 then foes = foes + 1 end end
    local seen = {}
    for full, t in pairs(ns.Foes.allies) do
        if now - t <= 10 then friends = friends + 1 seen[full] = true end
    end
    -- groupmates close enough to be drawn, if their plates are off
    local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
    if IsInGroup() then
        for i = 1, count do
            local u = prefix .. i
            if Safe(UnitExists, u) and not Safe(UnitIsUnit, u, "player") and Safe(UnitIsVisible, u) then
                local full = ns.FullName(u)
                if full and not seen[full] then friends = friends + 1 seen[full] = true end
            end
        end
    end
    return foes, friends
end

-- Who has killed you most this campaign (2+ times).
local function Nemesis()
    local c = db.campaign
    if not c then return end
    local n, best, who = {}, 1, nil
    for _, d in ipairs(c.dl or {}) do
        if d.f then
            n[d.f] = (n[d.f] or 0) + 1
            if n[d.f] > best then best, who = n[d.f], d.f end
        end
    end
    return who
end

local RIVAL = { [10] = true, [25] = true, [50] = true, [100] = true }

-- k = { full, short, class, lv, times, grudge, avenged, mapID, x, y, streak, first }
-- Returns every feat this kill earned, highest first: { key, a1, a2 }.
function Feats.Collect(k)
    local list, now = {}, GetTime()
    local function Add(key, a1, a2) list[#list + 1] = { key = key, a1 = a1, a2 = a2 } end
    local name = k.short or "an enemy"
    if k.grudge then Add("grudge", name) end
    if k.full and Nemesis() == k.full then Add("nemesis", name) end
    local pool = P.StreakPool(k.streak)
    if pool then Add("streak", k.streak) end
    local lk = Feats.lastKiller
    if k.full and lk and lk.full == k.full and now - lk.at <= 600 then Add("payback", name) end
    if k.full then
        for i = #Feats.guildDeaths, 1, -1 do
            local g = Feats.guildDeaths[i]
            if now - g.at > 120 then
                table.remove(Feats.guildDeaths, i)
            elseif g.killer == k.full then
                Add("guardian", g.ally)
                break
            end
        end
    end
    local hp = HealthPct()
    if hp and hp < 0.15 then Add("clutch", math.max(1, math.floor(hp * 100 + 0.5))) end
    local foes, friends = Odds()
    if foes - friends >= 2 then Add("outnum", foes, friends) end
    local lv, mine = k.lv, Safe(UnitLevel, "player")
    if lv and (lv == -1 or (type(mine) == "number" and lv >= mine + 3)) then Add("underdog", lv, k.class) end
    if Feats.deathRun >= 3 then Add("comeback", Feats.deathRun) end
    if Feats.rezAt and now - Feats.rezAt <= 60 then Add("rezkill") end
    if k.avenged then Add("avenged") end
    if k.times and RIVAL[k.times] then Add("rival", name, k.times) end
    if ns.Ground and k.mapID and ns.Ground.ToneAt(k.mapID, k.x, k.y) == "danger" then Add("ground") end
    if hp and hp >= 0.999 then Add("flawless") end
    return list
end

-- The text of one feat in your own words ("Bloodthirsty: 3 without dying.").
local function OwnExtra(f)
    if not f then return nil end
    if f.key == "streak" then
        return P.Text(P.StreakPool(f.a1), 1, { n = f.a1, name = myName })
    end
    return P.FeatText(f.key, f.a1, f.a2)
end
Feats.OwnExtra = OwnExtra

-- Your own line (quiet mode, or banners when the overlay is off).
-- "Kill: Elandris (first time)." / "Triple kill: Ilyssa. Bloodthirsty: 3 without dying."
function Feats.OwnLine(n, k, feats)
    local pool = P.TierPool(n)
    local label = pool == "kill" and "Kill" or pool == "bloodbath" and ("Bloodbath, " .. n .. " kills")
        or (P.TIER_TITLE[pool]:gsub(" Kill", " kill"))
    local who = k.short or "an enemy player"
    if pool == "kill" and k.times then
        who = who .. (k.times == 1 and " (first time)" or (" (%d times now)"):format(k.times))
    end
    local line = label .. ": " .. who .. "."
    local extra = OwnExtra(feats[1])
    if extra then line = line .. " " .. extra end
    return line
end

-- The overlay for a multi-kill or a streak milestone, or nil for an ordinary kill.
function Feats.OverlayFor(n, k, feats)
    local pool = P.TierPool(n)
    local streakName = P.StreakName(k.streak)
    if pool == "kill" and not streakName then return end
    local title, snd
    if pool ~= "kill" then
        title = P.TIER_TITLE[pool]
        if pool == "bloodbath" then title = title .. " \194\183 " .. n end
        snd = pool
    else
        title = streakName
        snd = k.streak >= 20 and "legend" or "streak"
    end
    local bits = { k.short or "an enemy player" }
    local shown = 0
    for _, f in ipairs(feats) do
        if shown >= 2 then break end
        -- the streak is already the title when there's no multi-kill
        if not (f.key == "streak" and pool == "kill") then
            local text = OwnExtra(f)
            if text then bits[#bits + 1] = text:gsub("%.$", "") shown = shown + 1 end
        end
    end
    return { title = title:upper(), sub = table.concat(bits, "  \194\183  "),
        r = faction.r, g = faction.g, b = faction.b, sound = snd }
end

---------------------------------------------------------------------------
-- The guild kill message and the line guildmates print from it
---------------------------------------------------------------------------

local POOL_CODE = { kill = "k", first = "f", grudge = "g", double = "2", triple = "3", quad = "4", bloodbath = "b" }
local CODE_POOL = {}
for k, v in pairs(POOL_CODE) do CODE_POOL[v] = k end
Feats.CODE_POOL = CODE_POOL

local function Clean(v) return (tostring(v or ""):gsub("[|;]", "")) end

-- Fields after the position: base pool, line number, chain, extra key,
-- extra line number, two arguments, faction cry, victim name.
function Feats.KillFields(n, k, feats)
    local pool = P.TierPool(n)
    local list = {}
    for _, f in ipairs(feats) do list[#list + 1] = f end
    if pool == "kill" then
        if list[1] and list[1].key == "grudge" then
            pool = "grudge"
            table.remove(list, 1) -- the line already says it
        elseif not list[1] and k.first then
            pool = "first"
        end
    end
    local pi = P.Deal(pool, { victim = k.short ~= nil })
    local f = list[1]
    local ek, ei, a1, a2, cry = "", "", "", "", ""
    if f then
        ek, a1, a2 = f.key == "streak" and "s" or f.key, f.a1 or "", f.a2 or ""
        if f.key == "streak" then
            ei = P.Deal(P.StreakPool(f.a1), {})
            if f.a1 >= 10 and math.random(3) == 1 and P.CRY[UnitFactionGroup("player") or ""] then cry = "1" end
        end
    end
    return table.concat({ POOL_CODE[pool], pi, n, ek, ei, Clean(a1), Clean(a2), cry, Clean(k.short) }, "|")
end

-- A guildmate's kill line. Fields from a 3.6 sender are missing: their line
-- is a plain kill with our own pick of wording.
function Feats.GuildKillLine(from, zone, bk, pi, n, ek, ei, a1, a2, cry, victim)
    local pool = CODE_POOL[bk or ""] or "kill"
    n = tonumber(n) or 1
    local vars = { name = from, zone = zone, n = n, victim = victim ~= "" and victim or nil }
    local line = P.Text(pool, pi, vars)
    local extra
    if ek == "s" then
        local sn = tonumber(a1)
        local sp = sn and P.StreakPool(sn)
        if sp then extra = P.Text(sp, ei, { name = from, n = sn }) end
        if extra and cry == "1" then
            local cryText = P.CRY[UnitFactionGroup("player") or ""]
            if cryText then extra = extra .. " " .. cryText end
        end
    elseif ek and ek ~= "" then
        extra = P.FeatText(ek, a1, a2)
    end
    if extra then line = line .. " " .. extra end
    return line
end

-- Death fields: killer (full), your streak when you fell, the streak-ended
-- line number, and the enemy you took down with you (killed within 3 s).
function Feats.DeathFields(killerFull, streak)
    local lk = Feats.lastKill
    local took = lk and GetTime() - lk.at <= 3 and lk.short or ""
    -- 3.7.6: a line number for every death, not only streaks (3.7.5 and
    -- earlier ignore it unless the streak was 3 or more)
    local pool = streak >= 3 and "ended" or took ~= "" and "took" or "died"
    local pi = P.Deal(pool, { killer = killerFull ~= nil and killerFull ~= "", victim = took ~= "" })
    return table.concat({ Clean(killerFull), streak, pi, Clean(took) }, "|")
end

function Feats.GuildDeathLine(from, zone, killerFull, streak, pi, took)
    streak = tonumber(streak) or 0
    local killer = killerFull and killerFull ~= "" and (killerFull:gsub("%-.*$", "")) or nil
    took = took ~= "" and took or nil
    local line
    if streak >= 3 then
        line = P.Text("ended", pi, { name = from, zone = zone, n = streak, killer = killer })
        if took then line = line .. (" Took %s down too."):format(took) end
    elseif took then
        line = P.Text("took", pi, { name = from, zone = zone, victim = took })
    else
        line = P.Text("died", pi, { name = from, zone = zone, killer = killer })
    end
    return line
end

-- A guildmate fell: remember who did it, for Guardian.
function Feats.GuildDeath(killerFull, ally)
    if not killerFull or killerFull == "" then return end
    local list = Feats.guildDeaths
    list[#list + 1] = { killer = killerFull, ally = ally, at = GetTime() }
    while #list > 20 do table.remove(list, 1) end
end

---------------------------------------------------------------------------
-- Your own state between kills and deaths
---------------------------------------------------------------------------

function Feats.OnKilled(short)
    Feats.lastKill = { short = short, at = GetTime() }
    Feats.deathRun = 0
end

function Feats.OnDied(pvp, killer)
    Feats.chain.n, Feats.chain.at = 0, -1000
    Feats.deadPvp = pvp and true or false
    if pvp then
        Feats.deathRun = Feats.deathRun + 1
        if killer then Feats.lastKiller = { full = killer.full, short = killer.short, at = GetTime() } end
    end
end

function Feats.OnAlive()
    if Feats.deadPvp then Feats.rezAt = GetTime() end
    Feats.deadPvp = false
end

ns.Feats = Feats
