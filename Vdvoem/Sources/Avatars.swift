import SwiftUI
import PhotosUI

// MARK: - Аватарки: своё фото у каждого, синхронизируется с партнёром

struct AvatarItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var who: Who
    var jpeg: Data
    var date = Date()
}

enum AvatarCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ item: AvatarItem) -> UIImage? {
        let key = (item.id.uuidString + "\(item.jpeg.count)") as NSString
        if let c = cache.object(forKey: key) { return c }
        guard let img = UIImage(data: item.jpeg) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// Квадрат по центру, 360×360, лёгкий JPEG — чтобы быстро уходило на сервер.
    static func encode(_ img: UIImage) -> Data? {
        let side: CGFloat = 360
        let s = min(img.size.width, img.size.height)
        guard s > 0 else { return nil }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt)
        let out = renderer.image { _ in
            let k = side / s
            let w = img.size.width * k
            let h = img.size.height * k
            img.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return out.jpegData(compressionQuality: 0.78)
    }
}

extension Store {
    func avatarItem(_ w: Who) -> AvatarItem? {
        data.avatars.filter { $0.who == w }.max { $0.date < $1.date }
    }

    func setAvatar(_ w: Who, image: UIImage?) {
        var list = data.avatars.filter { $0.who != w }
        if let image, let d = AvatarCache.encode(image) { list.append(AvatarItem(who: w, jpeg: d)) }
        data.avatars = list
        Toasts.shared.show(image == nil ? "Фото убрано" : "Фото обновлено", symbol: "person.crop.circle.badge.checkmark")
    }
}

/// Круглое лицо: фото, если есть, иначе цветной круг с первой буквой имени.
struct AvatarFace: View {
    @EnvironmentObject var store: Store
    let who: Who
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let item = store.avatarItem(who), let img = AvatarCache.image(item) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [store.color(who), store.color(who).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(String(store.name(who).prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Строка в настройках: превью, выбрать фото, убрать фото.
struct AvatarPickerRow: View {
    @EnvironmentObject var store: Store
    let who: Who
    @State private var picked: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        HStack(spacing: 14) {
            AvatarFace(who: who, size: 56)
                .overlay(Circle().stroke(store.color(who), lineWidth: 2).padding(-3))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.name(who)).font(.subheadline.weight(.semibold))
                Text(store.avatarItem(who) == nil ? "Без фото" : "Фото установлено").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if loading { ProgressView() }
            PhotosPicker(selection: $picked, matching: .images) {
                Text(store.avatarItem(who) == nil ? "Выбрать" : "Заменить")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Pal.field, in: Capsule())
            }
            if store.avatarItem(who) != nil {
                Button { withAnimation(Motion.spring) { store.setAvatar(who, image: nil) } } label: {
                    Image(systemName: "trash").font(.footnote.weight(.semibold)).foregroundStyle(.red)
                        .padding(8).background(Pal.field, in: Circle())
                }
            }
        }
        .onChange(of: picked) { _, item in load(item) }
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loading = true
        Task {
            defer { loading = false; picked = nil }
            if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                withAnimation(Motion.spring) { store.setAvatar(who, image: img) }
            }
        }
    }
}
