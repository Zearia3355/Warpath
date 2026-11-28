#!/usr/bin/env python3
"""Render what Warpath draws on the world map, from real saved data.

    python tools/harness/render.py --wtf "<WTF\\Account\\NAME>" --char Name-Realm
    python tools/harness/render.py ... --map 1448 --out felwood.png
    python tools/harness/render.py ... --ref 3.7.5 --ref main      # before / after
    python tools/harness/render.py ... --ref main --ref work       # main vs uncommitted
    python tools/harness/render.py ... --book campaigns            # the chronicle (book_render.py)

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

--backdrop draws over an in-game screenshot of the same map (--canvas cuts the
map's canvas out of it), at the size it was in game: the real art decides
whether a colour reads, which the olive stand-in can't tell you.

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

-- centre and size of a region, in image pixels (y down). Offsets from the
-- overlay are from its top-left, as Map.lua places everything.
-- -1 for a point on the first side, +1 on the second, 0 centred
local function Off(pt, a, b)
    if pt:find(a) then return -1 elseif pt:find(b) then return 1 end
    return 0
end

local rect
function rect(o)
    for _, p in ipairs(o.__points) do
        if p[2] == overlay and type(p[1]) == "string" then
            local x, y, w, h = p[4] or 0, -(p[5] or 0), o.__w, o.__h
            local s = (o.__scale or 1)
            if p[1]:find("LEFT") then x = x + w * s / 2 elseif p[1]:find("RIGHT") then x = x - w * s / 2 end
            if p[1]:find("TOP") then y = y + h * s / 2 elseif p[1]:find("BOTTOM") then y = y - h * s / 2 end
            return x, y, w, h
        end
    end
    -- anchored to another region (a pin, a font string), with its offset
    local p = o.__points[1]
    if p and p[1] ~= "ALL" then
        local rel, rp, ox, oy = o.__parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then rel, rp, ox, oy = p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
        if rel and rel ~= overlay then
            local x, y, w, h
            if rel.__kind == "FontString" then
                local q = rel.__points[1]
                if q then
                    local r2, rp2, ox2, oy2 = rel.__parent, q[1], q[2] or 0, q[3] or 0
                    if type(q[2]) == "table" then r2, rp2, ox2, oy2 = q[2], q[3] or q[1], q[4] or 0, q[5] or 0 end
                    local px, py, pw, ph = rect(r2)
                    if px then
                        local tw, th = #(rel.__text or "") * 6, 12
                        local ax, ay = px + Off(rp2, "LEFT", "RIGHT") * pw / 2 + ox2, py + Off(rp2, "TOP", "BOTTOM") * ph / 2 - oy2
                        x, y, w, h = ax - Off(q[1], "LEFT", "RIGHT") * tw / 2, ay - Off(q[1], "TOP", "BOTTOM") * th / 2, tw, th
                    end
                end
            else
                x, y, w, h = rect(rel)
            end
            if x then
                local ow, oh = o.__w or 0, o.__h or 0
                local ax, ay = x + Off(rp, "LEFT", "RIGHT") * w / 2 + ox, y + Off(rp, "TOP", "BOTTOM") * h / 2 - oy
                return ax - Off(p[1], "LEFT", "RIGHT") * ow / 2, ay - Off(p[1], "TOP", "BOTTOM") * oh / 2,
                    ow > 0 and ow or w, oh > 0 and oh or h
            end
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
    elseif o.__kind == "FontString" then
        -- text: where its anchor lands, and which of its own points sits there
        local t, p = o.__text, o.__points[1]
        if not t or t == "" or not p then return end
        local rel, rp, ox, oy = o.__parent, p[1], p[2] or 0, p[3] or 0
        if type(p[2]) == "table" then rel, rp, ox, oy = p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
        local x, y, w, h = rect(rel)
        if not x then return end
        if rp:find("LEFT") then x = x - w / 2 elseif rp:find("RIGHT") then x = x + w / 2 end
        if rp:find("TOP") then y = y - h / 2 elseif rp:find("BOTTOM") then y = y + h / 2 end
        local font = tostring(o.__font or "GameFontNormal")
        local c = o.__textColor or (font:find("Highlight") and { 1, 1, 1, 1 } or { 1, 0.82, 0, 1 })
        out[#out + 1] = table.concat({ "S", "BLEND", c[1], c[2], c[3], (c[4] or 1) * a,
            x + ox, y - oy, p[1], font, (tostring(t):gsub("[\t\n]", " ")) }, "\t")
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
local frames = {}
for i, f in ipairs(overlay.__children) do
    if not f.__layer and f:IsVisible() then frames[#frames + 1] = { f, i } end
end
-- higher frame levels draw on top, as in the client
table.sort(frames, function(p, q)
    local lp, lq = p[1].__level or 0, q[1].__level or 0
    if lp ~= lq then return lp < lq end
    return p[2] < q[2]
end)
for _, fi in ipairs(frames) do
    for _, r in ipairs(regionsOf(fi[1])) do emit(r) end
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


FONT_PX = {"GameFontNormalSmall": 10, "GameFontHighlightSmall": 10, "GameFontNormal": 12,
           "GameFontHighlight": 12, "GameFontNormalLarge": 16}
_fonts = {}


def text_font(name):
    """A stand-in for the game font (Friz Quadrata isn't on disk): a bold
    serif at the template's size, scaled with the supersampling."""
    px = FONT_PX.get(name, 12) * SS
    if px not in _fonts:
        for face in ("palab.ttf", "georgiab.ttf", "arialbd.ttf"):
            try:
                _fonts[px] = ImageFont.truetype(face, px)
                break
            except OSError:
                continue
        else:
            _fonts[px] = ImageFont.load_default()
    return _fonts[px]


def paint(prims, w, h, backdrop=None):
    W, H = w * SS, h * SS
    if backdrop is not None:            # the real map art, from an in-game screenshot
        base = backdrop.convert("RGB").resize((W, H), Image.LANCZOS)
    else:
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

        if kind == "S":
            x, y = float(f[6]) * SS, float(f[7]) * SS
            point, font, text = f[8], f[9], f[10]
            ft = text_font(font)
            tw, th = draw.textlength(text, font=ft), ft.size
            if "LEFT" in point: x0 = x
            elif "RIGHT" in point: x0 = x - tw
            else: x0 = x - tw / 2
            if "TOP" in point: y0 = y
            elif "BOTTOM" in point: y0 = y - th
            else: y0 = y - th / 2
            y0 -= th * 0.12          # the font's own top padding
            draw.text((x0 + SS, y0 + SS), text, font=ft, fill=(0, 0, 0, col[3]))   # the game fonts' shadow
            draw.text((x0, y0), text, font=ft, fill=col)
            continue

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


def render(addon_dir, saved, account, name, map_id, at, layers=None, backdrop=None):
    """backdrop: the map canvas cut from an in-game screenshot. The overlay
    takes its size, so lines are as thick, in pixels, as they were in game."""
    wow = Wow(saved=saved, saved_global=account, player={"name": name, "mapID": map_id},
              addon_dir=addon_dir)
    wow.H.now = int(at)
    wow.login(settle=0)
    if backdrop is not None:
        wow.run(f"WarpathOverlay.__w = {backdrop.width}; WarpathOverlay.__h = {backdrop.height}")
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
    return paint(prims, int(D["w"]), int(D["h"]), backdrop), stats, wow


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
    ap.add_argument("--char", help="character folder name, e.g. Name-Realm (required for the map; "
                    "for --book, none renders a fresh character)")
    ap.add_argument("--map", type=int, help="uiMapID to view (default: the zone with the most roads)")
    ap.add_argument("--at", help="unix time to render at (default: the character's last logout)")
    ap.add_argument("--ref", action="append",
                    help="git ref to render instead of the working copy; repeat for before/after. "
                         "'work' is the working copy, e.g. --ref main --ref work")
    ap.add_argument("--layers", help="comma list to show only these, e.g. roads,trail")
    ap.add_argument("--out", default="warpath-render.png")
    ap.add_argument("--backdrop", help="in-game screenshot of the same map, to draw over its real art")
    ap.add_argument("--canvas", help="x1,y1,x2,y2 of the map canvas in the screenshot (default: the whole image)")
    bk = ap.add_argument_group("the chronicle (--book)")
    bk.add_argument("--book", metavar="TAB", help="render the chronicle open on a tab: campaigns, grudges, settings, warpath")
    bk.add_argument("--page", type=int, help="campaigns: the Nth campaign, newest first; warpath: the Nth page of "
                    "What's New; grudges: the Nth grudge in the list")
    bk.add_argument("--section", help="settings: alerts, map, guild, shots, zones or grudges")
    bk.add_argument("--preview", action="store_true", help="the sample pages (the book's preview)")
    bk.add_argument("--scale", type=float, default=1.0, help="scale the 1092x748 canvas (1.175: in-game size)")
    bk.add_argument("--beside", metavar="DESIGN.png", help="put a design render beside the code's, at the same scale")
    bk.add_argument("--onion", metavar="DESIGN.png", help="blend a design render 50/50 over the code's")
    bk.add_argument("--origin", default="shot", help="the book's top-left on the canvas: shot (Joe's screenshot, "
                    "default), canon (chronicle.md's conversion) or x,y")
    bk.add_argument("--fonts", default="standin", choices=("standin", "game", "repo"),
                    help="standin: the design renders' faces at their sizes (default); game: the same faces sized "
                         "to the widths the game measured (the probe); repo: EB Garamond for every face (tests)")
    ap.add_argument("--night", choices=["design"], help="--book campaigns: give Lethality's 25 November campaign the "
                    "design renders' made-up 21-kill night (type/overflow.py LONG), to compare the right page")
    ap.add_argument("--grudges", choices=["design", "none"], help="--book grudges: the design's made-up busy "
                    "list (grudges/gdata.py BUSY, ns.ChronGrudges.Samples) or no grudges at all, in place of the saved ones")
    ap.add_argument("--run", help="--book: Lua to run after opening, before the render (fold a zone, scroll...)")
    args = ap.parse_args()
    if args.book:
        return book_main(ap, args)
    if not args.char:
        ap.error("--char is required")
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

    backdrop = None
    if args.backdrop:
        backdrop = Image.open(args.backdrop).convert("RGB")
        if args.canvas:
            backdrop = backdrop.crop(tuple(int(v) for v in args.canvas.split(",")))
    refs = args.ref or [None]
    panels = []
    for ref in refs:
        if ref == "work":
            ref = None
        addon_dir = addon_from_ref(ref) if ref else REPO
        img, stats, wow = render(addon_dir, saved, account, name, map_id, at, layers, backdrop)
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


def book_main(ap, args):
    import book_render as B
    saved = account = None
    name = "Tester"
    at = float(args.at) if args.at else None
    if args.char:
        if not args.wtf:
            ap.error("--wtf or WARPATH_WTF is required with --char")
        wtf = Path(args.wtf)
        saved = next(wtf.glob(f"*/{args.char}/SavedVariables/Warpath.lua"), None)
        if not saved:
            ap.error(f"no Warpath SavedVariables for {args.char} under {wtf}")
        account = wtf / "SavedVariables" / "Warpath.lua"
        account = account if account.exists() else None
        name = args.char.split("-")[0]
        at = at or saved.stat().st_mtime
    origin = args.origin
    if "," in origin:
        origin = tuple(float(v) for v in origin.split(","))
    elif origin not in B.ORIGINS:
        ap.error("--origin is shot, canon or x,y")
    addon_dir = addon_from_ref(args.ref[0]) if args.ref and args.ref[0] != "work" else REPO
    wow, typ = B.boot(saved, account, name, at, args.fonts, addon_dir)
    if args.night == "design":
        wow.run(B.DESIGN_NIGHT)
    if args.grudges:
        wow.run(B.DESIGN_GRUDGES if args.grudges == "design" else "WarpathGlobal.kos = {}")
    already = B.open_book(wow, args.book, args.page, args.section, args.preview)
    if args.run:
        wow.run(args.run)
    img, painter = B.render_book(wow, typ, origin)
    what = args.book + (f" {args.section}" if args.section else "") + (f" p{args.page}" if args.page else "")
    label = f"code: {what}  -  {args.char or 'fresh character'}  -  {args.ref[0] if args.ref else 'working copy'}"
    if already == args.book:
        label += "  -  opened by itself at login"
    if args.onion:
        out = B.onion(img, B.design_canvas(args.onion), args.scale, label + "   50/50 with   " + Path(args.onion).name)
    elif args.beside:
        out = B.beside(img, B.design_canvas(args.beside), args.scale, label, "design: " + Path(args.beside).name)
    else:
        out = B.scaled(img, args.scale)
    out.save(args.out)
    print(label)
    print("fonts: " + "; ".join(sorted(typ.used)))
    print("stand-ins for game art: " + ", ".join(sorted(painter.standins)))
    errors = wow.H.errors
    if errors:
        print("Lua errors caught by the error handler:")
        for i in range(1, len(errors) + 1):
            print("  " + str(errors[i]))
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
