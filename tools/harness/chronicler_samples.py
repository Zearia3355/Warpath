#!/usr/bin/env python3
"""Write every campaign of a character as the chronicle page would read it.

    python tools/harness/chronicler_samples.py --char Lethality-Starunner [--out file.txt]

Uses the addon's own Chronicler.lua on the real saved data (WARPATH_WTF, or
--wtf). Names drawn in class colour on the page are shown as [Name]. The
layout matches the design prototype's samples.txt, so the two can be diffed.
"""

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import Wow  # noqa: E402

WRITE_ALL = """
local out = {}
local list = { WarpathDB.campaign }
for _, c in ipairs(WarpathDB.campaigns or {}) do list[#list + 1] = c end
for _, c in ipairs(list) do
    if not c.old then
        local p = ns.Chronicler.Write(c, ...)
        local prose = {}
        for _, r in ipairs(p.runs) do prose[#prose + 1] = r.name and ("[" .. r.text .. "]") or r.text end
        out[#out + 1] = p.date.text .. "  \\194\\183  " .. p.date.tag .. (p.quiet and " (quiet, hidden)" or "")
        out[#out + 1] = "  " .. table.concat(p.title, " / "):upper()
        out[#out + 1] = "  " .. table.concat(prose)
        out[#out + 1] = ""
    end
end
return table.concat(out, "\\n")
"""


def samples(wtf, char, foe=None):
    root = Path(wtf)
    saved = root / "91" / char / "SavedVariables" / "Warpath.lua"
    if not saved.exists():
        saved = next(root.glob(f"*/{char}/SavedVariables/Warpath.lua"))
    wow = Wow(saved=saved, player={"name": char.split("-")[0]})
    fn = wow.lua.eval("function(ns, ...) return (function(...) " + WRITE_ALL + " end)(...) end")
    return wow.call(fn, wow.ns, char.split("-")[0], foe)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wtf", default=os.environ.get("WARPATH_WTF"))
    ap.add_argument("--char", required=True)
    ap.add_argument("--foe", help="Alliance or Horde (default: from the saved faction, else 'enemy')")
    ap.add_argument("--out")
    a = ap.parse_args()
    text = samples(a.wtf, a.char, a.foe)
    if a.out:
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        Path(a.out).write_text(text + "\n", encoding="utf-8")
    else:
        sys.stdout.buffer.write((text + "\n").encode("utf-8"))


if __name__ == "__main__":
    main()
