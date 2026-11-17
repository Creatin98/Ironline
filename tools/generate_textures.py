"""Generates tileable PBR-ish albedo textures as PNG files (pure Python, no deps).

Run from the project root:  py -3 tools/generate_textures.py
Output: assets/textures/*.png
"""
import math
import os
import random
import struct
import sys
import zlib

SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")


def write_png(path, size, rows):
    """rows: list of bytes objects, each row RGB (3*size bytes)."""
    raw = b"".join(b"\x00" + r for r in rows)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


class TileNoise:
    """Periodic value noise so every texture tiles seamlessly."""

    def __init__(self, seed, period):
        rnd = random.Random(seed)
        self.period = period
        self.grid = [[rnd.random() for _ in range(period)] for _ in range(period)]

    def sample(self, x, y):
        p = self.period
        xi = int(math.floor(x)) % p
        yi = int(math.floor(y)) % p
        xf = x - math.floor(x)
        yf = y - math.floor(y)
        xf = xf * xf * (3 - 2 * xf)
        yf = yf * yf * (3 - 2 * yf)
        g = self.grid
        a = g[yi][xi]
        b = g[yi][(xi + 1) % p]
        c = g[(yi + 1) % p][xi]
        d = g[(yi + 1) % p][(xi + 1) % p]
        return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf


def fbm(noises, u, v):
    """u,v in [0,1). Sum of octaves. Returns roughly [0,1]."""
    total = 0.0
    amp = 1.0
    norm = 0.0
    for n in noises:
        total += n.sample(u * n.period, v * n.period) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def make_noises(seed, base_period, octaves):
    return [TileNoise(seed + i * 101, base_period * (2 ** i)) for i in range(octaves)]


def clamp8(v):
    return max(0, min(255, int(round(v))))


def build(name, fn):
    rows = []
    for y in range(SIZE):
        row = bytearray()
        v = y / SIZE
        for x in range(SIZE):
            u = x / SIZE
            r, g, b = fn(u, v, x, y)
            row += bytes((clamp8(r), clamp8(g), clamp8(b)))
        rows.append(bytes(row))
    path = os.path.join(OUT_DIR, name + ".png")
    write_png(path, SIZE, rows)
    print("wrote", path)


def tex_concrete():
    n = make_noises(1, 4, 5)
    fine = make_noises(7, 64, 2)
    rnd = random.Random(3)
    def fn(u, v, x, y):
        base = 150 + (fbm(n, u, v) - 0.5) * 50
        speck = (fbm(fine, u, v) - 0.5) * 28
        val = base + speck
        return (val, val * 0.99, val * 0.96)
    build("concrete", fn)


def tex_plaster():
    n = make_noises(11, 6, 4)
    def fn(u, v, x, y):
        val = 225 + (fbm(n, u, v) - 0.5) * 22
        return (val, val, val)
    build("plaster", fn)


def tex_asphalt():
    n = make_noises(21, 8, 4)
    fine = make_noises(27, 128, 1)
    def fn(u, v, x, y):
        val = 62 + (fbm(n, u, v) - 0.5) * 24 + (fbm(fine, u, v) - 0.5) * 30
        return (val, val, val * 1.04)
    build("asphalt", fn)


def tex_metal_panel():
    n = make_noises(31, 8, 3)
    scratch = make_noises(37, 64, 1)
    def fn(u, v, x, y):
        val = 128 + (fbm(n, u, v) - 0.5) * 20
        # scratches: stretch noise horizontally
        s = fbm(scratch, u * 0.1, v)
        if s > 0.72:
            val += 25
        # panel seams every 128 px
        px = x % 128
        py = y % 128
        if px < 3 or py < 3:
            val *= 0.55
        elif px < 6 or py < 6:
            val *= 0.85
        # rivets
        if ((px - 12) ** 2 + (py - 12) ** 2) < 16 or ((px - 116) ** 2 + (py - 116) ** 2) < 16:
            val *= 0.7
        return (val * 0.96, val, val * 1.08)
    build("metal_panel", fn)


def tex_wood_planks():
    grain = make_noises(41, 4, 4)
    plank_h = 64
    rnd = random.Random(5)
    plank_tint = [0.85 + rnd.random() * 0.3 for _ in range(SIZE // plank_h)]
    def fn(u, v, x, y):
        pi = y // plank_h
        py = y % plank_h
        # grain stretched along x
        g = fbm(grain, u * 0.15 + pi * 0.37, v * 6.0)
        base_r = 142 * plank_tint[pi] + (g - 0.5) * 60
        base_g = 95 * plank_tint[pi] + (g - 0.5) * 40
        base_b = 58 * plank_tint[pi] + (g - 0.5) * 25
        if py < 2 or py > plank_h - 3:
            base_r *= 0.5
            base_g *= 0.5
            base_b *= 0.5
        # plank ends offset per row
        end = (x + pi * 173) % 256
        if end < 2:
            base_r *= 0.55
            base_g *= 0.55
            base_b *= 0.55
        return (base_r, base_g, base_b)
    build("wood_planks", fn)


def tex_brick():
    n = make_noises(51, 16, 3)
    bw, bh = 64, 32
    rnd = random.Random(9)
    tints = {}
    def fn(u, v, x, y):
        row = y // bh
        off = (bw // 2) if row % 2 else 0
        bx = (x + off) % bw
        by = y % bh
        key = (row, (x + off) // bw)
        if key not in tints:
            tints[key] = 0.8 + random.Random(hash(key) & 0xFFFF).random() * 0.4
        t = tints[key]
        nz = (fbm(n, u, v) - 0.5) * 30
        if bx < 4 or by < 4:
            val = 170 + nz
            return (val, val * 0.97, val * 0.92)
        return (158 * t + nz, 72 * t + nz * 0.6, 58 * t + nz * 0.5)
    build("brick", fn)


def tex_grass():
    n = make_noises(61, 16, 4)
    fine = make_noises(67, 128, 1)
    def fn(u, v, x, y):
        a = fbm(n, u, v)
        f = fbm(fine, u, v)
        r = 70 + (a - 0.5) * 40 + (f - 0.5) * 20
        g = 118 + (a - 0.5) * 50 + (f - 0.5) * 30
        b = 42 + (a - 0.5) * 20
        return (r, g, b)
    build("grass", fn)


def tex_crate():
    grain = make_noises(71, 4, 4)
    def fn(u, v, x, y):
        g = fbm(grain, u * 0.2, v * 5.0)
        r = 150 + (g - 0.5) * 50
        gg = 112 + (g - 0.5) * 35
        b = 70 + (g - 0.5) * 20
        px = x % 256
        py = y % 256
        border = px < 20 or px > 235 or py < 20 or py > 235
        if border:
            r *= 0.75; gg *= 0.75; b *= 0.75
        if abs(px - py) < 10 or abs(px - (255 - py)) < 10:
            r *= 0.8; gg *= 0.8; b *= 0.8
        if (px in range(20, 24) or px in range(232, 236) or py in range(20, 24) or py in range(232, 236)):
            r *= 0.5; gg *= 0.5; b *= 0.5
        return (r, gg, b)
    build("crate", fn)


def tex_tiles():
    n = make_noises(81, 32, 2)
    size = 64
    def fn(u, v, x, y):
        tx = x % size
        ty = y % size
        nz = (fbm(n, u, v) - 0.5) * 16
        if tx < 3 or ty < 3:
            val = 90 + nz
            return (val, val, val)
        tile = ((x // size) + (y // size)) % 2
        val = (205 if tile else 190) + nz
        return (val, val * 1.0, val * 0.97)
    build("tiles", fn)


def tex_roof():
    n = make_noises(91, 16, 3)
    def fn(u, v, x, y):
        nz = (fbm(n, u, v) - 0.5) * 30
        py = y % 32
        val = 95 + nz
        if py < 3:
            val *= 0.6
        return (val * 0.85, val * 0.7, val * 0.65)
    build("roof_shingles", fn)


def tex_hull():
    n = make_noises(101, 8, 3)
    def fn(u, v, x, y):
        nz = (fbm(n, u, v) - 0.5) * 18
        val = 232 + nz
        px = x % 256
        py = y % 128
        if py < 3:
            val *= 0.7
        if px % 32 == 8 and py in (12, 116):
            val *= 0.75
        return (val, val, val * 1.02)
    build("ship_hull", fn)


def tex_water():
    n = make_noises(111, 8, 4)
    def fn(u, v, x, y):
        a = fbm(n, u, v)
        return (20 + a * 30, 70 + a * 60, 110 + a * 70)
    build("water", fn)


def tex_dirt():
    n = make_noises(121, 8, 5)
    def fn(u, v, x, y):
        a = fbm(n, u, v)
        return (110 + (a - 0.5) * 50, 85 + (a - 0.5) * 40, 60 + (a - 0.5) * 30)
    build("dirt", fn)


def tex_rubber():
    n = make_noises(131, 64, 2)
    def fn(u, v, x, y):
        a = fbm(n, u, v)
        val = 36 + (a - 0.5) * 16
        return (val, val, val)
    build("rubber", fn)


ALL = [tex_concrete, tex_plaster, tex_asphalt, tex_metal_panel, tex_wood_planks, tex_brick,
       tex_grass, tex_crate, tex_tiles, tex_roof, tex_hull, tex_water, tex_dirt, tex_rubber]

if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    only = sys.argv[1:]
    for fn in ALL:
        if only and fn.__name__.replace("tex_", "") not in only:
            continue
        fn()
