#!/usr/bin/env python3
"""Рисует значки приложения (1024 px) в Vdvoem/Assets.xcassets.
Знак — два пересекающихся стеклянных круга («вдвоём»), как PairMark в самом приложении.
Запуск: python3 Vdvoem/tools/make_icons.py"""
import json, os, shutil
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets.xcassets")
S = 1024
K = 2                      # суперсэмплинг для гладких краёв
N = S * K

# id, фон сверху-слева, фон снизу-справа, свечение, (светлый значок? цвета кругов)
ICONS = [
    ("AppIcon",          "8FDDF5", "0889BF", "FF9CCB", None),   # Лагуна
    ("AppIcon-Night",    "24398A", "060A22", "F2683F", None),   # Полночь
    ("AppIcon-Indigo",   "7B88FF", "2328A0", "FF8DC0", None),   # Индиго
    ("AppIcon-Mint",     "4FD9B3", "0A5F49", "FFB199", None),   # Малахит
    ("AppIcon-Gold",     "FFD98A", "D4771F", "2BB8A8", None),   # Янтарь
    ("AppIcon-Berry",    "FF86A6", "A81E4B", "8FE3C9", None),   # Вишня
    ("AppIcon-Sunset",   "FFCDA3", "7C5CE0", "FF6B57", None),   # Закат
    ("AppIcon-Lavender", "E0D2FF", "7240D6", "FFC670", None),   # Сирень
    ("AppIcon-Aurora",   "6EE7B7", "6D3FE0", "3BA7FF", None),   # Аврора
    ("AppIcon-Mono",     "646B7A", "15181F", "E3B341", None),   # Графит
    ("AppIcon-Ink",      "26262C", "000000", "5A5A66", None),   # Тушь
    ("AppIcon-Neon",     "5B22B8", "07060F", "00E0C6", None),   # Неон
    ("AppIcon-Mocha",    "E3B08A", "4A2A1E", "FFF0E0", None),   # Мокко
    ("AppIcon-Toy",      "FFB8DE", "7E74FF", "FFE066", None),   # Игривый
    ("AppIcon-Paper",    "FAF4E8", "E8D9B8", "FFFFFF", ("B5533C", "4F7A5A")),  # Бумага
    ("AppIcon-Pearl",    "FBFAF7", "E2DED7", "FFFFFF", ("E4456F", "0593C6")),  # Жемчуг: цветные круги на светлом
]
REMOVED = ["AppIcon-Ocean", "AppIcon-Peach", "AppIcon-Candy", "AppIcon-Cosmos", "AppIcon-Neon", "AppIcon-Lime"]

def rgb(h): return np.array([int(h[i:i+2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0

yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
xn, yn = xx / N, yy / N

def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def disc(cx, cy, r, feather=1.5):
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    return np.clip((r - d) / feather + 0.5, 0, 1)

def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r * K)), dtype=np.float32) / 255.0

def over(base, color, alpha):
    a = alpha[..., None]
    return base * (1 - a) + np.asarray(color, dtype=np.float32) * a

def make(name, a, b, glow, pair):
    ca, cb, cg = rgb(a), rgb(b), rgb(glow)
    t = (xn * 0.45 + yn * 0.85) / 1.3
    t = smooth(0.0, 1.0, t)[..., None]
    im = ca * (1 - t) + cb * t
    # мягкое цветное свечение в правом нижнем углу и блик сверху слева
    g = np.exp(-(((xn - 0.92) / 0.55) ** 2 + ((yn - 0.98) / 0.50) ** 2))
    im = over(im, cg, g * (0.26 if pair is None else 0.0))
    top = np.exp(-(((xn - 0.18) / 0.5) ** 2 + ((yn - 0.02) / 0.35) ** 2))
    im = over(im, [1, 1, 1], top * (0.22 if pair is None else 0.55))

    R, off = 0.245 * N, 0.135 * N
    cx1, cx2, cy = N / 2 - off, N / 2 + off, N / 2 + 0.01 * N
    d1, d2 = disc(cx1, cy, R), disc(cx2, cy, R)
    lens = d1 * d2

    # тень под знаком
    sh = blur(np.maximum(d1, d2), 26)
    shifted = np.roll(sh, int(0.018 * N), axis=0)
    shadow_a = 0.30 if pair is None else 0.16
    im = over(im, [0, 0, 0], shifted * shadow_a)

    if pair is None:
        # Матовое стекло: круги белые с градиентом прозрачности сверху вниз
        vert = 1 - smooth(cy - R, cy + R, yy)
        for d, edge in ((d1, 0), (d2, 0)):
            al = d * (0.40 + 0.24 * vert)
            im = over(im, [1, 1, 1], al)
        # пересечение — самое светлое
        im = over(im, [1, 1, 1], lens * (0.42 + 0.20 * vert))
        # контур кругов
        for cx in (cx1, cx2):
            ring = np.clip(disc(cx, cy, R + 3 * K) - disc(cx, cy, R - 3 * K), 0, 1)
            im = over(im, [1, 1, 1], ring * 0.82)
        # блик на дуге сверху у каждого круга
        for cx in (cx1, cx2):
            arc = disc(cx, cy, R * 0.93) * (1 - disc(cx - 0.05 * R, cy + 0.10 * R, R * 0.93))
            arc *= smooth(cy + 0.15 * R, cy - 0.85 * R, yy)
            im = over(im, [1, 1, 1], blur(arc, 5) * 0.55)
    else:
        c1, c2 = rgb(pair[0]), rgb(pair[1])
        im = over(im, c1, d1 * 0.93)
        im = over(im, c2, d2 * 0.93)
        # пересечение — «смешанный» цвет (умножение), чуть темнее и насыщеннее
        mix = c1 * c2 * 1.25
        mix = np.clip(mix + 0.08, 0, 1)
        im = over(im, mix, lens * 0.95)
        for cx in (cx1, cx2):
            arc = disc(cx, cy, R * 0.93) * (1 - disc(cx - 0.05 * R, cy + 0.10 * R, R * 0.93))
            arc *= smooth(cy + 0.15 * R, cy - 0.85 * R, yy)
            im = over(im, [1, 1, 1], blur(arc, 5) * 0.35)

    # искра у верхнего правого круга
    def spark(cx, cy_, r, al):
        dx, dy = np.abs(xx - cx), np.abs(yy - cy_)
        s = np.clip(1 - (dx / (r * 0.16) + dy / r) , 0, 1) + np.clip(1 - (dx / r + dy / (r * 0.16)), 0, 1)
        return np.clip(s, 0, 1) * al
    sp = spark(0.83 * N, 0.20 * N, 0.075 * N, 0.95 if pair is None else 0.0)
    im = over(im, [1, 1, 1], blur(sp, 0.8))

    out = Image.fromarray((np.clip(im, 0, 1) * 255).astype(np.uint8)).resize((S, S), Image.LANCZOS)
    d = os.path.join(ROOT, name + ".appiconset")
    os.makedirs(d, exist_ok=True)
    out.save(os.path.join(d, "icon.png"))
    json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)

os.makedirs(ROOT, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "Contents.json"), "w"))
for r in REMOVED:
    shutil.rmtree(os.path.join(ROOT, r + ".appiconset"), ignore_errors=True)
for n, a, b, g, p in ICONS:
    make(n, a, b, g, p)
    print("ok", n)
