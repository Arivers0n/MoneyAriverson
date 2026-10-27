package ru.koshelek.app.widget

import android.content.Context
import android.graphics.*
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import ru.koshelek.app.core.*
import java.time.LocalDateTime
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Рисует виджет в картинку: и сам виджет на рабочем столе, и предпросмотр в конструкторе —
 * один и тот же код, поэтому они выглядят одинаково. Раскладка повторяет WidgetRenderer.swift на iPhone.
 * Рисуем в «виртуальных точках» (ширина = previewW размера), потом масштабируем под экран.
 */
object WidgetRender {
    private const val CORNER = 22f
    private val lettersMonday = listOf("П", "В", "С", "Ч", "П", "С", "В")
    private val lettersSunday = listOf("В", "П", "В", "С", "Ч", "П", "С")

    fun render(design: WidgetDesign, snap: WidgetSnapshot, pet: Bitmap?, widthPx: Int, heightPx: Int,
               now: LocalDateTime = LocalDateTime.now()): Bitmap {
        val w = max(1, widthPx); val h = max(1, heightPx)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val vw = design.family.previewW
        val scale = w / vw
        val vh = h / scale
        c.scale(scale, scale)
        c.clipPath(Path().apply { addRoundRect(RectF(0f, 0f, vw, vh), CORNER, CORNER, Path.Direction.CW) })
        drawBackground(c, design.background, vw, vh)

        val cells = design.blocks.map { Cell(it, WidgetContent.value(it, snap, now)) }
        val pad = design.padding.toFloat()
        val x = pad; val y = pad; val cw = vw - pad * 2; val ch = vh - pad * 2
        val painter = Painter(c, pet)
        when (design.layout) {
            WidgetLayoutKind.stack -> painter.flow(cells, x, y, cw, ch, 0f, true)
            WidgetLayoutKind.topFeature -> painter.flow(cells, x, y, cw, ch, design.spacing.toFloat(), false)
            WidgetLayoutKind.leadingFeature -> painter.leading(cells, x, y, cw, ch, design.spacing.toFloat())
        }
        return bmp
    }

    // MARK: Фон

    private fun drawBackground(c: Canvas, bg: WidgetBackground, w: Float, h: Float) {
        val a = HexColor.argb(bg.colorA, bg.opacity)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        if (bg.kind == WidgetBackgroundKind.solid) {
            p.color = a
        } else {
            val b = HexColor.argb(bg.colorB, bg.opacity)
            val r = Math.toRadians(bg.angle)
            val sx = (0.5 - cos(r) / 2).toFloat() * w; val sy = (0.5 - sin(r) / 2).toFloat() * h
            val ex = (0.5 + cos(r) / 2).toFloat() * w; val ey = (0.5 + sin(r) / 2).toFloat() * h
            p.shader = LinearGradient(sx, sy, ex, ey, a, b, Shader.TileMode.CLAMP)
        }
        c.drawRect(0f, 0f, w, h, p)
    }

    // MARK: Ячейки

    private class Cell(val block: WidgetBlock, val value: WidgetValue) {
        /** Кольцо и питомец занимают всё свободное место. */
        val flexible get() = value is WidgetValue.Ring || value is WidgetValue.Pet
        val after get() = block.spaceAfter.toFloat()
    }

    private class Painter(val c: Canvas, val pet: Bitmap?) {

        // --- раскладки

        fun flow(cells: List<Cell>, x: Float, y: Float, w: Float, h: Float, gap: Float, centerIfFixed: Boolean) {
            if (cells.isEmpty()) return
            val heights = cells.map { if (it.flexible) 0f else measure(it, w) }
            val flexCount = cells.count { it.flexible }
            val gaps = gap * (cells.size - 1)
            val fixedSum = cells.indices.sumOf { i -> ((if (cells[i].flexible) 0f else heights[i]) + cells[i].after).toDouble() }.toFloat() + gaps
            val flexH = if (flexCount > 0) max(20f, (h - fixedSum) / flexCount) else 0f
            var cy = y
            if (flexCount == 0 && centerIfFixed) cy += max(0f, (h - fixedSum) / 2)
            cells.forEachIndexed { i, cell ->
                val ch = if (cell.flexible) flexH else heights[i]
                draw(cell, x, cy, w, ch)
                cy += ch + cell.after + gap
            }
        }

        fun leading(cells: List<Cell>, x: Float, y: Float, w: Float, h: Float, spacing: Float) {
            val first = cells.firstOrNull() ?: return
            val colW = if (first.flexible) min(h - first.after, (w - spacing) * 0.45f).coerceAtLeast(20f) else (w - spacing) / 2
            val fh = if (first.flexible) h - first.after else measure(first, colW)
            draw(first, x, y + max(0f, (h - fh - first.after) / 2), colW, fh)
            flow(cells.drop(1), x + colW + spacing, y, w - colW - spacing, h, 0f, true)
        }

        // --- размеры

        fun measure(cell: Cell, w: Float): Float {
            val b = cell.block; val st = b.style
            return when (val v = cell.value) {
                is WidgetValue.Text -> text(v.t, st, 1.0, w, st.lineLimit).height.toFloat()
                is WidgetValue.Stat -> {
                    var hh = text(v.value, st, 1.0, w, st.lineLimit).height.toFloat()
                    if (b.showCaption) hh += 1f + text(v.caption, st, b.captionScale, w, 1, 0.8f).height
                    hh
                }
                is WidgetValue.Lines -> {
                    val shown = v.lines.take(max(1, st.lineLimit))
                    shown.sumOf { text(it, st, 1.0, w, 1).height.toDouble() }.toFloat() + 2f * (shown.size - 1)
                }
                is WidgetValue.Bar -> text(v.label, st, 1.0, w, 1).height + 3f + barHeight(b)
                is WidgetValue.Dots -> {
                    val size = dotSize(b)
                    size + if (b.showCaption) 2f + text("П", st, b.captionScale, size * 2, 1).height else 0f
                }
                else -> 0f
            }
        }

        private fun barHeight(b: WidgetBlock) = max(4.0, b.thickness * 0.6).toFloat()
        private fun dotSize(b: WidgetBlock) = min(18.0, max(6.0, b.thickness)).toFloat()

        // --- рисование

        fun draw(cell: Cell, x: Float, y: Float, w: Float, h: Float) {
            val b = cell.block; val st = b.style
            when (val v = cell.value) {
                is WidgetValue.Text -> drawText(text(v.t, st, 1.0, w, st.lineLimit), x, y)
                is WidgetValue.Stat -> {
                    val l1 = text(v.value, st, 1.0, w, st.lineLimit)
                    drawText(l1, x, y)
                    if (b.showCaption) drawText(text(v.caption, st, b.captionScale, w, 1, 0.8f), x, y + l1.height + 1f)
                }
                is WidgetValue.Lines -> {
                    var cy = y
                    for (line in v.lines.take(max(1, st.lineLimit))) {
                        val l = text(line, st, 1.0, w, 1)
                        drawText(l, x, cy); cy += l.height + 2f
                    }
                }
                is WidgetValue.Bar -> {
                    val l = text(v.label, st, 1.0, w, 1)
                    drawText(l, x, y)
                    bar(x, y + l.height + 3f, w, barHeight(b), v.fraction, b)
                }
                is WidgetValue.Dots -> dots(v, b, x, y, w)
                is WidgetValue.Ring -> ring(v, b, x, y, w, h)
                is WidgetValue.Pet -> petBlock(v, b, x, y, w, h)
            }
        }

        private fun alignX(a: WidgetAlign, x: Float, w: Float, itemW: Float) = when (a) {
            WidgetAlign.leading -> x
            WidgetAlign.center -> x + (w - itemW) / 2
            WidgetAlign.trailing -> x + w - itemW
        }

        private fun ring(v: WidgetValue.Ring, b: WidgetBlock, x: Float, y: Float, w: Float, h: Float) {
            val th = b.thickness.toFloat()
            val side = max(20f, min(w, h))
            val sx = alignX(b.style.alignment, x, w, side); val sy = y + (h - side) / 2
            val r = (side - th) / 2
            val cx = sx + side / 2; val cy = sy + side / 2
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeWidth = th }
            p.color = HexColor.argb(b.trackHex, b.trackOpacity)
            c.drawCircle(cx, cy, r, p)
            p.color = HexColor.argb(b.accentHex); p.strokeCap = Paint.Cap.ROUND
            val f = v.fraction.coerceIn(0.001, 1.0)
            c.drawArc(RectF(cx - r, cy - r, cx + r, cy + r), -90f, (360 * f).toFloat(), false, p)
            val inner = max(10f, side - 2 * (th + 2))
            val l1 = text(v.center, b.style, 1.0, inner, 1)
            val l2 = if (b.showCaption) text(v.caption, b.style, b.captionScale, inner, 1, 0.8f) else null
            val total = l1.height + (l2?.height ?: 0)
            var ty = cy - total / 2f
            drawText(l1, cx - inner / 2, ty); ty += l1.height
            if (l2 != null) drawText(l2, cx - inner / 2, ty)
        }

        private fun bar(x: Float, y: Float, w: Float, h: Float, f: Double, b: WidgetBlock) {
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            p.color = HexColor.argb(b.trackHex, b.trackOpacity)
            c.drawRoundRect(RectF(x, y, x + w, y + h), h / 2, h / 2, p)
            p.color = HexColor.argb(b.accentHex)
            val fw = max(h, (w * f.coerceIn(0.0, 1.0)).toFloat())
            if (f > 0) c.drawRoundRect(RectF(x, y, x + fw, y + h), h / 2, h / 2, p)
        }

        private fun dots(v: WidgetValue.Dots, b: WidgetBlock, x: Float, y: Float, w: Float) {
            val size = dotSize(b)
            val total = 7 * size + 6 * 6f
            // Если не помещается — ужимаем промежутки
            val sx = alignX(b.style.alignment, x, w, min(total, w))
            val letters = if (v.first == 1) lettersSunday else lettersMonday
            val p = Paint(Paint.ANTI_ALIAS_FLAG)
            v.dots.forEachIndexed { i, d ->
                val cx = sx + i * (size + 6f) + size / 2
                p.style = Paint.Style.FILL
                p.color = when (d) {
                    WidgetDot.done -> HexColor.argb(b.accentHex)
                    WidgetDot.partial -> HexColor.argb(b.accentHex, 0.5)
                    WidgetDot.missed -> HexColor.argb(b.trackHex, min(1.0, b.trackOpacity * 2))
                    else -> HexColor.argb(b.trackHex, b.trackOpacity)
                }
                c.drawCircle(cx, y + size / 2, size / 2, p)
                if (d == WidgetDot.today) {
                    p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f; p.color = HexColor.argb(b.accentHex)
                    c.drawCircle(cx, y + size / 2, size / 2 - 0.75f, p)
                }
                if (b.showCaption) {
                    val l = text(letters[i % 7], b.style, b.captionScale, size * 2, 1, 0.8f, Layout.Alignment.ALIGN_CENTER)
                    drawText(l, cx - size, y + size + 2f)
                }
            }
        }

        private fun petBlock(v: WidgetValue.Pet, b: WidgetBlock, x: Float, y: Float, w: Float, h: Float) {
            val cap = if (b.showCaption) text(v.name, b.style, b.captionScale, w, 1) else null
            val capH = (cap?.height ?: 0) + if (cap != null) 2f else 0f
            val boxH = max(10f, h - capH)
            val img = pet
            if (img != null) {
                val k = min(w / img.width, boxH / img.height)
                val iw = img.width * k; val ih = img.height * k
                val ix = alignX(b.style.alignment, x, w, iw); val iy = y + (boxH - ih) / 2
                val sp = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                sp.colorFilter = null
                c.drawBitmap(img, null, RectF(ix, iy, ix + iw, iy + ih), sp)
            } else {
                val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = min(boxH * 0.7f, b.style.size.toFloat() * 2) }
                val tw = p.measureText("🐾")
                c.drawText("🐾", alignX(b.style.alignment, x, w, tw), y + boxH / 2 + p.textSize * 0.35f, p)
            }
            if (cap != null) drawText(cap, x, y + boxH + 2f)
        }

        // --- текст

        private fun drawText(l: StaticLayout, x: Float, y: Float) {
            c.save(); c.translate(x, y); l.draw(c); c.restore()
        }

        private fun text(s: String, st: WidgetTextStyle, scale: Double, w: Float, maxLines: Int, alphaMul: Float = 1f,
                         forceAlign: Layout.Alignment? = null): StaticLayout {
            val t = if (st.uppercase) s.uppercase(RU) else s
            val width = max(1, w.toInt())
            val align = forceAlign ?: when (st.alignment) {
                WidgetAlign.leading -> Layout.Alignment.ALIGN_NORMAL
                WidgetAlign.center -> Layout.Alignment.ALIGN_CENTER
                WidgetAlign.trailing -> Layout.Alignment.ALIGN_OPPOSITE
            }
            var k = 1.0
            while (true) {
                val last = k <= 0.6001
                val paint = paintFor(st, st.size * scale * k, alphaMul)
                val free = StaticLayout.Builder.obtain(t, 0, t.length, paint, width).setAlignment(align).build()
                if (free.lineCount <= maxLines && !(maxLines == 1 && free.getLineWidth(0) > w + 0.5f && !last)) return free
                if (last) {
                    return StaticLayout.Builder.obtain(t, 0, t.length, paint, width).setAlignment(align)
                        .setMaxLines(maxLines).setEllipsize(TextUtils.TruncateAt.END).build()
                }
                k -= 0.1
            }
        }

        private fun paintFor(st: WidgetTextStyle, size: Double, alphaMul: Float): TextPaint {
            val p = TextPaint(Paint.ANTI_ALIAS_FLAG)
            p.textSize = size.toFloat()
            p.color = HexColor.argb(st.colorHex, st.opacity * alphaMul)
            val base = when (st.design) {
                WidgetFontDesign.serif -> Typeface.SERIF
                WidgetFontDesign.monospaced -> Typeface.MONOSPACE
                else -> Typeface.SANS_SERIF
            }
            p.typeface = if (Build.VERSION.SDK_INT >= 28) Typeface.create(base, (st.weight + 1) * 100, false)
            else Typeface.create(base, if (st.weight >= 6) Typeface.BOLD else Typeface.NORMAL)
            if (st.tracking != 0.0) p.letterSpacing = (st.tracking / size).toFloat()
            return p
        }
    }
}

/** Картинки питомцев для виджета: небольшие копии, чтобы не раздувать память. */
object WidgetAssets {
    private val cache = HashMap<String, Bitmap>()

    @Synchronized
    fun pet(ctx: Context, petId: String): Bitmap? {
        cache[petId]?.let { return it }
        val def = CompanionCatalog.def(petId)
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeResource(ctx.resources, def.art, opts)
        var sample = 1
        while (max(opts.outWidth, opts.outHeight) / (sample * 2) >= 320) sample *= 2
        val bmp = BitmapFactory.decodeResource(ctx.resources, def.art, BitmapFactory.Options().apply { inSampleSize = sample })
        if (bmp != null) cache[petId] = bmp
        return bmp
    }
}
