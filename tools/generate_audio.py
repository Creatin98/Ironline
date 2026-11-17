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
    """Hit / headshot / kill confirmation sounds. Own random generator so the other
    sounds stay byte-identical when this is changed."""
    local = random.Random(4711)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def ping(freq, length, decay):
        return env_exp(sine(freq, length), decay)

    # body hit: dry transient + short body tick + low thud (a satisfying "tck")
    hit = mix(
        gain(env_exp(highpass(nz(0.03), 2500), 0.004), 0.9),
        gain(ping(1900, 0.09, 0.016), 0.75),
        gain(ping(2850, 0.09, 0.010), 0.35),
        gain(env_exp(sweep(260, 110, 0.07), 0.025), 0.8),
    )
    write_wav("hitmarker", hit, 0.8)

    # headshot: sharper crack, metallic inharmonic ping and a snap sweep on top
    head = mix(
        gain(env_exp(highpass(nz(0.04), 3500), 0.006), 1.0),
        gain(env_exp(sweep(6200, 2600, 0.05), 0.012), 0.6),
        gain(ping(2950, 0.22, 0.05), 0.7),
        gain(ping(4400, 0.22, 0.035), 0.5),
        gain(ping(6150, 0.22, 0.02), 0.3),
        gain(env_exp(sweep(300, 120, 0.09), 0.03), 0.9),
    )
    write_wav("hitmarker_headshot", head, 0.9)

    # kill: heavy thunk + bright rising two-note chime + tiny click
    thunk = mix(env_exp(sweep(190, 62, 0.16), 0.06), gain(env_exp(lowpass(nz(0.12), 900), 0.03), 0.5))
    chime = mix(
        delay(mix(ping(880, 0.3, 0.07), gain(ping(1760, 0.3, 0.05), 0.35)), 0.04),
        delay(mix(ping(1320, 0.3, 0.09), gain(ping(2640, 0.3, 0.06), 0.3)), 0.11),
    )
    kill = mix(gain(thunk, 1.0), gain(chime, 0.75), gain(env_exp(highpass(nz(0.02), 3000), 0.004), 0.5))
    write_wav("kill_confirm", kill, 0.85)

    # headshot kill: same body, higher and brighter, three-note run with a glassy shimmer
    shimmer = mix(ping(3520, 0.4, 0.12), ping(5280, 0.4, 0.09), ping(7040, 0.4, 0.05))
    chime_h = mix(
        delay(mix(ping(1047, 0.35, 0.07), gain(ping(2094, 0.35, 0.05), 0.35)), 0.03),
        delay(mix(ping(1568, 0.35, 0.09), gain(ping(3136, 0.35, 0.06), 0.3)), 0.08),
        delay(mix(ping(2093, 0.4, 0.12), gain(ping(4186, 0.4, 0.08), 0.3)), 0.13),
    )
    kill_h = mix(
        gain(thunk, 1.0),
        gain(chime_h, 0.8),
        gain(delay(shimmer, 0.13), 0.25),
        gain(env_exp(highpass(nz(0.03), 3500), 0.006), 0.7),
    )
    write_wav("kill_headshot", kill_h, 0.9)


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
    if "hits" in sys.argv[1:]:
        make_hit_feedback() # only the hit/kill confirmation sounds
        sys.exit(0)
    make_guns()
    make_mechanical()
    make_movement()
    make_feedback()
    make_ui()
