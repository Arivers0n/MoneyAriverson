#!/usr/bin/env python3
"""Рисует значки приложения (1024 px) в Vdvoem/Assets.xcassets. Запуск: python3 Vdvoem/tools/make_icons.py"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets.xcassets")
S = 1024
ICONS = [  # id, цвет A, цвет B, фигура
    ("AppIcon", "FF8FB1", "E0457B", "heart"), ("AppIcon-Night", "2B3A67", "0B1026", "moon"),
    ("AppIcon-Ocean", "5EC8F2", "2563EB", "drop"), ("AppIcon-Sunset", "FDBA74", "EC4899", "heart"),
    ("AppIcon-Lavender", "C4B5FD", "7C3AED", "inf"), ("AppIcon-Gold", "FDE68A", "D97706", "star"),
    ("AppIcon-Mint", "86EFAC", "059669", "spark"), ("AppIcon-Peach", "FFC8A8", "FB7185", "heart"),
    ("AppIcon-Candy", "F9A8D4", "60A5FA", "inf"), ("AppIcon-Aurora", "6EE7B7", "8B5CF6", "spark"),
    ("AppIcon-Cosmos", "4C1D95", "0F172A", "star"), ("AppIcon-Mono", "9CA3AF", "374151", "heart"),
    ("AppIcon-Neon", "22D3EE", "A855F7", "spark"), ("AppIcon-Berry", "F472B6", "9D174D", "drop"),
    ("AppIcon-Lime", "BEF264", "22C55E", "heart"), ("AppIcon-Ink", "1F2937", "000000", "inf"),
]

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def gradient(a, b):
    ca, cb = rgb(a), rgb(b)
    im = Image.new("RGB", (S, S))
    px = im.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S - 2)
            px[x, y] = tuple(int(ca[i] + (cb[i] - ca[i]) * t) for i in range(3))
    return im

def shape_mask(kind):
    m = Image.new("L", (S * 2, S * 2), 0)
    d = ImageDraw.Draw(m)
    c = S  # центр в удвоенной сетке
    if kind == "heart":
        pts = []
        for i in range(400):
            t = i / 400 * 2 * math.pi
            x = 16 * math.sin(t) ** 3
            y = 13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t)
            pts.append((c + x * 46, c - y * 46 - 30))
        d.polygon(pts, fill=255)
    elif kind == "moon":
        d.ellipse((c-330, c-330, c+330, c+330), fill=255)
        d.ellipse((c-130, c-420, c+470, c+180), fill=0)
    elif kind == "drop":
        d.ellipse((c-280, c-120, c+280, c+440), fill=255)
        d.polygon([(c, c-460), (c-262, c+60), (c+262, c+60)], fill=255)
    elif kind == "star":
        pts = []
        for i in range(10):
            r = 430 if i % 2 == 0 else 190
            a = -math.pi/2 + i * math.pi/5
            pts.append((c + r*math.cos(a), c + r*math.sin(a) + 20))
        d.polygon(pts, fill=255)
    elif kind == "spark":
        pts = []
        for i in range(8):
            r = 440 if i % 2 == 0 else 110
            a = -math.pi/2 + i * math.pi/4
            pts.append((c + r*math.cos(a), c + r*math.sin(a)))
        d.polygon(pts, fill=255)
    elif kind == "inf":
        for cx in (c-170, c+170):
            d.ellipse((cx-200, c-200, cx+200, c+200), outline=255, width=86)
    if kind != "heart":
        return m.crop((S // 2, S // 2, S // 2 + S, S // 2 + S))
    return m.resize((S, S), Image.LANCZOS)

def make(name, a, b, kind):
    im = gradient(a, b).convert("RGBA")
    # мягкий блик сверху
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((-200, -500, S+200, 420), fill=(255, 255, 255, 40))
    im = Image.alpha_composite(im, glow.filter(ImageFilter.GaussianBlur(40)))
    mask = shape_mask(kind)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.28)))
    shifted = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shifted.paste(shadow, (0, 18))
    im = Image.alpha_composite(im, shifted)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    white.putalpha(mask)
    im = Image.alpha_composite(im, white)
    d = os.path.join(ROOT, name + ".appiconset")
    os.makedirs(d, exist_ok=True)
    im.convert("RGB").save(os.path.join(d, "icon.png"))
    json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d, "Contents.json"), "w"), indent=2)

os.makedirs(ROOT, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "Contents.json"), "w"))
for n, a, b, k in ICONS:
    make(n, a, b, k)
    print("ok", n)
