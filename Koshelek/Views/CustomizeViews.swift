import SwiftUI
import UIKit

// MARK: - Главный экран: порядок блоков и кнопки

struct CustomizeView: View {
    @ObservedObject private var layout = HomeLayout.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order, id: \.self) { id in
                        if let b = layout.block(id) {
                            HStack(spacing: 12) {
                                CategoryTile(symbol: b.symbol, color: Theme.accent, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.title)
                                    Text(b.hint).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onMove { layout.order.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { idx in layout.order.remove(atOffsets: idx) }
                } header: { Text("На экране") } footer: {
                    Text("Перетаскивайте за ≡, чтобы поменять порядок. Смахните влево, чтобы убрать.")
                }
                if !layout.hidden.isEmpty {
                    Section("Можно добавить") {
                        ForEach(layout.hidden) { b in
                            Button { layout.add(b.id) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.inc)
                                    CategoryTile(symbol: b.symbol, color: .secondary, size: 34)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(b.title).foregroundStyle(.primary)
                                        Text(b.hint).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section {
                    ForEach(HomeLayout.topButtons) { b in
                        let on = layout.top.contains(b.id)
                        Button { layout.toggleTop(b.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: b.symbol).frame(width: 28).foregroundStyle(Theme.accent)
                                Text(b.title).foregroundStyle(.primary)
                                Spacer()
                                if let i = layout.top.firstIndex(of: b.id) {
                                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(Theme.onAccent)
                                        .frame(width: 22, height: 22).background(Theme.accent, in: Circle())
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .disabled(!on && layout.top.count >= HomeLayout.maxTop)
                    }
                } header: { Text("Кнопки сверху") } footer: {
                    Text("До \(HomeLayout.maxTop) кнопок. Порядок — в порядке выбора.")
                }
                Section {
                    Toggle(isOn: $layout.showScan) { Label("Скан чека", systemImage: "viewfinder") }
                    Toggle(isOn: .constant(true)) { Label("Микрофон", systemImage: "mic") }.disabled(true)
                    Toggle(isOn: $layout.showPlus) { Label("Добавить вручную", systemImage: "plus") }
                } header: { Text("Кнопки снизу") }
                Section {
                    Button("Вернуть как было", role: .destructive) { withAnimation { layout.reset() } }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Главный экран")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

// MARK: - Оформление

struct AppearanceView: View {
    @ObservedObject private var ap = Appearance.shared

    var body: some View {
        Form {
            Section {
                ThemePreview()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section("Тема") {
                Picker("Тема", selection: $ap.scheme) {
                    Text("Как в системе").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            Section("Акцентный цвет") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                    ForEach(Appearance.accents) { a in
                        Button { withAnimation { ap.accent = a.id } } label: {
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(Color.dynamic(a.light, a.dark))
                                    .frame(width: 40, height: 40)
                                    .overlay(Circle().strokeBorder(Color.primary, lineWidth: ap.accent == a.id ? 3 : 0).padding(-4))
                                Text(a.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Фон") {
                Picker("Фон", selection: $ap.background) {
                    Text("Обычный").tag("grouped")
                    Text("Чистый чёрный/белый").tag("pure")
                    Text("С цветным свечением").tag("tint")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Карточки") {
                Picker("Карточки", selection: $ap.cards) {
                    Text("Заливка").tag("filled")
                    Text("Стекло").tag("glass")
                    Text("Контур").tag("outline")
                }
                .pickerStyle(.segmented)
            }
            Section("Шрифт") {
                Picker("Шрифт", selection: $ap.font) {
                    Text("Обычный").tag("default")
                    Text("Округлый").tag("rounded")
                    Text("С засечками").tag("serif")
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker("Крупная цифра", selection: $ap.bigNumber) {
                    Text("Остаток").tag("net")
                    Text("Расходы").tag("exp")
                    Text("Доходы").tag("inc")
                }
                Toggle("Компактный вид", isOn: $ap.compact)
                Toggle("Скрывать суммы на главном", isOn: $ap.hideAmounts)
            } header: { Text("Главный экран") } footer: {
                Text("Скрытые суммы показываются по нажатию на цифру — удобно, если открываете приложение при людях.")
            }
            Section {
                Button("Сбросить оформление", role: .destructive) { withAnimation { ap.reset() } }
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Живой пример того, как будет выглядеть экран.
struct ThemePreview: View {
    @ObservedObject private var ap = Appearance.shared
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Capsule().fill(Theme.inc.opacity(0.25)).frame(width: 90, height: 28)
                Spacer()
                Capsule().fill(Color.primary.opacity(0.08)).frame(width: 110, height: 28)
            }
            Text(ap.bigNumber == "exp" ? "13 256 ₽" : (ap.bigNumber == "inc" ? "79 000 ₽" : "65 744 ₽"))
                .font(.system(size: 34, weight: .bold, design: ap.fontDesign))
            HStack(spacing: 8) {
                Text("Инсайты").font(.system(.footnote, design: ap.fontDesign).weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6).glass(Capsule())
            }
            ForEach(Array(Catalog.expense.prefix(2))) { c in
                HStack(spacing: 10) {
                    CategoryTile(symbol: c.symbol, color: c.color, size: 34)
                    Text(c.name).font(.system(.subheadline, design: ap.fontDesign).weight(.medium))
                    Spacer()
                    Text("-250 ₽").font(.system(.subheadline, design: ap.fontDesign).weight(.medium))
                }
                .padding(10)
                .cardBG(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 10) {
                Circle().fill(Color.primary.opacity(0.1)).frame(width: 30, height: 30)
                Circle().fill(Theme.accent).frame(width: 40, height: 40)
                    .overlay(Image(systemName: "mic").foregroundStyle(Theme.onAccent))
                Circle().fill(Color.primary.opacity(0.1)).frame(width: 30, height: 30)
            }
        }
        .padding(16)
        .background(Backdrop().clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .padding(.vertical, 4)
        .id(ap.version)
    }
}

// MARK: - Категории

struct CatEditTarget: Identifiable { let id = UUID(); let cat: Category?; let kind: TxKind }

struct CategoriesView: View {
    @ObservedObject private var prefs = CategoryPrefs.shared
    @State private var kind: TxKind = .exp
    @State private var edit: CatEditTarget?

    var body: some View {
        let all = Catalog.all.filter { $0.kind == kind }
        List {
            Section {
                Picker("", selection: $kind) {
                    Text("Расходы").tag(TxKind.exp)
                    Text("Доходы").tag(TxKind.inc)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(all) { c in
                    let hidden = prefs.hidden.contains(c.id)
                    HStack(spacing: 12) {
                        Button { edit = CatEditTarget(cat: c, kind: kind) } label: {
                            HStack(spacing: 12) {
                                CategoryTile(symbol: c.symbol, color: c.color, size: 38)
                                Text(c.name).foregroundStyle(hidden ? Color.secondary : Color.primary)
                                if prefs.custom.contains(where: { $0.id == c.id }) {
                                    Text("своя").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accent.opacity(0.14), in: Capsule())
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        if !Catalog.locked.contains(c.id) {
                            Button { withAnimation { prefs.toggleHidden(c.id) } } label: {
                                Image(systemName: hidden ? "eye.slash" : "eye").foregroundStyle(hidden ? Color.secondary : Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .opacity(hidden ? 0.55 : 1)
                }
            } footer: {
                Text("Нажмите на категорию, чтобы сменить название, иконку или цвет. Глаз — скрыть из выбора (старые операции останутся).")
            }
            Section {
                Button { edit = CatEditTarget(cat: nil, kind: kind) } label: {
                    Label("Новая категория", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Категории")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $edit) { t in CategoryForm(cat: t.cat, kind: t.kind) }
    }
}

struct CategoryForm: View {
    let cat: Category?
    let kind: TxKind
    @ObservedObject private var prefs = CategoryPrefs.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = "star.fill"
    @State private var hex = "2B47C9"
    @State private var confirmDelete = false

    var isCustom: Bool { cat.map { c in prefs.custom.contains { $0.id == c.id } } ?? true }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CategoryTile(symbol: symbol, color: Color(hex: hex), size: 56)
                        TextField("Название", text: $name).font(.title3.weight(.medium))
                    }
                    .padding(.vertical, 4)
                }
                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(CategoryPrefs.symbolChoices, id: \.self) { s in
                            Image(systemName: s)
                                .font(.body)
                                .frame(width: 42, height: 42)
                                .foregroundStyle(symbol == s ? Color.white : Color(hex: hex))
                                .background(symbol == s ? Color(hex: hex) : Color(hex: hex).opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { symbol = s }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9), spacing: 12) {
                        ForEach(CategoryPrefs.colorChoices, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == h ? 2.5 : 0).padding(-3))
                                .onTapGesture { hex = h }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if cat != nil {
                    Section {
                        if isCustom {
                            Button("Удалить категорию", role: .destructive) { confirmDelete = true }
                        } else {
                            Button("Вернуть как было") {
                                prefs.setOverride(cat!.id, nil)
                                dismiss()
                            }
                        }
                    } footer: {
                        if isCustom { Text("Операции этой категории останутся и будут показаны как «Другое».") }
                    }
                }
            }
            .navigationTitle(cat == nil ? "Новая категория" : "Категория")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Удалить категорию «\(name)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { if let c = cat { prefs.deleteCustom(c.id) }; dismiss() }
            }
            .onAppear {
                if let c = cat { name = c.name; symbol = c.symbol; hex = c.hex }
                else { hex = CategoryPrefs.colorChoices.randomElement() ?? hex }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let c = cat {
            if isCustom {
                prefs.save(CustomCat(id: c.id, name: n, hex: hex, symbol: symbol, kind: kind == .inc ? "inc" : "exp"))
            } else {
                prefs.setOverride(c.id, CatOverride(name: n, hex: hex, symbol: symbol))
            }
        } else {
            prefs.save(CustomCat(id: "c_" + UUID().uuidString.prefix(8).lowercased(), name: n, hex: hex, symbol: symbol, kind: kind == .inc ? "inc" : "exp"))
        }
        dismiss()
    }
}

// MARK: - Иконка приложения

struct IconPickerView: View {
    @State private var current = UIApplication.shared.alternateIconName ?? ""
    @State private var err: String?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 22) {
                ForEach(AppIcons.all) { icon in
                    Button { set(icon.id) } label: {
                        VStack(spacing: 8) {
                            Image(icon.preview)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(Theme.accent, lineWidth: current == icon.id ? 3 : 0).padding(-5))
                            Text(icon.title).font(.footnote.weight(current == icon.id ? .semibold : .regular))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            if let err { Text(err).font(.footnote).foregroundStyle(Theme.exp).padding() }
            Text("iOS покажет короткое уведомление о смене иконки — это нормально.")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
        }
        .navigationTitle("Иконка приложения")
        .navigationBarTitleDisplayMode(.inline)
        .background(Backdrop())
    }

    private func set(_ id: String) {
        guard UIApplication.shared.supportsAlternateIcons else { err = "Это устройство не поддерживает смену иконки."; return }
        UIApplication.shared.setAlternateIconName(id.isEmpty ? nil : id) { e in
            DispatchQueue.main.async {
                if let e { err = "Не получилось сменить иконку: \(e.localizedDescription)" }
                else { current = id; err = nil }
            }
        }
    }
}
