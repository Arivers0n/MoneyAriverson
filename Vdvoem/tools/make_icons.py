#!/usr/bin/env python3
"""Рисует значки приложения (1024 px) в Vdvoem/Assets.xcassets. Запуск: python3 Vdvoem/tools/make_icons.py"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops
ImageChopsSubtract = ImageChops.subtract

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

def blob(im, color, box, blur):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse(box, fill=color)
    return Image.alpha_composite(im, layer.filter(ImageFilter.GaussianBlur(blur)))

def sparkle(d, cx, cy, r, alpha=230):
    pts = []
    for i in range(8):
        rr = r if i % 2 == 0 else r * 0.22
        a = -math.pi / 2 + i * math.pi / 4
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=(255, 255, 255, alpha))

def make(name, a, b, kind):
    ca, cb = rgb(a), rgb(b)
    im = gradient(a, b).convert("RGBA")
    # цветные световые пятна для глубины
    im = blob(im, ca + (200,), (-250, -300, 650, 500), 110)
    im = blob(im, tuple(min(255, int(v * 1.25)) for v in cb) + (170,), (420, 520, 1250, 1300), 120)
    im = blob(im, (255, 255, 255, 70), (150, -150, 900, 350), 90)

    mask = shape_mask(kind)
    # тень фигуры
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(mask.filter(ImageFilter.GaussianBlur(34)).point(lambda v: int(v * 0.40)))
    moved = Image.new("RGBA", (S, S), (0, 0, 0, 0)); moved.paste(sh, (0, 26))
    im = Image.alpha_composite(im, moved)

    # объёмная фигура: градиент белый -> светлый оттенок + внутренний блик
    fig = Image.new("RGBA", (S, S))
    px = fig.load()
    tint = tuple(int(255 - (255 - v) * 0.30) for v in ca)
    for y in range(S):
        t = y / (S - 1)
        col = tuple(int(255 * (1 - t) + tint[k] * t) for k in range(3))
        for x in range(S):
            px[x, y] = col + (255,)
    fig.putalpha(mask)
    im = Image.alpha_composite(im, fig)
    # внутренняя тень снизу и блик сверху
    inner = mask.filter(ImageFilter.GaussianBlur(14))
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rim.putalpha(Image.eval(ImageChopsSubtract(mask, inner), lambda v: min(255, v * 2)))
    rimc = Image.new("RGBA", (S, S), tuple(max(0, int(v * 0.65)) for v in cb) + (255,))
    rimc.putalpha(rim.getchannel("A").point(lambda v: int(v * 0.35)))
    im = Image.alpha_composite(im, rimc)
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse((S*0.22, S*0.12, S*0.78, S*0.46), fill=(255, 255, 255, 120))
    gm = Image.new("L", (S, S), 0); gm.paste(mask, (0, 0))
    gloss.putalpha(Image.fromarray(__import__("numpy").minimum(__import__("numpy").array(gloss.getchannel("A")), __import__("numpy").array(gm))))
    im = Image.alpha_composite(im, gloss.filter(ImageFilter.GaussianBlur(30)))
    # искры
    sp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(sp)
    sparkle(d, 800, 230, 62); sparkle(d, 230, 760, 42, 200); sparkle(d, 850, 700, 26, 170); sparkle(d, 190, 270, 22, 160)
    im = Image.alpha_composite(im, sp.filter(ImageFilter.GaussianBlur(0.8)))
    d2 = os.path.join(ROOT, name + ".appiconset")
    os.makedirs(d2, exist_ok=True)
    im.convert("RGB").save(os.path.join(d2, "icon.png"))
    json.dump({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(d2, "Contents.json"), "w"), indent=2)

os.makedirs(ROOT, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(ROOT, "Contents.json"), "w"))
for n, a, b, k in ICONS:
    make(n, a, b, k)
    print("ok", n)
