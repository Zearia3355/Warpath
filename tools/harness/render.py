#!/usr/bin/env python3
"""Render what Warpath draws on the world map, from real saved data.

    python tools/harness/render.py --wtf "<WTF\\Account\\NAME>" --char Name-Realm
    python tools/harness/render.py ... --map 1448 --out felwood.png
    python tools/harness/render.py ... --ref 3.7.5 --ref main      # before / after

This is the "render before/after from his real saved data before building"
step: run the addon's own Map.lua against a character's SavedVariables, catch
every line and texture it places, and paint them.

What it is and isn't:
  * Geometry, colour, alpha, thickness, blend and draw order are the addon's
    own. Fades, budgets and anchoring are exactly what the code computes.
  * The map art is not available outside the game, so the ground is a plain
    olive stand-in, and icon textures (skulls, blades, crests) are drawn as
    simple glyphs. Final looks are always checked in game.

Saved data is only read. The map's master switch is forced on in memory
(a character may have it off), and nothing is written back.

--at sets the moment to render. The default is when the SavedVariables file
was last written, i.e. the character's last logout, so "today's trail" shows
as it looked then rather than faded out by the time you run this.
"""

import argparse
import io
import os
import sys
import tarfile
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import REPO, Wow  # noqa: E402

GROUND = (92, 90, 60)        # olive stand-in for the map art
GRID = (100, 98, 67)
SS = 2                        # supersampling factor

# Walk the overlay and serialise every visible primitive, in draw order, one
# per line. Done in Lua because it's thousands of objects.
COLLECT = r"""
local overlay = WarpathOverlay
local RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local out = {}

local function alphaOf(o)
    local a, w = 1, o
    while w and w ~= overlay do a = a * (w.__alpha or 1) w = w.__parent end
    return a
end

-- centre and size of a region, in image pixels (y down)
local function rect(o)
    for _, p in ipairs(o.__points) do
        if p[1] == "CENTER" and p[2] == overlay then
            return p[4] or 0, -(p[5] or 0), o.__w, o.__h
        end
    end
    local par = o.__parent
    if par and par ~= overlay then
        local x, y, w, h = rect(par)
        if x then
            local full = o.__points[1] and o.__points[1][1] == "ALL"
            return x, y, (full or o.__w == 0) and w or o.__w, (full or o.__h == 0) and h or o.__h
        end
    end
end

local function emit(o)
    if not o:IsVisible() then return end
    local a = alphaOf(o)
    if o.__kind == "Line" then
        local s, e, c = o.__start, o.__end, o.__color
        if not (s and e and c) then return end
        out[#out + 1] = table.concat({ "L", o.__blend or "BLEND", c[1], c[2], c[3], c[4] * a,
            s[1], -s[2], e[1], -e[2], o.__thick or 1 }, "\t")
    elseif o.__kind == "Texture" then
        local x, y, w, h = rect(o)
        if not x or (w or 0) <= 0 then return end
        local r, g, b, va = 1, 1, 1, 1
        if o.__color then r, g, b, va = unpack(o.__color)
        elseif o.__vertex then r, g, b, va = unpack(o.__vertex) end
        out[#out + 1] = table.concat({ "T", o.__blend or "BLEND", r, g, b, va * a,
            x, y, w, h or w, tostring(o.__texture or "") }, "\t")
    end
end

local function regionsOf(frame)
    local list = {}
    for _, c in ipairs(frame.__children) do if c.__layer then list[#list + 1] = c end end
    table.sort(list, function(p, q)
        local rp, rq = RANK[p.__drawLayer] or 3, RANK[q.__drawLayer] or 3
        if rp ~= rq then return rp < rq end
        if (p.__sub or 0) ~= (q.__sub or 0) then return (p.__sub or 0) < (q.__sub or 0) end
        return (p.__seq or 0) < (q.__seq or 0)
    end)
    return list
end

-- the overlay's own regions, then child frames (pins, labels) above them
for _, r in ipairs(regionsOf(overlay)) do emit(r) end
for _, f in ipairs(overlay.__children) do
    if not f.__layer and f:IsVisible() then
        for _, r in ipairs(regionsOf(f)) do emit(r) end
    end
end
return table.concat(out, "\n")
"""


def stamp(size):
    """The soft radial falloff of the addon's glow.tga."""
    n = 64
    m = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(m)
    for i in range(n // 2, 0, -1):
        v = int(255 * (1 - i / (n / 2)) ** 1.6)
        d.ellipse([n / 2 - i, n / 2 - i, n / 2 + i, n / 2 + i], fill=v)
    return m.resize((max(size, 1), max(size, 1)), Image.LANCZOS)


def glyph(kind, size):
    """Stand-ins for icon textures that exist only in the game client."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    s, w = size, max(size // 8, 1)
    if kind == "skull":
        d.ellipse([s * .15, s * .05, s * .85, s * .7], fill=255)
        d.rectangle([s * .3, s * .55, s * .7, s * .9], fill=255)
        d.ellipse([s * .28, s * .25, s * .45, s * .45], fill=0)
        d.ellipse([s * .55, s * .25, s * .72, s * .45], fill=0)
    elif kind == "blades":
        d.line([s * .15, s * .15, s * .85, s * .85], fill=255, width=w * 2)
        d.line([s * .85, s * .15, s * .15, s * .85], fill=255, width=w * 2)
    elif kind == "cross":
        d.line([s * .25, s * .25, s * .75, s * .75], fill=255, width=w * 2)
        d.line([s * .75, s * .25, s * .25, s * .75], fill=255, width=w * 2)
    elif kind == "star":
        c = s / 2
        d.polygon([(c, 0), (c + s * .12, c), (c, s), (c - s * .12, c)], fill=255)
        d.polygon([(0, c), (c, c - s * .12), (s, c), (c, c + s * .12)], fill=255)
        m = m.filter(ImageFilter.GaussianBlur(max(s / 24, 0.5)))
    elif kind == "crest":
        d.polygon([(s * .5, s * .05), (s * .9, s * .25), (s * .8, s * .75), (s * .5, s * .95),
                   (s * .2, s * .75), (s * .1, s * .25)], fill=255)
    else:  # solid disc
        d.ellipse([0, 0, s - 1, s - 1], fill=255)
    return m


def classify(tex):
    t = tex.lower()
    if t == "color":
        return "rect"
    if t.endswith("\\glow") or "glow.tga" in t:
        return "soft"
    if "star4" in t:
        return "star"
    if "skull" in t:
        return "skull"
    if "cursor" in t and "attack" in t:
        return "blades"
    if "raidtargeting" in t:
        return "cross"
    if "ui-pvp" in t:
        return "crest"
    return "disc"


def paint(prims, w, h):
    W, H = w * SS, h * SS
    base = Image.new("RGB", (W, H), GROUND)
    g = ImageDraw.Draw(base)
    for i in range(1, 10):
        g.line([(W * i / 10, 0), (W * i / 10, H)], fill=GRID, width=1)
        g.line([(0, H * i / 10), (W, H * i / 10)], fill=GRID, width=1)

    add = None
    stamps = {}

    def layer_for(blend):
        nonlocal add
        if blend == "ADD":
            if add is None:
                add = Image.new("RGB", (W, H), (0, 0, 0))
            return add
        return base

    def flush():
        nonlocal base, add
        if add is not None:
            base = ImageChops.add(base, add)
            add = None

    last_blend = None
    for p in prims:
        f = p.split("\t")
        kind, blend = f[0], f[1]
        if last_blend == "ADD" and blend != "ADD":
            flush()
        last_blend = blend
        r, gg, b, a = (float(v) for v in f[2:6])
        a = max(0.0, min(1.0, a))
        if a < 0.01:
            continue
        target = layer_for(blend)
        if blend == "ADD":   # additive: colour scaled by alpha, onto black
            col = (int(r * a * 255), int(gg * a * 255), int(b * a * 255), 255)
        else:
            col = (int(r * 255), int(gg * 255), int(b * 255), int(a * 255))
        draw = ImageDraw.Draw(target, "RGBA")

        if kind == "L":
            x1, y1, x2, y2, th = (float(v) * SS for v in f[6:11])
            draw.line([(x1, y1), (x2, y2)], fill=col, width=max(int(round(th)), 1))
            continue

        x, y, tw, th = (float(v) * SS for v in f[6:10])
        what = classify(f[10] if len(f) > 10 else "")
        if what == "rect":
            draw.rectangle([x - tw / 2, y - th / 2, x + tw / 2, y + th / 2], fill=col)
            continue
        size = max(int(round(max(tw, th))), 2)
        key = (what, size)
        if key not in stamps:
            stamps[key] = stamp(size) if what == "soft" else glyph(what, size)
        mask = stamps[key]
        if blend != "ADD":
            mask = mask.point(lambda v, a=a: int(v * a))
        box = (int(x - size / 2), int(y - size / 2))
        target.paste(Image.new("RGB", (size, size), col[:3]), box, mask)
    flush()
    return base.resize((w, h), Image.LANCZOS)


def addon_from_ref(ref):
    """Extract the addon as it was at a git ref, for before/after renders."""
    import subprocess
    data = subprocess.run(["git", "-C", str(REPO), "archive", "--format=tar", ref],
                          check=True, capture_output=True).stdout
    tmp = Path(tempfile.mkdtemp(prefix=f"warpath-{ref.replace('/', '_')}-"))
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        t.extractall(tmp, filter="data")
    return tmp


def render(addon_dir, saved, account, name, map_id, at, layers=None):
    wow = Wow(saved=saved, saved_global=account, player={"name": name, "mapID": map_id},
              addon_dir=addon_dir)
    wow.H.now = int(at)
    wow.login(settle=0)
    wow.run(f"WorldMapFrame.__shown = true; __H.mapShown = {int(map_id)}; ns.cfg.shown = true")
    if layers is not None:
        wow.run("for k in pairs(ns.cfg.layers) do ns.cfg.layers[k] = false end")
        for l in layers:
            wow.run(f'ns.cfg.layers["{l}"] = true')
    D = wow.eval("ns.Redraw()")
    prims = [p for p in wow.run(COLLECT).split("\n") if p]
    stats = {k: D[k] for k in ("nl", "nd", "np", "ndash", "nrun")}
    # Zones with data that couldn't be placed on this map: no known rect.
    # In game some of these overlap the viewed map and would be drawn.
    stats["unplaced"] = int(wow.eval(f"""(function()
        local n = 0
        for id in pairs(WarpathDB.maps) do
            if id ~= {int(map_id)} and __H.rectMisses and __H.rectMisses[id .. ">" .. {int(map_id)}] then n = n + 1 end
        end return n end)()"""))
    return paint(prims, int(D["w"]), int(D["h"])), stats, wow


def caption(img, text):
    out = Image.new("RGB", (img.width, img.height + 28), (24, 22, 18))
    out.paste(img, (0, 28))
    try:
        font = ImageFont.truetype("arial.ttf", 16)
    except OSError:
        font = ImageFont.load_default()
    ImageDraw.Draw(out).text((10, 5), text, fill=(235, 220, 180), font=font)
    return out


LAYER_ALIASES = {"trail": "recent", "guild": "shared"}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--wtf", default=os.environ.get("WARPATH_WTF"),
                    help="the WTF\\Account\\<NAME> folder (or set WARPATH_WTF)")
    ap.add_argument("--char", required=True, help="character folder name, e.g. Name-Realm")
    ap.add_argument("--map", type=int, help="uiMapID to view (default: the zone with the most roads)")
    ap.add_argument("--at", help="unix time to render at (default: the character's last logout)")
    ap.add_argument("--ref", action="append", help="git ref to render instead of the working copy; repeat for before/after")
    ap.add_argument("--layers", help="comma list to show only these, e.g. roads,trail")
    ap.add_argument("--out", default="warpath-render.png")
    args = ap.parse_args()
    if not args.wtf:
        ap.error("--wtf or WARPATH_WTF is required")

    wtf = Path(args.wtf)
    saved = next(wtf.glob(f"*/{args.char}/SavedVariables/Warpath.lua"), None)
    if not saved:
        ap.error(f"no Warpath SavedVariables for {args.char} under {wtf}")
    account = wtf / "SavedVariables" / "Warpath.lua"
    account = account if account.exists() else None
    at = float(args.at) if args.at else saved.stat().st_mtime
    layers = [LAYER_ALIASES.get(l.strip(), l.strip()) for l in args.layers.split(",")] if args.layers else None
    name = args.char.split("-")[0]

    map_id = args.map
    if map_id is None:
        probe = Wow(saved=saved, saved_global=account)
        map_id = int(probe.eval("""(function()
            local best, n = 1448, -1
            for id, z in pairs(WarpathDB.maps) do
                local c = 0 for _ in pairs(z.road or {}) do c = c + 1 end
                if c > n then best, n = id, c end
            end return best end)()"""))

    refs = args.ref or [None]
    panels = []
    for ref in refs:
        addon_dir = addon_from_ref(ref) if ref else REPO
        img, stats, wow = render(addon_dir, saved, account, name, map_id, at, layers)
        zone = wow.eval(f"ns.MapName({map_id})")
        label = f"{ref or 'working copy'}  -  {zone}  -  {stats['nl']} lines, {stats['nd']} dots, {stats['np']} pins"
        if stats["unplaced"]:
            label += f"  -  {stats['unplaced']} other zones not placed (no map rects)"
            print(f"note: {stats['unplaced']} other zones with data have no known rect on this map and are "
                  "left out; in game, any that overlap it would be drawn. Capture rects in game (CLAUDE.md, Testing).")
        print(label)
        panels.append(caption(img, label))

    out = Image.new("RGB", (sum(p.width for p in panels) + 8 * (len(panels) - 1), panels[0].height), (24, 22, 18))
    x = 0
    for p in panels:
        out.paste(p, (x, 0))
        x += p.width + 8
    out.save(args.out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
