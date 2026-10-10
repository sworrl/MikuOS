#!/usr/bin/env python3
"""Original synthesized sound effects for MikuOS apps.

    sfx.py shutter_miku --out /tmp/s.ogg --play
    sfx.py --list

Every sound here is made from scratch in numpy: FM bells, additive saws, filtered noise,
pitch-swept sines and a noise-convolution reverb. No samples, no recordings, no borrowed
melodies. The "Miku" flavor is the palette, not a quote: glassy FM bells high in the
register, A major pentatonic arpeggios, bright saw pads, a little sparkle on top.

A recipe is a function returning mono float32 at 48 kHz. app_sounds.json names the recipe
for each sound id together with its loudness target and whether it loops.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import say  # noqa: E402

SR = 48000
RNG = np.random.default_rng(39)        # fixed seed: every build renders identical audio


# ── Building blocks ─────────────────────────────────────────────────────────
def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def tt(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def silence(dur: float) -> np.ndarray:
    return np.zeros(int(dur * SR), np.float64)


def ramp_in(x: np.ndarray, ms: float = 2.0) -> np.ndarray:
    n = min(len(x), int(ms * SR / 1000))
    x[:n] *= np.linspace(0, 1, n)
    return x


def ramp_out(x: np.ndarray, ms: float = 5.0) -> np.ndarray:
    n = min(len(x), int(ms * SR / 1000))
    x[-n:] *= np.linspace(1, 0, n)
    return x


def place(buf: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> np.ndarray:
    i = int(at * SR)
    if i + len(sig) > len(buf):
        buf = np.concatenate([buf, np.zeros(i + len(sig) - len(buf))])
    buf[i:i + len(sig)] += gain * sig
    return buf


def bell(f: float, dur: float = 0.6, decay: float = 0.25, ratio: float = 3.5,
         index: float = 2.0, index_decay: float = 0.08) -> np.ndarray:
    """Glassy FM bell: the mod index falls faster than the amplitude, so the attack
    shimmers and the tail goes pure."""
    t = tt(dur)
    mod = index * np.exp(-t / index_decay) * np.sin(2 * np.pi * f * ratio * t)
    y = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / decay)
    return ramp_out(ramp_in(y, 1.5), 8)


def epiano(f: float, dur: float = 0.8, decay: float = 0.45) -> np.ndarray:
    """FM electric piano: ratio-1 body plus a quiet high tine."""
    t = tt(dur)
    body = np.sin(2 * np.pi * f * t + 1.2 * np.exp(-t / 0.3) * np.sin(2 * np.pi * f * t))
    tine = np.sin(2 * np.pi * f * 14 * t) * np.exp(-t / 0.02) * 0.15
    y = (body * np.exp(-t / decay) + tine)
    return ramp_out(ramp_in(y, 2), 15)


def saw(f: float, dur: float, max_h: int = 40, phase=None) -> np.ndarray:
    """Band-limited saw by summing harmonics below Nyquist."""
    t = tt(dur)
    y = np.zeros_like(t)
    ph = RNG.uniform(0, 2 * np.pi) if phase is None else phase
    for k in range(1, max_h + 1):
        if f * k > SR * 0.45:
            break
        y += np.sin(2 * np.pi * f * k * t + ph * k) / k
    return y * 0.55


def supersaw(f: float, dur: float, cents=(-14, -6, 0, 6, 14), max_h: int = 24) -> np.ndarray:
    return sum(saw(f * 2 ** (c / 1200), dur, max_h) for c in cents) / len(cents)


def adsr(n: int, a: float, d: float, s: float, r: float) -> np.ndarray:
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    sus = max(n - a - d - r, 0)
    e = np.concatenate([np.linspace(0, 1, a, endpoint=False), np.linspace(1, s, d, endpoint=False),
                        np.full(sus, s), np.linspace(s, 0, r)])
    return np.pad(e, (0, max(0, n - len(e))))[:n]


def noise(dur: float) -> np.ndarray:
    return RNG.standard_normal(int(dur * SR))


def filt(x: np.ndarray, kind: str, f, order: int = 2) -> np.ndarray:
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(order, f, btype=kind, fs=SR, output="sos"), x)


def sweep(f0: float, f1: float, dur: float, curve: str = "exp") -> np.ndarray:
    """Sine with a gliding pitch (exponential by default, which sounds even)."""
    t = tt(dur)
    f = f0 * (f1 / f0) ** (t / dur) if curve == "exp" else f0 + (f1 - f0) * t / dur
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def svf_sweep(x: np.ndarray, f0: float, f1: float, q: float = 1.5) -> np.ndarray:
    """State-variable band-pass whose center glides from f0 to f1 across the signal."""
    n = len(x)
    fc = f0 * (f1 / f0) ** (np.arange(n) / n)
    g = np.tan(np.pi * fc / SR)
    k = 1 / q
    out = np.zeros(n)
    ic1 = ic2 = 0.0
    for i in range(n):
        a1 = 1 / (1 + g[i] * (g[i] + k))
        v1 = a1 * ic1 + g[i] * a1 * (x[i] - ic2)
        v2 = ic2 + g[i] * v1
        ic1, ic2 = 2 * v1 - ic1, 2 * v2 - ic2
        out[i] = v1
    return out


def reverb(x: np.ndarray, seconds: float = 1.2, mix: float = 0.25, tone: float = 7000,
           predelay: float = 0.012) -> np.ndarray:
    """Convolution with exponentially decaying filtered noise: a smooth, small hall."""
    from scipy.signal import fftconvolve
    n = int(seconds * SR)
    ir = RNG.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / seconds))
    ir = filt(ir, "lowpass", tone)
    ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = fftconvolve(x, ir)[: len(x) + len(ir)]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return (1 - mix) * dry + mix * wet


def trim_tail(x: np.ndarray, floor_db: float = -55) -> np.ndarray:
    a = np.abs(x)
    above = np.where(a > np.max(a) * 10 ** (floor_db / 20))[0]
    end = above[-1] + int(0.01 * SR) if len(above) else len(x)
    return ramp_out(x[:end].copy(), 10)


RECIPES: dict = {}


def recipe(fn):
    RECIPES[fn.__name__] = fn
    return fn


# ── Camera ──────────────────────────────────────────────────────────────────
def _click(level: float = 1.0, body_hz: float = 190, bright: float = 9000) -> np.ndarray:
    """One mechanical click: a broadband snap plus a short low body thump."""
    snap = filt(noise(0.03), "bandpass", [1800, bright]) * np.exp(-tt(0.03) / 0.004)
    body = np.sin(2 * np.pi * body_hz * tt(0.05)) * np.exp(-tt(0.05) / 0.012) * 0.6
    y = np.zeros(int(0.05 * SR))
    y[: len(snap)] += snap
    y += body
    return ramp_in(y, 0.3) * level


def _shutter_body() -> np.ndarray:
    y = silence(0.16)
    y = place(y, _click(1.0, 210), 0.0)
    whir = filt(noise(0.045), "bandpass", [1200, 4500]) * adsr(int(0.045 * SR), 0.01, 0.02, 0.4, 0.015)
    y = place(y, whir, 0.012, 0.18)
    y = place(y, _click(0.75, 170, 7000), 0.058)
    return y


@recipe
def shutter_miku() -> np.ndarray:
    """Crisp two-blade shutter, then a quick pentatonic sparkle up to B7."""
    y = _shutter_body()
    sparkle = silence(0.5)
    for i, m in enumerate([83, 88, 92, 95]):          # B5 E6 G#6 B6, voiced an octave up
        sparkle = place(sparkle, bell(hz(m + 12), 0.35, 0.09, 4.0, 1.2, 0.03), 0.028 * i,
                        0.22 * (0.85 ** i))
    sparkle = reverb(sparkle, 0.7, 0.3, 9000)
    y = place(y, sparkle, 0.07)
    return trim_tail(y)


@recipe
def shutter_plain() -> np.ndarray:
    """Short, dry, for burst mode: fires back to back without smearing."""
    return trim_tail(_shutter_body())


def _chime(notes, step: float, voice=bell, decay: float = 0.28, verb: float = 0.22, **kw):
    y = silence(0.1)
    for i, m in enumerate(notes):
        y = place(y, voice(hz(m), 0.9, decay, **kw), step * i, 0.8 if i else 1.0)
    return trim_tail(reverb(y, 0.9, verb))


@recipe
def video_start() -> np.ndarray:
    return _chime([81, 85, 88], 0.075, epiano, 0.3)            # A5 C#6 E6, rising


@recipe
def video_stop() -> np.ndarray:
    return _chime([88, 85, 81], 0.075, epiano, 0.3)            # and back down


@recipe
def focus_lock() -> np.ndarray:
    y = silence(0.08)
    for i, f in enumerate([3520, 4435]):
        pip = np.sin(2 * np.pi * f * tt(0.018)) * np.exp(-tt(0.018) / 0.005)
        y = place(y, ramp_in(pip, 0.5), 0.032 * i, 1.0 if i else 0.7)
    return trim_tail(y)


def _beep(f: float, dur: float) -> np.ndarray:
    t = tt(dur)
    y = (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(4 * np.pi * f * t)) * adsr(len(t), 0.004, 0.03, 0.6, 0.05)
    return y


@recipe
def timer_beep() -> np.ndarray:
    return trim_tail(reverb(_beep(hz(88), 0.11), 0.4, 0.12))      # E6, one per second


@recipe
def timer_beep_final() -> np.ndarray:
    y = place(_beep(hz(93), 0.26), bell(hz(105), 0.4, 0.1, 4.0, 1.0), 0.0, 0.2)   # A6 + A7 glint
    return trim_tail(reverb(y, 0.6, 0.18))


# ── Recorder ────────────────────────────────────────────────────────────────
@recipe
def rec_start() -> np.ndarray:
    return _chime([76, 83], 0.11, bell, 0.3, ratio=2.0, index=1.5)       # E5 B5


@recipe
def rec_stop() -> np.ndarray:
    return _chime([83, 76], 0.11, bell, 0.3, ratio=2.0, index=1.5)


@recipe
def rec_pause() -> np.ndarray:
    return _chime([80, 80], 0.13, bell, 0.12, ratio=2.0, index=1.0)      # G#5 twice, short


# ── Clock ───────────────────────────────────────────────────────────────────
@recipe
def timer_done() -> np.ndarray:
    y = silence(0.1)
    for rep in range(2):
        for i, m in enumerate([81, 85, 88, 93]):
            y = place(y, bell(hz(m), 1.0, 0.35, 3.5, 1.8), rep * 0.75 + i * 0.09, 0.75 if i < 3 else 1.0)
    return trim_tail(reverb(y, 1.4, 0.28))


# A major pentatonic world, 120 bpm, eighth-note grid; None is a rest. Original lines.
_ALARM_PHRASES = [
    [[76, None, 81, None, 83, 85, None, 88], [85, None, 83, 81, None, 78, None, None],
     [74, None, 78, 81, None, 83, 81, None], [83, None, 80, 76, None, None, None, None]],
    [[88, None, 85, None, 88, 90, None, 88], [85, None, 83, None, 81, None, 78, None],
     [81, None, 83, 85, None, 86, 85, 83], [80, None, 83, None, 88, None, None, None]],
    [[76, None, 81, None, 83, 85, None, 88], [85, None, 83, 81, None, 78, None, None],
     [74, None, 78, 81, None, 83, 81, None], [83, None, 85, None, 81, None, None, None]],
]
_CHORDS = {"A": [57, 61, 64], "F#m": [54, 57, 61], "D": [50, 54, 57], "E": [52, 56, 59]}
_PROG = ["A", "F#m", "D", "E"]


def _kick() -> np.ndarray:
    t = tt(0.25)
    return np.sin(2 * np.pi * np.cumsum(50 + 90 * np.exp(-t / 0.03)) / SR) * np.exp(-t / 0.09)


def _hat() -> np.ndarray:
    return filt(noise(0.05), "highpass", 7000) * np.exp(-tt(0.05) / 0.012)


def _loopable(y: np.ndarray, length: float) -> np.ndarray:
    """Fold everything that rings past the loop point back onto the start, so the file
    loops with no gap and no cut-off reverb."""
    n = int(length * SR)
    out = y[:n].copy()
    tail = y[n:]
    out[: len(tail)] += tail
    return out


@recipe
def alarm_loop() -> np.ndarray:
    """24 s, 12 bars: bell melody alone, then pad and bass come in, then a light beat and an
    octave doubling. Loops seamlessly; the first bars sit soft so a restart is gentle."""
    beat, bar = 0.5, 2.0
    total = 12 * bar
    lead = silence(total + 3)
    for p, phrase in enumerate(_ALARM_PHRASES):
        for b, notes in enumerate(phrase):
            for e, m in enumerate(notes):
                if m is None:
                    continue
                at = (p * 4 + b) * bar + e * beat / 2
                g = [0.55, 0.8, 0.9][p]
                lead = place(lead, epiano(hz(m), 1.0, 0.5), at, g)
                lead = place(lead, bell(hz(m + 12), 0.6, 0.18, 3.5, 1.0), at, 0.12 * (p + 1))
                if p == 2:
                    lead = place(lead, bell(hz(m + 12), 0.8, 0.3, 2.0, 0.8), at, 0.3)
    pad = silence(total + 3)
    bass = silence(total + 3)
    beat_l = silence(total + 3)
    for b in range(4, 12):
        chord = _CHORDS[_PROG[b % 4]]
        n = int(bar * SR)
        amp = adsr(n, 0.25, 0.3, 0.8, 0.35) * (min(1.0, 0.4 + 0.15 * (b - 4)))
        voices = sum(supersaw(hz(m + 12), bar) for m in chord) / 3
        pad = place(pad, filt(voices, "lowpass", 2400) * amp, b * bar, 0.35)
        root = chord[0] - 12
        for q in range(4):
            pluck = (np.sin(2 * np.pi * hz(root) * tt(0.45)) + 0.3 * saw(hz(root), 0.45, 8)) \
                * np.exp(-tt(0.45) / 0.16)
            bass = place(bass, ramp_in(pluck, 3), b * bar + q * beat, 0.45)
        if b >= 8:
            for q in range(4):
                if q in (0, 2):
                    beat_l = place(beat_l, _kick(), b * bar + q * beat, 0.5)
                beat_l = place(beat_l, _hat(), b * bar + q * beat + beat / 2, 0.12)
    mix = place(reverb(lead, 1.6, 0.25), reverb(pad, 1.8, 0.3), 0)
    mix = place(mix, bass, 0)
    mix = place(mix, beat_l, 0)
    return _loopable(mix, total)


@recipe
def ringtone_loop() -> np.ndarray:
    """16 s, 8 bars at 120 bpm: plucked arpeggios under a short bell hook. Loops."""
    beat, bar = 0.5, 2.0
    prog = ["A", "E", "F#m", "D"] * 2
    hook = [[88, None, 88, 85, None, 83, 85, None], [83, None, 80, None, 83, None, None, None],
            [81, None, 81, 85, None, 88, 90, None], [88, None, 85, None, None, None, None, None]]
    y = silence(8 * bar + 3)
    for b, name in enumerate(prog):
        chord = _CHORDS[name]
        arp = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 24]
        for s in range(16):
            m = arp[s % 4]
            pl = filt(saw(hz(m), 0.25, 20), "lowpass", 3500) * np.exp(-tt(0.25) / 0.07)
            y = place(y, ramp_in(pl, 1), b * bar + s * beat / 4, 0.18)
        for e, m in enumerate(hook[b % 4]):
            if m is not None:
                y = place(y, bell(hz(m), 0.9, 0.3, 3.5, 1.6), b * bar + e * beat / 2, 0.5)
        y = place(y, np.sin(2 * np.pi * hz(chord[0] - 12) * tt(1.8)) * adsr(int(1.8 * SR), 0.01, 0.4, 0.5, 0.3),
                  b * bar, 0.3)
    return _loopable(reverb(y, 1.2, 0.22), 8 * bar)


# ── Gallery, calculator, FM ─────────────────────────────────────────────────
@recipe
def delete_swoosh() -> np.ndarray:
    n = noise(0.32)
    y = svf_sweep(n, 5200, 500, 2.2) * adsr(len(n), 0.06, 0.12, 0.5, 0.14)
    y += 0.25 * sweep(1400, 300, 0.32) * adsr(len(n), 0.03, 0.1, 0.3, 0.15)
    return trim_tail(reverb(y, 0.5, 0.15))


@recipe
def key_click() -> np.ndarray:
    y = filt(noise(0.012), "bandpass", [2000, 8000]) * np.exp(-tt(0.012) / 0.0015)
    y = place(y, np.sin(2 * np.pi * 2300 * tt(0.02)) * np.exp(-tt(0.02) / 0.004), 0, 0.5)
    return trim_tail(ramp_in(y, 0.2))


@recipe
def key_equals() -> np.ndarray:
    y = place(key_click(), bell(hz(93), 0.3, 0.07, 3.0, 0.8), 0.004, 0.35)
    return trim_tail(y)


@recipe
def tune_click() -> np.ndarray:
    y = np.sin(2 * np.pi * 1600 * tt(0.015)) * np.exp(-tt(0.015) / 0.003)
    y = place(y, filt(noise(0.008), "bandpass", [1500, 5000]) * np.exp(-tt(0.008) / 0.001), 0, 0.5)
    return trim_tail(ramp_in(y, 0.2))


@recipe
def station_lock() -> np.ndarray:
    return _chime([85, 88], 0.06, bell, 0.12, ratio=3.0, index=1.0)


# ── BPM game ────────────────────────────────────────────────────────────────
@recipe
def hit() -> np.ndarray:
    y = _click(0.6, 160, 9000)
    y = place(y, bell(hz(93), 0.2, 0.05, 3.0, 1.0), 0.0, 0.5)
    return trim_tail(y)


@recipe
def hit_perfect() -> np.ndarray:
    y = hit()
    for i, m in enumerate([100, 105]):                          # E7 A7 glint
        y = place(y, bell(hz(m), 0.25, 0.06, 4.0, 0.8), 0.02 + 0.025 * i, 0.3)
    return trim_tail(reverb(y, 0.5, 0.15))


@recipe
def miss() -> np.ndarray:
    t = tt(0.16)
    y = np.sin(2 * np.pi * np.cumsum(180 * np.exp(-t / 0.08) + 70) / SR) * np.exp(-t / 0.05)
    y += filt(noise(0.16), "lowpass", 900) * np.exp(-t / 0.03) * 0.3
    return trim_tail(ramp_in(y, 1))


@recipe
def combo_break() -> np.ndarray:
    y = silence(0.1)
    for i, m in enumerate([76, 72, 69]):                        # E5 C5 A4, falling
        f = hz(m)
        t = tt(0.14)
        sq = np.sign(np.sin(2 * np.pi * f * t * (1 - 0.06 * t / 0.14)))
        sq = filt(sq, "lowpass", 2500) * adsr(len(t), 0.003, 0.05, 0.5, 0.05)
        sq = np.round(sq * 12) / 12                              # a little bitcrush grit
        y = place(y, sq, 0.11 * i, 0.6)
    return trim_tail(reverb(y, 0.5, 0.12))


@recipe
def full_combo_jingle() -> np.ndarray:
    y = silence(0.1)
    for i, m in enumerate([81, 85, 88, 93]):
        y = place(y, epiano(hz(m), 0.6, 0.3), 0.07 * i, 0.7)
        y = place(y, bell(hz(m + 12), 0.5, 0.15, 3.5, 1.2), 0.07 * i, 0.2)
    for m in [69, 73, 76, 81]:                                  # A major stab under the top
        stab = filt(supersaw(hz(m), 0.9), "lowpass", 4000) * adsr(int(0.9 * SR), 0.01, 0.2, 0.5, 0.4)
        y = place(y, stab, 0.3, 0.12)
    y = place(y, bell(hz(105), 1.0, 0.35, 4.0, 1.5), 0.3, 0.25)
    return trim_tail(reverb(y, 1.2, 0.25))


@recipe
def level_up_jingle() -> np.ndarray:
    y = silence(0.1)
    for i, m in enumerate([76, 81, 85, 88, 93]):
        y = place(y, bell(hz(m), 0.5, 0.15, 2.0, 1.4), 0.055 * i, 0.7)
    for m in [81, 85, 88]:
        y = place(y, epiano(hz(m), 0.9, 0.45), 0.3, 0.3)
    return trim_tail(reverb(y, 1.0, 0.22))


# ── System ──────────────────────────────────────────────────────────────────
@recipe
def notify_sparkle() -> np.ndarray:
    return _chime([85, 88, 93], 0.085, bell, 0.35, ratio=3.5, index=2.2)  # C#6 E6 A6


@recipe
def notify_bubble() -> np.ndarray:
    y = silence(0.1)
    for i, (f0, f1) in enumerate([(700, 880), (1050, 1320)]):
        pop = sweep(f0, f1, 0.09) * adsr(int(0.09 * SR), 0.004, 0.03, 0.5, 0.04)
        y = place(y, pop, 0.12 * i, 0.9)
    y = place(y, bell(hz(100), 0.4, 0.12, 3.0, 0.8), 0.13, 0.15)
    return trim_tail(reverb(y, 0.7, 0.2))


@recipe
def notify_chirp() -> np.ndarray:
    y = sweep(1800, 3200, 0.05) * adsr(int(0.05 * SR), 0.003, 0.02, 0.5, 0.02) * 0.5
    y = place(y, bell(hz(88), 0.7, 0.22, 2.0, 1.5), 0.06, 0.8)
    y = place(y, bell(hz(95), 0.7, 0.25, 2.0, 1.5), 0.15, 0.7)
    return trim_tail(reverb(y, 0.8, 0.22))


@recipe
def usb_connect() -> np.ndarray:
    return _chime([88, 93], 0.06, bell, 0.08, ratio=1.0, index=0.6, verb=0.1)


@recipe
def usb_disconnect() -> np.ndarray:
    return _chime([93, 88], 0.06, bell, 0.08, ratio=1.0, index=0.6, verb=0.1)


@recipe
def charge_connect() -> np.ndarray:
    y = sweep(420, 1250, 0.18) * adsr(int(0.18 * SR), 0.03, 0.05, 0.6, 0.06) * 0.6
    y = place(y, bell(hz(93), 0.6, 0.2, 3.5, 1.2), 0.14, 0.7)
    return trim_tail(reverb(y, 0.8, 0.2))


# ── Loudness and encoding ───────────────────────────────────────────────────
def max_momentary(a: np.ndarray) -> float:
    """Loudest 400 ms window (BS.1770 momentary), with short sounds padded to one window.
    For a UI sound this is what the ear judges, so it is what the target refers to."""
    import pyloudnorm
    win = int(0.4 * SR)
    a = np.concatenate([a, np.zeros(max(0, win - len(a)))])
    meter = pyloudnorm.Meter(SR, block_size=0.4)
    best = -120.0
    for i in range(0, len(a) - win + 1, int(0.1 * SR)):
        with np.errstate(divide="ignore"):
            best = max(best, meter.integrated_loudness(a[i:i + win]))
    return best


def render(recipe: str, out: Path, lufs: float = -20.0, loop: bool = False) -> dict:
    a = RECIPES[recipe]().astype(np.float64)
    a = filt(a, "highpass", 40, 2)                      # no DC or subsonic rumble on IEMs
    if loop:
        gain = lufs - say.loudness(a.astype(np.float32), SR)
    else:
        gain = lufs - max_momentary(a)
    a = (a * 10 ** (gain / 20)).astype(np.float32)
    tp = say.true_peak_db(a)
    if tp > say.TARGET_TP:
        a = say._limit(a, say.TARGET_TP - 1.0) if loop else a * 10 ** ((say.TARGET_TP - tp) / 20)
    out.parent.mkdir(parents=True, exist_ok=True)

    def enc(x):
        if loop:
            # Vorbis plus ANDROID_LOOP=true: MediaPlayer and the ringtone/alarm framework
            # loop it in the decoder, which is the gapless path on Android.
            args = ["-c:a", "libvorbis", "-q:a", "3", "-metadata", "ANDROID_LOOP=true"]
        else:
            # Opus "audio" mode at 64 kb/s keeps the sparkle up to 20 kHz.
            args = ["-c:a", "libopus", "-b:a", "64k", "-vbr", "on", "-application", "audio"]
        say._ffmpeg(["-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "pipe:0",
                     "-map_metadata", "-1", *args, "-f", "ogg", str(out)], stdin=x.tobytes())
    enc(a)
    for _ in range(3):
        tp = say.true_peak_db(say.decode(out))
        if tp <= say.MAX_TP_SHIPPED:
            break
        a = a * 10 ** ((say.MAX_TP_SHIPPED - 0.3 - tp) / 20)
        enc(a)
    d = say.decode(out)
    return {"duration": round(len(a) / SR, 3),
            "lufs": round(float(say.loudness(d, SR) if loop else max_momentary(d.astype(np.float64))), 1),
            "true_peak_dbtp": round(float(say.true_peak_db(d)), 2)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("recipe", nargs="?")
    ap.add_argument("--out", type=Path)
    ap.add_argument("--lufs", type=float, default=-20.0)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--play", action="store_true")
    args = ap.parse_args()
    if args.list or not args.recipe:
        print("\n".join(sorted(RECIPES)))
        return
    out = args.out or Path("/tmp") / f"miku-sfx-{args.recipe}.ogg"
    info = render(args.recipe, out, args.lufs, args.loop)
    print(out, info)
    if args.play:
        subprocess.run(["ffplay", "-v", "error", "-nodisp", "-autoexit", str(out)])


if __name__ == "__main__":
    say._ensure_venv()
    main()
