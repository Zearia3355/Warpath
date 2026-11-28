-- Warpath: Chronicle
-- The chronicle as a book (3.8.5): the book art (Art/book, drawn by
-- tools/art), five tabs on its top edge (Campaigns, Grudges and Ledger left
-- of the title plate, Settings and Warpath right of it), routing between
-- the pages, opening, What's New after an update, refreshing, and the
-- popups. Each page is its own file (ChronCampaigns, ChronGrudges,
-- ChronWarpath; Settings in Options.lua) and registers in Chron.pages.
-- The shared art and type are Book.lua.
local ADDON, ns = ...
local C = ns.C
local Print, UISound = ns.Print, ns.UISound
local Campaign, Grudge = ns.Campaign, ns.Grudge
local Book = ns.Book
local O = Book.Old

local db, gdb, cfg, myName
ns.OnBind(function() db, gdb, cfg, myName = ns.db, ns.gdb, ns.cfg, ns.myName end)

local W, H, PAD, PW, PH = Book.W, Book.H, Book.PAD, Book.PW, Book.PH

local view = { section = "campaigns", list = {}, page = 1, preview = false, grudges = {}, pick = 1,
    newsStack = {} }

-- What the page files share: the view, the book once built, Render, and
-- each page's Build/Render/Reset.
local Chron = { view = view, pages = {} }
ns.Chron = Chron

---------------------------------------------------------------------------
-- The book: art, two page frames, title plate, close, tabs
---------------------------------------------------------------------------

local Render

-- A page frame: where the old pages anchor (Grudges, Warpath, Settings),
-- with its folio. The parchment itself is the book art.
local function Page(f, left)
    local p = CreateFrame("Frame", nil, f)
    p:SetSize(PW, PH)
    if left then p:SetPoint("TOPLEFT", PAD, -PAD) else p:SetPoint("TOPRIGHT", -PAD, -PAD) end
    p.number = O.Font(p, QuestFontNormalSmall, GameFontNormalSmall, O.FADED)
    p.number:SetPoint("BOTTOM", 0, 14)
    p.number:SetJustifyH("CENTER")
    return p
end

-- The five tabs (ledger/lbase.py TABS_A): 92 units wide, render px.
local TABS = {
    { "Campaigns", "campaigns", 65, 175 }, { "Grudges", "grudges", 183, 293 }, { "Ledger", "ledger", 301, 411 },
    { "Settings", "settings", 813, 923 }, { "Warpath", "warpath", 931, 1041 },
}
Chron.TABS = TABS

-- Drawn as the game drew them (a dark box with a gold edge), the open one
-- taller and lit. They stand behind the book, whose leather covers their foot.
local function SectionTab(f, spec)
    local t = CreateFrame("Button", nil, f)
    t:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    t.edge = Book.Solid(t, "BACKGROUND", { 56, 16, 5 }, 1)
    t.rim = Book.Solid(t, "BORDER", { 190, 154, 100 }, 1)
    t.bg = Book.Solid(t, "ARTWORK", { 21, 15, 10 }, 1)
    t.lit = Book.Solid(t, "ARTWORK", { 82, 61, 23 }, 1, 1)
    t.text = Book.Str(t, "friz", 16, { 196, 196, 196 })
    Book.Shadow(t.text)
    t.text:SetText(spec[1])
    t.key, t.x0, t.x1 = spec[2], spec[3], spec[4]
    t:SetScript("OnClick", function()
        if view.section ~= t.key then
            view.section = t.key
            UISound("IG_ABILITY_PAGE_TURN", 836)
            Render()
        end
    end)
    local hl = t:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1, 0.82, 0, 0.10)
    hl:SetAllPoints(t.bg)
    return t
end

local function LayTab(f, t, on)
    local x0, x1 = t.x0, t.x1
    local top = on and 12 or 20
    Book.Box(t, x0 - 1, top - 1, x1 + 2, 46, f)
    local o = { t, x0 - 1, top - 1 }
    Book.Box(t.edge, x0 - 1, top - 1, x1 + 2, 46, o[1], o[2], o[3])
    Book.Box(t.rim, x0, top, x1 + 1, 46, o[1], o[2], o[3])
    Book.Box(t.bg, x0 + 3, top + 3, x1 - 2, 46, o[1], o[2], o[3])
    Book.Box(t.lit, x0 + 3, top + 3, x1 - 2, top + 4, o[1], o[2], o[3])
    t.lit:SetShown(on)
    local r, g, b = Book.RGB(on and { 45, 25, 9 } or { 21, 15, 10 })
    t.bg:SetColorTexture(r, g, b, 1)
    Book.Color(t.text, on and { 255, 209, 0 } or { 196, 196, 196 })
    Book.Put(t.text, (x0 + x1) / 2, top + (on and 21 or 17), "m", t, o[2], o[3])
end

local function BuildBook()
    local f = CreateFrame("Frame", "WarpathChronicle", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", -40, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "WarpathChronicle")
    f:SetScript("OnHide", function()
        UISound("IG_QUEST_LOG_CLOSE", 845)
        -- opened by an update: closing the book, however, marks it seen
        if view.newsPending then
            view.newsPending = nil
            gdb.seenVersion = ns.VERSION
            gdb.installed = gdb.installed or ns.VERSION
        end
    end)

    f.shadow = Book.Art(f)
    f.left, f.right = Page(f, true), Page(f, false)

    -- title plate and close button: the game's
    local plate = f:CreateTexture(nil, "OVERLAY")
    plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    plate:SetSize(380, 64)
    plate:SetPoint("TOP", 0, 14)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", plate, "TOP", 0, -14)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    -- the template's click goes through HideUIPanel, which the secure panel
    -- manager ignores in combat; the book is a plain frame, so hide it directly
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabs = {}
    for i, spec in ipairs(TABS) do f.tabs[i] = SectionTab(f, spec) end
    return f
end

---------------------------------------------------------------------------
-- The Ledger tab: its pages come in a later phase (Claude's call: one line
-- on the left page meanwhile)
---------------------------------------------------------------------------

local function BuildLedgerPages(f)
    local L = CreateFrame("Frame", nil, f)
    L:SetAllPoints(f)
    f.ledger = { L = L }
    local s = Book.Str(L, "gari", 18, Book.FADED)
    s:SetText("The Ledger is being written.")
    Book.Put(s, 296, 380, "m")
end
Chron.pages.ledger = {
    Build = BuildLedgerPages,
    Render = function() Chron.book.left.number:SetText("") Chron.book.right.number:SetText("") end,
}

---------------------------------------------------------------------------
-- Settings (3.8.3): built by Options.lua on the book's pages; its look is
-- a later phase
---------------------------------------------------------------------------

local function BuildSettingsPages(f)
    local L = CreateFrame("Frame", nil, f.left)
    L:SetAllPoints()
    local R = CreateFrame("Frame", nil, f.right)
    R:SetAllPoints()
    f.set = { L = L, R = R }
    if ns.Settings then
        ns.Settings.Build(L, R, { Font = O.Font,
            Topic = function(p, text, x, y) return O.Topic(p, text, x, y) end,
            Diamond = O.Diamond, Ornament = O.Ornament, INK = O.INK, FADED = O.FADED, RUBRIC = O.RUBRIC,
            GREY = O.GREY, INNER = PW - 64 })
    end
end
Chron.pages.settings = {
    Build = BuildSettingsPages,
    Render = function()
        Chron.book.left.number:SetText("")
        Chron.book.right.number:SetText("")
        if ns.Settings then ns.Settings.Render() end
    end,
}

---------------------------------------------------------------------------
-- Rendering and opening
---------------------------------------------------------------------------

-- Each page's frames: the pairs Build left in book[key] ({ L, R }).
local HOLDS = { campaigns = "camp", grudges = "gr", warpath = "news", settings = "set", ledger = "ledger" }

function Render()
    local book = Chron.book
    if not book then return end
    book.title:SetText("Chronicle of " .. (myName or "you"))
    local sec = view.section
    for key, hold in pairs(HOLDS) do
        local pages = book[hold]
        if pages then
            if pages.L then pages.L:SetShown(sec == key) end
            if pages.R then pages.R:SetShown(sec == key) end
        end
    end
    for _, t in ipairs(book.tabs) do LayTab(book, t, t.key == sec) end
    local page = Chron.pages[sec] or Chron.pages.warpath
    if page.broken then return end
    local ok, err, stack = Chron.Try(page.Render)
    if not ok then Chron.Fail(sec, "draw", err, stack) end
end
Chron.Render = Render

local function Popups()
    if not StaticPopupDialogs or StaticPopupDialogs.WARPATH_GRUDGE_NAME then return end
    local function EditBoxOf(self) return self.editBox or self.EditBox end
    StaticPopupDialogs.WARPATH_GRUDGE_NAME = {
        text = "Inscribe a grudge against whom?\n(Name, or Name-Realm)",
        button1 = "Inscribe", button2 = CANCEL or "Cancel",
        hasEditBox = true, maxLetters = 60,
        OnAccept = function(self)
            local name = EditBoxOf(self):GetText():gsub("%s", "")
            if name ~= "" then ns.Dispatch("grudge " .. name) end
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            local name = self:GetText():gsub("%s", "")
            if name ~= "" then ns.Dispatch("grudge " .. name) end
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopupDialogs.WARPATH_GRUDGE_FORGIVE = {
        text = "Forgive %s?\nTheir name is struck from your ledger.",
        button1 = "Forgive", button2 = CANCEL or "Cancel",
        OnAccept = function(_, full) if full then Grudge.Forgive(full) end end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end

local ORDER = { "campaigns", "grudges", "warpath", "settings", "ledger" }

-- One page that fails to build or draw doesn't take the book down with it
-- (3.8.5-test1 lost every tab to one font error): one chat line, the rest
-- of the book works, and the error is kept for whoever fixes it.
-- fn(...) under xpcall: ok, the error, and where it happened
function Chron.Try(fn, ...)
    local args, stack = { ... }, nil
    local ok, err = xpcall(function() return fn(unpack(args)) end,
        function(e) stack = debugstack and debugstack(2, 12, 0) or nil return e end)
    return ok, err, stack
end

function Chron.Fail(key, what, err, stack)
    local page = Chron.pages[key]
    if page then page.broken = true end
    ns.Print(("the chronicle couldn't %s its %s page: %s"):format(what, key, tostring(err)))
    if gdb then
        gdb.bookErrors = gdb.bookErrors or {}
        table.insert(gdb.bookErrors, 1, { t = time(), v = ns.VERSION, page = key, what = what, err = tostring(err),
            stack = stack })
        while #gdb.bookErrors > 5 do table.remove(gdb.bookErrors) end
    end
end

local function Build()
    local book = BuildBook()
    Chron.book = book
    for _, key in ipairs(ORDER) do
        local p = Chron.pages[key]
        if p and p.Build then
            local ok, err, stack = Chron.Try(p.Build, book)
            if not ok then Chron.Fail(key, "build", err, stack) end
        end
    end
    Popups()
end

local Chronicle = {}

-- section: "campaigns" (default), "grudges", "ledger", "settings" or "warpath".
function Chronicle.Open(preview, section)
    -- 3.8.3: opens by hand inside a battleground too (it only reads). It
    -- still closes on the way in and never opens there by itself.
    local first = not Chron.book
    if first then Build() end
    local book = Chron.book
    view.preview = preview and true or false
    view.section = section or (preview and view.section) or "campaigns"
    view.page, view.pick = 1, 1
    view.newsStart, view.newsLine, view.newsStack, view.newsNext, view.newSince = nil, nil, {}, nil, nil
    for key, p in pairs(Chron.pages) do
        if p.Open and not p.broken then
            local ok, err, stack = Chron.Try(p.Open, preview)
            if not ok then Chron.Fail(key, "open", err, stack) end
        end
    end
    for key, p in pairs(Chron.pages) do
        if p.Reset and not p.broken then
            local ok, err, stack = Chron.Try(p.Reset, book)
            if not ok then Chron.Fail(key, "open", err, stack) end
        end
    end
    Render()
    if not book:IsShown() then UISound("IG_QUEST_LOG_OPEN", 844) end
    book:Show()
    -- an addon font may apply only after the first draw: lay out again if
    -- what the faces measure changes
    Book.Settle(function() if book:IsShown() then Render() end end)
end

function Chronicle.Toggle()
    local book = Chron.book
    if book and book:IsShown() and not view.preview then book:Hide() else Chronicle.Open() end
end

function Chronicle.Hide() if Chron.book then Chron.book:Hide() end end

-- After an update (or a first install): open on the Warpath tab, marking
-- the releases newer than `since` (nil on a first install: nothing marked).
-- Closing the book marks this release seen (OnHide).
function Chronicle.News(since)
    Chronicle.Open(false, "warpath")
    local book = Chron.book
    if not (book and book:IsShown()) then return end
    view.newSince, view.newsPending = since, true
    Render()
end

function Chronicle.Shown() return Chron.book and Chron.book:IsShown() and view.section end

function Chronicle.Refresh()
    local book = Chron.book
    if book and book:IsShown() and not view.preview then
        local p = Chron.pages[view.section]
        if p and p.Refresh then p.Refresh() end
        Render()
    end
end

-- The campaign on the open page (for /warpath chronicle share).
function Chronicle.Current()
    local book = Chron.book
    if book and book:IsShown() and not view.preview and view.section == "campaigns" then return view.list[view.page] end
end

function ns.ChronicleShareMenu(owner)
    if view.preview then Print("these are sample pages; there's nothing real to share.") return end
    local c = view.list[view.page]
    local function To(where, who) return function() Campaign.Share(c, where, who) end end
    local items = {
        { text = "Guild", func = To("guild") },
        { text = "Party / raid", func = To("party") },
        { text = "Say", func = To("say") },
    }
    local target = UnitExists("target") and UnitIsPlayer("target") and UnitName("target")
    if target and target ~= myName then
        items[#items + 1] = { text = "Whisper " .. target, func = To("whisper", target) }
    end
    if not ns.Menu(owner, "Share this campaign", items) then Campaign.Share(c, "guild") end
end

ns.Chronicle = Chronicle
