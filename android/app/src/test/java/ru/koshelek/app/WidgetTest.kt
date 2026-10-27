package ru.koshelek.app

import android.graphics.Bitmap
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import ru.koshelek.app.core.*
import ru.koshelek.app.data.Settings
import ru.koshelek.app.widget.WidgetAssets
import ru.koshelek.app.widget.WidgetRender
import java.io.File
import java.io.FileOutputStream

/** Рисует виджеты всех пресетов и размеров в build/screens/widgets и проверяет модель дизайна. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class WidgetTest {
    private fun save(bmp: Bitmap, name: String) {
        val dir = File("build/screens/widgets").apply { mkdirs() }
        FileOutputStream(File(dir, "$name.png")).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test fun render() {
        val app = RuntimeEnvironment.getApplication()
        Settings.init(app)
        val snap = WidgetSnapshot.sample()
        val pet = WidgetAssets.pet(app, snap.petId)
        for (preset in WidgetPreset.entries) for (f in WidgetFamilyKind.desktop) {
            var d = WidgetPresets.make(preset, f)
            if (preset == WidgetPreset.kopilka && f == WidgetFamilyKind.large) d = d.copy(blocks = d.blocks + WidgetBlock(kind = WidgetBlockKind.petImage))
            val bmp = WidgetRender.render(d, snap, pet, (f.previewW * 3).toInt(), (f.previewH * 3).toInt())
            assertEquals((f.previewW * 3).toInt(), bmp.width)
            save(bmp, "${preset.name}_${f.name}")
        }
        // все виды блоков в большом виджете
        val all = WidgetPresets.make(WidgetPreset.night, WidgetFamilyKind.large).copy(
            layout = WidgetLayoutKind.stack,
            blocks = WidgetBlockKind.entries.take(9).map { WidgetBlock(kind = it) },
        )
        save(WidgetRender.render(all, snap, pet, 364 * 3, 382 * 3), "blocks_a")
        val rest = all.copy(blocks = WidgetBlockKind.entries.drop(9).map { WidgetBlock(kind = it) })
        save(WidgetRender.render(rest, snap, pet, 364 * 3, 382 * 3), "blocks_b")
    }

    @Test fun model() {
        val set = WidgetConfigSet.makeDefault()
        assertEquals(6, set.slots.size)
        assertEquals(WidgetFamilyKind.entries.size, set.slots[0].designs.size)
        // границы
        val bad = WidgetPresets.make(WidgetPreset.night, WidgetFamilyKind.small).copy(padding = 999.0)
        assertEquals(32.0, bad.validated().padding, 0.0)
        assertTrue(WidgetPresets.make(WidgetPreset.night, WidgetFamilyKind.small).blocks.size <= 4)
        assertEquals("5FD6C8", HexColor.normalize("#5fd6c8", "000000"))
        assertEquals("FFFFFF", HexColor.normalize("fff", "000000"))
    }

    @Test fun texts() {
        val snap = WidgetSnapshot.sample()
        val ring = WidgetContent.value(WidgetBlock(kind = WidgetBlockKind.budgetRing), snap) as WidgetValue.Ring
        assertEquals("62%", ring.center)
        assertEquals("12 340 ₽", WidgetMoney.rub(12340.0))
        assertEquals("−5 ₽", WidgetMoney.rub(-5.0))
    }
}
