import SwiftUI

// MARK: - Фотолента

struct MemoriesView: View {
    @EnvironmentObject var store: Store
    @State private var composing = false
    @State private var opened: PhotoItem?

    private var photos: [PhotoItem] { store.data.photos.sorted { $0.date > $1.date } }

    var body: some View {
        Screen {
            if photos.isEmpty {
                EmptyState(icon: "photo.on.rectangle.angled", title: "Ваши воспоминания",
                           text: "Делитесь фото — партнёр увидит их сразу и сможет ответить реакцией.",
                           action: "Добавить фото", onTap: { composing = true })
            }
            ForEach(photos) { p in
                card(p)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
            }
        }
        .navigationTitle("Воспоминания")
        .animation(Motion.spring, value: store.data.photos.count)
        .pairToolbar(scope: false) { composing = true }
        .sheet(isPresented: $composing) { PhotoComposer().environmentObject(store).environmentObject(store.sync) }
        .fullScreenCover(item: $opened) { p in PhotoViewer(photo: p).environmentObject(store) }
    }

    private func card(_ p: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(store.color(p.who)).frame(width: 10, height: 10)
                Text(store.name(p.who)).font(.subheadline.weight(.semibold))
                Spacer()
                Text(p.date.agoText).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.top, 12)

            Button { opened = p } label: {
                RemoteImage(media: p.media, file: p.file)
                    .aspectRatio(CGFloat(min(max(p.ratio, 0.75), 1.6)), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous))
                    .padding(.horizontal, 10)
            }
            .buttonStyle(PressStyle())

            if !p.caption.isEmpty {
                Text(p.caption).font(.body).padding(.horizontal, 14)
            }
            ReactionBar(photo: p).padding(.horizontal, 12).padding(.bottom, 12)
        }
        .card()
        .contextMenu {
            if p.who == .me {
                Button("Удалить", role: .destructive) { withAnimation { store.deletePhoto(p) } }
            }
        }
    }
}

struct ReactionBar: View {
    @EnvironmentObject var store: Store
    let photo: PhotoItem

    private var mine: String? { store.data.reactions.first { $0.photo == photo.id && $0.who == .me }?.emoji }
    private var theirs: String? { store.data.reactions.first { $0.photo == photo.id && $0.who == .partner }?.emoji }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactionEmojis, id: \.self) { e in
                Button {
                    withAnimation(Motion.spring) { store.react(photo.id, emoji: e) }
                    store.sfx(.pop)
                } label: {
                    Text(e).font(.system(size: 20))
                        .frame(width: 38, height: 34)
                        .background(mine == e ? store.meColor.opacity(0.25) : Pal.field.opacity(0.6), in: Capsule())
                        .scaleEffect(mine == e ? 1.12 : 1)
                }
                .buttonStyle(PressStyle())
            }
            Spacer(minLength: 0)
            if let t = theirs {
                HStack(spacing: 4) {
                    Circle().fill(store.partnerColor).frame(width: 7, height: 7)
                    Text(t).font(.system(size: 20))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(store.partnerColor.opacity(0.18), in: Capsule())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct PhotoViewer: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let photo: PhotoItem
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(media: photo.media, file: photo.file, thumb: "1080x0", contentMode: .fit)
                .scaleEffect(scale)
                .gesture(MagnificationGesture()
                    .onChanged { scale = max(1, min(4, lastScale * $0)) }
                    .onEnded { _ in lastScale = scale; if scale < 1.05 { withAnimation { scale = 1; lastScale = 1 } } })
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; lastScale = scale } }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 32)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white).padding(16)
            }
        }
    }
}
