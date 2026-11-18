"""Synthesises all sound effects as 16-bit mono WAV files (pure Python, no deps).

Run from the project root:  py -3 tools/generate_audio.py
Output: assets/audio/sfx/*.wav
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "audio", "sfx")
rnd = random.Random(1234)


def write_wav(name, samples, gain=0.9):
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = gain / peak
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print("wrote", path)


def silence(seconds):
    return [0.0] * int(seconds * SR)


def noise(seconds):
    return [rnd.uniform(-1, 1) for _ in range(int(seconds * SR))]


def sine(freq, seconds, phase=0.0):
    return [math.sin(2 * math.pi * freq * (i / SR) + phase) for i in range(int(seconds * SR))]


def sweep(f0, f1, seconds):
    out = []
    n = int(seconds * SR)
    ph = 0.0
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * t
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph))
    return out


def env_exp(samples, decay):
    """Exponential decay envelope, decay in seconds (time constant)."""
    return [s * math.exp(-i / (decay * SR)) for i, s in enumerate(samples)]


def env_adsr(samples, a, d, s_level, r):
    n = len(samples)
    out = []
    an, dn, rn = int(a * SR), int(d * SR), int(r * SR)
    for i, s in enumerate(samples):
        if i < an:
            e = i / max(1, an)
        elif i < an + dn:
            e = 1 - (1 - s_level) * (i - an) / max(1, dn)
        elif i < n - rn:
            e = s_level
        else:
            e = s_level * (n - i) / max(1, rn)
        out.append(s * e)
    return out


def lowpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out = []
    y = 0.0
    for s in samples:
        y += alpha * (s - y)
        out.append(y)
    return out


def highpass(samples, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    alpha = rc / (rc + dt)
    out = []
    y = 0.0
    prev = 0.0
    for s in samples:
        y = alpha * (y + s - prev)
        prev = s
        out.append(y)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def gain(samples, g):
    return [s * g for s in samples]


def concat(*tracks):
    out = []
    for t in tracks:
        out.extend(t)
    return out


def delay(samples, seconds):
    return silence(seconds) + samples


def soft_clip(samples, drive=2.0):
    return [math.tanh(s * drive) for s in samples]


# ----------------------------------------------------------------------------- gun shots

def gunshot(length, thump_freq, thump_decay, crack_decay, body_cut, crack_gain=1.0, tail=0.15):
    thump = env_exp(sine(thump_freq, length), thump_decay)
    thump = mix(thump, env_exp(sweep(thump_freq * 2.5, thump_freq * 0.6, length), thump_decay * 0.5))
    crack = env_exp(highpass(noise(length), 1800), crack_decay)
    body = env_exp(lowpass(noise(length), body_cut), thump_decay * 1.4)
    tail_n = env_exp(lowpass(noise(length), 900), tail)
    shot = mix(gain(thump, 1.1), gain(crack, crack_gain), gain(body, 0.9), gain(tail_n, 0.35))
    return soft_clip(shot, 2.5)


def make_guns():
    write_wav("shot_ak47", gunshot(0.45, 85, 0.07, 0.03, 2500, 1.0, 0.18))
    write_wav("shot_mp5", gunshot(0.3, 130, 0.045, 0.02, 3500, 0.9, 0.1))
    write_wav("shot_shotgun", gunshot(0.7, 60, 0.12, 0.05, 1800, 1.2, 0.3))
    write_wav("shot_pistol", gunshot(0.35, 110, 0.05, 0.025, 3000, 1.0, 0.12))
    # distant versions for other players' shots
    write_wav("shot_ak47_far", lowpass(gunshot(0.6, 70, 0.1, 0.02, 1200, 0.4, 0.3), 1500), 0.6)
    write_wav("shot_mp5_far", lowpass(gunshot(0.4, 110, 0.06, 0.015, 1500, 0.4, 0.2), 1800), 0.5)
    write_wav("shot_shotgun_far", lowpass(gunshot(0.9, 55, 0.15, 0.03, 1000, 0.4, 0.4), 1200), 0.7)
    write_wav("shot_pistol_far", lowpass(gunshot(0.45, 100, 0.07, 0.015, 1500, 0.4, 0.2), 1600), 0.5)


# ----------------------------------------------------------------------------- mechanical

def click(freq=1500, length=0.06, decay=0.012, noise_gain=0.6):
    ring = env_exp(sine(freq, length), decay)
    n = env_exp(highpass(noise(length), 900), decay * 0.6)
    return mix(ring, gain(n, noise_gain))


def slide(length=0.12, cutoff=2500):
    return env_adsr(lowpass(noise(length), cutoff), 0.01, 0.04, 0.5, 0.05)


def make_mechanical():
    mag_out = concat(click(900, 0.08, 0.02), silence(0.05), gain(slide(0.1, 1800), 0.5))
    mag_in = concat(gain(slide(0.08, 2200), 0.5), click(1300, 0.07, 0.015), silence(0.04), click(2200, 0.05, 0.01, 0.3))
    write_wav("reload_mag_out", mag_out, 0.7)
    write_wav("reload_mag_in", mag_in, 0.8)
    write_wav("reload_bolt", concat(click(700, 0.08, 0.02), silence(0.06), click(1100, 0.08, 0.02)), 0.8)
    write_wav("shell_insert", concat(click(1900, 0.05, 0.012, 0.4), silence(0.02), click(2400, 0.04, 0.008, 0.3)), 0.6)
    write_wav("pump", concat(gain(slide(0.1, 3000), 0.7), click(800, 0.06, 0.02), silence(0.05), gain(slide(0.08, 3000), 0.7), click(1000, 0.06, 0.018)), 0.85)
    write_wav("weapon_switch", concat(gain(slide(0.07, 2500), 0.5), click(1000, 0.06, 0.015, 0.5)), 0.6)
    write_wav("empty_click", click(2600, 0.04, 0.006, 0.4), 0.5)
    write_wav("grenade_pin", click(3200, 0.05, 0.01, 0.5), 0.5)
    whoosh = env_adsr(lowpass(highpass(noise(0.35), 400), 1800), 0.08, 0.1, 0.6, 0.15)
    write_wav("grenade_throw", whoosh, 0.6)
    write_wav("grenade_bounce", mix(click(500, 0.09, 0.03, 0.5), env_exp(sine(180, 0.09), 0.03)), 0.6)


# ----------------------------------------------------------------------------- movement

def footstep(seed, cutoff, length=0.09):
    r = random.Random(seed)
    n = [r.uniform(-1, 1) for _ in range(int(length * SR))]
    n = lowpass(n, cutoff)
    n = env_exp(n, 0.02)
    thump = env_exp(sine(120, length), 0.015)
    return mix(n, gain(thump, 0.5))


def make_movement():
    for i in range(4):
        write_wav("footstep_%d" % (i + 1), footstep(100 + i, 900 + i * 150), 0.55)
    write_wav("jump", mix(env_exp(lowpass(noise(0.12), 1200), 0.03), env_exp(sine(140, 0.12), 0.02)), 0.5)
    write_wav("land", mix(env_exp(lowpass(noise(0.18), 700), 0.05), env_exp(sine(90, 0.18), 0.05)), 0.7)


# ----------------------------------------------------------------------------- feedback

def make_feedback():
    make_hit_feedback()
    hurt = env_exp(lowpass(mix(noise(0.2), gain(sine(160, 0.2), 1.5)), 800), 0.06)
    write_wav("hurt", hurt, 0.6)
    death = env_exp(lowpass(mix(noise(0.6), gain(sweep(200, 60, 0.6), 1.5)), 600), 0.2)
    write_wav("death", death, 0.8)
    impact = mix(env_exp(highpass(noise(0.08), 1500), 0.01), env_exp(sine(900, 0.08), 0.01))
    write_wav("bullet_impact", impact, 0.5)
    ricochet = env_exp(sweep(3000, 800, 0.25), 0.07)
    write_wav("ricochet", ricochet, 0.35)
    boom = mix(
        env_exp(lowpass(noise(1.8), 400), 0.35),
        env_exp(sweep(120, 35, 1.8), 0.3),
        env_exp(highpass(noise(1.8), 2000), 0.04),
        delay(env_exp(lowpass(noise(1.2), 2500), 0.4), 0.05),
    )
    write_wav("explosion", soft_clip(boom, 3.0), 0.95)


# ----------------------------------------------------------------------------- UI / round

def tone(freq, length, kind="sine"):
    base = sine(freq, length)
    base = mix(base, gain(sine(freq * 2, length), 0.25), gain(sine(freq * 3, length), 0.1))
    return env_adsr(base, 0.01, 0.05, 0.7, 0.08)


def make_hit_feedback():
    """Hit / headshot / kill confirmation in the style of modern shooters (CoD, Apex): short, dry,
    punchy, built from filtered noise bursts and a low thump. No ringing partials (that sounds like
    hitting a metal tank). Own random generator so the other sounds stay byte-identical."""
    local = random.Random(4711)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def band(seconds, lo, hi, decay):
        """Noise burst limited to lo..hi Hz with an exponential decay (a 'tap' or 'crack')."""
        return env_exp(lowpass(highpass(nz(seconds), lo), hi), decay)

    def thump(length, f0, f1, decay):
        return env_exp(sweep(f0, f1, length), decay)

    def body(length, cutoff, decay):
        return env_exp(lowpass(nz(length), cutoff), decay)

    def metal(freqs, length, decay, amps=None):
        """Short metallic impulse: inharmonic partials (thin plate / casing) with a fast decay.
        All partials sit above 2 kHz, so there is no hollow 'tank' body."""
        amps = amps or [1.0] * len(freqs)
        parts = [gain(env_exp(sine(f, length), decay * (1.0 - 0.12 * k)), a) for k, (f, a) in enumerate(zip(freqs, amps))]
        return mix(*parts)

    def tick(f0, scale=1.0):
        """Dry transient: bright noise crack + metal click, f0 shifts the whole colour."""
        return mix(
            gain(band(0.03, 2800 * f0, 11000, 0.0045), 1.2 * scale),
            gain(band(0.012, 6500 * f0, 14000, 0.0022), 0.8 * scale),
            gain(metal([3150 * f0, 4780 * f0, 7420 * f0], 0.05, 0.011, [1.0, 0.7, 0.45]), 0.55 * scale),
        )

    # normal hit: very short, dry, metallic snap with a clean attack and a tiny punch below it
    hit = mix(
        tick(1.0),
        gain(thump(0.035, 260, 120, 0.009), 0.55),
        gain(body(0.03, 2200, 0.007), 0.4),
    )
    write_wav("hitmarker", soft_clip(hit, 2.4), 0.9)

    # headshot hit: sharper and higher, an instantly recognisable double snap (second one higher)
    head_a = mix(tick(1.25, 1.0), gain(thump(0.04, 300, 130, 0.01), 0.6))
    head_b = mix(tick(1.7, 1.0), gain(metal([5200, 8100, 11800], 0.08, 0.02, [1.0, 0.6, 0.35]), 0.5))
    head = mix(head_a, delay(gain(head_b, 0.95), 0.042))
    write_wav("hitmarker_headshot", soft_clip(head, 2.4), 0.96)

    # kill: the reward - heavy impact, big metallic clang (higher, ringing for ~0.2 s), crack and a short sub punch
    clang = metal([2480, 3770, 5650, 8300, 11200], 0.34, 0.085, [1.0, 0.85, 0.7, 0.5, 0.3])
    kill = mix(
        tick(1.1, 1.15),
        gain(clang, 0.95),
        gain(delay(metal([3300, 5100, 7700], 0.25, 0.06, [1.0, 0.7, 0.5]), 0.03), 0.6),
        gain(thump(0.16, 180, 55, 0.055), 1.25),
        gain(body(0.12, 1700, 0.035), 0.7),
    )
    write_wav("kill_confirm", soft_clip(kill, 2.8), 0.98)

    # headshot kill: the best of all - double snap into a bigger, brighter clang, a third crack and extra punch
    clang_h = metal([2900, 4400, 6600, 9400, 12500], 0.45, 0.11, [1.0, 0.9, 0.75, 0.55, 0.35])
    kill_h = mix(
        tick(1.3, 1.2),
        gain(delay(tick(1.7, 1.0), 0.04), 0.95),
        gain(delay(tick(2.1, 0.9), 0.085), 0.85),
        gain(delay(clang_h, 0.02), 1.0),
        gain(delay(metal([3700, 5700, 8600], 0.32, 0.07, [1.0, 0.7, 0.5]), 0.07), 0.7),
        gain(thump(0.22, 200, 50, 0.075), 1.45),
        gain(body(0.14, 1900, 0.04), 0.8),
    )
    write_wav("kill_headshot", soft_clip(kill_h, 3.0), 1.0)


def make_ambience():
    """Quiet ambience: seamless wind and water loops, bird/gull calls, a distant jet, own breathing.
    Own random generator, so the other sounds stay byte-identical. All files are normalised low
    (they are layered under the gameplay and played at low volume by the game)."""
    local = random.Random(2024)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def loop(samples, fade):
        """Makes `samples` loop seamlessly by cross-fading the end into the start."""
        f = int(fade * SR)
        body = samples[:-f]
        tail = samples[-f:]
        for i in range(f):
            w = i / f
            body[i] = body[i] * w + tail[i] * (1.0 - w)
        return body

    # wind: low rumble + gusts (periodic LFOs fit the loop length exactly) + a faint whistle
    length = 12.0
    raw = nz(length + 1.5)
    low = lowpass(raw, 420)
    mid = highpass(lowpass(raw, 1600), 500)
    out = []
    for i in range(len(low)):
        t = i / SR
        gust = 0.55 + 0.25 * math.sin(2 * math.pi * t / 12.0 + 1.0) + 0.2 * math.sin(2 * math.pi * t / 6.0 + 0.3)
        whistle = max(0.0, math.sin(2 * math.pi * t / 4.0 + 2.0)) ** 3
        out.append(low[i] * gust + mid[i] * 0.35 * whistle * gust)
    write_wav("amb_wind", loop(out, 1.5), 0.5)

    # water: soft lapping waves (slow swell) with small splashes
    raw = nz(length + 1.5)
    wash = lowpass(raw, 1100)
    fizz = highpass(lowpass(raw, 4500), 1800)
    out = []
    for i in range(len(wash)):
        t = i / SR
        swell = 0.5 + 0.5 * math.sin(2 * math.pi * t / 6.0)
        swell2 = 0.5 + 0.5 * math.sin(2 * math.pi * t / 4.0 + 1.3)
        out.append(wash[i] * (0.35 + 0.65 * swell) + fizz[i] * 0.25 * swell * swell2)
    write_wav("amb_water", loop(out, 1.5), 0.5)

    def chirp(f0, f1, length_s, vib=0.0, vib_rate=40.0):
        n = int(length_s * SR)
        ph = 0.0
        out = []
        for i in range(n):
            t = i / n
            f = f0 + (f1 - f0) * t + vib * math.sin(2 * math.pi * vib_rate * i / SR)
            ph += 2 * math.pi * f / SR
            env = math.sin(math.pi * t) ** 1.5
            out.append(math.sin(ph) * env + 0.25 * math.sin(2 * ph) * env)
        return out

    # birds: three short songs of different character
    song1 = concat(chirp(2900, 4300, 0.07), silence(0.06), chirp(3000, 4500, 0.07), silence(0.06), chirp(3100, 4700, 0.09))
    write_wav("amb_bird_1", song1, 0.5)
    song2 = concat(*[chirp(3300 + 400 * (k % 2), 3700 - 300 * (k % 2), 0.05, 150, 55) for k in range(7)])
    write_wav("amb_bird_2", song2, 0.5)
    song3 = concat(chirp(4600, 3500, 0.12), silence(0.09), chirp(4500, 3300, 0.14), silence(0.5), chirp(4400, 3400, 0.1))
    write_wav("amb_bird_3", song3, 0.5)
    # gull: a harsher, lower, wavering cry
    gull = mix(chirp(1500, 1050, 0.5, 70, 14), gain(chirp(3000, 2100, 0.5, 140, 14), 0.4))
    gull = [x * (0.8 + 0.2 * math.sin(2 * math.pi * 11 * i / SR)) for i, x in enumerate(gull)]
    write_wav("amb_gull", concat(gull, silence(0.05), gain(gull, 0.7)), 0.5)

    # distant jet: broadband rumble that swells and fades, with a slowly sinking pitch hum
    dur = 16.0
    raw = nz(dur)
    low = lowpass(raw, 350)
    high = highpass(lowpass(raw, 1500), 400)
    out = []
    for i in range(len(low)):
        t = i / SR
        env = math.sin(math.pi * t / dur) ** 2.5
        hum = math.sin(2 * math.pi * (95 - 18 * t / dur) * t)
        out.append(env * (low[i] * 1.0 + high[i] * 0.25 + hum * 0.05))
    write_wav("amb_plane", out, 0.45)

    # own breathing after a sprint: in (rising) and out (longer, falling), twice
    def breath_cycle(inh, exh):
        a = lowpass(highpass(nz(inh), 250), 2200)
        a = [x * math.sin(math.pi * i / len(a)) ** 1.3 * (0.6 + 0.4 * i / len(a)) for i, x in enumerate(a)]
        b = lowpass(highpass(nz(exh), 200), 1800)
        b = [x * (math.sin(math.pi * i / len(b)) ** 1.2) * (1.0 - 0.5 * i / len(b)) for i, x in enumerate(b)]
        return concat(a, silence(0.08), b, silence(0.12))
    write_wav("breath_heavy", concat(breath_cycle(0.45, 0.65), gain(breath_cycle(0.4, 0.6), 0.8)), 0.6)


def make_grenade_extra():
    """Grenade handling: cloth rustle when it is taken out and the metallic spoon 'ping' when it is released
    (the pin sound and the throw whoosh already exist). Own RNG: nothing else changes."""
    local = random.Random(31337)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    n = int(0.28 * SR)
    raw = highpass(lowpass(nz(0.28), 3200), 500)
    rustle = [raw[i] * (math.sin(math.pi * i / n) ** 1.4) * (0.6 + 0.4 * math.sin(i / SR * 70.0)) for i in range(n)]
    write_wav("grenade_draw", rustle, 0.45)
    ping = mix(
        env_exp(sine(2750, 0.25), 0.05),
        gain(env_exp(sine(4100, 0.25), 0.035), 0.5),
        gain(env_exp(highpass(nz(0.05), 3500), 0.006), 0.8),
        gain(env_exp(sweep(300, 140, 0.08), 0.02), 0.5),
    )
    write_wav("grenade_lever", ping, 0.6)


def make_slide_sound():
    """Knee slide: filtered noise swish with a fading scrape, no tonal part."""
    local = random.Random(4242)
    n = int(0.55 * SR)
    raw = [local.uniform(-1, 1) for _ in range(n)]
    low = lowpass(raw, 900)
    mid = lowpass(raw, 3200)
    out = []
    for i in range(n):
        t = i / SR
        att = min(1.0, t / 0.04)
        dec = math.exp(-t / 0.26)
        scrape = 0.5 + 0.5 * math.sin(t * 90.0 + 3.0 * math.sin(t * 17.0))
        out.append((low[i] * 1.2 + (mid[i] - low[i]) * 0.55 * scrape) * att * dec)
    write_wav("slide", out, 0.55)


def make_grenade_sounds():
    """Frag grenade: pin, throw, bounce on concrete, and a heavy explosion built from layered
    filtered noise (blast), sub bass, city echoes and scattering debris. No harsh clipping."""
    local = random.Random(777)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def lp_noise(seconds, cutoff, decay, attack=0.002):
        n = lowpass(nz(seconds), cutoff)
        out = []
        a = max(1, int(attack * SR))
        for i, s in enumerate(n):
            e = math.exp(-i / (decay * SR)) * min(1.0, (i + 1) / a)
            out.append(s * e)
        return out

    def modal(freqs, decays, gains, length):
        out = [0.0] * int(length * SR)
        for f, d, g in zip(freqs, decays, gains):
            for k, s in enumerate(env_exp(sine(f, length), d)):
                out[k] += s * g
        return out

    # explosion
    length = 3.0
    crack = gain(env_exp(highpass(nz(0.06), 1500), 0.010), 0.9)
    blast = gain(lp_noise(1.2, 1800, 0.20), 1.0)
    thud = gain(lp_noise(1.6, 520, 0.38), 1.0)
    sub = gain(mix(env_exp(sweep(88, 30, 0.9), 0.30), gain(env_exp(sweep(150, 55, 0.7), 0.22), 0.4)), 1.25)
    # long, slowly decaying rumble that swells a little at the start
    rumble_raw = lowpass(nz(length), 190)
    rumble = []
    for i, s in enumerate(rumble_raw):
        tt = i / SR
        e = min(1.0, tt / 0.06) * math.exp(-tt / 0.95)
        rumble.append(s * e * (0.85 + 0.15 * math.sin(2 * math.pi * 5.5 * tt)))
    rumble = gain(rumble, 1.3)
    # echoes between the buildings
    echoes = mix(delay(gain(lp_noise(0.8, 900, 0.16), 0.40), 0.12), delay(gain(lp_noise(0.8, 700, 0.18), 0.26), 0.27), delay(gain(lp_noise(0.8, 600, 0.2), 0.16), 0.46))
    # debris tinkling and thudding down
    debris = [0.0] * int(length * SR)
    for k in range(26):
        at = local.uniform(0.18, 1.7)
        amp = local.uniform(0.04, 0.2) * (1.0 - at / 2.2)
        piece = gain(env_exp(lowpass(highpass(nz(0.03), 900), 5000), local.uniform(0.004, 0.012)), amp)
        start = int(at * SR)
        for m, s in enumerate(piece):
            if start + m < len(debris):
                debris[start + m] += s
    for k in range(5):
        at = local.uniform(0.3, 1.4)
        piece = gain(env_exp(sweep(local.uniform(110, 190), 55, 0.1), 0.03), local.uniform(0.12, 0.25))
        start = int(at * SR)
        for m, s in enumerate(piece):
            if start + m < len(debris):
                debris[start + m] += s
    boom = mix(crack, blast, thud, sub, rumble, echoes, debris)
    boom = highpass(boom, 22)
    write_wav("explosion", soft_clip(boom, 1.15), 0.95)

    # pin: short metal ping plus a light click
    pin = mix(gain(env_exp(highpass(nz(0.03), 3000), 0.004), 0.7), gain(modal([2600, 3900], [0.05, 0.035], [0.5, 0.3], 0.18), 0.45))
    write_wav("grenade_pin", pin, 0.55)
    # bounce: a dull steel clunk on concrete
    bounce = mix(
        gain(modal([310, 640, 1080, 1700], [0.05, 0.04, 0.03, 0.02], [0.8, 0.6, 0.4, 0.25], 0.2), 0.7),
        gain(env_exp(highpass(nz(0.03), 1200), 0.006), 0.6),
        gain(env_exp(sweep(150, 70, 0.08), 0.03), 0.8),
    )
    write_wav("grenade_bounce", bounce, 0.7)


def make_reload_sounds():
    """Reload mechanics: magazine release/out/in, slap, charging handle, pistol slide, shotgun shell.
    Dry, short and mechanical (filtered noise + damped metal resonances), no tones. Own random
    generator so the other sounds stay byte-identical."""
    local = random.Random(2024)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def modal(freqs, decays, gains, length, pitch=1.0):
        out = [0.0] * int(length * SR)
        for f, d, g in zip(freqs, decays, gains):
            for k, s in enumerate(env_exp(sine(f * pitch, length), d)):
                out[k] += s * g
        return out

    def tick(freq_scale=1.0, strength=1.0, length=0.05):
        """Sharp metal tick: noise transient + short high resonance."""
        return gain(mix(
            env_exp(highpass(nz(length), 2500), 0.004),
            gain(modal([2400, 3700], [0.012, 0.008], [0.7, 0.4], length, freq_scale), 0.5),
        ), strength)

    def thunk(freq=130.0, length=0.09, strength=1.0):
        """Dull impact (plastic/steel on steel)."""
        return gain(mix(
            env_exp(sweep(freq * 1.6, freq * 0.7, length), 0.03),
            gain(env_exp(lowpass(nz(length), 1400), 0.018), 0.6),
        ), strength)

    def scrape(length, lo=700, hi=3800, peak=0.5):
        """Friction of a magazine sliding in/out: band-limited noise with a swelling envelope."""
        n = lowpass(highpass(nz(length), lo), hi)
        count = len(n)
        return [s * (math.sin(math.pi * min(1.0, i / max(1, count))) ** 0.7) * peak for i, s in enumerate(n)]

    def seq(*parts):
        """Place (time, samples) parts on a timeline."""
        total = max(int((tm * SR)) + len(sm) for tm, sm in parts)
        out = [0.0] * total
        for tm, sm in parts:
            start = int(tm * SR)
            for k, s in enumerate(sm):
                out[start + k] += s
        return out

    write_wav("reload_release", mix(tick(1.0, 1.0, 0.05), thunk(220, 0.04, 0.5)), 0.7)

    # rifle: magazine slides out of the well with a short scrape and a dull clunk when it clears
    write_wav("reload_mag_out", seq((0.0, scrape(0.13, 800, 3000, 0.45)), (0.11, thunk(120, 0.1, 0.9)), (0.11, tick(0.8, 0.35, 0.04))), 0.8)
    # rifle: new magazine slides in, then seats with a firm clack and a latch click
    write_wav("reload_mag_in", seq((0.0, scrape(0.10, 900, 3500, 0.4)), (0.095, thunk(105, 0.1, 1.1)), (0.095, tick(0.9, 0.8, 0.05)), (0.125, tick(1.15, 0.6, 0.04))), 0.9)
    # charging handle: back with a short scrape and a stop, forward with a heavy slam
    write_wav("reload_bolt", seq((0.0, scrape(0.09, 600, 2600, 0.5)), (0.085, tick(0.8, 0.6, 0.05)), (0.2, thunk(95, 0.12, 1.2)), (0.2, tick(0.75, 1.1, 0.06)), (0.215, gain(modal([1100, 1800], [0.03, 0.02], [0.6, 0.4], 0.12), 0.4))), 0.95)
    # palm slap on the magazine floor plate
    write_wav("reload_slap", mix(thunk(150, 0.06, 0.9), env_exp(lowpass(nz(0.05), 2200), 0.012)), 0.6)

    # pistol: light, higher variants
    write_wav("reload_pistol_out", seq((0.0, scrape(0.07, 1000, 3800, 0.35)), (0.06, thunk(170, 0.06, 0.7)), (0.06, tick(1.1, 0.3, 0.03))), 0.7)
    write_wav("reload_pistol_in", seq((0.0, scrape(0.06, 1000, 4000, 0.3)), (0.055, thunk(150, 0.07, 0.9)), (0.055, tick(1.25, 0.8, 0.04)), (0.08, tick(1.5, 0.45, 0.03))), 0.8)
    write_wav("reload_slide", seq((0.0, tick(0.9, 1.0, 0.05)), (0.0, thunk(190, 0.06, 0.8)), (0.02, gain(modal([1300, 2200, 3500], [0.03, 0.025, 0.015], [0.7, 0.5, 0.3], 0.14), 0.5))), 0.85)

    # shotgun shell: a double "ratsch ratsch" - the shell rasps past the shell stop into the gate (rattling ratchet
    # ticks + scrape) and bangs home with a dull clack; the carrier latch rasps and snaps back right after
    def ratchet(count, start, spacing, shrink, strength):
        """A row of fast ticks that speed up: the teeth of the ratchet."""
        parts = []
        at = start
        for i in range(count):
            parts.append((at, tick(0.85 + 0.07 * i, strength * (0.55 + 0.1 * i), 0.03)))
            at += spacing * (shrink ** i)
        return parts

    ratsch_in = seq(
        (0.0, scrape(0.085, 1100, 4300, 0.95)),
        *ratchet(4, 0.004, 0.016, 0.82, 1.1),
        (0.082, thunk(165, 0.07, 1.0)),
        (0.082, tick(0.95, 1.0, 0.05)),
        (0.084, gain(modal([1700, 2650], [0.026, 0.016], [0.6, 0.4], 0.12), 0.45)),
    )
    ratsch_latch = seq(
        (0.0, scrape(0.055, 1500, 5000, 0.75)),
        *ratchet(3, 0.003, 0.013, 0.8, 0.9),
        (0.054, tick(1.3, 0.9, 0.04)),
        (0.056, thunk(240, 0.04, 0.45)),
        (0.058, gain(modal([2100, 3300], [0.018, 0.01], [0.6, 0.4], 0.08), 0.35)),
    )
    write_wav("shell_insert", seq((0.0, ratsch_in), (0.145, ratsch_latch)), 0.85)


def make_glass_sounds():
    """Window glass: a sharp crack when it is hit, a crash with a bright shower of shards when it breaks,
    and a soft tinkle of fragments landing. Own random generator: the other sounds stay identical."""
    local = random.Random(777)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    # crack: a very short bright tick with a thin ring of the pane
    n = 0.35
    tick = env_exp(highpass(nz(n), 3000), 0.012)
    ring = [0.0] * int(n * SR)
    for f, d, g in ((4300, 0.07, 0.35), (6100, 0.05, 0.25), (2700, 0.09, 0.2)):
        for k, v in enumerate(env_exp(sine(f, n), d)):
            ring[k] += v * g
    write_wav("glass_hit", soft_clip(mix(gain(tick, 1.0), ring, gain(env_exp(sine(180, n), 0.02), 0.25)), 1.6), 0.8)

    # break: crash (noise burst) + a thump of the pane + many tiny falling tones
    n = 1.6
    crash = env_exp(highpass(nz(n), 1800), 0.16)
    body = env_exp(lowpass(nz(n), 900), 0.05)
    thud = env_exp(sweep(260, 80, n), 0.05)
    shower = [0.0] * int(n * SR)
    for _ in range(70):
        start = int(local.uniform(0.02, 1.1) * SR)
        f = local.uniform(2500, 9000)
        dur = local.uniform(0.02, 0.07)
        amp = local.uniform(0.05, 0.25) * (1.0 - start / (1.3 * SR))
        for k, v in enumerate(env_exp(sine(f, dur), dur * 0.35)):
            if start + k < len(shower):
                shower[start + k] += v * amp
    write_wav("glass_break", soft_clip(mix(gain(crash, 0.9), gain(body, 0.6), gain(thud, 0.5), shower), 2.0), 0.92)

    # tinkle: scattered light ticks (fragments landing)
    n = 1.2
    tk = [0.0] * int(n * SR)
    for i in range(26):
        start = int((0.03 * i + local.uniform(0, 0.06) + 0.02 * (i * i % 5)) * SR)
        f = local.uniform(3000, 8500)
        dur = local.uniform(0.015, 0.05)
        amp = local.uniform(0.1, 0.35) * (1.0 - i / 32.0)
        for k, v in enumerate(env_exp(sine(f, dur), dur * 0.3)):
            if start + k < len(tk):
                tk[start + k] += v * amp
    write_wav("glass_tinkle", tk, 0.6)


def make_flash_sounds():
    """Flashbang: a hard, bright crack with a deep thump and a metallic ring-out, and the tinnitus that follows it
    (a long fine whistle, its volume is driven by the game). Own random generator: the other sounds stay identical."""
    local = random.Random(4242)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    length = 1.1
    crack = env_exp(highpass(nz(length), 1400), 0.022)
    air = env_exp(nz(length), 0.012) # the first few milliseconds are pure noise
    thump = mix(env_exp(sweep(190, 42, length), 0.16), env_exp(sine(60, length), 0.2))
    ring = [0.0] * int(length * SR)
    for f, d, g in ((3200, 0.20, 0.30), (5400, 0.14, 0.22), (7900, 0.10, 0.16)):
        for k, v in enumerate(env_exp(sine(f, length), d)):
            ring[k] += v * g
    tail = mix(gain(env_exp(lowpass(nz(length), 2400), 0.30), 0.55), gain(env_exp(lowpass(nz(length), 650), 0.45), 0.6))
    bang = soft_clip(mix(gain(crack, 1.1), gain(air, 0.8), gain(thump, 1.2), ring, tail), 2.4)
    write_wav("flashbang_bang", bang, 0.96)

    # tinnitus: a high whistle with a second, slightly detuned one, a faint third and a slow wobble
    dur = 7.5
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        wob = 1.0 + 0.0035 * math.sin(2 * math.pi * 0.7 * t)
        a = math.sin(2 * math.pi * 6300 * wob * t) * 0.50
        b = math.sin(2 * math.pi * 3150 * 1.0012 * t) * 0.24
        c = math.sin(2 * math.pi * 9100 * t) * 0.10
        trem = 1.0 + 0.08 * math.sin(2 * math.pi * 2.3 * t) * math.sin(2 * math.pi * 0.31 * t)
        fade_in = min(1.0, t / 0.25)
        fade_out = min(1.0, (dur - t) / 0.6)
        out.append((a + b + c) * trem * fade_in * fade_out)
    write_wav("flash_ring", out, 0.55)


def make_sniper_sounds():
    """Sniper: a huge, ringing shot with an echo, the bolt being worked (open: lift + pull back, close: push + lock)
    and the soft optical sounds of the scope. Own random generator: the other sounds stay identical."""
    local = random.Random(9090)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def modal(freqs, decays, gains, length):
        out = [0.0] * int(length * SR)
        for f, d, g in zip(freqs, decays, gains):
            for k, v in enumerate(env_exp(sine(f, length), d)):
                out[k] += v * g
        return out

    def tick(freq_scale=1.0, strength=1.0, length=0.05):
        return gain(mix(
            env_exp(highpass(nz(length), 2500), 0.004),
            gain(modal([2400 * freq_scale, 3700 * freq_scale], [0.012, 0.008], [0.7, 0.4], length), 0.5),
        ), strength)

    def thunk(freq=130.0, length=0.09, strength=1.0):
        return gain(mix(
            env_exp(sweep(freq * 1.6, freq * 0.7, length), 0.03),
            gain(env_exp(lowpass(nz(length), 1400), 0.018), 0.6),
        ), strength)

    def scrape(length, lo=700, hi=3800, peak=0.5):
        n = lowpass(highpass(nz(length), lo), hi)
        count = len(n)
        return [v * (math.sin(math.pi * min(1.0, i / max(1, count))) ** 0.7) * peak for i, v in enumerate(n)]

    def seq(*parts):
        total = max(int(tm * SR) + len(sm) for tm, sm in parts)
        out = [0.0] * total
        for tm, sm in parts:
            start = int(tm * SR)
            for k, v in enumerate(sm):
                out[start + k] += v
        return out

    # --- the shot: sub-bass thump, hard crack, ringing steel, a long tail and two echoes
    length = 1.9
    thump = mix(env_exp(sine(48, length), 0.22), env_exp(sweep(160, 38, length), 0.12))
    crack = env_exp(highpass(nz(length), 1600), 0.035)
    body = env_exp(lowpass(nz(length), 2600), 0.11)
    ring = mix(modal([1250, 2150, 3400, 5200], [0.30, 0.22, 0.15, 0.08], [0.35, 0.28, 0.20, 0.16], length))
    tail = env_exp(lowpass(nz(length), 800), 0.55)
    direct = soft_clip(mix(gain(thump, 1.2), gain(crack, 1.7), gain(body, 0.9), ring, gain(tail, 0.5)), 2.8)
    echo1 = gain(lowpass(env_exp(nz(length), 0.35), 1200), 0.30)
    echo2 = gain(lowpass(env_exp(nz(length), 0.40), 800), 0.18)
    shot = mix(direct, delay(echo1, 0.22)[:len(direct)], delay(echo2, 0.46)[:len(direct)])
    write_wav("shot_sniper", shot, 0.98)
    write_wav("shot_sniper_far", gain(lowpass(shot, 1400), 0.6), 0.65)

    # --- bolt: lift the handle and pull back (ratchet + scrape + stop), push forward and lock down
    heavy = lambda f, l, st: mix(thunk(f, l, st), gain(modal([f * 6, f * 11], [0.05, 0.035], [0.5, 0.3], l), 0.35))
    write_wav("sniper_bolt_open", seq(
        (0.0, mix(heavy(150, 0.09, 1.2), tick(0.85, 1.2, 0.05))), # handle unlocks: hard clack
        (0.0, gain(modal([1100, 1900, 3000], [0.06, 0.05, 0.03], [0.6, 0.45, 0.3], 0.2), 0.5)),
        (0.07, scrape(0.26, 600, 3000, 1.0)), # long heavy slide back
        (0.09, tick(0.9, 1.0, 0.03)), (0.13, tick(0.95, 1.0, 0.03)), (0.17, tick(1.0, 1.0, 0.03)), (0.21, tick(1.05, 1.0, 0.03)), (0.25, tick(1.1, 1.0, 0.03)),
        (0.34, mix(heavy(85, 0.14, 1.5), tick(0.8, 1.3, 0.06))), # bolt hits the rear stop
        (0.345, gain(modal([1300, 2200, 3400], [0.08, 0.06, 0.04], [0.6, 0.45, 0.3], 0.25), 0.55)),
        (0.45, gain(modal([4200, 6100], [0.06, 0.04], [0.5, 0.3], 0.2), 0.35)), # the brass rings out
    ), 0.95)
    write_wav("sniper_bolt_close", seq(
        (0.0, scrape(0.22, 700, 3400, 1.0)), # forward
        (0.02, tick(0.9, 0.9, 0.03)), (0.07, tick(1.0, 0.9, 0.03)), (0.12, tick(1.1, 0.9, 0.03)),
        (0.22, mix(heavy(80, 0.15, 1.6), tick(0.75, 1.3, 0.06))), # slammed into the chamber
        (0.225, gain(modal([1200, 2000, 3200], [0.07, 0.05, 0.03], [0.6, 0.45, 0.3], 0.25), 0.55)),
        (0.33, mix(heavy(170, 0.07, 1.1), tick(1.15, 1.2, 0.04))), # handle locked down
        (0.335, gain(modal([2000, 3000], [0.05, 0.03], [0.6, 0.4], 0.15), 0.5)),
    ), 0.97)

    # --- scope: a soft optical swish and the click of the zoom ring
    def swish(length, rising):
        n = lowpass(highpass(nz(length), 1200), 5000)
        count = len(n)
        out = []
        for i, v in enumerate(n):
            u = i / max(1, count)
            e = math.sin(math.pi * (u if rising else 1.0 - u * 0.2)) ** 1.5
            out.append(v * e * 0.5)
        return out
    write_wav("sniper_scope_in", seq((0.0, swish(0.14, True)), (0.12, tick(1.3, 0.3, 0.03)), (0.125, thunk(260, 0.04, 0.3))), 0.5)
    write_wav("sniper_scope_out", seq((0.0, swish(0.12, False)), (0.0, tick(1.2, 0.25, 0.03))), 0.45)
    write_wav("sniper_scope_zoom", seq((0.0, tick(1.0, 0.8, 0.04)), (0.045, tick(1.15, 0.7, 0.04)), (0.0, thunk(300, 0.03, 0.4))), 0.5)


def make_ui():
    write_wav("ui_click", mix(env_exp(sine(1800, 0.05), 0.012), env_exp(highpass(noise(0.05), 2000), 0.006)), 0.5)
    write_wav("ui_hover", env_exp(sine(1400, 0.04), 0.01), 0.3)
    write_wav("ui_back", mix(env_exp(sine(900, 0.07), 0.02), env_exp(sine(600, 0.07), 0.025)), 0.45)
    write_wav("respawn", concat(tone(660, 0.1), tone(990, 0.16)), 0.6)
    write_wav("round_start", concat(tone(523, 0.14), tone(659, 0.14), tone(784, 0.3)), 0.7)
    write_wav("round_win", concat(tone(523, 0.12), tone(659, 0.12), tone(784, 0.12), tone(1047, 0.45)), 0.75)
    write_wav("round_lose", concat(tone(440, 0.18), tone(415, 0.18), tone(392, 0.5)), 0.7)
    write_wav("countdown_tick", env_exp(sine(1000, 0.1), 0.03), 0.5)
    write_wav("countdown_go", env_exp(sine(1500, 0.3), 0.1), 0.6)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    import sys
    if "grenade" in sys.argv[1:]:
        make_grenade_sounds()
        sys.exit(0)
    if "ambience" in sys.argv[1:]:
        make_ambience()
        sys.exit(0)
    if "grenadeextra" in sys.argv[1:]:
        make_grenade_extra()
        sys.exit(0)
    if "slide" in sys.argv[1:]:
        make_slide_sound()
        sys.exit(0)
    if "reload" in sys.argv[1:]:
        make_reload_sounds()
        sys.exit(0)
    if "hits" in sys.argv[1:]:
        make_hit_feedback() # only the hit/kill confirmation sounds
        sys.exit(0)
    if "glass" in sys.argv[1:]:
        make_glass_sounds()
        sys.exit(0)
    if "flash" in sys.argv[1:]:
        make_flash_sounds()
        sys.exit(0)
    if "sniper" in sys.argv[1:]:
        make_sniper_sounds()
        sys.exit(0)
    make_guns()
    make_mechanical()
    make_reload_sounds()
    make_grenade_sounds()
    make_slide_sound()
    make_grenade_extra()
    make_ambience()
    make_movement()
    make_feedback()
    make_ui()
    make_flash_sounds()
    make_sniper_sounds()
    make_glass_sounds()
