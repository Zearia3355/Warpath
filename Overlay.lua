-- Warpath: Overlay
-- Big text for your own multi-kills and streaks (and dangerous-ground
-- warnings): a raid-warning look in Warpath's own frame, in its own lane
-- just below the kill caption. One frame, upgraded in place: a new kill
-- while it shows changes the title, punches again and restarts the timer.
-- Clicks pass through it.
local ADDON, ns = ...
local C, S = ns.C, ns.S

local cfg
ns.OnBind(function() cfg = ns.cfg end)

local Overlay = {}
local frame, inner, sound
local SIZES = { small = { 22, 12 }, medium = { 28, 14 }, large = { 36, 17 } }
local PUNCH, HOLD, FADE, ALPHA = 0.15, 1.2, 0.4, 0.9

-- Escalating Blizzard sounds per tier (name in SOUNDKIT, numeric fallback).
local SOUNDS = {
    double = { "PVP_THROUGH_QUEUE", 8459 }, triple = { "READY_CHECK", 8960 },
    quad = { "RAID_WARNING", 8959 }, bloodbath = { "LEVELUPSOUND", 888 },
    streak = { "READY_CHECK", 8960 }, legend = { "LEVELUPSOUND", 888 },
    danger = { "RAID_WARNING", 8959 }, contested = { "IG_QUEST_LOG_OPEN", 875 },
}

local function Build()
    frame = CreateFrame("Frame", "WarpathBigText", UIParent)
    frame:SetSize(800, 90)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(false)
    if frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(false) end
    inner = CreateFrame("Frame", nil, frame)
    inner:SetSize(800, 90)
    inner:SetPoint("CENTER")
    inner:EnableMouse(false)
    inner.title = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    inner.title:SetPoint("TOP", 0, 0)
    inner.sub = inner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    inner.sub:SetPoint("TOP", inner.title, "BOTTOM", 0, -3)
    for _, fs in ipairs({ inner.title, inner.sub }) do
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
    end
    frame:Hide()
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.t = self.t + elapsed
        local t = self.t
        if t < PUNCH then
            inner:SetScale(1 + (self.punch - 1) * (1 - t / PUNCH))
        else
            inner:SetScale(1)
        end
        local a = ALPHA
        if t > PUNCH + HOLD then a = ALPHA * math.max(0, 1 - (t - PUNCH - HOLD) / FADE) end
        self:SetAlpha(a)
        if t >= PUNCH + HOLD + FADE then self:Hide() end
    end)
end

-- Where the lane is: just below the kill caption's bottom edge.
local function LaneY()
    local bottom = ns.CaptionBottom and ns.CaptionBottom()
    if bottom then return bottom - 8 end
    local top = ns.CardTop and ns.CardTop() or -math.floor(UIParent:GetHeight() * 0.165)
    return top - 68
end

local function SetFont(fs, size)
    local path, _, flags = fs:GetFont()
    if path then pcall(fs.SetFont, fs, path, size, flags) end
end

function Overlay.Busy()
    return frame and frame:IsShown() and frame.t < PUNCH + HOLD
end

-- o = { title, sub, r, g, b, small (streak ended, ground), sound key }
function Overlay.Show(o)
    if S.inInstance then return end
    if not frame then Build() end
    local size = SIZES[cfg.overlaySize] or SIZES.medium
    local k = o.small and 0.72 or 1
    SetFont(inner.title, math.floor(size[1] * k + 0.5))
    SetFont(inner.sub, size[2])
    inner.title:SetText(o.title or "")
    inner.title:SetTextColor(o.r or 1, o.g or 0.82, o.b or 0)
    inner.sub:SetText(o.sub or "")
    inner.sub:SetTextColor(o.sr or 1, o.sg or 1, o.sb or 1)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, LaneY())
    frame.t, frame.punch = 0, o.small and 1.1 or 1.25
    inner:SetScale(frame.punch)
    frame:SetAlpha(ALPHA)
    frame:Show()
    -- the previous tier's sound stops first
    if sound and StopSound then pcall(StopSound, sound) sound = nil end
    local snd = o.sound and SOUNDS[o.sound]
    if snd and cfg.sound and not cfg.quiet then
        local id = (SOUNDKIT and SOUNDKIT[snd[1]]) or snd[2]
        local ok, will, handle = pcall(PlaySound, id, "Master")
        if ok and will then sound = handle end
    end
end

function Overlay.Hide() if frame then frame:Hide() end end

ns.Overlay = Overlay
