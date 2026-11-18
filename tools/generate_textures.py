"""Generates tileable PBR texture sets (albedo, normal, roughness) as PNG files with numpy + Pillow.

Run from the project root:  python3 tools/generate_textures.py
Output: assets/textures/<name>.png, <name>_n.png (normal, OpenGL convention), <name>_r.png (roughness)
Everything is procedural (own noise, cracks, grime, seams) - no external assets.
"""
import os
import numpy as np
from PIL import Image

SIZE = 512
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "textures")
rng = np.random.default_rng(20240607)


def fbm(octaves=5, base=4, persistence=0.55, seed=None):
    """Tileable fractal noise 0..1 (random-phase FFT synthesis: periodic by construction)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    total = np.zeros((SIZE, SIZE))
    freq = np.fft.fftfreq(SIZE) * SIZE
    fx, fy = np.meshgrid(freq, freq)
    radius = np.sqrt(fx * fx + fy * fy)
    radius[0, 0] = 1.0
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        f0 = base * (2 ** o)
        spectrum = np.exp(-((radius - f0) ** 2) / (2 * (f0 * 0.45) ** 2))
        phase = np.fft.fft2(r.standard_normal((SIZE, SIZE)))
        layer = np.real(np.fft.ifft2(phase * spectrum))
        layer = (layer - layer.mean()) / (layer.std() + 1e-9)
        total += layer * amp
        norm += amp
        amp *= persistence
    total /= norm
    return np.clip(total * 0.28 + 0.5, 0.0, 1.0)


def noise(base, octaves=1, seed=None):
    return fbm(octaves, base, 0.5, seed)


def grid_lines(n_x, n_y, width, offset_rows=False):
    """Mask (0..1) of grid seams, tileable; with offset_rows the vertical seams shift every second row (bricks)."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    out = np.zeros((SIZE, SIZE))
    ph = SIZE / n_y
    row = (y // ph).astype(int)
    fy = (y % ph)
    out = np.maximum(out, (fy < width) | (fy > ph - width))
    pw = SIZE / n_x
    shift = np.where(row % 2 == 1, pw * 0.5, 0.0) if offset_rows else 0.0
    fx = (x + shift) % pw
    out = np.maximum(out, ((fx < width) | (fx > pw - width)).astype(float))
    return out.astype(float)


def cells(n_x, n_y, offset_rows=False):
    """Index image: a random value per cell (brick / tile / plank)."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    ph = SIZE / n_y
    row = (y // ph).astype(int)
    pw = SIZE / n_x
    shift = np.where(row % 2 == 1, pw * 0.5, 0.0) if offset_rows else 0.0
    col = ((x + shift) // pw).astype(int) % n_x
    table = rng.random((n_y, n_x))
    return table[row % n_y, col]


def cracks(count, length=90, width=1.4, seed=1):
    """Thin, branching, tileable crack mask 0..1."""
    r = np.random.default_rng(seed)
    img = np.zeros((SIZE, SIZE))
    for _ in range(count):
        x, y = r.random() * SIZE, r.random() * SIZE
        ang = r.random() * np.pi * 2
        for step in range(int(length * (0.5 + r.random()))):
            ang += r.normal(0, 0.28)
            x += np.cos(ang) * 2.0
            y += np.sin(ang) * 2.0
            w = width * (1.0 - step / (length * 1.6))
            xi, yi = int(x) % SIZE, int(y) % SIZE
            rr = max(1, int(w + 0.5))
            for dy in range(-rr, rr + 1):
                for dx in range(-rr, rr + 1):
                    if dx * dx + dy * dy <= rr * rr:
                        img[(yi + dy) % SIZE, (xi + dx) % SIZE] = 1.0
            if r.random() < 0.012:
                ang += r.choice([-1, 1]) * r.uniform(0.5, 1.1) # a branch turns away
    return img


def scratches(count, seed=3, length=60):
    r = np.random.default_rng(seed)
    img = np.zeros((SIZE, SIZE))
    for _ in range(count):
        x, y = r.random() * SIZE, r.random() * SIZE
        ang = r.normal(0.0, 0.5) + (np.pi / 2 if r.random() < 0.3 else 0.0)
        for _s in range(int(length * (0.4 + r.random()))):
            x += np.cos(ang)
            y += np.sin(ang)
            img[int(y) % SIZE, int(x) % SIZE] = max(img[int(y) % SIZE, int(x) % SIZE], 0.4 + 0.6 * r.random())
    return img


def blur(a, passes=1):
    for _ in range(passes):
        a = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    return a


def speckle(density, seed=5):
    r = np.random.default_rng(seed)
    return (r.random((SIZE, SIZE)) < density).astype(float)


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def col(r, g, b):
    return np.array([r, g, b], dtype=float)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-dx, dy, np.ones_like(h)], -1) # +Y up (OpenGL)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def save(name, albedo, height, rough, nstrength=6.0):
    os.makedirs(OUT_DIR, exist_ok=True)
    Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT_DIR, name + ".png"), optimize=True)
    Image.fromarray((normal_from_height(blur(height), nstrength) * 255).astype(np.uint8)).save(os.path.join(OUT_DIR, name + "_n.png"), optimize=True)
    Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT_DIR, name + "_r.png"), optimize=True)
    print("wrote", name)


# ----------------------------------------------------------------------------- materials

def asphalt():
    h = fbm(5, 3, 0.6) * 0.5 + speckle(0.35, 11) * 0.25 + blur(speckle(0.2, 12)) * 0.4
    patches = (noise(2, 1, 7) > 0.62).astype(float)
    cr = cracks(7, 110, 1.3, 21)
    base = mix(col(0.20, 0.205, 0.215), col(0.12, 0.125, 0.135), h)
    base = mix(base, base * 1.18, patches * 0.7) # lighter repair patches
    base = mix(base, col(0.04, 0.04, 0.045), cr * 0.9)
    grit = speckle(0.05, 13)
    base = mix(base, col(0.5, 0.5, 0.48), grit * 0.35)
    wear = noise(4, 3, 14)
    base = mix(base, col(0.26, 0.255, 0.25), np.clip(wear - 0.55, 0, 1) * 1.5) # worn track lines
    rough = 0.82 + 0.15 * fbm(4, 8, 0.5) - 0.12 * np.clip(wear - 0.55, 0, 1) * 3
    save("asphalt", base, h - cr * 0.6, rough, 5.0)


def concrete():
    h = fbm(6, 3, 0.55)
    pores = speckle(0.012, 31)
    pores = blur(pores)
    stain = fbm(3, 2, 0.6, seed=32)
    base = mix(col(0.58, 0.575, 0.56), col(0.40, 0.395, 0.385), h * 0.8 + stain * 0.5 - 0.3)
    base = mix(base, col(0.28, 0.27, 0.26), np.clip(pores * 6, 0, 1) * 0.8)
    streak = fbm(3, 14, 0.5, seed=33)
    streak_v = np.repeat(streak[:1, :], SIZE, axis=0) * 0.5 + 0.5
    base *= (0.9 + 0.12 * streak_v)[..., None]
    seams = grid_lines(1, 1, 2.0)
    base = mix(base, col(0.22, 0.215, 0.21), seams * 0.85)
    cr = cracks(4, 80, 1.1, 34)
    base = mix(base, col(0.12, 0.12, 0.12), cr * 0.9)
    holes = np.zeros((SIZE, SIZE))
    for hx in (SIZE // 4, 3 * SIZE // 4):
        for hy in (SIZE // 4, 3 * SIZE // 4):
            yy, xx = np.mgrid[0:SIZE, 0:SIZE]
            holes = np.maximum(holes, (((xx - hx) ** 2 + (yy - hy) ** 2) < 25).astype(float))
    base = mix(base, col(0.18, 0.18, 0.18), holes * 0.8)
    save("concrete", base, h * 0.6 - seams * 0.8 - cr * 0.5 - holes * 0.6 - pores * 0.8, 0.9 + 0.08 * h - 0.1 * seams, 7.0)


def brick():
    n_x, n_y = 8, 24
    cell = cells(n_x, n_y, True)
    mortar = grid_lines(n_x, n_y, 2.2, True)
    h = fbm(5, 6, 0.6)
    reds = [col(0.55, 0.22, 0.15), col(0.48, 0.19, 0.13), col(0.62, 0.30, 0.2), col(0.40, 0.16, 0.12), col(0.58, 0.26, 0.17)]
    idx = (cell * len(reds)).astype(int) % len(reds)
    base = np.zeros((SIZE, SIZE, 3))
    for i, c in enumerate(reds):
        base[idx == i] = c
    base *= (0.85 + 0.3 * cell)[..., None] * (0.88 + 0.22 * h)[..., None]
    soot = fbm(3, 3, 0.6, seed=41)
    base = mix(base, col(0.12, 0.09, 0.08), np.clip(soot - 0.55, 0, 1) * 1.6)
    base = mix(base, col(0.66, 0.63, 0.58) * (0.8 + 0.3 * h)[..., None], mortar)
    chip = blur(speckle(0.01, 42), 2)
    base = mix(base, col(0.3, 0.14, 0.1), np.clip(chip * 8, 0, 1) * 0.6)
    save("brick", base, (h * 0.5 - mortar * 1.2) + cell * 0.12, 0.88 + 0.1 * h + 0.05 * mortar, 8.0)


def plaster():
    h = fbm(6, 3, 0.55)
    mott = fbm(3, 2, 0.6, seed=51)
    base = mix(col(0.82, 0.76, 0.66), col(0.70, 0.64, 0.55), mott * 0.9 + h * 0.3 - 0.2)
    water = fbm(3, 12, 0.5, seed=52)
    wv = np.repeat(water[:1, :], SIZE, axis=0)
    base *= (0.92 + 0.1 * wv)[..., None]
    bottom = np.linspace(0, 1, SIZE)[:, None] ** 3
    base = mix(base, col(0.38, 0.33, 0.28), bottom * 0.45 * (0.5 + noise(6, 2, 53)))
    cr = cracks(5, 70, 0.9, 54)
    base = mix(base, col(0.2, 0.17, 0.14), cr * 0.9)
    peel = (noise(3, 2, 55) > 0.72).astype(float)
    base = mix(base, col(0.52, 0.28, 0.2), blur(peel, 2) * 0.55) # plaster chipped down to the brick
    save("plaster", base, h * 0.7 - cr * 0.6 - peel * 0.5, 0.86 + 0.1 * h, 6.0)


def metal_panel():
    n = 4
    mseam = grid_lines(n, n, 2.0)
    h = fbm(4, 4, 0.5)
    sc = scratches(260, 61)
    base = mix(col(0.40, 0.43, 0.47), col(0.30, 0.32, 0.36), h)
    cell = cells(n, n)
    base *= (0.9 + 0.2 * cell)[..., None]
    base = mix(base, col(0.62, 0.64, 0.66), sc * 0.5)
    rust = (fbm(4, 4, 0.6, seed=62) - 0.5) * 3 + 0.2
    edges = np.clip(mseam * 3 + blur(mseam, 6) * 4, 0, 1)
    base = mix(base, col(0.42, 0.2, 0.1), np.clip(rust, 0, 1) * (0.25 + 0.5 * edges))
    base = mix(base, col(0.12, 0.13, 0.15), mseam * 0.8)
    rivets = np.zeros((SIZE, SIZE))
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    step = SIZE // (n * 4)
    for cy in range(8, SIZE, step):
        for cx in (10, SIZE // n - 10):
            for px in range(cx, SIZE, SIZE // n):
                rivets = np.maximum(rivets, (((xx - px) ** 2 + (yy - cy) ** 2) < 7).astype(float))
    base = mix(base, col(0.55, 0.57, 0.6), rivets * 0.6)
    rough = 0.42 + 0.25 * h + 0.3 * np.clip(rust, 0, 1) - 0.15 * sc
    save("metal_panel", base, h * 0.3 - mseam * 0.9 + rivets * 0.8 - sc * 0.15, rough, 6.0)


def wood_planks():
    n = 8
    cell = cells(n, 1)
    gaps = grid_lines(n, 1, 1.5) # vertical seams = plank joints; planks run along Y
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    plank = (xx // (SIZE // n)).astype(int)
    grain = fbm(4, 10, 0.5, seed=71)
    grain2 = noise(24, 1, 72)
    # stretched grain: noise sampled along the plank
    stretched = np.roll(fbm(4, 40, 0.5, seed=73), 3, 0)
    stretched = np.repeat(stretched[::8, :], 8, axis=0) * 0.5 + 0.5 * grain
    tones = [col(0.50, 0.33, 0.18), col(0.45, 0.29, 0.15), col(0.56, 0.38, 0.21), col(0.40, 0.26, 0.14)]
    base = np.zeros((SIZE, SIZE, 3))
    for i, c in enumerate(tones):
        base[(plank % len(tones)) == i] = c
    base *= (0.8 + 0.4 * stretched)[..., None] * (0.9 + 0.2 * cell)[..., None]
    knots = np.zeros((SIZE, SIZE))
    for _ in range(5):
        kx, ky = rng.integers(0, SIZE), rng.integers(0, SIZE)
        knots = np.maximum(knots, np.clip(1 - np.sqrt(((xx - kx) ** 2) / 90 + ((yy - ky) ** 2) / 260), 0, 1))
    base = mix(base, col(0.2, 0.12, 0.06), knots * 0.8)
    base = mix(base, col(0.08, 0.06, 0.04), gaps * 0.9)
    wear = fbm(3, 3, 0.6, seed=74)
    base = mix(base, col(0.55, 0.52, 0.47), np.clip(wear - 0.6, 0, 1) * 1.2)
    save("wood_planks", base, stretched * 0.4 - gaps * 0.9 + knots * 0.3, 0.62 + 0.25 * stretched, 6.0)


def roof_shingles():
    n_x, n_y = 8, 20
    cell = cells(n_x, n_y, True)
    seam = grid_lines(n_x, n_y, 1.8, True)
    h = fbm(4, 6, 0.6)
    tones = [col(0.30, 0.25, 0.23), col(0.24, 0.2, 0.19), col(0.36, 0.28, 0.24), col(0.21, 0.19, 0.2)]
    idx = (cell * len(tones)).astype(int) % len(tones)
    base = np.zeros((SIZE, SIZE, 3))
    for i, c in enumerate(tones):
        base[idx == i] = c
    base *= (0.85 + 0.3 * h)[..., None]
    moss = fbm(3, 3, 0.6, seed=81)
    base = mix(base, col(0.18, 0.26, 0.14), np.clip(moss - 0.62, 0, 1) * 1.4)
    base = mix(base, col(0.06, 0.05, 0.05), seam * 0.8)
    gran = speckle(0.08, 82)
    base = mix(base, col(0.5, 0.48, 0.45), gran * 0.25)
    save("roof_shingles", base, h * 0.4 - seam * 0.9 + cell * 0.15, 0.9 + 0.08 * h, 7.0)


def dirt():
    h = fbm(6, 4, 0.6)
    base = mix(col(0.40, 0.31, 0.21), col(0.25, 0.19, 0.13), h)
    pebbles = blur(speckle(0.02, 91), 1)
    base = mix(base, col(0.52, 0.48, 0.42), np.clip(pebbles * 5, 0, 1) * 0.7)
    dry = fbm(3, 3, 0.6, seed=92)
    base = mix(base, col(0.55, 0.44, 0.3), np.clip(dry - 0.55, 0, 1) * 1.4)
    tracks = np.clip(np.sin(np.linspace(0, np.pi * 2 * 3, SIZE))[None, :] * 0.5 + 0.5, 0, 1) * 0.12
    base *= (1.0 - tracks[..., None])
    save("dirt", base, h * 0.8 + pebbles * 0.8, 0.95 + 0.05 * h, 5.0)


def grass():
    h = fbm(6, 4, 0.6)
    blades = noise(60, 1, 101) * 0.6 + noise(110, 1, 102) * 0.4
    base = mix(col(0.17, 0.30, 0.09), col(0.31, 0.46, 0.14), blades * 0.8 + h * 0.3 - 0.1)
    dry = fbm(4, 3, 0.6, seed=103)
    base = mix(base, col(0.5, 0.45, 0.2), np.clip(dry - 0.55, 0, 1) * 1.1)
    soil = fbm(3, 5, 0.6, seed=104)
    base = mix(base, col(0.28, 0.2, 0.12), np.clip(soil - 0.66, 0, 1) * 1.5)
    base *= (0.8 + 0.4 * blades)[..., None]
    save("grass", base, blades * 0.8, 0.98 + 0.02 * h, 4.0)


def crate():
    h = fbm(4, 8, 0.5)
    n = 4
    slats = grid_lines(1, n, 2.0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    grain = np.repeat(fbm(3, 36, 0.5, seed=111)[::8, :], 8, axis=0)
    base = mix(col(0.55, 0.38, 0.2), col(0.38, 0.25, 0.13), grain * 0.9 + h * 0.3 - 0.1)
    frame = ((xx < 40) | (xx > SIZE - 40) | (yy < 40) | (yy > SIZE - 40)).astype(float)
    base = mix(base, base * 0.82, frame)
    edge = ((np.abs(xx - 40) < 3) | (np.abs(xx - (SIZE - 40)) < 3) | (np.abs(yy - 40) < 3) | (np.abs(yy - (SIZE - 40)) < 3)).astype(float)
    base = mix(base, col(0.12, 0.08, 0.05), edge * 0.8)
    base = mix(base, col(0.12, 0.08, 0.05), slats * 0.8)
    nails = np.zeros((SIZE, SIZE))
    for cx in (20, SIZE - 20):
        for cy in (20, SIZE - 20, SIZE // 2):
            nails = np.maximum(nails, (((xx - cx) ** 2 + (yy - cy) ** 2) < 12).astype(float))
    base = mix(base, col(0.5, 0.5, 0.52), nails * 0.7)
    sc = scratches(120, 112)
    base = mix(base, col(0.7, 0.6, 0.45), sc * 0.25)
    save("crate", base, grain * 0.4 - edge * 0.7 - slats * 0.7 + nails * 0.6, 0.72 + 0.2 * grain, 6.0)


def rubber():
    h = fbm(4, 16, 0.5) * 0.5 + speckle(0.3, 121) * 0.3
    base = mix(col(0.07, 0.07, 0.075), col(0.13, 0.13, 0.14), h)
    save("rubber", base, h, 0.88 + 0.1 * h, 4.0)


def tiles():
    n = 4
    cell = cells(n, n)
    grout = grid_lines(n, n, 2.5)
    h = fbm(4, 8, 0.5)
    base = mix(col(0.62, 0.61, 0.58), col(0.5, 0.5, 0.48), cell)
    base *= (0.9 + 0.15 * h)[..., None]
    grime = fbm(4, 4, 0.6, seed=131)
    base = mix(base, col(0.2, 0.19, 0.17), np.clip(grime - 0.5, 0, 1) * 1.1 * (0.4 + grout * 0.6))
    base = mix(base, col(0.15, 0.15, 0.14), grout * 0.9)
    cr = cracks(3, 60, 1.0, 132)
    base = mix(base, col(0.1, 0.1, 0.1), cr * 0.8)
    save("tiles", base, h * 0.2 - grout * 1.0 - cr * 0.4, 0.4 + 0.35 * grime + 0.3 * grout, 6.0)


def ship_hull():
    n = 3
    seam = grid_lines(n, n, 2.5)
    h = fbm(4, 4, 0.5)
    cell = cells(n, n)
    paints = [col(0.20, 0.27, 0.34), col(0.23, 0.3, 0.37), col(0.18, 0.24, 0.31)]
    idx = (cell * 3).astype(int) % 3
    base = np.zeros((SIZE, SIZE, 3))
    for i, c in enumerate(paints):
        base[idx == i] = c
    base *= (0.85 + 0.25 * h)[..., None]
    rust = fbm(5, 4, 0.6, seed=141)
    bottom = (np.linspace(0, 1, SIZE)[:, None] ** 2)
    rust_m = np.clip((rust - 0.52) * 3.0 + bottom * 0.5 - 0.1, 0, 1)
    base = mix(base, col(0.45, 0.2, 0.09), rust_m * 0.8)
    chips = (fbm(4, 10, 0.6, seed=142) > 0.64).astype(float)
    base = mix(base, col(0.5, 0.51, 0.52), chips * 0.5)
    base = mix(base, col(0.08, 0.1, 0.12), seam * 0.8)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    rivets = np.zeros((SIZE, SIZE))
    for cy in (12, SIZE // n - 12):
        for py in range(cy, SIZE, SIZE // n):
            for px in range(10, SIZE, 24):
                rivets = np.maximum(rivets, (((xx - px) ** 2 + (yy - py) ** 2) < 6).astype(float))
    base = mix(base, base * 1.4, rivets * 0.6)
    save("ship_hull", base, h * 0.3 - seam * 0.9 + rivets * 0.7 - rust_m * 0.2, 0.42 + 0.45 * rust_m + 0.15 * h, 6.0)


def water():
    h = fbm(5, 6, 0.55) * 0.6 + fbm(4, 14, 0.5, seed=151) * 0.4
    base = mix(col(0.06, 0.2, 0.32), col(0.12, 0.38, 0.5), h)
    foam = np.clip((fbm(4, 10, 0.6, seed=152) - 0.66) * 4, 0, 1)
    base = mix(base, col(0.75, 0.85, 0.9), foam * 0.35)
    save("water", base, h, np.full((SIZE, SIZE), 0.10) + 0.08 * foam, 9.0)


if __name__ == "__main__":
    for fn in (asphalt, concrete, brick, plaster, metal_panel, wood_planks, roof_shingles, dirt, grass, crate, rubber, tiles, ship_hull, water):
        fn()
