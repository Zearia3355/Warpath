-- Warpath: Ground
-- Dangerous ground (3.7, replaces killing fields). Your PvP deaths are kept
-- on the battle-haze grid, spreading and fading the same way. Walk onto
-- ground where they reach the threshold and Warpath says what that ground
-- has been for you, from your kills and deaths there:
--   dangerous ground (deaths at least twice your kills), contested ground,
--   or your hunting ground (kills at least twice your deaths).
-- Out of combat only, never in neutral towns, once per area per session.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Cell, CellXY, PlayerPos, Print = ns.Cell, ns.CellXY, ns.PlayerPos, ns.Print

local db, cfg
ns.OnBind(function() db, cfg = ns.db, ns.cfg end)

local Ground = {}
local warned = {}            -- "mapID:cell" -> true, this session
local cache = {}             -- mapID -> { at, mine, guild }
local RADIUS = 2.5           -- in grid cells: what counts as "here"

local function Fields(mapID)
    local e = cache[mapID]
    if e and GetTime() - e.at < 10 then return e.mine, e.guild end
    local z = db.maps[mapID]
    if not z then return {}, {} end
    local mine, guild = ns.DeathField(z)
    cache[mapID] = { at = GetTime(), mine = mine, guild = guild }
    return mine, guild
end

function Ground.Forget(mapID)
    if mapID then cache[mapID] = nil else cache = {} end
end

-- Your kills and PvP deaths within RADIUS cells of a spot, from your marks.
-- skipAfter: leave out kills at or after this time (the kill being judged).
local function Tally(mapID, x, y, skipAfter)
    local z = db.maps[mapID]
    local k, d = 0, 0
    if not z then return 0, 0 end
    for _, m in ipairs(z.marks) do
        local dx, dy = (m[1] - x) * C.SW, (m[2] - y) * C.SH
        if dx * dx + dy * dy <= RADIUS * RADIUS then
            if m[4] == "kill" then
                if not (skipAfter and m[3] >= skipAfter) then k = k + 1 end
            elseif m.pvp then
                d = d + 1
            end
        end
    end
    return k, d
end

local function Tone(k, d)
    if d >= 2 * k then return "danger" end
    if k >= 2 * d then return "hunting" end
    return "contested"
end

-- "danger" / "contested" / "hunting" for a spot that counts as dangerous
-- ground (enough of your deaths), else nil.
function Ground.ToneAt(mapID, x, y, skipAfter)
    if not (mapID and x and y) then return end
    local mine = Fields(mapID)
    local v = mine[Cell(x, y, C.SW, C.SH)]
    if not v or v < (cfg.groundAfter or 2) then return end
    return Tone(Tally(mapID, x, y, skipAfter or (time() - 1)))
end

-- The worst ground within a few cells of where you stand, for the war table.
function Ground.Nearby(mapID, x, y)
    if not (mapID and x and y) then return end
    local mine = Fields(mapID)
    local need, best = cfg.groundAfter or 2, nil
    local town = db.maps[mapID] and db.maps[mapID].town or {}
    local cx, cy = math.floor(x * C.SW), math.floor(y * C.SH)
    for dy = -4, 4 do
        for dx = -4, 4 do
            local c = (cy + dy) * C.SW + (cx + dx)
            local v = cx + dx >= 0 and cx + dx < C.SW and mine[c]
            if v and v >= need and not town[c] then
                local px, py = CellXY(c, C.SW, C.SH)
                local t = Tone(Tally(mapID, px, py))
                if t == "danger" then return t end
                if t == "contested" then best = t end
            end
        end
    end
    return best
end

-- How many separate spots of dangerous ground a zone has.
function Ground.Spots(mapID)
    local mine = Fields(mapID)
    local need, n, taken = cfg.groundAfter or 2, 0, {}
    local list = {}
    for c, v in pairs(mine) do if v >= need then list[#list + 1] = { c = c, v = v } end end
    table.sort(list, function(a, b) return a.v > b.v end)
    for _, e in ipairs(list) do
        if not taken[e.c] then
            local px, py = CellXY(e.c, C.SW, C.SH)
            if Tone(Tally(mapID, px, py)) == "danger" then n = n + 1 end
            local cx, cy = e.c % C.SW, math.floor(e.c / C.SW)
            for dy = -2, 2 do for dx = -2, 2 do taken[(cy + dy) * C.SW + cx + dx] = true end end
        end
    end
    return n
end

local function TimesText(n)
    return n == 1 and "once" or n == 2 and "twice" or (n .. " times")
end

local LINES = {
    danger = {
        "Dangerous ground: you've died here %s and won %s.",
        "Careful: you've fallen here %s and won %s.",
        "Dangerous ground. It has had you %s; you've won %s.",
    },
    contested = {
        "Contested ground: %d kills, %d deaths here.",
        "Hard-fought ground: %d kills to %d deaths.",
        "Even fighting here: %d kills, %d deaths.",
    },
    hunting = {
        "Your hunting ground: %d kills, %d deaths here.",
        "Good hunting here: %d kills, %d deaths.",
        "You own this ground: %d kills to %d deaths.",
    },
}
local TITLES = { danger = "DANGEROUS GROUND", contested = "CONTESTED GROUND", hunting = "YOUR HUNTING GROUND" }
local COLORS = { danger = { 1, 0.25, 0.2 }, contested = { 1, 0.62, 0.16 }, hunting = { 1, 0.82, 0 } }
local turn = { danger = 0, contested = 0, hunting = 0 }

function Ground.Text(tone, k, d, guildDeaths)
    turn[tone] = turn[tone] % #LINES[tone] + 1
    local fmt = LINES[tone][turn[tone]]
    local text = tone == "danger" and fmt:format(TimesText(d), k == 0 and "never" or TimesText(k))
        or fmt:format(k, d)
    if guildDeaths and guildDeaths >= 1 then
        text = text .. (" Guildmates have died here %s."):format(TimesText(guildDeaths))
    end
    return text
end

-- Every 2 seconds.
function Ground.Check()
    if not (cfg.groundScreen or cfg.groundChat) or S.inInstance then return end
    if UnitAffectingCombat("player") or UnitIsDeadOrGhost("player") or UnitOnTaxi("player") then return end
    if ns.InNeutralTown() then return end
    local mapID, x, y = PlayerPos()
    if not mapID then return end
    local c = Cell(x, y, C.SW, C.SH)
    if warned[mapID .. ":" .. c] then return end
    local mine, guild = Fields(mapID)
    local v = mine[c]
    if not v or v < (cfg.groundAfter or 2) then return end
    if ns.Overlay.Busy() then return end -- a kill overlay is up: wait for it
    local cx, cy = c % C.SW, math.floor(c / C.SW)
    for dy = -2, 2 do for dx = -2, 2 do warned[mapID .. ":" .. ((cy + dy) * C.SW + cx + dx)] = true end end
    local k, d = Tally(mapID, x, y)
    if d == 0 then return end
    local tone = Tone(k, d)
    local g = guild[c] and math.floor(guild[c] / C.GROUND_GUILD + 0.5) or 0
    local text = Ground.Text(tone, k, d, g)
    if cfg.groundScreen and not cfg.quiet then
        local col = COLORS[tone]
        local sub = text:gsub("^[^:]+: ", ""):gsub("^Dangerous ground%. ", "")
        ns.Overlay.Show({ title = TITLES[tone], sub = sub, r = col[1], g = col[2], b = col[3], small = true,
            sound = tone ~= "hunting" and tone or nil })
    end
    if cfg.groundChat or (cfg.quiet and cfg.groundScreen) then
        local col = COLORS[tone]
        Print(("|cff%02x%02x%02x%s|r"):format(col[1] * 255, col[2] * 255, col[3] * 255, text))
    end
end

function Ground.Reset() warned = {} end

ns.Ground = Ground
