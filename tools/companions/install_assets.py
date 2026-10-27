#!/usr/bin/env python3
"""Раскладывает картинки питомцев по ассетам обеих платформ.
Использование (из корня репозитория): python3 tools/companions/install_assets.py <папка-с-png>
iOS:     Koshelek/Assets.xcassets/Pet-<id>.imageset/pet.png
Android: android/app/src/main/res/drawable-nodpi/pet_<id>.png"""
import json
import os
import shutil
import sys

IDS = ["iskorka", "funty", "baksik", "tyapa", "shurshik", "groshik", "penny",
       "kopeechka", "rublik", "kapital", "centi", "amur", "marley", "tosha", "zosya", "krosh"]


def main(src):
    for pid in IDS:
        f = os.path.join(src, pid + ".png")
        if not os.path.exists(f):
            print("нет файла", f)
            sys.exit(1)
        ios = f"Koshelek/Assets.xcassets/Pet-{pid}.imageset"
        os.makedirs(ios, exist_ok=True)
        shutil.copy(f, f"{ios}/pet.png")
        json.dump({"images": [{"filename": "pet.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, open(f"{ios}/Contents.json", "w"), indent=1)
        and_dir = "android/app/src/main/res/drawable-nodpi"
        os.makedirs(and_dir, exist_ok=True)
        shutil.copy(f, f"{and_dir}/pet_{pid}.png")
    # звуки: iOS Koshelek/Sounds, Android res/raw
    snd = os.path.join(src, "sounds")
    if os.path.isdir(snd):
        os.makedirs("Koshelek/Sounds", exist_ok=True)
        os.makedirs("android/app/src/main/res/raw", exist_ok=True)
        for f in os.listdir(snd):
            if f.endswith(".wav"):
                shutil.copy(os.path.join(snd, f), "Koshelek/Sounds/" + f)
                shutil.copy(os.path.join(snd, f), "android/app/src/main/res/raw/" + f)
    print("готово:", len(IDS), "питомцев")


if __name__ == "__main__":
    main(sys.argv[1])
