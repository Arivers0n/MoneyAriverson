import SwiftUI
import VisionKit
import Vision
import CoreImage.CIFilterBuiltins

// MARK: - Штрих-коды

enum BarcodeKind {
    static func name(_ k: String) -> String {
        switch k {
        case "qr": return "QR-код"
        case "pdf417": return "PDF417"
        case "aztec": return "Aztec"
        case "ean13": return "EAN-13"
        default: return "Штрих-код"
        }
    }

    static func kind(from s: VNBarcodeSymbology) -> String {
        switch s {
        case .qr, .microQR: return "qr"
        case .pdf417, .microPDF417: return "pdf417"
        case .aztec: return "aztec"
        case .ean13: return "ean13"
        default: return "code128"
        }
    }

    /// Рисует код нужного типа. Если тип не умеет рисовать CoreImage (EAN), используется Code 128.
    static func image(_ text: String, kind: String) -> UIImage? {
        let ctx = CIContext()
        let data = Data(text.utf8)
        var out: CIImage?
        switch kind {
        case "qr":
            let f = CIFilter.qrCodeGenerator(); f.message = data; f.correctionLevel = "M"; out = f.outputImage
        case "pdf417":
            let f = CIFilter.pdf417BarcodeGenerator(); f.message = data; out = f.outputImage
        case "aztec":
            let f = CIFilter.aztecCodeGenerator(); f.message = data; out = f.outputImage
        default:
            let f = CIFilter.code128BarcodeGenerator(); f.message = data; f.quietSpace = 8; out = f.outputImage
        }
        guard let img = out else { return nil }
        let isLinear = kind != "qr" && kind != "aztec"
        let scaled = img.transformed(by: CGAffineTransform(scaleX: isLinear ? 4 : 10, y: isLinear ? 4 : 10))
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

struct BarcodeView: View {
    let text: String
    let kind: String
    var body: some View {
        if let img = BarcodeKind.image(text, kind: kind) {
            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
        } else {
            Text(text).font(.title.monospaced())
        }
    }
}

// MARK: - Сканер

struct BarcodeScanner: UIViewControllerRepresentable {
    var onFound: (String, String) -> Void

    static var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()],
                                           qualityLevel: .accurate,
                                           recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false,
                                           isPinchToZoomEnabled: true,
                                           isGuidanceEnabled: true,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String, String) -> Void
        private var done = false
        init(onFound: @escaping (String, String) -> Void) { self.onFound = onFound }

        private func handle(_ item: RecognizedItem) {
            guard !done, case .barcode(let b) = item, let v = b.payloadStringValue, !v.isEmpty else { return }
            done = true
            onFound(v, BarcodeKind.kind(from: b.observation.symbology))
        }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            if let f = items.first { handle(f) }
        }
        func dataScanner(_ s: DataScannerViewController, didTapOn item: RecognizedItem) { handle(item) }
    }
}

// MARK: - Список карт

let cardBrands: [(name: String, hex: String)] = [
    ("Магнит", "E5322D"), ("Пятёрочка", "E4572E"), ("Перекрёсток", "1E9E57"), ("Лента", "2457C5"),
    ("ВкусВилл", "6BB43C"), ("Дикси", "F28C1A"), ("Ашан", "D6232A"), ("Аптека", "19A974"),
    ("Кофейня", "9A6B4B"), ("Одежда", "7C5CE0"), ("Техника", "2F3C7E"), ("Другая", "34C38F")
]

struct CardsView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var opened: SecureCard?

    var body: some View {
        Screen {
            if store.data.cards.isEmpty {
                EmptyState(icon: "barcode.viewfinder", title: "Карты магазинов",
                           text: "Наведите камеру на штрих-код карты — название и номер вводить не нужно. Покажете кассиру прямо с экрана.",
                           action: "Сканировать карту", onTap: { adding = true })
            }
            ForEach(store.data.cards) { c in
                Button { opened = c; store.tap() } label: { CardTile(card: c) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Удалить", role: .destructive) {
                            withAnimation { store.data.cards.removeAll { $0.id == c.id } }
                            Keychain.remove("card." + c.id.uuidString)
                        }
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            Text("Для скидочных и бонусных карт. Банковские карты здесь не храните. Удалить карту — долгое нажатие.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.data.cards.count)
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddCardSheet().environmentObject(store) }
        .fullScreenCover(item: $opened) { c in CardShowView(card: c).environmentObject(store) }
    }
}

struct CardTile: View {
    let card: SecureCard
    var body: some View {
        let c = Color(hex: card.hex)
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Theme.r(24), style: .continuous)
                .fill(LinearGradient(colors: [c, c.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.14)).frame(width: 180).offset(x: 150, y: -60)
            Circle().fill(.white.opacity(0.10)).frame(width: 120).offset(x: 220, y: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(card.name.prefix(1)).uppercased())
                        .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(c)
                        .frame(width: 40, height: 40).background(.white, in: Circle())
                    Spacer()
                    Image(systemName: "barcode").font(.title2).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text(card.name).font(.title3.weight(.bold)).foregroundStyle(.white)
                Text(masked(card.number)).font(.subheadline.monospaced()).foregroundStyle(.white.opacity(0.85))
            }
            .padding(18)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(24), style: .continuous))
        .shadow(color: c.opacity(0.35), radius: 14, y: 8)
    }

    private func masked(_ n: String) -> String {
        n.count > 8 ? "•••• " + n.suffix(4) : n
    }
}

// MARK: - Показ на кассе

struct CardShowView: View {
    @Environment(\.dismiss) private var dismiss
    let card: SecureCard
    @State private var oldBrightness: CGFloat = 0.5

    var body: some View {
        let c = Color(hex: card.hex)
        ZStack {
            LinearGradient(colors: [c, c.opacity(0.7)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 32)).foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
                Text(card.name).font(.largeTitle.weight(.bold)).foregroundStyle(.white)
                VStack(spacing: 14) {
                    BarcodeView(text: card.number, kind: card.symbology)
                        .frame(maxHeight: card.symbology == "qr" || card.symbology == "aztec" ? 260 : 130)
                    Text(card.number).font(.title3.monospaced()).foregroundStyle(.black)
                }
                .padding(24).frame(maxWidth: .infinity)
                .background(.white, in: RoundedRectangle(cornerRadius: Theme.r(28), style: .continuous))
                if !card.note.isEmpty { Text(card.note).font(.footnote).foregroundStyle(.white.opacity(0.9)) }
                Text("Яркость экрана увеличена").font(.caption).foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(20)
        }
        .onAppear {
            oldBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1
        }
        .onDisappear { UIScreen.main.brightness = oldBrightness }
    }
}

// MARK: - Добавление

struct AddCardSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var number = ""
    @State private var note = ""
    @State private var kind = "code128"
    @State private var hex = "34C38F"
    @State private var scanning = false
    @State private var manual = false
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if number.isEmpty {
                        scanBlock
                    } else {
                        VStack(spacing: 10) {
                            BarcodeView(text: number, kind: kind).frame(maxHeight: 110)
                            Text(number).font(.headline.monospaced())
                            Text(BarcodeKind.name(kind)).font(.caption).foregroundStyle(.secondary)
                            Button("Сканировать заново") { number = ""; scanning = true }.font(.footnote)
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .background(Pal.card, in: RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Магазин (по желанию)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(cardBrands, id: \.name) { b in
                                    Button {
                                        hex = b.hex
                                        if b.name != "Другая" { name = b.name }
                                    } label: {
                                        Text(b.name).font(.subheadline.weight(.semibold))
                                            .padding(.horizontal, 14).padding(.vertical, 9)
                                            .foregroundStyle(hex == b.hex ? .white : .primary)
                                            .background(hex == b.hex ? Color(hex: b.hex) : Pal.card, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        TextField("Своё название", text: $name)
                            .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                        TextField("Заметка (скидка 5%, чья карта)", text: $note)
                            .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    }

                    Button {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        store.data.cards.append(SecureCard(name: n.isEmpty ? "Карта" : n, number: number, note: note,
                                                           symbology: kind, hex: hex))
                        store.success()
                        dismiss()
                    } label: { Text("Сохранить").bigButton().opacity(number.isEmpty ? 0.4 : 1) }
                        .disabled(number.isEmpty)
                }
                .padding(16)
            }
            .background(ThemeBackground())
            .navigationTitle("Новая карта")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .fullScreenCover(isPresented: $scanning) {
                ZStack(alignment: .topTrailing) {
                    BarcodeScanner { value, k in
                        number = value; kind = k; scanning = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    .ignoresSafeArea()
                    Button { scanning = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 34)).foregroundStyle(.white).padding(20)
                    }
                }
            }
        }
    }

    private var scanBlock: some View {
        VStack(spacing: 14) {
            Image(systemName: "barcode.viewfinder").font(.system(size: 64)).foregroundStyle(store.meColor)
            if BarcodeScanner.supported {
                Text("Наведите камеру на штрих-код карты").font(.headline).multilineTextAlignment(.center)
                Button { scanning = true } label: { Text("Открыть камеру").bigButton() }
            } else {
                Text("Сканер недоступен на этом устройстве — введите номер вручную.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button(manual ? "Скрыть ввод" : "Ввести номер вручную") { manual.toggle() }.font(.footnote)
            if manual {
                HStack {
                    TextField("Номер под штрих-кодом", text: $typed)
                        .keyboardType(.asciiCapable)
                        .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    Button("Готово") {
                        let t = typed.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { number = t; kind = "code128" }
                    }
                    .font(.headline)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(Pal.card, in: RoundedRectangle(cornerRadius: Theme.r(22), style: .continuous))
    }
}
