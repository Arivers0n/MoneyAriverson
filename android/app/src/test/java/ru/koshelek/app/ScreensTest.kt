package ru.koshelek.app

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onRoot
import com.github.takahirom.roborazzi.captureRoboImage
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import ru.koshelek.app.data.*
import ru.koshelek.app.ui.*
import java.time.LocalDate

/** Рисует основные экраны с примерными данными и сохраняет PNG в build/screens. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35], qualifiers = "w411dp-h891dp-xxhdpi")
class ScreensTest {
    @get:Rule val rule = createComposeRule()

    @Before fun seed() {
        Settings.setBool("welcomed", true)
        if (Store.snapshot.value.txs.isNotEmpty()) return
        val now = LocalDate.now()
        val card = Account(name = "Карта", start = 42000.0, hex = "2B47C9"); Store.saveAccount(card)
        val cash = Account(name = "Наличные", start = 3000.0, hex = "17805A"); Store.saveAccount(cash)
        val items = listOf(
            Triple("food", 1840.0, "Пятёрочка"), Triple("cafe", 250.0, "Кофе"), Triple("transport", 420.0, "Такси"),
            Triple("cafe", 250.0, "Кофе"), Triple("subs", 399.0, "Яндекс Плюс"), Triple("food", 960.0, "ВкусВилл"),
            Triple("clothes", 4990.0, "Кроссовки"), Triple("cafe", 690.0, "Обед"), Triple("transport", 64.0, "Метро"),
        )
        items.forEachIndexed { i, (c, a, n) -> Store.saveTx(Tx(kind = TxKind.EXP, amount = a, cat = c, note = n, date = now.minusDays((i / 2).toLong()), acc = card.id)) }
        Store.saveTx(Tx(kind = TxKind.INC, amount = 85000.0, cat = "salary", note = "Зарплата", date = now.withDayOfMonth(1), acc = card.id))
        Store.saveTx(Tx(kind = TxKind.EXP, amount = 250.0, cat = "cafe", note = "Кофе", date = now.minusMonths(1), acc = card.id))
        Store.saveTx(Tx(kind = TxKind.EXP, amount = 12000.0, cat = "food", note = "Продукты", date = now.minusMonths(1).withDayOfMonth(5), acc = card.id))
        Store.saveDebt(Debt(name = "Кредит на машину", lender = "Сбер", total = 240000.0, payment = 12000.0, n = 20, first = now.minusMonths(2).withDayOfMonth(15),
            rate = 18.0, payments = mapOf(0 to Paid(now.minusMonths(2).withDayOfMonth(14), 12000.0, false))))
        Store.saveDebt(Debt(type = DebtType.MICRO, name = "Займ до зарплаты", lender = "Займер", total = 8000.0, payment = 8000.0, n = 1, first = now.plusDays(3)))
        Store.saveRec(Recurring(name = "Яндекс Плюс", amount = 399.0, cat = "subs", day = 3))
        Store.saveGoal(Goal(name = "Отпуск", target = 120000.0, hex = "C2621F", symbol = "airplane", autoPercent = 10.0,
            log = listOf(GoalEntry(now.minusMonths(1), 20000.0), GoalEntry(now, 8500.0))))
        Store.savePrefs(SpacePrefs(budget = 60000.0, catLimits = mapOf("cafe" to 5000.0)))
    }

    private fun shot(name: String, content: @Composable () -> Unit) {
        rule.mainClock.autoAdvance = false
        rule.setContent { KopilkaTheme { content() } }
        rule.mainClock.advanceTimeBy(2500)
        rule.onRoot().captureRoboImage("build/screens/$name.png")
    }

    @Test fun home() = shot("01_home") { AppRoot() }
    @Test fun txForm() = shot("02_tx") { TxForm(null) }
    @Test fun stats() = shot("03_stats") { StatsScreen() }
    @Test fun insights() = shot("04_insights") { InsightsScreen() }
    @Test fun payments() = shot("05_payments") { PaymentsScreen() }
    @Test fun goals() = shot("06_goals") { GoalsScreen(1) }
    @Test fun budgets() = shot("07_budgets") { GoalsScreen(0) }
    @Test fun settings() = shot("08_settings") { SettingsScreen() }
    @Test fun appearance() = shot("09_appearance") { AppearanceScreen() }
    @Test fun welcome() = shot("10_welcome") { WelcomeScreen {} }
    @Test fun voice() = shot("11_voice") { VoiceOverlay() }
    @Test fun review() = shot("12_review") {
        ReviewScreen(listOf(ParsedItem(cat = "cafe", amount = 250.0, note = "Кофе"), ParsedItem(cat = "transport", amount = 400.0, note = "Такси")), "«кофе 250, такси 400»")
    }
    @Config(qualifiers = "w1194dp-h834dp-land-xhdpi")
    @Test fun tablet() = shot("13_tablet") { AppRoot() }
}
