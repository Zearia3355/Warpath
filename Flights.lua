-- Warpath: Flights
-- Flight legs (3.8): the paths you fly most, etched into the map.
--
-- Every flight is laid onto the legs you've already flown: it's resampled
-- every AIR_STEP yards and each point is matched to the nearest leg point
-- within AIR_SNAP yards (a return flight runs a little beside the outbound
-- one, and both are the same leg). Matched points gain one day of long
-- memory, as roads do; the rest start a new leg, joined to where they left
-- the old one. So a hub you pass through on every trip builds up on the legs
-- you actually use, wherever you boarded, and a leg flown once never shows:
-- that's what keeps the map from becoming a web of every flight path.
--
-- z.air = { leg, ... }; leg = { x1, y1, x2, y2, ...,
--           l = { strength }, t = { when, play clock }, d = { day credited } }
-- Replaces z.routes (matched by their two ends only, so one path split into
-- several records, none of which reached the bar). Routes are kept, unused.
local ADDON, ns = ...
local C = ns.C
local Long, PlayNow, Q, ZoneData = ns.Long, ns.PlayNow, ns.Q, ns.ZoneData

local db
ns.OnBind(function() db = ns.db end)

local ASPECT = 668 / 1002 -- every map is 3:2 and scaled the same both ways

-- A leg point's long memory now (same clock and half-life as roads).
local function Strength(L, i)
    local l = L.l[i]
    if not l or l <= 0 then return 0 end
    return l * math.exp(-C.LN2 * (PlayNow() - L.t[i]) / (db.longDays * C.DAY))
end

-- The stroke as points AIR_STEP yards apart (in map units: wx, wy per yard).
local function Resample(s, wx, wy)
    local n = #s / 2
    local out = { s[1], s[2] }
    if n < 2 then return out end
    local carry = 0
    for i = 1, n - 1 do
        local x1, y1, x2, y2 = s[2 * i - 1], s[2 * i], s[2 * i + 1], s[2 * i + 2]
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt((dx / wx) ^ 2 + (dy / wy) ^ 2) -- yards
        if len > 0 then
            local pos = C.AIR_STEP - carry
            while pos <= len do
                out[#out + 1] = x1 + dx * pos / len
                out[#out + 1] = y1 + dy * pos / len
                pos = pos + C.AIR_STEP
            end
            carry = len - (pos - C.AIR_STEP)
        end
    end
    if carry > C.AIR_STEP * 0.3 then
        out[#out + 1] = s[2 * n - 1]
        out[#out + 1] = s[2 * n]
    end
    return out
end

-- Leg points bucketed by snap-sized squares, so matching looks at nine.
local function Index(air, bx, by)
    local idx = {}
    for _, L in ipairs(air) do
        for j = 1, #L / 2 do
            local k = math.floor(L[2 * j - 1] / bx) * 65536 + math.floor(L[2 * j] / by)
            local b = idx[k]
            if not b then b = {} idx[k] = b end
            b[#b + 1] = L
            b[#b + 1] = j
        end
    end
    return idx
end

local function Nearest(idx, bx, by, wx, wy, x, y)
    local cx, cy = math.floor(x / bx), math.floor(y / by)
    local best, bl, bj = 1, nil, nil -- in snap distances, squared
    for i = -1, 1 do
        for j = -1, 1 do
            local b = idx[(cx + i) * 65536 + cy + j]
            if b then
                for k = 1, #b, 2 do
                    local L, p = b[k], b[k + 1]
                    local d = (((L[2 * p - 1] - x) / wx) ^ 2 + ((L[2 * p] - y) / wy) ^ 2) / (C.AIR_SNAP * C.AIR_SNAP)
                    if d < best then best, bl, bj = d, L, p end
                end
            end
        end
    end
    return bl, bj
end

-- Lay one stretch onto the zone's legs. give = nil: a flight today (one day
-- of memory per point per calendar day). give = a strength: an old route
-- being brought over, merged as the stronger of the two (two records of one
-- path may hold the same days, so they aren't added).
local function Lay(mapID, s, give, day)
    local z = ZoneData(mapID)
    z.air = z.air or {}
    local yd = ns.Linger and ns.Linger.MapYards(mapID) or 4000
    local wx, wy = 1 / yd, 1 / (yd * ASPECT) -- map units per yard
    local pts = Resample(s, wx, wy)
    local m = #pts / 2
    if m < 2 then return end
    local bx, by = C.AIR_SNAP * wx, C.AIR_SNAP * wy
    local idx = Index(z.air, bx, by)
    local now, today = PlayNow(), day or tonumber(date("%y%j"))
    local function Mark(L, j)
        local cur = Strength(L, j)
        if give then
            if give > cur then L.l[j], L.t[j], L.d[j] = give, now, today end
        elseif L.d[j] ~= today then
            L.l[j], L.t[j], L.d[j] = cur + 1, now, today
        end
    end
    local hits = {}
    for i = 1, m do
        local L, j = Nearest(idx, bx, by, wx, wy, pts[2 * i - 1], pts[2 * i])
        if L then
            hits[i] = { L, j }
            Mark(L, j)
        end
    end
    -- Runs of unmatched points become new legs, starting and ending on the
    -- leg points either side, so the etching joins up.
    local i = 1
    while i <= m do
        if hits[i] then
            i = i + 1
        else
            local a = i
            while i <= m and not hits[i] do i = i + 1 end
            local leg = { l = {}, t = {}, d = {} }
            local function Put(x, y, l, t, d)
                leg[#leg + 1] = Q(x)
                leg[#leg + 1] = Q(y)
                local n = #leg / 2
                leg.l[n], leg.t[n], leg.d[n] = l, t, d
            end
            local v = give or 1
            local h = hits[a - 1]
            if h then Put(h[1][2 * h[2] - 1], h[1][2 * h[2]], h[1].l[h[2]], h[1].t[h[2]], h[1].d[h[2]]) end
            for k = a, i - 1 do Put(pts[2 * k - 1], pts[2 * k], v, now, today) end
            h = hits[i]
            if h then Put(h[1][2 * h[2] - 1], h[1][2 * h[2]], h[1].l[h[2]], h[1].t[h[2]], h[1].d[h[2]]) end
            if #leg >= 4 then z.air[#z.air + 1] = leg end
        end
    end
    ns.S.dirty = true
end

local function Add(mapID, s)
    if #s >= 4 then Lay(mapID, s) end
end

-- Bring each zone's flight routes over once (3.8). A zone with z.air has
-- been done; routes stay as they were. Strongest first, so a path's best
-- record lays the leg and weaker copies only match it.
local function Convert()
    for mapID, z in pairs(db.maps) do
        if not z.air then
            z.air = {}
            local rs = {}
            for _, r in ipairs(z.routes or {}) do
                if #r >= 4 and Long(r) >= 0.05 then rs[#rs + 1] = r end
            end
            table.sort(rs, function(a, b) return Long(a) > Long(b) end)
            for _, r in ipairs(rs) do Lay(mapID, r, Long(r), r.d) end
        end
    end
end

-- Legs whose every point has faded away are dropped (as roads are, at 0.05).
local function Prune(z)
    if not z.air then return end
    local kept = {}
    for _, L in ipairs(z.air) do
        for i = 1, #L / 2 do
            if Strength(L, i) >= 0.05 then kept[#kept + 1] = L break end
        end
    end
    z.air = kept
end

ns.Flights = { Add = Add, Convert = Convert, Prune = Prune, Strength = Strength }
