import SwiftUI
import PhotosUI

// MARK: - Загрузка и показ фото

enum ImageCache {
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 120
        return c
    }()
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 30_000_000, diskCapacity: 300_000_000)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    static func url(media: String, file: String, thumb: String?) -> URL? {
        var s = "\(VDConfig.base)/api/files/vd_media/\(media)/\(file)"
        if let t = thumb { s += "?thumb=\(t)" }
        return URL(string: s)
    }
}

/// Картинка с сервера: кэш в памяти и на диске, плавное появление.
struct RemoteImage: View {
    @EnvironmentObject private var themeStore: Store   // перерисовка при смене темы
    let media: String
    let file: String
    var thumb: String? = "480x0"
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Pal.field
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo").foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .task(id: media + file + (thumb ?? "")) { await load() }
    }

    private func load() async {
        let key = "\(media)/\(file)/\(thumb ?? "")" as NSString
        if let c = ImageCache.cache.object(forKey: key) { image = c; return }
        guard let url = ImageCache.url(media: media, file: file, thumb: thumb) else { failed = true; return }
        for attempt in 0..<3 {
            if Task.isCancelled { return }
            if let (d, r) = try? await ImageCache.session.data(from: url),
               (r as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: d) {
                ImageCache.cache.setObject(img, forKey: key)
                image = img
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(600_000_000 * (attempt + 1)))
        }
        failed = true
    }
}

// MARK: - Добавление фото

enum PhotoPrep {
    /// Уменьшает до 1600 px по длинной стороне и сжимает в JPEG.
    static func jpeg(from data: Data) -> (Data, Double)? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1600
        let size = img.size
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: target, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let j = out.jpegData(compressionQuality: 0.8) else { return nil }
        return (j, Double(size.width / max(size.height, 1)))
    }
}

extension Store {
    /// Загружает фото и добавляет его в ленту. Бросает ошибку с понятным текстом.
    func addPhoto(data: Data, caption: String, pin: UUID?) async throws {
        guard let (jpeg, ratio) = PhotoPrep.jpeg(from: data) else { throw SyncError.server("Не удалось прочитать фото") }
        let r = try await sync.upload(jpeg: jpeg)
        var item = PhotoItem(who: .me, media: r.id, file: r.file)
        item.caption = caption.trimmingCharacters(in: .whitespaces)
        item.pin = pin
        item.ratio = ratio
        data_append(item)
    }

    private func data_append(_ item: PhotoItem) {
        data.photos.append(item)
        success()
    }

    func react(_ photo: UUID, emoji: String) {
        let id = photo.uuidString + Who.me.rawValue
        if let i = data.reactions.firstIndex(where: { $0.id == id }) {
            if data.reactions[i].emoji == emoji { data.reactions.remove(at: i) } else { data.reactions[i].emoji = emoji }
        } else {
            data.reactions.append(PhotoReaction(id: id, photo: photo, who: .me, emoji: emoji))
        }
        tap()
    }

    func deletePhoto(_ p: PhotoItem) {
        data.photos.removeAll { $0.id == p.id }
        data.reactions.removeAll { $0.photo == p.id }
    }
}

/// Выбор фото + подпись + отправка. Используется в ленте и на карте.
struct PhotoComposer: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss
    var pin: UUID? = nil
    @State private var picked: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var raw: Data?
    @State private var caption = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    PhotosPicker(selection: $picked, matching: .images) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous).fill(Pal.card)
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFill()
                                    .frame(maxWidth: .infinity).frame(height: 320).clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.r(20), style: .continuous))
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus").font(.system(size: 38)).foregroundStyle(store.meColor)
                                    Text("Выбрать фото").font(.headline).foregroundStyle(.primary)
                                }
                            }
                        }
                        .frame(height: 320)
                    }
                    TextField("Подпись (по желанию)", text: $caption, axis: .vertical)
                        .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                    if sync.status == .notPaired {
                        Text("Сначала соединитесь с партнёром в настройках — фото хранятся на вашем сервере.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button { Task { await send() } } label: {
                        HStack {
                            if sending { ProgressView().tint(Pal.bg) }
                            Text(sending ? "Отправляю…" : "Опубликовать")
                        }
                        .bigButton().opacity(raw == nil || sync.status == .notPaired ? 0.4 : 1)
                    }
                    .disabled(raw == nil || sending || sync.status == .notPaired)
                }
                .padding(16)
            }
            .background(ThemeBackground())
            .navigationTitle("Новое фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onChange(of: picked) { _, item in
                Task {
                    guard let item, let d = try? await item.loadTransferable(type: Data.self) else { return }
                    raw = d
                    preview = UIImage(data: d)
                }
            }
        }
    }

    private func send() async {
        guard let raw else { return }
        sending = true
        error = nil
        do {
            try await store.addPhoto(data: raw, caption: caption, pin: pin)
            dismiss()
        } catch {
            self.error = SyncEngine.human(error)
        }
        sending = false
    }
}
