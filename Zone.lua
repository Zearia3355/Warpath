-- Warpath: Zone
-- Your record in a zone, when you enter it: a chat line, and a line under
-- the game's big zone name. Each can be turned off on its own.
local ADDON, ns = ...
local C, S = ns.C, ns.S
local Long, MapName, Miles, Print, Recent, Secret = ns.Long, ns.MapName, ns.Miles, ns.Print, ns.Recent, ns.Secret
local Fields = ns.Fields

local db, gdb, cfg
ns.OnBind(function() db, gdb, cfg = ns.db, ns.gdb, ns.cfg end)

local Zone = {}
local DOT = " \194\183 "
local leftAt, shownAt, inZone = {}, {}, nil

-- Neutral-town ground doesn't count: enemies are expected there. The
-- counts stay saved (3.6.4: hidden, not wiped).
local function Sighted(z)
    local n, town = 0, z.town or {}
    for c, v in pairs(z.sight) do
        if not town[c] then n = n + v end
    end
    return n
end

local function Active(z)
    return z.kills + z.pdeaths >= 3 or Miles(z.yards) >= 1
end

-- At most one tag, only when true: deadliest, bloodiest, most travelled, most watched.
local function Rank(mapID)
    local z = db.maps[mapID]
    if not z or not Active(z) then return end
    local best = { d = 0, k = 0, y = 0, s = 0 }
    for _, o in pairs(db.maps) do
        if Active(o) then
            best.d = math.max(best.d, o.pdeaths)
            best.k = math.max(best.k, o.kills)
            best.y = math.max(best.y, o.yards)
            best.s = math.max(best.s, Sighted(o))
        end
    end
    if z.pdeaths > 0 and z.pdeaths >= best.d then return "your deadliest zone" end
    if z.kills > 0 and z.kills >= best.k then return "your bloodiest ground" end
    if z.yards > 0 and z.yards >= best.y then return "your most-travelled zone" end
    local seen = Sighted(z)
    if seen > 0 and seen >= best.s then return "your most-watched zone" end
end

function Zone.Stats(mapID)
    local z = db.maps[mapID]
    if not z then return end
    return { kills = z.kills, deaths = z.pdeaths, miles = Miles(z.yards), sighted = Sighted(z),
        avenged = z.avenged or 0, best = z.bestStreak or 0, rank = Rank(mapID) }
end

local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- "9 kills, 7 deaths, 18.4 miles · 41 enemies sighted · ..." (zeros left out)
function Zone.ChatText(st)
    local head = {}
    if st.kills > 0 then head[#head + 1] = Plural(st.kills, "kill", "kills") end
    if st.deaths > 0 then head[#head + 1] = Plural(st.deaths, "death", "deaths") end
    if st.miles >= 0.1 then head[#head + 1] = ("%.1f miles"):format(st.miles) end
    local parts = { #head > 0 and table.concat(head, ", ") or nil }
    if st.sighted > 0 then parts[#parts + 1] = Plural(st.sighted, "enemy sighted", "enemies sighted") end
    if st.avenged > 0 then parts[#parts + 1] = Plural(st.avenged, "death avenged", "deaths avenged") end
    if st.best > 0 then parts[#parts + 1] = "best streak " .. st.best end
    if st.rank then parts[#parts + 1] = st.rank end
    return table.concat(parts, DOT)
end

-- "9 kills · 7 deaths · 18.4 mi — your deadliest zone"
function Zone.HeaderText(st)
    local parts = {}
    if st.kills > 0 then parts[#parts + 1] = Plural(st.kills, "kill", "kills") end
    if st.deaths > 0 then parts[#parts + 1] = Plural(st.deaths, "death", "deaths") end
    if st.miles >= 0.1 then parts[#parts + 1] = ("%.1f mi"):format(st.miles) end
    if #parts == 0 and st.sighted > 0 then parts[1] = Plural(st.sighted, "enemy sighted", "enemies sighted") end
    local text = table.concat(parts, DOT)
    if st.rank then text = text .. " \226\128\148 " .. st.rank end
    return text
end

---------------------------------------------------------------------------
-- The line under the zone name
---------------------------------------------------------------------------

local header

local function Anchor()
    for _, fs in ipairs({ PVPInfoTextString, SubZoneTextString, ZoneTextString }) do
        if fs and fs.IsShown and fs:IsShown() and (fs:GetText() or "") ~= "" then return fs end
    end
end

local function HeaderUpdate(self, elapsed)
    self.t = self.t + elapsed
    local zf = ZoneTextFrame
    local a
    if zf and zf:IsShown() and self.t < 15 then
        self.followed = true
        a = zf:GetAlpha()
    elseif self.followed then
        a = 0 -- the game's zone text is gone: so are we
    else
        -- no zone text to follow: fade in, hold, fade out on our own
        local t = self.t
        a = t < 0.5 and t / 0.5 or t < 4 and 1 or t < 6 and 1 - (t - 4) / 2 or 0
    end
    self:SetAlpha(a)
    if a <= 0 and self.t > 0.5 then self:Hide() end
end

local function ShowHeader(text)
    if not header then
        header = CreateFrame("Frame", "WarpathZoneHeader", UIParent)
        header:SetSize(900, 28)
        header:SetFrameStrata("MEDIUM")
        header.text = header:CreateFontString(nil, "OVERLAY")
        if not pcall(header.text.SetFontObject, header.text, SubZoneTextFont or GameFontNormalLarge) then
            header.text:SetFontObject(GameFontNormalLarge)
        end
        header.text:SetPoint("TOP")
        header.text:SetTextColor(1, 0.82, 0)
        header.text:SetShadowOffset(1, -1)
        header.text:SetShadowColor(0, 0, 0, 1)
        header:SetScript("OnUpdate", HeaderUpdate)
    end
    header:ClearAllPoints()
    local anchor = Anchor()
    if anchor then
        header:SetPoint("TOP", anchor, "BOTTOM", 0, -6)
    else
        header:SetPoint("TOP", UIParent, "TOP", 0, -300)
    end
    header.text:SetText(text)
    header.t, header.followed = 0, false
    header:SetAlpha(0)
    header:Show()
end

function Zone.HideHeader() if header then header:Hide() end end

---------------------------------------------------------------------------
-- Entering a zone
---------------------------------------------------------------------------

-- On entering a zone, and again on coming back after 30+ minutes away.
-- test: show it now regardless (/warpath zone test).
function Zone.Enter(test)
    if S.inInstance then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or Secret(mapID) then return end
    local now = time()
    if not test then
        if inZone == mapID then return end
        if inZone then leftAt[inZone] = now end
        inZone = mapID
        if shownAt[mapID] and leftAt[mapID] and now - leftAt[mapID] < C.ZONE_REENTRY then return end
    end
    local st = Zone.Stats(mapID)
    if not st or (st.kills + st.deaths + st.sighted == 0 and st.miles < 0.1) then
        if test then Print("nothing recorded in this zone yet, so entering it says nothing.") end
        return
    end
    shownAt[mapID] = now
    if cfg.zoneChat or test then
        Print(MapName(mapID) .. ": " .. Zone.ChatText(st) .. ".")
    end
    if (cfg.zoneText or test) and not cfg.quiet then ShowHeader(Zone.HeaderText(st)) end
end

-- /warpath zone: the same stats plus the extras.
function Zone.Report()
    local mapID = C_Map.GetBestMapForUnit("player")
    local z = mapID and not Secret(mapID) and db.maps[mapID]
    if not z then Print("nothing recorded in this zone yet.") return end
    local st = Zone.Stats(mapID)
    local text = Zone.ChatText(st)
    Print(MapName(mapID) .. ": " .. (text ~= "" and text or "nothing of note yet") .. ".")
    local goldN, silverN, recent, now = 0, 0, 0, time()
    for _, e in pairs(z.road) do
        local long = Long(e, now)
        if long >= db.roadMin then goldN = goldN + 1
        elseif long >= db.roadMin * C.SILVER_SHARE then silverN = silverN + 1 end
        if Recent(e, now) >= C.RECENT_MIN then recent = recent + 1 end
    end
    Print(("Ground remembered: %d stretches of gold road, %d of silver, %d with today's footsteps. Killing fields: %d.")
        :format(goldN, silverN, recent, #Fields(mapID)))
    local victims, names = {}, {}
    for _, m in ipairs(z.marks) do
        if m[4] == "kill" and m.n then
            local key = m.f or m.n
            victims[key], names[key] = (victims[key] or 0) + 1, m.n
        end
    end
    local who, most = nil, 0
    for k, n in pairs(victims) do if n > most then who, most = k, n end end
    if who then Print(("Most killed here: %s (%d)."):format(names[who], most)) end
end

ns.Zone = Zone
