import SwiftUI

// MARK: - Хотелки

struct WishesView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        let items = store.data.wishes.filter { store.visible($0.owner) }
        Screen {
            if store.data.wishes.isEmpty {
                EmptyState(icon: "gift", title: "Хотелки",
                           text: "Записывайте, что хочется получить. Вторая половинка тайно бронирует подарок — вы не увидите, что именно.",
                           action: "Добавить хотелку", onTap: { adding = true })
            } else if items.isEmpty {
                EmptyState(icon: "gift", title: "Пока пусто", text: "У выбранного человека нет хотелок.")
            }
            ForEach(items) { w in WishRow(w: store.bind(\.wishes, w)) }
        }
        .navigationTitle("Хотелки")
        .pairToolbar(add: { adding = true })
        .sheet(isPresented: $adding) { AddWishSheet() }
    }
}

struct WishRow: View {
    @EnvironmentObject var store: Store
    @Binding var w: Wish

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Circle().fill(store.color(w.owner)).frame(width: 10, height: 10).padding(.top, 7)
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.title).font(.body.weight(.semibold)).strikethrough(w.got)
                    HStack(spacing: 6) {
                        Chip(text: store.name(w.owner), color: store.color(w.owner))
                        if !w.price.isEmpty { Chip(text: w.price + " ₽") }
                        Text(String(repeating: "★", count: w.priority + 1)).font(.caption).foregroundStyle(.orange)
                    }
                    if !w.note.isEmpty { Text(w.note).font(.caption).foregroundStyle(.secondary) }
                    if let u = URL(string: w.link), !w.link.isEmpty {
                        Link(destination: u) { Label("Ссылка", systemImage: "link").font(.caption) }
                    }
                }
                Spacer()
                Menu {
                    Button(w.got ? "Не получено" : "Получено", systemImage: "checkmark.circle") { w.got.toggle() }
                    // Бронь видит только «чужой» человек: у владельца статус не показывается.
                    if store.scope != .we && store.scope != w.owner.asScope {
                        Button(w.reserved ? "Снять бронь" : "Тайно забронировать", systemImage: "lock") { w.reserved.toggle() }
                    }
                    Button("Удалить", systemImage: "trash", role: .destructive) {
                        let id = w.id
                        store.data.wishes.removeAll { $0.id == id }
                    }
                } label: { Image(systemName: "ellipsis").padding(8).foregroundStyle(.secondary) }
            }
            if w.reserved && store.scope != w.owner.asScope && store.scope != .we {
                Label("Вы забронировали этот подарок", systemImage: "lock.fill").font(.caption).foregroundStyle(.green)
            }
        }
        .padding(14).card()
    }
}

extension Who {
    var asScope: Scope { self == .me ? .me : .partner }
}

struct AddWishSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var owner: Who = .me
    @State private var price = ""
    @State private var link = ""
    @State private var note = ""
    @State private var priority = 1

    var body: some View {
        FormSheet(title: "Новая хотелка", canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            store.data.wishes.insert(Wish(title: title, owner: owner, price: price, link: link, note: note, priority: priority), at: 0)
            store.success()
        }) {
            Section {
                TextField("Что хочется?", text: $title)
                WhoPicker(who: $owner)
            }
            Section {
                TextField("Цена, ₽", text: $price).keyboardType(.numberPad)
                TextField("Ссылка", text: $link).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("Заметка (размер, цвет)", text: $note)
                Picker("Как сильно", selection: $priority) {
                    Text("★").tag(0); Text("★★").tag(1); Text("★★★").tag(2)
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Списки

struct ListsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        Screen {
            if store.data.lists.isEmpty {
                EmptyState(icon: "list.bullet.rectangle", title: "Общие списки",
                           text: "Покупки, фильмы, места, рецепты — всё, что хочется собрать вдвоём.",
                           action: "Создать список", onTap: { adding = true })
            }
            ForEach(store.data.lists) { l in
                NavigationLink { ListDetail(list: store.bind(\.lists, l)) } label: {
                    HStack(spacing: 14) {
                        Text(l.emoji).font(.title).frame(width: 44, height: 44)
                            .background(Pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.title).font(.body.weight(.semibold))
                            Text("\(l.items.filter { $0.done }.count) из \(l.items.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(14).card()
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Списки")
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddListSheet() }
    }
}

struct AddListSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var emoji = "🛒"
    private let presets: [(String, String)] = [("🛒", "Покупки"), ("🎬", "Фильмы"), ("📍", "Места"),
                                               ("🍝", "Рецепты"), ("📚", "Книги"), ("🧳", "В поездку")]

    var body: some View {
        FormSheet(title: "Новый список", canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            store.data.lists.append(UserList(title: title, emoji: emoji))
        }) {
            Section { TextField("Название", text: $title) }
            Section("Быстрый выбор") {
                ForEach(presets, id: \.1) { p in
                    Button { emoji = p.0; title = p.1 } label: { Text("\(p.0)  \(p.1)").foregroundStyle(.primary) }
                }
            }
        }
    }
}

struct ListDetail: View {
    @EnvironmentObject var store: Store
    @Binding var list: UserList
    @State private var text = ""

    var body: some View {
        Screen {
            HStack {
                TextField("Добавить пункт", text: $text).submitLabel(.done).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14).card()

            ForEach($list.items) { $e in
                HStack(spacing: 12) {
                    Button { e.done.toggle(); store.tap() } label: {
                        Image(systemName: e.done ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(e.done ? store.meColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    Text(e.title).strikethrough(e.done).foregroundStyle(e.done ? .secondary : .primary)
                    Spacer()
                    Button {
                        let id = e.id
                        list.items.removeAll { $0.id == id }
                    } label: { Image(systemName: "xmark").font(.caption).foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                }
                .padding(14).card()
            }
        }
        .navigationTitle("\(list.emoji) \(list.title)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Убрать выполненные", systemImage: "checkmark.circle") { list.items.removeAll { $0.done } }
                    Button("Удалить список", systemImage: "trash", role: .destructive) {
                        let id = list.id
                        store.data.lists.removeAll { $0.id == id }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        list.items.append(ListEntry(title: t))
        text = ""
        store.tap()
    }
}

// MARK: - Ещё

struct MoreView: View {
    @EnvironmentObject var store: Store

    private var answeredToday: Bool {
        let a = store.data.answers.first { $0.id == Date().dayKey }
        return !(a?.me.isEmpty ?? true)
    }

    var body: some View {
        Screen {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(store.more) { m in
                    NavigationLink { ModuleView(module: m) } label: {
                        tile(m.title, m.subtitle, m.art, m.hex, locked: m.locked, dot: m == .question && !answeredToday)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { SettingsView() } label: { tile("Настройки", "Вид, пара, защита", "⚙️", "AEB8C8", locked: false, dot: false) }
                    .buttonStyle(.plain)
            }
            .padding(.top, 4)

            NavigationLink { ReorderView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.up.arrow.down").font(.title3).frame(width: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Изменить порядок").font(.headline)
                        Text("что в нижней панели и как идёт этот список").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(16).card()
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .navigationTitle("Ещё")
        .pairToolbar()
    }

    private func tile(_ title: String, _ sub: String, _ art: String, _ hex: String, locked: Bool, dot: Bool) -> some View {
        let c = Color(hex: hex)
        return ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.primary).lineLimit(2).minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if dot { Circle().fill(store.partnerColor).frame(width: 10, height: 10) }
                    if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(sub).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(art).font(.system(size: 54)).shadow(color: c.opacity(0.6), radius: 10, y: 6).rotationEffect(.degrees(-6))
        }
        .padding(14).frame(height: 138)
        .background(LinearGradient(colors: [c.opacity(0.55), c.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: max(store.radius, 20), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: max(store.radius, 20), style: .continuous).stroke(.white.opacity(0.5), lineWidth: 1))
        .shadow(color: c.opacity(0.28), radius: 10, y: 6)
    }

}
