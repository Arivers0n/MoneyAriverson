package ru.koshelek.app.ui

import android.content.Context
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.*
import ru.koshelek.app.data.Server

/** Состояние входа через Google / Яндекс: браузер открывается, а код возвращается ссылкой koshelek://oauth. */
object Auth {
    var busy by mutableStateOf<String?>(null)
    var error by mutableStateOf<String?>(null)

    fun open(ctx: Context, p: Server.OAuthProvider) {
        busy = p.name; error = null
        val url = Server.beginOAuth(p)
        runCatching { CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(ctx, Uri.parse(url)) }
            .onFailure { busy = null; error = "Не удалось открыть браузер" }
    }
    fun done() { busy = null; error = null; Router.showWelcome = false }
    fun fail(msg: String?) { busy = null; error = msg }
}
