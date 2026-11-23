#!/usr/bin/env python3
"""Compile-check every Lua file Warpath ships, under real Lua 5.1.

WoW runs Lua 5.1, and Lua 5.1's own compiler enforces the limits that bit
this addon before: 200 local variables per function (the top level of a file
counts as one function) and 60 upvalues per closure. So compiling with the
real 5.1 compiler catches those exactly, along with every syntax error,
without needing the game.

Files are taken from Warpath.toc, in load order, so a file that exists but is
not listed is reported too: WoW would silently never load it.

Usage:  python tools/harness/check.py      (exit 1 on any failure)
"""

import sys
from pathlib import Path

from lupa.lua51 import LuaRuntime

REPO = Path(__file__).resolve().parents[2]


def toc_files():
    files = []
    for line in (REPO / "Warpath.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        files.append(line.replace("\\", "/"))
    return files


LOCAL_LIMIT = 200
WARN_BELOW = 30   # flag a file once fewer than this many top-level locals remain


def headroom(compile_only, src):
    """How many more top-level locals this file could declare.

    Asked of the real compiler rather than counted by hand: append k fresh
    locals to the end of the chunk, where every top-level local is still in
    scope, and binary-search the largest k that still compiles.
    """
    def fits(k):
        if k == 0:
            return True
        extra = "\nlocal " + ",".join(f"__hr{i}" for i in range(k))
        return compile_only(src + extra, "@headroom")[0]

    lo, hi = 0, LOCAL_LIMIT
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if fits(mid):
            lo = mid
        else:
            hi = mid - 1
    return lo


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    compile_only = lua.eval("function(src, name) local f, err = loadstring(src, name) return f ~= nil, err end")

    listed = toc_files()
    failures = 0
    for rel in listed:
        path = REPO / rel
        if not path.exists():
            print(f"MISSING  {rel}  (listed in Warpath.toc)")
            failures += 1
            continue
        # Lua 5.1 reads bytes; WoW strips a UTF-8 BOM, so do the same.
        src = path.read_bytes().removeprefix(b"\xef\xbb\xbf").decode("utf-8")
        ok, err = compile_only(src, "@" + rel)
        if ok:
            room = headroom(compile_only, src)
            used = LOCAL_LIMIT - room
            flag = "  <-- close to Lua's limit" if room < WARN_BELOW and not rel.startswith("Libs/") else ""
            print(f"ok       {rel:<52} {used:>3}/{LOCAL_LIMIT} top-level locals{flag}")
        else:
            print(f"FAIL     {err}")
            failures += 1

    on_disk = {p.relative_to(REPO).as_posix() for p in REPO.glob("*.lua")}
    on_disk |= {p.relative_to(REPO).as_posix() for p in (REPO / "Libs").rglob("*.lua")}
    for rel in sorted(on_disk - set(listed)):
        print(f"UNLISTED {rel}  (exists but Warpath.toc never loads it)")
        failures += 1

    print()
    print(f"{len(listed)} files, {failures} problem(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
