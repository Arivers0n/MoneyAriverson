import SwiftUI
import PhotosUI
import UIKit

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

/// Выбор «Сфотографировать / Из Фото» и выдача готовых JPEG.
struct ScanFlow: ViewModifier {
    @Binding var isPresented: Bool
    var title = "Скан чека или скриншота"
    let onImages: ([Data]) -> Void

    @State private var showCamera = false
    @State private var showPhotos = false
    @State private var picks: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
                Button("Сфотографировать") { showCamera = true }
                Button("Выбрать из Фото") { showPhotos = true }
                Button("Отмена", role: .cancel) {}
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
    func scanFlow(isPresented: Binding<Bool>, title: String = "Скан чека или скриншота", onImages: @escaping ([Data]) -> Void) -> some View {
        modifier(ScanFlow(isPresented: isPresented, title: title, onImages: onImages))
    }
}
