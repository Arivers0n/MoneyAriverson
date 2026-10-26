package ru.koshelek.app

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import ru.koshelek.app.core.Calc
import ru.koshelek.app.core.Catalog
import ru.koshelek.app.core.Fmt
import ru.koshelek.app.data.*
import ru.koshelek.app.ui.*

class KopilkaApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Settings.init(this)
        Store.init(this)
        SyncEngine.init()
        Haptic.init(this)
        Fmt.showKopecks = Look.showKopecks
        Calc.debtInTotals = Look.debtInTotals
        Updater.init(this)
    }
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT))
        handle(intent)
        setContent {
            KopilkaTheme {
                LaunchedEffect(Unit) { Store.snapshot.value.prefs.cats.let(Catalog::update) }
                AppRoot()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { SyncEngine.sync() }
        Updater.check()
        // Окно входа закрыли, не войдя, — убираем «загрузку» с кнопки
        if (Auth.busy != null) lifecycleScope.launch { kotlinx.coroutines.delay(2000); if (!Server.loggedIn) Auth.busy = null }
    }

    private fun handle(intent: Intent?) {
        val uri: Uri = intent?.data ?: return
        if (uri.scheme != "koshelek") return
        when (uri.host) {
            "oauth" -> {
                val code = uri.getQueryParameter("code"); val state = uri.getQueryParameter("state") ?: ""
                val err = uri.getQueryParameter("error")
                if (code.isNullOrEmpty()) { Auth.fail(if (err != null) "Вход отменён" else null); return }
                lifecycleScope.launch {
                    runCatching { Server.completeOAuth(code, state) }
                        .onSuccess { Auth.done(); Haptic.success(); Router.say("Вы вошли — данные синхронизируются") }
                        .onFailure { Auth.fail(it.message) }
                }
            }
            "connect" -> {
                uri.getQueryParameter("server")?.takeIf { it.isNotBlank() }?.let { Server.url = it }
                uri.getQueryParameter("code")?.takeIf { it.isNotBlank() }?.let { Settings.setStr("pendingJoin", it.uppercase()) }
                if (Server.loggedIn) lifecycleScope.launch { SyncEngine.joinPending() } else Router.showWelcome = true
            }
            "voice" -> Router.voiceOn = true
            "scan" -> Router.scanRequest++
            "new" -> Router.show(Route.NewTx)
        }
    }
}
