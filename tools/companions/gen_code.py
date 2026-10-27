#!/usr/bin/env python3
"""Генерирует каталог питомцев для обеих платформ из spec.py.
Запуск из корня репозитория:  python3 tools/companions/gen_code.py
  → Koshelek/CompanionCatalog.swift
  → android/app/src/main/java/ru/koshelek/app/core/CompanionCatalog.kt
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from spec import PETS  # noqa: E402

MOODS = ["happy", "calm", "sad", "sleepy"]
SWIFT_OUT = "Koshelek/CompanionCatalog.swift"
KT_OUT = "android/app/src/main/java/ru/koshelek/app/core/CompanionCatalog.kt"


def check():
    ids = set()
    for p in PETS:
        assert p["id"] not in ids, p["id"]
        ids.add(p["id"])
        assert re.fullmatch(r"[a-z]+", p["id"]), p["id"]
        assert re.fullmatch(r"[0-9A-F]{6}", p["accent"]), p["id"]
        texts = [p["name"], p["role"], p["blurb"], p["sound"], p["voice"], p["feed"], p["greet"]]
        for m in MOODS:
            assert len(p[m]) >= 2, (p["id"], m)
            texts += p[m]
        for t in texts:
            assert '"' not in t and "$" not in t and "\\" not in t, (p["id"], t)
        for m in MOODS:
            for t in p[m]:
                assert len(t) <= 95, (p["id"], len(t), t)
        assert len(p["blurb"]) <= 110, p["id"]
    print("спецификация ок:", len(PETS), "питомцев")


def q(s):
    return '"' + s + '"'


def f(x):
    return repr(float(x))


def swift():
    out = ["""// Сгенерировано tools/companions/gen_code.py из tools/companions/spec.py — руками не править.
import Foundation

enum CompanionMood: String, CaseIterable {
    case happy, calm, sad, sleepy
    var title: String {
        switch self {
        case .happy: return "Радостный"
        case .calm: return "Спокойный"
        case .sad: return "Грустный"
        case .sleepy: return "Сонный"
        }
    }
}

/// Характер движения питомца (одинаков на iOS и Android).
struct CompanionMotionSpec {
    let rot: Double, rotHz: Double          // качание, градусы и частота
    let bob: Double, bobHz: Double          // подпрыгивание, доля высоты
    let squash: Double, squashHz: Double    // сжатие/растяжение
    let period: Double, duty: Double        // движение «вспышками»: период и доля активной части (0 — постоянно)
    let juggle: Bool                        // жонглирует монетками
}

struct CompanionDef: Identifiable, Hashable {
    let id: String          // латиницей, для ассетов и хранения
    let code: String        // кодовое имя
    let name: String        // имя на экране
    let role: String
    let blurb: String
    let accentHex: String
    let sound: String       // как звучит (для списка)
    let voice: String       // характер для ИИ
    let motion: CompanionMotionSpec
    let lines: [CompanionMood: [String]]
    let feedLine: String
    let greetLine: String
    var asset: String { "Pet-" + id }
    var soundTx: String { "snd_" + id + "_tx" }
    var soundXp: String { "snd_" + id + "_xp" }
    static func == (a: CompanionDef, b: CompanionDef) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum CompanionCatalog {
    static let defaultID = "iskorka"
    static let all: [CompanionDef] = ["""]
    for p in PETS:
        m = p["motion"]
        out.append("        CompanionDef(")
        out.append(f"            id: {q(p['id'])}, code: {q(p['code'])}, name: {q(p['name'])}, role: {q(p['role'])},")
        out.append(f"            blurb: {q(p['blurb'])},")
        out.append(f"            accentHex: {q(p['accent'])}, sound: {q(p['sound'])},")
        out.append(f"            voice: {q(p['voice'])},")
        out.append("            motion: CompanionMotionSpec(rot: %s, rotHz: %s, bob: %s, bobHz: %s, squash: %s, squashHz: %s, period: %s, duty: %s, juggle: %s),"
                   % (f(m["rot"]), f(m["rotHz"]), f(m["bob"]), f(m["bobHz"]), f(m["squash"]), f(m["squashHz"]), f(m["period"]), f(m["duty"]), "true" if m["juggle"] else "false"))
        out.append("            lines: [")
        for mood in MOODS:
            out.append(f"                .{mood}: [" + ", ".join(q(t) for t in p[mood]) + "],")
        out.append("            ],")
        out.append(f"            feedLine: {q(p['feed'])}, greetLine: {q(p['greet'])}")
        out.append("        ),")
    out.append("""    ]

    static func def(_ id: String) -> CompanionDef { all.first { $0.id == id } ?? all[0] }
}
""")
    return "\n".join(out)


def kotlin():
    out = ["""// Сгенерировано tools/companions/gen_code.py из tools/companions/spec.py — руками не править.
package ru.koshelek.app.core

import ru.koshelek.app.R

enum class CompanionMood(val raw: String, val title: String) {
    HAPPY("happy", "Радостный"), CALM("calm", "Спокойный"), SAD("sad", "Грустный"), SLEEPY("sleepy", "Сонный")
}

/** Характер движения питомца (одинаков на iOS и Android). */
data class CompanionMotionSpec(
    val rot: Double, val rotHz: Double,          // качание, градусы и частота
    val bob: Double, val bobHz: Double,          // подпрыгивание, доля высоты
    val squash: Double, val squashHz: Double,    // сжатие/растяжение
    val period: Double, val duty: Double,        // движение «вспышками»: период и доля активной части (0 — постоянно)
    val juggle: Boolean,                         // жонглирует монетками
)

data class CompanionDef(
    val id: String,          // латиницей, для хранения
    val code: String,        // кодовое имя
    val name: String,        // имя на экране
    val role: String,
    val blurb: String,
    val accentHex: String,
    val sound: String,       // как звучит (для списка)
    val voice: String,       // характер для ИИ
    val motion: CompanionMotionSpec,
    val lines: Map<CompanionMood, List<String>>,
    val feedLine: String,
    val greetLine: String,
    val art: Int,            // R.drawable.pet_*
    val soundTx: Int,        // R.raw.snd_*_tx
    val soundXp: Int,        // R.raw.snd_*_xp
)

object CompanionCatalog {
    const val DEFAULT_ID = "iskorka"
    val all: List<CompanionDef> = listOf("""]
    for p in PETS:
        m = p["motion"]
        out.append("        CompanionDef(")
        out.append(f"            id = {q(p['id'])}, code = {q(p['code'])}, name = {q(p['name'])}, role = {q(p['role'])},")
        out.append(f"            blurb = {q(p['blurb'])},")
        out.append(f"            accentHex = {q(p['accent'])}, sound = {q(p['sound'])},")
        out.append(f"            voice = {q(p['voice'])},")
        out.append("            motion = CompanionMotionSpec(%s, %s, %s, %s, %s, %s, %s, %s, %s),"
                   % (f(m["rot"]), f(m["rotHz"]), f(m["bob"]), f(m["bobHz"]), f(m["squash"]), f(m["squashHz"]), f(m["period"]), f(m["duty"]), "true" if m["juggle"] else "false"))
        out.append("            lines = mapOf(")
        for mood in MOODS:
            out.append(f"                CompanionMood.{mood.upper()} to listOf(" + ", ".join(q(t) for t in p[mood]) + "),")
        out.append("            ),")
        out.append(f"            feedLine = {q(p['feed'])}, greetLine = {q(p['greet'])},")
        out.append(f"            art = R.drawable.pet_{p['id']}, soundTx = R.raw.snd_{p['id']}_tx, soundXp = R.raw.snd_{p['id']}_xp,")
        out.append("        ),")
    out.append("""    )

    fun def(id: String): CompanionDef = all.firstOrNull { it.id == id } ?: all[0]
}
""")
    return "\n".join(out)


def main():
    check()
    open(SWIFT_OUT, "w", encoding="utf-8").write(swift())
    open(KT_OUT, "w", encoding="utf-8").write(kotlin())
    print("записано:", SWIFT_OUT, KT_OUT)


if __name__ == "__main__":
    main()
