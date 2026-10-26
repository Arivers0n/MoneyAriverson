package ru.koshelek.app.ui

import androidx.compose.runtime.*
import kotlinx.coroutines.*
import ru.koshelek.app.data.ParsedItem
import ru.koshelek.app.data.Tx

sealed class Route {
    data object NewTx : Route()
    data class EditTx(val tx: Tx) : Route()
    data class Review(val items: List<ParsedItem>, val subtitle: String) : Route()
    data object Settings : Route()
    data object Stats : Route()
    data object Payments : Route()
    data object Search : Route()
    data object Insights : Route()
    data object Accounts : Route()
    data class Goals(val tab: Int) : Route()
    data object Account : Route()
    data object Family : Route()
    data object Appearance : Route()
}

/** Навигация и общие состояния экрана (как Router на iPhone). */
object Router {
    var sheet by mutableStateOf<Route?>(null)
    var voiceOn by mutableStateOf(false)
    var scanRequest by mutableIntStateOf(0)
    var toast by mutableStateOf<String?>(null)
    var undo by mutableStateOf<(() -> Unit)?>(null)
    var celebrate by mutableStateOf<Pair<String, String>?>(null)
    var accFilter by mutableStateOf<String?>(null)
    var showWelcome by mutableStateOf(false)
    private var toastJob: Job? = null
    private val scope = MainScope()

    fun show(r: Route) {
        if (sheet != null) { sheet = null; scope.launch { delay(250); sheet = r } } else sheet = r
    }
    fun close() { sheet = null }
    fun scopeLaunch(block: suspend CoroutineScope.() -> Unit) { scope.launch(block = block) }

    fun say(t: String, undo: (() -> Unit)? = null) {
        this.undo = undo; toast = t
        toastJob?.cancel()
        toastJob = scope.launch { delay(if (undo == null) 2600 else 4500); toast = null; this@Router.undo = null }
    }
    fun runUndo() { val u = undo; undo = null; toast = null; Haptic.tap(); u?.invoke() }
}
