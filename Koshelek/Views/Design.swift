import SwiftUI

// MARK: - Стекло (iOS 26) с запасным вариантом

extension View {
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive { self.glassEffect(.regular.interactive(), in: shape) }
            else { self.glassEffect(.regular, in: shape) }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Круглая стеклянная кнопка с иконкой.
struct GlassCircle: View {
    let symbol: String
    var size: CGFloat = 46
    var weight: Font.Weight = .medium
    var tint: Color = .primary
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: weight))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(Pressable(scale: 0.92))
        .glass(Circle(), interactive: true)
    }
}

/// Группа иконок в одной стеклянной капсуле.
struct GlassIconGroup: View {
    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        var dot = false
        let action: () -> Void
    }
    let items: [Item]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { it in
                Button(action: it.action) {
                    Image(systemName: it.symbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 46)
                        .overlay(alignment: .topTrailing) {
                            if it.dot { Circle().fill(Theme.exp).frame(width: 8, height: 8).offset(x: -8, y: 10) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(Pressable(scale: 0.9))
            }
        }
        .padding(.horizontal, 4)
        .glass(Capsule())
    }
}

/// Плитка категории: скруглённый квадрат с мягкой заливкой цветом категории.
struct CategoryTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = Appearance.shared.compact ? 40 : 50
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Переключатель месяца в капсуле: ‹ Сентябрь ›
struct MonthPill: View {
    @Binding var month: Date
    @State private var forward = true
    var body: some View {
        HStack(spacing: 4) {
            Button { forward = false; Haptic.select(); withAnimation(Motion.snappy) { month = month.addingMonths(-1) } } label: {
                Image(systemName: "chevron.left").font(.subheadline.weight(.semibold)).frame(width: 30, height: 36)
            }
            // Направление сдвига совпадает со стрелкой: назад — уезжает вправо, вперёд — влево
            Text(title).font(.body.weight(.medium)).frame(minWidth: 96).id(title)
                .transition(Motion.moves ? .push(from: forward ? .trailing : .leading) : .opacity)
            Button { forward = true; Haptic.select(); withAnimation(Motion.snappy) { month = month.addingMonths(1) } } label: {
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).frame(width: 30, height: 36)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .cardBG(Capsule())
        .clipShape(Capsule())
    }
    var title: String {
        month.sameYear(Date()) ? DF.s(month, "LLLL").capitalizedFirst : DF.s(month, "LLL yyyy").replacingOccurrences(of: ".", with: "").capitalizedFirst
    }
}

extension Date {
    func sameYear(_ o: Date) -> Bool { cal.isDate(self, equalTo: o, toGranularity: .year) }
}

/// Плашка счёта: иконка кошелька + название + баланс.
struct AccountPill: View {
    let title: String
    let amount: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "wallet.bifold.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.inc)
                    .frame(width: 40, height: 40)
                    .background(Theme.inc.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(amount).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.trailing, 8)
            }
            .padding(4)
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable(scale: 0.96))
        .glass(Capsule(), interactive: true)
    }
}

/// Шапка для полноэкранных шторок: ✕ слева, заголовок-капсула по центру, действия справа.
struct SheetBar<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.subheadline.weight(.semibold)) }
                Text(title).font(.body.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .glass(Capsule())
            HStack {
                GlassCircle(symbol: "xmark", weight: .semibold) { dismiss() }
                Spacer()
                trailing()
            }
        }
    }
}

extension SheetBar where Trailing == EmptyView {
    init(title: String, symbol: String? = nil) {
        self.title = title
        self.symbol = symbol
        self.trailing = { EmptyView() }
    }
}

/// Сегменты-капсулы: «Бюджеты | Копилки», «Приход | Расход».
struct PillToggle: View {
    struct Option: Identifiable {
        let id: Int
        let title: String
        let symbol: String
        var color: Color = .primary
    }
    let options: [Option]
    @Binding var selection: Int
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { o in
                let on = selection == o.id
                Button { Haptic.select(); withAnimation(Motion.snappy) { selection = o.id } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: o.symbol).font(.subheadline.weight(.semibold))
                        if on { Text(o.title).font(.body.weight(.semibold)).transition(.opacity) }
                    }
                    .foregroundStyle(on ? o.color : Color.secondary)
                    .padding(.horizontal, on ? 14 : 12).frame(height: 38)
                    .background {
                        // подложка переезжает к выбранной вкладке, а не мигает
                        if on {
                            Capsule().fill(o.color.opacity(o.color == .primary ? 0.12 : 0.18))
                                .matchedGeometryEffect(id: "pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .cardBG(Capsule())
    }
}

/// Пустое состояние с крупной контурной иконкой.
struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .ultraLight))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 60)
    }
}

/// Карточка-строка списка.
struct RowCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 14) { content() }
            .padding(.horizontal, 14).padding(.vertical, Appearance.shared.compact ? 8 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
