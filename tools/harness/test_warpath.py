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
            ns.DeathField = function() return setmetatable({}, { __index = function() return 5 end }), {} end
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


class MapButton(unittest.TestCase):
    def test_the_button_toggles_the_map_without_a_chat_line(self):
        wow = Wow().login()
        before = len(wow.chat)
        wow.run("ns.SetMapShown(false)")
        self.assertFalse(wow.eval("ns.cfg.shown"))
        wow.run("ns.SetMapShown(true)")
        self.assertEqual(wow.chat[before:], [])

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
        """The notes page's visible text, top to bottom."""
        return wow.eval("""(function() local t = {}
            local function add(fs) if fs:IsShown() and fs:GetText() then
                local _, _, _, _, y = fs:GetPoint(1) t[#t + 1] = { y or 0, fs:GetText() } end end
            for _, f in ipairs(WarpathChronicle.__children) do
                for _, c in ipairs(f.__children) do
                    for _, r in ipairs(c.__children) do
                        if r.__kind == "FontString" and r:IsVisible() then add(r) end
                    end
                end
            end
            table.sort(t, function(a, b) return a[1] > b[1] end)
            local out = {} for _, v in ipairs(t) do out[#out + 1] = v[2] end
            return table.concat(out, "|") end)()""").replace("|", "\n")

    def test_an_update_opens_the_book_on_whats_new(self):
        wow = self.booted("3.8.2")
        self.assertTrue(self.shown(wow), "the book didn't open on the Warpath tab")
        self.assertFalse(wow.eval("WarpathSetup ~= nil and WarpathSetup:IsShown()"),
                         "the options window no longer opens by itself")
        text = self.page(wow)
        self.assertIn("What's New", text)
        self.assertIn("3.8.3   \u00b7   new since you last played", text)
        self.assertNotIn("3.8.2   \u00b7   new", text, "3.8.2 was already seen")
        self.assertIn("Settings", wow.eval("""(function() for _, f in ipairs(WarpathChronicle.__children) do
            for _, c in ipairs(f.__children) do for _, b in ipairs(c.__children) do
            if b.__template == "UIPanelButtonTemplate" and b:IsVisible() then return b:GetText() end end end end end)()"""))

    def test_closing_the_book_marks_the_release_seen(self):
        wow = self.booted("3.8.2")
        wow.run("WarpathChronicle:Hide()")
        self.assertEqual(wow.eval("WarpathGlobal.seenVersion"), wow.eval("ns.VERSION"))

    def test_a_first_install_opens_the_welcome(self):
        wow = self.booted(None, installed=None)
        self.assertTrue(self.shown(wow))
        text = self.page(wow)
        self.assertIn("Welcome to Warpath", text)
        self.assertNotIn("new since you last played", text, "nothing is 'new' on a first install")
        self.assertIn("Guild sharing is off", text)

    def test_older_releases_are_a_page_turn_away(self):
        wow = self.booted("3.8.2")
        # enough releases that they can't all fit on one page
        wow.run("""for i = 1, 12 do table.insert(ns.NewIn.List, 1, { "2.0." .. i,
            { "An old change that takes up a line or two of the page, for this test.", "And another." } }) end""")
        wow.run("ns.Chronicle.News('3.8.2')")
        first = self.page(wow)
        self.assertIn("3.8.3", first)
        self.assertNotIn("2.0.1\n", first + "\n", "the oldest release can't fit on the first page")
        earlier = "WarpathChronicle.news.earlier"
        self.assertTrue(wow.eval(f"{earlier}:IsEnabled()"))
        for _ in range(20):
            if not wow.eval(f"{earlier}:IsEnabled()"):
                break
            wow.run(f"{earlier}:GetScript('OnClick')({earlier})")
        self.assertFalse(wow.eval(f"{earlier}:IsEnabled()"), "Earlier never reached the oldest page")
        self.assertIn("2.0.1", self.page(wow), "the oldest release is on the last page")
        wow.run("WarpathChronicle.news.later:GetScript('OnClick')(WarpathChronicle.news.later)")
        self.assertNotIn("2.0.1\n", self.page(wow) + "\n")

    def test_versions_order_with_test_builds_first(self):
        wow = Wow()
        for a, b in (("3.7.11", "3.8.0"), ("3.8.0", "3.8.1"), ("3.8.0-test4", "3.8.0"),
                     ("3.8.9", "3.8.10"), ("3.3.5", "3.4")):
            with self.subTest(a=a, b=b):
                self.assertTrue(wow.eval(f"ns.NewIn.Older({lua_str(a)}, {lua_str(b)})"))
                self.assertFalse(wow.eval(f"ns.NewIn.Older({lua_str(b)}, {lua_str(a)})"))
        self.assertFalse(wow.eval('ns.NewIn.Older("3.8.0", "3.8.0")'))

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


class Share(unittest.TestCase):
    """The guild channel, including what 3.7.10's diagnostics count."""

    def setUp(self):
        self.wow = Wow().login()
        self.wow.run("ns.cfg.share = true")
        self.chat_from = len(self.wow.chat)

    def receive(self, text, sender="Bob Smith", channel="GUILD"):
        # WoW Forever: senders arrive as "First Last", a space and no realm.
        self.wow.run(f"ns.OnComm('WARPATH', {lua_str(text)}, {lua_str(channel)}, {lua_str(sender)})")

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
        self.receive(self.kill_msg("Thrall"), sender="Bob Smith")
        self.receive(self.kill_msg("Thrall", 0.41, 0.61), sender="Ann Lee")
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
        self.receive(self.kill_msg(), sender="Bob Smith")
        self.receive(self.kill_msg(x=0.405), sender="Ann Lee")       # same spot
        self.receive(self.kill_msg(x=0.60), sender="Cid Roe")        # far away
        self.assertEqual(len(self.kill_lines()), 2, self.new_chat())
        self.wow.advance(11)
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
        self.receive(self.kill_msg("Thrall", mx, my), sender="Bob Smith")
        lines = len(self.kill_lines())
        self.assertEqual(self.gpins(), 1)
        self.own_kill()
        self.assertEqual(self.wow.eval("WarpathDB.kills"), 1)
        self.assertEqual(len(self.kill_lines()), lines, self.new_chat())
        self.assertEqual(self.gpins(), 0)  # your own mark is there instead

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

    def test_nothing_is_drawn_inside_an_instance(self):
        self.wow.run("ns.OnComm('WARPATH', '1|K|1448|0.25|0.75', 'GUILD', 'Bob Smith')")
        self.wow.run("ns.S.inInstance = true")
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
    # dash slot (Joe's pick D), so it stays joined up instead of thinning to
    # sparse dots. The dash itself still shortens with age.
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
        self.assertLess(dash, 0.5, "the dash no longer shortens with age")
        self.assertLessEqual(gap, 0.36, "old outline gaps are wider than a third of a slot")

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

    def test_the_hidden_trail_stays_hidden_when_you_leave(self):
        # Joe, 3.8.0-test3: leaving an area filled it with trail. The dashes
        # hidden while you were inside came back for a minute. With the solid
        # line short, nothing at all may be drawn inside just after leaving.
        self.wow.run("ns.C.LINE_SOLID = 5")
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
        self.wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end ns.cfg.layers.runs = true")

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


def lua_str(s):
    s = str(s)
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


if __name__ == "__main__":
    unittest.main(verbosity=2)
