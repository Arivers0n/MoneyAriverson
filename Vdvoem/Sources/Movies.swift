import SwiftUI

// MARK: - Фильмы: у каждого свой список и общий

private let movieKinds = ["Фильм", "Сериал", "Мультфильм", "Аниме"]
private let movieEmoji = ["🎬", "📺", "🧸", "🌸"]
private let movieStates = ["Хочу посмотреть", "Смотрю", "Посмотрел"]

struct MoviesView: View {
    @EnvironmentObject var store: Store
    /// 0 — мой список, 1 — партнёра, 2 — общий
    @State private var tab = 2
    @State private var editing: MovieItem?

    private func owner(for tab: Int) -> Who? { tab == 0 ? .me : (tab == 1 ? .partner : nil) }

    private var items: [MovieItem] {
        let o = owner(for: tab)
        return store.data.movies.filter { $0.owner == o }
    }

    var body: some View {
        Screen {
            Picker("Список", selection: $tab.animation(Motion.spring)) {
                Text(store.name(.me)).tag(0)
                Text(store.name(.partner)).tag(1)
                Text("Вместе").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.top, 4)

            stats

            if items.isEmpty {
                EmptyState(icon: "film", title: tab == 2 ? "Общий список пуст" : "Здесь пока пусто",
                           text: tab == 2 ? "Добавьте то, что хотите посмотреть вдвоём, и отмечайте просмотренное."
                                          : "Записывайте, что хочется посмотреть и что уже видели.",
                           action: "Добавить", onTap: { editing = MovieItem(title: "", owner: owner(for: tab)) })
            }
            ForEach(0..<3, id: \.self) { i in
                let st = [1, 0, 2][i]          // сначала «смотрю», потом «хочу», потом «посмотрел»
                let list = items.filter { $0.state == st }.sorted { $0.date > $1.date }
                if !list.isEmpty {
                    SectionTitle("\(movieStates[st]) · \(list.count)", color: [Color.orange, store.meColor, Color.green][i])
                    ForEach(list) { m in row(m) }
                }
            }
        }
        .navigationTitle("Фильмы")
        .pairToolbar(scope: false, add: { editing = MovieItem(title: "", owner: owner(for: tab)) })
        .sheet(item: $editing) { m in MovieSheet(item: m) }
        .animation(Motion.spring, value: store.data.movies)
    }

    private var stats: some View {
        let seen = items.filter { $0.state == 2 }.count
        let now = items.filter { $0.state == 1 }.count
        let want = items.filter { $0.state == 0 }.count
        return HStack(spacing: 8) {
            stat("\(seen)", "посмотрено")
            stat("\(now)", "смотрим")
            stat("\(want)", "в планах")
        }
    }

    private func stat(_ n: String, _ t: String) -> some View {
        VStack(spacing: 2) {
            Text(n).font(.title2.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).card()
    }

    private func row(_ m: MovieItem) -> some View {
        Button { editing = m } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(movieEmoji[min(m.kind, 3)]).font(.system(size: 28))
                    .frame(width: 44, height: 44)
                    .background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.title).font(.body.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Chip(text: movieKinds[min(m.kind, 3)])
                        if !m.year.isEmpty { Chip(text: m.year) }
                        if m.rating > 0 {
                            Text(String(repeating: "★", count: m.rating)).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    if !m.progress.isEmpty && m.state == 1 {
                        Text(m.progress).font(.caption).foregroundStyle(.secondary)
                    }
                    if !m.note.isEmpty { Text(m.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(0..<3, id: \.self) { s in
                        Button(movieStates[s], systemImage: m.state == s ? "checkmark" : "circle") { setState(m, s) }
                    }
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        store.data.movies.removeAll { $0.id == m.id }
                    }
                } label: { Image(systemName: "ellipsis").padding(8).foregroundStyle(.secondary) }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .buttonStyle(PressStyle())
    }

    private func setState(_ m: MovieItem, _ s: Int) {
        guard let i = store.data.movies.firstIndex(where: { $0.id == m.id }) else { return }
        store.data.movies[i].state = s
        store.data.movies[i].date = Date()
        store.tap()
        if s == 2 { store.success() }
    }
}

struct MovieSheet: View {
    @EnvironmentObject var store: Store
    @State var item: MovieItem
    /// 0 — я, 1 — партнёр, 2 — вместе
    @State private var who: Int

    init(item: MovieItem) {
        _item = State(initialValue: item)
        _who = State(initialValue: item.owner == .me ? 0 : (item.owner == .partner ? 1 : 2))
    }

    private var exists: Bool { store.data.movies.contains { $0.id == item.id } }

    var body: some View {
        FormSheet(title: exists ? "Фильм" : "Новый фильм", canSave: !item.title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: save) {
            Section {
                TextField("Название", text: $item.title)
                TextField("Год (по желанию)", text: $item.year).keyboardType(.numberPad)
                Picker("Тип", selection: $item.kind) {
                    ForEach(0..<4, id: \.self) { Text(movieKinds[$0]).tag($0) }
                }
            }
            Section("Чей список") {
                Picker("", selection: $who) {
                    Text(store.name(.me)).tag(0)
                    Text(store.name(.partner)).tag(1)
                    Text("Вместе").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("Статус") {
                Picker("", selection: $item.state) {
                    ForEach(0..<3, id: \.self) { Text(movieStates[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                if item.state == 1 && item.kind != 0 {
                    TextField("Где остановились (сезон, серия)", text: $item.progress)
                }
                if item.state == 2 {
                    HStack {
                        Text("Оценка")
                        Spacer()
                        ForEach(1...5, id: \.self) { n in
                            Image(systemName: n <= item.rating ? "star.fill" : "star")
                                .foregroundStyle(.orange)
                                .onTapGesture { item.rating = item.rating == n ? 0 : n; store.tap() }
                        }
                    }
                }
            }
            Section { TextField("Заметка (где смотреть, впечатления)", text: $item.note, axis: .vertical).lineLimit(1...5) }
            if exists {
                Section {
                    Button("Удалить", role: .destructive) {
                        let id = item.id
                        store.data.movies.removeAll { $0.id == id }
                    }
                }
            }
        }
    }

    private func save() {
        var m = item
        m.owner = who == 0 ? .me : (who == 1 ? .partner : nil)
        m.title = m.title.trimmingCharacters(in: .whitespaces)
        m.date = Date()
        if let i = store.data.movies.firstIndex(where: { $0.id == m.id }) { store.data.movies[i] = m }
        else { store.data.movies.insert(m, at: 0) }
        if m.state == 2 { store.success() }
    }
}
