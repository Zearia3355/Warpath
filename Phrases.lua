-- Warpath: Phrases
-- The wording for kill and death lines, so chat isn't the same message over
-- and over. Each pool is dealt from a shuffled deck: every line once before
-- any repeats, never the same line twice in a row, in a different order per
-- character. The sender picks; the line's number travels in the guild
-- message so everyone on 3.7 sees the same line.
--
-- Placeholders: {name} the player, {zone}, {n} a count, {killer}, {victim}.
-- Every line names the tier or its number, so chat stays easy to scan.
local ADDON, ns = ...

local P = {}

P.pools = {
    kill = {
        "{name} scored a kill in {zone}.",
        "{name} cut down an enemy in {zone}.",
        "{name} felled a foe in {zone}.",
        "{name} claimed a kill in {zone}.",
        "{name} put an enemy in the dirt in {zone}.",
    },
    first = { "{name} drew first blood in {zone}." },
    grudge = { "{name} settled a grudge in {zone}: {victim} falls!" },
    double = {
        "{name} scored a double kill in {zone}!",
        "Two fall to {name} in {zone}!",
        "{name} cut down two in quick succession in {zone}!",
        "{name} drops a pair in {zone}!",
    },
    triple = {
        "{name} scored a triple kill in {zone}!",
        "Three fall to {name} in {zone}!",
        "{name} cuts through three in {zone}!",
        "{name} makes it three in {zone}!",
    },
    quad = {
        "{name} scored a quad kill in {zone}!",
        "Four enemies fall to {name} in {zone}!",
        "{name} leaves four in the dirt in {zone}!",
    },
    bloodbath = {
        "Bloodbath in {zone}: {name} has felled {n}!",
        "{zone} runs red: {n} fall to {name}!",
        "{name} turns {zone} into a bloodbath: {n} down!",
    },
    s3 = {
        "Bloodthirsty: 3 without dying.",
        "{name} has the taste for it now: three straight.",
        "{name}'s blade stays wet: three in a row.",
    },
    s5 = {
        "Rampage: 5 without dying.",
        "Nothing stops {name}: five straight.",
        "{name} rampages on: five kills, no deaths.",
    },
    s10 = {
        "Warmonger: 10 without dying.",
        "Ten straight for {name}; the enemy will remember this one.",
        "{name} has made a war of it: ten without falling.",
    },
    s15 = {
        "Unstoppable: 15 without dying.",
        "Fifteen straight; no one has answered {name} yet.",
        "{name} cannot be stopped: fifteen in a row.",
    },
    s20 = {
        "Legend of the Warpath: {n} without dying.",
        "{name} walks the Warpath: {n} straight.",
        "{n} kills and still standing: {name} is a legend of the Warpath.",
    },
    ended = {
        "{name}'s run ends at {n} in {zone}.",
        "{killer} ends {name}'s streak at {n} in {zone}.",
        "{name} falls after {n} straight in {zone}.",
    },
    died = { "{name} was killed in {zone}." },
    took = { "{name} fell in {zone}, but took {victim} down with them." },
}

-- Lines that need a placeholder only some events have.
local NEEDS = { killer = "{killer}", victim = "{victim}" }

-- The streak milestone names (fixed: they're the overlay's titles too).
P.STREAKS = { [3] = "Bloodthirsty", [5] = "Rampage", [10] = "Warmonger", [15] = "Unstoppable", [20] = "Legend of the Warpath" }

-- 3, 5, 10, 15, 20, then every 10: the pool for a streak count, or nil.
function P.StreakPool(n)
    if n == 3 or n == 5 or n == 10 or n == 15 then return "s" .. n end
    if n and n >= 20 and n % 10 == 0 then return "s20" end
end

function P.StreakName(n)
    return P.STREAKS[n] or (n and n >= 20 and n % 10 == 0 and P.STREAKS[20]) or nil
end

-- The multi-kill tier for a chain of n kills.
function P.TierPool(n)
    if not n or n < 2 then return "kill" end
    if n == 2 then return "double" end
    if n == 3 then return "triple" end
    if n == 4 then return "quad" end
    return "bloodbath"
end

P.TIER_TITLE = { double = "Double Kill", triple = "Triple Kill", quad = "Quad Kill", bloodbath = "Bloodbath" }

---------------------------------------------------------------------------
-- Shuffled decks
---------------------------------------------------------------------------

local seed = 0
function P.Seed(text)
    local h = 5381
    for i = 1, #(text or "") do h = (h * 33 + text:byte(i)) % 2147483647 end
    seed = (h + math.floor((time and time() or 0) % 100000)) % 2147483647
    if seed == 0 then seed = 1 end
end

local function Rand(n)
    seed = (seed * 48271) % 2147483647
    return seed % n + 1
end

local decks, last = {}, {}

-- Lines in a pool that can be used with what this event knows.
local function Usable(pool, have)
    local list = P.pools[pool]
    local ok = {}
    for i, line in ipairs(list) do
        local fine = true
        for key, tag in pairs(NEEDS) do
            if not have[key] and line:find(tag, 1, true) then fine = false break end
        end
        if fine then ok[#ok + 1] = i end
    end
    return ok
end

-- Deal the next line number from a pool. have: { killer = true, ... }.
function P.Deal(pool, have)
    local list = P.pools[pool]
    if not list then return 1 end
    if #list == 1 then return 1 end
    local ok = Usable(pool, have or {})
    if #ok == 0 then return 1 end
    if #ok == 1 then return ok[1] end
    local deck = decks[pool]
    if not deck or #deck == 0 then
        deck = {}
        for i, v in ipairs(ok) do deck[i] = v end
        for i = #deck, 2, -1 do
            local j = Rand(i)
            deck[i], deck[j] = deck[j], deck[i]
        end
        -- never the same line twice in a row across a reshuffle
        if deck[#deck] == last[pool] then deck[1], deck[#deck] = deck[#deck], deck[1] end
        decks[pool] = deck
    end
    -- the deck is drawn from its end; skip lines this event can't use
    for k = #deck, 1, -1 do
        local idx = deck[k]
        local usable = false
        for _, v in ipairs(ok) do if v == idx then usable = true break end end
        if usable then
            table.remove(deck, k)
            last[pool] = idx
            return idx
        end
    end
    decks[pool] = nil
    return ok[1]
end

-- Fill a pool's line. An unknown number (a newer sender) falls back to our own pick.
function P.Text(pool, idx, vars)
    local list = P.pools[pool]
    if not list then return "" end
    local have = {}
    for k, v in pairs(vars) do if v ~= nil and v ~= "" then have[k] = true end end
    local line = list[tonumber(idx) or 0]
    if not line then line = list[P.Deal(pool, have)] end
    for key, tag in pairs(NEEDS) do
        if not have[key] and line:find(tag, 1, true) then line = list[1] break end
    end
    return (line:gsub("{(%a+)}", function(k)
        local v = vars[k]
        return v ~= nil and tostring(v) or ""
    end))
end

---------------------------------------------------------------------------
-- Feats: the one extra a kill line carries, highest first.
---------------------------------------------------------------------------

local function Ordinal(n)
    n = tonumber(n) or 0
    local tens, ones = n % 100, n % 10
    if tens >= 11 and tens <= 13 then return n .. "th" end
    return n .. (ones == 1 and "st" or ones == 2 and "nd" or ones == 3 and "rd" or "th")
end

-- key -> { label (chronicle and the overlay), text(a1, a2) }
P.FEATS = {
    grudge   = { "Grudge settled", function(a) return ("Grudge settled: %s."):format(a) end },
    nemesis  = { "Nemesis down", function(a) return ("Nemesis down: %s."):format(a) end },
    payback  = { "Payback", function(a) return ("Payback on %s."):format(a) end },
    guardian = { "Guardian", function(a) return ("%s avenged."):format(a) end },
    clutch   = { "Clutch", function(a) return ("Clutch, at %s%% health."):format(a) end },
    outnum   = { "Outnumbered", function(a, b) return ("Outnumbered %s to %s."):format(a, b) end },
    underdog = { "Underdog", function(a, b)
        local who = b ~= nil and b ~= "" and ns.ClassName and ns.ClassName(b) or "enemy"
        return ("Underdog: a level %s %s."):format((a == "-1" or a == -1) and "??" or a, who)
    end },
    comeback = { "Comeback", function(a) return ("Comeback after %s deaths."):format(a) end },
    rezkill  = { "Back from the dead", function() return "Back from the dead." end },
    avenged  = { "Death avenged", function() return "Death avenged." end },
    rival    = { "Old rival", function(a, b) return ("%s, for the %s time."):format(a, Ordinal(b)) end },
    ground   = { "Ground taken", function() return "Dangerous ground, but not today." end },
    flawless = { "Flawless", function() return "Flawless." end },
}
P.FEAT_ORDER = { "grudge", "nemesis", "streak", "payback", "guardian", "clutch", "outnum", "underdog",
    "comeback", "rezkill", "avenged", "rival", "ground", "flawless" }

function P.FeatText(key, a1, a2)
    local f = P.FEATS[key]
    if not f then return nil end
    local ok, text = pcall(f[2], a1 or "", a2 or "")
    return ok and text or nil
end

P.CRY = { Horde = "Blood and thunder!", Alliance = "For the Alliance!" }

ns.Phrases = P
ns.Ordinal = Ordinal
