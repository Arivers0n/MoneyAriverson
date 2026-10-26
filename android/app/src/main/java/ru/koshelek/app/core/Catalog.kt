package ru.koshelek.app.core

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.serialization.json.*
import ru.koshelek.app.data.TxKind
import ru.koshelek.app.data.str

fun hexColor(hex: String): Color {
    val v = hex.trim().removePrefix("#").toLongOrNull(16) ?: 0x7A8580
    return Color(0xFF000000 or v)
}

data class Category(val id: String, val name: String, val hex: String, val kind: TxKind, val symbol: String) {
    val color get() = hexColor(hex)
    val icon get() = Icons2.of(symbol)
}

/** Значки iPhone (SF Symbols) → значки Material. */
object Icons2 {
    private val map: Map<String, ImageVector> = mapOf(
        "cart.fill" to Icons.Rounded.ShoppingCart, "basket.fill" to Icons.Rounded.ShoppingBasket,
        "cup.and.saucer.fill" to Icons.Rounded.LocalCafe, "fork.knife" to Icons.Rounded.Restaurant,
        "takeoutbag.and.cup.and.straw.fill" to Icons.Rounded.Fastfood, "wineglass.fill" to Icons.Rounded.WineBar,
        "car.fill" to Icons.Rounded.DirectionsCar, "bus.fill" to Icons.Rounded.DirectionsBus, "tram.fill" to Icons.Rounded.Tram,
        "fuelpump.fill" to Icons.Rounded.LocalGasStation, "airplane" to Icons.Rounded.Flight, "bicycle" to Icons.Rounded.PedalBike,
        "house.fill" to Icons.Rounded.Home, "bolt.fill" to Icons.Rounded.Bolt, "drop.fill" to Icons.Rounded.WaterDrop,
        "wifi" to Icons.Rounded.Wifi, "phone.fill" to Icons.Rounded.Phone, "tv.fill" to Icons.Rounded.Tv,
        "cross.case.fill" to Icons.Rounded.MedicalServices, "pills.fill" to Icons.Rounded.Medication, "heart.fill" to Icons.Rounded.Favorite,
        "figure.run" to Icons.AutoMirrored.Rounded.DirectionsRun, "dumbbell.fill" to Icons.Rounded.FitnessCenter, "scissors" to Icons.Rounded.ContentCut,
        "tshirt.fill" to Icons.Rounded.Checkroom, "bag.fill" to Icons.Rounded.ShoppingBag, "gift.fill" to Icons.Rounded.CardGiftcard,
        "gamecontroller.fill" to Icons.Rounded.SportsEsports, "film.fill" to Icons.Rounded.Movie, "music.note" to Icons.Rounded.MusicNote,
        "book.fill" to Icons.AutoMirrored.Rounded.MenuBook, "graduationcap.fill" to Icons.Rounded.School, "pawprint.fill" to Icons.Rounded.Pets,
        "leaf.fill" to Icons.Rounded.Eco, "teddybear.fill" to Icons.Rounded.ChildCare, "stroller.fill" to Icons.Rounded.ChildFriendly,
        "wrench.and.screwdriver.fill" to Icons.Rounded.Build, "hammer.fill" to Icons.Rounded.Handyman,
        "building.columns.fill" to Icons.Rounded.AccountBalance, "creditcard.fill" to Icons.Rounded.CreditCard,
        "banknote.fill" to Icons.Rounded.Payments, "percent" to Icons.Rounded.Percent, "briefcase.fill" to Icons.Rounded.Work,
        "laptopcomputer" to Icons.Rounded.Laptop, "iphone" to Icons.Rounded.Smartphone, "sparkles" to Icons.Rounded.AutoAwesome,
        "star.fill" to Icons.Rounded.Star, "ellipsis" to Icons.Rounded.MoreHoriz, "play.rectangle.fill" to Icons.Rounded.Subscriptions,
        "arrow.uturn.backward" to Icons.AutoMirrored.Rounded.Undo, "target" to Icons.Rounded.TrackChanges, "airplane.departure" to Icons.Rounded.FlightTakeoff,
        "car.side.fill" to Icons.Rounded.DirectionsCar, "house.and.flag.fill" to Icons.Rounded.House, "beach.umbrella.fill" to Icons.Rounded.BeachAccess,
        "shield.fill" to Icons.Rounded.Shield, "arrow.left.arrow.right" to Icons.Rounded.SwapHoriz,
    )
    fun of(sf: String): ImageVector = map[sf] ?: Icons.Rounded.Category
    val choices = map.keys.toList()
}

object Catalog {
    private val baseExpense = listOf(
        Category("food", "Продукты", "2E8B57", TxKind.EXP, "cart.fill"),
        Category("cafe", "Кафе", "D9822B", TxKind.EXP, "cup.and.saucer.fill"),
        Category("transport", "Транспорт", "3B6FD8", TxKind.EXP, "car.fill"),
        Category("home", "Жильё и ЖКУ", "7B5CC4", TxKind.EXP, "house.fill"),
        Category("loans", "Кредиты и долги", "4E5E9E", TxKind.EXP, "building.columns.fill"),
        Category("subs", "Подписки", "8A4FD0", TxKind.EXP, "play.rectangle.fill"),
        Category("phone", "Связь и интернет", "1A9BB0", TxKind.EXP, "wifi"),
        Category("health", "Здоровье", "D04F6E", TxKind.EXP, "cross.case.fill"),
        Category("clothes", "Одежда", "A4703A", TxKind.EXP, "tshirt.fill"),
        Category("fun", "Развлечения", "C04FB0", TxKind.EXP, "gamecontroller.fill"),
        Category("gifts", "Подарки", "E0A21A", TxKind.EXP, "gift.fill"),
        Category("savings", "Накопления", "2F7D8C", TxKind.EXP, "banknote.fill"),
        Category("other", "Другое", "7A8580", TxKind.EXP, "ellipsis"),
    )
    private val baseIncome = listOf(
        Category("salary", "Зарплата", "17805A", TxKind.INC, "briefcase.fill"),
        Category("side", "Подработка", "2F9E8F", TxKind.INC, "hammer.fill"),
        Category("debtback", "Возврат долга", "3E7FA8", TxKind.INC, "arrow.uturn.backward"),
        Category("cashback", "Кэшбэк", "9A8A1F", TxKind.INC, "percent"),
        Category("gift", "Подарок", "E0A21A", TxKind.INC, "gift.fill"),
        Category("iother", "Другое", "7A8580", TxKind.INC, "ellipsis"),
    )

    /** Настройки категорий приходят с сервера (cats в prefs) — общие с iPhone. */
    @Volatile private var cats: JsonObject = JsonObject(emptyMap())
    @Volatile private var cache: List<Category>? = null
    var hidden: Set<String> = emptySet(); private set

    fun update(c: JsonObject) {
        if (c == cats && cache != null) return
        cats = c
        hidden = (c["hidden"] as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }?.toSet() ?: emptySet()
        cache = null
    }

    val all: List<Category>
        get() = cache ?: run {
            val ov = cats["overrides"] as? JsonObject
            val base = (baseExpense + baseIncome).map { c ->
                val o = ov?.get(c.id) as? JsonObject
                if (o == null) c else c.copy(
                    name = o.str("name").ifEmpty { c.name }, hex = o.str("hex").ifEmpty { c.hex }, symbol = o.str("symbol").ifEmpty { c.symbol })
            }
            val custom = (cats["custom"] as? JsonArray)?.mapNotNull { e ->
                val o = e as? JsonObject ?: return@mapNotNull null
                Category(o.str("id"), o.str("name"), o.str("hex").ifEmpty { "7A8580" },
                    if (o.str("kind") == "inc") TxKind.INC else TxKind.EXP, o.str("symbol").ifEmpty { "ellipsis" })
            } ?: emptyList()
            (base + custom).also { cache = it }
        }

    val expense get() = all.filter { it.kind == TxKind.EXP && it.id !in hidden }
    val income get() = all.filter { it.kind == TxKind.INC && it.id !in hidden }
    fun list(k: TxKind) = if (k == TxKind.INC) income else expense
    fun cat(id: String): Category = all.firstOrNull { it.id == id } ?: all.first { it.id == "other" }
    fun valid(id: String, kind: TxKind): String =
        if (all.any { it.id == id && it.kind == kind }) id else if (kind == TxKind.INC) "iother" else "other"
    fun describe(): String =
        "Категории расходов (type \"exp\"): " + expense.joinToString { "${it.id}=${it.name}" } +
        ".\nКатегории доходов (type \"inc\"): " + income.joinToString { "${it.id}=${it.name}" } + "."
}
