#!/usr/bin/env python3
"""Рисует Искорку (базовый питомец) — золотую искру в такой же миске, как у остальных.
Использование: python3 make_iskorka.py <папка-вывода>   → iskorka.png 512x512
Если есть оригинальная Искорка из HabitFlow — просто подложите её как iskorka.png."""
import sys, os
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFilter

N = 2048


def radial(cx, cy, r, c_in, c_out):
    yy, xx = np.mgrid[0:N, 0:N]
    d = np.clip(np.hypot(xx - cx, yy - cy) / r, 0, 1)[..., None]
    return (np.array(c_in) * (1 - d) + np.array(c_out) * d).astype(np.uint8)


def vgrad(y0, y1, c0, c1):
    yy = np.clip((np.arange(N) - y0) / max(1, (y1 - y0)), 0, 1)[:, None, None]
    return (np.array(c0) * (1 - yy) + np.array(c1) * yy).astype(np.uint8) * np.ones((1, N, 1), np.uint8)


def paste(base, color_arr, mask):
    m = np.asarray(mask, np.float32)[..., None] / 255.0
    base[...] = (base * (1 - m) + color_arr * m).astype(np.uint8)


def main(out):
    os.makedirs(out, exist_ok=True)
    img = np.zeros((N, N, 3), np.uint8)
    alpha = np.zeros((N, N), np.uint8)

    # --- миска: задняя стенка
    back = Image.new("L", (N, N), 0)
    ImageDraw.Draw(back).ellipse((330, 880, 1718, 1180), fill=255)
    paste(img, np.full((N, N, 3), (176, 118, 84), np.uint8), back)
    alpha = np.maximum(alpha, np.array(back))

    # --- тело-искра: четырёхлучевая звезда со скруглением
    star = Image.new("L", (N, N), 0)
    cx, cy, R, r = 1024, 800, 640, 250
    pts = []
    for k in range(8):
        ang = np.pi / 2 * (k / 2) - np.pi / 2
        rad = R if k % 2 == 0 else r
        pts.append((cx + rad * np.cos(ang), cy + rad * np.sin(ang)))
    ImageDraw.Draw(star).polygon(pts, fill=255)
    star = star.filter(ImageFilter.GaussianBlur(46)).point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.GaussianBlur(3))
    body = radial(cx, cy, 700, (255, 236, 150), (244, 174, 40))
    paste(img, body, star)
    alpha = np.maximum(alpha, np.array(star))

    # --- лицо
    face = Image.fromarray(img.copy())
    d = ImageDraw.Draw(face)
    for ex in (cx - 120, cx + 120):
        d.ellipse((ex - 46, cy - 40, ex + 46, cy + 60), fill=(54, 36, 28))
        d.ellipse((ex - 18, cy - 28, ex + 4, cy - 6), fill=(255, 255, 255))
    for bx in (cx - 215, cx + 215):
        d.ellipse((bx - 52, cy + 40, bx + 52, cy + 100), fill=(255, 150, 130))
    d.arc((cx - 70, cy + 20, cx + 70, cy + 120), 20, 160, fill=(120, 60, 40), width=14)
    img = np.array(face)

    # --- передняя стенка миски: от нижней дуги края до дна (полуэллипс)
    yy, xx = np.mgrid[0:N, 0:N]
    rx, ry_rim, ry_bowl, ccx, ccy = 694.0, 150.0, 520.0, 1024.0, 1030.0
    t = np.clip(1 - ((xx - ccx) / rx) ** 2, 0, 1)
    arc_y = ccy + ry_rim * np.sqrt(t)                       # нижняя дуга края
    bottom_y = ccy + ry_bowl * np.sqrt(t)                   # дно миски
    inside = (np.abs(xx - ccx) <= rx) & (yy >= arc_y) & (yy <= bottom_y)
    front = Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    bowl = vgrad(1030, 1550, (246, 196, 158), (212, 136, 98))
    paste(img, bowl, front)
    alpha = np.maximum(alpha, np.array(front))
    # светлая кромка по нижней дуге края
    rim = Image.new("L", (N, N), 0)
    ImageDraw.Draw(rim).arc((330, 880, 1718, 1180), 0, 180, fill=255, width=22)
    paste(img, np.full((N, N, 3), (255, 222, 190), np.uint8), rim.filter(ImageFilter.GaussianBlur(3)))
    # золотая монетка на миске
    coin = Image.new("L", (N, N), 0)
    ImageDraw.Draw(coin).ellipse((900, 1230, 1148, 1478), fill=255)
    paste(img, radial(1024, 1354, 150, (255, 232, 120), (226, 160, 24)), coin)
    cd = Image.fromarray(img)
    dd = ImageDraw.Draw(cd)
    dd.ellipse((936, 1266, 1112, 1442), outline=(196, 134, 16), width=10)
    dd.line((1000, 1300, 1000, 1410), fill=(176, 118, 10), width=14)
    dd.arc((972, 1296, 1070, 1366), 270, 90, fill=(176, 118, 10), width=14)
    dd.line((970, 1366, 1050, 1366), fill=(176, 118, 10), width=12)
    img = np.array(cd)

    rgba = np.dstack([img, alpha])
    ys, xs = np.where(alpha > 8)
    rgba = rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    h, w = rgba.shape[:2]
    side = int(max(h, w) * 1.08)
    canvas = np.zeros((side, side, 4), np.uint8)
    canvas[(side - h) // 2: (side - h) // 2 + h, (side - w) // 2: (side - w) // 2 + w] = rgba
    Image.fromarray(canvas, "RGBA").resize((512, 512), Image.LANCZOS).save(os.path.join(out, "iskorka.png"), optimize=True)
    print("iskorka ok")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
