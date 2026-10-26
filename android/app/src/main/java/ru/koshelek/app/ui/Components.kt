package ru.koshelek.app.ui

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ru.koshelek.app.core.*
import java.time.YearMonth

// MARK: Фон

@Composable
fun Backdrop(style: String = Look.background, modifier: Modifier = Modifier) {
    val p = LocalPal.current
    Box(modifier.fillMaxSize().background(p.bg)) {
        when (style) {
            "tint" -> Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to p.accent.copy(alpha = 0.28f), 0.5f to Color.Transparent)))
            "depth" -> Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(p.accent.copy(alpha = if (p.dark) 0.42f else 0.28f), Color.Transparent), center = Offset(0f, 0f), radius = 1400f)))
            "aurora" -> {
                Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(p.accent.copy(alpha = if (p.dark) 0.55f else 0.32f), Color.Transparent), center = Offset(120f, 80f), radius = 1100f)))
                Box(Modifier.fillMaxSize().background(Brush.radialGradient(listOf(hexColor("2ECFC4").copy(alpha = if (p.dark) 0.4f else 0.26f), Color.Transparent), center = Offset(1100f, 500f), radius = 900f)))
            }
            "midnight" -> Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to hexColor(if (p.dark) "1B2470" else "C9D1F5").copy(alpha = 0.7f), 0.5f to Color.Transparent)))
        }
    }
}

// MARK: Карточки

@Composable
fun Modifier.cardBg(shape: Shape = RoundedCornerShape(22.dp)): Modifier {
    val p = LocalPal.current
    return when (Look.cards) {
        "glass" -> this.clip(shape).background(p.card.copy(alpha = if (p.dark) 0.55f else 0.7f)).border(0.5.dp, p.stroke, shape)
        "outline" -> this.clip(shape).background(p.text.copy(alpha = 0.025f)).border(1.dp, p.text.copy(alpha = 0.13f), shape)
        else -> this.clip(shape).background(p.card)
    }
}

@Composable
fun Modifier.glass(shape: Shape = CircleShape): Modifier {
    val p = LocalPal.current
    return this.clip(shape).background(if (p.dark) Color(0xFF2A2A2E).copy(alpha = 0.78f) else Color.White.copy(alpha = 0.82f)).border(0.5.dp, p.stroke, shape)
}

/** Нажатие: вниз — быстро, обратно — пружиной. */
@Composable
fun Modifier.pressable(onClick: () -> Unit, scaleTo: Float = 0.96f, haptic: Boolean = false, enabled: Boolean = true, onLongClick: (() -> Unit)? = null): Modifier {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed && Look.animated) scaleTo else 1f,
        if (pressed) tween(100, easing = FastOutSlowInEasing) else spring(0.55f, 500f), label = "press")
    return this.scale(s).combinedClickable(interactionSource = src, indication = null, enabled = enabled,
        onLongClick = onLongClick?.let { lc -> { Haptic.heavy(); lc() } }) { if (haptic) Haptic.tap(); onClick() }
}

@Composable
fun GlassCircle(icon: ImageVector, size: Dp = 46.dp, tint: Color = LocalPal.current.text, desc: String? = null, onClick: () -> Unit) {
    Box(Modifier.size(size).glass().pressable(onClick, 0.92f), contentAlignment = Alignment.Center) {
        Icon(icon, desc, tint = tint, modifier = Modifier.size(size * 0.46f))
    }
}

data class IconItem(val icon: ImageVector, val dot: Boolean = false, val action: () -> Unit)

@Composable
fun GlassIconGroup(items: List<IconItem>) {
    Row(Modifier.glass(RoundedCornerShape(50)).padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        items.forEach { it2 ->
            Box(Modifier.size(width = 40.dp, height = 46.dp).pressable(it2.action, 0.88f), contentAlignment = Alignment.Center) {
                Icon(it2.icon, null, tint = LocalPal.current.text, modifier = Modifier.size(22.dp))
                if (it2.dot) Box(Modifier.align(Alignment.TopEnd).padding(top = 10.dp, end = 8.dp).size(8.dp).clip(CircleShape).background(LocalPal.current.exp))
            }
        }
    }
}

@Composable
fun CategoryTile(cat: Category, size: Dp = if (Look.compact) 40.dp else 50.dp) = Tile(cat.icon, cat.color, size)

@Composable
fun Tile(icon: ImageVector, color: Color, size: Dp = 50.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(size * 0.3f)).background(color.copy(alpha = 0.2f)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color, modifier = Modifier.size(size * 0.48f))
    }
}

@Composable
fun MonthPill(month: YearMonth, onChange: (YearMonth) -> Unit) {
    val p = LocalPal.current
    var forward by remember { mutableStateOf(true) }
    Row(Modifier.cardBg(RoundedCornerShape(50)).padding(horizontal = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(34.dp, 38.dp).pressable({ forward = false; Haptic.select(); onChange(month.minusMonths(1)) }, 0.85f), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.ChevronLeft, null, tint = p.text)
        }
        AnimatedContent(month, transitionSpec = {
            val d = if (forward) 1 else -1
            (slideInHorizontally(Motion.snappy()) { it * d / 2 } + fadeIn()) togetherWith (slideOutHorizontally(Motion.snappy()) { -it * d / 2 } + fadeOut())
        }, label = "month") { m ->
            Text(DF.monthTitle(m), fontWeight = FontWeight.Medium, fontSize = 16.sp, color = p.text, modifier = Modifier.widthIn(min = 96.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
        Box(Modifier.size(34.dp, 38.dp).pressable({ forward = true; Haptic.select(); onChange(month.plusMonths(1)) }, 0.85f), contentAlignment = Alignment.Center) {
            Icon(Icons.Rounded.ChevronRight, null, tint = p.text)
        }
    }
}

data class PillOption(val id: Int, val title: String, val icon: ImageVector, val color: Color? = null)

@Composable
fun PillToggle(options: List<PillOption>, selection: Int, onSelect: (Int) -> Unit) {
    val p = LocalPal.current
    Row(Modifier.cardBg(RoundedCornerShape(50)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        options.forEach { o ->
            val on = o.id == selection
            val c = o.color ?: p.text
            val bg by animateColorAsState(if (on) c.copy(alpha = if (o.color == null) 0.12f else 0.18f) else Color.Transparent, label = "pill")
            Row(Modifier.clip(RoundedCornerShape(50)).background(bg).pressable({ Haptic.select(); onSelect(o.id) }, 0.95f)
                .padding(horizontal = if (on) 14.dp else 12.dp).height(38.dp).animateContentSize(Motion.spring()),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(o.icon, null, tint = if (on) c else p.secondary, modifier = Modifier.size(18.dp))
                if (on) Text(o.title, fontWeight = FontWeight.SemiBold, color = c)
            }
        }
    }
}

@Composable
fun RowCard(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().cardBg().padding(horizontal = 14.dp, vertical = if (Look.compact) 8.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp), content = content)
}

@Composable
fun SectionTitle(text: String, action: String? = null, onAction: () -> Unit = {}) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, color = p.secondary, modifier = Modifier.weight(1f))
        if (action != null) Text(action, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = p.accent, modifier = Modifier.pressable(onAction))
    }
}

@Composable
fun EmptyState(icon: ImageVector, title: String, text: String) {
    val p = LocalPal.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 50.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(icon, null, tint = p.secondary, modifier = Modifier.size(56.dp))
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = p.text)
        Text(text, fontSize = 15.sp, color = p.secondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }
}

@Composable
fun ProgressBar(value: Double, color: Color, height: Dp = 10.dp) {
    val p = LocalPal.current
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val v by animateFloatAsState(if (shown) value.coerceIn(0.0, 1.0).toFloat() else 0f, Motion.entrance(800), label = "bar")
    Box(Modifier.fillMaxWidth().height(height).clip(RoundedCornerShape(50)).background(p.soft)) {
        Box(Modifier.fillMaxWidth(v).fillMaxHeight().clip(RoundedCornerShape(50)).background(Brush.horizontalGradient(listOf(color.copy(alpha = 0.75f), color))))
    }
}

/** Сумма, которая плавно «докручивается» до нового значения. */
@Composable
fun RollingAmount(value: Double, style: TextStyle, color: Color, masked: Boolean = false, countUp: Boolean = false) {
    var target by remember { mutableDoubleStateOf(if (countUp && Look.moves) 0.0 else value) }
    LaunchedEffect(value) { target = value }
    val v by animateFloatAsState(target.toFloat(), if (Look.animated) tween(700, easing = CubicBezierEasing(0.23f, 1f, 0.32f, 1f)) else snap(), label = "amt")
    Text(if (masked) "••••• ₽" else Fmt.rub(if (kotlin.math.abs(v - value.toFloat()) < 0.5f) value else v.toDouble()),
        style = style, color = color, maxLines = 1, overflow = TextOverflow.Visible)
}

@Composable
fun Divider1() = HorizontalDivider(color = LocalPal.current.stroke, thickness = 0.5.dp)

/** Шапка полноэкранных окон: ✕ слева, заголовок-капсула по центру, действия справа. */
@Composable
fun SheetBar(title: String, icon: ImageVector? = null, onClose: () -> Unit, trailing: @Composable () -> Unit = {}) {
    val p = LocalPal.current
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
        Row(Modifier.align(Alignment.Center).glass(RoundedCornerShape(50)).padding(horizontal = 16.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            if (icon != null) Icon(icon, null, tint = p.text, modifier = Modifier.size(18.dp))
            Text(title, fontWeight = FontWeight.SemiBold, color = p.text)
        }
        Row(Modifier.fillMaxWidth().align(Alignment.Center), verticalAlignment = Alignment.CenterVertically) {
            GlassCircle(Icons.Rounded.Close, onClick = onClose)
            Spacer(Modifier.weight(1f))
            trailing()
        }
    }
}

@Composable
fun SettingRow(title: String, icon: ImageVector, color: Color, detail: String? = null, onClick: (() -> Unit)? = null, trailing: @Composable () -> Unit = {}) {
    val p = LocalPal.current
    Row(Modifier.fillMaxWidth().then(if (onClick != null) Modifier.pressable(onClick, 0.98f) else Modifier).padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(Brush.verticalGradient(listOf(color.copy(alpha = 0.85f), color))), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, color = p.text, fontSize = 16.sp)
            if (detail != null) Text(detail, color = p.secondary, fontSize = 12.sp)
        }
        trailing()
        if (onClick != null) Icon(Icons.Rounded.ChevronRight, null, tint = p.tertiary)
    }
}

@Composable
fun Group(title: String? = null, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    val p = LocalPal.current
    Column(Modifier.fillMaxWidth()) {
        if (title != null) Text(title, color = p.secondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
        Column(Modifier.fillMaxWidth().cardBg(RoundedCornerShape(20.dp)), content = content)
        if (footer != null) Text(footer, color = p.secondary, fontSize = 12.sp, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
    }
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false, onClick: () -> Unit) {
    val p = LocalPal.current
    Box(modifier.fillMaxWidth().height(52.dp).clip(RoundedCornerShape(16.dp)).background(if (enabled) p.accent else p.soft)
        .pressable(onClick, 0.97f, enabled = enabled && !busy), contentAlignment = Alignment.Center) {
        if (busy) CircularProgressIndicator(color = p.onAccent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
        else Text(text, color = if (enabled) p.onAccent else p.secondary, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
}

@Composable
fun KTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier, singleLine: Boolean = true,
               keyboard: androidx.compose.foundation.text.KeyboardOptions = androidx.compose.foundation.text.KeyboardOptions.Default,
               visual: androidx.compose.ui.text.input.VisualTransformation = androidx.compose.ui.text.input.VisualTransformation.None, textStyle: TextStyle? = null) {
    val p = LocalPal.current
    val st = textStyle ?: TextStyle(fontSize = 17.sp, color = p.text)
    Box(modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 14.dp)) {
        if (value.isEmpty()) Text(placeholder, style = st.copy(color = p.tertiary))
        androidx.compose.foundation.text.BasicTextField(value, onChange, singleLine = singleLine, textStyle = st.copy(color = p.text),
            cursorBrush = SolidColor(p.accent), keyboardOptions = keyboard, visualTransformation = visual, modifier = Modifier.fillMaxWidth())
    }
}
