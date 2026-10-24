import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import VisionKit
import Vision

// MARK: - Отрисовка штрихкодов

enum BarcodeFormat: String, CaseIterable, Identifiable {
    case ean13, ean8, code128, qr, pdf417, aztec, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ean13: return "EAN-13"
        case .ean8: return "EAN-8"
        case .code128: return "Code 128"
        case .qr: return "QR-код"
        case .pdf417: return "PDF417"
        case .aztec: return "Aztec"
        case .none: return "Только номер"
        }
    }
    var isSquare: Bool { self == .qr || self == .aztec }
}

enum EAN {
    static let L = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    static let G = ["0100111", "0110011", "0011011", "0100001", "0011101", "0111001", "0000101", "0010001", "0001001", "0010111"]
    static let R = ["1110010", "1100110", "1101100", "1000010", "1011100", "1001110", "1010000", "1000100", "1001000", "1110100"]
    static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    static func checkDigit(_ d: [Int]) -> Int {
        // веса справа налево: 3,1,3,1…
        var sum = 0
        for (i, v) in d.reversed().enumerated() { sum += v * (i % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10
    }

    /// Строка из 0/1 для EAN-13 или EAN-8, либо nil, если код не подходит.
    static func bits(_ code: String) -> String? {
        var d = code.compactMap { $0.wholeNumberValue }
        guard d.count == code.count else { return nil }
        if d.count == 12 || d.count == 7 { d.append(checkDigit(d)) }
        if d.count == 13 {
            let p = Array(parity[d[0]])
            var s = "101"
            for i in 1...6 { s += p[i - 1] == "L" ? L[d[i]] : G[d[i]] }
            s += "01010"
            for i in 7...12 { s += R[d[i]] }
            return s + "101"
        }
        if d.count == 8 {
            var s = "101"
            for i in 0...3 { s += L[d[i]] }
            s += "01010"
            for i in 4...7 { s += R[d[i]] }
            return s + "101"
        }
        return nil
    }
}

struct BarsView: View {
    let bits: String
    var body: some View {
        Canvas { ctx, size in
            let arr = Array(bits)
            let w = size.width / CGFloat(arr.count)
            for (i, b) in arr.enumerated() where b == "1" {
                ctx.fill(Path(CGRect(x: CGFloat(i) * w, y: 0, width: w + 0.4, height: size.height)), with: .color(.black))
            }
        }
    }
}

enum CIBarcode {
    static let context = CIContext()
    static func image(_ code: String, format: BarcodeFormat) -> UIImage? {
        let data = Data(code.utf8)
        let out: CIImage?
        switch format {
        case .qr:
            let f = CIFilter.qrCodeGenerator(); f.message = data; f.correctionLevel = "M"; out = f.outputImage
        case .pdf417:
            let f = CIFilter.pdf417BarcodeGenerator(); f.message = data; out = f.outputImage
        case .aztec:
            let f = CIFilter.aztecCodeGenerator(); f.message = data; out = f.outputImage
        default:
            let f = CIFilter.code128BarcodeGenerator(); f.message = Data(code.utf8); f.quietSpace = 0; out = f.outputImage
        }
        guard let img = out?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Штрихкод на белом фоне, готовый для сканера на кассе.
struct BarcodeView: View {
    let code: String
    let format: BarcodeFormat
    var body: some View {
        VStack(spacing: 8) {
            Group {
                if (format == .ean13 || format == .ean8), let b = EAN.bits(code) {
                    BarsView(bits: b).frame(height: 110)
                } else if format == .none {
                    EmptyView()
                } else if let img = CIBarcode.image(code, format: format) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: format.isSquare ? 230 : 120)
                } else {
                    Text("Не удалось нарисовать код").foregroundStyle(.gray)
                }
            }
            Text(code.isEmpty ? "—" : code)
                .font(.system(format == .none ? .largeTitle : .title3, design: .monospaced).weight(.semibold))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Сканер штрихкода камерой

struct BarcodeScanner: UIViewControllerRepresentable {
    let onFound: (String, BarcodeFormat) -> Void

    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(onFound: onFound) }

    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String, BarcodeFormat) -> Void
        var done = false
        init(onFound: @escaping (String, BarcodeFormat) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let b) = item, let payload = b.payloadStringValue, !payload.isEmpty {
                    done = true
                    scanner.stopScanning()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onFound(payload, Self.format(b.observation.symbology))
                    return
                }
            }
        }

        static func format(_ s: VNBarcodeSymbology) -> BarcodeFormat {
            switch s {
            case .ean13: return .ean13
            case .ean8: return .ean8
            case .qr: return .qr
            case .pdf417: return .pdf417
            case .aztec: return .aztec
            default: return .code128
            }
        }
    }
}
