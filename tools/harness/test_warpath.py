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
