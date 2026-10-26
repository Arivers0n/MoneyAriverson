package ru.koshelek.app.ui

import android.content.Intent
import androidx.compose.animation.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import ru.koshelek.app.core.*
import ru.koshelek.app.data.*

private val iosBlue = hexColor("0A84FF"); private val iosPink = hexColor("FF2D55"); private val iosIndigo = hexColor("5E5CE6")
private val iosTeal = hexColor("30B0C7"); private val iosGreen = hexColor("34C759"); private val iosRed = hexColor("FF3B30")
private val iosGray = hexColor("8E8E93"); private val iosMint = hexColor("00C7BE"); private val iosPurple = hexColor("AF52DE"); private val iosOrange = hexColor("FF9500")

@Composable
fun SettingsScreen() {
    val p = LocalPal.current
    val ctx = LocalContext.current
    val snap by Store.snapshot.collectAsState()
    val st by SyncEngine.state.collectAsState()
    val login by SyncEngine.loginVersion.collectAsState()
    var wipe by remember { mutableStateOf(false) }
    login.hashCode()

    SheetScaffold("Настройки", Icons.Rounded.Settings) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
            Group("Аккаунт", if (!Server.loggedIn) "Синхронизация между телефонами и iPhone и общий семейный бюджет." else null) {
                Row(Modifier.fillMaxWidth().pressable({ Router.show(Route.Account) }, 0.98f).padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(if (Server.loggedIn) Icons.Rounded.VerifiedUser else Icons.Rounded.PersonAdd, null, tint = if (Server.loggedIn) p.inc else p.accent, modifier = Modifier.size(30.dp))
                    Column(Modifier.weight(1f)) {
                        Text(if (Server.loggedIn) Settings.str("userName").ifEmpty { Settings.str("userEmail") } else "Войти и синхронизировать", fontWeight = FontWeight.Medium, color = p.text)
                        Text(statusLine(st), fontSize = 13.sp, color = p.secondary)
                    }
                    Icon(Icons.Rounded.ChevronRight, null, tint = p.tertiary)
                }
                if (Server.loggedIn) { Divider1(); SettingRow("Бюджет", Icons.Rounded.Groups, iosBlue, detail = SyncEngine.currentSpace?.name ?: "Личное", onClick = { Router.show(Route.Family) }) }
            }
            Group {
                SettingRow("Оформление", Icons.Rounded.Palette, iosPink, detail = "темы, цвета, главный экран", onClick = { Router.show(Route.Appearance) })
            }
            Group("Отклик") {
                SettingRow("Вибрация", Icons.Rounded.Vibration, iosIndigo) { Switch(Look.haptics, { Look.haptics = it; Look.save(); Haptic.press() }, colors = sw(p)) }
                Divider1()
                SettingRow("Анимации", Icons.Rounded.AutoAwesome, iosTeal)
                Segmented(listOf("Все", "Спокойные", "Выкл"), when (Look.motion) { "full" -> 0; "reduced" -> 1; else -> 2 }, { Look.motion = listOf("full", "reduced", "off")[it]; Look.save() })
            }
            Group("Расчёты") {
                SettingRow("Показывать копейки", Icons.Rounded.Tag, iosGray) { Switch(Look.showKopecks, { Look.showKopecks = it; Look.save() }, colors = sw(p)) }
                Divider1()
                SettingRow("Всегда показывать доходы", Icons.Rounded.ArrowCircleDown, iosGreen) { Switch(Look.alwaysIncome, { Look.alwaysIncome = it; Look.save() }, colors = sw(p)) }
                Divider1()
                SettingRow("Долги в итогах месяца", Icons.Rounded.CreditCard, iosRed) { Switch(Look.debtInTotals, { Look.debtInTotals = it; Look.save(); Store.publish() }, colors = sw(p)) }
                Divider1()
                SettingRow("Лимит расходов", Icons.Rounded.Speed, iosMint, detail = if (snap.prefs.budget > 0) Fmt.rubU(snap.prefs.budget) else "не задан", onClick = { Router.show(Route.Goals(0)) })
            }
            Group("Умные функции") {
                when {
                    Claude.available -> SettingRow("ИИ работает", Icons.Rounded.AutoAwesome, iosPurple, detail = "через сервер Копилки")
                    !Server.loggedIn -> SettingRow("Войдите в аккаунт", Icons.Rounded.AutoAwesome, iosPurple, detail = "и ИИ заработает без ключа", onClick = { Router.show(Route.Account) })
                    else -> SettingRow("ИИ на сервере не настроен", Icons.Rounded.AutoAwesome, iosGray, detail = "голос работает упрощённо")
                }
            }
            Group("Данные") {
                SettingRow("Экспорт операций в CSV", Icons.Rounded.TableChart, iosGreen, onClick = { Csv.share(ctx, snap.txs, snap.accounts) })
                Divider1()
                SettingRow("Стереть все данные", Icons.Rounded.Delete, iosRed, onClick = { wipe = true })
            }
            Group("Приложение", "Обновления приходят с вашего сервера: как только на iPhone появляется новое, Android-версия собирается и предлагает обновиться.") {
                SettingRow("Версия ${Updater.currentName}", Icons.Rounded.Info, iosGray,
                    detail = Updater.available?.let { "доступна новая — нажмите, чтобы установить" } ?: "последняя",
                    onClick = { Updater.available?.let(Updater::install) ?: run { Updater.check(force = true); Router.say("Проверяю обновления…") } })
            }
            Text("Копилка для Android", fontSize = 12.sp, color = p.tertiary, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        }
    }
    if (wipe) Confirm("Стереть все операции, счета, долги и копилки${if (Server.loggedIn) " — на всех устройствах этого бюджета" else ""}?", "Стереть", {
        Store.wipeSpace(); Router.accFilter = null; Router.close(); Router.say("Данные стёрты")
    }) { wipe = false }
}

@Composable
private fun sw(p: Pal) = SwitchDefaults.colors(checkedTrackColor = p.accent, checkedThumbColor = p.onAccent)

private fun statusLine(st: SyncState): String = when (st) {
    SyncState.OFF -> "Данные только на этом устройстве"
    SyncState.SYNCING -> "Синхронизация…"
    SyncState.ERROR -> "Ошибка: ${SyncEngine.lastError.value ?: "нет связи"}"
    SyncState.IDLE -> {
        val last = Settings.dbl("lastSync")
        if (last <= 0) "Подключено" else {
            val m = ((System.currentTimeMillis() / 1000.0 - last) / 60).toInt()
            when { m < 1 -> "Синхронизировано только что"; m < 60 -> "Синхронизировано $m мин назад"; else -> "Синхронизировано " + DF.s(epochToDate(last), "d MMM") }
        }
    }
}

// MARK: Аккаунт и вход

@Composable
fun AccountScreen() {
    val p = LocalPal.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val st by SyncEngine.state.collectAsState()
    val login by SyncEngine.loginVersion.collectAsState()
    var providers by remember { mutableStateOf<List<Server.OAuthProvider>>(emptyList()) }
    var server by remember { mutableStateOf(Server.url) }
    var register by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    var logout by remember { mutableStateOf(false) }
    LaunchedEffect(login) { if (!Server.loggedIn) providers = Server.oauthProviders() }

    SheetScaffold("Аккаунт", Icons.Rounded.Person) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (Server.loggedIn) {
                Group(footer = "Данные останутся на телефоне. Синхронизация продолжится после повторного входа.") {
                    Column(Modifier.padding(16.dp)) {
                        Text(Settings.str("userName").ifEmpty { "Вы вошли" }, fontWeight = FontWeight.SemiBold, fontSize = 18.sp, color = p.text)
                        Text(Settings.str("userEmail"), color = p.secondary)
                        Text(statusLine(st), color = p.secondary, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
                    }
                    Divider1()
                    SettingRow("Синхронизировать сейчас", Icons.Rounded.Sync, iosBlue, onClick = { scope.launch { SyncEngine.sync(); Router.say(if (SyncEngine.state.value == SyncState.ERROR) "Нет связи" else "Синхронизировано") } })
                    Divider1()
                    SettingRow("Выйти из аккаунта", Icons.AutoMirrored.Rounded.Logout, iosRed, onClick = { logout = true })
                }
            } else {
                Group("Быстрый вход", "Войдите тем же аккаунтом, что на iPhone, — данные будут одни и те же. Или по почте и паролю:") {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        listOf("google", "yandex").filter { n -> providers.any { it.name == n } }.forEach { n ->
                            OAuthButton(n, Auth.busy == n) { providers.firstOrNull { it.name == n }?.let { Auth.open(ctx, it) } }
                        }
                        if (providers.isEmpty()) Text("Вход через Google и Яндекс появится, когда сервер ответит.", fontSize = 13.sp, color = p.secondary)
                        Auth.error?.let { Text(it, color = p.exp, fontSize = 13.sp) }
                    }
                }
                Group {
                    Segmented(listOf("Вход", "Новый аккаунт"), if (register) 1 else 0, { register = it == 1 })
                    if (register) { KTextField(name, { name = it }, "Имя"); Divider1() }
                    KTextField(email, { email = it.trim() }, "Почта", keyboard = KeyboardOptions(keyboardType = KeyboardType.Email))
                    Divider1()
                    KTextField(password, { password = it }, "Пароль (от 8 символов)", visual = PasswordVisualTransformation(), keyboard = KeyboardOptions(keyboardType = KeyboardType.Password))
                }
                err?.let { Text(it, color = p.exp, fontSize = 14.sp) }
                PrimaryButton(if (register) "Создать аккаунт" else "Войти", enabled = email.contains("@") && password.length >= (if (register) 8 else 1), busy = busy) {
                    busy = true; err = null
                    scope.launch {
                        runCatching { if (register) Server.register(name.trim(), email, password) else Server.login(email, password) }
                            .onSuccess { Haptic.success(); Router.say("Вы вошли — данные синхронизируются"); Router.close() }
                            .onFailure { Haptic.warning(); err = it.message }
                        busy = false
                    }
                }
                Text("Всё, что вы уже записали на этом телефоне, перенесётся в ваш личный бюджет на сервере.", fontSize = 13.sp, color = p.secondary)
                Group("Адрес сервера", "Уже указан сервер Копилки по умолчанию. Менять нужно, только если вам дали адрес другого сервера.") {
                    KTextField(server, { server = it.trim() }, Server.DEFAULT, keyboard = KeyboardOptions(keyboardType = KeyboardType.Uri))
                    if (Server.normalize(server) != Server.url) {
                        Divider1()
                        SettingRow("Сохранить адрес", Icons.Rounded.Dns, iosBlue, onClick = {
                            scope.launch {
                                if (Server.ping(server)) { Server.url = server; providers = Server.oauthProviders(); Router.say("Сервер сохранён") }
                                else err = "Сервер не отвечает — проверьте адрес"
                            }
                        })
                    }
                }
            }
        }
    }
    if (logout) Confirm("Выйти из аккаунта?", "Выйти", { Server.logout(); Router.say("Вы вышли") }) { logout = false }
}

@Composable
fun OAuthButton(provider: String, busy: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    val yandex = hexColor("FC3F1D")
    val bg = if (provider == "yandex") yandex else p.card
    val fg = if (provider == "yandex") Color.White else p.text
    Row(Modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(14.dp)).background(bg)
        .then(if (provider == "google") Modifier.border(1.dp, p.text.copy(alpha = 0.12f), RoundedCornerShape(14.dp)) else Modifier)
        .pressable(onClick, 0.97f, enabled = Auth.busy == null), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        if (busy) CircularProgressIndicator(Modifier.size(20.dp), color = fg, strokeWidth = 2.dp)
        else if (provider == "yandex") Box(Modifier.size(22.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
            Text("Я", color = yandex, fontWeight = FontWeight.Black, fontSize = 14.sp)
        } else GoogleG(Modifier.size(20.dp))
        Spacer(Modifier.width(10.dp))
        Text(if (provider == "yandex") "Войти с Яндекс ID" else "Войти через Google", color = fg, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
}

/** Цветная «G» Google из четырёх дуг. */
@Composable
fun GoogleG(modifier: Modifier) {
    Canvas(modifier) {
        val w = size.minDimension * 0.22f
        val d = size.minDimension - w
        val tl = Offset(w / 2, w / 2); val sz = Size(d, d)
        drawArc(hexColor("EA4335"), 200f, 120f, false, tl, sz, style = Stroke(w))
        drawArc(hexColor("FBBC05"), 145f, 60f, false, tl, sz, style = Stroke(w))
        drawArc(hexColor("34A853"), 45f, 100f, false, tl, sz, style = Stroke(w))
        drawArc(hexColor("4285F4"), -10f, 55f, false, tl, sz, style = Stroke(w))
        drawRect(hexColor("4285F4"), Offset(size.width / 2, size.height / 2 - w / 2), Size(size.width / 2 - w / 4, w))
    }
}

// MARK: Семья и бюджеты

@Composable
fun FamilyScreen() {
    val p = LocalPal.current
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val spaces by SyncEngine.spaces.collectAsState()
    val ver by SyncEngine.spaceVersion.collectAsState()
    ver.hashCode()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    var create by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("Семья") }
    var leave by remember { mutableStateOf<SpaceInfo?>(null) }
    fun run(block: suspend () -> Unit) { busy = true; err = null; scope.launch { runCatching { block() }.onFailure { err = it.message }; busy = false } }
    LaunchedEffect(Unit) { runCatching { Server.loadSpaces() } }

    SheetScaffold("Бюджеты", Icons.Rounded.Groups) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Group("Мои бюджеты", "Каждый бюджет — отдельные счета, траты, копилки и долги. Переключайтесь, когда нужно.") {
                spaces.forEachIndexed { i, s ->
                    if (i > 0) Divider1()
                    Row(Modifier.fillMaxWidth().pressable({ Haptic.select(); SyncEngine.switchTo(s.id); Router.accFilter = null; scope.launch { SyncEngine.sync() } }, 0.98f).padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Icon(if (s.personal) Icons.Rounded.Person else Icons.Rounded.Groups, null, tint = p.accent)
                        Column(Modifier.weight(1f)) {
                            Text(s.name, color = p.text)
                            Text(if (s.personal) "Видите только вы" else "${s.members.size} ${plural(s.members.size, "участник", "участника", "участников")}", fontSize = 13.sp, color = p.secondary)
                        }
                        if (s.id == Space.current) Icon(Icons.Rounded.Check, null, tint = p.accent)
                    }
                }
            }
            SyncEngine.currentSpace?.takeIf { !it.personal }?.let { s ->
                Group("«${s.name}» · код приглашения", "Отправьте код близким: в Копилке → Настройки → Аккаунт → Бюджет → «Вступить по коду». Все участники видят и меняют общие траты, копилки и долги, у каждой записи подписан автор.") {
                    Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(s.code, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 24.sp, letterSpacing = 3.sp, color = p.text, modifier = Modifier.weight(1f))
                        Row(Modifier.pressable({
                            val t = "Присоединяйся к нашему бюджету в Копилке: ${Server.url}/api/kp/invite?code=${s.code}\n\nИли вручную — сервер: ${Server.url.removePrefix("https://")}, код приглашения: ${s.code}"
                            ctx.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, t), "Пригласить"))
                        }), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.IosShare, null, tint = p.accent, modifier = Modifier.size(18.dp)); Text(" Отправить", color = p.accent, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    s.members.forEach { m ->
                        Divider1()
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(Icons.Rounded.AccountCircle, null, tint = p.secondary)
                            Column(Modifier.weight(1f)) {
                                Text(m.display + if (m.id == Server.userId) " (вы)" else "", color = p.text)
                                if (m.name.isNotEmpty()) Text(m.email, fontSize = 12.sp, color = p.secondary)
                            }
                            if (m.id == s.owner) Text("владелец", fontSize = 12.sp, color = p.secondary)
                            else if (s.owner == Server.userId) Text("Удалить", fontSize = 13.sp, color = p.exp, modifier = Modifier.pressable({ run { Server.updateSpace(s.id, kick = m.id) } }))
                        }
                    }
                    if (s.owner == Server.userId) { Divider1(); SettingRow("Сменить код приглашения", Icons.Rounded.Refresh, iosBlue, onClick = { run { Server.updateSpace(s.id, newCode = true) } }) }
                    Divider1(); SettingRow("Выйти из «${s.name}»", Icons.AutoMirrored.Rounded.Logout, iosRed, onClick = { leave = s })
                }
            }
            Group("Общий бюджет") {
                SettingRow("Создать семейный бюджет", Icons.Rounded.GroupAdd, iosGreen, onClick = { create = true })
                Divider1()
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { KTextField(code, { code = it.uppercase().filter { c -> c.isLetterOrDigit() }.take(12) }, "Код приглашения") }
                    Text("Вступить", color = if (code.length >= 4) p.accent else p.tertiary, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.pressable({ if (code.length >= 4) run { Server.join(code); code = "" } }).padding(16.dp))
                }
            }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth(), color = p.accent)
            err?.let { Text(it, color = p.exp) }
        }
    }
    if (create) AlertDialog({ create = false }, containerColor = p.card, title = { Text("Новый общий бюджет") },
        text = { Column { Text("Например «Семья» или «Мы вдвоём». Потом пригласите близких по коду.", color = p.secondary, fontSize = 14.sp)
            Box(Modifier.padding(top = 10.dp).clip(RoundedCornerShape(12.dp)).background(p.soft)) { KTextField(newName, { newName = it }, "Название") } } },
        confirmButton = { TextButton({ create = false; run { Server.createSpace(newName.trim().ifEmpty { "Семья" }); SyncEngine.spaces.value.lastOrNull { !it.personal }?.let { SyncEngine.switchTo(it.id); SyncEngine.sync() } } }) { Text("Создать") } },
        dismissButton = { TextButton({ create = false }) { Text("Отмена") } })
    leave?.let { s -> Confirm("Выйти из «${s.name}»? Общие записи останутся у остальных участников.", "Выйти", { run { Server.leave(s.id) } }) { leave = null } }
}

// MARK: Оформление

@Composable
fun AppearanceScreen() {
    val p = LocalPal.current
    var tab by remember { mutableIntStateOf(0) }
    fun set(block: () -> Unit) { Haptic.select(); block(); Look.save() }
    SheetScaffold("Оформление", Icons.Rounded.Palette) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                PillToggle(listOf(PillOption(0, "Темы", Icons.Rounded.Palette), PillOption(1, "Экран", Icons.Rounded.Dashboard)), tab) { tab = it }
            }
            PreviewCard()
            if (tab == 0) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Готовые темы", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Look.presets.forEach { pr -> PresetTile(pr, Look.isCurrent(pr)) { set { Look.apply(pr) } } }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Акцентный цвет", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                    Look.accents.chunked(6).forEach { row ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            row.forEach { a ->
                                val c = hexColor(if (p.dark) a.dark else a.light)
                                Box(Modifier.size(44.dp).clip(CircleShape).background(Brush.verticalGradient(listOf(c.copy(alpha = 0.85f), c))).pressable({ set { Look.accent = a.id } }, 0.88f),
                                    contentAlignment = Alignment.Center) { if (Look.accent == a.id) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
                            }
                        }
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Фон", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = p.text)
                    Look.backgrounds.chunked(3).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            row.forEach { (id, title) ->
                                Column(Modifier.weight(1f).pressable({ set { Look.background = id } }, 0.95f), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Box(Modifier.fillMaxWidth().height(70.dp).clip(RoundedCornerShape(14.dp))
                                        .border(if (Look.background == id) 2.5.dp else 1.dp, if (Look.background == id) p.accent else p.text.copy(alpha = 0.1f), RoundedCornerShape(14.dp))) {
                                        Backdrop(id)
                                    }
                                    Text(title, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = p.text)
                                }
                            }
                        }
                    }
                }
                Group("Карточки") { Segmented(listOf("Заливка", "Стекло", "Контур"), listOf("filled", "glass", "outline").indexOf(Look.cards).coerceAtLeast(0), { set { Look.cards = listOf("filled", "glass", "outline")[it] } }) }
                Group("Схема") { Segmented(listOf("Как в системе", "Светлая", "Тёмная"), listOf("system", "light", "dark").indexOf(Look.scheme).coerceAtLeast(0), { set { Look.scheme = listOf("system", "light", "dark")[it] } }) }
                Group("Шрифт") { Segmented(listOf("Обычный", "Округлый", "С засечками"), listOf("default", "rounded", "serif").indexOf(Look.font).coerceAtLeast(0), { set { Look.font = listOf("default", "rounded", "serif")[it] } }) }
            } else {
                Group("Большая цифра") { Segmented(listOf("Итог", "Потрачено", "Доход"), listOf("net", "exp", "inc").indexOf(Look.bigNumber).coerceAtLeast(0), { set { Look.bigNumber = listOf("net", "exp", "inc")[it] } }) }
                Group(footer = "Скрытые суммы показываются по касанию на большую цифру — удобно, когда рядом другие люди.") {
                    SwitchRow("Компактный список", Look.compact) { set { Look.compact = it } }
                    Divider1()
                    SwitchRow("Скрывать суммы", Look.hideAmounts) { set { Look.hideAmounts = it } }
                }
            }
        }
    }
}

@Composable
private fun PreviewCard() {
    val p = LocalPal.current
    Box(Modifier.fillMaxWidth().height(120.dp).clip(RoundedCornerShape(26.dp)).border(1.dp, p.stroke, RoundedCornerShape(26.dp))) {
        Backdrop()
        Row(Modifier.align(Alignment.Center).padding(horizontal = 18.dp)) {
            RowCard {
                CategoryTile(Catalog.cat("cafe"))
                Column(Modifier.weight(1f)) {
                    Text("Кафе", fontSize = 18.sp, fontWeight = FontWeight.Medium, color = p.text, fontFamily = p.fontFamily)
                    Text("Капучино · Сегодня", fontSize = 14.sp, color = p.secondary)
                }
                Text("−250 ₽", fontSize = 18.sp, fontWeight = FontWeight.Medium, color = p.text, fontFamily = p.fontFamily)
            }
        }
    }
}

@Composable
private fun PresetTile(pr: Look.Preset, selected: Boolean, onClick: () -> Unit) {
    val p = LocalPal.current
    val a = Look.accents.firstOrNull { it.id == pr.accent } ?: Look.accents[0]
    val dark = pr.scheme == "dark" || (pr.scheme == "system" && p.dark)
    val accent = hexColor(if (dark) a.dark else a.light)
    val bg = when (pr.background) { "pure" -> if (dark) Color.Black else Color.White; "midnight" -> hexColor(if (dark) "0A1030" else "E9ECF8"); "aurora" -> hexColor(if (dark) "06070D" else "F1F0F8"); else -> hexColor(if (dark) "090B12" else "EEF1F7") }
    Column(Modifier.width(104.dp).pressable(onClick, 0.95f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.size(104.dp, 72.dp).clip(RoundedCornerShape(16.dp)).background(bg)
            .background(Brush.radialGradient(listOf(accent.copy(alpha = 0.55f), Color.Transparent), center = Offset(30f, 20f), radius = 160f))
            .border(if (selected) 2.5.dp else 1.dp, if (selected) accent else p.text.copy(alpha = 0.1f), RoundedCornerShape(16.dp))) {
            Row(Modifier.align(Alignment.BottomStart).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(14.dp).clip(CircleShape).background(accent))
                Box(Modifier.size(34.dp, 10.dp).clip(RoundedCornerShape(4.dp)).background(Color.White.copy(alpha = if (dark) 0.2f else 0.9f)))
            }
        }
        Text(pr.name, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = p.text, maxLines = 1)
    }
}

// MARK: Первый запуск

@Composable
fun WelcomeScreen(onDone: () -> Unit) {
    val p = LocalPal.current
    val ctx = LocalContext.current
    var providers by remember { mutableStateOf<List<Server.OAuthProvider>?>(null) }
    var serverOK by remember { mutableStateOf<Boolean?>(null) }
    var email by remember { mutableStateOf(false) }
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        shown = true
        serverOK = Server.ping(Server.url)
        providers = if (serverOK == true) Server.oauthProviders() else emptyList()
    }
    val a by animateFloatAsState(if (shown) 1f else 0f, Motion.entrance(600), label = "w")
    Box(Modifier.fillMaxSize().background(p.bg).pressable({}, 1f)) {
        Backdrop("aurora")
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp)) {
                Icon(Icons.Rounded.Close, "Позже", tint = p.secondary, modifier = Modifier.size(40.dp).pressable({ Haptic.tap(); onDone() }).padding(8.dp))
            }
            Spacer(Modifier.weight(1f))
            Box(Modifier.size(104.dp).graphicsScale(0.9f + 0.1f * a).clip(RoundedCornerShape(26.dp))
                .background(Brush.linearGradient(listOf(hexColor("3A4BD8"), hexColor("101634")))), contentAlignment = Alignment.Center) {
                Box(Modifier.size(56.dp).clip(CircleShape).background(Color.White), contentAlignment = Alignment.Center) {
                    Text("₽", fontSize = 34.sp, fontWeight = FontWeight.Black, color = hexColor("2B3BB8"))
                }
            }
            Text("Копилка", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = p.text, modifier = Modifier.padding(top = 22.dp))
            Text("Скажите, что потратили, — остальное посчитаю сам.\nДанные одни на всех ваших устройствах.", color = p.secondary, fontSize = 16.sp,
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp, start = 30.dp, end = 30.dp))
            Spacer(Modifier.weight(1f))
            Column(Modifier.widthIn(max = 440.dp).padding(horizontal = 24.dp).padding(bottom = 20.dp).graphicsAlpha2(a), verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                listOf("google", "yandex").filter { n -> providers?.any { it.name == n } == true }.forEach { n ->
                    OAuthButton(n, Auth.busy == n) { providers?.firstOrNull { it.name == n }?.let { Auth.open(ctx, it) } }
                }
                if (providers == null) CircularProgressIndicator(Modifier.size(24.dp), color = p.accent, strokeWidth = 2.dp)
                Row(Modifier.fillMaxWidth().height(50.dp).clip(RoundedCornerShape(14.dp)).background(p.accent).pressable({ email = true }, 0.97f),
                    horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Email, null, tint = p.onAccent, modifier = Modifier.size(20.dp)); Spacer(Modifier.width(8.dp))
                    Text("Войти с помощью почты", color = p.onAccent, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
                }
                Auth.error?.let { Text(it, color = p.exp, fontSize = 13.sp, textAlign = TextAlign.Center) }
                    ?: if (serverOK == false) Text("Сервер не отвечает. Проверьте интернет — или нажмите ✕, записи сохранятся на телефоне.", color = p.secondary, fontSize = 13.sp, textAlign = TextAlign.Center) else Unit
            }
        }
        Overlay(if (email) true else null, { email = false }) {
            Box(Modifier.fillMaxSize()) { AccountScreenEmbedded { email = false } }
        }
    }
}

/** Экран входа по почте поверх приветствия (закрывается крестиком, а не уводит из приветствия). */
@Composable
private fun AccountScreenEmbedded(onClose: () -> Unit) {
    Box(Modifier.fillMaxSize()) {
        AccountScreen()
        Box(Modifier.statusBarsPadding().padding(16.dp, 8.dp).size(46.dp).pressable(onClose, 0.92f))
    }
}

private fun Modifier.graphicsScale(s: Float) = this.scale(s)
private fun Modifier.graphicsAlpha2(a: Float) = this.alpha(a)
