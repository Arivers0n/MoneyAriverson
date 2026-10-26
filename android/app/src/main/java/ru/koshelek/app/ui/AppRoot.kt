package ru.koshelek.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import ru.koshelek.app.core.Catalog
import ru.koshelek.app.data.*

@Composable
fun AppRoot() {
    val snap by Store.snapshot.collectAsState()
    val login by SyncEngine.loginVersion.collectAsState()
    LaunchedEffect(snap.prefs.cats) { Catalog.update(snap.prefs.cats) }
    LaunchedEffect(Unit) {
        if (!Server.loggedIn && !Settings.bool("welcomed")) Router.showWelcome = true
    }
    LaunchedEffect(login) { if (Server.loggedIn) Router.showWelcome = false }
    LaunchedEffect(Unit) {
        Store.onNote = { n -> Router.scopeLaunch { delay(1600); Router.say(n) } }
        // Пока приложение открыто — подтягиваем изменения семьи раз в 20 секунд (как на iPhone)
        while (true) { delay(20_000); SyncEngine.sync() }
    }

    Box(Modifier.fillMaxSize().background(LocalPal.current.bg)) {
        HomeScreen()

        // Окна поверх главного экрана
        AnimatedContent(Router.sheet, transitionSpec = {
            if (Look.moves) (slideInVertically(Motion.entrance(420)) { it / 3 } + fadeIn(tween(220))) togetherWith
                (slideOutVertically(tween(260)) { it / 4 } + fadeOut(tween(200)))
            else fadeIn(tween(if (Look.animated) 180 else 0)) togetherWith fadeOut(tween(if (Look.animated) 140 else 0))
        }, label = "sheet") { r ->
            if (r != null) {
                BackHandler { Router.close() }
                Box(Modifier.fillMaxSize()) { Sheet(r) }
            } else Box(Modifier)
        }

        ScanFlow()

        AnimatedVisibility(Router.voiceOn, enter = fadeIn(tween(160)), exit = fadeOut(tween(200))) {
            BackHandler { Router.voiceOn = false }
            VoiceOverlay()
        }

        Toast(Modifier.align(Alignment.TopCenter))
        Celebrate()
        UpdateBanner(Modifier.align(Alignment.BottomCenter))

        AnimatedVisibility(Router.showWelcome, enter = fadeIn(tween(250)), exit = fadeOut(tween(300))) {
            BackHandler { Router.showWelcome = false; Settings.setBool("welcomed", true) }
            WelcomeScreen { Router.showWelcome = false; Settings.setBool("welcomed", true) }
        }
    }
}

@Composable
private fun Sheet(r: Route) {
    when (r) {
        Route.NewTx -> TxForm(null)
        is Route.EditTx -> TxForm(r.tx)
        is Route.Review -> ReviewScreen(r.items, r.subtitle)
        Route.Settings -> SettingsScreen()
        Route.Stats -> StatsScreen()
        Route.Payments -> PaymentsScreen()
        Route.Search -> SearchScreen()
        Route.Insights -> InsightsScreen()
        Route.Accounts -> AccountsScreen()
        is Route.Goals -> GoalsScreen(r.tab)
        Route.Account -> AccountScreen()
        Route.Family -> FamilyScreen()
        Route.Appearance -> AppearanceScreen()
    }
}

/** Общий каркас окна: фон, шапка и прокручиваемое содержимое. */
@Composable
fun SheetScaffold(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector? = null, onClose: () -> Unit = { Router.close() },
                  trailing: @Composable () -> Unit = {}, bottom: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize()) {
        Backdrop()
        Column(Modifier.fillMaxSize().statusBarsPadding()) {
            SheetBar(title, icon, onClose, trailing)
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                Column(Modifier.widthIn(max = 720.dp).fillMaxSize(), content = content)
            }
            if (bottom != null) Box(Modifier.fillMaxWidth().imePadding().navigationBarsPadding(), contentAlignment = Alignment.Center) {
                Box(Modifier.widthIn(max = 720.dp)) { bottom() }
            }
        }
    }
}

@Composable
private fun Toast(modifier: Modifier) {
    val p = LocalPal.current
    AnimatedVisibility(Router.toast != null, modifier.statusBarsPadding().padding(top = 8.dp),
        enter = slideInVertically(Motion.spring()) { -it * 2 } + fadeIn(), exit = slideOutVertically(tween(220)) { -it * 2 } + fadeOut()) {
        var last by remember { mutableStateOf("") }
        Router.toast?.let { last = it }
        Row(Modifier.padding(horizontal = 16.dp).glass(RoundedCornerShape(50)).padding(start = 18.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Rounded.CheckCircle, null, tint = p.inc, modifier = Modifier.size(20.dp))
            Text(last, color = p.text, fontWeight = FontWeight.Medium, fontSize = 15.sp, maxLines = 2)
            if (Router.undo != null) {
                Text("Отменить", color = p.accent, fontWeight = FontWeight.SemiBold, fontSize = 15.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).pressable({ Router.runUndo() }).padding(horizontal = 10.dp, vertical = 8.dp))
            } else Spacer(Modifier.width(10.dp))
        }
    }
}

/** Праздник: закрыт долг или копилка набрана. */
@Composable
private fun Celebrate() {
    val p = LocalPal.current
    val c = Router.celebrate
    LaunchedEffect(c) { if (c != null) { Haptic.success(); delay(2600); Router.celebrate = null } }
    AnimatedVisibility(c != null, enter = fadeIn() + scaleIn(spring(0.55f, 300f), 0.8f), exit = fadeOut() + scaleOut(targetScale = 0.9f)) {
        var last by remember { mutableStateOf("" to "") }
        c?.let { last = it }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)).pressable({ Router.celebrate = null }, 1f), contentAlignment = Alignment.Center) {
            Column(Modifier.padding(32.dp).cardBg(RoundedCornerShape(30.dp)).padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("🎉", fontSize = 56.sp)
                Text(last.first, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.text, textAlign = TextAlign.Center)
                Text(last.second, fontSize = 15.sp, color = p.secondary, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
private fun UpdateBanner(modifier: Modifier) {
    val p = LocalPal.current
    val b = Updater.available
    var hidden by remember { mutableStateOf(false) }
    AnimatedVisibility(b != null && !hidden && Router.sheet == null && !Router.voiceOn, modifier.navigationBarsPadding().padding(bottom = 112.dp, start = 16.dp, end = 16.dp),
        enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut()) {
        Row(Modifier.widthIn(max = 520.dp).glass(RoundedCornerShape(22.dp)).padding(start = 14.dp, end = 6.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(34.dp).clip(CircleShape).background(p.accent.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.SystemUpdate, null, tint = p.accent, modifier = Modifier.size(18.dp))
            }
            Column(Modifier.weight(1f)) {
                Text("Новая версия", color = p.text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                val pr = Updater.progress
                Text(Updater.error ?: if (pr != null) "Скачиваю… ${(pr * 100).toInt()}%" else (b?.notes?.ifEmpty { null } ?: "Обновления как на iPhone"),
                    color = if (Updater.error != null) p.exp else p.secondary, fontSize = 13.sp, maxLines = 2)
            }
            if (Updater.progress != null) CircularProgressIndicator(progress = { Updater.progress ?: 0f }, color = p.accent, strokeWidth = 3.dp, modifier = Modifier.size(26.dp).padding(2.dp))
            else Text("Обновить", color = p.onAccent, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(p.accent).pressable({ b?.let(Updater::install) }).padding(horizontal = 14.dp, vertical = 9.dp))
            Icon(Icons.Rounded.Close, "Позже", tint = p.tertiary, modifier = Modifier.size(32.dp).pressable({ hidden = true }).padding(6.dp))
        }
    }
}
