package ru.koshelek.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Pets
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import ru.koshelek.app.core.*
import ru.koshelek.app.data.Snapshot
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

// MARK: Движение (та же математика, что на iPhone)

data class PetPose(val rot: Float = 0f, val dy: Float = 0f, val sx: Float = 1f, val sy: Float = 1f)

object PetMotion {
    fun pose(m: CompanionMotionSpec, mood: CompanionMood, t: Double): PetPose {
        val tau = 2 * PI
        var amp = when (mood) { CompanionMood.HAPPY -> 1.0; CompanionMood.CALM -> 0.55; CompanionMood.SAD -> 0.12; CompanionMood.SLEEPY -> 0.0 }
        if (m.period > 0 && mood != CompanionMood.SLEEPY) {
            val ph = (t % m.period) / m.period
            amp *= if (ph < m.duty) sin(PI * ph / m.duty) else 0.0
        }
        val rot = m.rot * amp * sin(tau * m.rotHz * t)
        var dy = -m.bob * amp * abs(sin(tau * m.bobHz * t))
        val sq = m.squash * amp * sin(tau * m.squashHz * t)
        var sx = 1 - sq
        var sy = 1 + sq
        var r = rot
        when (mood) {
            CompanionMood.HAPPY -> dy -= 0.03 * abs(sin(tau * 1.1 * t))
            CompanionMood.SAD -> { sy *= 0.97; dy += 0.01 }
            CompanionMood.SLEEPY -> { val br = 0.015 * sin(tau * 0.25 * t); sx = 1 - br; sy = 1 + br; r = 3.0 }
            CompanionMood.CALM -> {}
        }
        return PetPose(r.toFloat(), dy.toFloat(), sx.toFloat(), sy.toFloat())
    }
}

// MARK: Питомец

private fun DrawScope.sparkle(c: Offset, r: Float, color: Color) {
    val path = Path()
    for (i in 0 until 8) {
        val rad = if (i % 2 == 0) r else r * 0.38f
        val a = i * PI / 4 - PI / 2
        val x = c.x + rad * cos(a).toFloat(); val y = c.y + rad * sin(a).toFloat()
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    path.close()
    drawPath(path, color)
}

@Composable
fun PetView(pet: CompanionDef, mood: CompanionMood, modifier: Modifier = Modifier, animated: Boolean = true) {
    val live = animated && Look.moves
    var t by remember { mutableDoubleStateOf(0.3) }
    if (live) LaunchedEffect(Unit) {
        val t0 = System.nanoTime()
        while (true) withFrameNanos { t = (System.nanoTime() - t0) / 1e9 + 0.3 }
    }
    val tm = rememberTextMeasurer()
    Box(modifier) {
        Image(painterResource(pet.art), "${pet.name}, ${mood.title.lowercase()}", Modifier.fillMaxSize().graphicsLayer {
            val ps = if (live) PetMotion.pose(pet.motion, mood, t) else PetPose()
            transformOrigin = TransformOrigin(0.5f, 1f)
            scaleX = ps.sx; scaleY = ps.sy; rotationZ = ps.rot
            translationY = size.height * ps.dy
        }, contentScale = ContentScale.Fit)
        Canvas(Modifier.fillMaxSize()) {
            val s = size.minDimension
            val tt = if (live) t else 0.3
            val tau = 2 * PI
            if (mood == CompanionMood.HAPPY) {
                for (k in 0..1) {
                    val a = (0.5 + 0.5 * sin(tau * 0.8 * tt + k * 2.1)).toFloat()
                    val c = Offset(s * (if (k == 0) 0.84f else 0.14f), s * (if (k == 0) 0.18f else 0.3f))
                    sparkle(c, s * (0.12f + 0.05f * a) * 0.55f, Color(1f, 0.78f, 0.2f, 0.4f + 0.6f * a))
                }
            }
            if (mood == CompanionMood.SAD) {
                val f = ((tt * 0.5) % 1.0).toFloat()
                drawRoundRect(Color(0.35f, 0.62f, 0.95f, 1f - f), Offset(s * 0.72f - s * 0.025f, s * (0.25f + 0.2f * f) - s * 0.04f),
                    Size(s * 0.05f, s * 0.08f), CornerRadius(s * 0.025f))
            }
            if (mood == CompanionMood.SLEEPY) {
                for (k in 0..2) {
                    val f = ((tt * 0.4 + k / 3.0) % 1.0).toFloat()
                    val fs = s * (0.1f + 0.08f * f)
                    drawText(tm, "z", Offset(s * (0.72f + 0.1f * f) - fs * 0.3f, s * (0.3f - 0.25f * f) - fs * 0.6f),
                        TextStyle(fontSize = fs.toSp(), fontWeight = FontWeight.Bold, color = Color.Gray.copy(alpha = 1f - f)))
                }
            }
            if (pet.motion.juggle && mood != CompanionMood.SLEEPY) {
                for (k in 0..2) {
                    val a = tau * (tt * 0.9 + k / 3.0)
                    val c = Offset(s * (0.5f + 0.28f * cos(a).toFloat()), s * (0.1f + 0.08f * sin(a).toFloat()))
                    drawCircle(Color(1f, 0.8f, 0.2f), s * 0.04f, c)
                    drawCircle(Color(0.8f, 0.55f, 0.1f), s * 0.04f, c, style = Stroke(1.dp.toPx()))
                }
            }
        }
    }
}

// MARK: Карточка на главной

@Composable
fun CompanionCard(snap: Snapshot) {
    val p = LocalPal.current
    val pet = CompanionCatalog.def(CompanionEngine.petId)
    val fed = CompanionEngine.fedCount
    val fedDay = CompanionEngine.fedDay
    val st = remember(snap, pet.id, fed, fedDay, Look.debtInTotals) {
        CompanionEngine.compute(snap.txs, snap.prefs.budget, pet, fed = fed, fedDay = fedDay)
    }
    var said by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(said) { if (said != null) { delay(4000); said = null } }
    var lastLevel by remember { mutableIntStateOf(st.level) }
    LaunchedEffect(st.level) {
        if (st.level > lastLevel) { CompanionSound.xp(); Haptic.press() }
        lastLevel = st.level
    }
    val accent = hexColor(pet.accentHex)
    Column(Modifier.fillMaxWidth().padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle("Напарник", "Сменить") { Router.show(Route.Companion) }
        Column(Modifier.fillMaxWidth().cardBg().padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                PetView(pet, st.mood, Modifier.size(104.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("${pet.name} · ${st.mood.title}", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = p.text)
                    Text(said ?: st.phrase, fontSize = 15.sp, color = p.secondary)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth()) {
                    Text("Уровень ${st.level}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.text, modifier = Modifier.weight(1f))
                    Text("${st.xpInLevel}/${st.xpNeed} XP", fontSize = 13.sp, color = p.secondary)
                }
                Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50)).background(p.soft)) {
                    Box(Modifier.fillMaxWidth(st.progress.coerceIn(0f, 1f)).fillMaxHeight().clip(RoundedCornerShape(50)).background(accent))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                val canFeed = st.treats > 0
                Text("Угостить (${st.treats})", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center,
                    color = if (canFeed) p.onAccent else p.secondary,
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(if (canFeed) p.accent else p.soft)
                        .pressable({
                            if (CompanionEngine.feed(st)) { Haptic.press(); CompanionSound.xp(); said = pet.feedLine }
                        }, 0.97f, enabled = canFeed).padding(vertical = 10.dp))
                Text("Поговорить", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, color = p.text,
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(p.soft)
                        .pressable({ Haptic.tap(); Router.show(Route.PetChat(pet.id, st.mood.raw)) }, 0.97f).padding(vertical = 10.dp))
            }
        }
    }
}

// MARK: Выбор напарника

@Composable
fun CompanionScreen() {
    val p = LocalPal.current
    val cur = CompanionCatalog.def(CompanionEngine.petId)
    SheetScaffold("Напарник", Icons.Rounded.Pets) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(horizontal = 12.dp)) {
                PetView(cur, CompanionMood.HAPPY, Modifier.size(150.dp))
                Text(cur.name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
                Text(cur.role, fontSize = 15.sp, color = p.secondary)
                Text(cur.blurb, fontSize = 13.sp, color = p.secondary, textAlign = TextAlign.Center)
                Text("Звук: ${cur.sound}", fontSize = 13.sp, color = p.tertiary, textAlign = TextAlign.Center)
                Row(Modifier.pressable({ CompanionSound.play(cur.soundTx) }, 0.96f).padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Rounded.MusicNote, null, tint = p.accent, modifier = Modifier.size(18.dp))
                    Text("Послушать", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = p.accent)
                }
            }
            CompanionCatalog.all.chunked(3).forEach { row ->
                Row(Modifier.fillMaxWidth().widthIn(max = 560.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    row.forEach { pet ->
                        val on = pet.id == cur.id
                        Column(Modifier.weight(1f).clip(RoundedCornerShape(16.dp)).background(p.soft)
                            .border(2.dp, if (on) p.accent else Color.Transparent, RoundedCornerShape(16.dp))
                            .pressable({ Haptic.select(); CompanionEngine.petId = pet.id }, 0.97f).padding(8.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            PetView(pet, CompanionMood.CALM, Modifier.size(72.dp), animated = false)
                            Text(pet.name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = p.text, maxLines = 1)
                        }
                    }
                    repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
fun PetChatScreen(petId: String, mood: String) {
    AdvisorChat({ Router.close() }, CompanionCatalog.def(petId), CompanionMood.entries.firstOrNull { it.raw == mood } ?: CompanionMood.CALM)
}
