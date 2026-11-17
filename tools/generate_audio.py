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
    """Hit / headshot / kill confirmation sounds: dry flesh thwack, metallic clatter and a
    heavy low punch (no pure sine pings, that sounds electronic). Own random generator so the
    other sounds stay byte-identical when this is changed."""
    local = random.Random(4711)

    def nz(seconds):
        return [local.uniform(-1, 1) for _ in range(int(seconds * SR))]

    def modal(freqs, decays, gains, length, pitch=1.0):
        """Struck metal: sum of exponentially decaying partials (inharmonic frequencies)."""
        out = [0.0] * int(length * SR)
        for f, d, g in zip(freqs, decays, gains):
            part = env_exp(sine(f * pitch, length), d)
            for k, s in enumerate(part):
                out[k] += s * g
        return out

    def tremolo(samples, rate, depth):
        return [s * (1.0 - depth + depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate * i / SR))) for i, s in enumerate(samples)]

    def punch(length, f0, f1, decay, noise_gain=0.5):
        body = env_exp(sweep(f0, f1, length), decay)
        flesh = env_exp(lowpass(nz(length), 900), decay * 0.5)
        return mix(body, gain(flesh, noise_gain))

    def clang(pitch=1.0, length=0.5, strength=1.0):
        partials = modal([610, 1030, 1670, 2480, 3560, 4900, 6400], [0.20, 0.16, 0.12, 0.09, 0.06, 0.04, 0.025],
                         [0.9, 0.8, 0.7, 0.5, 0.4, 0.25, 0.15], length, pitch)
        rattle = tremolo(partials, 41, 0.45) # the "scheppern"
        crack = env_exp(highpass(nz(0.03), 2500), 0.006)
        return gain(mix(rattle, gain(crack, 0.9)), strength)

    # body hit: very short, dry and hard
    hit = mix(
        gain(env_exp(highpass(nz(0.02), 2200), 0.0035), 1.0),
        gain(env_exp(lowpass(nz(0.06), 2200), 0.018), 0.9),
        gain(env_exp(sweep(240, 85, 0.08), 0.024), 1.1),
        gain(modal([3100, 4700], [0.012, 0.008], [1.0, 0.6], 0.05), 0.35),
    )
    write_wav("hitmarker", soft_clip(hit, 1.6), 0.85)

    # headshot hit: hard crack, a short clatter and a second quick tap
    head_a = mix(
        gain(env_exp(highpass(nz(0.03), 3200), 0.007), 1.3),
        gain(modal([1450, 2330, 3410, 5100], [0.05, 0.04, 0.03, 0.02], [0.8, 0.6, 0.45, 0.3], 0.25), 0.9),
        gain(env_exp(sweep(300, 100, 0.1), 0.03), 1.1),
    )
    head_b = gain(mix(
        gain(env_exp(highpass(nz(0.03), 3200), 0.006), 1.0),
        gain(modal([1740, 2790, 4090, 6120], [0.04, 0.03, 0.022, 0.015], [0.8, 0.6, 0.45, 0.3], 0.2), 0.9),
    ), 0.75)
    head = mix(head_a, delay(head_b, 0.055))
    write_wav("hitmarker_headshot", soft_clip(head, 1.6), 0.92)

    # kill: heavy punch + rattling metal crash
    kill = mix(
        gain(punch(0.22, 170, 42, 0.09), 1.3),
        delay(clang(1.0, 0.55, 1.0), 0.012),
    )
    write_wav("kill_confirm", soft_clip(kill, 2.0), 0.95)

    # headshot kill: three clatters in a rising run, harder punch, crack on top (rings out longer)
    kill_h = mix(
        gain(punch(0.26, 190, 38, 0.11, 0.7), 1.5),
        delay(clang(1.0, 0.5, 1.0), 0.008),
        delay(clang(1.22, 0.5, 0.9), 0.065),
        delay(clang(1.5, 0.6, 0.85), 0.125),
        gain(delay(env_exp(highpass(nz(0.05), 3800), 0.012), 0.125), 0.8),
    )
    write_wav("kill_headshot", soft_clip(kill_h, 2.2), 0.97)


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

    # shotgun shell: plastic shell on the loading gate, then the carrier latch clicks
    write_wav("shell_insert", seq((0.0, mix(thunk(260, 0.05, 0.7), tick(1.2, 0.5, 0.03))), (0.045, tick(1.0, 0.7, 0.04)), (0.045, gain(modal([1500, 2300], [0.02, 0.014], [0.6, 0.4], 0.08), 0.3))), 0.75)


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
    if "reload" in sys.argv[1:]:
        make_reload_sounds()
        sys.exit(0)
    if "hits" in sys.argv[1:]:
        make_hit_feedback() # only the hit/kill confirmation sounds
        sys.exit(0)
    make_guns()
    make_mechanical()
    make_reload_sounds()
    make_movement()
    make_feedback()
    make_ui()
