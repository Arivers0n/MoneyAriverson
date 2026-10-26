package ru.koshelek.app.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import ru.koshelek.app.core.hexColor
import ru.koshelek.app.data.*
import kotlin.math.sin

/** Распознавание речи: живой текст по мере речи и громкость для «дыхания» кнопки. */
class Speech(private val ctx: Context) {
    var transcript by mutableStateOf("")
    var level by mutableFloatStateOf(0f)
    var recording by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    var onFinal: (() -> Unit)? = null
    private var rec: SpeechRecognizer? = null
    private var prefix = ""

    fun start() {
        error = null
        if (!SpeechRecognizer.isRecognitionAvailable(ctx)) { error = "На телефоне нет распознавания речи — установите приложение Google"; return }
        rec?.destroy()
        prefix = transcript.trim().let { if (it.isEmpty()) "" else "$it " }
        val r = SpeechRecognizer.createSpeechRecognizer(ctx)
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { recording = true }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) { level = level * 0.6f + ((rmsdB + 2f) / 12f).coerceIn(0f, 1f) * 0.4f }
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { level = 0f }
            override fun onError(code: Int) {
                recording = false; level = 0f
                when (code) {
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> if (transcript.isNotBlank()) onFinal?.invoke()
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> error = "Нет доступа к микрофону"
                    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> error = "Нет интернета для распознавания"
                    SpeechRecognizer.ERROR_CLIENT -> {}
                    else -> error = "Не расслышал. Попробуйте ещё раз"
                }
            }
            override fun onResults(results: Bundle?) {
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.let { transcript = prefix + it }
                recording = false; level = 0f
                onFinal?.invoke()
            }
            override fun onPartialResults(partial: Bundle?) {
                partial?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.takeIf { it.isNotBlank() }?.let { transcript = prefix + it }
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val i = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1600L)
            .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1600L)
        rec = r
        recording = true
        r.startListening(i)
    }
    fun stop() { rec?.stopListening() }
    fun cancel() { onFinal = null; rec?.cancel(); recording = false; level = 0f }
    fun destroy() { cancel(); rec?.destroy(); rec = null }
}

private enum class Phase { LISTENING, IDLE, THINKING }

private val hints = listOf("«Кофе 250, такси 400»", "«Вчера в Пятёрочке на 1 800 с карты»", "«Пришла зарплата 85 тысяч»",
    "«Закинул по кредиту восемь пятьсот»", "«Отложил пятёрку на отпуск»")

/** Голосовой ввод в стиле iPhone: размытый фон, тёмный пузырь с живым текстом и дышащая кнопка. */
@Composable
fun VoiceOverlay() {
    val ctx = LocalContext.current
    val speech = remember { Speech(ctx) }
    var phase by remember { mutableStateOf(Phase.LISTENING) }
    var err by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    var hint by remember { mutableIntStateOf(0) }
    var shown by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }

    fun close() { speech.destroy(); Router.voiceOn = false }

    fun parse() {
        val text = speech.transcript.trim()
        if (text.isEmpty()) { phase = Phase.IDLE; return }
        if (phase == Phase.THINKING) return
        editing = false; phase = Phase.THINKING; err = null
        speech.cancel()
        scope.launch {
            val snap = Store.snapshot.value
            val items = try { Brain.parseSpeech(text, snap) } catch (e: Exception) {
                LocalParser.parse(text).ifEmpty { Haptic.warning(); err = e.message; phase = Phase.IDLE; return@launch }
            }
            if (items.isEmpty()) { Haptic.warning(); err = "Не услышал сумм. Скажите, например: «кофе двести пятьдесят»."; phase = Phase.IDLE; return@launch }
            Haptic.success()
            shown = false
            delay(200)
            close()
            Router.show(Route.Review(items, "«$text»"))
        }
    }

    fun listen() { phase = Phase.LISTENING; speech.onFinal = { parse() }; speech.start() }

    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) listen() else { phase = Phase.IDLE; err = "Разрешите доступ к микрофону в настройках телефона" }
    }

    LaunchedEffect(Unit) {
        shown = true
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) listen()
        else perm.launch(Manifest.permission.RECORD_AUDIO)
    }
    LaunchedEffect(speech.recording) { if (!speech.recording && phase == Phase.LISTENING) { delay(300); if (!speech.recording && phase == Phase.LISTENING) phase = Phase.IDLE } }
    val release = VoiceBus.release
    LaunchedEffect(release) { if (release > 0 && speech.recording) speech.stop() }
    LaunchedEffect(speech.transcript.isEmpty()) { while (speech.transcript.isEmpty()) { delay(2800); hint = (hint + 1) % hints.size } }
    DisposableEffect(Unit) { onDispose { speech.destroy() } }

    val slide by animateFloatAsState(if (shown || !Look.moves) 0f else 60f, Motion.entrance(420), label = "slide")
    val alpha by animateFloatAsState(if (shown) 1f else 0f, tween(if (Look.animated) 260 else 0), label = "a")

    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f * alpha)).pressable({ if (phase != Phase.THINKING) close() }, 1f))
        Column(Modifier.align(Alignment.BottomCenter).widthIn(max = 560.dp).fillMaxWidth().navigationBarsPadding().imePadding()
            .padding(start = 18.dp, end = 18.dp, bottom = 26.dp).offset(y = slide.dp).graphicsAlpha(alpha),
            verticalArrangement = Arrangement.spacedBy(26.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            // Пузырь
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(Color.Black.copy(alpha = 0.86f))
                .border(0.5.dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape(28.dp)).padding(horizontal = 22.dp, vertical = 18.dp)
                .animateContentSize(Motion.spring()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LiveDots(phase == Phase.LISTENING, speech.level)
                    val status = when (phase) {
                        Phase.LISTENING -> if (speech.transcript.isEmpty()) "Я вас слушаю…" else "Говорите — я записываю"
                        Phase.IDLE -> if (speech.transcript.isEmpty()) "Нажмите и говорите" else "Нажмите на текст, чтобы поправить"
                        Phase.THINKING -> "Разбираю…"
                    }
                    AnimatedContent(status, transitionSpec = { fadeIn(tween(160)) togetherWith fadeOut(tween(120)) }, label = "st") {
                        Text(it, color = Color.White.copy(alpha = 0.6f), fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                val big = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Medium, fontStyle = FontStyle.Italic, color = Color.White)
                when {
                    editing -> {
                        BasicTextField(speech.transcript, { speech.transcript = it }, textStyle = big, cursorBrush = SolidColor(Color.White),
                            modifier = Modifier.fillMaxWidth().focusRequester(focus))
                        LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
                    }
                    speech.transcript.isEmpty() -> AnimatedContent(hint, transitionSpec = { fadeIn(tween(300)) togetherWith fadeOut(tween(200)) }, label = "hint") {
                        Text(hints[it], style = big.copy(color = Color.White.copy(alpha = 0.35f)))
                    }
                    else -> Text("“${speech.transcript}”", style = big.copy(color = Color.White.copy(alpha = if (phase == Phase.THINKING) 0.5f else 1f)),
                        modifier = Modifier.pressable({ if (phase != Phase.THINKING) { speech.cancel(); phase = Phase.IDLE; editing = true } }, 1f))
                }
                (err ?: speech.error)?.let { Text(it, color = hexColor("FF8A75"), fontSize = 13.sp) }
            }
            // Кнопки
            Row(horizontalArrangement = Arrangement.spacedBy(22.dp), verticalAlignment = Alignment.CenterVertically) {
                DarkCircle(Icons.Rounded.Keyboard, phase != Phase.THINKING) { close(); Router.show(Route.NewTx) }
                MicButton(phase, speech.level) {
                    editing = false; Haptic.press()
                    when (phase) {
                        Phase.LISTENING -> { speech.stop(); if (speech.transcript.isNotBlank()) parse() }
                        Phase.IDLE -> if (speech.transcript.isBlank()) listen() else parse()
                        Phase.THINKING -> {}
                    }
                }
                DarkCircle(Icons.Rounded.Close, phase != Phase.THINKING) { close() }
            }
        }
    }
}

private fun Modifier.graphicsAlpha(a: Float) = this.alpha(a)

@Composable
private fun MicButton(phase: Phase, level: Float, onClick: () -> Unit) {
    val p = LocalPal.current
    val lv by animateFloatAsState(if (Look.animated) level else 0f, tween(80), label = "lv")
    Box(Modifier.size(120.dp).pressable(onClick, 0.92f, enabled = phase != Phase.THINKING), contentAlignment = Alignment.Center) {
        if (phase == Phase.LISTENING) {
            Box(Modifier.size(96.dp).scale(1 + lv * 0.55f).clip(CircleShape).background(Color.White.copy(alpha = 0.10f)))
            Box(Modifier.size(96.dp).scale(1 + lv * 0.28f).clip(CircleShape).background(Color.White.copy(alpha = 0.14f)))
        }
        val bg by animateColorAsState(if (phase == Phase.LISTENING) Color.White else p.accent, label = "bg")
        Box(Modifier.size(84.dp).scale(if (phase == Phase.LISTENING) 1 + lv * 0.06f else 1f).clip(CircleShape).background(bg), contentAlignment = Alignment.Center) {
            AnimatedContent(phase, transitionSpec = { (scaleIn(initialScale = 0.6f) + fadeIn()) togetherWith (scaleOut(targetScale = 0.6f) + fadeOut()) }, label = "ph") { ph ->
                when (ph) {
                    Phase.LISTENING -> Box(Modifier.size(28.dp).clip(RoundedCornerShape(7.dp)).background(Color.Black))
                    Phase.IDLE -> Icon(Icons.Rounded.ArrowUpward, "Готово", tint = p.onAccent, modifier = Modifier.size(32.dp))
                    Phase.THINKING -> CircularProgressIndicator(color = p.onAccent, strokeWidth = 3.dp, modifier = Modifier.size(32.dp))
                }
            }
        }
    }
}

@Composable
private fun LiveDots(active: Boolean, level: Float) {
    val t by rememberInfiniteTransition(label = "dots").animateFloat(0f, 100f, infiniteRepeatable(tween(100_000, easing = LinearEasing)), label = "t")
    Row(Modifier.height(18.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(3) { i ->
            val h = if (active && Look.animated) 6f + ((sin(t * 9 + i * 1.3) * 0.5 + 0.5) * 12 * maxOf(0.25f, level)).toFloat() else 6f
            Box(Modifier.width(4.dp).height(h.dp).clip(RoundedCornerShape(50)).background(if (active) hexColor("FF5A4E") else Color.White.copy(alpha = 0.35f)))
        }
    }
}

@Composable
private fun DarkCircle(icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.size(54.dp).androidx_alpha(if (enabled) 1f else 0.4f).clip(CircleShape).background(Color.Black.copy(alpha = 0.86f))
        .border(0.5.dp, Color.White.copy(alpha = 0.08f), CircleShape).pressable(onClick, 0.9f, enabled = enabled), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

private fun Modifier.androidx_alpha(a: Float) = this.alpha(a)
