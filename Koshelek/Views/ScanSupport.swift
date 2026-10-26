import SwiftUI
import PhotosUI
import UIKit
import VisionKit

/// Камера-сканер документов: сама находит края чека, выравнивает и убирает фон.
struct DocumentScanner: UIViewControllerRepresentable {
    let onImages: ([UIImage]) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ p: DocumentScanner) { parent = p }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let imgs = (0..<min(scan.pageCount, 5)).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.onImages(imgs)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }
    }
}

/// Запасной вариант — обычная камера (если сканер документов недоступен).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }

    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Шторка «Добавить по фото»: две большие плитки вместо системного меню.
private struct ScanSourceSheet: View {
    let title: String
    let onCamera: () -> Void
    let onPhotos: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 38, height: 5).padding(.top, 8)
            VStack(spacing: 6) {
                Text(title).font(.title3.weight(.bold))
                Text("Чек, скриншот из банка или график платежей — суммы и категории найдутся сами.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            HStack(spacing: 12) {
                tile("Сканировать", "Камера сама найдёт края чека", "doc.viewfinder", Theme.accent) { pick(onCamera) }
                tile("Из Фото", "Скриншоты и снимки, до 5 штук", "photo.on.rectangle.angled", Color(hex: "7B4FD0")) { pick(onPhotos) }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(.regularMaterial)
    }

    private func pick(_ action: @escaping () -> Void) {
        Haptic.tap()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { action() }
    }

    private func tile(_ title: String, _ hint: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Spacer(minLength: 0)
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .padding(16)
            .background(Color(.secondarySystemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(Pressable(scale: 0.96))
    }
}

/// Выбор источника и выдача готовых JPEG.
struct ScanFlow: ViewModifier {
    @Binding var isPresented: Bool
    var title = "Добавить по фото"
    let onImages: ([Data]) -> Void

    @State private var showScanner = false
    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var picks: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                ScanSourceSheet(title: title) {
                    if VNDocumentCameraViewController.isSupported { showScanner = true } else { showCamera = true }
                } onPhotos: { showPhotos = true }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { imgs in
                    let out = imgs.compactMap { ImagePrep.jpeg($0) }
                    if !out.isEmpty { onImages(out) }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    if let d = ImagePrep.jpeg(img) { onImages([d]) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $picks, maxSelectionCount: 5, matching: .images)
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    var out: [Data] = []
                    for it in items {
                        if let d = try? await it.loadTransferable(type: Data.self), let j = ImagePrep.jpeg(d) { out.append(j) }
                    }
                    picks = []
                    if !out.isEmpty { onImages(out) }
                }
            }
    }
}

extension View {
    func scanFlow(isPresented: Binding<Bool>, title: String = "Добавить по фото", onImages: @escaping ([Data]) -> Void) -> some View {
        modifier(ScanFlow(isPresented: isPresented, title: title, onImages: onImages))
    }
}

/// Экран обработки: снимок, по которому бежит луч сканера, и подпись.
struct ScanProcessingView: View {
    let images: [Data]
    var text = "Claude читает чек…"
    @State private var sweep = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).overlay(Color.black.opacity(0.25)).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    ForEach(Array(images.prefix(3).enumerated().reversed()), id: \.offset) { i, d in
                        if let img = UIImage(data: d) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 200, height: 270)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .rotationEffect(.degrees(Double(i) * 5))
                                .offset(x: CGFloat(i) * 10, y: CGFloat(i) * -6)
                                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
                        }
                    }
                    // луч сканера
                    if Motion.enabled {
                        LinearGradient(colors: [.clear, Theme.accent.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(width: 200, height: 70)
                            .offset(y: sweep ? 120 : -120)
                            .blendMode(.plusLighter)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .frame(width: 200, height: 270)
                            .clipped()
                    }
                }
                .frame(width: 220, height: 290)
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(text).font(.headline).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color.black.opacity(0.7), in: Capsule())
            }
            .scaleEffect(appeared || !Motion.moves ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(Motion.entrance(0.4)) { appeared = true }
            if Motion.enabled {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { sweep = true }
            }
        }
    }
}
