import SwiftUI

// MARK: - Лента статусов: большие карточки-«истории», сгруппированные по дням

struct StatusFeedView: View {
    @EnvironmentObject var store: Store
    @State private var scope: Int = 0   // 0 все, 1 я, 2 партнёр

    private var items: [StatusItem] {
        store.data.statuses
            .filter { scope == 0 || (scope == 1 ? $0.who == .me : $0.who == .partner) }
            .sorted { $0.started > $1.started }
    }

    private func dayTitle(_ d: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(d) { return "Сегодня" }
        if c.isDateInYesterday(d) { return "Вчера" }
        return d.formatted(Date.FormatStyle().locale(ruLocale).day().month(.wide))
    }

    var body: some View {
        let list = items
        let days = Dictionary(grouping: list) { Calendar.current.startOfDay(for: $0.started) }.keys.sorted(by: >)
        Screen {
            Picker("Чьи", selection: $scope) {
                Text("Все").tag(0)
                Text(store.name(.me)).tag(1)
                Text(store.name(.partner)).tag(2)
            }.pickerStyle(.segmented)
            if list.isEmpty {
                EmptyState(icon: "sparkles", title: "Статусов пока не было", text: "Поставьте статус на экране «Сегодня» — он сохранится здесь как история дня.")
            }
            ForEach(days, id: \.self) { day in
                Text(dayTitle(day)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                ForEach(list.filter { Calendar.current.startOfDay(for: $0.started) == day }) { s in
                    StatusStoryCard(s: s, until: endOf(s))
                }
            }
        }
        .navigationTitle("История статусов")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Когда статус закончился: началом следующего статуса того же человека, иначе — «сейчас».
    private func endOf(_ s: StatusItem) -> Date? {
        let next = store.data.statuses.filter { $0.who == s.who && $0.started > s.started }.min { $0.started < $1.started }
        if let n = next { return n.started }
        return store.statusNow(s.who)?.id == s.id ? nil : min(s.expires, Date())
    }
}

struct StatusStoryCard: View {
    @EnvironmentObject var store: Store
    let s: StatusItem
    let until: Date?
    @State private var float = false

    var body: some View {
        let k = statusKind(s.kind)
        let c = Color(hex: k.hex)
        let t = Date.FormatStyle().locale(ruLocale).hour().minute()
        ZStack {
            if s.hasPhoto, let m = s.media, let f = s.file {
                RemoteImage(media: m, file: f, thumb: "1080x0").clipped()
                LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [c.opacity(0.95), c.opacity(0.55), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 18) {
                    Group {
                        if let e = s.emoji, !e.isEmpty { Text(e).font(.system(size: 92)) }
                        else { Image(systemName: k.symbol).font(.system(size: 84, weight: .semibold)).foregroundStyle(.white) }
                    }
                    .offset(y: float ? -8 : 6)
                    Ellipse().fill(.black.opacity(0.28)).frame(width: float ? 120 : 150, height: 20).blur(radius: 1)
                }
                .offset(y: -10)
            }
            VStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock").font(.caption.weight(.semibold))
                    Text("\(s.started.formatted(t))" + (until.map { " — \($0.formatted(t))" } ?? " — сейчас"))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(store.name(s.who)).font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(store.color(s.who).opacity(0.85), in: Capsule())
                }
                .foregroundStyle(.white.opacity(0.92))
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title).font(.system(size: 28, weight: .bold)).foregroundStyle(.white).lineLimit(2)
                        if !(s.place + s.note).isEmpty {
                            Text([s.place, s.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                        }
                    }
                    Spacer()
                }
            }
            .padding(18)
        }
        .frame(height: 380)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(34), style: .continuous))
        .shadow(color: c.opacity(0.25), radius: 14, y: 8)
        .onAppear { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true } }
    }
}
