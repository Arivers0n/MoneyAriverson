import SwiftUI
import UIKit

// MARK: - Палитра экрана «Сегодня»
// Все варианты экрана берут цвета отсюда: фон, карточки, текст и акценты выводятся из выбранной темы,
// светлого/тёмного режима и цветов пары. Поэтому любой вариант выглядит родным в любой теме.

struct TodayPalette {
    let dark: Bool
    /// Фон экрана, тон верха, карточка, поле ввода — как в теме.
    let bg, top, card, field: Color
    /// Насыщенный тёмный тон темы (верх тёмного режима): сцена, занавес, ночь.
    let deep: Color
    /// Бумага: записки, полоски, билеты.
    let paper: Color
    /// Текст: главный, обычный, приглушённый, совсем тихий; линии-разделители.
    let ink, ink2, muted, faint, line: Color
    /// Тёмный текст темы — для того, что всегда лежит на светлом (фотобумага, магниты).
    let inkOnLight: Color
    /// Цвета пары и их версии, которые читаются как текст на фоне темы.
    let me, partner, meText, partnerText: Color
    /// Тень в оттенке темы.
    let shadow: Color
    let hue: CGFloat

    init(scheme: ColorScheme, me: Color, partner: Color) {
        let t = Theme.current
        let d = scheme == .dark
        dark = d
        bg = Color(hex: d ? t.bgD : t.bgL)
        top = Color(hex: d ? t.topD : t.topL)
        card = Color(hex: d ? t.cardD : t.cardL)
        field = Color(hex: d ? t.fieldD : t.fieldL)
        deep = Color(hex: t.topD)
        paper = d ? Color(hex: t.fieldD) : Color(hex: t.cardL)

        // Оттенок темы берём из насыщенного верха тёмного режима: там цвет темы выражен сильнее всего.
        let h = HSB(Color(hex: t.topD)).h
        hue = h
        ink = d ? Color(hue: h, saturation: 0.05, brightness: 0.97) : Color(hue: h, saturation: 0.42, brightness: 0.16)
        ink2 = d ? Color(hue: h, saturation: 0.08, brightness: 0.86) : Color(hue: h, saturation: 0.28, brightness: 0.30)
        muted = d ? Color(hue: h, saturation: 0.12, brightness: 0.70) : Color(hue: h, saturation: 0.20, brightness: 0.43)
        faint = d ? Color(hue: h, saturation: 0.12, brightness: 0.50) : Color(hue: h, saturation: 0.14, brightness: 0.66)
        line = (d ? Color.white : Color(hue: h, saturation: 0.5, brightness: 0.2)).opacity(d ? 0.12 : 0.10)
        inkOnLight = Color(hue: h, saturation: 0.42, brightness: 0.16)

        self.me = me
        self.partner = partner
        meText = TodayPalette.readable(me, dark: d)
        partnerText = TodayPalette.readable(partner, dark: d)
        shadow = d ? Color.black.opacity(0.42) : Color(hue: h, saturation: 0.55, brightness: 0.25).opacity(0.13)
    }

    /// Цвет пары, который читается как текст: на светлом — темнее, на тёмном — светлее.
    static func readable(_ c: Color, dark: Bool) -> Color {
        let x = HSB(c)
        if dark {
            return Color(hue: x.h, saturation: min(x.s, 0.55), brightness: max(x.b, 0.9))
        }
        // Жёлтые и зелёные кажутся светлее при той же яркости — их притемняем сильнее.
        let yellowish = x.h > 0.1 && x.h < 0.45
        return Color(hue: x.h, saturation: max(x.s, 0.6), brightness: min(x.b, yellowish ? 0.5 : 0.62))
    }

    /// Текст поверх произвольного цвета: тёмный текст темы или почти белый.
    func text(on c: Color) -> Color {
        HSB.luminance(c) > 0.42 ? inkOnLight : Color(hue: hue, saturation: 0.04, brightness: 0.98)
    }

    /// Мягкая заливка цветом поверх фона (для пятен, островов, записок).
    func wash(_ c: Color, _ amount: Double) -> Color { HSB.mix(dark ? bg : .white, c, amount) }

    static func make(_ store: Store, _ scheme: ColorScheme) -> TodayPalette {
        TodayPalette(scheme: scheme, me: store.meColor, partner: store.partnerColor)
    }
}

/// Разбор цвета на тон/насыщенность/яркость и простые смеси.
struct HSB {
    let h, s, b: CGFloat
    init(_ c: Color) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        self.h = h; self.s = s; self.b = b
    }

    static func rgba(_ c: Color) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Смесь двух цветов: t = 0 — первый, t = 1 — второй.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let x = rgba(a), y = rgba(b)
        let k = CGFloat(min(1, max(0, t)))
        return Color(.sRGB, red: Double(x.0 + (y.0 - x.0) * k), green: Double(x.1 + (y.1 - x.1) * k),
                     blue: Double(x.2 + (y.2 - x.2) * k), opacity: 1)
    }

    static func luminance(_ c: Color) -> Double {
        let x = rgba(c)
        func lin(_ v: CGFloat) -> Double { let d = Double(v); return d <= 0.03928 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(x.0) + 0.7152 * lin(x.1) + 0.0722 * lin(x.2)
    }
}

private struct TodayPaletteKey: EnvironmentKey {
    static let defaultValue = TodayPalette(scheme: .light, me: Color(hex: "0593C6"), partner: Color(hex: "DB3996"))
}

extension EnvironmentValues {
    var todayPalette: TodayPalette {
        get { self[TodayPaletteKey.self] }
        set { self[TodayPaletteKey.self] = newValue }
    }
}

/// Кнопка-капсула экрана «Сегодня»: заливка + подобранный к ней цвет текста.
struct TodayPill: View {
    let title: String
    var symbol: String? = nil
    let fill: Color
    let text: Color
    var height: CGFloat = 48
    var font: Font = .body.weight(.semibold)
    var body: some View {
        HStack(spacing: 7) {
            if let symbol { Image(systemName: symbol) }
            Text(title).lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(font).foregroundStyle(text)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity).frame(height: height)
        .background(fill, in: Capsule())
    }
}
