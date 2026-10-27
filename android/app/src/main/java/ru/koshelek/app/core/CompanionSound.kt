package ru.koshelek.app.core

import android.content.Context
import android.media.MediaPlayer
import ru.koshelek.app.ui.Look

/** Короткие звуки питомца. Выключаются настройкой «Звуки». */
object CompanionSound {
    private var ctx: Context? = null
    fun init(c: Context) { ctx = c.applicationContext }

    fun play(res: Int) {
        if (!Look.sounds) return
        val c = ctx ?: return
        runCatching {
            val mp = MediaPlayer.create(c, res) ?: return
            mp.setOnCompletionListener { it.release() }
            mp.setOnErrorListener { m, _, _ -> m.release(); true }
            mp.start()
        }
    }
    /** Звук при записи операции. */
    fun tx() = play(CompanionCatalog.def(CompanionEngine.petId).soundTx)
    /** Звук при опыте, уровне, угощении. */
    fun xp() = play(CompanionCatalog.def(CompanionEngine.petId).soundXp)
}
