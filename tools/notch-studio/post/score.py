"""Score a studio take: a 120 BPM bed in D minor whose drop lands on the first notch open and
whose final hit lands on the outro card, plus effects placed on the timeline's own cues.

    uv run -q --with numpy post/score.py out/notch-full-cues.json out/notch-full.wav
"""
import json, sys, wave
import numpy as np

cues = json.load(open(sys.argv[1]))
DUR = cues["duration"]
ev = sorted(cues["events"], key=lambda e: e["t"])
SR = 48000; N = int(SR * DUR); BEAT = 0.5
rng = np.random.default_rng(7)
L = np.zeros(N); R = np.zeros(N)


def first(kind, label=None):
    return next(e["t"] for e in ev if e["kind"] == kind and (label is None or e["label"] == label))


DROP = first("notch", "open")          # the notch opening is the downbeat
END = first("card", "outro")           # the final hit


def t_(d): return np.arange(int(SR * d)) / SR
def add(sig, at, gain=1.0, pan=0.0):
    i = int(round(at * SR))
    if i < 0 or i >= N: return
    s = sig[: N - i] * gain
    L[i:i + len(s)] += s * np.sqrt((1 - pan) / 2) * 1.414; R[i:i + len(s)] += s * np.sqrt((1 + pan) / 2) * 1.414
def hz(m): return 440 * 2 ** ((m - 69) / 12)
def env(n, a, d):
    e = np.ones(n); ai = max(1, int(a * SR)); e[:ai] = np.linspace(0, 1, ai)
    return e * np.exp(-np.arange(n) / SR / d)
def lp(x, cutoff):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X / np.sqrt(1 + (f / cutoff) ** 4), len(x))

def kick():
    t = t_(0.45); f = 48 + 90 * np.exp(-t * 28)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), .002, .16)
def clap():
    t = t_(0.3); n = np.diff(np.concatenate([[0], lp(rng.standard_normal(len(t)), 3200)])) * 6
    return lp(n, 6000) * env(len(t), .001, .09) * 0.6
def hat(open_=False):
    t = t_(0.25 if open_ else 0.06); n = rng.standard_normal(len(t)); n = n - lp(n, 7000)
    return n * env(len(t), .001, .08 if open_ else .018) * 0.35
def bass(m, d):
    t = t_(d); f = hz(m)
    s = np.tanh(1.6 * (np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * 2 * f * t)))
    e = np.minimum(1, t / .01) * np.minimum(1, (d - t) / .04) * (0.75 + 0.25 * np.exp(-t * 6))
    return lp(s * e, 900) * 0.55
def pluck(m, d=0.4):
    t = t_(d); f = hz(m)
    s = sum(np.sin(2 * np.pi * f * k * t) * np.exp(-t * (6 + 4 * k)) / k for k in range(1, 6))
    return s * env(len(t), .002, .22) * 0.28
def pad(ms, d, bright=1800):
    t = t_(d); s = np.zeros(len(t))
    for m in ms:
        for det in (-0.08, 0.0, 0.08):
            s += 2 * ((hz(m + det) * t + rng.uniform(0, 1)) % 1) - 1
    e = np.minimum(1, t / .25) * np.minimum(1, (d - t) / .35)
    return lp(s / (len(ms) * 3), bright) * e * 0.22
def pop(m, up=True, g=1.0):
    t = t_(0.22); f0 = hz(m)
    f = f0 * (0.75 + 0.25 * (1 - np.exp(-t * 40))) if up else f0 * (1.0 - 0.3 * (1 - np.exp(-t * 30)))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), .003, .06) * 0.5 * g
def click():
    t = t_(0.03); return rng.standard_normal(len(t)) * np.exp(-t * 400) * 0.25 + np.sin(2 * np.pi * 2200 * t) * np.exp(-t * 300) * 0.15
def thock(m):
    t = t_(0.12); return (np.sin(2 * np.pi * hz(m) * t) * np.exp(-t * 45) + lp(rng.standard_normal(len(t)), 2500) * np.exp(-t * 90) * 0.6) * 0.35
def whoosh(d=0.6):
    t = t_(d); n = rng.standard_normal(len(t)); x = np.sin(np.pi * t / d) ** 2
    return (lp(n, 1500) * (1 - t / d) + lp(n, 5000) * (t / d)) * x * 0.12

CH = [[50, 53, 57, 62], [46, 50, 53, 58], [53, 57, 60, 65], [48, 52, 55, 60]]   # Dm Bb F C
ROOT = [38, 34, 41, 36]
ARP = [[62, 65, 69, 74, 69, 65, 62, 69], [58, 62, 65, 70, 65, 62, 58, 65],
       [60, 65, 69, 72, 69, 65, 60, 69], [60, 64, 67, 72, 67, 64, 60, 67]]

# Typing gets a lighter bed, so the keys read.
typing = [e["t"] for e in ev if e["kind"] == "keys"]
quiet = (min(typing) - 0.5, max(typing) + 1.0) if typing else (-1, -1)

# intro: filtered pad and ticking hats up to the drop, a riser into it
add(pluck(74, .6), 0.0, 0.8)
add(pad(CH[0], DROP, bright=700), 0.0, 1.0)
k = 0
while DROP - (k + 1) * 0.25 >= 0 and k < 16:
    add(hat(), DROP - (k + 1) * 0.25, 0.6 if k % 2 else 0.35, pan=0.2); k += 1
r = t_(1.0); add(lp(rng.standard_normal(len(r)), 3000) * r ** 2 * 0.18, DROP - 1.0)

# groove: whole bars from the drop until the outro card
b = 0
while DROP + (b + 1) * 2.0 <= END + 1e-6:
    t0 = DROP + b * 2.0; c = b % 4
    light = quiet[0] < t0 + 1.0 < quiet[1]
    add(pad(CH[c], 2.05, bright=1600), t0, 0.9)
    for j in range(4):
        add(kick(), t0 + j * BEAT, 0.95)
        if j in (1, 3): add(clap(), t0 + j * BEAT, 0.55)
    for j in range(8):
        add(hat(open_=(j == 7)), t0 + j * 0.25, 0.5 if j % 2 else 0.28, pan=0.25)
        add(bass(ROOT[c] + (12 if j in (3, 6) else 0), 0.22), t0 + j * 0.25, 0.9)
        if not light:
            add(pluck(ARP[c][j]), t0 + j * 0.25, 0.75, pan=-0.3 if j % 2 else 0.3)
    b += 1
# the gap between the last whole bar and the card: a fill
gap0 = DROP + b * 2.0
for j in range(int((END - gap0) / 0.125)):
    add(hat(), gap0 + j * 0.125, 0.3 + 0.4 * j / 16, pan=0.2)
add(kick(), END, 1.0)
add(pad(CH[0] + [69], DUR - END, bright=2600), END, 1.3)
for j, m in enumerate([62, 65, 69, 74, 77]): add(pluck(m, 1.6), END + j * 0.06, 0.7, pan=(j - 2) * 0.2)
add(bass(38, min(1.4, DUR - END)), END, 0.9)

mus = np.stack([L.copy(), R.copy()]); L[:] = 0; R[:] = 0

# effects, from the cues
FIRST_TRACK = next(e["label"] for e in ev if e["kind"] == "music")
was_open = False; vol = 0; drop = 0
for e in ev:
    t, kind, label = e["t"], e["kind"], e["label"]
    if kind == "notch" and label == "open":
        add(whoosh(0.45), t - 0.35, 0.8); add(pop(74, True), t, 0.9); was_open = True
    elif kind == "notch" and label == "close":
        add(pop(69, False), t, 0.7); was_open = False
    elif kind == "view" and was_open:
        add(click(), t, 0.6)
    elif kind == "music" and label != FIRST_TRACK:
        add(click(), t, 0.7); add(pop(81, True, 0.5), t, 0.5)
    elif kind == "action" and label.startswith("volume"):
        add(thock(62 + 3 * vol), t, 0.6); vol += 1
    elif kind == "action" and label.startswith("drop"):
        add(pop(76 + 3 * drop, True, 0.6), t, 0.7); drop += 1
    elif kind == "keys":
        n = len(label.split())
        if label == "⏎": add(thock(57), t, 1.0)
        elif label.startswith("⌥"): add(thock(62), t, 0.9); add(thock(57), t + 0.12, 0.9)
        else: add(thock(66 + 3 * n), t, 0.7)
    elif kind == "agent" and "askPermission" in label:
        add(whoosh(0.5), t + 0.05, 0.9)          # no chime: the notch makes none here
    elif kind == "click":
        add(click(), t, 1.0)
    elif kind == "card" and label == "title":
        add(pop(81, True, 0.6), t, 0.6)
sfx = np.stack([L.copy(), R.copy()])

irt = t_(1.6); ir = rng.standard_normal((2, len(irt))) * np.exp(-irt * 3.2); ir[:, :int(.012 * SR)] = 0
def verb(x):
    return np.stack([np.fft.irfft(np.fft.rfft(x[c], 2 * N) * np.fft.rfft(ir[c], 2 * N), 2 * N)[:N] for c in range(2)]) * 0.012
mix = mus * 0.62 + sfx * 0.42
mix = mix + verb(mus * 0.5 + sfx * 0.6)
mix = np.tanh(mix * 1.1) / np.tanh(1.1)
fi = int(0.8 * SR); mix[:, -fi:] *= np.linspace(1, 0, fi) ** 1.5
mix /= np.max(np.abs(mix)) / 0.89
with wave.open(sys.argv[2], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix.T * 32767).astype(np.int16).tobytes())
print("ok", DUR, "drop", DROP, "end", END, "bars", b)
