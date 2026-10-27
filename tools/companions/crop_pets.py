#!/usr/bin/env python3
"""Нарезка питомцев из листов-картинок.

Использование:
    python3 crop_pets.py <лист1.jpg> <лист2.jpg> <лист3.jpg> <папка-вывода>

Каждый питомец вырезается с прозрачным фоном (GrabCut), оставляется самая большая
связная область (питомец + миска), потом всё приводится к квадрату 512x512.
Координаты рамок — в пикселях исходных листов 2576x1438.
"""
import sys
import numpy as np
import cv2
from PIL import Image
from scipy import ndimage as ndi

# id: (лист, (x0, y0, x1, y1))
BOXES = {
    # лист 1: свинка, енот, выдра, белка, сова, панда
    "funty":    (0, (80, 225, 540, 790)),
    "baksik":   (0, (730, 225, 1245, 790)),
    "tyapa":    (0, (1360, 255, 1975, 790)),
    "shurshik": (0, (2030, 235, 2500, 790)),
    "groshik":  (0, (1710, 880, 2080, 1345)),
    "penny":    (0, (2110, 875, 2510, 1345)),
    # лист 2: хомяк, дракон, лис
    "kopeechka": (1, (90, 305, 850, 1160)),
    "rublik":    (1, (900, 270, 1700, 1180)),
    "kapital":   (1, (1745, 295, 2515, 1175)),
    # лист 3: барсук, красная панда, щенок, утконос, шиншилла, ёжик
    "centi":  (2, (70, 215, 615, 815)),
    "amur":   (2, (730, 240, 1245, 800)),
    "marley": (2, (1380, 235, 1885, 795)),
    "tosha":  (2, (2010, 225, 2505, 795)),
    "zosya":  (2, (1045, 890, 1540, 1380)),
    "krosh":  (2, (1725, 940, 2190, 1405)),
}

OUT = 512  # итоговый размер стороны, px


def fit_bg(crop, ring=8):
    """Плоскость цвета фона по краю рамки (фон — мягкий градиент).
    Подгонка устойчивая: точки-выбросы (монетки, тени у края) отбрасываются."""
    h, w = crop.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    m = np.zeros((h, w), bool)
    m[:ring] = m[-ring:] = True
    m[:, :ring] = m[:, -ring:] = True
    pts = np.stack([xx[m] / w, yy[m] / h, np.ones(m.sum())], 1)
    vals = crop[m].astype(np.float32)
    keep = np.ones(len(pts), bool)
    med = np.median(vals, axis=0)
    keep &= np.linalg.norm(vals - med, axis=1) < 12
    coefs = None
    for _ in range(4):
        if keep.sum() < 30:
            break
        coefs = [np.linalg.lstsq(pts[keep], vals[keep, c], rcond=None)[0] for c in range(3)]
        pred = np.stack([pts @ coefs[c] for c in range(3)], 1)
        keep = np.linalg.norm(vals - pred, axis=1) < 6
    X = np.stack([xx.ravel() / w, yy.ravel() / h, np.ones(h * w)], 1)
    out = np.zeros((h, w, 3), np.float32)
    for c in range(3):
        out[..., c] = (X @ coefs[c]).reshape(h, w) if coefs else med[c]
    return out


def cut(img_rgb: np.ndarray, box, thr=17.0):
    x0, y0, x1, y1 = box
    crop = img_rgb[y0:y1, x0:x1].copy()
    h, w = crop.shape[:2]
    f = crop.astype(np.float32)
    bg = fit_bg(crop)
    dist = np.linalg.norm(f - bg, axis=2)
    ratio = f / np.maximum(bg, 1)
    # Тень: тот же оттенок, что у фона, но темнее
    spread = ratio.max(2) - ratio.min(2)
    lum = ratio.mean(2)
    shadow = (spread < 0.10) & (lum < 0.992) & (lum > 0.55) & (dist < 70)
    # Тень бывает только под миской (нижняя часть кадра); серый мех выше — это не тень
    low_rows = (np.arange(h)[:, None] > h * 0.72)
    shadow &= low_rows
    # Пятна свечения под миской: почти цвета фона, но не тень — тоже считаем фоном
    glow = (spread < 0.16) & (dist < 55) & (lum < 1.05) & low_rows
    shadow |= glow

    # Фон = похожее на фон/тень и связанное с краем рамки
    cand = (dist < thr) | shadow
    lab, n = ndi.label(cand)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    bgmask = np.isin(lab, edge[edge > 0])
    fg = ~bgmask
    fg = cv2.morphologyEx(fg.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    lab, n = ndi.label(fg)
    if n > 1:
        sizes = ndi.sum(fg, lab, range(1, n + 1))
        fg = (lab == (1 + int(np.argmax(sizes)))).astype(np.uint8)
    fg = ndi.binary_fill_holes(fg).astype(np.uint8)
    fg = cv2.morphologyEx(fg, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    fg = ndi.binary_fill_holes(fg).astype(np.uint8)
    # Срезаем «подставку» под миской. Она — в самом низу (последние ~14% высоты):
    # миска там сужается, а подставка снова расширяется.
    widths = np.convolve(fg.sum(1).astype(np.float32), np.ones(5) / 5, mode="same")
    rows = np.where(fg.any(1))[0]
    top, bot = int(rows.min()), int(rows.max())
    start = int(bot - 0.14 * (bot - top))
    seg = widths[start:bot - 2]
    if len(seg) > 10:
        k = int(np.argmin(seg))
        low_y = start + k
        if widths[low_y + 3: bot].size and widths[low_y + 3: bot].max() > widths[low_y] + 5:
            fg[low_y + 2:, :] = 0
    # Бледные заплатки у дна (почти белое/кремовое) — остатки фона; миска насыщенная, её не трогаем
    rows = np.where(fg.any(1))[0]
    lo = int(rows.max() - 0.22 * (rows.max() - rows.min()))
    mx2, mn2 = f.max(2), f.min(2)
    sat2 = (mx2 - mn2) / np.maximum(mx2, 1)
    pale = (mn2 > 200) & (sat2 < 0.20)
    pale[:lo] = False
    fg[pale] = 0
    fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    lab2, n2 = ndi.label(fg)
    if n2 > 1:
        sizes2 = ndi.sum(fg, lab2, range(1, n2 + 1))
        fg = (lab2 == (1 + int(np.argmax(sizes2)))).astype(np.uint8)
    fg = cv2.erode(fg, np.ones((3, 3), np.uint8), iterations=1)
    a_fg = cv2.GaussianBlur(fg.astype(np.float32), (0, 0), 1.2)
    a_fg = np.clip((a_fg - 0.2) / 0.6, 0, 1)

    # Мягкая тень под миской: только рядом с питомцем и ниже его середины
    near = cv2.dilate(fg, np.ones((61, 61), np.uint8)).astype(bool)
    ys = np.where(fg.any(1))[0]
    mid = (ys.min() + ys.max()) // 2
    low = np.zeros((h, w), bool)
    low[mid:] = True
    sh_a = np.clip((1 - lum) * 2.2, 0, 0.45)
    sh_a = np.where(shadow & near & low & (fg == 0), sh_a, 0)
    sh_a = cv2.GaussianBlur(sh_a.astype(np.float32), (0, 0), 3)

    alpha = np.maximum(a_fg, sh_a)
    rgb = np.where((a_fg > 0.02)[..., None], crop.astype(np.float32), 0)
    # Убираем светлую кайму на краю: края берём чуть темнее
    rgba = np.dstack([rgb, alpha * 255]).clip(0, 255).astype(np.uint8)
    return rgba


def to_square(rgba: np.ndarray, size=OUT, pad=0.04):
    ys, xs = np.where(rgba[..., 3] > 8)
    rgba = rgba[ys.min(): ys.max() + 1, xs.min(): xs.max() + 1]
    h, w = rgba.shape[:2]
    side = int(max(h, w) * (1 + pad * 2))
    canvas = np.zeros((side, side, 4), np.uint8)
    oy, ox = (side - h) // 2, (side - w) // 2
    canvas[oy: oy + h, ox: ox + w] = rgba
    im = Image.fromarray(canvas, "RGBA").resize((size, size), Image.LANCZOS)
    return im


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        sys.exit(1)
    sheets = [np.array(Image.open(p).convert("RGB")) for p in sys.argv[1:4]]
    out = sys.argv[4]
    import os
    os.makedirs(out, exist_ok=True)
    for pid, (s, box) in BOXES.items():
        im = to_square(cut(sheets[s], box))
        im.save(f"{out}/{pid}.png", optimize=True)
        print(pid, "ok")


if __name__ == "__main__":
    main()
