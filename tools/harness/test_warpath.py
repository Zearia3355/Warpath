#!/usr/bin/env python3
"""Warpath's tests, run against the real addon code under Lua 5.1.

    python tools/harness/test_warpath.py            # everything that needs no game data
    WARPATH_WTF="...\\WTF\\Account\\NAME" python tools/harness/test_warpath.py
                                                    # also boot every real character

Stdlib unittest only, so CI needs nothing beyond lupa.
"""

import hashlib
import os
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import LuaFailure, Wow  # noqa: E402


def lua_count(wow, expr):
    return wow.eval(f"(function() local n = 0 for _ in pairs({expr} or {{}}) do n = n + 1 end return n end)()")


class Boot(unittest.TestCase):
    def test_fresh_character_reaches_current_saved_data_version(self):
        wow = Wow().login()
        self.assertEqual(wow.eval("WarpathDB.v"), 10)

    def test_version_comes_from_the_toc(self):
        wow = Wow()
        self.assertEqual(wow.eval("ns.VERSION"), wow.H.meta["Version"])

    def test_creates_no_globals_beyond_the_documented_ones(self):
        # Warpath, its saved variables, slash commands, its own named frames
        # and the libraries it embeds. Anything else is a leaked local.
        wow = Wow().login()
        allowed = re.compile(r"^(Warpath\w*|SLASH_WARPATH\w*|LibStub|LibDBIcon\w*)$")
        leaked = [g for g in wow.new_globals() if not allowed.match(g)]
        self.assertEqual(leaked, [])

    def test_every_documented_command_runs(self):
        wow = Wow().login()
        for cmd in ("", "help", "help all", "zone", "zone test", "share status", "debug",
                    "debug kills", "debug haze", "map", "map", "history", "history",
                    "trail 90", "trail 1h", "memory 14", "roads 2.5", "icons 100",
                    "overlay test", "grudges", "chronicle chat", "nonsense"):
            with self.subTest(cmd=cmd):
                wow.run(f'SlashCmdList.WARPATH({cmd!r:s})'.replace("'", '"'))

    def test_survives_an_hour_of_play(self):
        # The sampling ticker, sightings sweep and saved-data pruning all run.
        wow = Wow().login()
        for _ in range(12):
            wow.H.player.x = wow.H.player.x + 0.01
            wow.advance(300)
        self.assertGreater(lua_count(wow, "WarpathDB.maps[1448] and WarpathDB.maps[1448].strokes"), 0)


class Settings(unittest.TestCase):
    """3.8's one-time map reset, /warpath clear trail and /warpath roads."""

    OLD = """WarpathGlobal = { installed = "3.7.11", seenVersion = "3.7.11", cfg = {
        trailMin = 60, iconScale = 140, shown = false, runHours = 6, guildHaze = false,
        layers = { battle = false, roads = true, recent = false, runs = true, marks = true,
                   sightings = false, shared = true } } }"""

    def upgraded(self):
        wow = Wow()
        wow.run(self.OLD)
        return wow.login()

    def test_upgrade_turns_every_layer_on_and_sets_the_trail(self):
        wow = self.upgraded()
        for name in ("battle", "roads", "recent", "runs", "marks", "sightings", "shared"):
            with self.subTest(layer=name):
                self.assertTrue(wow.eval(f"ns.cfg.layers.{name}"))
        self.assertTrue(wow.eval("ns.cfg.guildHaze"))
        self.assertEqual(wow.eval("ns.cfg.trailMin"), 720)
        self.assertTrue(wow.eval("ns.S.mapWasReset"))

    def test_upgrade_keeps_the_other_map_settings(self):
        wow = self.upgraded()
        self.assertEqual(wow.eval("ns.cfg.iconScale"), 140)
        self.assertFalse(wow.eval("ns.cfg.shown"))
        self.assertEqual(wow.eval("ns.cfg.runHours"), 6)

    def test_the_reset_happens_only_once(self):
        wow = self.upgraded()
        wow.run('SlashCmdList.WARPATH("layer battle off")')
        wow.run('SlashCmdList.WARPATH("trail 1h")')
        wow.login()  # the next login
        self.assertFalse(wow.eval("ns.cfg.layers.battle"))
        self.assertEqual(wow.eval("ns.cfg.trailMin"), 60)

    def test_a_new_install_gets_the_12_hour_trail_and_no_reset_note(self):
        wow = Wow().login()
        self.assertEqual(wow.eval("ns.cfg.trailMin"), 720)
        self.assertFalse(wow.eval("ns.S.mapWasReset"))

    def test_clear_trail_clears_the_trail_and_keeps_the_rest(self):
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        for i in range(40):
            wow.H.player.x = 0.4 + i * 0.003
            wow.advance(5)
        z = "WarpathDB.maps[1448]"
        self.assertGreater(lua_count(wow, f"{z}.strokes"), 0)
        roads = lua_count(wow, f"{z}.road")
        self.assertGreater(roads, 0)
        wow.run('SlashCmdList.WARPATH("clear trail")')
        self.assertEqual(lua_count(wow, f"{z}.strokes"), 0)
        self.assertEqual(lua_count(wow, f"{z}.road"), roads)
        # Walking on starts a new trail at once, without a /reload (the bug
        # this command exists for: an orphaned stroke drew nothing).
        for i in range(5):
            wow.H.player.y = 0.5 + i * 0.003
            wow.advance(5)
        self.assertGreater(lua_count(wow, f"{z}.strokes"), 0)
        self.assertTrue(wow.eval(f"ns.cur.stroke ~= nil and {z}.strokes[#{z}.strokes] == ns.cur.stroke"))

    def test_trail_clear_is_the_same_as_clear_trail(self):
        wow = Wow().login()
        for i in range(20):
            wow.H.player.x = 0.4 + i * 0.003
            wow.advance(5)
        self.assertGreater(lua_count(wow, "WarpathDB.maps[1448].strokes"), 0)
        trail = wow.eval("ns.cfg.trailMin")
        wow.run('SlashCmdList.WARPATH("trail clear")')
        self.assertEqual(lua_count(wow, "WarpathDB.maps[1448].strokes"), 0)
        self.assertEqual(wow.eval("ns.cfg.trailMin"), trail)

    def test_roads_says_how_long_to_gold(self):
        wow = Wow().login()
        before = len(wow.chat)
        wow.run('SlashCmdList.WARPATH("roads")')
        line = " ".join(wow.chat[before:])
        self.assertIn("about 12 days", line)  # the documented day 12.5 of daily use, at 2.5
        before = len(wow.chat)
        wow.run('SlashCmdList.WARPATH("roads 8")')
        self.assertIn("never turns fully gold", " ".join(wow.chat[before:]))


class Overlay(unittest.TestCase):
    """Kill text is a flash; ground warnings stay long enough to read."""

    def ground_warning(self):
        wow = Wow().login()
        wow.advance(10)
        # Dangerous ground where the player stands: three PvP deaths, no kills.
        wow.run("""
            local _, x, y = ns.PlayerPos()
            local z = ns.db.maps[1448]
            for i = 1, 3 do z.marks[#z.marks + 1] = { x, y, time() - i * 60, "death", pvp = true } end
            ns.BattleField = function() return setmetatable({}, { __index = function() return 5 end }) end
            ns.Ground.Forget()
            ns.Ground.Check()""")
        return wow

    def shown_after(self, wow, seconds):
        # The stub doesn't drive OnUpdate: step the overlay's script by hand.
        return wow.eval(f"""(function()
            local f = WarpathBigText
            local step = f:GetScript("OnUpdate")
            for _ = 1, {int(seconds * 10)} do if f:IsShown() then step(f, 0.1) end end
            return f:IsShown() and f:GetAlpha() > 0.5
        end)()""")

    def test_a_ground_warning_stays_up_long_enough_to_read(self):
        wow = self.ground_warning()
        self.assertTrue(wow.eval("WarpathBigText ~= nil and WarpathBigText:IsShown()"))
        self.assertTrue(self.shown_after(wow, 3.5))

    def test_a_ground_warning_still_goes_away(self):
        wow = self.ground_warning()
        self.assertFalse(wow.eval("""(function()
            local f = WarpathBigText
            local step = f:GetScript("OnUpdate")
            for _ = 1, 80 do if f:IsShown() then step(f, 0.1) end end
            return f:IsShown()
        end)()"""))

    def test_kill_text_is_still_a_flash(self):
        wow = Wow().login()
        wow.run('ns.Overlay.Show({ title = "DOUBLE KILL", sub = "Thrall" })')
        self.assertTrue(self.shown_after(wow, 1.0))
        wow2 = Wow().login()
        wow2.run('ns.Overlay.Show({ title = "DOUBLE KILL", sub = "Thrall" })')
        self.assertFalse(self.shown_after(wow2, 2.0))


class GroundWarnings(unittest.TestCase):
    """3.8.3: any fighting here sets it off, not only your deaths (Joe:
    "an 'activity here' tag to fire hunting/contested/dangerous")."""

    def walk_onto(self, kills, deaths, after=2):
        wow = Wow().login()
        wow.advance(10)
        wow.run(f"""
            ns.cfg.groundAfter = {after}
            local mapID, x, y = ns.PlayerPos()
            local z = ns.db.maps[mapID]
            for i = 1, {kills} do
                z.marks[#z.marks + 1] = {{ x, y, time() - i * 600, "kill" }}
                ns.AddBattle(mapID, x, y, ns.C.BATTLE_W.kill)
            end
            for i = 1, {deaths} do
                z.marks[#z.marks + 1] = {{ x, y, time() - i * 600 - 300, "death", pvp = true }}
                ns.AddBattle(mapID, x, y, ns.C.BATTLE_W.death)
                ns.AddDeathHeat(mapID, x, y, 1)
            end
            ns.Ground.Forget()
            ns.Ground.Check()""")
        return " ".join(wow.chat)

    def test_a_hunting_ground_where_you_never_died_speaks(self):
        chat = self.walk_onto(3, 0)
        self.assertTrue(any(w in chat for w in ("hunting ground", "Good hunting", "You own this ground")), chat)

    def test_contested_ground_speaks(self):
        chat = self.walk_onto(2, 2)
        self.assertTrue(any(w in chat for w in ("Contested", "Hard-fought", "Even fighting")), chat)

    def test_dangerous_ground_still_speaks(self):
        chat = self.walk_onto(0, 3)
        self.assertTrue(any(w in chat for w in ("Dangerous", "Careful")), chat)

    def test_one_fight_is_not_enough_at_two(self):
        chat = self.walk_onto(1, 0, after=2)
        self.assertFalse(any(w in chat for w in ("hunting ground", "Good hunting", "You own this ground")), chat)


class MapButton(unittest.TestCase):
    def test_the_button_toggles_the_map_without_a_chat_line(self):
        wow = Wow().login()
        before = len(wow.chat)
        wow.run("ns.SetMapShown(false)")
        self.assertFalse(wow.eval("ns.cfg.shown"))
        wow.run("ns.SetMapShown(true)")
        self.assertEqual(wow.chat[before:], [])

    def test_the_button_and_the_book_work_inside_a_battleground(self):
        # 3.8.3 (Joe): inside, other maps still draw, so the button toggles
        # them; the chronicle opens by hand (it never opens by itself there).
        wow = Wow().login()
        wow.run("ns.S.inInstance = true; ns.cfg.shown = true; WorldMapFrame.__shown = true; ns.Redraw()")
        self.assertIsNotNone(wow.eval("WarpathMapButton and 1"), "the map button wasn't built")
        wow.run("WarpathMapButton:GetScript('OnClick')(WarpathMapButton, 'LeftButton')")
        self.assertFalse(wow.eval("ns.cfg.shown"))
        wow.run("ns.Chronicle.Open()")
        self.assertTrue(wow.eval("WarpathChronicle:IsShown()"))

    def test_the_books_x_closes_it_in_combat(self):
        # 3.8.3 (Joe): the X did nothing in combat; the template's click goes
        # through HideUIPanel, which the secure panel manager ignores then.
        wow = Wow().login()
        wow.run("ns.Chronicle.Open(); InCombatLockdown = function() return true end")
        wow.run("""for _, c in ipairs(WarpathChronicle.__children) do
            if c.__template == 'UIPanelCloseButton' then c:GetScript('OnClick')(c, 'LeftButton') end end""")
        self.assertFalse(wow.eval("WarpathChronicle:IsShown()"), "the X didn't close the book in combat")

    def test_the_slash_command_still_replies(self):
        wow = Wow().login()
        before = len(wow.chat)
        wow.run('SlashCmdList.WARPATH("map off")')
        self.assertIn("hidden (still recording)", " ".join(wow.chat[before:]))


class NewIn(unittest.TestCase):
    """After every release the chronicle opens on its Warpath tab (Joe,
    2026-11-24 for every release; the book instead of the options window
    from 3.8.3)."""

    def booted(self, seen, installed="3.7.0"):
        wow = Wow()
        inst = "nil" if installed is None else lua_str(installed)
        seen = "nil" if seen is None else lua_str(seen)
        wow.run(f'WarpathGlobal = {{ installed = {inst}, seenVersion = {seen}, cfg = {{}} }}')
        return wow.login()

    def shown(self, wow):
        return wow.eval('ns.Chronicle.Shown() == "warpath"')

    def page(self, wow):
        """The Warpath tab's visible text: every font string under the book,
        and the letter-by-letter capitals (title, headings, topics) joined
        into their words."""
        return wow.eval("""(function() local t = {}
            local function walk(f)
                for _, r in ipairs(f.__children or {}) do
                    if r.__kind == "FontString" and r:IsVisible() and r:GetText() then t[#t + 1] = r:GetText() end
                    walk(r)
                end
            end
            walk(WarpathChronicle)
            local P = ns.ChronWarpath.Frames()
            local function caps(c) local s = "" for _, l in ipairs(c.letters) do
                if l:IsVisible() then s = s .. l:GetText() end end t[#t + 1] = s end
            caps(P.title) caps(P.head)
            for _, h in ipairs(P.heads) do if h:IsShown() then caps(h.caps) end end
            for _, x in ipairs(P.topics) do if x:IsShown() then caps(x.caps) end end
            return table.concat(t, "|") end)()""").replace("|", "\n")

    def test_an_update_opens_the_book_on_whats_new(self):
        wow = self.booted("3.8.2")
        self.assertTrue(self.shown(wow), "the book didn't open on the Warpath tab")
        self.assertFalse(wow.eval("WarpathSetup ~= nil and WarpathSetup:IsShown()"),
                         "the options window no longer opens by itself")
        text = self.page(wow)
        self.assertIn("WELCOME BACK", text, "the title is in small caps")
        # 3.8.5: gilt diamonds flank each release newer than the last seen
        newer = int(wow.eval('(function() local n = 0 for _, r in ipairs(ns.NewIn.List) do '
                             'if ns.NewIn.Older("3.8.2", r[1]) then n = n + 1 end end return n end)()'))
        self.assertEqual(self.marked(wow), newer, "every release after 3.8.2 is marked, nothing older")
        self.assertIn("ON THE MAP", text, "3.8.3's notes are grouped under topics")

    def marked(self, wow):
        """How many releases on the sheet show their gilt diamonds."""
        return wow.eval("""(function() local n = 0 for _, h in ipairs(ns.ChronWarpath.Frames().heads) do
            if h:IsShown() and h.dia[1].fill:IsShown() then n = n + 1 end end return n end)()""")

    def test_closing_the_book_marks_the_release_seen(self):
        wow = self.booted("3.8.2")
        wow.run("WarpathChronicle:Hide()")
        self.assertEqual(wow.eval("WarpathGlobal.seenVersion"), wow.eval("ns.VERSION"))

    def test_a_first_install_opens_the_welcome(self):
        wow = self.booted(None, installed=None)
        self.assertTrue(self.shown(wow))
        text = self.page(wow)
        self.assertIn("WELCOME TO WARPATH", text)
        self.assertEqual(self.marked(wow), 0, "nothing is 'new' on a first install")
        # 3.8.3: sharing starts on for a new install, with its switch on this page
        self.assertIn("Guild sharing", text)
        self.assertTrue(wow.eval("ns.cfg.share"))
        self.assertTrue(wow.eval("""(function() local function walk(f)
            for _, c in ipairs(f.__children or {}) do
                if c.__template == "UICheckButtonTemplate" and c:IsVisible() and c:GetChecked() then return true end
                if walk(c) then return true end end end return walk(WarpathChronicle) end)()"""))

    def test_the_welcome_switch_turns_sharing_off(self):
        wow = self.booted("3.8.2")
        wow.run("ns.cfg.share = true")
        wow.run("""(function() local function walk(f)
            for _, c in ipairs(f.__children or {}) do
                if c.__template == "UICheckButtonTemplate" and c:IsVisible() then
                    c:SetChecked(false) c:GetScript("OnClick")(c) return true end
                if walk(c) then return true end end end walk(WarpathChronicle) end)()""")
        self.assertFalse(wow.eval("ns.cfg.share"))

    def test_notes_stay_short(self):
        # Joe picked layout C for its short lines (2026-11-26); test10's
        # paragraphs let two topics fill a page.
        wow = self.booted("3.8.2")
        longest = wow.eval("""(function() local m, at = 0, ""
            for _, rel in ipairs(ns.NewIn.List) do for _, l in ipairs(rel[2]) do
                if #l > m then m, at = #l, l end end end return at end)()""")
        self.assertLessEqual(len(longest), 70, f"a note too long for one line: {longest!r}")

    def test_versions_order_with_test_builds_first(self):
        wow = Wow()
        for a, b in (("3.7.11", "3.8.0"), ("3.8.0", "3.8.1"), ("3.8.0-test4", "3.8.0"),
                     ("3.8.9", "3.8.10"), ("3.3.5", "3.4"), ("3.8.3-test8", "3.8.3-test9"),
                     ("3.8.3-test9", "3.8.3-test10")):
            with self.subTest(a=a, b=b):
                self.assertTrue(wow.eval(f"ns.NewIn.Older({lua_str(a)}, {lua_str(b)})"))
                self.assertFalse(wow.eval(f"ns.NewIn.Older({lua_str(b)}, {lua_str(a)})"))
        self.assertFalse(wow.eval('ns.NewIn.Older("3.8.0", "3.8.0")'))
        self.assertFalse(wow.eval('ns.NewIn.Older("3.8.3-test9", "3.8.3-test9")'))

    def test_a_new_test_build_opens_the_book(self):
        # Joe, test9: the book stayed shut after test8, both "3.8.3" builds
        self.assertTrue(self.shown(self.booted("3.8.3-test8")))

    def test_opens_after_a_release_in_the_same_series(self):
        # The case 3.8.1 is for: before, an earlier 3.8 build kept it shut.
        full = Wow().eval("ns.VERSION")
        if "-" in full:
            self.skipTest("a test build; its release needs an entry before shipping")
        version = full.split("-")[0]
        self.assertTrue(self.shown(self.booted(version + "-test1")))

    def test_opens_after_a_feature_release(self):
        self.assertTrue(self.shown(self.booted("3.7.9")))

    def test_stays_shut_once_seen_or_going_back(self):
        wow = Wow()
        version = wow.eval("ns.VERSION")
        self.assertFalse(self.shown(self.booted(version)))
        self.assertFalse(self.shown(self.booted("99.0.0")))

    def test_the_current_release_has_an_entry(self):
        wow = Wow()
        version = wow.eval("ns.VERSION")
        if "-" in version:
            self.skipTest("a test build; its release needs an entry before shipping")
        self.assertGreater(wow.eval(f"#ns.NewIn.Unseen({lua_str(version + '-test0')})"), 0)

    def test_shows_only_what_this_account_has_not_seen(self):
        wow = Wow()
        self.assertGreater(wow.eval('#ns.NewIn.Unseen("3.7.9")'), 0)
        self.assertEqual(wow.eval('#ns.NewIn.Unseen("99.0.0")'), 0)
        self.assertLessEqual(wow.eval('#ns.NewIn.Unseen(nil)'), 8)


class AlertSettings(unittest.TestCase):
    """3.8.3: quiet mode and the big-text switch became "Announce on screen";
    guild sharing starts on for new installs only."""

    def booted(self, cfg, db=None):
        wow = Wow()
        wow.run(f'WarpathGlobal = {{ installed = "3.8.2", seenVersion = "3.8.2", cfg = {cfg} }}')
        if db:
            wow.run(f"WarpathDB = {db}")
        return wow.login()

    def test_quiet_mode_keeps_everything_it_turned_off(self):
        wow = self.booted("{ quiet = true, sound = true, zoneText = true, overlay = true }")
        self.assertFalse(wow.eval("ns.cfg.announce"))
        self.assertFalse(wow.eval("ns.cfg.sound"))
        self.assertFalse(wow.eval("ns.cfg.zoneText"))
        self.assertIsNone(wow.eval("ns.cfg.quiet"))
        self.assertIsNone(wow.eval("ns.cfg.overlay"))

    def test_without_quiet_mode_nothing_changes(self):
        wow = self.booted("{ quiet = false, sound = true, zoneText = true, overlay = false }")
        self.assertTrue(wow.eval("ns.cfg.announce"))
        self.assertTrue(wow.eval("ns.cfg.sound"))
        self.assertTrue(wow.eval("ns.cfg.zoneText"))

    def test_quiet_command_is_a_shortcut(self):
        wow = Wow().login()
        wow.run('SlashCmdList.WARPATH("quiet on")')
        self.assertFalse(wow.eval("ns.cfg.announce"))
        self.assertFalse(wow.eval("ns.cfg.sound"))
        wow.run('SlashCmdList.WARPATH("quiet")')
        self.assertTrue(wow.eval("ns.cfg.announce"))
        self.assertTrue(wow.eval("ns.cfg.sound"))

    def test_existing_accounts_keep_their_sharing_choice(self):
        self.assertFalse(self.booted("{ share = false }").eval("ns.cfg.share"))
        self.assertTrue(self.booted("{ share = true }").eval("ns.cfg.share"))

    def test_a_new_install_shares(self):
        self.assertTrue(Wow().login().eval("ns.cfg.share"))

    def test_a_pre_3_3_character_keeps_sharing_off(self):
        # account settings seeded from an old character that never turned it on
        wow = Wow()
        wow.run("WarpathDB = { maps = { [1448] = { marks = {} } } }")
        self.assertFalse(wow.login().eval("ns.cfg.share"))


class SettingsTab(unittest.TestCase):
    """3.8.3: the settings are a tab of the chronicle."""

    FIND = """local function Find(label)
        local function walk(f)
            for _, c in ipairs(f.__children or {}) do
                if c.__kind == "FontString" and c:GetText() == label and c:IsVisible() then
                    local _, rel = c:GetPoint(1) return rel end
                local r = walk(c) if r then return r end
            end
        end
        return walk(WarpathChronicle)
    end"""

    def opened(self, section=None):
        wow = Wow().login()
        wow.run('SlashCmdList.WARPATH("setup")')
        if section:
            wow.run(f'ns.ShowSetup(nil, {lua_str(section)})')
        return wow

    def click(self, wow, label):
        wow.run(self.FIND + f"""
            local cb = Find({lua_str(label)})
            assert(cb and cb.GetChecked, "no checkbox labelled " .. {lua_str(label)})
            cb:SetChecked(not cb:GetChecked())
            cb:GetScript("OnClick")(cb)""")

    def test_setup_opens_the_book_on_settings(self):
        wow = self.opened()
        self.assertEqual(wow.eval("ns.Chronicle.Shown()"), "settings")
        self.assertIsNone(wow.eval("WarpathSetup"), "the old options window is gone")

    def test_every_section_fits_its_page(self):
        wow = self.opened()
        floor = wow.eval("WarpathChronicle:GetHeight() - 36 - 44")
        for key in wow.eval("(function() local t = {} for _, s in ipairs(ns.Settings.Sections) do t[#t + 1] = s[1] end return table.concat(t, ',') end)()").split(","):
            with self.subTest(section=key):
                self.assertLessEqual(wow.eval(f"ns.Settings.Bottom({lua_str(key)})"), floor)

    def test_a_checkbox_writes_its_setting(self):
        wow = self.opened("alerts")
        self.assertTrue(wow.eval("ns.cfg.announce"))
        self.click(wow, "Announce on screen")
        self.assertFalse(wow.eval("ns.cfg.announce"))
        wow = self.opened("map")
        self.click(wow, "Roads")
        self.assertFalse(wow.eval("ns.cfg.layers.roads"))

    def test_rows_grey_out_when_they_do_nothing(self):
        wow = self.opened("guild")
        wow.run("ns.cfg.share = true ns.Settings.Refresh()")
        enabled = self.FIND + """ local cb = Find("Guildmates' kills and deaths in chat") return cb:IsEnabled() """
        self.assertTrue(wow.eval(f"(function() {enabled} end)()"))
        self.click(wow, "Guild sharing")
        self.assertFalse(wow.eval("ns.cfg.share"))
        self.assertFalse(wow.eval(f"(function() {enabled} end)()"))

    def test_restore_defaults_resets_only_the_open_section(self):
        wow = self.opened("map")
        wow.run("ns.cfg.runHours = 6 ns.cfg.flightHours = 48 ns.cfg.layers.roads = false ns.cfg.sound = false")
        wow.run("ns.Settings.Restore()")
        self.assertEqual(wow.eval("ns.cfg.runHours"), 24)
        self.assertEqual(wow.eval("ns.cfg.flightHours"), 24)
        self.assertTrue(wow.eval("ns.cfg.layers.roads"))
        self.assertFalse(wow.eval("ns.cfg.sound"), "sound is an Alerts setting")

    def test_the_minimap_right_click_opens_settings(self):
        wow = Wow().login()
        wow.run('ns.Dispatch("setup")')
        self.assertEqual(wow.eval("ns.Chronicle.Shown()"), "settings")


class Share(unittest.TestCase):
    """The guild channel, including what 3.7.10's diagnostics count."""

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("ns.cfg.share = true")
        self.chat_from = len(self.wow.chat)

    def receive(self, text, sender="Bob Smith", channel="GUILD", settle=True):
        # WoW Forever: senders arrive as "First Last", a space and no realm.
        self.wow.run(f"ns.OnComm('WARPATH', {lua_str(text)}, {lua_str(channel)}, {lua_str(sender)})")
        # 3.8.4: a kill's line waits 2 s for anyone else with credit;
        # settle=False for reports arriving together
        if settle and "|K|" in text:
            self.wow.advance(2.1)

    def new_chat(self):
        return self.wow.chat[self.chat_from:]

    def diag(self):
        before = len(self.wow.chat)
        self.wow.run("ns.DiagStatus()")
        return " ".join(self.wow.chat[before:])

    def test_guildmates_kill_prints_and_is_saved(self):
        self.receive("1|K|1448|0.40|0.60")
        self.assertTrue(any("Bob Smith" in l and "Felwood" in l for l in self.new_chat()), self.new_chat())
        self.assertEqual(lua_count(self.wow, "WarpathDB.maps[1448].gmarks"), 1)

    def test_guildmates_lines_can_be_turned_off(self):
        # 3.8.3: no chat line, but the pin is still saved
        self.wow.run("ns.cfg.guildChat = false")
        self.receive("1|K|1448|0.40|0.60")
        self.receive("1|D|1448|0.45|0.65|Aldric-Realm|0|1|")
        self.assertFalse(any("Bob Smith" in l for l in self.new_chat()), self.new_chat())
        self.assertEqual(lua_count(self.wow, "WarpathDB.maps[1448].gmarks"), 2)

    def test_guildmates_death_prints(self):
        self.receive("1|D|1448|0.40|0.60|Aldric-Realm|0|1|")
        self.assertTrue(any("Bob Smith" in l for l in self.new_chat()), self.new_chat())

    def test_own_echo_is_dropped(self):
        self.receive("1|K|1448|0.40|0.60", sender="Tester")
        self.assertEqual(self.new_chat(), [])
        self.assertIn("1 your own echo", self.diag())

    def test_duplicate_from_guild_and_party_is_dropped(self):
        self.receive("1|K|1448|0.40|0.60", channel="GUILD")
        self.receive("1|K|1448|0.40|0.60", channel="PARTY")
        self.assertEqual(lua_count(self.wow, "WarpathDB.maps[1448].gmarks"), 1)
        self.assertIn("1 duplicates", self.diag())

    def test_malformed_is_counted_not_applied(self):
        self.receive("1|K|1448|5|5")          # off the map
        self.receive("9|K|1448|0.5|0.5")      # unknown protocol
        self.assertIn("2 malformed", self.diag())

    def test_received_inside_an_instance(self):
        # 3.7.8: inside, Warpath sends nothing but still receives.
        self.wow.run("ns.S.inInstance = true")
        self.receive("1|K|1448|0.40|0.60")
        self.assertTrue(any("Bob Smith" in l for l in self.new_chat()))
        self.assertIn("(1 inside an instance)", self.diag())

    def test_a_message_that_errors_does_not_stop_the_next(self):
        # 3.7.10 wraps Receive in pcall and counts the error.
        self.wow.run("""
            local real = ns.Feats.GuildKillLine
            ns.Feats.GuildKillLine = function() ns.Feats.GuildKillLine = real error("boom") end""")
        self.receive("1|K|1448|0.40|0.60")
        self.receive("1|K|1448|0.41|0.61")
        self.assertIn("1 errors", self.diag())
        self.assertEqual(lua_count(self.wow, "WarpathDB.maps[1448].gmarks"), 2)

    # 3.8.3: several guildmates with credit for one enemy -> one line, one pin.
    @staticmethod
    def kill_msg(victim="", x=0.40, y=0.60, mapID=1448):
        return f"1|K|{mapID}|{x:.2f}|{y:.2f}|" + "|".join(["", "1", "1", "", "", "", "", "", victim])

    def kill_lines(self):
        return [l for l in self.new_chat() if "Felwood" in l or "Ashenvale" in l]

    def gpins(self, mapID=1448):
        return lua_count(self.wow, f"WarpathDB.maps[{mapID}] and WarpathDB.maps[{mapID}].gmarks")

    def test_two_guildmates_killing_one_enemy_say_it_once(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith", settle=False)
        self.receive(self.kill_msg("Thrall", 0.41, 0.61), sender="Ann Lee", settle=False)
        self.receive(self.kill_msg("Thrall"), sender="Cid Roe", channel="PARTY")
        self.assertEqual(len(self.kill_lines()), 1, self.new_chat())
        self.assertEqual(self.gpins(), 1)
        self.assertIn("2 repeat kills", self.diag())
        # each guildmate's own haze layer still counts it
        for who in ("Ann Lee", "Cid Roe"):
            with self.subTest(who=who):
                self.assertGreater(lua_count(self.wow, f'ns.GuildLayer(1448, "guildBattle", {lua_str(who)})'), 0)

    def test_different_enemies_or_places_are_separate_kills(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith")
        self.receive(self.kill_msg("Garrosh"), sender="Ann Lee")
        self.receive(self.kill_msg("Thrall", mapID=1440), sender="Ann Lee")
        self.assertEqual(len(self.kill_lines()), 3, self.new_chat())

    def test_one_guildmates_two_kills_stay_two(self):
        self.receive(self.kill_msg(), sender="Bob Smith")
        self.receive(self.kill_msg(x=0.405), sender="Bob Smith")
        self.assertEqual(len(self.kill_lines()), 2, self.new_chat())

    def test_the_same_enemy_killed_again_later_is_a_new_kill(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith")
        self.wow.advance(31)
        self.receive(self.kill_msg("Thrall"), sender="Ann Lee")
        self.assertEqual(len(self.kill_lines()), 2, self.new_chat())

    def test_old_senders_without_a_name_group_by_place(self):
        self.receive(self.kill_msg(), sender="Bob Smith", settle=False)
        self.receive(self.kill_msg(x=0.405), sender="Ann Lee", settle=False)  # same spot
        self.receive(self.kill_msg(x=0.60), sender="Cid Roe")        # far away
        self.assertEqual(len(self.kill_lines()), 2, self.new_chat())
        self.wow.advance(9)
        self.receive(self.kill_msg(x=0.405), sender="Dee Fox")       # same spot, later
        self.assertEqual(len(self.kill_lines()), 3, self.new_chat())

    def own_kill(self, victim="Thrall"):
        # a named PvP kill: the honorable-kill counter ticks in combat
        self.wow.run(f"""ns.Foes.Pick = function() return {lua_str(victim + '-Realm')}, {lua_str(victim)}, "SHAMAN", "target" end""")
        self.wow.H.combat = True
        self.wow.fire("PLAYER_REGEN_DISABLED")
        self.wow.H.hk = (self.wow.H.hk or 0) + 1
        self.wow.fire("PLAYER_PVP_KILLS_CHANGED")
        self.wow.advance(1)
        self.wow.H.combat = False
        self.wow.fire("PLAYER_REGEN_ENABLED")
        self.wow.advance(3)

    def test_a_guildmates_report_of_your_own_kill_is_folded(self):
        self.own_kill()
        self.assertEqual(self.wow.eval("WarpathDB.kills"), 1)
        mx = self.wow.eval("(select(2, ns.PlayerPos()))")
        my = self.wow.eval("(select(3, ns.PlayerPos()))")
        before = len([l for l in self.new_chat() if "Bob Smith" in l])
        self.receive(self.kill_msg("Thrall", mx, my), sender="Bob Smith")
        self.assertEqual(len([l for l in self.new_chat() if "Bob Smith" in l]), before, self.new_chat())
        self.assertEqual(self.gpins(), 0)

    def test_your_own_line_is_skipped_when_a_guildmate_said_it_first(self):
        self.wow.run("ns.cfg.selfChat = true")
        mx = self.wow.eval("(select(2, ns.PlayerPos()))")
        my = self.wow.eval("(select(3, ns.PlayerPos()))")
        self.receive(self.kill_msg("Thrall", mx, my), sender="Bob Smith", settle=False)
        self.assertEqual(self.gpins(), 1)
        self.own_kill()
        self.assertEqual(self.wow.eval("WarpathDB.kills"), 1)
        lines = self.kill_lines()
        self.assertEqual(len(lines), 1, self.new_chat())
        self.assertIn("Bob Smith", lines[0])
        self.assertTrue(lines[0].endswith("(with Tester)"), lines[0])
        self.assertEqual(self.gpins(), 0)  # your own mark is there instead, naming Bob
        self.assertEqual(self.wow.eval("ns.JoinNames(ns.db.maps[1448].marks[#ns.db.maps[1448].marks].with)"), "Bob Smith")

    # 3.8.4: everyone with credit is named on the one line and its pin.
    def test_everyone_with_credit_is_named_on_the_line(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith", settle=False)
        self.assertEqual(self.kill_lines(), [], "the line waits for others with credit")
        self.receive(self.kill_msg("Thrall", 0.41, 0.61), sender="Ann Lee", settle=False)
        self.receive(self.kill_msg("Thrall"), sender="Cid Roe")
        lines = self.kill_lines()
        self.assertEqual(len(lines), 1, self.new_chat())
        self.assertIn("Bob Smith", lines[0])
        self.assertTrue(lines[0].endswith("(with Ann Lee and Cid Roe)"), lines[0])
        self.assertEqual(self.wow.eval("ns.JoinNames(ns.db.maps[1448].gmarks[1].with)"), "Ann Lee and Cid Roe")

    def test_a_big_group_is_counted_not_listed_in_chat(self):
        names = [f"Mate {c}" for c in "ABCDEFGHIJ"]
        for n in names:
            self.receive(self.kill_msg("Thrall"), sender=n, settle=False)
        self.wow.advance(2.1)
        lines = self.kill_lines()
        self.assertEqual(len(lines), 1, self.new_chat())
        self.assertTrue(lines[0].endswith("(with Mate B, Mate C, Mate D and 6 others)"), lines[0])
        # the pin's tooltip has them all
        self.assertEqual(lua_count(self.wow, "ns.db.maps[1448].gmarks[1].with"), 9)
        # four reporters besides the first: all four named, nothing counted
        self.assertEqual(self.wow.eval('ns.JoinNames({"A", "B", "C", "D"}, 3)'), "A, B, C and D")

    def test_a_lone_kill_names_no_one_else(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith")
        lines = self.kill_lines()
        self.assertEqual(len(lines), 1, self.new_chat())
        self.assertNotIn("(with", lines[0])
        self.assertIsNone(self.wow.eval("ns.db.maps[1448].gmarks[1].with"))

    def test_a_late_report_joins_the_pin_not_a_second_line(self):
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith")
        self.receive(self.kill_msg("Thrall"), sender="Ann Lee")  # after the line printed
        self.assertEqual(len(self.kill_lines()), 1, self.new_chat())
        self.assertEqual(self.wow.eval("ns.JoinNames(ns.db.maps[1448].gmarks[1].with)"), "Ann Lee")

    def test_a_guildmate_with_credit_for_your_kill_is_named_on_your_line(self):
        self.wow.run("ns.cfg.selfChat = true")
        self.wow.run(f"""ns.Foes.Pick = function() return "Thrall-Realm", "Thrall", "SHAMAN", "target" end""")
        self.wow.H.combat = True
        self.wow.fire("PLAYER_REGEN_DISABLED")
        self.wow.H.hk = (self.wow.H.hk or 0) + 1
        self.wow.fire("PLAYER_PVP_KILLS_CHANGED")
        self.wow.advance(0.5)
        self.assertEqual(self.wow.eval("WarpathDB.kills"), 1)
        mx = self.wow.eval("(select(2, ns.PlayerPos()))")
        my = self.wow.eval("(select(3, ns.PlayerPos()))")
        self.receive(self.kill_msg("Thrall", mx, my), sender="Bob Smith")
        lines = self.kill_lines()
        self.assertEqual(len(lines), 1, self.new_chat())
        self.assertIn("Tester", lines[0])
        self.assertTrue(lines[0].endswith("(with Bob Smith)"), lines[0])
        self.assertEqual(self.gpins(), 0)
        self.assertEqual(self.wow.eval("ns.JoinNames(ns.db.maps[1448].marks[#ns.db.maps[1448].marks].with)"), "Bob Smith")

    def test_announce_off_says_your_kill_in_chat_instead(self):
        # 3.8.3: "Announce on screen" off (once quiet mode): no banner, a chat line
        self.wow.run("ns.cfg.announce = false ns.cfg.selfChat = false")
        before = self.wow.eval("#__H.notices")
        self.own_kill()
        self.assertEqual(self.wow.eval("#__H.notices"), before, "no banner")
        self.assertTrue(any("Thrall" in l for l in self.new_chat()), self.new_chat())

    def test_your_own_line_still_prints_for_your_own_kill(self):
        self.wow.run("ns.cfg.selfChat = true")
        self.own_kill()
        self.assertEqual(self.wow.eval("WarpathDB.kills"), 1)
        self.assertEqual(len(self.kill_lines()), 1, self.new_chat())

    def newer_lines(self):
        return [l for l in self.new_chat() if "is out (you have" in l]

    def test_a_guildmate_on_a_newer_release_is_mentioned_once(self):
        # 3.8.1: the hello carries the sender's version.
        self.receive("1|H|0|99.0.0")
        self.receive("1|H|0|99.0.0", sender="Ann Lee")
        self.assertEqual(len(self.newer_lines()), 1, self.new_chat())
        self.assertIn("99.0.0", self.newer_lines()[0])
        self.receive("1|H|0|99.0.1")  # an even newer one is news again
        self.assertEqual(len(self.newer_lines()), 2)

    def test_same_older_test_and_garbled_versions_say_nothing(self):
        version = self.wow.eval("ns.VERSION")
        for text in (f"1|H|0|{version}", "1|H|0|3.0.0", "1|H|0|99.0.0-test1", "1|H|0", "1|H|1|",
                     "1|H|0|99.0", "1|H|0|99.0.0.0.0.0.0", "1|H|0|banana"):
            with self.subTest(text=text):
                self.receive(text)
        self.assertEqual(self.newer_lines(), [])

    def test_the_hello_carries_this_version(self):
        self.wow.run("IsInGuild = function() return true end")
        self.wow.run("ns.Sync.Hello(false)")
        msgs = [m for m in self.wow.sent if "|H|" in str(m)]
        self.assertTrue(msgs, self.wow.sent)
        self.assertIn("1|H|0|" + self.wow.eval("ns.VERSION"), str(msgs[-1]))

    def test_nothing_is_received_with_sharing_off(self):
        self.wow.run("ns.cfg.share = false")
        self.receive("1|K|1448|0.40|0.60")
        self.assertEqual(self.new_chat(), [])


class Lines(unittest.TestCase):
    """Every chat line, at every index, with any field missing, reads cleanly.

    P.Text falls back to a pool's first line when a placeholder has no value,
    so the property worth holding is: no pool ever leaves a hole."""

    HOLE = re.compile(r"\{\w+\}|\bnil\b|  |\s[,.!:]|\(\s*\)")

    @classmethod
    def setUpClass(cls):
        cls.wow = Wow().login()
        cls.pools = {str(k): int(cls.wow.eval(f"#ns.Phrases.pools[{lua_str(str(k))}]"))
                     for k in cls.wow.eval("ns.Phrases.pools").keys()}

    def text(self, pool, idx, **vars_):
        table = ", ".join(f"{k} = {lua_str(v)}" for k, v in vars_.items())
        return self.wow.eval(f"ns.Phrases.Text({lua_str(pool)}, {idx}, {{ {table} }})")

    def test_pools_exist(self):
        self.assertGreater(len(self.pools), 5)

    def test_every_line_with_every_field(self):
        full = dict(name="Bob", zone="Felwood", n="5", killer="Aldric", victim="Thrall")
        for pool, size in self.pools.items():
            for i in range(1, size + 1):
                with self.subTest(pool=pool, i=i):
                    line = self.text(pool, i, **full)
                    self.assertNotRegex(line, self.HOLE)

    def requires(self, pool, field):
        """A pool requires a field when every one of its lines uses it. Such a
        pool ("took", "grudge") is only ever chosen when the field exists, so
        testing it without that field would test a case that can't happen."""
        tag = "{" + field + "}"
        size = self.pools[pool]
        return all(tag in self.wow.eval(f"ns.Phrases.pools[{lua_str(pool)}][{i}]") for i in range(1, size + 1))

    def test_every_line_with_each_optional_field_missing(self):
        for missing in ("killer", "victim"):
            vars_ = dict(name="Bob", zone="Felwood", n="5", killer="Aldric", victim="Thrall")
            del vars_[missing]
            for pool, size in self.pools.items():
                if self.requires(pool, missing):
                    continue
                for i in range(1, size + 1):
                    with self.subTest(pool=pool, i=i, missing=missing):
                        line = self.text(pool, i, **vars_)
                        self.assertNotRegex(line, self.HOLE)

    def test_grudge_kill_from_the_network_without_a_victim(self):
        """Found by this harness on 2026-11-23, fixed in 3.7.11: a garbled
        message with the grudge wording but no victim printed "settled a
        grudge in Felwood:  falls!". It now falls back to a plain kill line."""
        line = self.wow.eval("ns.Feats.GuildKillLine('Bob', 'Felwood', 'g', '1', '1', '', '', '', '', '', '')")
        self.assertNotRegex(line, self.HOLE)
        self.assertIn("Bob", line)
        self.assertNotIn("grudge", line)

    def test_grudge_kill_with_a_victim_still_names_them(self):
        line = self.wow.eval("ns.Feats.GuildKillLine('Bob', 'Felwood', 'g', '1', '1', '', '', '', '', '', 'Thrall')")
        self.assertIn("Thrall", line)
        self.assertIn("grudge", line)

    def test_old_sender_kill_line(self):
        # A 3.6 sender sends no tier or feat fields.
        line = self.wow.eval("ns.Feats.GuildKillLine('Bob', 'Felwood')")
        self.assertIn("Bob", line)
        self.assertNotRegex(line, self.HOLE)

    def test_unknown_line_number_from_a_newer_sender(self):
        line = self.wow.eval("ns.Feats.GuildDeathLine('Bob', 'Felwood', 'Aldric-X', '0', '999', '')")
        self.assertNotRegex(line, self.HOLE)


class MapDrawing(unittest.TestCase):
    """The map overlay, through the same collector the renderer uses."""

    def setUp(self):
        from render import COLLECT
        self.COLLECT = COLLECT
        self.wow = Wow().login()
        self.wow.run("ns.cfg.share = true; ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")

    def primitives(self):
        self.wow.eval("ns.Redraw()")
        return [p.split("\t") for p in self.wow.run(self.COLLECT).split("\n") if p]

    def test_a_pin_lands_where_the_kill_was(self):
        # Orientation can't be judged by eye without the map art: a flipped
        # axis still looks like a map. So put a kill at a known point and
        # check the pin is drawn exactly there (map 0..1 -> 1002 x 668, y down).
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        pins = [p for p in self.primitives() if p[0] == "T"]
        self.assertTrue(pins, "no pin drawn")
        x, y = float(pins[-1][6]), float(pins[-1][7])
        self.assertAlmostEqual(x, 0.25 * 1002, delta=1.0)
        self.assertAlmostEqual(y, 0.75 * 668, delta=1.0)

    def test_another_zone_is_not_stacked_on_the_viewed_map(self):
        # The bug a real screenshot caught: with every map "covering" every
        # other, a Felwood render was 95% other zones. A zone whose place on
        # the viewed map is unknown must not be drawn on it at all.
        self.wow.run("ns.OnComm('WARPATH', '1|K|1440|0.50|0.50', 'GUILD', 'Bob Smith')")  # Ashenvale
        self.assertEqual(self.primitives(), [])

    def test_another_zone_is_drawn_inside_its_rect(self):
        # Ashenvale occupying x 0.2-0.4, y 0.6-0.8 of the viewed map: its
        # centre lands at the centre of that box, not the centre of the map.
        self.wow.run("__H.rects = { [1440] = { [1448] = { 0.2, 0.4, 0.6, 0.8 } } }")
        self.wow.run("ns.OnComm('WARPATH', '1|K|1440|0.50|0.50', 'GUILD', 'Bob Smith')")
        pins = [p for p in self.primitives() if p[0] == "T"]
        self.assertTrue(pins, "no pin drawn")
        self.assertAlmostEqual(float(pins[-1][6]), 0.30 * 1002, delta=1.0)
        self.assertAlmostEqual(float(pins[-1][7]), 0.70 * 668, delta=1.0)

    def test_felwood_lands_where_the_client_puts_it_on_kalimdor(self):
        # Real placement, from the rects captured in game (map_rects.lua):
        # the middle of Felwood is the middle of Felwood's box on Kalimdor.
        x0, x1, y0, y1 = (float(self.wow.eval(f"__H.rects[1448][1414][{i}]")) for i in range(1, 5))
        self.wow.run("__H.mapShown = 1414")
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.50|0.50', 'GUILD', 'Bob Smith')")
        pins = [p for p in self.primitives() if p[0] == "T"]
        self.assertTrue(pins, "no pin drawn")
        self.assertAlmostEqual(float(pins[-1][6]), (x0 + x1) / 2 * 1002, delta=1.0)
        self.assertAlmostEqual(float(pins[-1][7]), (y0 + y1) / 2 * 668, delta=1.0)

    def test_hiding_the_map_draws_nothing(self):
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        self.wow.run("ns.cfg.shown = false")
        self.assertEqual(self.primitives(), [])

    def test_the_battleground_map_stays_clean(self):
        # Inside, the map you're standing in draws nothing, pins included.
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        self.wow.run("ns.S.inInstance = true; __H.player.mapID = 1448")
        self.assertEqual(self.primitives(), [])

    def test_other_maps_still_draw_inside_a_battleground(self):
        # 3.8.3 (Joe): resting inside means no pins or spam there, not
        # hiding the rest of the world. Viewing Felwood from a battleground
        # still shows Felwood.
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        outside = self.primitives()
        self.assertNotEqual(outside, [])
        self.wow.run("ns.S.inInstance = true; __H.player.mapID = 1460")
        self.assertEqual(self.primitives(), outside)

    def test_an_unreadable_position_inside_draws_nothing(self):
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        self.wow.run("ns.S.inInstance = true; __H.player.mapID = nil")
        self.assertEqual(self.primitives(), [])

    def standing(self, kills, deaths, viewed=1448):
        # the zone's record, then the map; returns the corner badge's text and
        # colour, or None when it isn't shown
        self.wow.run("if not ns.db.maps[1448] then ns.OnComm('WARPATH', '1|K|1448|0.5|0.5', 'GUILD', 'Bob Smith') end")
        self.wow.run(f"""for id, z in pairs(ns.db.maps) do z.kills, z.pdeaths = 0, 0 end
            ns.db.maps[1448].kills, ns.db.maps[1448].pdeaths = {kills}, {deaths}
            __H.mapShown = {viewed}""")
        self.wow.eval("ns.Redraw()")
        return self.wow.eval("""(function()
            for _, f in ipairs(WorldMapFrame.ScrollContainer.__children) do
                if f.crest and f.back and f:IsShown() then
                    local r, g, b = f.text:GetTextColor()
                    local _, _, rel, x, y = f:GetPoint(1)
                    return table.concat({ f.text:GetText(), r, g, b, rel, x, y }, "|")
                end
            end
        end)()""")

    BLUE, YELLOW, RED = [0.35, 0.65, 1.0], [1.0, 0.82, 0.0], [1.0, 0.25, 0.2]

    def test_a_zone_map_shows_its_standing_in_the_corner(self):
        got = self.standing(8, 1)
        self.assertTrue(got, "no standing on the zone's own map")
        text, r, g, b, rel, x, y = got.split("|")
        self.assertEqual(text, "8 : 1")
        self.assertEqual([round(float(v), 3) for v in (r, g, b)], self.BLUE, "clearly ahead: blue")
        # fixed to the map frame's top-left, not to the canvas, so zooming can't move it
        self.assertEqual(rel, "TOPLEFT")
        self.assertLess(float(x), 80)

    def test_the_corner_is_red_behind_and_yellow_when_close(self):
        text, r, g, b, *_ = self.standing(1, 5).split("|")
        self.assertEqual(text, "1 : 5")
        self.assertEqual([round(float(v), 3) for v in (r, g, b)], self.RED)
        _, r, g, b, *_ = self.standing(3, 2).split("|")
        self.assertEqual([round(float(v), 3) for v in (r, g, b)], self.YELLOW)

    # --- continent and world views (3.8.3) ---------------------------------

    def pins_on(self, viewed):
        self.wow.run(f"__H.mapShown = {viewed}")
        self.wow.eval("ns.Redraw()")
        rows = self.wow.eval("""(function() local t = {}
            for _, f in ipairs(WarpathOverlay.__children) do
                if f.kind and f.tex and f:IsShown() then
                    local _, _, _, x, y = f:GetPoint(1)
                    t[#t + 1] = table.concat({ f.kind, f.kind == "many" and f.d.n or "",
                        x, y, f:GetWidth() }, ",")
                end
            end return table.concat(t, ";") end)()""")
        return [r.split(",") for r in rows.split(";") if r]

    def scores_on(self, viewed):
        self.wow.run(f"__H.mapShown = {viewed}")
        self.wow.eval("ns.Redraw()")
        rows = self.wow.eval("""(function() local t = {}
            for _, f in ipairs(WarpathOverlay.__children) do
                local s = f.text and f:IsShown() and f.text:GetText()
                if s and s:match("^%d+ : %d+$") then
                    local r, g, b = f.text:GetTextColor()
                    local _, _, _, x, y = f:GetPoint(1)
                    t[#t + 1] = table.concat({ s, r, g, b, x, y }, ",")
                end
            end return table.concat(t, ";") end)()""")
        return [r.split(",") for r in rows.split(";") if r]

    def guild(self, kind, x, y, n=1, step=0.0):
        for i in range(n):
            self.wow.run(f"ns.OnComm('WARPATH', '1|{kind}|1448|{x + i * step}|{y}', 'GUILD', 'Bob Smith')")

    def test_crowded_kills_on_a_continent_become_one_big_sword(self):
        self.guild("K", 0.40, 0.40, n=5, step=0.01)      # a few yards apart in Felwood
        self.guild("K", 0.90, 0.90)                        # one far away
        pins = self.pins_on(1414)
        big = [p for p in pins if p[0] == "many"]
        self.assertEqual(len(big), 1, pins)
        self.assertEqual(big[0][1], "5", "the big pin stands for all five")
        self.assertEqual(len([p for p in pins if p[0] == "skill"]), 1, "the lone kill stays a pin")
        normal = float([p for p in pins if p[0] == "skill"][0][4])
        self.assertGreater(float(big[0][4]), normal * 1.2, "the big pin is bigger")
        self.assertLessEqual(float(big[0][4]), normal * 1.5 + 0.01, "but not by much (Joe: 'a little big')")

    def test_two_crowded_kills_stay_separate_pins(self):
        self.guild("K", 0.40, 0.40, n=2, step=0.01)
        pins = self.pins_on(1414)
        self.assertEqual(sorted(p[0] for p in pins), ["skill", "skill"])

    def test_a_zone_map_never_combines(self):
        self.guild("K", 0.40, 0.40, n=5, step=0.01)
        pins = self.pins_on(1448)
        self.assertEqual([p[0] for p in pins], ["skill"] * 5)

    def test_a_big_sword_and_a_big_skull_do_not_overlap(self):
        self.guild("K", 0.40, 0.40, n=4, step=0.002)   # one fight: kills and deaths on one spot
        self.guild("D", 0.40, 0.40, n=4, step=0.002)
        big = [p for p in self.pins_on(1414) if p[0] == "many"]
        self.assertEqual(len(big), 2, big)
        (_, _, x1, y1, w1), (_, _, x2, y2, w2) = big
        gap = ((float(x1) - float(x2)) ** 2 + (float(y1) - float(y2)) ** 2) ** 0.5
        self.assertGreaterEqual(gap + 0.01, (float(w1) + float(w2)) / 2)

    def set_record(self, rec):
        for mid, (k, d) in rec.items():
            self.wow.run(f"""if not ns.db.maps[{mid}] then
                ns.OnComm('WARPATH', '1|K|{mid}|0.5|0.5', 'GUILD', 'Bob Smith') end
                ns.db.maps[{mid}].kills, ns.db.maps[{mid}].pdeaths = {k}, {d}""")

    def test_a_continent_shows_a_small_score_per_zone_in_three_colours(self):
        self.wow.run("__H.rects[1440] = { [1414] = { 0.42, 0.57, 0.33, 0.49 } }")
        self.wow.run("__H.rects[2482] = { [1414] = { 0.49, 0.58, 0.26, 0.36 } }")
        self.set_record({1448: (1, 5), 1440: (8, 1), 2482: (2, 2)})
        got = {s[0]: [round(float(v), 3) for v in s[1:4]] for s in self.scores_on(1414)}
        self.assertEqual(got, {"1 : 5": self.RED, "8 : 1": self.BLUE, "2 : 2": self.YELLOW})

    def test_scores_that_would_overlap_step_apart(self):
        self.wow.run("__H.rects[2482] = { [1414] = __H.rects[1448][1414] }")  # same centre as Felwood
        self.set_record({1448: (1, 5), 2482: (0, 2)})
        s = {r[0]: (float(r[4]), float(r[5])) for r in self.scores_on(1414)}
        self.assertEqual(len(s), 2)
        self.assertGreater(abs(s["1 : 5"][1] - s["0 : 2"][1]), 9, "the smaller one steps away")
        self.assertGreater(s["1 : 5"][1], s["0 : 2"][1], "the most-fought zone keeps its centre (y is negative down)")

    def test_a_score_stays_put_over_pins_and_draws_above_them(self):
        self.set_record({1448: (4, 0)})
        alone = [(float(r[4]), float(r[5])) for r in self.scores_on(1414)]
        self.guild("K", 0.5, 0.5, n=4, step=0.002)         # a big sword on Felwood's centre
        self.set_record({1448: (4, 0)})
        assert [p for p in self.pins_on(1414) if p[0] == "many"]
        here = [(float(r[4]), float(r[5])) for r in self.scores_on(1414)]
        self.assertEqual(here, alone, "pins coming and going never move a score (Joe: they jumped about)")
        top = self.wow.eval("""(function() local s, p = 0, 0
            for _, f in ipairs(WarpathOverlay.__children) do
                if f:IsShown() and f.text and f.text:GetText() and f.text:GetText():match(" : ") then s = math.max(s, f:GetFrameLevel()) end
                if f:IsShown() and f.kind then p = math.max(p, f:GetFrameLevel()) end
            end return s .. "," .. p end)()""").split(",")
        self.assertGreater(int(top[0]), int(top[1]), "the score draws above every pin")

    def test_the_world_view_shows_one_score_per_continent(self):
        self.wow.run("""__H.rects[1414] = { [947] = { 0.0, 0.5, 0.1, 0.9 } }
            __H.rects[1415] = { [947] = { 0.5, 1.0, 0.1, 0.9 } }
            __H.rects[1448][947] = { 0.2, 0.3, 0.3, 0.4 }
            __H.rects[1440] = { [1414] = { 0.42, 0.57, 0.33, 0.49 }, [947] = { 0.2, 0.3, 0.4, 0.5 } }""")
        self.set_record({1448: (1, 5), 1440: (2, 13)})
        got = self.scores_on(947)
        self.assertEqual([g[0] for g in got], ["3 : 18"], "Kalimdor's total, no zone scores")
        self.assertEqual([round(float(v), 3) for v in got[0][1:4]], self.RED)

    def test_no_standing_without_a_fight_or_off_the_zone_map(self):
        self.assertIsNone(self.standing(0, 0))
        self.assertIsNone(self.standing(8, 1, viewed=1414), "continent views keep their own labels")
        self.wow.run("ns.cfg.layers.marks = false")
        self.assertIsNone(self.standing(8, 1), "the marks layer switches it off")
        self.wow.run("ns.cfg.layers.marks = true; ns.cfg.shown = false")
        self.assertIsNone(self.standing(8, 1), "hiding Warpath on the map hides it")

    def test_walking_draws_todays_trail(self):
        for i in range(40):
            self.wow.H.player.x = 0.30 + i * 0.005
            self.wow.advance(1)
        lines = [p for p in self.primitives() if p[0] == "L"]
        self.assertGreater(len(lines), 0)
        xs = [float(p[6]) for p in lines] + [float(p[8]) for p in lines]
        # the walk ran from x=0.30 to ~0.50 of the map's width
        self.assertGreaterEqual(min(xs), 0.29 * 1002)
        self.assertLessEqual(max(xs), 0.51 * 1002)


class Steadiness(unittest.TestCase):
    """Marks are anchored to the ground and only fade (Joe's rule).

    Anything recomputed from "now" each redraw makes the trail crawl, which
    is how 3.7.5 was rejected. So: walk, stop, and as time passes every dash
    must stay exactly where it was. It may shorten, thin, fade or vanish,
    but its centre must not move."""

    def segments(self, wow):
        from render import COLLECT
        wow.eval("ns.Redraw()")
        out = []
        for p in wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L":
                out.append(tuple(float(v) for v in f[6:10]))
        return out

    @staticmethod
    def dist(px, py, seg):
        x1, y1, x2, y2 = seg
        dx, dy = x2 - x1, y2 - y1
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - x1) * dx + (py - y1) * dy) / L2))
        return ((px - x1 - t * dx) ** 2 + (py - y1 - t * dy) ** 2) ** 0.5

    def new_ink(self, earlier, later, tol=0.6):
        """Points of later segments that don't lie on any earlier segment.

        Not segment centres: a dash crossing a bend is drawn as several
        segments, and where they split changes as it shortens, so centres
        move even when the dash doesn't. What a crawl does that a steady
        dash can't is put ink into what was a gap."""
        bad = []
        for seg in later:
            x1, y1, x2, y2 = seg
            for t in (0.0, 0.25, 0.5, 0.75, 1.0):
                px, py = x1 + t * (x2 - x1), y1 + t * (y2 - y1)
                if min(self.dist(px, py, e) for e in earlier) > tol:
                    bad.append((round(px, 1), round(py, 1)))
        return bad

    def test_dashes_do_not_move_as_time_passes(self):
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        for i in range(120):                   # two minutes of walking
            wow.H.player.x = 0.30 + i * 0.002
            wow.H.player.y = 0.40 + (i % 20) * 0.003
            wow.advance(1)
        wow.advance(8 * 60)                    # stop; everything is now older than the 5-minute solid line
        first = self.segments(wow)
        self.assertGreater(len(first), 10, "no dashes to compare")
        for minutes in (1, 5, 15):
            wow.advance(60 * minutes)
            later = self.segments(wow)
            with self.subTest(minutes_later=minutes):
                self.assertEqual(self.new_ink(first, later), [], "trail ink appeared where there was none: a dash moved")

    def test_dashes_stay_put_when_you_walk_on_after_a_stop(self):
        # 3.8 smooths the path the dashes follow. Near the end of the trail
        # the smoothing window is narrower; stop long enough for that end to
        # turn to dashes, then walk on round a tight bend: the old dashes must
        # not shift (at 2 slots of smoothing they do, by about 1.7 px).
        import math
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        for i in range(120):
            a = i / 120 * math.pi
            wow.H.player.x, wow.H.player.y = 0.40 + 0.08 * math.cos(a), 0.50 + 0.08 * math.sin(a)
            wow.advance(1)
        wow.advance(5 * 60)
        first = self.segments(wow)
        for i in range(1, 30):
            a = math.pi + i / 120 * math.pi
            wow.H.player.x, wow.H.player.y = 0.40 + 0.08 * math.cos(a), 0.50 + 0.08 * math.sin(a)
            wow.advance(1)
        later = [s for s in self.segments(wow) if min(s[1], s[3]) > 0.50 * 668 + 3]  # the old curve only
        self.assertEqual(self.new_ink(first, later), [], "dashes moved when you walked on")

    def test_dashes_and_arrows_are_evenly_spaced(self):
        # Joe, 3.8: with the shorter arrow, the gap before each arrow was about
        # four times the others. Walk a straight line, let it turn to dashes,
        # and measure the gaps between marks along it.
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        for i in range(150):
            wow.H.player.x, wow.H.player.y = 0.20 + i * 0.004, 0.50
            wow.advance(1)
        wow.advance(4 * 60)                              # all of it past the solid line, still fresh
        y0 = 0.50 * 668
        on = sorted((min(x1, x2), max(x1, x2)) for x1, y1, x2, y2 in self.segments(wow)
                    if abs(y1 - y0) < 0.3 and abs(y2 - y0) < 0.3 and abs(x2 - x1) > 0.01)
        marks = []
        for a, b in on:                                  # join the pieces of one mark
            if marks and a - marks[-1][1] < 0.3:
                marks[-1][1] = max(marks[-1][1], b)
            else:
                marks.append([a, b])
        gaps = [b[0] - a[1] for a, b in zip(marks, marks[1:])]
        inner = gaps[2:-2]                               # leave the ends of the trail out
        self.assertGreater(len(inner), 10)
        # neighbours match; along the trail gaps grow slowly as older marks shorten
        jumps = [abs(b - a) for a, b in zip(inner, inner[1:])]
        self.assertLess(max(jumps), 0.6, f"uneven gaps: {[round(g, 1) for g in inner]}")

    def test_the_check_catches_a_crawl(self):
        # Guard against a test that can't fail: shift every dash 3 px along x.
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        for i in range(120):
            wow.H.player.x = 0.30 + i * 0.002
            wow.advance(1)
        wow.advance(8 * 60)
        first = self.segments(wow)
        shifted = [(x1 + 3, y1, x2 + 3, y2) for x1, y1, x2, y2 in first]
        # a horizontal walk shifted along itself mostly overlaps; shift across it too
        shifted = [(x1, y1 + 3, x2, y2 + 3) for x1, y1, x2, y2 in shifted]
        self.assertNotEqual(self.new_ink(first, shifted), [])


class TrailOnRoads(unittest.TestCase):
    """Older trail gives way to the roads it runs along (3.8.3, Joe's pick).

    The same path drawn twice, as a road and as trail on top of it, was most
    of the clutter in the Plaguelands. Trail along a road you can see is kept
    10 minutes, then fades out over 5; trail off the roads stays."""

    ROW = 30                       # the road runs along this row of road cells

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        self.wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end "
                     "ns.cfg.layers.roads = true; ns.cfg.layers.recent = true")
        self.wow.run(f"""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {{}}
            for x = 8, 45 do local a = {self.ROW} * GW + x z.road[a * 10000 + a + 1] = {{ l = 6, tl = now }} end""")
        self.road_y = (self.ROW + 0.5) / 64
        self.walk(self.road_y)                     # along the road
        self.walk(0.70)                            # and across open ground

    def walk(self, y):
        for i in range(140):
            self.wow.H.player.x = 0.12 + i * 0.002
            self.wow.H.player.y = y
            self.wow.advance(1)
        self.wow.H.player.x, self.wow.H.player.y = 0.9, 0.9   # step away
        self.wow.advance(5)

    def trail(self, after):
        """Trail ink (red, not the silver road) as (x1, y1, x2, y2), `after` seconds on."""
        from render import COLLECT
        self.wow.run(f"__H.now = __H.now + {after}")
        self.wow.eval("ns.Redraw()")
        out = []
        for p in self.wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and float(f[2]) > float(f[3]) + 0.3 and float(f[5]) > 0.02:
                out.append(tuple(float(v) for v in f[6:10]))
        return out

    def on(self, segs, y):
        py = y * 668
        return [q for q in segs if abs((q[1] + q[3]) / 2 - py) < 4]

    def test_trail_along_a_road_gives_way(self):
        early = self.trail(5 * 60)
        self.assertTrue(self.on(early, self.road_y), "the last few minutes show on the road too")
        late = self.trail(15 * 60)                 # 20 minutes after
        self.assertEqual(self.on(late, self.road_y), [], "old trail still drawn over the road")
        self.assertTrue(self.on(late, 0.70), "trail off the roads must stay")

    def test_no_road_shown_nothing_gives_way(self):
        self.wow.run("ns.cfg.layers.roads = false")
        self.assertTrue(self.on(self.trail(20 * 60), self.road_y))

    def test_giving_way_only_fades(self):
        before = self.trail(11 * 60)
        steady = Steadiness()
        for _ in range(8):                        # through the fade, 30 s at a time
            after = self.trail(30)
            self.assertEqual(steady.new_ink(before, after), [], "trail ink appeared or moved while fading")
            before = after


class OldTrail(unittest.TestCase):
    """Old trail stays readable on busy map art (3.8.3, Joe's picks over his
    Dustwallow screenshot): crimson long dashes on a dark casing, and an
    older pass gives way where a newer one runs alongside it.

    Before, 9-hour-old trail had sunk to an earthy red-brown and shrunk to
    dots, the same ink as Dustwallow's marsh outlines, and an out-and-back
    drew two rails side by side."""

    H = 668
    SLOT = 5 * 0.0020 * 1002                     # C.DASH_PERIOD x a zone map's thin line, px

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448; ns.cfg.trailMin = 720")
        self.wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.recent = true")

    def walk(self, x0, y0, x1, y1, steps=140):
        for i in range(steps + 1):
            self.wow.H.player.x = x0 + (x1 - x0) * i / steps
            self.wow.H.player.y = y0 + (y1 - y0) * i / steps
            self.wow.advance(1)

    def lines(self, after=0):
        from render import COLLECT
        if after:
            self.wow.run(f"__H.now = __H.now + {after}")
        self.wow.eval("ns.Redraw()")
        out = []
        for p in self.wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and float(f[5]) > 0.01:
                out.append(dict(rgb=tuple(float(v) for v in f[2:5]), a=float(f[5]),
                                seg=tuple(float(v) for v in f[6:10]), th=float(f[10])))
        return out

    @staticmethod
    def red(ls):
        # trail ink; not the tail line from the trail's end to your arrow
        return [l for l in ls if l["rgb"][0] > l["rgb"][1] + 0.3 and l["seg"][:2] != l["seg"][2:]]

    def on_row(self, ls, y):
        py = y * self.H
        return [l for l in self.red(ls) if abs((l["seg"][1] + l["seg"][3]) / 2 - py) < 3]

    def test_old_trail_stays_crimson_long_dashes(self):
        import math
        self.walk(0.20, 0.50, 0.70, 0.50)
        ls = self.on_row(self.lines(after=9 * 3600), 0.50)
        self.assertTrue(ls, "no old trail drawn")
        deep = (0.65, 0.03, 0.13)                       # the Horde's deep red
        for l in ls:
            self.assertLess(max(abs(c - d) for c, d in zip(l["rgb"], deep)), 0.02, "old trail sank towards brown")
            self.assertGreater(l["a"], 0.7, "old trail faded too far")
        xs = sorted((min(l["seg"][0], l["seg"][2]), max(l["seg"][0], l["seg"][2])) for l in ls)
        marks = []
        for a, b in xs:                                  # join the pieces of one mark
            if marks and a - marks[-1][1] < 0.3:
                marks[-1][1] = max(marks[-1][1], b)
            else:
                marks.append([a, b])
        inner = [b - a for a, b in marks[2:-2]]
        self.assertGreater(len(inner), 10)
        self.assertGreater(sorted(inner)[len(inner) // 2], 0.55 * self.SLOT, "old dashes shrank to dots")

    def test_every_dash_sits_on_a_dark_casing(self):
        self.walk(0.20, 0.50, 0.70, 0.50)
        ls = self.lines(after=3600)
        dark = [l for l in ls if max(l["rgb"]) < 0.15]
        dashes = self.red(ls)
        self.assertTrue(dashes)
        for l in dashes:
            match = [c for c in dark if c["seg"] == l["seg"]]
            self.assertTrue(match, "a dash without its casing")
            self.assertAlmostEqual(match[0]["th"] / l["th"], 1.7, places=3)

    def test_an_older_pass_gives_way_to_a_newer_one_alongside(self):
        self.walk(0.20, 0.50, 0.70, 0.50)                # out
        self.wow.advance(10 * 60)
        self.walk(0.70, 0.512, 0.20, 0.512)              # back, 8 px to the side
        ls = self.lines(after=10 * 60)
        self.assertTrue(self.on_row(ls, 0.512), "the newer pass must show")
        old = [l for l in self.on_row(ls, 0.50) if 0.25 * 1002 < l["seg"][0] < 0.65 * 1002]
        self.assertEqual(old, [], "the older pass still runs alongside the newer one")

    def test_a_pass_further_off_or_across_stays(self):
        self.walk(0.20, 0.50, 0.70, 0.50)
        self.wow.advance(10 * 60)
        self.walk(0.70, 0.56, 0.20, 0.56)               # 40 px away: a different way
        self.wow.advance(5)
        self.walk(0.45, 0.30, 0.45, 0.70)               # straight across
        ls = self.lines(after=10 * 60)
        old = self.on_row(ls, 0.50)
        self.assertTrue([l for l in old if 0.25 * 1002 < l["seg"][0] < 0.40 * 1002], "a separate way gave way")
        near = [l for l in old if abs((l["seg"][0] + l["seg"][2]) / 2 - 0.45 * 1002) < 12]
        self.assertTrue(near, "a crossing hid the older pass")

    def test_one_pass_never_hides_itself(self):
        # a tight zigzag lies alongside itself within two minutes: it all stays
        for k in range(6):
            y = 0.50 + (k % 2) * 0.012
            self.walk(0.30 if k % 2 == 0 else 0.50, y, 0.50 if k % 2 == 0 else 0.30, y, steps=20)
        ls = self.lines(after=30 * 60)
        span = (0.32 * 1002, 0.48 * 1002)
        for y in (0.50, 0.512):
            inked = sum(abs(l["seg"][2] - l["seg"][0]) for l in self.on_row(ls, y)
                        if span[0] < l["seg"][0] < span[1])
            self.assertGreater(inked, 0.5 * (span[1] - span[0]), f"the pass along {y} hid itself")

    # Sharp turns stay solid (3.8.3, Joe): at a hairpin the dashes broke into
    # scattered pieces. Ink near the turn must be one unbroken piece.
    @staticmethod
    def pieces(segs, tol=0.8):
        """How many separate runs of ink: segments joined end to end."""
        parent = list(range(len(segs)))
        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i
        ends = [((s[0], s[1]), (s[2], s[3])) for s in segs]
        for i in range(len(segs)):
            for j in range(i + 1, len(segs)):
                if any(abs(p[0] - q[0]) < tol and abs(p[1] - q[1]) < tol for p in ends[i] for q in ends[j]):
                    parent[find(i)] = find(j)
        return len({find(i) for i in range(len(segs))})

    def hairpin(self):
        self.walk(0.20, 0.50, 0.50, 0.50, steps=90)        # out
        self.walk(0.50, 0.50, 0.50, 0.508, steps=2)        # round the tip
        self.walk(0.50, 0.508, 0.20, 0.508, steps=90)      # and back, 5 px over
        self.walk(0.20, 0.508, 0.20, 0.80, steps=90)       # then away

    def near(self, ls, x, y, r):
        return [l["seg"] for l in self.red(ls)
                if ((l["seg"][0] + l["seg"][2]) / 2 - x) ** 2 + ((l["seg"][1] + l["seg"][3]) / 2 - y) ** 2 < r * r]

    def test_a_hairpin_stays_solid_through_the_turn(self):
        self.hairpin()
        ls = self.lines(after=3600)
        near = self.near(ls, 0.50 * 1002, 0.504 * self.H, 3 * self.SLOT)
        tipx = max(max(s[0], s[2]) for s in near)
        tip = [s for s in near if max(s[0], s[2]) > tipx - 1.0 * self.SLOT]
        self.assertEqual(self.pieces(tip), 1, "the turn broke into dashes")
        # one solid piece from a slot before the turn to a slot after it
        for row in (0.50 * self.H, 0.508 * self.H):
            on = [s for s in tip if abs((s[1] + s[3]) / 2 - row) < 1.5]
            self.assertTrue(on, "the solid stretch doesn't reach along both sides")
            self.assertLessEqual(min(min(s[0], s[2]) for s in on), tipx - 1.0 * self.SLOT,
                                 "the solid stretch starts too close to the turn")
        legs = self.near(ls, 0.35 * 1002, 0.504 * self.H, 3 * self.SLOT)
        self.assertGreater(self.pieces(legs), 3, "the straight legs should still be dashes")

    def test_a_gentle_bend_stays_dashed(self):
        import math
        for i in range(121):
            a = i / 120 * math.pi
            self.wow.H.player.x, self.wow.H.player.y = 0.40 + 0.08 * math.cos(a), 0.50 + 0.08 * math.sin(a)
            self.wow.advance(1)
        segs = [l["seg"] for l in self.red(self.lines(after=3600))]
        self.assertGreater(self.pieces(segs), 12, "a gentle bend turned solid")

    def test_a_turn_only_fades(self):
        self.hairpin()
        before = [l["seg"] for l in self.red(self.lines(after=3 * 60))]
        steady = Steadiness()
        for minutes in (5, 30, 120):
            after = [l["seg"] for l in self.red(self.lines(after=minutes * 60))]
            self.assertEqual(steady.new_ink(before, after), [], "trail ink appeared at a turn as time passed")
            before = after

    def test_giving_way_only_fades_even_when_the_newer_pass_fades_on_a_road(self):
        # The newer pass runs on a road and gives way to it after 10-15 min;
        # the older one, just off the road, must not come back when it does.
        self.wow.run("ns.cfg.layers.roads = true")
        self.wow.run("""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {}
            for x = 8, 45 do local a = 30 * GW + x z.road[a * 10000 + a + 1] = { l = 6, tl = now } end""")
        road_y = 30.5 / 64
        self.walk(0.15, road_y + 0.022, 0.65, road_y + 0.022)   # older, 15 px off the road
        self.wow.advance(5 * 60)
        self.walk(0.65, road_y, 0.15, road_y)                   # newer, on the road
        steady = Steadiness()
        before = [l["seg"] for l in self.red(self.lines(after=3 * 60))]
        for _ in range(30):                                     # through the road fade, 40 s at a time
            after = [l["seg"] for l in self.red(self.lines(after=40))]
            self.assertEqual(steady.new_ink(before, after), [], "older trail came back as the newer pass faded")
            before = after


class Roads(unittest.TestCase):
    """A route walked on several days is one road (3.7.12).

    Nobody walks the same line twice. Before 3.7.12 each day's drift of a
    cell started a lane beside the last, so a route's days were split and it
    came out broken, doubled and late to gild."""

    CELL_Y = 1 / 64

    def walk_days(self, offsets):
        wow = Wow().login()
        for off in offsets:
            for i in range(200):                       # west to east across Felwood
                wow.H.player.x = 0.20 + i * 0.002
                wow.H.player.y = 0.40 + off + 0.002 * ((i // 7) % 2)
                wow.advance(0.5)
            wow.H.player.x = 0.9                        # leave, so the next day starts fresh
            wow.advance(30)
            wow.H.now = wow.H.now + 86400
            wow.advance(1)
        return wow

    def strengths(self, wow):
        return [float(v) for v in wow.eval("""(function()
            local t = {} for _, e in pairs(WarpathDB.maps[1448].road) do t[#t + 1] = ns.Long(e) end
            return table.concat(t, ",") end)()""").split(",")]

    def test_a_drifting_route_builds_one_road(self):
        one = self.walk_days([0])
        lane = len(self.strengths(one))
        wow = self.walk_days([0, self.CELL_Y, -0.6 * self.CELL_Y, 0.8 * self.CELL_Y])
        L = self.strengths(wow)
        self.assertLess(len(L), lane * 1.5, "each day's drift started a new lane")
        gold = sum(1 for v in L if v >= 2.5)
        self.assertGreater(gold, lane * 0.6, "four days on one route should gild most of it")

    def drawn_near(self, walked_gap):
        """Two roads along one row with a 3-stretch gap between them; is ink
        drawn in the middle of the gap?"""
        from render import COLLECT
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.roads = true")
        wow.run(f"""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {{}}
            local function Put(x, l) local a = 30 * GW + x z.road[a * 10000 + a + 1] = {{ l = l, tl = now }} end
            for x = 10, 15 do Put(x, 3) end          -- a road walked on three days
            for x = 19, 24 do Put(x, 3) end          -- and its continuation
            if {str(walked_gap).lower()} then for x = 16, 18 do Put(x, 1) end end  -- the gap, walked once
        """)
        D = wow.eval("ns.Redraw()")
        px, py = 17.5 / 96 * float(D["w"]), 30.5 / 64 * float(D["h"])
        for p in wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and Steadiness.dist(px, py, tuple(float(v) for v in f[6:10])) < 2:
                return True
        return False

    def test_a_short_walked_gap_between_roads_is_joined(self):
        self.assertTrue(self.drawn_near(walked_gap=True), "the road should run on through ground you walked")

    def test_a_gap_never_walked_is_left_open(self):
        self.assertFalse(self.drawn_near(walked_gap=False), "a join must follow ground you walked, not guess")

    def ink_at(self, setup, x, y):
        """Build roads with the given Lua, draw them, and say whether any
        line passes within 2 px of cell (x, y)."""
        from render import COLLECT
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.roads = true")
        wow.run("""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {}
            function Put(ax, ay, bx, by, l)
                local a, b = ay * GW + ax, by * GW + bx
                z.road[math.min(a, b) * 10000 + math.max(a, b)] = { l = l, tl = now }
            end
        """ + setup)
        D = wow.eval("ns.Redraw()")
        px, py = (x + 0.5) / 96 * float(D["w"]), (y + 0.5) / 64 * float(D["h"])
        for p in wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and Steadiness.dist(px, py, tuple(float(v) for v in f[6:10])) < 2:
                return True
        return False

    def test_a_sliver_beside_a_road_is_one_road(self):
        # a gold road along row 30, and a silver side path out to row 32 and back
        setup = """
            for x = 10, 25 do Put(x, 30, x + 1, 30, 3) end
            Put(14, 30, 15, 32, 2) Put(15, 32, 16, 32, 2) Put(16, 32, 17, 32, 2) Put(17, 32, 18, 30, 2)
        """
        self.assertTrue(self.ink_at(setup, 16, 30), "the road itself must stay")
        self.assertFalse(self.ink_at(setup, 16, 32), "a short side path beside the road should fold into it")

    def test_a_big_loop_keeps_both_sides(self):
        # two ways round, 12 stretches each: a real choice of route, not a sliver
        setup = """
            for x = 10, 22 do Put(x, 30, x + 1, 30, 3) end
            Put(10, 30, 10, 36, 2.5) Put(23, 30, 23, 36, 2.5)
            for x = 10, 22 do Put(x, 36, x + 1, 36, 2.5) end
        """
        self.assertTrue(self.ink_at(setup, 16, 36), "a long way round is a road of its own")

    def test_upgrade_folds_side_by_side_lanes(self):
        wow = Wow().login()
        wow.run("""
            local z, GW = ns.ZoneData(1448), ns.C.GW
            local now = ns.PlayNow()
            z.road = {}
            local function Put(a, b, l, d) z.road[math.min(a, b) * 10000 + math.max(a, b)] = { l = l, tl = now, d = d } end
            for x = 10, 20 do
                Put(30 * GW + x, 30 * GW + x + 1, 2, 1)   -- a lane walked on two days, last on day 1
                Put(31 * GW + x, 31 * GW + x + 1, 1, 2)   -- the lane beside it, one other day
                Put(29 * GW + x, 29 * GW + x + 1, 1, 1)   -- and one walked the same day as the first
            end
            Put(30 * GW + 15, 31 * GW + 15, 1, 2)          -- a rung between lanes
            ns.MergeLanes(z, time())
        """)
        L = self.strengths(wow)
        self.assertEqual(len(L), 11, "three lanes and a rung should fold into one road of 11 stretches")
        for v in L:
            self.assertAlmostEqual(v, 3.0, places=3)        # 2 + 1, and the shared day counted once


class RoadFading(unittest.TestCase):
    """Roads only fade between visits (3.7.12).

    With nothing new walked, every stretch loses strength at the same rate,
    so the drawn roads may thin, gild back to silver, fade or go, but no ink
    may appear where there was none and nothing may get brighter. The 3.7.12
    prototype broke this: its gap joins and fragment rules were re-decided on
    every redraw, so as one stretch faded a join filled the gap at the
    brightness of the roads either side, and the network rewired itself."""

    def lines(self, wow):
        from render import COLLECT
        wow.eval("ns.Redraw()")
        out = []
        for p in wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L":
                out.append((float(f[5]),) + tuple(float(v) for v in f[6:10]))
        return out

    def brighter(self, earlier, later, tol=0.6, eps=0.02):
        """Points of later lines that no earlier line covered at least as
        strongly: new ink, or ink that got brighter."""
        bad = []
        for a, *seg in later:
            if a < 0.02:
                continue
            x1, y1, x2, y2 = seg
            for t in (0.0, 0.5, 1.0):
                px, py = x1 + t * (x2 - x1), y1 + t * (y2 - y1)
                best = max((ea for ea, *es in earlier if Steadiness.dist(px, py, tuple(es)) <= tol), default=0)
                if best < a - eps:
                    bad.append((round(px), round(py), round(best, 2), round(a, 2)))
        return bad

    def fade_days(self, setup, days=20):
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.roads = true")
        wow.run("""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {}
            function Put(ax, ay, bx, by, l)
                local a, b = ay * GW + ax, by * GW + bx
                z.road[math.min(a, b) * 10000 + math.max(a, b)] = { l = l, tl = now }
            end
        """ + setup)
        prev = self.lines(wow)
        self.assertGreater(len(prev), 0, "nothing drawn to begin with")
        base = int(wow.eval("ns.db.play.days"))
        for d in range(1, days + 1):
            wow.run(f"ns.db.play.days = {base + d}")   # one more day played, nothing walked
            wow.H.now += 1                              # the play clock caches per second
            cur = self.lines(wow)
            with self.subTest(play_day=d):
                self.assertEqual(self.brighter(prev, cur), [], "road ink appeared or brightened with nothing walked")
            prev = cur

    def test_a_weak_middle_fades_instead_of_being_joined_over(self):
        # a road whose middle stretch was walked less: as it fades the middle
        # goes first; it must not be filled back in at the road's brightness
        self.fade_days("""
            for x = 10, 14 do Put(x, 30, x + 1, 30, 2.2) end
            Put(15, 30, 16, 30, 1.3)
            for x = 16, 20 do Put(x, 30, x + 1, 30, 2.2) end
        """)

    def test_a_lynchpin_is_held_as_a_thread_until_what_it_joins_fades(self):
        # The weak middle of a road (1.3) is the only link between its two
        # strong halves (2.2). On its own it drops out within two days; held,
        # it stays as a faint thread while both halves are drawn, then goes.
        wow = Wow().login()
        wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.roads = true")
        wow.run("""
            local z, GW, now = ns.ZoneData(1448), ns.C.GW, ns.PlayNow()
            z.road = {}
            local function Put(x, l) local a = 30 * GW + x z.road[a * 10000 + a + 1] = { l = l, tl = now } end
            for x = 10, 14 do Put(x, 2.2) end
            Put(15, 1.3)
            for x = 16, 20 do Put(x, 2.2) end
        """)
        base = int(wow.eval("ns.db.play.days"))
        D = wow.eval("ns.Redraw()")
        px, py = 16.0 / 96 * float(D["w"]), 30.5 / 64 * float(D["h"])  # mid-stretch: cell 15 centre to cell 16 centre

        def middle(day):
            wow.run(f"ns.db.play.days = {base + day}")
            wow.H.now += 1
            return max((a for a, *s in self.lines(wow) if Steadiness.dist(px, py, tuple(s)) < 2), default=0)

        thread, held = float(wow.eval("ns.C.ROAD_THREAD")), middle(4)
        self.assertGreater(held, 0.15, "day 4: the middle is gone on its own, but should still show as a thread")
        self.assertAlmostEqual(held, thread, places=2, msg="day 4: held at the thread level")
        self.assertEqual(middle(14), 0, "day 14: both halves have faded, so the thread goes too")

    def test_a_worn_road_with_a_weak_middle_only_fades(self):
        # A heavily worn road (faction mark, both tiers) with a weaker stretch
        # in the middle: as that stretch fades out, nothing beyond it may move
        # or brighten.
        # (Threads off: a held thread would keep the middle drawn.)
        self.fade_days("""
            ns.C.ROAD_THREAD = 0
            for x = 10, 19 do Put(x, 30, x + 1, 30, 22) end
            Put(20, 30, 21, 30, 1.5)
            for x = 21, 34 do Put(x, 30, x + 1, 30, 22) end
        """, days=10)

    def test_a_joined_network_only_fades(self):
        # two roads joined across ground walked once, a side path beside one,
        # and a scrap: every rule the prototype added, fading together
        self.fade_days("""
            for x = 10, 16 do Put(x, 30, x + 1, 30, 3) end
            for x = 17, 19 do Put(x, 30, x + 1, 30, 0.9) end
            for x = 20, 26 do Put(x, 30, x + 1, 30, 1.7) end
            Put(12, 30, 13, 32, 1.6) Put(13, 32, 14, 32, 1.6) Put(14, 32, 15, 30, 1.6)
            Put(30, 40, 31, 40, 1.9)
            for y = 30, 36 do Put(24, y, 24, y + 1, 1.5) end
        """)


class Lingering(unittest.TestCase):
    """Where you lingered becomes an outlined area (3.8).

    Questing tangles the trail into scribble. Staying a few minutes in one
    place forms an area that grows while you're in it and freezes when you
    leave; the trail inside is replaced by the outline."""

    MAP = 1448

    def setUp(self):
        from render import COLLECT
        self.COLLECT = COLLECT
        self.wow = Wow().login()
        self.wow.run(f"ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = {self.MAP}")

    def go(self, x, y):
        self.wow.H.player.x, self.wow.H.player.y = x, y
        self.wow.advance(1)

    def quest(self, cx, cy, seconds, r=0.025, phase=0.0):
        import math
        for i in range(seconds):
            t = i * 0.05 + phase
            self.go(cx + r * math.sin(t * 1.3) * math.cos(t * 0.7), cy + r * 1.4 * math.sin(t * 0.9))

    def walk(self, x0, y0, x1, y1, step=0.004):
        n = max(1, int(((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5 / step))
        for i in range(1, n + 1):
            self.go(x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n)

    def areas(self):
        return self.wow.eval(f"#(WarpathDB.maps[{self.MAP}].areas or {{}})")

    def live(self):
        return self.wow.eval("ns.Linger.Live() ~= nil")

    def visits(self, i=1):
        return self.wow.eval(f"#WarpathDB.maps[{self.MAP}].areas[{i}].v")

    def spent(self, i=1):
        return self.wow.eval(f"""(function() local n = 0
            for _, v in ipairs(WarpathDB.maps[{self.MAP}].areas[{i}].v) do n = n + v.t end return n end)()""")

    def outline_px(self, i=1):
        flat = self.wow.eval(f"table.concat(ns.Linger.Outline(WarpathDB.maps[{self.MAP}].areas[{i}]), ',')")
        v = [float(t) for t in flat.split(",")]
        return [(v[j] * 1002, v[j + 1] * 668) for j in range(0, len(v), 2)]

    def lines(self):
        self.wow.eval("ns.Redraw()")
        out = []
        for p in self.wow.run(self.COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L":
                out.append(tuple(float(v) for v in f[6:10]))
        return out

    def test_questing_forms_an_area_that_freezes_when_you_leave(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.assertEqual(self.areas(), 0, "walking somewhere is not lingering")
        self.quest(0.40, 0.50, 6 * 60)
        self.assertEqual(self.areas(), 1)
        self.assertTrue(self.live())
        before = self.wow.eval(f"table.concat(WarpathDB.maps[{self.MAP}].areas[1].h, ',')")
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.assertFalse(self.live(), "walking away leaves the area")
        after = self.wow.eval(f"table.concat(WarpathDB.maps[{self.MAP}].areas[1].h, ',')")
        xs = [float(v) for v in after.split(",")[0::2]]
        self.assertLess(max(xs), 0.40 + 0.025 + 0.035, "the walk out joined the area")
        self.assertGreater(len(before), 0)
        self.assertGreater(self.spent(), 5 * 60)

    # 3.8.3: the time label is WoW's yellow on a soft dark patch (Joe's pick
    # from renders over his Undercity screenshot) and stays readable as the
    # area ages, fading only in the trail's last quarter.
    def label(self, hours_later=0):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.wow.run(f"ns.cfg.trailMin = 720; __H.now = __H.now + {int(hours_later * 3600)}")
        self.wow.eval("ns.Redraw()")
        found = self.wow.eval("""(function()
            for _, f in ipairs(WarpathOverlay.__children) do
                if f.back and f.text and f:IsShown() then
                    local r, g, b, a = f.text:GetTextColor()
                    return table.concat({ f.text:GetText(), r, g, b, a,
                        f.back:IsShown() and 1 or 0, f.back:GetAlpha(), f.back:GetWidth(),
                        f.text:GetStringWidth() }, "|")
                end
            end
        end)()""")
        self.assertTrue(found, "no area label drawn")
        t = found.split("|")
        return dict(text=t[0], colour=tuple(float(v) for v in t[1:4]), alpha=float(t[4]),
                    back=t[5] == "1", back_alpha=float(t[6]), back_w=float(t[7]), text_w=float(t[8]))

    def test_the_area_label_is_yellow_on_a_dark_patch(self):
        lab = self.label()
        self.assertRegex(lab["text"], r"^\d+m$")
        self.assertEqual(lab["colour"], (1, 0.82, 0))
        self.assertEqual(lab["alpha"], 1)
        self.assertTrue(lab["back"])
        self.assertGreater(lab["back_alpha"], 0.5)
        self.assertGreater(lab["back_w"], lab["text_w"])

    def test_an_old_area_label_stays_readable(self):
        self.assertGreaterEqual(self.label(hours_later=3)["alpha"], 0.9)

    def test_the_label_fades_in_the_trails_last_quarter(self):
        lab = self.label(hours_later=10.5)
        self.assertLess(lab["alpha"], 0.9)
        self.assertLess(lab["back_alpha"], 0.7)

    # 3.8.3: an old area's outline keeps its gaps to at most a third of a
    # dash slot, so it stays joined up instead of thinning to sparse dots.
    # From pick C (2026-11-26) it uses the trail's own dash (85% -> 65% of a
    # slot), so the dash still shortens with age.
    def outline_gaps(self, hours_later):
        import math
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.wow.run(f"ns.cfg.trailMin = 720; __H.now = __H.now + {int(hours_later * 3600)}")
        poly = self.outline_px()
        poly = poly + poly[:1] if poly[0] != poly[-1] else poly
        def off(x, y):  # distance from the outline
            best = 1e9
            for (ax, ay), (bx, by) in zip(poly, poly[1:]):
                dx, dy = bx - ax, by - ay
                t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / ((dx * dx + dy * dy) or 1)))
                best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
            return best
        on = [(x1, abs(y1), x2, abs(y2)) for x1, y1, x2, y2 in self.lines()
              if off(x1, abs(y1)) < 0.5 and off(x2, abs(y2)) < 0.5]
        self.assertTrue(on, "no outline drawn")
        # pieces split at a corner are one dash: count dash starts only
        ends = {(round(x2, 2), round(y2, 2)) for _, _, x2, y2 in on}
        dashes = sum(1 for x1, y1, _, _ in on if (round(x1, 2), round(y1, 2)) not in ends)
        drawn = sum(math.hypot(x2 - x1, y2 - y1) for x1, y1, x2, y2 in on)
        perim = sum(math.hypot(bx - ax, by - ay) for (ax, ay), (bx, by) in zip(poly, poly[1:]))
        slot = 5 * 0.0020 * 1002                     # C.DASH_PERIOD x a zone map's thin line
        return (perim - drawn) / dashes / slot, drawn / dashes / slot

    def test_an_old_area_outline_stays_joined_up(self):
        gap, dash = self.outline_gaps(hours_later=6)
        self.assertLess(dash, 0.8, "the dash no longer shortens with age")
        self.assertGreater(dash, 0.6, "the outline's dash is not the trail's")
        self.assertLessEqual(gap, 0.36, "old outline gaps are wider than a third of a slot")

    def test_an_old_area_outline_sits_on_the_casing(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.wow.run("__H.now = __H.now + 3600")
        import math
        from render import COLLECT
        poly = self.outline_px()
        poly = poly + poly[:1]
        def off(x, y):
            return min(Steadiness.dist(x, y, (ax, ay, bx, by)) for (ax, ay), (bx, by) in zip(poly, poly[1:]))
        self.wow.eval("ns.Redraw()")
        segs = {}
        for p in self.wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L":
                x1, y1, x2, y2 = (float(v) for v in f[6:10])
                if off(x1, abs(y1)) < 0.5 and off(x2, abs(y2)) < 0.5 and math.hypot(x2 - x1, y2 - y1) > 0.5:
                    segs.setdefault(tuple(f[6:10]), []).append(float(f[2]))
        self.assertTrue(segs, "no outline drawn")
        for k, reds in segs.items():
            self.assertTrue(any(r < 0.15 for r in reds) and any(r > 0.3 for r in reds),
                            "an outline dash without its casing")

    def test_standing_still_is_not_lingering(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        for _ in range(15 * 60):
            self.go(0.40, 0.50)
        self.assertEqual(self.areas(), 0)

    def test_a_short_trip_past_the_edge_does_not_split_the_area(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.40, 0.62)          # out past the edge...
        self.walk(0.40, 0.62, 0.40, 0.50)          # ...and straight back
        self.quest(0.40, 0.50, 6 * 60, phase=2.0)
        self.assertEqual(self.areas(), 1)

    def test_a_return_visit_adds_its_time_to_the_same_area(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        first = self.spent()
        self.walk(0.40, 0.50, 0.80, 0.30)
        self.quest(0.80, 0.30, 6 * 60)             # somewhere else for a while
        self.walk(0.80, 0.30, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60, phase=1.0)
        self.assertEqual(self.areas(), 2)
        self.assertEqual(self.visits(1), 2)
        self.assertGreater(self.spent(1), first + 5 * 60)

    def inside_ink(self, poly, lines, margin=2.0):
        """Points of drawn lines well inside an area's outline (not on it)."""
        def inside(x, y):
            c = False
            for (x1, y1), (x2, y2) in zip(poly, poly[1:]):
                if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                    c = not c
            return c
        bad = []
        for x1, y1, x2, y2 in lines:
            for t in (0.25, 0.5, 0.75):
                x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * t
                if inside(x, y) and min(Steadiness.dist(x, y, (a[0], a[1], b[0], b[1]))
                                        for a, b in zip(poly, poly[1:])) > margin:
                    bad.append((round(x), round(y)))
        return bad

    def test_after_you_leave_the_trail_stops_at_the_outline(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 8 * 60)
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.wow.advance(3 * 60)
        poly = self.outline_px()
        lines = self.lines()
        self.assertTrue(lines)
        self.assertEqual(self.inside_ink(poly, lines), [], "trail drawn inside an area you've left")
        # and the check can fail: without the cut, the tangle is still there
        self.wow.run("ns.Linger.Clip = function(_, _, _, _, _, out) out(0, 1, 1) end")
        self.assertNotEqual(self.inside_ink(poly, self.lines()), [])

    def hull_xs(self, i=1):
        h = self.wow.eval(f"table.concat(WarpathDB.maps[{self.MAP}].areas[{i}].h, ',')")
        return [float(v) for v in h.split(",")[0::2]]

    def room(self, cx, cy, seconds, rx, ry):
        import math
        for i in range(seconds):
            t = i * 0.05
            self.go(cx + rx * math.sin(t * 1.3) * math.cos(t * 0.7), cy + ry * math.sin(t * 0.9))

    def test_areas_are_measured_in_yards(self):
        # Joe, test3: in the Undercity the area by the lift covered only part
        # of where he lingered. Distances were fractions of the map, and a
        # city map covers a few times less ground than a zone map. The same
        # room-sized wander (about 60 yards across a 1000-yard city map)...
        self.wow = Wow()                                # a map's width is read once, at its first sample
        self.wow.run(f"__H.mapYards = {{ [{self.MAP}] = 1000 }}")
        self.wow.login()
        self.wow.run(f"ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = {self.MAP}")
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.room(0.40, 0.50, 6 * 60, 0.06, 0.08)
        self.assertEqual(self.areas(), 1, "a room in a city is somewhere you lingered")
        # ...on a zone map is ground four times wider, and isn't one place
        other = Lingering()
        other.setUp()
        other.walk(0.20, 0.50, 0.40, 0.50)
        other.room(0.40, 0.50, 6 * 60, 0.06, 0.08)
        self.assertEqual(other.areas(), 0)

    def test_side_by_side_areas_become_one(self):
        # Joe, Plaguelands data (3.8.3): questing that wandered made areas
        # next to each other that never joined. The area you're in takes in
        # one its outline touches.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)                # area one: x about 0.375-0.425
        self.walk(0.40, 0.50, 0.50, 0.50)             # 200 yd east, too far to reopen it
        self.quest(0.50, 0.50, 6 * 60, phase=1.0)     # area two forms on its own
        self.assertEqual(self.areas(), 2)
        self.quest(0.49, 0.50, 3 * 60, phase=2.0)     # area two creeps west...
        self.quest(0.465, 0.50, 3 * 60, phase=3.0)
        self.quest(0.45, 0.50, 3 * 60, phase=4.0)     # ...until the outlines touch
        self.assertEqual(self.areas(), 1, "side-by-side areas didn't merge")
        self.assertLess(min(self.hull_xs()), 0.38)
        self.assertGreater(max(self.hull_xs()), 0.52)
        self.assertEqual(self.visits(1), 2, "a merged area keeps both visits")

    def test_far_apart_areas_stay_apart(self):
        # merging across a gap would draw one outline over the road between
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.55, 0.50)             # 400 yd of gap
        self.quest(0.55, 0.50, 8 * 60, phase=1.0)
        self.assertEqual(self.areas(), 2)

    def test_a_city_keeps_the_tighter_radius(self):
        # 225 yd suits questing outside; in the Undercity it swallowed the
        # corridor to the lift. The same 180-yard wander...
        city = Wow()
        city.run(f"__H.mapYards = {{ [{self.MAP}] = 1000 }}")
        city.login()
        self.wow = city
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.room(0.40, 0.50, 6 * 60, 0.18, 0.03)
        self.assertEqual(self.areas(), 0, "a wander across a city quarter made an area")
        # ...in the open world is somewhere you lingered
        other = Lingering()
        other.setUp()
        other.walk(0.20, 0.50, 0.40, 0.50)
        other.room(0.40, 0.50, 6 * 60, 0.045, 0.03)
        self.assertEqual(other.areas(), 1)

    def test_a_short_trip_past_the_edge_joins_the_area(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.45, 0.50)             # out past the edge (90 yd)...
        for _ in range(30):                           # ...about a bit there, within 150 yd...
            self.go(0.45, 0.505)
            self.go(0.45, 0.495)
        self.walk(0.45, 0.50, 0.40, 0.50)             # ...and straight back
        self.quest(0.40, 0.50, 60, phase=2.0)
        self.assertEqual(self.areas(), 1)
        self.assertGreater(max(self.hull_xs()), 0.445, "the trip's ground didn't join")

    def test_trail_from_just_before_an_area_forms_joins_it(self):
        self.walk(0.20, 0.50, 0.385, 0.50)
        for i in range(90):                           # milling about on one side, doubling back...
            self.go(0.387 + 0.003 * (i % 3 - 1), 0.49 + 0.02 * ((i // 3) % 2))
            self.go(0.387, 0.50)
        self.walk(0.387, 0.50, 0.52, 0.50)            # ...off east for a bit...
        self.room(0.52, 0.50, 90, 0.003, 0.01)
        self.walk(0.52, 0.50, 0.42, 0.50)             # ...and back in from the east
        self.room(0.42, 0.50, 5 * 60, 0.012, 0.02)    # ...then long enough beside it to form
        self.assertEqual(self.areas(), 1)
        self.assertLess(min(self.hull_xs()), 0.392, "the earlier wandering didn't join")

    def test_a_corridor_walked_out_and_back_stays_a_line(self):
        # Joe, test4: an area spread up the hallway. A short trip that only
        # walks out along a corridor and straight back isn't lingering.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.46, 0.50)             # straight up the corridor...
        self.walk(0.46, 0.50, 0.40, 0.50)             # ...and straight back
        self.quest(0.40, 0.50, 60, phase=2.0)
        self.assertEqual(self.areas(), 1)
        self.assertLess(max(self.hull_xs()), 0.44, "the corridor joined the area")

    def test_a_minute_inside_an_old_area_reopens_it(self):
        # Joe, test4: re-entering an old area didn't refresh it.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.80, 0.30)
        self.room(0.80, 0.30, 12 * 60, 0.003, 0.003)  # away longer than 10 minutes
        self.walk(0.80, 0.30, 0.40, 0.50)
        for _ in range(20):                           # through it, briefly: not reopened
            self.go(0.40, 0.50)
        self.assertFalse(self.live())
        self.quest(0.40, 0.50, 70, phase=1.0)         # a minute there: reopened
        self.assertTrue(self.live())
        self.assertEqual(self.wow.eval(f"WarpathDB.maps[{self.MAP}].areas[1]") is not None, True)
        self.assertEqual(self.visits(1), 2)

    def test_the_visit_list_reads_like_visits(self):
        # Stepping in and out at the edge made a list of "1 min" entries.
        out = self.wow.eval("""(function()
            local a = { v = {
                { s = 0, e = 600, t = 500 }, { s = 650, e = 700, t = 40 }, { s = 800, e = 860, t = 50 },
                { s = 3000, e = 3300, t = 280 }, { s = 3320, e = 3330, t = 10 },
                { s = 10000, e = 10050, t = 50 } } }
            local r = {}
            for _, v in ipairs(ns.Linger.Visits(a)) do r[#r + 1] = v.s .. ':' .. v.t end
            return table.concat(r, ' ')
        end)()""")
        self.assertEqual(out, "0:590 3000:340")

    def test_inside_the_area_you_are_in_only_your_last_moments_show(self):
        # Joe, test4: lingering left a fresh scribble of the last minutes
        # inside the area. 3.8.2 (Joe): only the last 3 s show there, not 45 s
        # ("the point of the zone is to stop scribbling the map").
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 8 * 60)
        self.assertTrue(self.live())
        recent = self.wow.eval("""(function()
            local out, now = {}, time()
            for _, s in ipairs(WarpathDB.maps[1448].strokes) do
                for i = 1, #s / 2 do
                    if ns.PointTime(s, i) >= now - 5 then out[#out + 1] = s[2 * i - 1] .. ',' .. s[2 * i] end
                end
            end
            return table.concat(out, ';')
        end)()""")
        pts = [tuple(float(v) for v in p.split(",")) for p in recent.split(";")]
        pts = [(x * 1002, y * 668) for x, y in pts] + [(self.wow.H.player.x * 1002, self.wow.H.player.y * 668)]
        path = [(a[0], a[1], b[0], b[1]) for a, b in zip(pts, pts[1:])]
        stray = [(x, y) for x, y in self.inside_ink(self.outline_px(), self.lines())
                 if min(Steadiness.dist(x, y, sg) for sg in path) > 1.5]
        self.assertEqual(stray, [], "older line drawn inside the area you're in")

    def run_frames(self, seconds, x, y, ang, speed=7 / 4000.0, dt=0.05, each=None):
        """Run in a slow circle at running speed, frame by frame, with the map
        open: the sampler and the map's 2 s redraws run as in game, and the
        map's per-frame update (UpdateTail) every frame."""
        import math
        for f in range(int(round(seconds / dt))):
            ang += 0.6 * dt
            x += speed * dt * math.cos(ang)
            y += speed * dt * math.sin(ang)
            self.wow.H.player.x, self.wow.H.player.y = x, y
            self.wow.advance(dt)
            self.wow.run("ns.UpdateTail()")
            if each:
                each(f)
        return x, y, ang

    def comet_pieces(self):
        """Your own line inside the area you're in, within 3 s of running of
        you (older trail there is steps not yet joined): {segment: (alpha, width)}."""
        px, py = self.wow.H.player.x * 1002, self.wow.H.player.y * 668
        r, g, b = (float(v) for v in self.wow.run(
            "return ns.faction.r .. ' ' .. ns.faction.g .. ' ' .. ns.faction.b").split())
        poly = self.outline_px()
        out = {}
        for p in self.wow.run(self.COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] != "L" or abs(float(f[2]) - r) > 0.01 or abs(float(f[3]) - g) > 0.01 or abs(float(f[4]) - b) > 0.01:
                continue
            a, x1, y1, x2, y2, w = (float(v) for v in f[5:11])
            near = ((x1 + x2) / 2 - px) ** 2 + ((y1 + y2) / 2 - py) ** 2 < 12 ** 2
            if a > 0.01 and near and self.inside_ink(poly, [(x1, y1, x2, y2)], margin=0):
                out[(round(x1, 1), round(y1, 1), round(x2, 1), round(y2, 1))] = (a, w)
        return out

    def into_live_area(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 8 * 60)
        self.assertTrue(self.live())
        self.wow.eval("ns.Redraw()")
        return self.wow.H.player.x, self.wow.H.player.y

    def test_inside_the_area_you_are_in_the_line_fades_like_a_comet(self):
        # Joe, 3.8.3-test8: "a more comet-like fade from the end to bright just
        # behind me", still only 3 s long. The pieces of line inside the area
        # are brightest and widest just behind you and fainter, thinner back.
        x, y = self.into_live_area()
        self.run_frames(3, x, y, 0.0)
        px, py = self.wow.H.player.x * 1002, self.wow.H.player.y * 668
        pieces = sorted((((k[0] + k[2]) / 2 - px) ** 2 + ((k[1] + k[3]) / 2 - py) ** 2, a, w)
                        for k, (a, w) in self.comet_pieces().items())
        self.assertGreaterEqual(len(pieces), 10, "no comet behind you inside the area")
        near, far = pieces[0], pieces[-1]
        self.assertGreater(near[1], 0.85, "the comet isn't bright just behind you")
        self.assertLess(far[1], 0.25, "the comet doesn't fade out behind you")
        self.assertGreater(near[2], far[2], "the comet doesn't thin away from you")

    def test_the_comet_never_vanishes_and_only_fades(self):
        # Joe, 3.8.3-test13: "a full strength line forms behind me for 3
        # seconds and then the whole thing disappears and a new line begins".
        # Drawn from recorded steps at redraws, the comet was one line to your
        # arrow that grew, then reset at each redraw. Running through redraws,
        # frame by frame: the comet is always there, about as long, and each
        # piece only fades where it lies.
        x, y = self.into_live_area()
        x, y, ang = self.run_frames(3, x, y, 0.0)        # the comet grows in
        frames, drawn = [], self.wow.eval("ns.S.lastDraw")
        self.run_frames(8, x, y, ang, each=lambda f: frames.append(self.comet_pieces()))
        self.assertGreater(self.wow.eval("ns.S.lastDraw"), drawn + 4, "the map didn't redraw while running")
        counts = [len(fr) for fr in frames]
        self.assertGreater(min(counts), 0.6 * max(counts), f"the comet vanished: pieces per frame {counts}")
        for before, after in zip(frames, frames[1:]):
            for k, (a2, w2) in after.items():
                if k in before:
                    a, w = before[k]
                    self.assertLessEqual(a2, a + 1e-6, "a piece of comet got brighter")
                    self.assertLessEqual(w2, w + 1e-6, "a piece of comet got wider")

    def test_the_comet_shows_in_an_old_area_too(self):
        # Joe, 3.8.3-test14, Undercity: back in an old area, before it reopens
        # (a minute inside), the line still grew, then vanished at each
        # redraw: the comet drew only in the area you're lingering in. Any
        # area that hides your line gets the comet.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.80, 0.30)
        self.room(0.80, 0.30, 12 * 60, 0.003, 0.003)    # away longer than 10 minutes
        self.walk(0.80, 0.30, 0.40, 0.50)
        self.wow.eval("ns.Redraw()")
        x, y = self.wow.H.player.x, self.wow.H.player.y
        x, y, ang = self.run_frames(3, x, y, 0.0)
        self.assertFalse(self.live(), "the old area reopened: not the case under test")
        frames = []
        self.run_frames(6, x, y, ang, each=lambda f: frames.append(self.comet_pieces()))
        self.assertFalse(self.live())
        counts = [len(fr) for fr in frames]
        self.assertGreaterEqual(min(counts), 10, f"no steady comet in the old area: pieces per frame {counts}")
        last = sorted(frames[-1].values())
        self.assertLess(last[0][0], 0.25, "the comet doesn't fade out behind you")
        self.assertGreater(last[-1][0], 0.85, "the comet isn't bright just behind you")

    def test_the_hidden_trail_stays_hidden_when_you_leave(self):
        # Joe, 3.8.0-test3: leaving an area filled it with trail. The dashes
        # hidden while you were inside came back for a minute. Nothing at all
        # may be drawn inside just after leaving. 3.8.3-test14 (Joe,
        # Undercity): the solid line still came back, because this test had
        # shortened it to 5 s; it now runs at the real 2.5 min.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 8 * 60)
        # inside the area you're in: only your last seconds, around you
        px, py = self.wow.H.player.x * 1002, self.wow.H.player.y * 668
        before = [(x, y) for x, y in self.inside_ink(self.outline_px(), self.lines())
                  if (x - px) ** 2 + (y - py) ** 2 > 15 ** 2]
        self.assertEqual(before, [], "trail drawn inside the area you're in")
        self.walk(0.40, 0.50, 0.52, 0.50)              # just out: seconds after leaving
        self.assertFalse(self.live())
        self.assertEqual(self.inside_ink(self.outline_px(), self.lines()), [],
                         "hidden trail came back when you left")

    def test_areas_and_links_only_fade_as_time_passes(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.60, 0.35)
        self.quest(0.60, 0.35, 6 * 60, r=0.02)
        self.walk(0.60, 0.35, 0.75, 0.60)
        self.wow.advance(6 * 60)
        st = Steadiness()
        first = st.segments(self.wow)
        self.assertGreater(len(first), 20)
        for minutes in (1, 5, 15, 30):
            self.wow.advance(60 * minutes)
            with self.subTest(minutes_later=minutes):
                self.assertEqual(st.new_ink(first, st.segments(self.wow)), [], "ink appeared as time passed")

    def test_the_trail_between_visits_still_shows_when_you_come_back(self):
        # Found on a render (3.8.0-test2): coming back into an area stretched
        # every earlier visit's hidden span to "now", so the whole trail in
        # between vanished. Out to a loop well away from the area and back in:
        # the loop's dashes must still be drawn.
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.40, 0.20)
        self.walk(0.40, 0.20, 0.70, 0.20)
        self.walk(0.70, 0.20, 0.40, 0.50)              # back inside, within 10 minutes
        self.quest(0.40, 0.50, 7 * 60, phase=1.0)      # long enough that the loop is all dashes
        self.assertEqual(self.wow.eval("ns.Linger.Live() ~= nil"), True)
        far = [l for l in self.lines() if min(l[1], l[3]) < 0.30 * 668]
        self.assertGreater(len(far), 10, "the trail out and back vanished")

    def test_the_trail_reaches_you_between_redraws(self):
        # The trail is redrawn every 2 s at most and points are recorded every
        # few steps, but your arrow moves all the time: the trail must still
        # run right up to it, with no gap behind you (Joe, 3.8.0-test1).
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.lines()                                   # a redraw
        self.wow.H.player.x = 0.4025                   # a step on, not yet sampled or drawn
        self.wow.run("ns.UpdateTail()")
        ends = [(x2, y2) for x1, y1, x2, y2 in self.collect()]
        px, py = 0.4025 * 1002, 0.50 * 668
        self.assertTrue(any(abs(x - px) < 0.6 and abs(y - py) < 0.6 for x, y in ends),
                        "no line reaches where you are")

    def collect(self):
        out = []
        for p in self.wow.run(self.COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L":
                out.append(tuple(float(v) for v in f[6:10]))
        return out

    def test_areas_go_with_the_trail_after_a_day(self):
        self.walk(0.20, 0.50, 0.40, 0.50)
        self.quest(0.40, 0.50, 6 * 60)
        self.walk(0.40, 0.50, 0.70, 0.50)
        self.wow.H.now = self.wow.H.now + 25 * 3600
        self.wow.run("ns.Prune()")
        self.assertEqual(self.areas(), 0)


class Flights(unittest.TestCase):
    """Flight legs (3.8): the paths you fly most, etched into the map.

    Flight paths are point to point through hubs you pass on every trip, so
    drawing every flight spins a web. A flight is laid onto the legs already
    flown (snapped within 100 yd, so a return flight beside the outbound one
    is the same leg), each point gains a day of memory, and only legs flown
    on about two days are drawn. The old routes, matched by their two ends,
    split one path into several records and none ever showed."""

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("__H.taxi = false; UnitOnTaxi = function() return __H.taxi end")
        self.wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        self.wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.flights = true")

    def fly(self, pts, dy=0.0):
        w = self.wow
        w.H.player.x, w.H.player.y = pts[0][0], pts[0][1] + dy
        w.advance(1)
        w.run("__H.taxi = true")
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = max(1, int(((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5 / 0.004))
            for i in range(1, n + 1):
                w.H.player.x, w.H.player.y = ax + (bx - ax) * i / n, ay + (by - ay) * i / n + dy
                w.advance(0.5)
        w.run("__H.taxi = false")
        w.advance(2)                                    # landing closes the flight

    def next_day(self):
        self.wow.H.now += 86400
        self.wow.advance(1)

    def lines(self):
        from render import COLLECT
        self.wow.eval("ns.Redraw()")
        out = []
        for p in self.wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and float(f[5]) > 0.02:
                out.append((float(f[5]),) + tuple(float(v) for v in f[6:10]))
        return out

    def inked(self, x, y, tol=6):
        px, py = x * 1002, y * 668
        return any(Steadiness.dist(px, py, tuple(seg)) <= tol for _, *seg in self.lines())

    def legs(self):
        return int(self.wow.eval("#(WarpathDB.maps[1448].air or {})"))

    PATH = [(0.10, 0.50), (0.90, 0.50)]

    def test_a_flight_flown_once_draws_nothing(self):
        self.fly(self.PATH)
        self.assertGreater(self.legs(), 0, "the flight wasn't recorded")
        self.assertEqual(self.lines(), [], "a leg flown once (or today's flight) was drawn")

    def test_a_leg_flown_on_two_days_is_etched_once(self):
        self.fly(self.PATH)
        self.next_day()
        self.fly(list(reversed(self.PATH)), dy=0.02)    # the way back, ~50 yd to one side
        self.assertEqual(self.legs(), 1, "the return flight started a second leg beside the first")
        for x in (0.2, 0.5, 0.8):
            self.assertTrue(self.inked(x, 0.50), f"no etching at x={x}")

    def test_flights_from_different_places_build_the_shared_leg(self):
        self.fly([(0.10, 0.20), (0.50, 0.50), (0.90, 0.50)])
        self.next_day()
        self.fly([(0.10, 0.80), (0.50, 0.50), (0.90, 0.50)])
        for x in (0.6, 0.8):
            self.assertTrue(self.inked(x, 0.50), f"shared leg not etched at x={x}")
        self.assertFalse(self.inked(0.30, 0.35), "a branch flown once was etched")
        self.assertFalse(self.inked(0.30, 0.65), "a branch flown once was etched")

    def test_legs_only_fade(self):
        self.fly(self.PATH)
        self.next_day()
        self.fly(self.PATH)
        first = prev = self.lines()
        self.assertGreater(len(prev), 0)
        base = int(self.wow.eval("ns.db.play.days"))
        for d in range(1, 21):
            self.wow.run(f"ns.db.play.days = {base + d}")
            self.wow.H.now += 1
            cur = self.lines()
            with self.subTest(play_day=d):
                # against yesterday, and against the first day: a slow creep
                # brightens each day by less than the check's tolerance
                self.assertEqual(RoadFading.brighter(None, prev, cur), [], "leg ink appeared or brightened")
                self.assertEqual(RoadFading.brighter(None, first, cur), [], "leg ink crept brighter")
            prev = cur
        self.assertEqual(prev, [], "legs never faded out")

    def test_dashes_stay_put_as_a_leg_fades(self):
        # A leg whose first half was flown on fewer days: as that half fades
        # out, the dashes on the rest must not shift. They're measured from
        # the start of the leg, not from the first part still drawn.
        bend = [(0.10, 0.50), (0.30, 0.42), (0.50, 0.40), (0.70, 0.44), (0.90, 0.50)]
        self.fly(bend)
        self.next_day()
        self.fly(bend)
        self.next_day()
        self.fly(bend[2:])
        st = Steadiness()
        prev = st.segments(self.wow)
        self.assertGreater(len(prev), 0)
        base = int(self.wow.eval("ns.db.play.days"))
        for d in range(1, 13):
            self.wow.run(f"ns.db.play.days = {base + d}")
            self.wow.H.now += 1
            cur = st.segments(self.wow)
            with self.subTest(play_day=d):
                self.assertEqual(st.new_ink(prev, cur), [], "leg dashes moved")
            prev = cur
        self.assertFalse(self.inked(0.2, 0.46), "the weaker half never faded out")
        self.assertTrue(self.inked(0.8, 0.47, tol=10), "the stronger half faded too soon")

    def test_old_routes_are_brought_over_once(self):
        w = self.wow
        w.run("""
            local z = ns.ZoneData(1448)
            local function Route(x1, x2, l)
                local r = { l = l, tl = ns.PlayNow(), d = 1 }
                for i = 0, 20 do r[#r + 1] = x1 + (x2 - x1) * i / 20; r[#r + 1] = 0.5 end
                return r
            end
            -- one path held as a whole record and a partial copy (the old split)
            z.routes = { Route(0.1, 0.9, 3), Route(0.4, 0.9, 1) }
            z.air = nil
            ns.Flights.Convert()
        """)
        self.assertEqual(self.legs(), 1, "the partial copy became a second leg")
        n = self.legs()
        w.run("ns.Flights.Convert()")
        self.assertEqual(self.legs(), n, "converting again added legs")
        self.assertEqual(int(w.eval("#WarpathDB.maps[1448].routes")), 2, "the old routes were not kept")
        for x in (0.2, 0.5, 0.8):
            self.assertTrue(self.inked(x, 0.50), f"a route flown on 3 days isn't etched at x={x}")


class FlightsOnContinents(Flights):
    """Flight legs on a continent (3.8.3, Joe): accurate start, path and end,
    without janky dashes. At continent scale a leg's points are under a
    pixel apart, so dashes drawn along them came out as kinked shapes, and
    legs recorded on the continent map itself were drawn zone-style. Each
    leg is simplified, rounded and dashed with straight strokes; a weaker
    leg beside a stronger one gives way. Felwood sits on Kalimdor about 156
    px across, so 0.064 of Felwood is one dash."""

    def setUp(self):
        super().setUp()

    def view(self, mapID=1414):
        self.wow.run(f"__H.mapShown = {mapID}")

    def strokes(self):
        """Blue dash strokes (the colour pass) and dark casing strokes."""
        from render import COLLECT
        self.wow.eval("ns.Redraw()")
        blue, dark = [], []
        for p in self.wow.run(COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] == "L" and float(f[5]) > 0.02:
                rgb = tuple(float(v) for v in f[2:5])
                seg = tuple(float(v) for v in f[6:10])
                if rgb[2] > 0.9 and rgb[0] < 0.4:
                    blue.append((seg, float(f[10])))
                elif max(rgb) < 0.15:
                    dark.append((seg, float(f[10])))
        return blue, dark

    WIGGLE = [(0.10 + 0.02 * i, 0.50 + (0.012 if i % 2 else -0.012)) for i in range(41)]  # about 2 px either side on Kalimdor

    def flown(self, path, days=2, dy=0.0):
        for d in range(days):
            if d:
                self.next_day()
            self.fly(path if d % 2 == 0 else list(reversed(path)), dy=dy)

    def put_leg(self, mapID, pts, days=3):
        """A leg straight into saved data, flown on `days` days, now."""
        flat = ", ".join(f"{x}, {y}" for x, y in pts)
        self.wow.run(f"""
            local z = ns.ZoneData({mapID})
            z.air = z.air or {{}}
            local leg = {{ {flat} }}
            leg.l, leg.t, leg.d = {{}}, {{}}, {{}}
            for i = 1, #leg / 2 do leg.l[i], leg.t[i], leg.d[i] = {days}, ns.PlayNow(), 1 end
            z.air[#z.air + 1] = leg""")

    def zigzag(self, x0, x1, y, amp, n=40):
        return [(x0 + (x1 - x0) * i / n, y + (0 if i in (0, n) else amp if i % 2 else -amp)) for i in range(n + 1)]

    def test_each_dash_is_one_straight_stroke_along_the_route(self):
        import math
        self.put_leg(1448, self.zigzag(0.10, 0.90, 0.50, 0.012))   # about 2 px either side on Kalimdor
        self.view()
        blue, dark = self.strokes()
        self.assertGreater(len(blue), 6, "no flight drawn on the continent")
        ends = {}
        for (x1, y1, x2, y2), _ in blue:
            for pt in ((round(x1, 1), round(y1, 1)), (round(x2, 1), round(y2, 1))):
                ends[pt] = ends.get(pt, 0) + 1
        self.assertEqual(max(ends.values()), 1, "a dash is made of several pieces")
        y0 = (0.230975 + 0.50 * 0.156251) * 668
        for (x1, y1, x2, y2), th in blue:
            self.assertLess(max(abs(y1 - y0), abs(y2 - y0)), 0.8, "a dash follows the recorded wiggle instead of the route")
            self.assertLessEqual(th, 1002 * 0.00088 * 1.6, "continent flights are not the thinner width")
        self.assertEqual(len(dark), len(blue), "every dash sits on its casing")
        # start and end where you flew: Felwood 0.10 and 0.90 on Kalimdor
        xs = [v for (x1, _, x2, _), _ in blue for v in (x1, x2)]
        self.assertLess(abs(min(xs) - (0.419158 + 0.10 * 0.156251) * 1002), 6)   # half a gap in
        self.assertLess(abs(max(xs) - (0.419158 + 0.90 * 0.156251) * 1002), 12)

    def test_a_hook_at_a_legs_end_is_dropped(self):
        # a leg's end joins the leg it met, which can double back a pixel or
        # three: that hook mustn't bend the last dash
        import math
        pts = [(0.10 + 0.02 * i, 0.50) for i in range(41)] + [(0.885, 0.52)]
        self.put_leg(1448, pts)
        self.view()
        blue, _ = self.strokes()
        self.assertGreater(len(blue), 6)
        y0 = (0.230975 + 0.50 * 0.156251) * 668
        for (x1, y1, x2, y2), _ in blue:
            self.assertLess(max(abs(y1 - y0), abs(y2 - y0)), 0.5, "the hook pulled the leg's end")

    def test_the_zone_map_is_unchanged(self):
        self.flown(self.WIGGLE)
        self.view(1448)
        blue, _ = self.strokes()
        self.assertTrue(any(th > 1002 * 0.0013 * 1.3 for _, th in blue), "the zone map's flights changed width")

    def test_a_leg_recorded_on_the_continent_map_is_drawn_the_same_way(self):
        import math
        self.put_leg(1414, self.zigzag(0.40, 0.56, 0.30, 0.002))
        self.view()
        blue, _ = self.strokes()
        self.assertGreater(len(blue), 4)
        for (x1, y1, x2, y2), th in blue:
            self.assertLessEqual(th, 1002 * 0.00088 * 1.6, "drawn at zone width")
            self.assertLess(math.degrees(math.atan2(abs(y2 - y1), abs(x2 - x1))), 12, "drawn zone-style along the wiggle")

    def test_a_weaker_leg_beside_a_stronger_one_gives_way(self):
        self.put_leg(1448, [(0.10 + 0.02 * i, 0.50) for i in range(41)], days=4)   # the main leg
        self.put_leg(1448, [(0.10 + 0.02 * i, 0.54) for i in range(41)], days=2)   # 6 px over on Kalimdor
        self.view()
        blue, _ = self.strokes()
        y0 = (0.230975 + 0.50 * 0.156251) * 668
        mid = [s for s, _ in blue if abs(s[0] - s[2]) > abs(s[1] - s[3]) and 470 < (s[0] + s[2]) / 2 < 490]
        rows = sorted({round((s[1] + s[3]) / 2) for s in mid})
        self.assertTrue(mid, "the main leg isn't drawn")
        self.assertLess(max(rows) - min(rows), 3, f"both legs drawn side by side: rows {rows}")

    def test_where_legs_meet_no_two_dashes_make_an_l(self):
        # one leg ends where another begins, at a right angle: their end dashes
        # touched and read as an L. The weaker leg's dash gives way.
        import math
        self.put_leg(1448, [(0.10 + 0.01 * i, 0.50) for i in range(41)], days=4)
        self.view()
        for start in (0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06):   # wherever its dashes fall
            self.wow.run("local z = ns.ZoneData(1448) z.air[2] = nil")
            self.put_leg(1448, [(0.50, 0.50 - start + 0.01 * i) for i in range(41)], days=2)
            blue, _ = self.strokes()
            ends = [((s[0], s[1]), (s[2], s[3]), abs(s[0] - s[2]) > abs(s[1] - s[3])) for s, _ in blue]
            for a, b, flat in ends:
                for c, d, flat2 in ends:
                    if flat and not flat2:
                        gap = min(math.dist(p, q) for p in (a, b) for q in (c, d))
                        self.assertGreater(gap, 1.5, f"two dashes meet in an L (leg starting {start} back)")

    # Fitted dashes (3.8.3, Joe: "stretches where dashes are far away"):
    # each piece between sharp bends gets whole dashes with even gaps and
    # half a gap at each end, so no stubs are dropped and a bend is one gap.
    @staticmethod
    def along(blue, horizontal=True):
        ax = 0 if horizontal else 1
        return sorted((min(s[ax], s[ax + 2]), max(s[ax], s[ax + 2])) for s, _ in blue)

    def test_dashes_along_a_leg_are_evenly_spaced_end_to_end(self):
        self.put_leg(1448, [(0.10 + 0.01 * i, 0.50) for i in range(73)])   # a length that isn't whole dashes
        self.view()
        marks = self.along(self.strokes()[0])
        self.assertGreater(len(marks), 5)
        gaps = [b[0] - a[1] for a, b in zip(marks, marks[1:])]
        self.assertLess(max(gaps) - min(gaps), 0.6, f"uneven gaps: {[round(g, 1) for g in gaps]}")
        x0, x1 = (0.419158 + 0.10 * 0.156251) * 1002, (0.419158 + 0.82 * 0.156251) * 1002
        self.assertLess(abs((marks[0][0] - x0) - (x1 - marks[-1][1])), 1.0, "the two ends aren't alike")
        self.assertLess(marks[0][0] - x0, min(gaps), "more than half a gap before the first dash")

    def test_a_sharp_bend_is_one_gap_not_a_bent_dash(self):
        # A U-turn with a short side (switchbacks keep their sharp bends;
        # a single corner between long runs is rounded into a wide curve).
        # Without the cuts, a dash lands across the tip at up to 90 degrees.
        import math
        self.view()
        for k in range(16):                                  # the bend at every place in the rhythm
            x0 = 0.10 + 0.008 * k
            self.wow.run("ns.ZoneData(1448).air = {}")
            pts = ([(x0 + (0.50 - x0) * i / 40, 0.50) for i in range(41)]
                   + [(0.50, 0.50 + 0.01 * i) for i in range(1, 7)]
                   + [(0.50 - 0.01 * i, 0.56) for i in range(1, 41)])
            self.put_leg(1448, pts)
            blue, _ = self.strokes()
            self.assertGreaterEqual(len(blue), 4)            # two sides of 50 to 63 px
            for (x1, y1, x2, y2), _ in blue:
                ang = math.degrees(math.atan2(abs(y2 - y1), abs(x2 - x1)))
                self.assertLess(ang, 20, f"a dash cuts across the bend ({ang:.0f} degrees, start {x0:.3f})")
    def test_a_tiny_leg_is_not_drawn_on_a_continent(self):
        # a flight circling in to land at a flight master: a loop a few pixels across
        import math
        self.put_leg(1448, [(0.30 + 0.03 * math.cos(a / 8 * math.pi), 0.50 + 0.03 * math.sin(a / 8 * math.pi)) for a in range(17)])
        self.view()
        self.assertEqual(self.strokes()[0], [], "a landing loop was drawn on the continent")
        self.view(1448)
        self.assertTrue(self.strokes()[0], "the zone map should still show it")

    def test_every_leg_shown_is_drawn_whole(self):
        # one look: a leg flown on about two days isn't drawn half faded
        self.put_leg(1448, [(0.10 + 0.02 * i, 0.50) for i in range(41)], days=1.8)
        self.view()
        from render import COLLECT
        self.wow.eval("ns.Redraw()")
        alphas = [float(f.split("\t")[5]) for f in self.wow.run(COLLECT).split("\n")
                  if f.startswith("L\t") and float(f.split("\t")[4]) > 0.9]
        self.assertTrue(alphas)
        self.assertGreater(min(alphas), 0.9, "a shown leg drawn half faded")

    def test_where_a_leg_meets_another_side_on_no_t_forms(self):
        # a weaker leg ending against the middle of a stronger one
        import math
        self.put_leg(1448, [(0.10 + 0.01 * i, 0.50) for i in range(81)], days=4)
        self.view()
        for start in (0.0, 0.01, 0.02, 0.03, 0.04, 0.05):
            self.wow.run("local z = ns.ZoneData(1448) z.air[2] = nil")
            self.put_leg(1448, [(0.42 + 0.003 * start * 100, 0.20 + 0.0075 * i + start) for i in range(41)], days=2)
            blue, _ = self.strokes()
            flat = [s for s, _ in blue if abs(s[0] - s[2]) > abs(s[1] - s[3])]
            for s, _ in blue:
                if abs(s[1] - s[3]) > abs(s[0] - s[2]):
                    gap = min(Steadiness.dist(x, y, f) for f in flat for x, y in ((s[0], s[1]), (s[2], s[3])))
                    self.assertGreater(gap, 2.0, f"a leg's end dash butts into another leg (start {start})")

    def test_a_leg_crossing_another_keeps_every_dash(self):
        cross = [(0.50, 0.10 + 0.02 * i) for i in range(41)]
        self.put_leg(1448, cross, days=2)
        self.view()
        alone = len(self.strokes()[0])
        self.put_leg(1448, [(0.10 + 0.02 * i, 0.50) for i in range(41)], days=4)   # a stronger leg across it
        self.put_leg(1448, [(0.10 + 0.02 * i, 0.47) for i in range(41)], days=4)
        blue, _ = self.strokes()
        upright = [s for s, _ in blue if abs(s[1] - s[3]) > abs(s[0] - s[2])]
        self.assertEqual(len(upright), alone, "the crossing leg gave way where it crosses")

    def test_continent_dashes_only_fade(self):
        bend = [(0.10, 0.50), (0.30, 0.42), (0.50, 0.40), (0.70, 0.44), (0.90, 0.50)]
        self.fly(bend)
        self.next_day()
        self.fly(bend)
        self.next_day()
        self.fly(bend[2:])
        self.view()
        st = Steadiness()
        prev = st.segments(self.wow)
        self.assertGreater(len(prev), 0)
        base = int(self.wow.eval("ns.db.play.days"))
        for d in range(1, 13):
            self.wow.run(f"ns.db.play.days = {base + d}")
            self.wow.H.now += 1
            cur = st.segments(self.wow)
            with self.subTest(play_day=d):
                self.assertEqual(st.new_ink(prev, cur), [], "continent dashes moved as a leg faded")
            prev = cur


class Upgrades(unittest.TestCase):
    """Saved data from every past release upgrades with nothing lost.

    Each tag's own code plays a session and saves; the working copy then
    boots on that data. Needs the release tags (CI checks out with tags)."""

    def test_every_release_upgrades_cleanly(self):
        import subprocess
        from upgrade_matrix import upgrade
        tags = subprocess.run(["git", "-C", str(Path(__file__).resolve().parents[2]), "tag"],
                              capture_output=True, text=True).stdout.split()
        if not tags:
            self.skipTest("no release tags in this checkout")
        import tempfile
        work = Path(tempfile.mkdtemp(prefix="warpath-upgrade-"))
        for tag in sorted(tags, key=lambda t: tuple(int(x) for x in t.split("."))):
            with self.subTest(release=tag):
                before, after, errors, lost = upgrade(tag, work)
                self.assertEqual(errors, [])
                self.assertEqual(lost, [], f"upgrading from {tag} lost: {lost}")
                self.assertEqual(after["v"], 10)


# A wrapped string as the 3.8.3 welcome set it, for the renderer's line pitch.
PROBE_WRAP = r"""
__probe = ns.Book.Old.Font(WarpathChronicle.news.L, QuestFont, GameFontHighlight, ns.Book.Old.INK)
__probe:SetPoint("TOPLEFT", WarpathChronicle.left, "TOPLEFT", 32, -96)
__probe:SetWidth(ns.Book.PW - 64)
__probe:SetJustifyV("TOP")
__probe:SetSpacing(3)
__probe:SetText("Warpath draws your war on the world map: the roads you travel, today's trail, where you fought, "
    .. "killed and fell, and the enemies you've seen.\n\nThis book keeps a campaign for each time you ride out, "
    .. "and your ledger of grudges. Open it from the minimap button or with /warpath chronicle.")
"""


class BookRender(unittest.TestCase):
    """The chronicle renderer (book_render.py, render.py --book): every later
    phase of the redesign is checked against the design renders through it,
    so where it puts things is pinned here. Numbers are render px on the
    1092x748 design canvas: the book's top-left at (20.5, 40.4), as in Joe's
    screenshot, and 1.2 px a UI unit. Fonts are EB Garamond for every face
    (--fonts repo) so the results don't depend on the machine's fonts."""

    @classmethod
    def setUpClass(cls):
        global B
        import book_render as B
        cls.B = B
        cls.wow, cls.typ = B.boot(fonts="repo")
        cls.renders = {}
        for tab in B.TABS:
            B.open_book(cls.wow, tab)
            if tab == "warpath":
                cls.wow.run(PROBE_WRAP)
            cls.renders[tab] = B.render_book(cls.wow, cls.typ)

    def text(self, tab, s):
        """A text drawn on the pages (below the tabs, which share some names)."""
        found = [r for r in self.renders[tab][1].records if r["kind"] == "text" and r["text"] == s and r["top"] > 60]
        self.assertTrue(found, f"no text {s!r} drawn on {tab}")
        return found[0]

    def of(self, tab, lua):
        seq = self.wow.eval(lua + ".__seq")
        found = [r for r in self.renders[tab][1].records if r["obj"]["__seq"] == seq]
        self.assertTrue(found, f"{lua} not drawn on {tab}")
        return found[0]

    def assertBox(self, box, want, tol=0.5):
        for got, exp in zip(box, want):
            self.assertAlmostEqual(got, exp, delta=tol, msg=f"{box} != {want}")

    def test_every_tab_renders_without_errors(self):
        for tab, (img, painter) in self.renders.items():
            with self.subTest(tab=tab):
                self.assertEqual(img.size, (1092, 748))
                self.assertEqual(self.wow.eval("ns.Chronicle.Shown()") and True, True)
                self.assertIsNone(self.wow.H.errors)
                self.assertGreater(len([r for r in painter.records if r["kind"] == "text"]), 6)

    def test_the_frame_lands_where_the_screenshot_has_it(self):
        for tab in self.B.TABS:
            with self.subTest(tab=tab):
                plate = [r for r in self.renders[tab][1].records if "DialogBox-Header" in r.get("path", "")][0]
                self.assertBox(plate["box"], (320.5, 23.6, 776.5, 100.4))
                close = [r for r in self.renders[tab][1].records if r.get("what") == "close"][0]
                self.assertBox(close["box"], (1040.5, 38.0, 1078.9, 76.4))
        # five tabs of 92 units (ledger/lbase.py TABS_A), the open one taller:
        # its top at 12 against 20, each with a 1 px dark edge round its rim
        for i, x0, x1 in ((1, 65, 175), (2, 183, 293), (3, 301, 411), (4, 813, 923), (5, 931, 1041)):
            with self.subTest(tab=i):
                self.assertBox(self.of("warpath", f"WarpathChronicle.tabs[{i}].rim")["box"],
                               (x0, 12 if i == 5 else 20, x1 + 1, 46))
        self.assertBox(self.of("campaigns", "WarpathChronicle.tabs[1].rim")["box"], (65, 12, 176, 46))
        self.assertBox(self.of("campaigns", "WarpathChronicle.tabs[1].edge")["box"], (64, 11, 177, 46))

    def test_headings_sit_where_the_code_puts_them(self):
        # (Campaigns' and Warpath's headings are the 3.8.5 pages': CampaignsPage
        # and WarpathPage check them)
        # left page: TOP 0,-32, QuestTitleFont (Morpheus 18)
        for tab, s in (("settings", "Settings"), ("grudges", "The Ledger of Grudges")):
            with self.subTest(heading=s):
                r = self.text(tab, s)
                self.assertAlmostEqual((r["box"][0] + r["box"][2]) / 2, 295.3, delta=0.5)
                self.assertAlmostEqual(r["baseline"], 119.41, delta=0.5)

    def test_wrapped_text_steps_by_whole_pixels(self):
        # the 3.8.3 welcome's settings (QuestFont 13, SetSpacing(3), TOPLEFT
        # 32,-96 of the left page), kept as a probe string (setUpClass)
        r = self.text("warpath", self.wow.eval("__probe:GetText()").replace("\r", ""))
        self.assertGreaterEqual(len(r["lines"]), 6)
        self.assertAlmostEqual(r["box"][0], 80.5, delta=0.5)
        self.assertAlmostEqual(r["baselines"][0], 190.85, delta=0.5)
        # 15.6 px rounds up to 16, 3.6 to 4: 20 px a line, as Joe's screenshot steps 19 for 13 + 2
        self.assertAlmostEqual(r["baselines"][1] - r["baselines"][0], 20.0, delta=0.01)
        for line in r["lines"]:
            self.assertLessEqual(self.typ.width("Fonts\\FRIZQT__.TTF", 13, line), 358 + 0.01)

    def test_the_stub_has_what_the_probe_found(self):
        self.assertIsNone(self.wow.eval("UIParent:CreateTexture().SetGradientAlpha"), "SetGradientAlpha isn't on Forever")
        self.assertTrue(self.wow.eval("CreateColor ~= nil"))
        self.assertEqual(self.wow.eval("select(2, QuestFont:GetFont())"), 13)
        self.assertEqual(self.wow.eval("WarpathChronicle.left:GetFrameLevel() - WarpathChronicle:GetFrameLevel()"), 1)

    def test_paint_gradients_blends_masks_and_rotation(self):
        wow, B = self.wow, self.B
        wow.run("""
            local f = CreateFrame("Frame", nil, WarpathChronicle)
            f:SetFrameLevel(200) f:SetSize(400, 100) f:SetPoint("TOPLEFT", 100, -300)
            local bg = f:CreateTexture(nil, "BACKGROUND") bg:SetAllPoints() bg:SetColorTexture(1, 1, 1, 1)
            local g = f:CreateTexture(nil, "ARTWORK") g:SetSize(100, 20) g:SetPoint("TOPLEFT", 0, 0)
            g:SetColorTexture(1, 1, 1, 1) g:SetGradient("HORIZONTAL", CreateColor(1, 0, 0, 1), CreateColor(0, 0, 1, 1))
            local u = f:CreateTexture(nil, "BORDER") u:SetSize(40, 20) u:SetPoint("TOPLEFT", 120, 0)
            u:SetColorTexture(1, 0.6, 0.2, 1)
            local m = f:CreateTexture(nil, "ARTWORK") m:SetSize(40, 20) m:SetPoint("TOPLEFT", 120, 0)
            m:SetColorTexture(0.5, 0.5, 0.5, 1) m:SetBlendMode("MOD")
            local d = f:CreateTexture(nil, "BORDER") d:SetSize(40, 20) d:SetPoint("TOPLEFT", 180, 0)
            d:SetColorTexture(0.2, 0.2, 0.2, 1)
            local a = f:CreateTexture(nil, "ARTWORK") a:SetSize(40, 20) a:SetPoint("TOPLEFT", 180, 0)
            a:SetColorTexture(0, 0, 0.5, 1) a:SetBlendMode("ADD")
            local r = f:CreateTexture(nil, "ARTWORK") r:SetSize(40, 40) r:SetPoint("TOPLEFT", 240, -30)
            r:SetColorTexture(0, 0, 0, 1) r:SetRotation(math.pi / 4)
            local k = f:CreateTexture(nil, "ARTWORK") k:SetSize(40, 40) k:SetPoint("TOPLEFT", 320, -30)
            k:SetColorTexture(0, 0.6, 0, 1)
            local mask = f:CreateMaskTexture() mask:SetTexture("Interface\\\\AddOns\\\\Warpath\\\\glow") mask:SetAllPoints(k)
            k:AddMaskTexture(mask)
            local h = CreateFrame("Frame", nil, f) h:SetAllPoints() h:Hide()
            local x = h:CreateTexture(nil, "OVERLAY") x:SetAllPoints() x:SetColorTexture(1, 0, 1, 1)
            __H.testFrame = f""")
        img, _ = B.render_book(wow, self.typ)
        wow.run("__H.testFrame:Hide()")
        P = lambda ux, uy: img.getpixel((round(20.5 + (100 + ux) * 1.2), round(40.4 + (300 + uy) * 1.2)))
        left, right = P(3, 10), P(97, 10)
        self.assertGreater(left[0], 220)
        self.assertLess(left[2], 30)
        self.assertGreater(right[2], 220)
        self.assertLess(right[0], 30)
        for got, want in zip(P(140, 10), (128, 77, 26)):          # MOD: orange times half
            self.assertAlmostEqual(got, want, delta=3)
        for got, want in zip(P(200, 10), (51, 51, 178)):          # ADD: grey plus half blue
            self.assertAlmostEqual(got, want, delta=3)
        self.assertLess(sum(P(260, 50)), 30, "the turned square's middle is ink")
        self.assertEqual(P(242, 32), (255, 255, 255), "a corner of the unturned square is bare once turned")
        self.assertLess(P(340, 50)[0], 60, "the glow mask keeps the middle")
        self.assertEqual(P(321, 31), (255, 255, 255), "and drops the corner")
        self.assertNotEqual(P(380, 10), (255, 0, 255), "a hidden frame draws nothing")

    def test_a_scroll_child_moves_with_the_scroll_and_is_clipped(self):
        # 3.8.5: the Campaigns sheet scrolls a real child frame
        wow, B = self.wow, self.B
        wow.run("""
            local f = CreateFrame("Frame", nil, WarpathChronicle)
            f:SetFrameLevel(200) f:SetSize(400, 300) f:SetPoint("TOPLEFT", 100, -200)
            local bg = f:CreateTexture(nil, "BACKGROUND") bg:SetAllPoints() bg:SetColorTexture(1, 1, 1, 1)
            local sf = CreateFrame("ScrollFrame", nil, f) sf:SetSize(100, 50) sf:SetPoint("TOPLEFT", 50, -50)
            local c = CreateFrame("Frame", nil, sf) c:SetSize(100, 200) sf:SetScrollChild(c)
            local a = c:CreateTexture(nil, "ARTWORK") a:SetSize(100, 40) a:SetPoint("TOPLEFT", 0, 0) a:SetColorTexture(1, 0, 0, 1)
            local b = c:CreateTexture(nil, "ARTWORK") b:SetSize(100, 40) b:SetPoint("TOPLEFT", 0, -60) b:SetColorTexture(0, 0, 1, 1)
            local g = c:CreateTexture(nil, "ARTWORK") g:SetSize(100, 40) g:SetPoint("TOPLEFT", 0, -150) g:SetColorTexture(0, 1, 0, 1)
            sf:SetVerticalScroll(55)
            __H.testFrame = f""")
        img, _ = B.render_book(wow, self.typ)
        wow.run("__H.testFrame:Hide()")
        P = lambda ux, uy: img.getpixel((round(20.5 + (100 + ux) * 1.2), round(40.4 + (200 + uy) * 1.2)))
        self.assertGreater(P(100, 60)[2], 200, "the blue piece scrolled up into the window")
        self.assertEqual(P(100, 20), (255, 255, 255), "the red piece scrolled out above it is clipped")
        self.assertEqual(P(100, 160), (255, 255, 255), "the green piece below the window is clipped")

    def test_every_real_character_renders_every_tab(self):
        root = os.environ.get("WARPATH_WTF")
        if not root:
            self.skipTest("set WARPATH_WTF to render real characters' books")
        account = Path(root) / "SavedVariables" / "Warpath.lua"
        for path in sorted(Path(root).glob("*/*/SavedVariables/Warpath.lua")):
            files = [p for p in (path, account) if p.exists()]
            before = [hashlib.md5(p.read_bytes()).hexdigest() for p in files]
            wow, typ = self.B.boot(path, account if account.exists() else None, path.parents[1].name.split("-")[0],
                                   path.stat().st_mtime, fonts="repo")
            for tab in self.B.TABS:
                with self.subTest(character=path.parents[1].name, tab=tab):
                    self.B.open_book(wow, tab)
                    img, painter = self.B.render_book(wow, typ)
                    self.assertIsNone(wow.H.errors)
                    self.assertTrue(any(r["kind"] == "text" and r["top"] > 60 for r in painter.records))
            self.assertEqual(before, [hashlib.md5(p.read_bytes()).hexdigest() for p in files])


# The reference campaign (Lethality's 25 November, as saved), for tests that
# must run without real saved data.
REF_CAMPAIGN = r"""
local start = time({ year = 2026, month = 11, day = 25, hour = 14, min = 46 })
local function K(z, hm, n, f, c, lv, tag, st, mk, shot)
  local h, m = hm:match("(%d+):(%d+)")
  local t = time({ year = 2026, month = 11, day = 25, hour = tonumber(h), min = tonumber(m) }) + st
  return { z = z, t = t, n = n, f = f, c = c, lv = lv, tag = tag, st = st, mk = mk, shot = shot, x = 0.5, y = 0.5 }
end
__H.ref = { start = start, stop = start + 9 * 3600, played = 32160, cur = 0, kills = 6, deaths = 0, best = 6,
  streak = 6, yards = 267500, sightings = 90, avenged = 0, grudges = 0,
  zones = { [1427] = { k = 1, d = 0 }, [1443] = { k = 1, d = 0 }, [1452] = { k = 3, d = 0 }, [1445] = { k = 1, d = 0 } },
  kl = {
    K(1427, "17:35", "Bluey", "Bluey-Vitruvius", "ROGUE", 57, "first", 1, nil, 11),
    K(1443, "20:31", "Balrog", "Balrog-Fury", "MAGE", 48, "first", 2, nil, 12),
    K(1452, "22:52", "Pherk", "Pherk-Pawpads", "DRUID", 60, "first", 3, nil, 13),
    K(1452, "22:52", "Felon", "Felon-Keller", "WARRIOR", 55, "first", 4, 2, 14),
    K(1452, "22:56", "Felon", "Felon-Keller", "WARRIOR", 55, "streak", 5, nil, 15),
    K(1445, "23:29", "Xylanthian", "Xylanthian-Warcaster", "SHAMAN", 49, "first", 6, nil, 16),
  }, dl = {} }
WarpathDB.campaigns = { __H.ref }
WarpathDB.campaign = { start = time(), stop = time(), played = 0, cur = 0, kills = 0, deaths = 0, zones = {}, kl = {}, dl = {} }
"""


class CampaignsPage(unittest.TestCase):
    """The Campaigns page (3.8.5, ChronCampaigns.lua) against its spec,
    docs/design/chronicle-campaigns.md, whose geometry table is the page's
    GEOMETRY. Laid out by the book renderer (book_render.py) with EB
    Garamond for every face (--fonts repo), so the numbers don't depend on
    the machine's fonts; centring and right edges are checked against the
    widths the code itself measured."""

    def setUp(self):
        import book_render as B
        self.B = B
        self.wow, self.typ = B.boot(name="Lethality", fonts="repo")
        self.wow.run(REF_CAMPAIGN)
        self.wow.run("ns.Chronicle.Open(false, 'campaigns')")
        self.P = "ns.ChronCampaigns.Frames()"
        self.paint()

    def paint(self):
        self.img, self.painter = self.B.render_book(self.wow, self.typ)
        self.recs = {}
        for r in self.painter.records:
            self.recs.setdefault(r["obj"]["__seq"], r)

    def rec(self, lua):
        seq = self.wow.eval(lua + ".__seq")
        self.assertIn(seq, self.recs, f"{lua} not drawn")
        return self.recs[seq]

    def near(self, got, want, what, tol=1.2):
        # within 1 unit (1.2 render px), as the spec asks
        self.assertAlmostEqual(got, want, delta=tol, msg=f"{what}: {got:.2f} != {want}")

    def G(self, path):
        return self.wow.eval("ns.ChronCampaigns.GEOMETRY." + path)

    # -- geometry -------------------------------------------------------------
    def test_the_left_page_lands_where_the_spec_says(self):
        P = self.P
        cx = self.G("CX")
        first = self.rec(f"{P}.date.letters[1]")
        self.near(first["baseline"], self.G("date.y"), "date baseline")
        width = self.wow.eval(f"{P}.date.width")
        self.near(first["box"][0] + width / 2, cx, "date centred")
        rule = self.rec(f"{P}.dateRules[1]")
        self.near(rule["box"][1], self.G("date.y") + self.G("date.dy"), "date rule y")
        self.near(rule["box"][2], cx - width / 2 - self.G("date.gap"), "date rule's end", 1.5)
        for i, y in ((1, 150), (2, 185)):
            r = self.rec(f"{P}.title[{i}].letters[1]")
            self.near(r["baseline"], y, f"title line {i}")
            self.near(r["box"][0] + self.wow.eval(f"{P}.title[{i}].width") / 2, cx, f"title line {i} centred")
        cap = self.rec(f"{P}.cap")
        self.near(cap["baseline"], 286, "drop cap on the third line")
        self.near(cap["box"][0], self.G("cap.x"), "drop cap's left")
        line1 = self.rec(f"{P}.lines[1]")
        self.near(line1["baseline"], 242, "the prose's first line")
        capw = self.wow.eval(f"{P}.cap:GetStringWidth()") * 1.2
        self.near(line1["box"][0], 82 + 0.583 * capw + 5, "line 1 tucked to the L's stem")
        third = [r for r in self.painter.records if r["kind"] == "text" and abs((r.get("baseline") or 0) - 286) < 0.5
                 and 90 < r["box"][0] < 200]
        self.near(min(r["box"][0] for r in third), 82 + capw + 6, "line 3 clears the foot")
        self.near(self.wow.eval(f"{P}.mapRect[1]"), 110, "map left")
        self.near(self.wow.eval(f"{P}.mapRect[2]"), max(478, 242 + 22 * self.wow.eval(f"{P}.nLines") + 2), "map top")
        self.assertGreaterEqual(self.wow.eval(f"{P}.mapRect[2]"), 478)
        masked = self.rec(f"{P}.mapPool.tex[1]")
        self.assertIsNotNone(masked)
        self.near(self.wow.eval(f"{P}.mapRect[3]") - self.wow.eval(f"{P}.mapRect[1]"), 372, "map width")
        self.near(self.wow.eval(f"{P}.mapRect[4]") - self.wow.eval(f"{P}.mapRect[2]"), 180, "map height")

    def test_the_right_page_lands_where_the_spec_says(self):
        P = self.P
        h = self.rec(f"{P}.head.letters[1]")
        self.near(h["baseline"], 120, "Deeds and Losses")
        self.near(h["box"][0] + self.wow.eval(f"{P}.head.width") / 2, 802, "heading centred")
        paper = self.rec(f"{P}.sheet.paper")
        for got, want, what in zip(paper["box"], (576, 142, 1026, 421), ("left", "top", "right", "bottom")):
            self.near(got, want, "sheet " + what)
        zone = self.rec(f"{P}.zones[1].name")
        self.near(zone["baseline"], self.G("first"), "first zone line")
        self.near(zone["box"][0], 598, "zone name x")
        tally = self.rec(f"{P}.zones[1].tally")
        self.near(tally["box"][2], 1005, "tally right edge")
        t = self.rec(f"{P}.rows[1].time")
        self.near(t["baseline"], 184, "first row")
        self.near(t["box"][0], 616, "time x")
        self.near(self.rec(f"{P}.rows[1].name")["box"][0], 658, "name x")
        self.near(self.rec(f"{P}.rows[2].time")["baseline"], 237, "a zone's line and rows step 4 + 22 + 27")
        tile = self.rec(f"{P}.rows[1].tile.parts[2]")
        self.near(tile["box"][0], 586, "tile x")
        self.near(tile["box"][1], 167, "tile top")
        self.near(tile["box"][2] - tile["box"][0], 23, "tile rim, 22 px inclusive")
        rh = self.rec(f"{P}.reckHead.letters[1]")
        self.near(rh["baseline"], 448, "The Reckoning")
        for i in range(1, 7):
            lab = self.rec(f"{P}.reck[{i}].label")
            self.near(lab["baseline"], 488 + 26 * (i - 1), f"reckoning row {i}")
            self.near(lab["box"][0], 616, "reckoning label x")
            self.near(self.rec(f"{P}.reck[{i}].value.twin")["box"][2], 987, "value right edge (bold copy)")
        share = self.rec(f"{P}.share")
        for got, want in zip(share["box"], (938, 95, 1023, 121)):
            self.near(got, want, "Share")

    def test_the_footer_lands_where_the_spec_says(self):
        P = self.P
        e = self.rec(f"{P}.earlier.label")
        self.near(e["baseline"], 692, "Earlier")
        self.near(e["box"][0], 106, "Earlier x")
        self.near(self.rec(f"{P}.later.label")["box"][2], 990, "Later right edge")
        fl = self.rec(f"{P}.folioL")
        self.near(fl["baseline"], 694, "left folio")
        self.near(fl["box"][0], 200, "left folio x")
        fr = self.rec(f"{P}.folioR")
        self.near((fr["box"][0] + fr["box"][2]) / 2, 801, "right folio centred")
        self.near(self.rec(f"{P}.count")["box"][0], fl["box"][2] + 14, "count 14 px after the folio")

    def test_the_geometry_table_is_the_specs(self):
        # the spec's numbers, so a change to one has to be made in both
        spec = (Path(__file__).resolve().parents[2] / "docs" / "design" / "chronicle-campaigns.md").read_text(encoding="utf-8")
        for text in ("x 576–1025, y 142–420", "x 578–1023, y 146–416", "first zone line y 162",
                     "y 488, 514, 540, 566, 592, 618", "372 × 180", "centred on CX, y 107", "y 120; ornament y 133", "centred on CX, y 202", "first baseline y 242"):
            with self.subTest(text=text):
                self.assertIn(text, spec)
        self.assertEqual([self.G(f"sheet[{i}]") for i in range(1, 5)], [576, 142, 1025, 420])
        self.assertEqual([self.G(f"win[{i}]") for i in range(1, 5)], [578, 146, 1023, 416])
        self.assertEqual((self.G("first"), self.G("date.y"), self.G("head.y"), self.G("head.orn")), (162, 107, 120, 133))
        self.assertEqual((self.G("map.w"), self.G("map.h"), self.G("reck.y"), self.G("reck.lh")), (372, 180, 488, 26))
        self.assertEqual((self.G("row"), self.G("zone"), self.G("after"), self.G("folded")), (27, 22, 4, 26))

    # -- words ----------------------------------------------------------------
    def date_text(self):
        w = self.wow
        out = []
        for i in range(1, 80):
            if not w.eval(f"{self.P}.date.letters[{i}] ~= nil and {self.P}.date.letters[{i}]:IsShown()"):
                break
            out.append(w.eval(f"{self.P}.date.letters[{i}]:GetText()"))
        return "".join(out)

    def test_the_left_page_reads_as_the_design(self):
        w = self.wow
        self.assertEqual(w.eval(f"{self.P}.written.title[1]"), "From Searing Gorge")
        self.assertEqual(w.eval(f"{self.P}.written.title[2]"), "to Dustwallow Marsh")
        self.assertTrue(self.date_text().startswith("WEDNESDAY, NOVEMBER 25  ·  A SKIRMISH"), self.date_text())
        self.assertEqual(w.eval(f"{self.P}.cap:GetText()"), "L")
        self.assertEqual(w.eval(f"{self.P}.lines[1]:GetText()"), "ethality", "the cap's letter leaves the prose")
        # names are their own strings, in N2 with a black shadow
        found = w.eval(f"""(function() for _, fs in ipairs({self.P}.lines) do
            if fs:IsShown() and fs:GetText() == "Bluey" then local r, g, b = fs:GetTextColor()
            local x = fs:GetShadowOffset() return r .. "," .. g .. "," .. b .. "," .. x end end end)()""")
        self.assertIsNotNone(found)
        r, g, b, x = (float(v) for v in found.split(","))
        self.assertGreater(x, 0, "a name has its shadow")
        self.assertGreater(r, b, "a rogue's N2 is warm")

    def test_tags_raise_only_the_rare_part(self):
        rows = self.wow.eval(f"""(function() local out = {{}}
            for _, g in ipairs({self.P}.groups) do for _, it in ipairs(g.items) do
              out[#out + 1] = table.concat(it.plain, ", ") .. "|" .. table.concat(it.raised, ", ") end end
            return table.concat(out, ";") end)()""").split(";")
        self.assertEqual(rows, ["first blood|", "first blood|", "first blood|", "first blood|double kill",
                                "|streak of 5", "first blood|"])
        self.assertEqual(self.wow.eval(f"{self.P}.groups[3].honours"), 2)
        self.assertTrue(self.wow.eval(f"{self.P}.rows[4].band.strips[1][1]:IsShown()"), "an honour row has its band")
        self.assertFalse(self.wow.eval(f"{self.P}.rows[3].band.strips[1] ~= nil and {self.P}.rows[3].band.strips[1][1]:IsShown()"))
        self.assertEqual(self.wow.eval(f"{self.P}.zones[3].tally:GetText()"), "3 slain")

    def test_the_tooltip_names_the_foe_first_last(self):
        w = self.wow
        w.run("__H.tip = {} GameTooltip.AddLine = function(self, t) table.insert(__H.tip, t) end")
        w.run(f"local r = {self.P}.rows[1] r:GetScript('OnEnter')(r)")
        self.assertEqual(w.eval("__H.tip[1]"), "Bluey Vitruvius")
        self.assertIn("Slain once this campaign", [w.eval(f"__H.tip[{i}]") for i in range(1, 6)])
        w.run("__H.tip = {}")
        w.run(f"local h = {self.P}.hovers[1] h:GetScript('OnEnter')(h)")
        self.assertEqual(w.eval("__H.tip[1]"), "Bluey Vitruvius", "a name in the prose has the same tooltip")

    # -- the sheet ------------------------------------------------------------
    def test_the_sheet_scrolls_fades_and_keeps_its_size(self):
        w, P = self.wow, self.P
        S = f"{P}.sheet"
        # six rows in four zones: 282 px of content in a 270 px window
        self.assertEqual(w.eval(f"{S}.content"), 282)
        self.assertEqual(w.eval(f"{S}:Range()"), 12)
        self.assertTrue(w.eval(f"{S}.bar:IsShown()"), "the bar shows while the deeds overflow")
        self.assertEqual(w.eval(f"{P}.zones[1]:GetAlpha()"), 1, "no fade at the top before scrolling")
        w.run(f"{S}.frame:GetScript('OnMouseWheel')({S}.frame, -1)")
        self.assertEqual(w.eval(f"{S}.scroll"), 12, "the wheel scrolls, never past the end")
        self.assertLess(w.eval(f"{P}.zones[1]:GetAlpha()"), 1, "scrolled: the top fades")
        self.assertEqual(w.eval(f"{P}.rows[6]:GetAlpha()"), 1, "at the end: nothing below to fade into")
        self.paint()
        paper = self.rec(f"{S}.paper")["box"]
        self.assertAlmostEqual(paper[3] - paper[1], 279, delta=0.5, msg="the sheet never changes size")
        # a short night: no bar, no fades, same sheet
        w.run("for i = 2, 6 do __H.ref.kl[i] = nil end ns.Chron.Render()")
        self.assertFalse(w.eval(f"{S}.bar:IsShown()"))
        self.assertEqual(w.eval(f"{S}:Range()"), 0)
        self.paint()
        self.assertEqual(self.rec(f"{S}.paper")["box"], paper)

    def test_a_folded_zone_hides_its_rows_and_closes_the_gap(self):
        w, P = self.wow, self.P
        before = w.eval(f"{P}.sheet.content")
        w.run(f"local z = {P}.zones[3] z:GetScript('OnClick')(z)")
        self.assertTrue(w.eval(f"{P}.folded[3]"))
        self.assertEqual(w.eval(f"{P}.sheet.content"), before - (22 + 3 * 27 + 4) + 26)
        self.assertFalse(w.eval(f"{P}.rows[4]:IsShown()"), "only three rows left to show")
        self.paint()
        self.near(self.rec(f"{P}.zones[4].name")["baseline"], 268 + 26, "the next zone moves up")
        self.assertEqual(w.eval(f"{P}.zones[3].tally:GetText()"), "3 slain", "a folded zone keeps its tally")
        self.assertTrue(w.eval(f"{P}.zones[3].dia[1].fill:IsShown()"), "and its honours")
        w.run(f"local z = {P}.zones[3] z:GetScript('OnClick')(z)")
        self.assertEqual(w.eval(f"{P}.sheet.content"), before)

    # -- the quiet filter -----------------------------------------------------
    def quiet_list(self):
        # newest first: a patrol (newest), the reference, a clash, a patrol, a skirmish
        self.wow.run("""
            local function C(day, kills, deaths)
              local s = time({ year = 2026, month = 11, day = day, hour = 10 })
              local kl, dl = {}, {}
              for i = 1, kills do kl[i] = { z = 1448, t = s + i * 60, n = "Foe" .. i, c = "MAGE" } end
              for i = 1, deaths do dl[i] = { z = 1448, t = s + 900 + i * 60 } end
              return { start = s, stop = s + 3600, played = 3600, cur = 0, kills = kills, deaths = deaths,
                zones = { [1448] = { k = kills, d = deaths } }, kl = kl, dl = dl, sightings = 3 }
            end
            WarpathDB.campaigns = { C(26, 0, 0), __H.ref, C(24, 1, 0), C(23, 0, 0), C(22, 5, 2) }
            ns.Chronicle.Open(false, "campaigns")""")

    def test_quiet_campaigns_hide_by_default_and_the_box_shows_them(self):
        w, P = self.wow, self.P
        self.quiet_list()
        self.assertEqual(w.eval("#ns.Chron.view.list"), 3, "the newest (quiet) stays, two quiet ones hide")
        self.assertEqual(w.eval("ns.Chron.view.quietN"), 2)
        self.assertEqual(w.eval(f"{P}.quiet.label:GetText()"), "show 2 quiet")
        self.assertEqual(w.eval(f"{P}.count:GetText()"), "campaign 3 of 3")
        w.run(f"local b = {P}.earlier b:GetScript('OnClick')(b)")
        self.assertEqual(w.eval("ns.Chron.view.list[ns.Chron.view.page] == __H.ref"), True)
        w.run(f"local b = {P}.earlier b:GetScript('OnClick')(b)")
        self.assertEqual(w.eval("ns.Chron.view.list[ns.Chron.view.page].kills"), 5, "Earlier steps over the quiet ones")
        self.assertFalse(w.eval(f"{P}.earlier:IsEnabled()"))
        w.run(f"local q = {P}.quiet q:GetScript('OnClick')(q)")
        self.assertTrue(w.eval("ns.cfg.chronQuiet"), "remembered for the account")
        self.assertEqual(w.eval("#ns.Chron.view.list"), 5)
        self.assertEqual(w.eval("ns.Chron.view.list[ns.Chron.view.page].kills"), 5, "the open campaign stays open")
        self.assertTrue(w.eval(f"{P}.quiet.check:IsShown()"))
        w.run("ns.Chronicle.Hide() ns.Chronicle.Open(false, 'campaigns')")
        self.assertEqual(w.eval("#ns.Chron.view.list"), 5, "still shown on the next opening")

    def test_preview_still_works(self):
        w = self.wow
        w.run("ns.Chronicle.Open(true, 'campaigns')")
        self.assertIsNone(w.H.errors)
        self.assertTrue(w.eval(f"not {self.P}.share:IsEnabled()"))
        self.assertFalse(w.eval(f"{self.P}.quiet:IsShown()"))
        self.assertIn("SAMPLE PAGES", self.date_text())


class CampaignsRealData(unittest.TestCase):
    """Every campaign of every real character opens, renders and turns
    without a Lua error (WARPATH_WTF). Nothing is written."""

    def test_every_campaign_of_every_character_opens(self):
        root = os.environ.get("WARPATH_WTF")
        if not root:
            self.skipTest("set WARPATH_WTF to open real characters' campaigns")
        import book_render as B
        account = Path(root) / "SavedVariables" / "Warpath.lua"
        for path in sorted(Path(root).glob("*/*/SavedVariables/Warpath.lua")):
            with self.subTest(character=path.parents[1].name):
                wow, typ = B.boot(path, account if account.exists() else None, path.parents[1].name.split("-")[0],
                                  fonts="repo")
                wow.run("ns.cfg.chronQuiet = true ns.Chronicle.Open(false, 'campaigns')")
                n = wow.eval("#ns.Chron.view.list")
                self.assertGreaterEqual(n, 1)
                for i in range(n):
                    wow.run("local P = ns.ChronCampaigns.Frames() for _, z in ipairs(P.zones) do "
                            "if z:IsShown() then z:GetScript('OnClick')(z) z:GetScript('OnClick')(z) end end "
                            "P.sheet:SetScroll(9999)")
                    B.render_book(wow, typ)
                    self.assertIsNone(wow.H.errors, f"campaign {i + 1}")
                    wow.run("local b = ns.ChronCampaigns.Frames().earlier b:GetScript('OnClick')(b)")
                self.assertEqual(wow.eval("ns.Chron.view.page"), n)


class WarpathPage(unittest.TestCase):
    """The Warpath tab (3.8.5, ChronWarpath.lua) against its spec,
    docs/design/chronicle-warpath.md, whose geometry tables are the page's
    GEOMETRY. Laid out by the book renderer with EB Garamond for every face
    (--fonts repo), so the numbers don't depend on the machine's fonts."""

    P = "ns.ChronWarpath.Frames()"

    def boot(self, state="update", faction=None):
        import book_render as B
        self.B = B
        self.wow, self.typ = B.boot(name="Lethality", fonts="repo", faction=faction)
        w = self.wow
        # what News knows: installed before (or not), the book closed
        w.run("if WarpathChronicle then WarpathChronicle:Hide() end")
        w.run("ns.gdb.installed = " + ("nil" if state == "first" else '"3.7.0"'))
        if state == "update":
            w.run("ns.Chronicle.News('3.8.2')")
        elif state == "first":
            w.run("ns.Chronicle.News(nil)")
        else:
            w.run("if WarpathChronicle then WarpathChronicle:Hide() end ns.Chronicle.Open(false, 'warpath')")
        return w

    def paint(self):
        self.img, self.painter = self.B.render_book(self.wow, self.typ)
        self.recs = {}
        for r in self.painter.records:
            self.recs.setdefault(r["obj"]["__seq"], r)

    def rec(self, lua):
        seq = self.wow.eval(lua + ".__seq")
        self.assertIn(seq, self.recs, f"{lua} not drawn")
        return self.recs[seq]

    def near(self, got, want, what, tol=1.2):
        self.assertAlmostEqual(got, want, delta=tol, msg=f"{what}: {got:.2f} != {want}")

    def G(self, path):
        return self.wow.eval("ns.ChronWarpath.GEOMETRY." + path)

    def versions(self):
        return self.wow.eval("""(function() local t = {} for i = #ns.NewIn.List, 1, -1 do
            t[#t + 1] = ns.NewIn.List[i][1] end return table.concat(t, ",") end)()""").split(",")

    def heads(self):
        """(version, baseline, gilt diamonds shown) of each release heading on the sheet."""
        out = []
        n = self.wow.eval(f"#{self.P}.heads")
        for i in range(1, n + 1):
            h = f"{self.P}.heads[{i}]"
            if self.wow.eval(f"{h}:IsShown()"):
                out.append((self.wow.eval(f"{h}.version"), self.wow.eval(f"{h}.caps.letters[1].by"),
                            self.wow.eval(f"{h}.dia[1].fill:IsShown() and {h}.dia[2].fill:IsShown()")))
        return out

    # -- geometry -------------------------------------------------------------
    def test_the_left_page_lands_where_the_spec_says(self):
        self.boot("update")
        self.paint()
        P, cx = self.P, 296
        k = self.rec(f"{P}.kicker.letters[1]")
        self.near(k["baseline"], 107, "kicker")
        self.near(k["box"][0] + self.wow.eval(f"{P}.kicker.width") / 2, cx, "kicker centred")
        rule = self.rec(f"{P}.kickerRules[2]")
        self.near(rule["box"][1], 103, "kicker rule y")
        t = self.rec(f"{P}.title.letters[1]")
        self.near(t["baseline"], 150, "title")
        self.near(t["box"][0] + self.wow.eval(f"{P}.title.width") / 2, cx, "title centred")
        cap = self.rec(f"{P}.cap")
        self.near(cap["baseline"], 254, "the initial sunk three lines")
        self.near(cap["box"][0], 81, "the initial's left")
        w1 = self.rec(f"{P}.words[1]")
        self.near(w1["baseline"], 210, "the welcome's first line")
        capw = self.wow.eval(f"{P}.cap:GetStringWidth()") * 1.2
        self.near(w1["box"][0], 82 + 1.0 * capw + 5, "line 1 tucked to the W's stem")
        self.assertLessEqual(self.wow.eval(f"{P}.welcomeEnd"), 290, "the welcome ends by y 290")
        fig = self.rec(f"{P}.figs[1]")
        self.assertEqual(self.wow.eval(f"{P}.figs[1]:GetText()"), "3.8.2")
        self.near(fig["baseline"], 210, "a figure sits on its line")
        self.assertEqual([self.wow.eval(f"{P}.picRect[{i}]") for i in range(1, 5)], [100, 288, 492, 428])
        for i in range(1, 9):
            lab = self.rec(f"{P}.keyLabels[{i}]")
            self.near(lab["baseline"], (448, 469, 490, 511)[(i - 1) // 2], f"key row {i}")
            self.near(lab["box"][0], (86, 330)[(i - 1) % 2] + 34, f"key label {i} x")
        gl = self.rec(f"{P}.keyGloss[1]")
        self.near(gl["box"][0], self.rec(f"{P}.keyLabels[1]")["box"][2] + 5, "the gloss 5 px after its label", 1.5)
        btn = self.rec(f"{P}.mapButton.bg")
        self.near((btn["box"][0] + btn["box"][2]) / 2, 95, "map button centre x")
        self.near((btn["box"][1] + btn["box"][3]) / 2, 535, "map button centre y")
        for lua, x, y in ((f"{P}.mapLine", 120, 540), (f"{P}.bookLine", 120, 562), (f"{P}.share.label", 110, 618),
                          (f"{P}.share.hint[1]", 110, 640), (f"{P}.share.hint[2]", 110, 659)):
            r = self.rec(lua)
            self.near(r["box"][0], x, lua + " x")
            self.near(r["baseline"], y, lua + " baseline")
        self.near(self.rec(f"{P}.share.state")["box"][0], self.rec(f"{P}.share.label")["box"][2] + 10, "state", 1.5)
        fo = self.rec(f"{P}.folioL")
        self.near(fo["baseline"], 694, "left folio")
        self.near((fo["box"][0] + fo["box"][2]) / 2, cx, "left folio centred")

    def test_the_map_button_and_check_box_sit_where_the_spec_says(self):
        w = self.boot("update")
        # frames, not drawn regions: their boxes from Book.Box
        bx = [w.eval(f"select({i}, {self.P}.mapButton:GetPoint(1))") for i in (4, 5)]
        self.near(bx[0] * 1.2 + 20.5, 95 - 12, "map button's left")
        self.near(-bx[1] * 1.2 + 40.4, 535 - 12, "map button's top")
        self.near(w.eval(f"{self.P}.mapButton:GetWidth()") * 1.2, 24, "map button at 24 px")
        cb = [w.eval(f"select({i}, {self.P}.share:GetPoint(1))") for i in (4, 5)]
        self.near(cb[0] * 1.2 + 20.5, 82, "check box x")
        self.near(-cb[1] * 1.2 + 40.4, 603, "check box top")

    def test_the_right_page_lands_where_the_spec_says(self):
        self.boot("update")
        self.paint()
        P = self.P
        h = self.rec(f"{P}.head.letters[1]")
        self.near(h["baseline"], 120, "What's New")
        self.near(h["box"][0] + self.wow.eval(f"{P}.head.width") / 2, 801, "heading centred")
        paper = self.rec(f"{P}.sheet.paper")
        for got, want, what in zip(paper["box"], (576, 150, 1026, 669), ("left", "top", "right", "bottom")):
            self.near(got, want, "sheet " + what)
        v1 = self.rec(f"{P}.heads[1].caps.letters[1]")
        self.near(v1["baseline"], 176, "the first release's heading")
        self.near(v1["box"][0] + self.wow.eval(f"{P}.heads[1].caps.width") / 2, 796.5, "heading centred on the column")
        n1 = self.rec(f"{P}.notes[1].lines[1]")
        self.near(n1["box"][0], 606, "note text x")
        self.near(n1["baseline"], 176 + 26, "3.8.4 has no title: notes 26 below")
        self.near(self.wow.eval(f"{P}.notes[1].mark.x"), 594, "note mark centre")
        foot = self.rec(f"{P}.footer")
        self.near(foot["box"][2], 1017, "footer right edge")
        self.near(foot["baseline"], 694, "footer baseline")
        fr = self.rec(f"{P}.folioR")
        self.near((fr["box"][0] + fr["box"][2]) / 2, 801, "right folio centred")

    def test_a_note_wraps_with_a_hanging_indent(self):
        w = self.boot("update")
        self.assertTrue(w.eval(f"{self.P}.notes[1].lines[2] ~= nil and {self.P}.notes[1].lines[2]:IsShown()"),
                        "3.8.4's spirit-healer note takes two lines at 397 px")
        self.paint()
        a, b = self.rec(f"{self.P}.notes[1].lines[1]"), self.rec(f"{self.P}.notes[1].lines[2]")
        self.near(b["box"][0], a["box"][0], "the second line under the text, not the mark")
        self.near(b["baseline"] - a["baseline"], 20, "20 px leading")

    def test_the_geometry_table_is_the_specs(self):
        self.boot("settled")
        spec = (Path(__file__).resolve().parents[2] / "docs" / "design" / "chronicle-warpath.md").read_text(encoding="utf-8")
        for text in ("centred at (296, 107)", "centred at (296, 150); ornament at y 167", "from (82, 210), 428 wide",
                     "392 × 140, centred, top y 288", "columns at x 86 and 330; baselines 448, 469, 490, 511",
                     "icon centre (95, 535); text at (120, 540)", "(120, 562)", "box top-left (82, 603); label (110, 618)",
                     "from (110, 640), 400 wide", "box (576, 150)–(1025, 668)", "x 590–1003; first baseline at sheet top + 26",
                     "mark at x 594; text at x 606", "cord at x 1016", "right-aligned at (1017, 694)"):
            with self.subTest(text=text):
                self.assertIn(text, spec)
        self.assertEqual([self.G(f"sheet[{i}]") for i in range(1, 5)], [576, 150, 1025, 668])
        self.assertEqual([self.G(f"col[{i}]") for i in range(1, 3)], [590, 1003])
        self.assertEqual(self.G("win[2]") + self.G("first"), 150 + 26)
        self.assertEqual((self.G("note.mark"), self.G("note.x"), self.G("cord[1]")), (594, 606, 1016))

    # -- What's New -----------------------------------------------------------
    def test_every_release_is_on_the_sheet_newest_first(self):
        w = self.boot("update")
        self.assertEqual(w.eval(f"table.concat({self.P}.order, ',')").split(","), self.versions())
        heads = self.heads()
        self.assertEqual([h[0] for h in heads], self.versions())
        ys = [h[1] for h in heads]
        self.assertEqual(ys, sorted(ys), "laid out top to bottom, newest first")
        self.assertTrue(w.eval(f"{self.P}.heads[1]:GetParent() == {self.P}.sheet.child"), "on the sheet's scroll child")
        self.assertFalse(w.eval("WarpathChronicle.news.earlier ~= nil or WarpathChronicle.news.later ~= nil"), "no paging")
        self.assertGreater(w.eval(f"{self.P}.sheet:Range()"), 0, "it doesn't all fit: the sheet scrolls")
        self.assertEqual(w.eval(f"{self.P}.sheet.scroll"), 0, "opens at the top, on the newest")
        w.run(f"{self.P}.sheet:SetScroll(10000)")
        self.assertEqual(w.eval(f"{self.P}.sheet.scroll"), w.eval(f"{self.P}.sheet:Range()"))
        w.run("ns.Chronicle.News('3.8.2')")
        self.assertEqual(w.eval(f"{self.P}.sheet.scroll"), 0, "opened again: back at the top")

    def test_the_divider_sits_before_the_first_release_already_read(self):
        w = self.boot("update")
        self.assertTrue(w.eval(f"{self.P}.dividerShown"))
        self.assertEqual(w.eval(f"{self.P}.divider.text:GetText()"), "read before, at version 3.8.2")
        dy = w.eval(f"{self.P}.divider.y")
        ys = {v: y for v, y, _ in self.heads()}
        self.assertLess(ys["3.8.3"], dy, "below the last new release")
        self.assertLess(dy, ys["3.8.2"], "above 3.8.2, the first one read")
        self.assertEqual(ys["3.8.2"] - dy, 40, "the divider takes its room")

    def test_no_divider_on_a_first_install_or_from_the_tab(self):
        for state in ("first", "settled"):
            with self.subTest(state=state):
                w = self.boot(state)
                self.assertFalse(w.eval(f"{self.P}.dividerShown"))
                self.assertFalse(w.eval(f"{self.P}.divider ~= nil and {self.P}.divider:IsShown()"))
                self.assertEqual(w.eval(f"{self.P}.footer:GetText()"), f"{len(self.versions())} releases")

    def test_gilt_diamonds_on_new_releases_only(self):
        w = self.boot("update")
        newer = [v for v in self.versions() if w.eval(f'ns.NewIn.Older("3.8.2", "{v}")')]
        self.assertEqual([v for v, _, new in self.heads() if new], newer)
        self.assertEqual(newer, ["3.8.4", "3.8.3"])
        self.assertEqual(w.eval(f"{self.P}.footer:GetText()"), f"{len(self.versions())} releases  ·  2 new")
        # read ones are faded: their heading in (150,80,56), without a shadow
        h = f"{self.P}.heads[3]"
        self.assertEqual(w.eval(f"{h}.version"), "3.8.2")
        col = tuple(round(w.eval(f"select({i}, {h}.caps.letters[1]:GetTextColor())") * 255) for i in (1, 2, 3))
        self.assertEqual(col, (150, 80, 56))
        for state in ("first", "settled"):
            with self.subTest(state=state):
                self.boot(state)
                self.assertFalse(any(new for _, _, new in self.heads()))

    def test_a_release_title_shows_when_there_is_one(self):
        w = self.boot("update")
        titled = [i for i, h in enumerate(self.heads(), 1) if h[0] == "3.8.3"][0]
        self.assertEqual(w.eval(f"{self.P}.heads[{titled}].title:GetText()"), "Scores and a clearer trail")
        self.assertTrue(w.eval(f"{self.P}.heads[{titled}].title:IsShown()"))
        self.assertFalse(w.eval(f"{self.P}.heads[1].title:IsShown()"), "3.8.4 has no title yet")
        w.run('ns.NewIn.List[#ns.NewIn.List].title = "Spirit healers" ns.Chronicle.News("3.8.2")')
        self.assertTrue(w.eval(f"{self.P}.heads[1].title:IsShown()"))
        self.assertEqual(w.eval(f"{self.P}.heads[1].title:GetText()"), "Spirit healers")

    # -- the left page's words -------------------------------------------------
    def kicker(self):
        w, P = self.wow, self.P
        return "".join(w.eval(f"{P}.kicker.letters[{i}]:GetText()") for i in range(1, 80)
                       if w.eval(f"{P}.kicker.letters[{i}] ~= nil and {P}.kicker.letters[{i}]:IsShown()"))

    def test_the_three_states_read_as_the_spec(self):
        w = self.boot("update")
        v = w.eval("ns.VERSION")
        self.assertEqual(self.kicker(), f"VERSION {v}  ·  TWO NEW RELEASES")
        self.assertEqual(w.eval(f"{self.P}.welcome"), "Warpath was just updated, from {3.8.2} to {" + v + "}. What "
                         "changed is on the facing page, marked new. On the world map it draws Lethality's war in these marks.")
        self.assertEqual(w.eval(f"{self.P}.figs[2]:GetText()"), v)
        self.assertTrue(w.eval(f"{self.P}.figs[1].twin ~= nil"), "figures are faux bold")
        w = self.boot("first")
        self.assertEqual(self.kicker(), f"VERSION {v}  ·  A NEW CHRONICLE")
        self.assertRegex(w.eval(f"{self.P}.welcome"),
                         r"^Here begins the chronicle of Lethality, opened on the [a-z-]+ of [A-Z][a-z]+\. ")
        self.assertFalse(w.eval(f"{self.P}.figs[1] ~= nil and {self.P}.figs[1]:IsShown()"))
        w = self.boot("settled")
        self.assertEqual(self.kicker(), f"VERSION {v}")
        self.assertEqual(w.eval(f"{self.P}.welcome"), "This is the chronicle of Lethality, kept by Warpath. On the world "
                         "map it draws the war as it is fought, in these marks.")
        self.assertEqual(w.eval(f"{self.P}.cap:GetText()"), "T")
        self.assertEqual(w.eval(f"{self.P}.words[1]:GetText()"), "his", "the initial's letter leaves the words")

    def test_one_new_release_is_singular(self):
        w = self.boot("update")
        w.run("ns.Chronicle.News('3.8.3')")
        self.assertTrue(self.kicker().endswith("ONE NEW RELEASE"), self.kicker())
        self.assertEqual(w.eval(f"{self.P}.footer:GetText()"), f"{len(self.versions())} releases  ·  1 new")

    def test_punctuation_stays_on_a_figures_line(self):
        self.boot("settled")
        pieces = self.wow.eval("""(function() local t = {}
            for _, p in ipairs(ns.ChronWarpath.Pieces("from {3.8.2} to {3.8.4}. What")) do
                t[#t + 1] = p[1] .. (p[2] and "*" or "") .. (p[3] and "+" or "") end
            return table.concat(t, " ") end)()""")
        self.assertEqual(pieces, "from 3.8.2* to 3.8.4* .+ What")

    # -- the key ---------------------------------------------------------------
    def test_the_keys_crest_and_trail_follow_the_faction(self):
        for faction, crest, red in (("Horde", "UI-PVP-Alliance", True), ("Alliance", "UI-PVP-Horde", False)):
            with self.subTest(faction=faction):
                w = self.boot("settled", faction=faction)
                self.assertIn(crest, w.eval(f"{self.P}.keyPins.sight:GetTexture()"))
                self.assertEqual(w.eval(f"{self.P}.keyPins.sight:GetTexture()"), w.eval('(ns.MapLook.Pin("sight"))'))
                sight = [p for p in range(1, 9)
                         if w.eval(f"{self.P}.scenePins[{p}] ~= nil and {self.P}.scenePins[{p}].kind == 'sight'")]
                self.assertIn(crest, w.eval(f"{self.P}.scenePins[{sight[0]}]:GetTexture()"), "the picture's enemy too")
                rgb = [w.eval(f"{self.P}.trailColor[{i}]") for i in (1, 2, 3)]
                self.assertEqual(rgb[0] > rgb[2], red, f"the trail sample is {faction}'s colour: {rgb}")
                want = [w.eval(f"select({i}, ns.MapLook.Trail(ns.C.LINE_SOLID + 60, 43200))") for i in (1, 2, 3)]
                self.assertEqual(rgb, want, "the map's own trail colour")

    def test_the_keys_pins_use_the_maps_textures(self):
        w = self.boot("settled")
        for kind, tex, size in (("kill", "TEX_BLADES", 20), ("death", "TEX_SKULL", 17), ("sight", None, 20)):
            with self.subTest(kind=kind):
                p = f"{self.P}.keyPins.{kind}"
                self.assertEqual(w.eval(f"{p}:GetTexture()"), w.eval(f'(ns.MapLook.Pin("{kind}"))'))
                if tex:
                    self.assertEqual(w.eval(f"{p}:GetTexture()"), w.eval(f"ns.C.{tex}"))
                got = [w.eval(f"select({i}, {p}:GetTexCoord())") for i in (1, 2, 3, 4)]
                want = [w.eval(f'select({i}, ns.MapLook.PinCoords("{kind}"))') for i in (1, 2, 3, 4)]
                self.assertEqual(got, want)
                self.assertAlmostEqual(w.eval(f"{p}:GetWidth()") * 1.2, size, delta=0.01)
                self.assertEqual([w.eval(f"select({i}, {p}:GetVertexColor())") for i in (1, 2, 3)], [1, 1, 1],
                                 "untinted, as your own marks")

    def test_the_map_pins_through_the_same_look(self):
        # the other half of "can't drift": DrawMarks takes its textures from Look
        w = self.boot("settled")
        self.assertEqual(w.eval('(ns.MapLook.Pin("kill"))'), w.eval("ns.C.TEX_BLADES"))
        self.assertEqual(w.eval('(ns.MapLook.Pin("death"))'), w.eval("ns.C.TEX_SKULL"))
        self.assertEqual([w.eval(f'select({i}, ns.MapLook.PinCoords("sight"))') for i in (1, 2, 3, 4)], [0, 0.62, 0, 0.62])
        src = (Path(__file__).resolve().parents[2] / "Map.lua").read_text(encoding="utf-8")
        self.assertIn('f.tex:SetTexCoord(Look.PinCoords(kind))', src)
        self.assertIn('(Look.Pin("sight"))', src)

    def test_dashes_never_stall_where_a_dash_rounds_to_nothing(self):
        # the picture's trail found it: 5.95 on, 2.13 off along this stretch,
        # a dash's end rounded onto its start and Look.Dashes looped for ever
        # (the map's corpse runs used the same loop). Capped, so the old code
        # fails instead of hanging; the book stays shut (its picture stalled too).
        w = Wow()
        w.run("WarpathGlobal = { installed = '3.7.0', seenVersion = '99.0.0', cfg = {} }")
        w = w.login()
        n = w.eval("""(function() local n = 0
            local put = function() n = n + 1 if n > 100 then error("stalled") end end
            local h = 0 debug.sethook(function() h = h + 1 if h > 2000 then debug.sethook() error("looped") end end, "", 1000)
            ns.MapLook.Dashes(put, 6, 1, 0, 0, 0, 1, 5.95, 2.1291666666667, 0, 141.12, -133, 164.64, -120.4)
            debug.sethook() return n end)()""")
        self.assertLessEqual(n, 5, "about four dashes in 27 px")

    def test_the_picture_is_drawn_with_the_maps_pieces(self):
        w = self.boot("settled")
        self.assertGreater(w.eval(f"{self.P}.printN"), 2, "the world map's art is under the marks")
        self.assertTrue(w.eval(f"{self.P}.ground[1].__masks ~= nil"), "printed through the mask")
        cols = w.eval(f"""(function() local t = {{}} for i = 1, {self.P}.picPen.n do
            local r, g, b = {self.P}.picPen.tex[i]:GetVertexColor()
            local c = {self.P}.picPen.tex[i].__color
            if c then r, g, b = c[1], c[2], c[3] end
            t[#t + 1] = ("%.2f,%.2f,%.2f"):format(r, g, b) end
            return table.concat(t, ";") end)()""").split(";")
        self.assertIn("0.10,0.04,0.03", cols, "the trail's casing (Look.Case)")
        self.assertIn("0.25,0.45,1.00", cols, "a flight's royal blue (Look.Air)")
        self.assertIn("0.24,0.15,0.05", cols, "a gold road's bronze edge (Look.Road)")
        self.assertEqual(w.eval(f"{self.P}.picPen.dots[1]:GetTexture()"), w.eval("ns.C.TEX_DOT"), "haze is the map's dot")

    # -- sharing ---------------------------------------------------------------
    def hint(self):
        w, P = self.wow, self.P
        return " ".join(w.eval(f"{P}.share.hint[{i}]:GetText()") for i in range(1, 4)
                        if w.eval(f"{P}.share.hint[{i}] ~= nil and {P}.share.hint[{i}]:IsShown()"))

    def test_the_sharing_hint_is_the_shorter_one(self):
        self.boot("settled")
        self.assertEqual(self.hint(), "Guildmates' kills, deaths and enemy sightings on your map, and yours on theirs. "
                         "Only between guildmates who have it on.")
        self.assertEqual(self.wow.eval(f"#{self.P}.share.hint"), 2, "two lines at 400 px")

    def test_the_switch_turns_sharing_off_and_on_but_never_in_a_preview(self):
        w = self.boot("settled")
        cb = f"{self.P}.share"
        w.run("ns.cfg.share = true ns.Chronicle.Open(false, 'warpath')")
        self.assertEqual(w.eval(f"{cb}.state:GetText()"), "on")
        w.run(f"{cb}:SetChecked(false) {cb}:GetScript('OnClick')({cb})")
        self.assertFalse(w.eval("ns.cfg.share"))
        self.assertEqual(w.eval(f"{cb}.state:GetText()"), "off")
        w.run(f"{cb}:SetChecked(true) {cb}:GetScript('OnClick')({cb})")
        self.assertTrue(w.eval("ns.cfg.share"))
        w.run("ns.Chronicle.Open(true, 'warpath')")
        w.run(f"{cb}:SetChecked(false) {cb}:GetScript('OnClick')({cb})")
        self.assertTrue(w.eval("ns.cfg.share"), "a preview never changes the setting")
        self.assertTrue(w.eval(f"{cb}:GetChecked()"), "and the box goes back")


class RealData(unittest.TestCase):
    """Boot every character found under WARPATH_WTF. Skipped without it.

    SavedVariables are read, never written: each file is checksummed before
    and after."""

    @classmethod
    def setUpClass(cls):
        root = os.environ.get("WARPATH_WTF")
        if not root:
            raise unittest.SkipTest("set WARPATH_WTF to an account folder to test real saved data")
        cls.account = Path(root) / "SavedVariables" / "Warpath.lua"
        cls.chars = sorted(Path(root).glob("*/*/SavedVariables/Warpath.lua"))
        if not cls.chars:
            raise unittest.SkipTest(f"no characters with Warpath data under {root}")

    def test_every_character_boots_and_files_are_untouched(self):
        for path in self.chars:
            name = path.parents[1].name.split("-")[0]
            with self.subTest(character=path.parents[1].name):
                files = [p for p in (path, self.account) if p.exists()]
                before = [hashlib.md5(p.read_bytes()).hexdigest() for p in files]
                wow = Wow(saved=path, saved_global=self.account if self.account.exists() else None,
                          player={"name": name})
                # What login must never lose. (It may ADD: the stub stands the
                # player in Felwood, so a character who's never been there
                # gains that zone.)
                counts = {
                    "zones": "WarpathDB and WarpathDB.maps",
                    "victims": "WarpathDB and WarpathDB.victims",
                    "grudges": "WarpathGlobal and WarpathGlobal.kos",
                    "campaigns": "WarpathDB and WarpathDB.campaigns",
                }
                before_counts = {k: lua_count(wow, v) for k, v in counts.items()}
                wow.login(settle=60)
                self.assertEqual(wow.eval("WarpathDB.v"), 10)
                for k, v in counts.items():
                    self.assertGreaterEqual(lua_count(wow, v), before_counts[k], f"login lost {k}")
                self.assertFalse([l for l in wow.chat if "upgrade hit an error" in l or "rebuild hit an error" in l])
                after = [hashlib.md5(p.read_bytes()).hexdigest() for p in files]
                self.assertEqual(before, after)

    def test_every_campaign_of_every_character_writes(self):
        for path in self.chars:
            with self.subTest(character=path.parents[1].name):
                wow = Wow(saved=path, player={"name": path.parents[1].name.split("-")[0]}).login()
                n = wow.eval("""(function()
                    local list, n = { WarpathDB.campaign }, 0
                    for _, c in ipairs(WarpathDB.campaigns or {}) do list[#list + 1] = c end
                    for _, c in ipairs(list) do
                        for _, foe in ipairs({ "Alliance", "Horde", false }) do
                            local p = ns.Chronicler.Write(c, ns.myName, foe or nil)
                            assert(#p.runs > 0 and p.text ~= "" and #p.title >= 1 and p.date.text)
                            for _, r in ipairs(p.runs) do
                                assert(type(r.text) == "string" and r.text ~= "")
                                if r.name then assert(not r.name:find("-", 1, true), r.name) end
                            end
                        end
                        n = n + 1
                    end
                    return n end)()""")
                self.assertGreaterEqual(n, 1)


    def test_the_layer_split_copies_the_real_settings(self):
        # 3.8.5: the new layers start as the old ones were on this account
        if not self.account.exists():
            self.skipTest("no account-wide saved data")
        path = self.chars[0]
        wow = Wow(saved=path, saved_global=self.account, player={"name": path.parents[1].name.split("-")[0]})
        old = {k: wow.eval(f"WarpathGlobal.cfg and WarpathGlobal.cfg.layers and WarpathGlobal.cfg.layers.{k}")
               for k in ("runs", "shared", "flights", "guildMarks")}
        wow.login(settle=5)
        if old["flights"] is None and old["runs"] is not None:
            self.assertIs(wow.eval("ns.cfg.layers.flights"), old["runs"])
            self.assertIs(wow.eval("ns.cfg.layers.spirits"), old["runs"])
        if old["guildMarks"] is None and old["shared"] is not None:
            self.assertIs(wow.eval("ns.cfg.layers.guildMarks"), old["shared"])
            self.assertIs(wow.eval("ns.cfg.layers.guildSights"), old["shared"])
        self.assertIs(wow.eval("ns.cfg.layers.runs"), old["runs"] if old["runs"] is not None else True)
        self.assertIs(wow.eval("ns.cfg.layers.shared"), old["shared"], "the old key must stay for older builds")


class SpiritHealers(unittest.TestCase):
    """Spirit healers on the map (3.8.4), a layer of their own (3.8.5).

    A built-in list of vanilla graveyards with the faction each serves,
    corrected by what the account's characters see: dying learns where you'll
    release to, by faction. In the stub every map sits on continent 0 at
    4000 yd wide, so Eastern Kingdoms' Tirisfal graveyards (all Horde only in
    the list) fall on the Felwood map: Deathknell at about 0.47, 0.61."""

    DEATHKNELL = (1883 / 4000, 1629 / (4000 * 2 / 3))

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448; __H.worldMaps = true")

    def drawn(self):
        self.wow.eval("ns.Redraw()")
        n = int(self.wow.eval("#ns.Spirits.drawn"))
        out = []
        for i in range(1, n + 1):
            d = f"ns.Spirits.drawn[{i}]"
            out.append((float(self.wow.eval(d + ".x")), float(self.wow.eval(d + ".y")),
                        self.wow.eval(d + ".side"), float(self.wow.eval(d + ".alpha")),
                        self.wow.eval(d + ".k.name")))
        return out

    def at(self, x, y, tol=0.002):
        return [d for d in self.drawn() if abs(d[0] - x) < tol and abs(d[1] - y) < tol]

    def die(self, x, y, faction="Horde"):
        w = self.wow
        w.H.player.faction = faction
        w.run(f"__H.release = {{ {x}, {y} }}; __H.dead = true")
        w.fire("PLAYER_DEAD")
        w.run("__H.release = nil; __H.dead = false")
        w.advance(1)

    def test_listed_graveyards_show_on_a_zone_map_quietly(self):
        hit = self.at(*self.DEATHKNELL)
        self.assertEqual(len(hit), 1)
        self.assertEqual(hit[0][2], "H")
        self.assertIn("Deathknell", hit[0][4])
        self.assertLess(hit[0][3], 1)

    def test_only_the_viewed_zones_own_graveyards(self):
        # The zone lookup puts Deathknell in Ashenvale, a neighbour: left off
        # though it's inside the Felwood map's edges. Everything else Felwood.
        dk = 1883 / 4000
        self.wow.run(f"__H.zoneAt = function(id, x, y) if math.abs(x - {dk}) < 0.001 then return 1440 end return 1448 end")
        self.assertEqual(self.at(*self.DEATHKNELL), [])
        self.assertGreater(len(self.drawn()), 0)

    def test_a_city_inside_the_zone_counts(self):
        self.wow.run("__H.maps[9999] = { name = 'Town', mapType = 3, parentMapID = 1448 }")
        self.wow.run("__H.zoneAt = function() return 9999 end")
        self.assertEqual(len(self.at(*self.DEATHKNELL)), 1)

    def test_brighter_while_dead(self):
        self.wow.run("__H.dead = true")
        self.assertEqual(self.at(*self.DEATHKNELL)[0][3], 1)

    def test_only_with_the_spirit_healers_layer_on(self):
        # their own layer from 3.8.5 (on the corpse runs layer before)
        self.wow.run("ns.cfg.layers.runs = false")
        self.assertGreater(len(self.drawn()), 0, "the corpse runs layer still hides them")
        self.wow.run("ns.cfg.layers.runs = true; ns.cfg.layers.spirits = false")
        self.assertEqual(self.drawn(), [])

    def test_not_on_a_continent(self):
        self.wow.run("__H.mapShown = 1415")
        self.assertEqual(self.drawn(), [])

    def test_dying_learns_the_release_spot_by_faction(self):
        self.die(0.30, 0.20)
        self.assertEqual(int(self.wow.eval("#WarpathGlobal.spirits")), 1)
        self.assertIsNotNone(self.wow.eval("WarpathGlobal.spirits[1].H"))
        hit = self.at(0.30, 0.20)
        self.assertEqual([(d[2], d[4]) for d in hit], [("H", None)])

    def test_both_factions_releasing_there_makes_it_shared(self):
        # the list says Deathknell is Horde only; an Alliance character released there
        self.die(*self.DEATHKNELL, faction="Alliance")
        self.assertEqual(self.at(*self.DEATHKNELL)[0][2], "S")
        self.assertEqual(int(self.wow.eval("#WarpathGlobal.spirits")), 1)

    def test_a_second_death_at_the_same_graveyard_is_one_record(self):
        self.die(0.30, 0.20)
        self.die(0.301, 0.2005, faction="Alliance")
        self.assertEqual(int(self.wow.eval("#WarpathGlobal.spirits")), 1)
        self.assertEqual(self.at(0.30, 0.20)[0][2], "S")

    def test_nothing_is_learned_inside_an_instance(self):
        self.wow.run("ns.S.inInstance = true")
        self.wow.run("__H.release = { 0.3, 0.2 }")
        self.wow.run("pcall(ns.Spirits.OnDead)")
        self.assertEqual(int(self.wow.eval("#(WarpathGlobal.spirits or {})")), 0)

    def test_debug_spirits_runs(self):
        self.die(0.30, 0.20)
        self.wow.run('SlashCmdList.WARPATH("debug spirits")')
        self.assertTrue(any("spirit healers:" in l for l in self.wow.chat))


class Chronicler(unittest.TestCase):
    """The campaign page's words (Chronicler.lua, 3.8.5): the date line, the
    title and the prose as runs, a foe's name its own run.

    Campaigns are built here with invented names. Times are local-clock
    (time{...}), so time-of-day wording holds in any timezone."""

    # Wednesday 25 November 2026, 14:46 local
    START = "time({ year = 2026, month = 11, day = 25, hour = 14, min = 46 })"

    @classmethod
    def setUpClass(cls):
        cls.wow = Wow().login()

    # -- building campaigns ----------------------------------------------------
    @staticmethod
    def kill(n, c, z, dt, lv=60, full=None):
        full = full or (n + "-Testrealm" if n else None)
        if not n:
            return f"{{ z = {z}, t = S + {dt} }}"
        return f'{{ n = "{n}", f = "{full}", c = "{c}", lv = {lv}, z = {z}, t = S + {dt} }}'

    def camp(self, kl=(), dl=(), sightings=0, zones=(1448,), start=None, hours=3, best=0,
             bestBy=None, bestEnded=None, wow=None):
        zl = ", ".join(f"[{z}] = {{ k = 0, d = 0 }}" for z in zones)
        bb = f', bestBy = "{bestBy}"' if bestBy else ""
        be = ", bestEnded = true" if bestEnded else ""
        (wow or self.wow).run(f"""
            local S = {start or self.START}
            __H.camp = {{ start = S, stop = S + {int(hours * 3600)}, played = {int(hours * 3600)}, cur = 0,
                kills = {len(kl)}, deaths = {len(dl)}, best = {best}, sightings = {sightings},
                zones = {{ {zl} }}, kl = {{ {", ".join(kl)} }}, dl = {{ {", ".join(dl)} }}{bb}{be} }}""")
        return "__H.camp"

    def write(self, camp, me='"Grimtusk"', foe='"Alliance"'):
        self.wow.run(f"__H.page = ns.Chronicler.Write({camp}, {me}, {foe})")
        e = self.wow.eval
        n = int(e("#__H.page.runs"))
        runs = []
        for i in range(1, n + 1):
            r = f"__H.page.runs[{i}]"
            runs.append({k: e(f"{r}.{k}") for k in ("text", "name", "key", "class", "level", "slain", "slew")})
        title = [e(f"__H.page.title[{i}]") for i in range(1, int(e("#__H.page.title")) + 1)]
        return {"runs": runs, "title": title, "text": e("__H.page.text"), "scale": e("__H.page.scale"),
                "quiet": e("__H.page.quiet"), "date": e("__H.page.date.text"), "tag": e("__H.page.date.tag")}

    @staticmethod
    def marked(p):
        """The prose with name runs in brackets: 'the rogue [Bluey]'."""
        return "".join(f"[{r['text']}]" if r["name"] else r["text"] for r in p["runs"])

    # A long night: one of each kind of kill sentence, over both continents.
    def night(self, start=None, wow=None):
        k = self.kill
        return self.camp(start=start, sightings=90, hours=9, best=6, wow=wow,
                         zones=(1427, 1443, 1452, 1445, 1414, 1415, 1411, 1412, 1413, 1416, 1420, 1424),
                         kl=[k("Bluey", "ROGUE", 1427, 0, 57), k("Balrog", "MAGE", 1443, 3000, 48),
                             k("Pherk", "DRUID", 1452, 6000), k("Felon", "WARRIOR", 1452, 6011, 55),
                             k("Felon", "WARRIOR", 1452, 6245, 55), k("Xylan", "SHAMAN", 1445, 9000, 49)])

    # -- tests ----------------------------------------------------------------
    def test_the_same_campaign_always_reads_the_same(self):
        a = self.write(self.night())
        self.wow.advance(5000)  # later, the same page
        b = self.write(self.night())
        self.assertEqual(a["runs"], b["runs"])
        other = Wow().login()  # another session
        self.night(wow=other)
        self.assertEqual(other.eval('ns.Chronicler.Write(__H.camp, "Grimtusk", "Alliance").text'), a["text"])

    def test_different_nights_read_differently(self):
        openings = set()
        for day in range(1, 15):
            p = self.write(self.night(start=f"time({{ year = 2026, month = 11, day = {day}, hour = 14, min = 46 }})"))
            openings.add(p["text"].split(" in the afternoon")[0])
        self.assertEqual(openings, {"Grimtusk rode out", "Grimtusk took to the road", "Grimtusk set out"})

    def test_a_foe_is_named_with_class_first_and_by_name_after(self):
        m = self.marked(self.write(self.night()))
        self.assertIn("the rogue [Bluey]", m)
        self.assertIn("the warrior [Felon] fell in the same breath", m)
        self.assertIn("and [Felon] fell again before long", m)
        self.assertEqual(m.count("the warrior [Felon]"), 1)

    def test_a_killer_already_named_is_not_introduced_again(self):
        k = self.kill
        m = self.marked(self.write(self.camp(zones=(1448, 1452), kl=[k("Thorn", "PALADIN", 1448, 0)],
                                             dl=[k("Thorn", "PALADIN", 1448, 60), k(None, None, 1452, 900)])))
        self.assertIn("the paladin [Thorn]", m)
        self.assertIn("until Grimtusk fell to [Thorn].", m)
        self.assertIn("Grimtusk fell to a foe no one saw", m)

    def test_name_runs_carry_what_the_page_colours_and_tooltips(self):
        p = self.write(self.night())
        felon = [r for r in p["runs"] if r["text"] == "Felon"]
        self.assertEqual(len(felon), 2)
        self.assertEqual((felon[0]["name"], felon[0]["key"]), ("Felon Testrealm", "Felon-Testrealm"))
        self.assertEqual((felon[0]["class"], felon[0]["level"], felon[0]["slain"], felon[0]["slew"]),
                         ("WARRIOR", 55, 2, 0))
        # one font string per run: plain prose is never split needlessly
        for a, b in zip(p["runs"], p["runs"][1:]):
            self.assertFalse(a["name"] is None and b["name"] is None)
        # the drop cap is just the first letter of the first run
        self.assertTrue(p["runs"][0]["text"].startswith("Grimtusk "))
        self.assertEqual("".join(r["text"] for r in p["runs"]), p["text"])

    def test_one_zone(self):
        k = self.kill
        p = self.write(self.camp(kl=[k("Ann", "MAGE", 1423, 0), k("Bo", "PRIEST", 1423, 400),
                                     k("Cy", "ROGUE", 1423, 900)]))
        self.assertEqual(p["title"], ["The Skirmish", "in the Eastern Plaguelands"])
        self.assertIn("In the blighted Eastern Plaguelands, the mage [Ann] fell, the priest [Bo] soon after, "
                      "and the rogue [Cy] soon after.", self.marked(p))
        self.assertEqual((p["date"], p["tag"]), ("Wednesday, November 25", "a skirmish"))

    def test_mount_hyjal_is_on(self):
        p = self.write(self.camp(dl=[self.kill("Ann", "MAGE", 2482, 0)]))
        self.assertEqual(p["title"], ["The Clash", "on Mount Hyjal"])

    def test_two_zones(self):
        k = self.kill
        p = self.write(self.camp(kl=[k("Ann", "MAGE", 1437, 0), k("Bo", "PRIEST", 1434, 900)]))
        self.assertEqual(p["title"], ["From the Wetlands", "to Stranglethorn Vale"])
        self.assertIn("in the jungles of Stranglethorn", p["text"])

    def test_two_thirds_in_one_zone_names_that_zone(self):
        k = self.kill
        p = self.write(self.camp(kl=[k("Ann", "MAGE", 1437, 0), k("Bo", "PRIEST", 1434, 900),
                                     k("Cy", "ROGUE", 1434, 1900)]))
        self.assertEqual(p["title"], ["The Skirmish", "in Stranglethorn Vale"])

    def test_many_zones(self):
        k = self.kill
        zs = (1448, 1452, 1443, 1445, 1427, 1431)
        p = self.write(self.camp(zones=zs, kl=[k(f"Foe{chr(65 + i)}", "MAGE", z, i * 600) for i, z in enumerate(zs)]))
        self.assertEqual(p["title"], ["From Felwood", "to Duskwood"])
        self.assertIn("There was more fighting after, two blows in all, before the day was done.", p["text"])
        self.assertNotIn("Duskwood", p["text"].split("There was more")[0])

    def test_a_night_with_no_kills(self):
        p = self.write(self.camp(sightings=4))
        self.assertEqual((p["title"], p["scale"], p["quiet"], p["tag"]), (["A Patrol"], "patrol", True, "a patrol"))
        self.assertTrue(p["text"].endswith("No blood was spilled.") or p["text"].endswith("Not a blade was drawn in anger."))

    def test_a_night_with_deaths_only(self):
        k = self.kill
        p = self.write(self.camp(zones=(1448, 1452), dl=[k("Ann", "MAGE", 1448, 0), k("Bo", "PRIEST", 1448, 500),
                                                         k("Cy", "HUNTER", 1448, 800)]))
        self.assertTrue(p["text"].endswith("No Alliance blood was spilled that day."))
        self.assertRegex(self.marked(p), r"(Felwood went badly: Grimtusk fell three times there|"
                                         r"Beneath the rotting boughs of Felwood, Grimtusk fell three times), "
                                         r"to the mage \[Ann\], the priest \[Bo\] and the hunter \[Cy\]\.")

    def test_a_big_night(self):
        k = self.kill
        kl = [k(f"Foe{i}", "WARRIOR", 1423, i * 30) for i in range(31)]
        p = self.write(self.camp(kl=kl, dl=[k("Foe3", "WARRIOR", 1423, 2000)], sightings=95, best=31,
                                 bestBy="Foe3", bestEnded=True))
        m = self.marked(p)
        self.assertEqual((p["scale"], p["quiet"]), ("war", False))
        self.assertIn("thirty-one fell, the warrior [Foe0] and the warrior [Foe1] among them", m)
        self.assertIn("Some ninety of the Alliance were seen on the roads.", p["text"])
        self.assertTrue("thirty-one of the Alliance had fallen, at a cost of one death." in p["text"]
                        or "Thirty-one slain, once fallen: so the day was reckoned." in p["text"])
        self.assertIn("A streak of thirty-one was ended by [Foe3].", m)
        ender = [r for r in p["runs"] if r["text"] == "Foe3"][-1]
        self.assertEqual((ender["class"], ender["slew"]), ("WARRIOR", 1))

    def test_unnamed_kills_and_no_faction(self):
        k = self.kill
        self.wow.run("__H.faction = ns.faction; ns.faction = ns.C.FACTION.Neutral")
        try:
            p = self.write(self.camp(kl=[k(None, None, 1448, 0), k(None, None, 1448, 900)]), foe="nil")
        finally:
            self.wow.run("ns.faction = __H.faction")
        self.assertIn("Beneath the rotting boughs of Felwood, two fell.", p["text"])
        self.assertIn("Two of the enemy", p["text"])
        # a horde character's foe, when none is given
        self.assertIn("of the Alliance", self.write(self.night(), foe="nil")["text"])

    def test_the_character_is_named_by_first_name(self):
        for me in ('"Grimtusk-Ironhide"', '"Grimtusk Ironhide"'):
            with self.subTest(me=me):
                self.assertTrue(self.write(self.camp(), me=me)["text"].startswith("Grimtusk "))

    def test_display_names(self):
        # every form found in Lethality's saved data, plus edge cases
        for stored, shown in [("Savage-Druiduser", "Savage Druiduser"), ("Plains-Stomper", "Plains Stomper"),
                              ("Plains Stomper", "Plains Stomper"), ("Xaryu Forever-", "Xaryu Forever"),
                              ("Charkoalz Rogue-CAMWOWUS2Realm6PvP", "Charkoalz Rogue"),
                              ("Dizz Zz-CAMWOWUS2Realm6PvP", "Dizz Zz"), ("Bainekx-Execute", "Bainekx Execute"),
                              ("Wreckless", "Wreckless"), ("Bluey-", "Bluey"), ("Tiglie-Wiglie", "Tiglie Wiglie")]:
            with self.subTest(stored=stored):
                self.assertEqual(self.wow.eval(f"ns.DisplayName({lua_str(stored)})"), shown)
        self.assertIsNone(self.wow.eval("ns.DisplayName(nil)"))

    def test_number_words(self):
        for n, w in [(0, "no"), (1, "one"), (13, "thirteen"), (20, "twenty"), (21, "twenty-one"), (40, "forty"),
                     (90, "ninety"), (99, "ninety-nine"), (100, "one hundred"), (105, "one hundred and five"),
                     (342, "three hundred and forty-two"), (1000, "1000")]:
            with self.subTest(n=n):
                self.assertEqual(self.wow.eval(f"ns.NumberWord({n})"), w)
        for n, w in [(1, "first"), (2, "second"), (3, "third"), (12, "twelfth"), (20, "twentieth"),
                     (21, "twenty-first"), (27, "twenty-seventh"), (30, "thirtieth"), (31, "thirty-first")]:
            with self.subTest(nth=n):
                self.assertEqual(self.wow.eval(f"ns.OrdinalWord({n})"), w)
        for n, w in [(3, "three"), (20, "twenty"), (25, "a score and more"), (90, "some ninety"),
                     (97, "some ninety"), (140, "over a hundred"), (261, "hundreds")]:
            with self.subTest(crowd=n):
                self.assertEqual(self.wow.eval(f"ns.Chronicler.Many({n})"), w)
        self.assertEqual(self.wow.eval("ns.DateWords(time({ year = 2026, month = 11, day = 27, hour = 12 }))"),
                         "the twenty-seventh of November")
        self.assertEqual(self.wow.eval("ns.DateWords(time({ year = 2026, month = 3, day = 1, hour = 12 }))"),
                         "the first of March")


class LayerSplit(unittest.TestCase):
    """3.8.5: corpse runs, flights and spirit healers are three layers (one
    before), and guildmates' marks two, under pins and sightings (one,
    "shared", before). Each layer hides only its own marks."""

    def setUp(self):
        from render import COLLECT
        self.COLLECT = COLLECT
        wow = self.wow = Wow().login()
        wow.run("__H.taxi = false; UnitOnTaxi = function() return __H.taxi end")
        wow.run("ns.cfg.share = true; ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448; __H.worldMaps = true")
        # a leg flown on two days, so it's drawn
        Flights.fly(self, Flights.PATH)
        Flights.next_day(self)
        Flights.fly(self, list(reversed(Flights.PATH)), dy=0.02)
        wow.run("""
            local z, now = ns.db.maps[1448], time()
            z.runs[#z.runs + 1] = { 0.30, 0.30, 0.60, 0.30, k = "g", t = now - 60, e = now - 10, ts = { 0, 50 } }
            z.marks[#z.marks + 1] = { 0.20, 0.20, now - 60, "kill" }
            ns.recentSight[#ns.recentSight + 1] = { mapID = 1448, x = 0.70, y = 0.70, t = now - 30 }
            ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')
            ns.OnComm('WARPATH', '1|S|1448|0.80|0.20', 'GUILD', 'Bob Smith')""")
        wow.advance(3)

    def drawn(self):
        """What's on the map, by kind: run, leg, spirit, kill, sight,
        gkill (a guildmate's pin) and gsight (a guildmate's sighting)."""
        self.wow.eval("ns.Redraw()")
        got = set()
        for p in self.wow.run(self.COLLECT).split("\n"):
            f = p.split("\t")
            if f[0] != "L" or float(f[5]) <= 0.02:
                continue
            rgb = tuple(round(float(v), 2) for v in f[2:5])
            if rgb in ((0.55, 0.9, 1.0), (0.35, 0.75, 1.0)):
                got.add("run")
            elif rgb in ((0.25, 0.45, 1.0), (0.08, 0.05, 0.1)):
                got.add("leg")
        if int(self.wow.eval("#ns.Spirits.drawn")) > 0:
            got.add("spirit")
        kinds = self.wow.eval("""(function() local t = {}
            for _, f in ipairs(WarpathOverlay.__children) do
                if f.kind and f.tex and f:IsShown() then
                    local k = f.kind
                    if k == "sight" and f.d.from then k = "gsight" end
                    t[#t + 1] = k
                end
            end return table.concat(t, ",") end)()""")
        names = {"skill": "gkill", "sdeath": "gkill"}
        for k in filter(None, kinds.split(",")):
            got.add(names.get(k, k))
        return got

    ALL = {"run", "leg", "spirit", "kill", "sight", "gkill", "gsight"}

    def test_everything_draws_with_every_layer_on(self):
        self.assertEqual(self.drawn(), self.ALL)

    def test_each_layer_hides_only_its_own_marks(self):
        for key, gone in (("runs", {"run"}), ("flights", {"leg"}), ("spirits", {"spirit"}),
                          ("guildMarks", {"gkill"}), ("guildSights", {"gsight"}),
                          ("marks", {"kill", "gkill"}), ("sightings", {"sight", "gsight"})):
            with self.subTest(layer=key):
                self.wow.run(f"ns.cfg.layers.{key} = false")
                self.assertEqual(self.drawn(), self.ALL - gone)
                self.wow.run(f"ns.cfg.layers.{key} = true")

    def test_the_map_buttons_menu_lists_every_layer(self):
        keys = self.wow.eval("""(function() local t = {}
            for _, it in ipairs(ns.LayerItems()) do t[#t + 1] = it.key or "" end
            return table.concat(t, ",") end)()""").split(",")
        for key in ("runs", "flights", "spirits", "guildMarks", "guildSights", "guildHaze"):
            self.assertIn(key, keys)
        self.assertNotIn("shared", keys)
        self.wow.run("""for _, it in ipairs(ns.LayerItems()) do
            if it.key == "flights" then it.func() end end""")
        self.assertFalse(self.wow.eval("ns.cfg.layers.flights"))
        self.assertTrue(self.wow.eval("ns.cfg.layers.runs"))

    def test_the_layer_command_knows_the_new_layers(self):
        self.wow.run('SlashCmdList.WARPATH("layer spirits off")')
        self.assertFalse(self.wow.eval("ns.cfg.layers.spirits"))
        self.assertTrue(self.wow.eval("ns.cfg.layers.runs"))
        self.wow.run('SlashCmdList.WARPATH("layer guild off")')
        self.assertFalse(self.wow.eval("ns.cfg.layers.guildMarks"))
        self.assertFalse(self.wow.eval("ns.cfg.layers.guildSights"))

    # --- the upgrade ------------------------------------------------------

    def booted(self, layers):
        wow = Wow()
        wow.run(f'WarpathGlobal = {{ installed = "3.8.4", seenVersion = "3.8.4", cfg = {{ mapReset = "3.8", layers = {layers} }} }}')
        return wow.login()

    def test_the_upgrade_copies_the_old_layers(self):
        wow = self.booted("{ runs = false, shared = false, marks = true, sightings = true }")
        for key in ("runs", "flights", "spirits", "guildMarks", "guildSights", "shared"):
            with self.subTest(layer=key):
                self.assertIs(wow.eval(f"ns.cfg.layers.{key}"), False)
        self.assertTrue(wow.eval("ns.cfg.layers.marks"))
        wow = self.booted("{ runs = true, shared = true }")
        for key in ("flights", "spirits", "guildMarks", "guildSights"):
            self.assertIs(wow.eval(f"ns.cfg.layers.{key}"), True)

    def test_the_upgrade_runs_once(self):
        wow = self.booted("{ runs = false, shared = false }")
        wow.run("ns.cfg.layers.flights = true; ns.cfg.layers.guildSights = true")
        wow.login()
        self.assertTrue(wow.eval("ns.cfg.layers.flights"))
        self.assertTrue(wow.eval("ns.cfg.layers.guildSights"))
        self.assertFalse(wow.eval("ns.cfg.layers.spirits"))

    def test_a_new_install_has_every_layer_on(self):
        wow = Wow().login()
        for key in ("runs", "flights", "spirits", "guildMarks", "guildSights"):
            self.assertIs(wow.eval(f"ns.cfg.layers.{key}"), True)


class SharingOff(unittest.TestCase):
    """3.8.5 (Joe: "Hide, keep the data"): with guild sharing off, no
    guildmates' pins, sightings or haze are drawn and their deaths don't count
    toward dangerous ground. Their saved data is kept and comes back."""

    def setUp(self):
        wow = self.wow = Wow().login()
        wow.run("ns.cfg.share = true; ns.cfg.shown = true; WorldMapFrame.__shown = true; __H.mapShown = 1448")
        wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        wow.run("ns.OnComm('WARPATH', '1|D|1448|0.60|0.60', 'GUILD', 'Bob Smith')")
        wow.advance(3)

    def saved(self):
        return self.wow.eval("""(function() local z, n = ns.db.maps[1448], 0
            for _, cells in pairs(z.guildBattle or {}) do for _ in pairs(cells) do n = n + 1 end end
            for _, cells in pairs(z.guildDeaths or {}) do for _ in pairs(cells) do n = n + 1 end end
            return #(z.gmarks or {}) .. "/" .. n end)()""")

    def guild_pins(self):
        self.wow.eval("ns.Redraw()")
        return int(self.wow.eval("""(function() local n = 0
            for _, f in ipairs(WarpathOverlay.__children) do
                if (f.kind == "skill" or f.kind == "sdeath") and f:IsShown() then n = n + 1 end
            end return n end)()"""))

    def haze(self):
        return lua_count(self.wow, "ns.BattleField(ns.db.maps[1448])")

    def guild_deaths(self):
        return lua_count(self.wow, "select(2, ns.DeathField(ns.db.maps[1448]))")

    def test_off_hides_guildmates_marks_and_keeps_them(self):
        before = self.saved()
        self.assertEqual(self.guild_pins(), 2)
        self.assertGreater(self.haze(), 0)
        self.assertGreater(self.guild_deaths(), 0)
        self.wow.run('SlashCmdList.WARPATH("share off")')
        self.assertEqual(self.guild_pins(), 0)
        self.assertEqual(self.haze(), 0, "guildmates' haze still drawn")
        self.assertEqual(self.guild_deaths(), 0, "guildmates' deaths still count toward dangerous ground")
        self.assertEqual(self.saved(), before, "sharing off changed the saved guild data")
        self.wow.run('SlashCmdList.WARPATH("share on")')
        self.assertEqual(self.guild_pins(), 2)
        self.assertGreater(self.haze(), 0)
        self.assertGreater(self.guild_deaths(), 0)

    def test_off_hides_guildmates_sightings(self):
        self.wow.run("ns.cfg.share = false")
        self.wow.run("table.insert(ns.shared, { kind = 'S', mapID = 1448, x = 0.8, y = 0.2, t = time(), from = 'Bob', expire = time() + 120 })")
        self.wow.eval("ns.Redraw()")
        self.assertEqual(int(self.wow.eval("""(function() local n = 0
            for _, f in ipairs(WarpathOverlay.__children) do
                if f.kind == "sight" and f:IsShown() then n = n + 1 end
            end return n end)()""")), 0)

    def test_ground_warnings_leave_out_guild_deaths_while_off(self):
        def chat(share):
            wow = Wow().login()
            wow.advance(10)
            wow.run(f"""
                ns.cfg.share = {str(share).lower()}
                local mapID, x, y = ns.PlayerPos()
                local z = ns.db.maps[mapID]
                for i = 1, 3 do
                    z.marks[#z.marks + 1] = {{ x, y, time() - i * 600, "death", pvp = true }}
                    ns.AddBattle(mapID, x, y, ns.C.BATTLE_W.death)
                    ns.AddDeathHeat(mapID, x, y, 1)
                    ns.AddHeat(ns.GuildLayer(mapID, "guildDeaths", "Bob Smith"), ns.Cell(x, y, ns.C.SW, ns.C.SH), 1)
                end
                ns.Ground.Forget()
                ns.Ground.Check()""")
            self.last = wow
            return " ".join(wow.chat)
        self.assertIn("Guildmates have died here", chat(True))
        # turned off with a warning just given: Ground's cached fields go too
        wow = self.last
        wow.run('SlashCmdList.WARPATH("share off")')
        n = len(wow.chat)
        wow.run("if WarpathBigText then WarpathBigText:Hide() end ns.Ground.Reset() ns.Ground.Check()")
        again = " ".join(wow.chat[n:])
        self.assertTrue(any(w in again for w in ("Dangerous", "Careful")), again)
        self.assertNotIn("Guildmates have died here", again, "sharing off kept the cached guild deaths")
        said = chat(False)
        self.assertTrue(any(w in said for w in ("Dangerous", "Careful")), said)
        self.assertNotIn("Guildmates have died here", said)


class SettingsGreying(unittest.TestCase):
    """3.8.5: each "kept for" row greys with its layer; the guildmates' rows
    grey with guild sharing (and with their own layer)."""

    def opened(self):
        wow = Wow().login()
        wow.run("ns.cfg.share = true")
        wow.run('SlashCmdList.WARPATH("setup")')
        wow.run('ns.ShowSetup(nil, "map")')
        return wow

    def row_on(self, wow, path):
        # every refresh function bound to that path, called through the live greying
        return wow.eval(f"""(function()
            ns.Settings.Refresh()
            return ns.Settings.Enabled({lua_str(path)}) end)()""")

    def test_kept_for_rows_grey_with_their_layer(self):
        wow = self.opened()
        for layer, path in (("recent", "trailMin"), ("runs", "runHours"), ("flights", "flightHours")):
            with self.subTest(layer=layer):
                self.assertTrue(self.row_on(wow, path))
                wow.run(f"ns.cfg.layers.{layer} = false")
                self.assertFalse(self.row_on(wow, path))
                wow.run(f"ns.cfg.layers.{layer} = true")

    def test_guildmates_rows_grey_with_sharing(self):
        wow = self.opened()
        for path in ("guildHaze", "layers.guildMarks", "layers.guildSights"):
            with self.subTest(row=path):
                self.assertTrue(self.row_on(wow, path))
                wow.run("ns.cfg.share = false")
                self.assertFalse(self.row_on(wow, path))
                wow.run("ns.cfg.share = true")

    def test_greyed_rows_are_disabled_on_the_page(self):
        wow = self.opened()
        wow.run("ns.cfg.share = false; ns.Settings.Refresh()")
        self.assertFalse(wow.eval(f"""(function() {SettingsTab.FIND}
            return Find("with guildmates' sightings"):IsEnabled() end)()"""))
        wow.run("ns.cfg.share = true; ns.Settings.Refresh()")
        self.assertTrue(wow.eval(f"""(function() {SettingsTab.FIND}
            return Find("with guildmates' sightings"):IsEnabled() end)()"""))


class KillCards(unittest.TestCase):
    """3.8.5: the kill captions can be drawn into any frame at any scale, for
    the Settings tab's preview, by the same code that draws them on
    screenshots."""

    KILL = "{ name = 'Thrall', class = 'SHAMAN', zone = 'Felwood', times = 3, streak = 2, when = 1700000000 }"

    def shape(self, wow, frame):
        # every region the card is made of, in order: kind, font, points, text, colour
        return wow.eval(f"""(function()
            local f, t = {frame}, {{}}
            local function pt(r)
                local out = {{}}
                for _, p in ipairs(r.__points or {{}}) do
                    local bits = {{}}
                    for i, v in ipairs(p) do
                        if type(v) == "table" then
                            v = v == f and "card" or ((f.tag == v and "tag") or (f.name == v and "name")
                                or (f.crest == v and "crest") or (f.text == v and "text") or "other")
                        end
                        bits[i] = tostring(v)
                    end
                    out[#out + 1] = table.concat(bits, " ")
                end
                return table.concat(out, ";")
            end
            for _, r in ipairs(f.__children or {{}}) do
                local c = r.__color or r.__textColor or {{}}
                t[#t + 1] = table.concat({{ r.__kind, tostring(r.__template or ""), pt(r), tostring(r.__text or ""),
                    tostring(c[1]), tostring(c[2]), tostring(c[3]) }}, "|")
            end
            t[#t + 1] = tostring(f:GetWidth()) .. "x" .. tostring(f:GetHeight())
            return table.concat(t, "\\n") end)()""")

    def test_a_preview_is_built_by_the_screenshots_code(self):
        for kind, name in (("Text", "WarpathKillCardText"), ("Strip", "WarpathKillCardStrip")):
            with self.subTest(card=kind):
                wow = Wow().login()
                wow.run(f"__shot = ns.KillCard.{kind}({self.KILL})")
                wow.run(f"__host = CreateFrame('Frame', nil, UIParent) __prev = ns.KillCard.{kind}({self.KILL}, __host, 0.6)")
                self.assertEqual(wow.eval(f"__shot == {name}"), True, "the screenshot's frame changed")
                self.assertEqual(wow.eval("__prev:GetParent() == __host"), True)
                self.assertEqual(wow.eval("__prev ~= __shot"), True, "the preview took the screenshot's frame")
                self.assertAlmostEqual(float(wow.eval("__prev:GetScale()")), 0.6)
                self.assertEqual(self.shape(wow, "__prev"), self.shape(wow, "__shot"))
                self.assertIn("Thrall", self.shape(wow, "__prev"))

    def test_the_preview_is_reused_and_the_screenshot_path_unchanged(self):
        wow = Wow().login()
        wow.run(f"__host = CreateFrame('Frame', nil, UIParent) __a = ns.KillCard.Text({self.KILL}, __host, 1)")
        wow.run(f"__b = ns.KillCard.Text({self.KILL}, __host, 0.5)")
        self.assertTrue(wow.eval("__a == __b"))
        self.assertIsNone(wow.eval("WarpathKillCardText"), "a preview built the screenshot's frame")
        wow.run('SlashCmdList.WARPATH("shot test")')
        wow.advance(2)
        self.assertIsNotNone(wow.eval("WarpathKillCardText"))
        self.assertEqual(wow.eval("WarpathKillCardText:GetParent() == UIParent"), True)



def ledger_snapshot():
    """Joe's frozen saved data for the Ledger's design (gitignored, so only on
    his machine): WARPATH_LEDGER_SNAPSHOT, else tools/out/design/ledger/snapshot
    in this checkout or in the main checkout a worktree belongs to."""
    import subprocess
    env = os.environ.get("WARPATH_LEDGER_SNAPSHOT")
    roots = [Path(env)] if env else []
    here = Path(__file__).resolve().parents[2]
    roots.append(here / "tools/out/design/ledger/snapshot")
    common = subprocess.run(["git", "-C", str(here), "rev-parse", "--git-common-dir"],
                            capture_output=True, text=True).stdout.strip()
    if common:
        roots.append((here / common).resolve().parent / "tools/out/design/ledger/snapshot")
    for r in roots:
        if (r / "SavedVariables" / "Warpath.lua").exists():
            return r


class Ledger(unittest.TestCase):
    """The Ledger tab's data (3.8.5): the new recordings, Ledger.Stats and the
    account view. Ledger.Stats on Joe's real data is LedgerSnapshot."""

    def setUp(self):
        self.wow = Wow().login()

    # -- driving ---------------------------------------------------------------
    def kill(self, victim="Thrall", cls="SHAMAN"):
        w = self.wow
        w.run(f"""ns.Foes.Pick = function() return {lua_str(victim + '-Realm')}, {lua_str(victim)}, {lua_str(cls)}, "target" end""")
        w.H.combat = True
        w.fire("PLAYER_REGEN_DISABLED")
        w.H.hk = (w.H.hk or 0) + 1
        w.fire("PLAYER_PVP_KILLS_CHANGED")
        w.advance(1)
        w.H.combat = False
        w.fire("PLAYER_REGEN_ENABLED")
        w.advance(3)

    def die(self):
        self.wow.run("__H.dead = true")
        self.wow.fire("PLAYER_DEAD")
        self.wow.advance(0.5)

    def release(self):
        self.wow.run("__H.dead = false; __H.ghost = true")
        self.wow.fire("PLAYER_ALIVE")
        self.wow.advance(1.5)

    def walk(self, x, y, steps=10):
        w = self.wow
        x0, y0 = float(w.eval("__H.player.x")), float(w.eval("__H.player.y"))
        for i in range(1, steps + 1):
            w.run(f"__H.player.x = {x0 + (x - x0) * i / steps}; __H.player.y = {y0 + (y - y0) * i / steps}")
            w.advance(0.5)

    def unghost(self):
        self.wow.run("__H.ghost = false")
        self.wow.fire("PLAYER_UNGHOST")
        self.wow.advance(1)

    def last_mark(self, field):
        return self.wow.eval(
            f"(function() local ms = WarpathDB.maps[1448].marks local m = ms[#ms] return m and m.{field} end)()")

    # -- recordings ------------------------------------------------------------
    def test_a_flight_is_counted_when_it_starts(self):
        w = self.wow
        w.run("__H.taxi = false; UnitOnTaxi = function() return __H.taxi end")
        w.advance(1)
        self.assertIsNone(w.eval("WarpathDB.flights"))  # "none yet" until the first
        w.run("__H.taxi = true")
        w.advance(30)
        self.assertEqual(w.eval("WarpathDB.flights"), 1)
        w.run("__H.taxi = false")
        w.advance(2)
        w.run("__H.taxi = true")
        w.advance(2)
        self.assertEqual(w.eval("WarpathDB.flights"), 2)

    def test_a_reload_mid_flight_is_not_a_second_flight(self):
        w = Wow()
        w.run("UnitOnTaxi = function() return true end")
        w.login()
        w.advance(5)
        self.assertIsNone(w.eval("WarpathDB.flights"))

    def test_a_corpse_run_ends_at_the_body(self):
        w = self.wow
        self.die()
        self.release()
        w.run("__H.player.x = 0.70")  # the graveyard, 800 yd east
        w.advance(1)
        self.walk(0.502, 0.5)
        self.unghost()
        self.assertEqual(w.eval("WarpathDB.runs"), 1)
        self.assertEqual(w.eval("WarpathDB.maps[1448].runs_n"), 1)
        self.assertIsNone(w.eval("WarpathDB.spirit"))
        ghost = float(w.eval("WarpathDB.ghostYards"))
        self.assertAlmostEqual(ghost, 0.198 * 4000, delta=40)  # the walk back, as a ghost
        self.assertEqual(w.eval("ns.Ledger.Stats(WarpathDB, WarpathGlobal).lands[1448].runs"), 1)

    def test_resurrecting_at_a_spirit_healer_is_not_a_corpse_run(self):
        w = self.wow
        self.die()
        self.release()
        w.run("__H.player.x = 0.70")
        w.advance(1)
        self.unghost()
        self.assertEqual(w.eval("WarpathDB.spirit"), 1)
        self.assertIsNone(w.eval("WarpathDB.runs"))

    def test_coming_back_is_counted_once_and_only_after_a_recorded_death(self):
        w = self.wow
        self.unghost()  # no death recorded this session
        self.assertIsNone(w.eval("WarpathDB.runs"))
        self.assertIsNone(w.eval("WarpathDB.spirit"))
        self.die()
        self.release()
        self.unghost()
        self.unghost()
        self.assertEqual(w.eval("WarpathDB.runs"), 1)

    def test_kills_and_deaths_keep_your_level(self):
        self.wow.run("__H.player.level = 42")
        self.kill()
        self.assertEqual(self.last_mark("my"), 42)
        self.die()
        self.assertEqual(self.last_mark("my"), 42)

    def test_a_kill_keeps_your_health_and_the_odds(self):
        w = self.wow
        w.run("UnitHealth = function() return 37 end")
        w.run("ns.Foes.near['A-R'] = GetTime(); ns.Foes.near['B-R'] = GetTime(); ns.Foes.near['C-R'] = GetTime() - 30")
        self.kill()
        self.assertEqual(self.last_mark("hp"), 37)
        self.assertEqual(self.last_mark("odds[1]"), 2)
        self.assertEqual(self.last_mark("odds[2]"), 1)

    def test_a_kill_with_no_enemy_read_keeps_no_odds(self):
        self.wow.run("for k in pairs(ns.Foes.near) do ns.Foes.near[k] = nil end")
        self.kill()
        self.assertIsNone(self.last_mark("odds"))
        self.assertEqual(self.last_mark("hp"), 100)

    def cause(self):
        return (self.last_mark("cause"), self.last_mark("how"), self.last_mark("ct"))

    def creature(self, name="Deadwood Ursa", kind="Beast"):
        w = self.wow
        w.run(f"__H.units = {{ target = {{ name = {lua_str(name)} }} }}")
        w.run(f"UnitCanAttack = function(a, u) return u == 'target' end; UnitCreatureType = function() return {lua_str(kind)} end")
        w.fire("PLAYER_TARGET_CHANGED")

    def test_a_fall_is_a_cause(self):
        self.wow.run("IsFalling = function() return true end")
        self.die()
        self.assertEqual(self.cause(), (None, "fall", None))

    def test_landing_just_before_dying_is_still_a_fall(self):
        w = self.wow
        w.run("IsFalling = function() return true end")
        w.advance(0.5)
        w.run("IsFalling = function() return false end")
        w.advance(0.6)
        self.die()
        self.assertEqual(self.last_mark("how"), "fall")

    def test_a_fall_long_before_is_not_a_cause(self):
        w = self.wow
        w.run("IsFalling = function() return true end")
        w.advance(0.5)
        w.run("IsFalling = function() return false end")
        w.advance(2)
        self.die()
        self.assertIsNone(self.last_mark("how"))

    def test_drowning_is_a_cause(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1)
        w.advance(61)
        self.die()
        self.assertEqual(self.cause(), (None, "drown", None))

    def test_fatigue_is_a_cause(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "EXHAUSTION", 30000, 60000, -1)
        w.advance(31)
        self.die()
        self.assertEqual(self.last_mark("how"), "fatigue")

    def test_a_creature_is_a_cause(self):
        self.creature()
        self.wow.advance(4)
        self.die()
        self.assertEqual(self.cause(), ("Deadwood Ursa", "beast", "Beast"))

    def test_a_creature_that_has_you_targeted_is_a_cause(self):
        w = self.wow
        w.run("""__H.units = { nameplate1 = { name = 'Jaedenar Hound' } }
                 C_NamePlate.GetNamePlates = function() return { { namePlateUnitToken = 'nameplate1' } } end
                 UnitCanAttack = function(a, u) return u == 'nameplate1' end
                 UnitIsUnit = function(a, b) return a == b or (a == 'nameplate1target' and b == 'player') end""")
        self.die()
        self.assertEqual(self.last_mark("cause"), "Jaedenar Hound")

    def test_a_creature_underwater_beats_the_breath_timer(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1)
        w.advance(10)
        self.creature("Murloc Hunter", "Humanoid")
        self.die()
        self.assertEqual(self.cause(), ("Murloc Hunter", "beast", "Humanoid"))

    def test_running_out_of_breath_beats_a_creature(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1)
        w.advance(55)
        self.creature("Murloc Hunter", "Humanoid")
        w.advance(6)
        self.die()
        self.assertEqual(self.cause(), (None, "drown", None))

    def test_a_breath_timer_still_running_counts_when_nothing_else_does(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1)
        w.advance(10)
        self.die()
        self.assertEqual(self.last_mark("how"), "drown")

    def test_a_surfaced_timer_and_an_old_creature_explain_nothing(self):
        w = self.wow
        w.fire("MIRROR_TIMER_START", "BREATH", 60000, 60000, -1)
        w.advance(5)
        w.fire("MIRROR_TIMER_STOP", "BREATH")
        self.creature()
        w.run("__H.units = nil")
        w.advance(11)
        self.die()
        self.assertEqual(self.cause(), (None, None, None))

    def test_a_pvp_death_gets_no_cause(self):
        w = self.wow
        w.run("IsFalling = function() return true end; ns.Foes.PlayerNearby = function() return true end")
        self.die()
        self.assertTrue(self.last_mark("pvp"))
        self.assertIsNone(self.last_mark("how"))

    # -- the kill message ------------------------------------------------------
    def kill_sent(self):
        self.wow.run("ns.cfg.share = true")
        self.kill(victim="Thrall", cls="SHAMAN")
        self.wow.advance(2)
        return [m["msg"] for m in self.wow.sent if "|K|" in m["msg"]][-1]

    def test_the_kill_message_carries_the_victims_class_last(self):
        msg = self.kill_sent()
        parts = msg.split("|")
        self.assertEqual(parts[-1], "SHAMAN", msg)
        self.assertEqual(parts[13], "Thrall", msg)  # the victim is still the 14th field

    def receive(self, text, sender="Bob Smith"):
        self.wow.run("ns.cfg.share = true")
        self.wow.run(f"ns.OnComm('WARPATH', {lua_str(text)}, 'GUILD', {lua_str(sender)})")
        self.wow.advance(2.1)
        return self.wow.eval("(function() local g = WarpathDB.maps[1448].gmarks return g[#g] end)()")

    def test_a_guild_kill_pin_keeps_the_victims_name_and_class(self):
        g = self.receive("1|K|1448|0.40|0.60|k|1|1||||||Thrall|SHAMAN")
        self.assertEqual((g["vn"], g["vc"]), ("Thrall", "SHAMAN"))

    def test_an_old_kill_message_still_works(self):
        chat = len(self.wow.chat)
        g = self.receive("1|K|1448|0.40|0.60|k|1|1||||||Thrall")  # 3.7 to 3.8.4
        self.assertEqual((g["vn"], g["vc"]), ("Thrall", None))
        self.assertTrue(any("Bob Smith" in l for l in self.wow.chat[chat:]))
        g = self.receive("1|K|1448|0.30|0.60", sender="Ann Lee")  # before 3.7
        self.assertEqual((g["vn"], g["vc"]), (None, None))
        g = self.receive("1|K|1448|0.20|0.60|k|1|1||||||Garrosh|SHAM", sender="Cid Roe")  # cut short
        self.assertEqual((g["vn"], g["vc"]), ("Garrosh", None))

    def test_the_last_release_reads_the_new_kill_message(self):
        import subprocess
        from render import addon_from_ref
        repo = Path(__file__).resolve().parents[2]
        if subprocess.run(["git", "-C", str(repo), "rev-parse", "-q", "--verify", "refs/tags/3.8.4"],
                          capture_output=True).returncode != 0:
            self.skipTest("no 3.8.4 tag in this checkout")
        old = Wow(addon_dir=addon_from_ref("3.8.4")).login()
        old.run("ns.cfg.share = true")
        msg = self.kill_sent()
        # the same kill without the class, as 3.8.4 itself sends it, from
        # another guildmate on another map: 3.8.4 must read both alike
        bare = msg.rsplit("|", 1)[0].replace("|1448|", "|1440|", 1)
        old.run(f"ns.OnComm('WARPATH', {lua_str(msg)}, 'GUILD', 'Bob Smith')")
        old.run(f"ns.OnComm('WARPATH', {lua_str(bare)}, 'GUILD', 'Ann Lee')")
        old.advance(2.1)
        self.assertEqual(old.eval("#WarpathDB.maps[1448].gmarks"), 1)
        new_line = [l for l in old.chat if "Bob Smith" in l]
        bare_line = [l for l in old.chat if "Ann Lee" in l]
        self.assertEqual(len(new_line), 1, old.chat)
        self.assertEqual(new_line[0].replace("Bob Smith", "X").replace("Felwood", "Z"),
                         bare_line[0].replace("Ann Lee", "X").replace("Ashenvale", "Z"))
        old.run("ns.DiagStatus()")
        self.assertIn(" 0 errors", " ".join(old.chat))
        self.assertIn(" 0 malformed", " ".join(old.chat))

    # -- Stats -------------------------------------------------------------------
    def test_a_new_character_gets_every_figure(self):
        w = self.wow
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        self.assertEqual([w.eval(f"__L.tally.{k}") for k in
                          ("kills", "deaths", "best", "foes", "wilds", "flights", "runs", "spirit")], [0] * 8)
        self.assertIsNone(w.eval("__L.tally.kd"))
        self.assertIsNone(w.eval("next(__L.records)"))
        self.assertEqual(w.eval("__L.multi[2] + __L.multi[5] + __L.streaks[3] + __L.streaks[20]"), 0)
        self.assertIsNone(w.eval("__L.first"))
        self.assertEqual(w.eval("#__L.foes.slain + #__L.foes.struck + #__L.wilds.causes"), 0)
        self.assertEqual(w.eval("#__L.guild.mates"), 1)  # you
        self.assertTrue(w.eval("__L.guild.mates[1].me"))
        self.assertIsNotNone(w.eval("__L.lands[1448]"))  # walked, no fight

    def test_stats_count_a_chain_once_and_streaks_at_every_title(self):
        w = self.wow
        for i in range(6):  # one chain of six: one bloodbath; streak titles at 3 and 5
            self.kill(victim=f"Foe{i}")
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        self.assertEqual([w.eval(f"__L.multi[{n}]") for n in (2, 3, 4, 5)], [0, 0, 0, 1])
        self.assertEqual([w.eval(f"__L.streaks[{n}]") for n in (3, 5, 10)], [1, 1, 0])
        self.assertEqual(w.eval("__L.records.hour.n"), 6)
        self.assertEqual(w.eval("__L.records.longest.n"), 6)

    def test_legend_of_the_warpath_counts_at_every_ten_from_twenty(self):
        w = self.wow
        w.run("""local ms = WarpathDB.maps[1448].marks
                 for _, n in ipairs({ 3, 5, 10, 15, 20, 25, 30, 40 }) do ms[#ms + 1] = { 0.5, 0.5, time(), 'kill', streak = n } end
                 __L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)""")
        self.assertEqual([w.eval(f"__L.streaks[{n}]") for n in (3, 5, 10, 15, 20)], [1, 1, 1, 1, 3])

    def test_a_chain_that_ends_on_a_tier_counts_there(self):
        w = self.wow
        self.kill(victim="A")
        self.kill(victim="B")
        self.kill(victim="C")
        w.advance(200)
        self.kill(victim="D")
        self.kill(victim="E")
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        self.assertEqual([w.eval(f"__L.multi[{n}]") for n in (2, 3, 4, 5)], [1, 1, 0, 0])

    def test_records_from_the_new_fields(self):
        w = self.wow
        w.run("__H.player.level = 40; UnitHealth = function() return 12 end")
        w.run("ns.Foes.near['A-R'] = GetTime(); ns.Foes.near['B-R'] = GetTime(); ns.Foes.near['C-R'] = GetTime()")
        w.run("ns.Foes.info['Thrall-Realm'] = { lv = 44 }")
        self.kill()
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        self.assertEqual(w.eval("__L.records.closest.hp"), 12)
        self.assertEqual((w.eval("__L.records.odds.foes"), w.eval("__L.records.odds.friends")), (3, 1))
        self.assertEqual(w.eval("__L.records.gap.gap"), 4)

    def test_the_wilds_count_causes(self):
        w = self.wow
        self.creature()
        self.die()
        w.run("__H.dead = false; ns.Foes.dead = false; __H.units = nil")
        w.advance(12)
        self.die()
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        self.assertEqual(w.eval("__L.wilds.total"), 2)
        self.assertEqual((w.eval("__L.wilds.causes[1].cause"), w.eval("__L.wilds.causes[1].how"),
                          w.eval("__L.wilds.causes[1].kind"), w.eval("__L.wilds.causes[1].n")),
                         ("Deadwood Ursa", "beast", "Beast", 1))
        self.assertEqual(w.eval("__L.wilds.unrecorded"), 1)

    def test_the_guild_war_names_victims_and_joins_the_roster(self):
        self.receive("1|K|1448|0.40|0.60|k|1|1||||||Thrall|SHAMAN")
        self.receive("1|D|1448|0.40|0.60|Garrosh-R|0|1|")
        w = self.wow
        w.run("""__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal, { me = 'Tester',
            roster = { { 'Bob Smith', 'Officer', 58, 'ROGUE', 'sneaky' } } })""")
        bob = "__L.guild.mates[1]"
        self.assertEqual(w.eval(f"{bob}.name"), "Bob Smith")
        self.assertEqual((w.eval(f"{bob}.kills"), w.eval(f"{bob}.deaths")), (1, 1))
        self.assertEqual((w.eval(f"{bob}.class"), w.eval(f"{bob}.level"), w.eval(f"{bob}.note")), ("ROGUE", 58, "sneaky"))
        self.assertEqual((w.eval(f"{bob}.victims[1].n"), w.eval(f"{bob}.victims[1].c")), ("Thrall", "SHAMAN"))
        self.assertEqual(w.eval("__L.guild.lands[1448].kills"), 1)
        self.assertTrue(w.eval("__L.guild.mates[2].me"))

    # -- every character -----------------------------------------------------------
    def test_login_and_logout_write_this_characters_summary(self):
        w = self.wow
        key = "ns.gdb.chars[ns.myFull]"
        self.assertEqual(w.eval(f"{key}.stats.tally.kills"), 0)
        self.kill()
        w.fire("PLAYER_LOGOUT")
        self.assertEqual(w.eval(f"{key}.stats.tally.kills"), 1)
        self.assertEqual(w.eval(f"{key}.class"), "WARRIOR")
        self.assertEqual(w.eval(f"{key}.level"), 60)
        self.assertIsNone(w.eval(f"{key}.stats.guild"))

    def test_a_summary_that_errors_says_so_once_and_is_marked(self):
        w = self.wow
        w.run("local real = ns.Ledger.Stats; ns.Ledger.Stats = function() error('boom') end; "
              "ns.Ledger.Summarize(); ns.Ledger.Stats = real")
        lines = [l for l in w.chat if "Ledger" in l]
        self.assertEqual(len(lines), 1, w.chat)
        self.assertIsNotNone(w.eval("ns.gdb.chars[ns.myFull].err"))
        self.assertEqual(w.eval("ns.Ledger.Account(ns.gdb).failed[1]"), w.eval("ns.myFull"))

    def test_the_account_adds_characters_together(self):
        w = self.wow
        self.kill()
        self.die()
        w.run("ns.Ledger.Summarize()")
        w.run("""local function copy(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == 'table' and copy(v) or v end return c end
                 local other = copy(ns.gdb.chars[ns.myFull])
                 other.stats.tally.best = 7
                 other.stats.records.longest.n = 7
                 ns.gdb.chars['Alt-Realm'] = other
                 __A = ns.Ledger.Account(ns.gdb)""")
        self.assertEqual(w.eval("#__A.chars"), 2)
        self.assertEqual(w.eval("__A.tally.kills"), 2)
        self.assertEqual(w.eval("__A.tally.wilds"), 2)
        self.assertEqual(w.eval("__A.tally.best"), 7)
        self.assertIsNone(w.eval("__A.tally.kd"))  # no PvP deaths
        self.assertEqual(w.eval("__A.records.longest.char"), "Alt-Realm")
        self.assertEqual(w.eval("__A.slain.SHAMAN"), 2)
        self.assertEqual(w.eval("__A.lands[1448].kills"), 2)
        self.assertEqual(w.eval("__A.foes.slain[1].count"), 2)
        self.assertEqual(w.eval("__A.wilds.unrecorded"), 2)
        self.assertEqual(w.eval("__A.continents[1414].bloodiest"), 1448)
        self.assertIsNone(w.eval("__A.guild"))

    def test_one_character_alone_adds_up_to_itself(self):
        w = self.wow
        self.kill()
        self.kill(victim="Garrosh", cls="WARRIOR")
        self.die()
        w.run("ns.Ledger.Summarize(); __L = ns.Ledger.Stats(WarpathDB, WarpathGlobal); __A = ns.Ledger.Account(ns.gdb)")
        for e in ("tally.kills", "tally.deaths", "tally.best", "tally.foes", "tally.wilds", "multi[2]", "streaks[3]",
                  "slain.SHAMAN", "slain.WARRIOR", "lands[1448].kills", "records.firstBlood.t", "records.hour.n",
                  "foes.slain[1].count", "wilds.total", "continents[1414].kills"):
            with self.subTest(figure=e):
                self.assertEqual(w.eval(f"__A.{e}"), w.eval(f"__L.{e}"))
        hour = int(w.eval("tonumber(date('%H'))"))
        self.assertEqual(w.eval(f"__A.hours[{hour}]"), 2)


class LedgerSnapshot(unittest.TestCase):
    """Ledger.Stats on Joe's frozen saved data, against the figures the spec
    (docs/design/chronicle-ledger.md) quotes from it. Hours and dates are
    local time, so these hold in Joe's time zone. Skipped without the
    snapshot (it's gitignored)."""

    @classmethod
    def setUpClass(cls):
        cls.root = ledger_snapshot()
        if not cls.root:
            raise unittest.SkipTest("no Ledger snapshot (tools/out/design/ledger/snapshot)")

    def boot(self, char):
        w = Wow(saved=self.root / "91" / char / "SavedVariables" / "Warpath.lua",
                saved_global=self.root / "SavedVariables" / "Warpath.lua", player={"name": char.split("-")[0]})
        # where the client puts these zones (the stub's unknown maps sit on Kalimdor)
        w.run("""for id, name in pairs({ [1423] = 'Eastern Plaguelands', [1422] = 'Western Plaguelands',
                    [1437] = 'Wetlands', [1431] = 'Duskwood' }) do
                    __H.maps[id] = { name = name, mapType = 3, parentMapID = 1415 } end""")
        w.login()
        return w

    def test_lethality(self):
        w = self.boot("Lethality-Starunner")
        w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal)")
        ev = w.eval
        self.assertEqual((ev("__L.tally.kills"), ev("__L.tally.deaths"), ev("__L.tally.best")), (28, 27, 6))
        self.assertEqual(round(ev("__L.tally.kd"), 2), 1.04)
        self.assertEqual(ev("__L.tally.foes"), 16)
        self.assertEqual(ev("__L.tally.avenged"), 0)
        self.assertEqual(ev("__L.tally.wilds"), 34)
        self.assertEqual(round(ev("__L.tally.yards") / 1760, 1), 1402.6)
        self.assertEqual(ev("__L.tally.sightings"), 1696)
        self.assertEqual(ev("__L.tally.shots"), 22)
        self.assertEqual([ev(f"__L.multi[{n}]") for n in (2, 3, 4, 5)], [2, 1, 0, 0])
        self.assertEqual([ev(f"__L.streaks[{n}]") for n in (3, 5, 10, 15, 20)], [4, 3, 0, 0, 0])
        busiest = ev("(function() local b, h = 0 for k, v in pairs(__L.hours) do if v > b then b, h = v, k end end return h .. ' ' .. b end)()")
        self.assertEqual(busiest, "22 6")
        days = [ev(f"__L.weekdays[{d}] or 0") for d in range(1, 8)]
        self.assertEqual((days[3], max(days)), (10, 10))  # Thursday
        slain = {"PALADIN": 4, "SHAMAN": 4, "WARRIOR": 3, "HUNTER": 2, "MAGE": 2, "PRIEST": 2, "ROGUE": 2,
                 "DRUID": 1, "WARLOCK": None, "unknown": 8}
        for c, n in slain.items():
            with self.subTest(slain=c):
                self.assertEqual(ev(f"__L.slain.{c}"), n)
        slew = {"unknown": 17, "HUNTER": 2, "PALADIN": 2, "WARLOCK": 2, "DRUID": 1, "PRIEST": 1, "SHAMAN": 1, "WARRIOR": 1}
        for c, n in slew.items():
            with self.subTest(slew=c):
                self.assertEqual(ev(f"__L.slew.{c}"), n)
        ep = "__L.lands[1423]"
        self.assertEqual((ev(f"{ep}.kills"), ev(f"{ep}.deaths"), ev(f"{ep}.best")), (8, 1, 5))
        self.assertEqual((ev(f"{ep}.top.f"), ev(f"{ep}.top.count")), ("Kourne-Bladeheart", 2))
        self.assertEqual(ev("__L.continents[1415].bloodiest"), 1423)
        # the wilds' lands: Un'Goro Crater 5, Mount Hyjal 5, Western Plaguelands 4
        self.assertEqual([ev(f"__L.wilds.lands[{m}]") for m in (1449, 2482, 1422)], [5, 5, 4])
        self.assertEqual(ev("__L.wilds.unrecorded"), 34)
        r = "__L.records"
        self.assertEqual(ev(f"date('%B %d', {r}.firstBlood.t)"), "November 19")
        self.assertEqual(ev(f"{r}.firstBlood.map"), 1422)
        self.assertIsNone(ev(f"{r}.firstBlood.n"))  # the foe unnamed
        self.assertEqual(ev(f"{r}.bloodiest.kills .. date(' %A, %B %d', {r}.bloodiest.start)"), "8 Tuesday, November 24")
        self.assertEqual(ev(f"{r}.hour.n .. date(' %A, %B %d, %H:%M', {r}.hour.t)"), "6 Tuesday, November 24, 19:09")
        self.assertEqual((ev(f"{r}.longest.n"), ev(f"{r}.longest.map"), ev(f"{r}.longest.shot")), (6, 1431, 22))
        self.assertEqual(ev(f"date('%B %d', {r}.longest.t)"), "November 26")
        self.assertEqual(ev(f"{r}.worst.deaths .. date(' %A, %B %d', {r}.worst.start)"), "4 Sunday, November 22")
        self.assertEqual((ev(f"{r}.smallest.lv"), ev(f"{r}.smallest.f"), ev(f"{r}.smallest.c"),
                          ev(f"{r}.smallest.ra"), ev(f"{r}.smallest.map")),
                         (28, "Isitin-Mytruck", "MAGE", "High Order Skyborne", 1437))
        self.assertEqual(ev(f"math.floor({r}.longNight.played / 60)"), 15 * 60 + 59)
        self.assertEqual(ev(f"date('%A, %B %d', {r}.longNight.start)"), "Saturday, November 21")
        self.assertEqual(round(ev(f"{r}.farthest.yards") / 1760, 1), 218.6)
        self.assertEqual(ev(f"{r}.mostSeen.n"), 291)
        for k in ("revenge", "closest", "odds", "gap"):
            with self.subTest(record=k):
                self.assertIsNone(ev(f"{r}.{k}"))

    def test_lethalitys_guild_war_joins_the_roster(self):
        roster = self.root / "roster" / "Warpath.lua"
        if not roster.exists():
            self.skipTest("no roster capture")
        w = self.boot("Lethality-Starunner")
        w.run(f"""local env = {{}} local f = assert(loadfile({lua_str(str(roster))})) setfenv(f, env)()
                  __L = ns.Ledger.Stats(WarpathDB, WarpathGlobal, {{ me = 'Lethality Starunner', roster = env.WarpathGlobal.roster }})""")
        ev = w.eval
        self.assertEqual((ev("__L.guild.mates[1].name"), ev("__L.guild.mates[1].kills")), ("Plains Stomper", 38))
        me = "__L.guild.mates[2]"
        self.assertEqual((ev(f"{me}.name"), ev(f"{me}.me"), ev(f"{me}.class"), ev(f"{me}.kills")),
                         ("Lethality Starunner", True, "DRUID", 28))
        self.assertEqual(ev(f"{me}.note"), "Joe")

    def test_empty_characters_give_every_figure(self):
        for char in ("Dabank-Dabonk", "Derelect-Armstrong"):
            with self.subTest(character=char):
                w = self.boot(char)
                w.run("__L = ns.Ledger.Stats(WarpathDB, WarpathGlobal); ns.Ledger.Summarize(); __A = ns.Ledger.Account(ns.gdb)")
                self.assertEqual((w.eval("__L.tally.kills"), w.eval("__L.tally.deaths"), w.eval("__L.tally.best")), (0, 0, 0))
                self.assertIsNone(w.eval("next(__L.records)"))
                self.assertEqual(w.eval("#__A.chars"), 1)
                self.assertGreater(lua_count(w, "__L.lands"), 0)
                self.assertFalse([l for l in w.chat if "Ledger" in l])



REPO = Path(__file__).resolve().parents[2]


def read_tga(path):
    """Parse a TGA with the stdlib: (width, height, bits, rle), checking that the pixel data is
    complete (every RLE packet present). Raises AssertionError on anything the client can't load."""
    data = path.read_bytes()
    assert len(data) >= 18, "shorter than a TGA header"
    idlen, cmap, kind = data[0], data[1], data[2]
    w, h = int.from_bytes(data[12:14], "little"), int.from_bytes(data[14:16], "little")
    bits, desc = data[16], data[17]
    assert cmap == 0, "has a colour map"
    assert kind in (2, 10), "image type %d: not true-colour (2) or RLE true-colour (10)" % kind
    assert bits in (24, 32), "%d bits per pixel" % bits
    assert (desc & 15) == (8 if bits == 32 else 0), "alpha bits %d for %d bpp" % (desc & 15, bits)
    bpp, pos, need = bits // 8, 18 + idlen, w * h
    if kind == 2:
        assert len(data) - pos >= need * bpp, "pixel data truncated"
    else:
        got = 0
        while got < need:
            assert pos < len(data), "RLE data truncated at pixel %d of %d" % (got, need)
            head = data[pos]
            n = (head & 127) + 1
            pos += 1 + (bpp if head & 128 else n * bpp)
            got += n
        assert got == need and pos <= len(data), "RLE packets overrun the image"
    return w, h, bits, kind == 10


class ArtTextures(unittest.TestCase):
    """The chronicle's book art (tools/art/export.py writes it): present, loadable, small enough."""

    # name: (width, height). Anything else in Art/book is a stray file that would ship.
    BOOK = {"book.tga": (1024, 1024), "book-shadow.tga": (256, 256),
            "sheet-shadow.tga": (64, 64), "map-mask.tga": (128, 128)}
    FILE_BUDGET = 3 * 1024 * 1024
    TOTAL_BUDGET = 4 * 1024 * 1024

    def test_every_book_texture_is_there_and_nothing_else(self):
        folder = REPO / "Art" / "book"
        self.assertEqual(sorted(p.name for p in folder.iterdir()), sorted(self.BOOK))

    def test_each_is_a_valid_tga_of_the_expected_size(self):
        for name, size in self.BOOK.items():
            with self.subTest(name=name):
                w, h, bits, rle = read_tga(REPO / "Art" / "book" / name)
                self.assertEqual((w, h), size)
                self.assertEqual(bits, 32)          # every piece has soft alpha

    def test_every_addon_tga_has_power_of_two_sides(self):
        tgas = [p for p in (REPO / "Art").rglob("*.tga")] + [REPO / "glow.tga"]
        self.assertTrue(tgas)
        for p in tgas:
            with self.subTest(tga=str(p.relative_to(REPO))):
                w, h, _, _ = read_tga(p)
                self.assertTrue(w and h and w & (w - 1) == 0 and h & (h - 1) == 0, (w, h))

    def test_sizes_stay_under_budget(self):
        sizes = {n: (REPO / "Art" / "book" / n).stat().st_size for n in self.BOOK}
        for n, b in sizes.items():
            with self.subTest(name=n):
                self.assertLessEqual(b, self.FILE_BUDGET)
        self.assertLessEqual(sum(sizes.values()), self.TOTAL_BUDGET)


def lua_str(s):
    s = str(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


if __name__ == "__main__":
    unittest.main(verbosity=2)
