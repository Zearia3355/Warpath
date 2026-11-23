#!/usr/bin/env python3
"""Load Warpath under Lua 5.1 the way the WoW client does, and drive it.

    from harness import Wow
    wow = Wow()                                   # fresh character, no saved data
    wow = Wow(saved="path/to/char/Warpath.lua",   # or real SavedVariables
              saved_global="path/to/account/Warpath.lua")
    wow.login()                                   # ADDON_LOADED, PLAYER_LOGIN, ...
    wow.advance(30)                               # run timers for 30 s
    wow.fire("PLAYER_DEAD")
    wow.chat                                      # every line printed

Boot order follows the client: the stub API, then SavedVariables (which in the
client are executed before any addon code), then every file in Warpath.toc in
order, each called with (addonName, ns) like the real loader.

SavedVariables are only ever READ. They are executed into the Lua state and
never written back, so a real character's history can be used safely.
"""

from pathlib import Path

from lupa.lua51 import LuaRuntime

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
ADDON = "Warpath"


class LuaFailure(RuntimeError):
    pass


def toc(addon_dir=REPO):
    meta, files = {}, []
    for line in (Path(addon_dir) / "Warpath.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("##"):
            key, _, value = line[2:].partition(":")
            meta[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return meta, files


def read_lua(path):
    return Path(path).read_bytes().removeprefix(b"\xef\xbb\xbf").decode("utf-8")


class Wow:
    def __init__(self, saved=None, saved_global=None, player=None, addon_dir=REPO):
        """addon_dir: load the addon from another checkout instead of this
        repo, e.g. an older release extracted with `git archive`, so the same
        saved data can be rendered before and after a change."""
        self.addon_dir = Path(addon_dir)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        # Run a function and turn a Lua error into a Python one with the Lua
        # traceback attached, instead of lupa's bare message.
        self._run = self.lua.eval("""
            function(f, ...)
                local args, n = {...}, select('#', ...)
                local ok, err = xpcall(function() return f(unpack(args, 1, n)) end, debug.traceback)
                return ok, err
            end""")
        # Always two values: lupa only unpacks multiple returns into a tuple.
        self._load = self.lua.eval(
            "function(src, name) local f, err = loadstring(src, name) return f or false, err or false end")

        self._exec(read_lua(HERE / "wow_stub.lua"), "@wow_stub.lua")
        self.H = g["__H"]  # item access: g.__H would be name-mangled inside a class
        meta, self.files = toc(self.addon_dir)
        self.H.meta = self.lua.table_from(meta)
        if player:
            for k, v in player.items():
                self.H.player[k] = v

        self.globals_before = set(g.keys())
        if saved_global:
            self._exec(read_lua(saved_global), "@SavedVariables(account)")
        if saved:
            self._exec(read_lua(saved), "@SavedVariables(character)")
        self.saved_globals = set(g.keys()) - self.globals_before

        self.ns = self.lua.table()
        for rel in self.files:
            self._exec(read_lua(self.addon_dir / rel), "@" + rel, ADDON, self.ns)

    # -- plumbing --------------------------------------------------------------
    def _exec(self, src, name, *args):
        fn, err = self._load(src, name)
        if not fn:
            raise LuaFailure(f"compile {name}: {err}")
        return self.call(fn, *args)

    def call(self, fn, *args):
        ok, err = self._run(fn, *args)
        if not ok:
            raise LuaFailure(err)
        return err

    def eval(self, expr):
        """Evaluate a Lua expression. `ns` refers to the addon namespace."""
        fn, err = self._load("local ns = ...; return " + expr, "@eval")
        if not fn:
            raise LuaFailure(err)
        ok, res = self._run(fn, self.ns)
        if not ok:
            raise LuaFailure(res)
        return res

    def run(self, code):
        """Run Lua statements. `ns` refers to the addon namespace."""
        fn, err = self._load("local ns = ...; " + code, "@run")
        if not fn:
            raise LuaFailure(err)
        ok, res = self._run(fn, self.ns)
        if not ok:
            raise LuaFailure(res)
        return res

    # -- driving ----------------------------------------------------------------
    def fire(self, event, *args):
        self.call(self.H.Fire, event, *args)

    def advance(self, seconds):
        self.call(self.H.Advance, seconds)

    def login(self, settle=10):
        """The client's boot sequence, then let startup timers run."""
        self.fire("ADDON_LOADED", ADDON)
        self.fire("PLAYER_LOGIN")
        self.fire("PLAYER_ENTERING_WORLD", True, False)
        self.fire("ADDON_LOADED", "Blizzard_WorldMap")
        if settle:
            self.advance(settle)
        return self

    # -- inspection ------------------------------------------------------------
    @property
    def chat(self):
        return [self.H.chat[i] for i in range(1, len(self.H.chat) + 1)]

    @property
    def sent(self):
        return [dict(self.H.sent[i]) for i in range(1, len(self.H.sent) + 1)]

    def new_globals(self):
        """Globals the addon itself created: anything beyond the stub and the
        SavedVariables. A leaked local shows up here at runtime."""
        now = set(self.lua.globals().keys())
        return sorted(str(k) for k in now - self.globals_before - self.saved_globals)

    def unknown_methods(self):
        return {str(k): v for k, v in self.H.unknownMethods.items()}
