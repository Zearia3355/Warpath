-- Warpath: Linger
-- Where you lingered (3.8): an area forms once you've stayed in one place
-- for a few minutes, grows while you're in it, and freezes when you leave.
-- The trail inside it is replaced by its outline, so an hour of questing
-- reads as a few areas joined by the way you went between them.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Q, ZoneData, TrailSeconds, WorldXY, PointTime = ns.Q, ns.ZoneData, ns.TrailSeconds, ns.WorldXY, ns.PointTime

local ASPECT = 668 / 1002          -- every zone map is 3:2; distances are in map widths
-- Distances are in yards (3.8, test4): a city map (the Undercity) covers a
-- few times less ground than a zone map, so fractions of the map made city
-- areas several times tighter. Each map's width in yards comes from the game.
local FORM_T = 240                 -- 4 min in one place...
local FORM_YD = 225                -- ...within this of its centre: an area forms (3.8.3: was 150;
                                   -- questing in the open world roams 200-330 yd every 4 min)
local FORM_N = 6                   -- and you moved about (standing still isn't lingering)
local LAG = 45                     -- a step joins the area 45 s later, if you're still in it
local SHOW = 3                     -- inside the area you're in, only this much of your line shows (3.8.2)...
local CURVE, TAPER = 1.0, 0.5      -- ...fading out behind you (3.8.3): brightness (1 - age/SHOW)^CURVE,
                                   -- width down to TAPER of the line's at the far end
local MARGIN_YD = 90               -- this far outside the area is leaving it...
local TRIP_T, TRIP_YD = 120, 150   -- ...but back within 2 min, never further out than this,
                                   -- and the trip was part of lingering: it joins
local RECENT = 600                 -- when an area forms, your last 10 min of trail near it joins
local REENTER = 600                -- stepping back inside within 10 min reopens the area
local SPAN_YD = 1200               -- an area stops growing past this size
-- A city (a map under CITY_YD wide: the Undercity is about 960) is denser:
-- 225 yd there swallowed the corridor to the lift (Joe's Undercity data),
-- so cities keep the tighter radius and a smaller cap (3.8.3).
local CITY_YD, CITY_FORM_YD, CITY_SPAN_YD = 2000, 150, 400
local GAP = 600                    -- a 10-minute gap (logged off, loading) ends a visit
local PAD = 0.010                  -- the outline sits this far outside the ground covered (on the map)
local ZONE_YD = 4000               -- a map's width when the game can't say
-- Only ground you milled about joins an area by a short trip or as recent
-- trail; ground you travelled through (a corridor) stays a line (Joe, test4). Travelling:
-- over MILL_T seconds either side you got more than MILL_STRAIGHT of the
-- way you walked, and walked at least MILL_YD.
local MILL_T, MILL_STRAIGHT, MILL_YD = 12, 0.75, 25
local TRIP_WIDE_YD = 10            -- a trip narrower than this went along a corridor and back
local REOPEN_T = 60                -- a minute inside an older area reopens it (passing through doesn't)
local VISIT_MERGE, VISIT_MIN = 600, 120 -- the visit list: under 10 min apart is one visit; under 2 min folds in

local st = { win = {}, pend = {} } -- live state; nothing here is saved
local outlines = setmetatable({}, { __mode = "k" })

-- How many yards one map width is, from two points across the middle.
local widths = {}
local function MapYards(mapID)
    local w = widths[mapID]
    if w then return w end
    local ax, ay = WorldXY(mapID, 0.25, 0.5)
    local bx, by = WorldXY(mapID, 0.75, 0.5)
    w = ax and bx and math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2) * 2
    if not w or w < 100 or w > 100000 then w = ZONE_YD end
    widths[mapID] = w
    return w
end
local function R(yd) return yd / (st.yd or ZONE_YD) end -- yards to map widths, on this map
local function City() return (st.yd or ZONE_YD) < CITY_YD end
local function FormR() return R(City() and CITY_FORM_YD or FORM_YD) end
local function SpanR() return R(City() and CITY_SPAN_YD or SPAN_YD) end

---------------------------------------------------------------------------
-- Geometry, on (x, y * ASPECT) so distances are true on the map
---------------------------------------------------------------------------

local function Cross(ox, oy, ax, ay, bx, by) return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox) end

-- Convex hull of flat {x1,y1,x2,y2,...}, counter-clockwise, as a flat list.
local function Hull(flat)
    local P = {}
    for i = 1, #flat, 2 do P[#P + 1] = { flat[i], flat[i + 1] * ASPECT } end
    table.sort(P, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a[2] < b[2] end)
    if #P < 3 then
        local out = {}
        for _, p in ipairs(P) do out[#out + 1] = p[1] out[#out + 1] = p[2] / ASPECT end
        return out
    end
    local H = {}
    local function Add(p)
        while #H >= 2 and Cross(H[#H - 1][1], H[#H - 1][2], H[#H][1], H[#H][2], p[1], p[2]) <= 0 do H[#H] = nil end
        H[#H + 1] = p
    end
    for i = 1, #P do Add(P[i]) end
    local lower = #H + 1
    for i = #P - 1, 1, -1 do
        while #H >= lower and Cross(H[#H - 1][1], H[#H - 1][2], H[#H][1], H[#H][2], P[i][1], P[i][2]) <= 0 do H[#H] = nil end
        H[#H + 1] = P[i]
    end
    H[#H] = nil
    local out = {}
    for _, p in ipairs(H) do out[#out + 1] = Q(p[1]) out[#out + 1] = Q(p[2] / ASPECT) end
    return out
end

-- How far (x, y) is outside a convex hull; 0 inside.
local function Outside(h, x, y)
    local n = #h / 2
    if n == 0 then return math.huge end
    y = y * ASPECT
    local inside, best = n >= 3, math.huge
    for i = 1, n do
        local j = i % n + 1
        local ax, ay, bx, by = h[2 * i - 1], h[2 * i] * ASPECT, h[2 * j - 1], h[2 * j] * ASPECT
        if Cross(ax, ay, bx, by, x, y) < 0 then inside = false end
        local dx, dy = bx - ax, by - ay
        local L2 = dx * dx + dy * dy
        local t = L2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / L2)) or 0
        best = math.min(best, math.sqrt((x - ax - t * dx) ^ 2 + (y - ay - t * dy) ^ 2))
    end
    return inside and 0 or best
end

local function Span(h)
    local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, #h, 2 do
        x0, x1 = math.min(x0, h[i]), math.max(x1, h[i])
        y0, y1 = math.min(y0, h[i + 1] * ASPECT), math.max(y1, h[i + 1] * ASPECT)
    end
    return math.max(x1 - x0, y1 - y0)
end

-- The outline as drawn: the hull pushed out by PAD and rounded (Chaikin),
-- cached until the area changes. Flat, closed (last point = first).
local function Outline(a)
    local c = outlines[a]
    if c and c.w == (a.w or 0) then return c.poly, c.box end
    local h, n = a.h, #a.h / 2
    local pts = {}
    if n >= 3 then
        for i = 1, n do
            local p, q, r = (i - 2) % n + 1, i, i % n + 1
            local ax, ay = h[2 * p - 1], h[2 * p] * ASPECT
            local bx, by = h[2 * q - 1], h[2 * q] * ASPECT
            local cx, cy = h[2 * r - 1], h[2 * r] * ASPECT
            local n1x, n1y = by - ay, -(bx - ax)
            local n2x, n2y = cy - by, -(cx - bx)
            local l1, l2 = math.sqrt(n1x * n1x + n1y * n1y), math.sqrt(n2x * n2x + n2y * n2y)
            local nx, ny = n1x / (l1 > 0 and l1 or 1) + n2x / (l2 > 0 and l2 or 1), n1y / (l1 > 0 and l1 or 1) + n2y / (l2 > 0 and l2 or 1)
            local ln = math.sqrt(nx * nx + ny * ny)
            if ln == 0 then nx, ny, ln = 0, 1, 1 end
            -- counter-clockwise hull: (dy, -dx) is the outward normal of each edge
            pts[#pts + 1] = { bx + nx / ln * PAD, by + ny / ln * PAD }
        end
    else -- a point or a line: a small rounded box around it
        local x0, y0 = h[1] or 0.5, (h[2] or 0.5) * ASPECT
        local x1, y1 = h[3] or x0, (h[4] and h[4] * ASPECT) or y0
        pts = { { math.min(x0, x1) - PAD, math.min(y0, y1) - PAD }, { math.max(x0, x1) + PAD, math.min(y0, y1) - PAD },
                { math.max(x0, x1) + PAD, math.max(y0, y1) + PAD }, { math.min(x0, x1) - PAD, math.max(y0, y1) + PAD } }
    end
    for _ = 1, 2 do
        local sm = {}
        for i = 1, #pts do
            local p, q = pts[i], pts[i % #pts + 1]
            sm[#sm + 1] = { 0.75 * p[1] + 0.25 * q[1], 0.75 * p[2] + 0.25 * q[2] }
            sm[#sm + 1] = { 0.25 * p[1] + 0.75 * q[1], 0.25 * p[2] + 0.75 * q[2] }
        end
        pts = sm
    end
    local poly, box = {}, { math.huge, math.huge, -math.huge, -math.huge }
    for i = 1, #pts + 1 do
        local p = pts[(i - 1) % #pts + 1]
        local x, y = p[1], p[2] / ASPECT
        poly[#poly + 1] = x
        poly[#poly + 1] = y
        box[1], box[2] = math.min(box[1], x), math.min(box[2], y)
        box[3], box[4] = math.max(box[3], x), math.max(box[4], y)
    end
    -- a circle that fits inside (the outline is convex), for a quick
    -- "wholly inside" test before any cutting
    local n, cx, cy = #poly / 2 - 1, 0, 0
    for i = 1, n do cx, cy = cx + poly[2 * i - 1], cy + poly[2 * i] end
    cx, cy = cx / n, cy / n
    local rin = math.huge
    for i = 1, n do
        local ax, ay, bx, by = poly[2 * i - 1], poly[2 * i], poly[2 * i + 1], poly[2 * i + 2]
        local ex, ey = bx - ax, by - ay
        local L = math.sqrt(ex * ex + ey * ey)
        if L > 0 then rin = math.min(rin, math.abs((cx - ax) * ey - (cy - ay) * ex) / L) end
    end
    box[5], box[6], box[7] = cx, cy, rin * rin * 0.98
    outlines[a] = { w = a.w or 0, poly = poly, box = box }
    return poly, box
end

-- Is (x, y) inside a closed flat polygon? (even-odd)
local function InPoly(poly, x, y)
    local c, n = false, #poly / 2 - 1
    for i = 1, n do
        local x1, y1, x2, y2 = poly[2 * i - 1], poly[2 * i], poly[2 * i + 1], poly[2 * i + 2]
        if (y1 > y) ~= (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1 then c = not c end
    end
    return c
end

-- The parts of the segment (x1,y1)-(x2,y2) and how much of each to draw,
-- given clips { poly, box, k }: inside a clip's outline a piece is drawn at
-- that clip's k (0 = not at all). Calls out(t0, t1, k) for each part.
local function Clip(clips, x1, y1, x2, y2, out)
    local near
    local lx, hx, ly, hy = math.min(x1, x2), math.max(x1, x2), math.min(y1, y2), math.max(y1, y2)
    for _, c in ipairs(clips) do
        local b = c.box
        if not (hx < b[1] or lx > b[3] or hy < b[2] or ly > b[4]) then
            near = near or {}
            near[#near + 1] = c
        end
    end
    if not near then return out(0, 1, 1) end
    for _, c in ipairs(near) do
        local b = c.box
        if (x1 - b[5]) ^ 2 + (y1 - b[6]) ^ 2 < b[7] and (x2 - b[5]) ^ 2 + (y2 - b[6]) ^ 2 < b[7] then
            -- wholly inside this one: at its k, or less where another covers it too
            local k = c.k
            for _, o in ipairs(near) do
                if o ~= c and o.k < k and InPoly(o.poly, (x1 + x2) / 2, (y1 + y2) / 2) then k = o.k end
            end
            if k > 0.01 then out(0, 1, k) end
            return
        end
    end
    local ts = { 0, 1 }
    local dx, dy = x2 - x1, y2 - y1
    for _, c in ipairs(near) do
        local poly = c.poly
        for i = 1, #poly / 2 - 1 do
            local ax, ay, bx, by = poly[2 * i - 1], poly[2 * i], poly[2 * i + 1], poly[2 * i + 2]
            local ex, ey = bx - ax, by - ay
            local den = dx * ey - dy * ex
            if den ~= 0 then
                local t = ((ax - x1) * ey - (ay - y1) * ex) / den
                local u = ((ax - x1) * dy - (ay - y1) * dx) / den
                if t > 0 and t < 1 and u >= 0 and u <= 1 then ts[#ts + 1] = t end
            end
        end
    end
    table.sort(ts)
    local from, fk
    for i = 1, #ts - 1 do
        local t0, t1 = ts[i], ts[i + 1]
        if t1 > t0 then
            local tm = (t0 + t1) / 2
            local mx, my, k = x1 + dx * tm, y1 + dy * tm, 1
            for _, c in ipairs(near) do
                if c.k < k and InPoly(c.poly, mx, my) then k = c.k end
            end
            if from and k == fk then
                -- extend
            else
                if from and fk > 0.01 then out(from, t0, fk) end
                from, fk = t0, k
            end
        end
    end
    if from and fk > 0.01 then out(from, 1, fk) end
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function Join(a, x, y)
    if Outside(a.h, x, y) == 0 then return end
    local flat = {}
    for i = 1, #a.h do flat[i] = a.h[i] end
    flat[#flat + 1], flat[#flat + 2] = x, y
    a.h = Hull(flat)
    a.w = (a.w or 0) + 1
    S.dirty = true
    return true
end

-- Do two convex hulls' edges cross? (the one way to overlap with no
-- corner of either inside the other)
local function Crosses(h, g)
    local n, m = #h / 2, #g / 2
    for i = 1, n do
        local j = i % n + 1
        local ax, ay, bx, by = h[2 * i - 1], h[2 * i] * ASPECT, h[2 * j - 1], h[2 * j] * ASPECT
        for k = 1, m do
            local l = k % m + 1
            local cx, cy, dx, dy = g[2 * k - 1], g[2 * k] * ASPECT, g[2 * l - 1], g[2 * l] * ASPECT
            if Cross(ax, ay, bx, by, cx, cy) * Cross(ax, ay, bx, by, dx, dy) < 0
                and Cross(cx, cy, dx, dy, ax, ay) * Cross(cx, cy, dx, dy, bx, by) < 0 then return true end
        end
    end
    return false
end

-- How far apart two hulls are; 0 if they overlap. For convex shapes the
-- nearest points are a corner of one and an edge of the other.
local function Gap(h, g)
    local best = math.huge
    for i = 1, #h, 2 do best = math.min(best, Outside(g, h[i], h[i + 1])) end
    for i = 1, #g, 2 do best = math.min(best, Outside(h, g[i], g[i + 1])) end
    if best > 0 and Crosses(h, g) then best = 0 end
    return best
end

-- The area you're in takes in any recent area its outline touches (3.8.3):
-- questing that wandered made side-by-side areas that never joined, so an
-- hour in one hub read as three blobs. Only while you're in it, so an area
-- grows only the way it already does as you play; never past the size cap.
local function Merge(z, a, now)
    local life = TrailSeconds()
    for i = #z.areas, 1, -1 do
        local b = z.areas[i]
        if b ~= a and now - b.e <= life and Gap(a.h, b.h) <= 2 * PAD then
            local flat = {}
            for k = 1, #a.h do flat[#flat + 1] = a.h[k] end
            for k = 1, #b.h do flat[#flat + 1] = b.h[k] end
            local h = Hull(flat)
            if Span(h) <= SpanR() then
                a.h = h
                a.w = (a.w or 0) + (b.w or 0) + 1
                -- visits in time order; the one being recorded stays last
                local live = table.remove(a.v)
                for _, v in ipairs(b.v or {}) do a.v[#a.v + 1] = v end
                table.sort(a.v, function(p, q) return p.s < q.s end)
                a.v[#a.v + 1] = live
                table.remove(z.areas, i)
                if st.inside == b then st.inside = nil end
                if st.trip and st.trip.a == b then st.trip.a = a end
                S.dirty = true
            end
        end
    end
end

-- Were you travelling at point i of a time-ordered list of { x, y, t }?
local function Moving(list, i)
    local p, a, b = list[i], i, i
    while a > 1 and p.t - list[a - 1].t <= MILL_T do a = a - 1 end
    while b < #list and list[b + 1].t - p.t <= MILL_T do b = b + 1 end
    -- each side on its own: an out-and-back turns where both sides are straight
    local function Straight(from, to)
        if from == to then return false end
        local path = 0
        for j = from + 1, to do
            path = path + math.sqrt((list[j].x - list[j - 1].x) ^ 2 + ((list[j].y - list[j - 1].y) * ASPECT) ^ 2)
        end
        local net = math.sqrt((list[to].x - list[from].x) ^ 2 + ((list[to].y - list[from].y) * ASPECT) ^ 2)
        return path > R(MILL_YD) / 2 and net > path * MILL_STRAIGHT
    end
    return Straight(a, i) or Straight(i, b)
end

-- Did a trip only go out along a line and back? Every point lies within
-- TRIP_WIDE_YD of the line from where it started to its furthest point.
local function Narrow(pts)
    local o, far, fd = pts[1], nil, 0
    if not o then return true end
    for _, p in ipairs(pts) do
        local d = (p.x - o.x) ^ 2 + ((p.y - o.y) * ASPECT) ^ 2
        if d > fd then far, fd = p, d end
    end
    if not far then return true end
    local dx, dy = far.x - o.x, (far.y - o.y) * ASPECT
    local L = math.sqrt(dx * dx + dy * dy)
    for _, p in ipairs(pts) do
        local px, py = p.x - o.x, (p.y - o.y) * ASPECT
        if math.abs(px * dy - py * dx) / L > R(TRIP_WIDE_YD) then return false end
    end
    return true
end

local function Leave()
    st.live, st.pend = nil, {}
    S.dirty = true
end

local function Reset()
    if st.live then Leave() end
    st.win, st.pend, st.map, st.clock, st.trip, st.inside = {}, {}, nil, nil, nil, nil
end

local function Begin(a, startWall, now, secs)
    a.v[#a.v + 1] = { s = startWall, e = now, t = secs }
    a.e = now
    st.live, st.pend, st.win = a, {}, {}
    S.dirty = true
end

-- The window has held still long enough: start an area, or carry on one
-- you were in earlier, if this is on or next to it.
-- Your trail from the last RECENT seconds within reach of where an area
-- formed joins it: the wandering before the four minutes were up.
local function JoinRecent(z, a, cx, cy, now)
    local reach = FormR()
    for si = #z.strokes, 1, -1 do
        local s = z.strokes[si]
        if s.e < now - RECENT then break end
        if not s.k then
            local list = {}
            for i = 1, #s / 2 do
                local t = PointTime(s, i)
                if t and t >= now - RECENT then list[#list + 1] = { x = s[2 * i - 1], y = s[2 * i], t = t } end
            end
            for i, p in ipairs(list) do
                if (p.x - cx) ^ 2 + ((p.y - cy) * ASPECT) ^ 2 <= reach * reach and not Moving(list, i) then
                    Join(a, p.x, p.y)
                end
            end
        end
    end
end

local function Form(z, now, clock, cx, cy)
    local win = st.win
    local secs = clock - win[1].t
    local life = TrailSeconds()
    local flat = {}
    for _, p in ipairs(win) do flat[#flat + 1] = p.x flat[#flat + 1] = p.y end
    for i = #z.areas, 1, -1 do
        local a = z.areas[i]
        if now - a.e <= life and Span(a.h) < SpanR() then
            for _, p in ipairs(win) do
                if Outside(a.h, p.x, p.y) <= R(MARGIN_YD) then
                    Begin(a, now - secs, now, secs)
                    for _, q in ipairs(win) do Join(a, q.x, q.y) end
                    JoinRecent(z, a, cx, cy, now)
                    Merge(z, a, now)
                    return
                end
            end
        end
    end
    local a = { h = Hull(flat), v = {}, w = 0 }
    z.areas[#z.areas + 1] = a
    Begin(a, now - secs, now, secs)
    JoinRecent(z, a, cx, cy, now)
    Merge(z, a, now)
end

local function Linger(z, x, y, now, clock, dt)
    local a = st.live
    -- AFK time counts: /afk is often on while you're still playing (Joe)
    local v = a.v[#a.v]
    v.t = v.t + dt
    v.e, a.e = now, now
    local pend = st.pend
    local last = pend[#pend]
    if not last or math.abs(x - last.x) + math.abs(y - last.y) >= C.MIN_STEP then
        pend[#pend + 1] = { x = x, y = y, t = clock }
    end
    if Outside(a.h, x, y) > R(MARGIN_YD) or Span(a.h) > SpanR() then
        -- the walk out hasn't joined; keep it in case you come straight back
        -- (only the ground outside it: the steps inside are inside anyway)
        local outside = {}
        for _, p in ipairs(pend) do
            if Outside(a.h, p.x, p.y) > 0 then outside[#outside + 1] = p end
        end
        local trip = Span(a.h) <= SpanR() and { a = a, t = clock, pts = outside } or nil
        Leave()
        st.trip = trip
        st.win = { { x = x, y = y, t = clock } }
        return
    end
    local grew
    while pend[1] and clock - pend[1].t >= LAG do
        local p = table.remove(pend, 1)
        grew = Join(a, p.x, p.y) or grew
    end
    if grew then Merge(z, a, now) end
end

local function Watch(z, x, y, now, clock)
    -- a short trip past the edge: follow it while it lasts
    local trip = st.trip
    if trip then
        if clock - trip.t > TRIP_T or Outside(trip.a.h, x, y) > R(TRIP_YD) then
            st.trip = nil -- gone too long or too far: you left
        else
            local last = trip.pts[#trip.pts]
            if not last or math.abs(x - last.x) + math.abs(y - last.y) >= C.MIN_STEP then
                trip.pts[#trip.pts + 1] = { x = x, y = y, t = clock }
            end
        end
    end
    -- back inside an area you only just left
    for i = #z.areas, 1, -1 do
        local a = z.areas[i]
        if now - a.e <= REENTER and Outside(a.h, x, y) == 0 then
            -- straight back from a short trip: its ground joins, unless it
            -- only went out along a line and back (a corridor stays a line)
            if st.trip and st.trip.a == a and not Narrow(st.trip.pts) then
                for _, p in ipairs(st.trip.pts) do Join(a, p.x, p.y) end
            end
            st.trip = nil
            -- a new visit record even after a step outside, so a visit's
            -- times only ever cover time inside (the map relies on it);
            -- the tooltip shows visits under 2 minutes apart as one
            Begin(a, now, now, 0)
            return
        end
    end
    -- inside an older area still on your trail: a minute there reopens it;
    -- passing through doesn't
    -- (inside its outline; a few seconds out at the edge don't restart the count)
    local life, inside = TrailSeconds(), nil
    for i = #z.areas, 1, -1 do
        local a = z.areas[i]
        if now - a.e <= life and Outside(a.h, x, y) <= PAD then inside = a break end
    end
    if inside then
        if st.inside ~= inside then st.inside, st.insideT, st.insideW = inside, clock, now end
        st.insideSeen = clock
        if clock - st.insideT >= REOPEN_T then
            local since = clock - st.insideT
            st.inside = nil
            Begin(inside, st.insideW, now, since)
            return
        end
    elseif st.inside and clock - (st.insideSeen or 0) > 15 then
        st.inside = nil
    end
    local win = st.win
    local last = win[#win]
    if not last or math.abs(x - last.x) + math.abs(y - last.y) >= C.MIN_STEP then
        win[#win + 1] = { x = x, y = y, t = clock }
    end
    while win[2] and clock - win[2].t >= FORM_T do table.remove(win, 1) end
    if #win < FORM_N or clock - win[1].t < FORM_T - 5 then return end
    -- moving about through those minutes, not a few steps then standing
    local slices, seen = 0, {}
    for _, p in ipairs(win) do
        local b = math.floor((clock - p.t) / 60)
        if b < FORM_T / 60 and not seen[b] then seen[b], slices = true, slices + 1 end
    end
    if slices < FORM_T / 60 - 1 then return end
    local cx, cy = 0, 0
    for _, p in ipairs(win) do cx, cy = cx + p.x, cy + p.y end
    cx, cy = cx / #win, cy / #win
    local r = FormR()
    for _, p in ipairs(win) do
        if (p.x - cx) ^ 2 + ((p.y - cy) * ASPECT) ^ 2 > r * r then return end
    end
    Form(z, now, clock, cx, cy)
end

-- Called with every position sample (twice a second). mode: flights and
-- corpse runs aren't lingering.
local function Step(mapID, x, y, mode)
    local clock, now = GetTime(), time()
    if not mapID or mode or S.inInstance then return Reset() end
    local gap = st.clock and clock - st.clock or 0
    local jump = st.x and ((x - st.x) ^ 2 + (y - st.y) ^ 2 > C.JUMP_STEP * C.JUMP_STEP)
    if mapID ~= st.map or gap > GAP or jump then
        Reset()
        st.map = mapID
        gap = 0
    end
    st.clock, st.x, st.y, st.yd = clock, x, y, MapYards(mapID)
    local z = ZoneData(mapID)
    z.areas = z.areas or {}
    if st.live then
        Linger(z, x, y, now, clock, math.min(2, gap))
    else
        Watch(z, x, y, now, clock)
    end
end

-- An area's visits as a person would tell them: visits under 10 minutes
-- apart are one, and anything under 2 minutes folds into its neighbour
-- (stepping in and out at the edge made a list of "1 min" entries).
local function Visits(a)
    local out = {}
    for _, v in ipairs(a.v or {}) do
        local last = out[#out]
        if last and v.s - last.e < VISIT_MERGE then
            last.e, last.t = math.max(last.e, v.e), last.t + (v.t or 0)
        else
            out[#out + 1] = { s = v.s, e = v.e, t = v.t or 0 }
        end
    end
    local i = 1
    while i <= #out and #out > 1 do
        if out[i].t < VISIT_MIN then
            local n = out[i > 1 and i - 1 or i + 1]
            n.t, n.s, n.e = n.t + out[i].t, math.min(n.s, out[i].s), math.max(n.e, out[i].e)
            table.remove(out, i)
        else
            i = i + 1
        end
    end
    return out
end

ns.Linger = {
    LAG = LAG, SHOW = SHOW, CURVE = CURVE, TAPER = TAPER, Visits = Visits, MapYards = MapYards,
    Step = Step, Reset = Reset, Outline = Outline, Clip = Clip, InPoly = InPoly,
    Live = function() return st.live end,
    State = function() return st end, -- for tests
}
