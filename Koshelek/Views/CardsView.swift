import SwiftUI
import SwiftData

struct CardTarget: Identifiable { let id = UUID(); let card: LoyaltyCard? }

struct CardsView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: [SortDescriptor(\LoyaltyCard.uses, order: .reverse), SortDescriptor(\LoyaltyCard.created)]) private var cards: [LoyaltyCard]
    @State private var show: LoyaltyCard?
    @State private var edit: CardTarget?
    @State private var query = ""

    var filtered: [LoyaltyCard] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? cards : cards.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Карты").font(.system(size: 32, weight: .bold, design: .rounded))
                        Spacer()
                        Button { edit = CardTarget(card: nil) } label: {
                            Image(systemName: "plus").font(.headline).frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    if cards.count > 6 {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Найти карту", text: $query)
                        }
                        .padding(10)
                        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    if cards.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard.and.123")
                                .font(.system(size: 34)).foregroundStyle(Theme.accent)
                                .frame(width: 72, height: 72).background(Theme.accent.opacity(0.1), in: Circle())
                            Text("Бонусные карты в одном месте").font(.title3.weight(.semibold))
                            Text("Наведите камеру на штрихкод карты — и на кассе её можно будет показать в одно касание, с яркостью на максимум.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Добавить первую карту") { edit = CardTarget(card: nil) }
                                .buttonStyle(.borderedProminent).padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(filtered) { c in
                                Button { c.uses += 1; try? ctx.save(); show = c } label: { CardTile(card: c) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button { edit = CardTarget(card: c) } label: { Label("Изменить", systemImage: "pencil") }
                                        Button(role: .destructive) { ctx.delete(c); try? ctx.save() } label: { Label("Удалить", systemImage: "trash") }
                                    }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Color(.systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $show) { c in CardShow(card: c, onEdit: { show = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { edit = CardTarget(card: c) } }) }
            .sheet(item: $edit) { t in CardForm(card: t.card) }
        }
    }
}

struct CardTile: View {
    let card: LoyaltyCard
    var body: some View {
        let color = Color(hex: card.hex)
        VStack(alignment: .leading) {
            Text(card.name).font(.headline).foregroundStyle(.white).lineLimit(2)
            Spacer()
            HStack {
                Text(String(card.code.suffix(4))).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Image(systemName: BarcodeFormat(rawValue: card.format)?.isSquare == true ? "qrcode" : "barcode")
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(14)
        .frame(height: 104)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

/// Карта на кассе: крупный штрихкод, яркость на максимум.
struct CardShow: View {
    let card: LoyaltyCard
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var oldBrightness: CGFloat = 0.5

    var body: some View {
        let color = Color(hex: card.hex)
        VStack(spacing: 24) {
            HStack {
                Button("Изменить", action: onEdit).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(.white.opacity(0.2), in: Circle())
                }
            }
            Spacer()
            Text(card.name).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
            BarcodeView(code: card.code, format: BarcodeFormat(rawValue: card.format) ?? .code128)
            if !card.note.isEmpty { Text(card.note).foregroundStyle(.white.opacity(0.85)) }
            Spacer()
            Text("Яркость увеличена, пока открыт код").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .padding(24)
        .background(color.ignoresSafeArea())
        .onAppear {
            oldBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear { UIScreen.main.brightness = oldBrightness }
    }
}

struct CardForm: View {
    let card: LoyaltyCard?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [LoyaltyCard]
    @State private var name = ""
    @State private var code = ""
    @State private var format: BarcodeFormat = .ean13
    @State private var hex = Theme.palette[0]
    @State private var note = ""
    @State private var scanning = false

    let stores = ["Пятёрочка", "Магнит", "Перекрёсток", "Лента", "Ашан", "ВкусВилл", "Мария-Ра", "Ярче", "Спортмастер",
                  "М.Видео", "DNS", "Леруа Мерлен", "Золотое Яблоко", "Летуаль", "Магнит Косметик", "Аптека"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        scanning = true
                    } label: {
                        Label(code.isEmpty ? "Сканировать штрихкод" : "Отсканировать заново", systemImage: "barcode.viewfinder")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(!BarcodeScanner.isAvailable)
                    if !BarcodeScanner.isAvailable {
                        Text("Камера недоступна — введите номер вручную.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Магазин") {
                    TextField("Название", text: $name)
                    if card == nil {
                        FlowLayout {
                            ForEach(stores, id: \.self) { s in Chip(title: s, selected: name == s) { name = s } }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    TextField("Номер карты", text: $code).keyboardType(.asciiCapable).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Picker("Тип кода", selection: $format) {
                        ForEach(BarcodeFormat.allCases) { f in Text(f.title).tag(f) }
                    }
                    TextField("Заметка (PIN, телефон)", text: $note)
                } footer: { Text("Тип кода определяется сам при сканировании. Если касса не читает — попробуйте другой тип.") }
                if !code.isEmpty {
                    Section("Так будет на кассе") {
                        BarcodeView(code: code, format: format).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                }
                Section("Цвет") {
                    HStack {
                        ForEach(Theme.palette, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 28, height: 28)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: hex == h ? 2.5 : 0))
                                .onTapGesture { hex = h }
                        }
                    }
                }
            }
            .navigationTitle(card == nil ? "Новая карта" : "Карта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let n = name.trimmingCharacters(in: .whitespaces), c = code.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, !c.isEmpty else { return }
                        if let k = card { k.name = n; k.code = c; k.format = format.rawValue; k.hex = hex; k.note = note }
                        else { let k = LoyaltyCard(name: n, code: c, format: format.rawValue, hex: hex); k.note = note; ctx.insert(k) }
                        try? ctx.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                ZStack(alignment: .top) {
                    BarcodeScanner { payload, f in
                        code = payload; format = f; scanning = false
                    }
                    .ignoresSafeArea()
                    HStack {
                        Text("Наведите на штрихкод карты").font(.headline).foregroundStyle(.white)
                        Spacer()
                        Button("Отмена") { scanning = false }.foregroundStyle(.white)
                    }
                    .padding()
                    .background(.black.opacity(0.4))
                }
            }
            .onAppear {
                if let k = card { name = k.name; code = k.code; format = BarcodeFormat(rawValue: k.format) ?? .code128; hex = k.hex; note = k.note }
                else { hex = Theme.palette[cards.count % Theme.palette.count] }
            }
        }
    }
}
