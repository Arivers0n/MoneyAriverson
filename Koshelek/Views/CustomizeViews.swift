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

/// «Оформление»: вкладки Тема · Иконки · Экран, живое превью и готовые темы.
struct AppearanceView: View {
    @ObservedObject private var ap = Appearance.shared
    @State var tab: Int = 0
    @State private var naming = false
    @State private var presetName = ""
    @Namespace private var ns

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                tabs
                switch tab {
                case 1: IconGrid()
                case 2: screenTab
                default: themeTab
                }
            }
            .padding(16)
            .padding(.bottom, 30)
            .animation(Motion.snappy, value: tab)
        }
        .scrollIndicators(.hidden)
        .background(Backdrop())
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Название темы", isPresented: $naming) {
            TextField("Моя тема", text: $presetName)
            Button("Сохранить") {
                let n = presetName.trimmingCharacters(in: .whitespaces)
                ap.saveCurrent(as: n.isEmpty ? "Моя тема" : n)
                Haptic.success()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Вкладки

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Array(["Тема", "Иконки", "Экран"].enumerated()), id: \.offset) { i, t in
                Button {
                    Haptic.select()
                    withAnimation(Motion.snappy) { tab = i }
                } label: {
                    Text(t)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tab == i ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background {
                            if tab == i {
                                Capsule().fill(Color.primary.opacity(0.1)).matchedGeometryEffect(id: "tab", in: ns)
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

    // MARK: Тема

    private var themeTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            ThemePreview()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Темы").font(.headline)
                    Spacer()
                    Button { presetName = ""; naming = true } label: {
                        Label("Сохранить текущую", systemImage: "plus").font(.subheadline.weight(.semibold))
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(ThemePreset.builtIns + ap.customPresets) { p in
                            PresetTile(preset: p, selected: ap.isCurrent(p))
                                .onTapGesture {
                                    Haptic.select()
                                    withAnimation(Motion.spring) { ap.apply(p) }
                                }
                                .contextMenu {
                                    if !p.builtIn {
                                        Button(role: .destructive) { ap.customPresets.removeAll { $0.id == p.id } } label: {
                                            Label("Удалить тему", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }

            group("Режим") {
                Picker("Режим", selection: $ap.scheme.animation(Motion.spring)) {
                    Text("Тёмная").tag("dark")
                    Text("Светлая").tag("light")
                    Text("Как в системе").tag("system")
                }
                .pickerStyle(.segmented)
            }

            group("Акцентный цвет") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                    ForEach(Appearance.accents) { a in
                        Button {
                            Haptic.select()
                            withAnimation(Motion.spring) { ap.accent = a.id }
                        } label: {
                            Circle()
                                .fill(Color.dynamic(a.light, a.dark).gradient)
                                .frame(width: 44, height: 44)
                                .overlay {
                                    if ap.accent == a.id {
                                        Image(systemName: "checkmark").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                        }
                        .buttonStyle(Pressable(scale: 0.9))
                        .accessibilityLabel(a.name)
                    }
                }
            }

            group("Фон") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(Appearance.backgrounds) { b in
                        Button {
                            Haptic.select()
                            withAnimation(Motion.spring) { ap.background = b.id }
                        } label: {
                            VStack(spacing: 6) {
                                BackdropLayer(style: b.id, accent: ap.accentColor)
                                    .frame(height: 74)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(ap.background == b.id ? ap.accentColor : Color.primary.opacity(0.1),
                                                      lineWidth: ap.background == b.id ? 2.5 : 1))
                                Text(b.name).font(.caption.weight(.medium)).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(Pressable(scale: 0.96))
                    }
                }
            }

            group("Карточки") {
                Picker("Карточки", selection: $ap.cards.animation(Motion.spring)) {
                    Text("Сплошные").tag("filled")
                    Text("Стекло").tag("glass")
                    Text("Контур").tag("outline")
                }
                .pickerStyle(.segmented)
            }

            group("Шрифт") {
                VStack(spacing: 8) {
                    ForEach([("default", "Системный", Font.Design.default), ("rounded", "Скруглённый", .rounded), ("serif", "С засечками", .serif)], id: \.0) { f in
                        Button {
                            Haptic.select()
                            withAnimation(Motion.spring) { ap.font = f.0 }
                        } label: {
                            HStack {
                                Text(f.1).font(.body.weight(.medium))
                                Spacer()
                                Text("65 744 ₽").font(.system(.headline, design: f.2)).foregroundStyle(.secondary)
                                Image(systemName: ap.font == f.0 ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(ap.font == f.0 ? ap.accentColor : Color.secondary)
                            }
                            .fontDesign(f.2)
                            .padding(.horizontal, 14).frame(minHeight: 50)
                            .cardBG(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(Pressable(scale: 0.98))
                        .foregroundStyle(.primary)
                    }
                }
            }

            Button(role: .destructive) { withAnimation(Motion.spring) { ap.reset() } } label: {
                Text("Сбросить оформление").frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
    }

    // MARK: Экран

    private var screenTab: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("Крупная цифра на главном") {
                Picker("Крупная цифра", selection: $ap.bigNumber) {
                    Text("Остаток").tag("net")
                    Text("Расходы").tag("exp")
                    Text("Доходы").tag("inc")
                }
                .pickerStyle(.segmented)
            }
            VStack(spacing: 0) {
                toggleRow("Компактный вид", "Меньше отступов — больше операций на экране", $ap.compact)
                Divider().padding(.leading, 14)
                toggleRow("Скрывать суммы", "Цифры появляются по нажатию — удобно при людях", $ap.hideAmounts)
                Divider().padding(.leading, 14)
                toggleRow("Показывать копейки", "12 345,67 ₽ вместо 12 346 ₽", $ap.showKopecks)
                Divider().padding(.leading, 14)
                toggleRow("Всегда показывать доходы", "Даже если в месяце их ещё нет", $ap.alwaysIncome)
            }
            .cardBG(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(spacing: 0) {
                NavigationLink { CustomizeView() } label: { linkRow("Главный экран", "Блоки, порядок, кнопки сверху и снизу", "square.grid.2x2.fill") }
                Divider().padding(.leading, 56)
                NavigationLink { CategoriesView() } label: { linkRow("Категории", "Свои категории, цвета и значки", "tag.fill") }
            }
            .cardBG(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Совет: удержите палец на пустом месте главного экрана — блоки можно убирать и добавлять прямо там.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func toggleRow(_ title: String, _ hint: String, _ v: Binding<Bool>) -> some View {
        Toggle(isOn: v.animation(Motion.spring)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(ap.accentColor)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func linkRow(_ title: String, _ hint: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 30, height: 30).background(ap.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }
}

/// Миниатюра темы: фон, акцент и полоска «карточки».
private struct PresetTile: View {
    let preset: ThemePreset
    let selected: Bool
    var body: some View {
        let info = Appearance.accents.first { $0.id == preset.accent } ?? Appearance.accents[0]
        let accent = Color.dynamic(info.light, info.dark)
        let dark: ColorScheme = preset.scheme == "light" ? .light : .dark
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                BackdropLayer(style: preset.background, accent: accent)
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.18)).frame(width: 38, height: 10)
                }
                .padding(10)
            }
            .environment(\.colorScheme, dark)
            .frame(width: 108, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.body).foregroundStyle(.white, accent).padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text(preset.name).font(.caption.weight(.semibold)).lineLimit(1)
        }
        .frame(width: 108)
        .contentShape(Rectangle())
    }
}

/// Сетка иконок приложения: 4 в ряд, отметка выбранной.
struct IconGrid: View {
    @State private var current = UIApplication.shared.alternateIconName ?? ""
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Значок приложения").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 18) {
                ForEach(AppIcons.all) { icon in
                    Button { set(icon.id) } label: {
                        VStack(spacing: 6) {
                            Image(icon.preview)
                                .resizable()
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                                .overlay(alignment: .topTrailing) {
                                    if current == icon.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(.white, Theme.accent)
                                            .background(Circle().fill(.white).padding(2))
                                            .offset(x: 6, y: -6)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .scaleEffect(current == icon.id && Motion.moves ? 1.04 : 1)
                            Text(icon.title).font(.caption2.weight(current == icon.id ? .semibold : .regular))
                                .foregroundStyle(current == icon.id ? Color.primary : Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(Pressable(scale: 0.92))
                }
            }
            .padding(14)
            .cardBG(RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let err { Text(err).font(.footnote).foregroundStyle(Theme.exp) }
            Text("iOS покажет короткое уведомление о смене значка — это нормально.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func set(_ id: String) {
        guard id != current else { return }
        guard UIApplication.shared.supportsAlternateIcons else { err = "Это устройство не поддерживает смену значка."; return }
        Haptic.select()
        UIApplication.shared.setAlternateIconName(id.isEmpty ? nil : id) { e in
            DispatchQueue.main.async {
                if let e { err = "Не получилось сменить значок: \(e.localizedDescription)"; Haptic.warning() }
                else { withAnimation(Motion.spring) { current = id }; err = nil; Haptic.success() }
            }
        }
    }
}

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
    var body: some View { AppearanceView(tab: 1) }
}
