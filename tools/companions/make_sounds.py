#!/usr/bin/env python3
"""Синтез звуков питомцев: по два на каждого — «tx» (операция) и «xp» (опыт/успех).

Использование: python3 make_sounds.py <папка-вывода>
Файлы: snd_<id>_tx.wav, snd_<id>_xp.wav (22.05 кГц, моно, 16 бит).
Всё синтезируется кодом, чужих сэмплов нет.
"""
import os
import sys
import wave
import numpy as np
from scipy import signal

SR = 22050
rng = np.random.default_rng(7)


# ---------- примитивы ----------
def t_(dur):
    return np.arange(int(SR * dur)) / SR


def env_exp(n, decay, attack=0.004):
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t * decay)


def sine(freq, dur, decay=8, amp=1.0, vib=0.0, vib_hz=6):
    t = t_(dur)
    f = freq * (1 + vib * np.sin(2 * np.pi * vib_hz * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(ph) * env_exp(len(t), decay)


def bell(freq, dur=0.5, decay=7, amp=1.0, ratios=(1, 2.76, 5.4, 8.93), weights=(1, 0.5, 0.25, 0.12)):
    """Металлический «звон» (монета, колокольчик)."""
    out = np.zeros(int(SR * dur))
    for r, w in zip(ratios, weights):
        s = sine(freq * r, dur, decay * (1 + 0.5 * r / 5), w)
        out += s[: len(out)]
    return amp * out / sum(weights)


def noise_band(dur, lo, hi, decay=20, amp=1.0, attack=0.002):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    hi = min(hi, SR / 2 - 100)
    b, a = signal.butter(3, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    x = signal.lfilter(b, a, x)
    x = x / (np.max(np.abs(x)) + 1e-9)
    return amp * x * env_exp(n, decay, attack)


def noise_low(dur, cutoff, decay=6, amp=1.0, attack=0.01):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    b, a = signal.butter(2, cutoff / (SR / 2), btype="low")
    x = signal.lfilter(b, a, x)
    x = x / (np.max(np.abs(x)) + 1e-9)
    return amp * x * env_exp(n, decay, attack)


def chirp(f0, f1, dur, decay=10, amp=1.0, vib=0.0, vib_hz=18):
    t = t_(dur)
    f = f0 + (f1 - f0) * (t / dur)
    f = f * (1 + vib * np.sin(2 * np.pi * vib_hz * t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(ph) * env_exp(len(t), decay)


def formant(freq0, freq1, dur, formants, decay=6, amp=1.0, pulse=True, vib=0.0, vib_hz=5):
    """Голос: пилообразная волна через полосовые формантные фильтры."""
    t = t_(dur)
    f = freq0 + (freq1 - freq0) * (t / dur)
    f = f * (1 + vib * np.sin(2 * np.pi * vib_hz * t))
    ph = np.cumsum(f) / SR
    src = signal.sawtooth(2 * np.pi * ph)
    out = np.zeros_like(src)
    for fc, bw, g in formants:
        b, a = signal.butter(2, [(fc - bw / 2) / (SR / 2), (fc + bw / 2) / (SR / 2)], btype="band")
        out += g * signal.lfilter(b, a, src)
    out = out / (np.max(np.abs(out)) + 1e-9)
    n = len(t)
    e = np.minimum(np.arange(n) / (0.02 * SR), 1) * np.exp(-t * decay)
    return amp * out * e


def mix(*arrs):
    """Сложить дорожки разной длины."""
    n = max(len(a) for a in arrs)
    out = np.zeros(n)
    for a in arrs:
        out[: len(a)] += a
    return out


def place(parts, total=1.0):
    """Склеить [(время_старта, массив), ...] в одну дорожку."""
    out = np.zeros(int(SR * total))
    for start, arr in parts:
        i = int(SR * start)
        j = min(len(out), i + len(arr))
        if i < len(out):
            out[i:j] += arr[: j - i]
    return out


def finish(x, peak=0.55, fade=0.03):
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    n = int(SR * fade)
    x[:8] *= np.linspace(0, 1, 8)
    x[-n:] *= np.linspace(1, 0, n)
    # лёгкий ФНЧ против резкости
    b, a = signal.butter(2, 9000 / (SR / 2), btype="low")
    x = signal.lfilter(b, a, x)
    # обрезаем тишину в конце
    idx = np.where(np.abs(x) > 0.004)[0]
    if len(idx):
        x = x[: min(len(x), idx.max() + int(SR * 0.05))]
    return x


def save(path, x):
    pcm = np.clip(x, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((pcm * 32767).astype(np.int16).tobytes())


# ---------- готовые «звуки» ----------
def coin_clink(f=2900, dur=0.35, amp=1.0):
    return bell(f, dur, 11, amp, ratios=(1, 1.52, 2.6, 4.1), weights=(1, 0.7, 0.4, 0.2))


def coin_rustle(dur=0.35, n=7, lo=3500, hi=9000):
    parts = []
    for k in range(n):
        st = rng.uniform(0, dur * 0.7)
        parts.append((st, mix(noise_band(0.05, lo, hi, 60, rng.uniform(0.3, 0.8)), 0.3 * coin_clink(rng.uniform(2600, 4200), 0.12, rng.uniform(0.2, 0.5)))))
    return place(parts, dur + 0.1)


def squeak(f0=1500, f1=2300, dur=0.12, amp=0.7):
    return chirp(f0, f1, dur, 14, amp, vib=0.02, vib_hz=30)


def page_rustle(dur=0.3, lo=2500, hi=7000):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    b, a = signal.butter(3, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], btype="band")
    x = signal.lfilter(b, a, x)
    t = np.arange(n) / SR
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2 * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t) ** 2)
    return x / (np.max(np.abs(x)) + 1e-9) * e * 0.8


def sparkle(base=1318, n=3, step=1.26, gap=0.09, dur=0.35):
    parts = []
    for k in range(n):
        parts.append((k * gap, bell(base * step ** k, dur, 9, 0.9, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2))))
    return place(parts, n * gap + dur + 0.05)


def oink(f0=210, f1=150, dur=0.16, amp=0.8):
    return formant(f0, f1, dur, [(900, 300, 1.0), (1700, 400, 0.6)], decay=9, amp=amp, vib=0.04, vib_hz=40)


def hoot(f=360, dur=0.34, amp=0.8):
    t = t_(dur)
    s = mix(sine(f, dur, 5, 1.0, vib=0.012, vib_hz=5), 0.25 * sine(f * 2, dur, 6, 1.0, vib=0.012, vib_hz=5))
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.7
    return amp * s * e


def yip(f0=700, f1=1050, dur=0.12, amp=0.9):
    return formant(f0, f1, dur, [(1100, 350, 1.0), (2400, 600, 0.7)], decay=10, amp=amp, vib=0.03, vib_hz=35)


def grunt(f0=130, f1=110, dur=0.22, amp=0.9):
    return formant(f0, f1, dur, [(500, 200, 1.0), (1000, 300, 0.5)], decay=8, amp=amp)


def wood_knock(f=300, dur=0.1, amp=0.8):
    return mix(sine(f, dur, 40, amp), 0.4 * noise_band(0.05, 500, 2500, 60, 0.8))


def tick(f=1800, amp=0.8):
    return mix(sine(f, 0.04, 90, amp), 0.5 * noise_band(0.02, 2000, 6000, 150, 0.6))


def bubble(f0=380, f1=1100, dur=0.11, amp=0.8):
    return chirp(f0, f1, dur, 25, amp)


def water_splash(dur=0.45):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    b, a = signal.butter(2, [800 / (SR / 2), 4500 / (SR / 2)], btype="band")
    x = signal.lfilter(b, a, x)
    t = np.arange(n) / SR
    e = (1 - np.exp(-t * 60)) * np.exp(-t * 7)
    return x / (np.max(np.abs(x)) + 1e-9) * e * 0.9


def breath_sigh(dur=0.9):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    t = np.arange(n) / SR
    # срез фильтра плавно падает → «выдох»
    out = np.zeros(n)
    blocks = 18
    size = n // blocks
    for k in range(blocks):
        cutoff = 2600 - 1900 * k / blocks
        b, a = signal.butter(2, cutoff / (SR / 2), btype="low")
        out[k * size:(k + 1) * size] = signal.lfilter(b, a, x[k * size:(k + 1) * size])
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.3
    return out / (np.max(np.abs(out)) + 1e-9) * e * 0.6


def snort(dur=0.22):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    t = np.arange(n) / SR
    b, a = signal.butter(2, 1800 / (SR / 2), btype="low")
    x = signal.lfilter(b, a, x)
    am = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * 38 * t))
    e = np.minimum(t / 0.01, 1) * np.exp(-t * 9)
    return x / (np.max(np.abs(x)) + 1e-9) * am * e * 0.9


def rumble(dur=0.5, f=90):
    t = t_(dur)
    s = signal.sawtooth(2 * np.pi * np.cumsum(f * (1 + 0.15 * np.sin(2 * np.pi * 9 * t))) / SR)
    b, a = signal.butter(2, 380 / (SR / 2), btype="low")
    s = signal.lfilter(b, a, s)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.8
    return 0.9 * s / (np.max(np.abs(s)) + 1e-9) * e


def hum(f=220, dur=0.7, amp=0.7):
    t = t_(dur)
    tri = signal.sawtooth(2 * np.pi * np.cumsum(f * (1 + 0.02 * np.sin(2 * np.pi * 5 * t))) / SR, 0.5)
    b, a = signal.butter(2, 900 / (SR / 2), btype="low")
    s = signal.lfilter(b, a, tri)
    e = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 0.6
    return amp * s / (np.max(np.abs(s)) + 1e-9) * e


# ---------- набор по питомцам ----------
def pet_sounds():
    S = {}
    # Искорка: колокольчик / искристое арпеджио
    S["iskorka"] = (
        place([(0, bell(1568, 0.5, 8, 1.0, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2)))], 0.55),
        place([(0, sparkle(1175, 4, 1.26, 0.08, 0.4))], 0.8),
    )
    # Фунтя: звон копилки + тихое хрюканье
    S["funty"] = (
        place([(0, coin_clink(2700, 0.4)), (0.07, coin_clink(3300, 0.35, 0.7)), (0.13, noise_band(0.12, 3000, 8000, 40, 0.3))], 0.55),
        place([(0, coin_clink(2900, 0.4)), (0.1, oink(220, 160, 0.14, 0.45)), (0.3, oink(200, 140, 0.18, 0.4))], 0.65),
    )
    # Баксик: шуршание монет + фырканье
    S["baksik"] = (
        place([(0, coin_rustle(0.36)), (0.3, coin_clink(2500, 0.3, 0.8))], 0.65),
        place([(0, coin_rustle(0.25)), (0.22, snort(0.22)), (0.46, snort(0.16) * 0.7)], 0.72),
    )
    # Тяпа: плеск воды + довольный писк
    S["tyapa"] = (
        place([(0, bubble(380, 1100, 0.1, 0.9)), (0.1, bubble(450, 1300, 0.1, 0.8)), (0.22, bubble(520, 1500, 0.12, 0.7))], 0.4),
        place([(0, water_splash(0.4)), (0.28, squeak(1100, 1900, 0.1, 0.55)), (0.4, squeak(1300, 2200, 0.13, 0.6))], 0.6),
    )
    # Шуршик: быстрый хруст и шелест
    S["shurshik"] = (
        place([(k * 0.045 + rng.uniform(0, 0.012), noise_band(0.045, 1800, 5500, 70, rng.uniform(0.5, 1.0))) for k in range(6)], 0.4),
        place([(0, page_rustle(0.3, 4000, 9000)), (0.18, noise_band(0.05, 1800, 5500, 70, 0.8)), (0.24, noise_band(0.05, 1800, 5500, 70, 0.7)), (0.34, squeak(1700, 2500, 0.09, 0.45))], 0.5),
    )
    # Грошик: уханье и шелест страниц
    S["groshik"] = (
        place([(0, page_rustle(0.22)), (0.18, page_rustle(0.2, 3000, 8000))], 0.42),
        place([(0, hoot(380, 0.28, 0.8)), (0.3, hoot(330, 0.38, 0.8)), (0.62, page_rustle(0.22) * 0.7)], 0.9),
    )
    # Пенни: мягкий хруст бамбука + спокойный вздох
    S["penny"] = (
        place([(0, wood_knock(300, 0.1, 0.6)), (0.07, noise_band(0.12, 500, 2200, 25, 0.6)), (0.2, noise_band(0.08, 600, 2000, 35, 0.4))], 0.4),
        place([(0, wood_knock(280, 0.1, 0.5)), (0.12, noise_band(0.12, 500, 2200, 25, 0.5)), (0.3, breath_sigh(0.8))], 1.1),
    )
    # Копеечка: писк хомяка + монетка
    S["kopeechka"] = (
        place([(0, squeak(1800, 2500, 0.07, 0.6)), (0.09, squeak(2000, 2800, 0.07, 0.6)), (0.2, coin_clink(3100, 0.3, 0.8))], 0.55),
        place([(0, coin_clink(2800, 0.3)), (0.08, coin_clink(3300, 0.3, 0.8)), (0.16, coin_clink(3700, 0.3, 0.7)), (0.28, squeak(1900, 2700, 0.09, 0.5))], 0.65),
    )
    # Рублик: ворчание дракончика + золотой звон
    S["rublik"] = (
        place([(0, rumble(0.3, 95) * 0.8), (0.12, bell(1760, 0.4, 8, 0.7))], 0.55),
        place([(0, rumble(0.4, 85) * 0.7), (0.3, sparkle(1318, 4, 1.26, 0.07, 0.35))], 0.9),
    )
    # Капитал: страница + «динь» мудрости
    S["kapital"] = (
        place([(0, page_rustle(0.2)), (0.17, bell(1318, 0.5, 7, 0.8, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2)))], 0.65),
        place([(0, bell(988, 0.6, 5, 0.9, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2))), (0.2, bell(1480, 0.7, 5, 0.9, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2)))], 0.95),
    )
    # Центи: стопка монет + тихое ворчание
    S["centi"] = (
        place([(0, coin_clink(2300, 0.35)), (0.06, coin_clink(2600, 0.3, 0.8)), (0.12, coin_clink(2100, 0.3, 0.8))], 0.5),
        place([(0, grunt(130, 105, 0.22, 0.7)), (0.22, coin_clink(2400, 0.4))], 0.65),
    )
    # Амур: игривое чириканье
    S["amur"] = (
        place([(0, chirp(700, 900, 0.07, 14, 0.8, 0.02)), (0.08, chirp(900, 1200, 0.07, 14, 0.8, 0.02)), (0.16, chirp(1100, 1500, 0.09, 12, 0.8, 0.02))], 0.35),
        place([(0, chirp(700, 900, 0.07, 14, 0.7, 0.02)), (0.08, chirp(900, 1200, 0.07, 14, 0.7, 0.02)), (0.16, chirp(1100, 1500, 0.09, 12, 0.7, 0.02)), (0.3, coin_clink(3000, 0.3, 0.6)), (0.37, coin_clink(3500, 0.3, 0.5))], 0.7),
    )
    # Марли: радостное «йип»
    S["marley"] = (
        place([(0, yip(650, 1000, 0.12, 0.9)), (0.04, noise_band(0.03, 2000, 6000, 80, 0.15))], 0.25),
        place([(0, yip(650, 1000, 0.12, 0.8)), (0.16, yip(750, 1150, 0.13, 0.85)), (0.34, bell(1568, 0.4, 8, 0.6, ratios=(1, 2.0, 3.0), weights=(1, 0.4, 0.2)))], 0.75),
    )
    # Тоша: куча монет + довольное мычание
    S["tosha"] = (
        place([(rng.uniform(0, 0.25), coin_clink(rng.uniform(2300, 4300), 0.15, rng.uniform(0.3, 0.8))) for _ in range(9)], 0.45),
        place([(0, hum(220, 0.55, 0.7)), (0.4, coin_clink(2800, 0.3, 0.6)), (0.47, coin_clink(3400, 0.3, 0.5))], 0.85),
    )
    # Зося: писк + круглый звон
    S["zosya"] = (
        place([(0, squeak(2000, 2600, 0.06, 0.5)), (0.08, squeak(2100, 2800, 0.06, 0.5)), (0.17, bell(880, 0.5, 6, 0.9, ratios=(1, 2.0, 3.0), weights=(1, 0.5, 0.2)))], 0.65),
        place([(0, bell(659, 0.5, 6, 0.8, ratios=(1, 2.0, 3.0), weights=(1, 0.5, 0.2))), (0.14, bell(830, 0.5, 6, 0.8, ratios=(1, 2.0, 3.0), weights=(1, 0.5, 0.2))), (0.28, bell(988, 0.6, 6, 0.8, ratios=(1, 2.0, 3.0), weights=(1, 0.5, 0.2))), (0.5, squeak(2000, 2800, 0.08, 0.4))], 0.95),
    )
    # Крош: счёты/печатная машинка + звонок кассы
    S["krosh"] = (
        place([(k * 0.055, tick(1700 + 140 * k, 0.8)) for k in range(5)], 0.4),
        place([(k * 0.05, tick(1700 + 140 * k, 0.7)) for k in range(4)] + [(0.28, bell(2093, 0.6, 5, 0.9, ratios=(1, 2.0, 2.4), weights=(1, 0.5, 0.3)))], 0.95),
    )
    return S


def main(out):
    os.makedirs(out, exist_ok=True)
    total = 0
    for pid, (tx, xp) in pet_sounds().items():
        for kind, arr in (("tx", tx), ("xp", xp)):
            x = finish(arr)
            assert np.isfinite(x).all() and 0.15 < len(x) / SR < 1.3, (pid, kind, len(x) / SR)
            save(os.path.join(out, f"snd_{pid}_{kind}.wav"), x)
            total += 1
    print("звуков:", total)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
