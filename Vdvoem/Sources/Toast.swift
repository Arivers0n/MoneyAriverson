import SwiftUI

// MARK: - Тосты и скелетоны (по мотивам transitions.dev)

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let symbol: String
}

@MainActor
final class Toasts: ObservableObject {
    static let shared = Toasts()
    @Published var item: ToastItem?

    func show(_ text: String, symbol: String = "checkmark.circle.fill") {
        let it = ToastItem(text: text, symbol: symbol)
        withAnimation(Motion.spring) { item = it }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if item?.id == it.id { withAnimation(Motion.spring) { item = nil } }
        }
    }
}

struct ToastHost: View {
    @ObservedObject private var toasts = Toasts.shared

    var body: some View {
        VStack {
            if let i = toasts.item {
                HStack(spacing: 8) {
                    Image(systemName: i.symbol).foregroundStyle(.green)
                    Text(i.text).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .glass(Capsule())
                .id(i.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}

/// Серая заглушка с бегущим бликом — пока грузится картинка.
struct SkeletonBox: View {
    @State private var on = false

    var body: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.14))
            .overlay(
                GeometryReader { g in
                    LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.6)
                        .offset(x: on ? g.size.width : -g.size.width * 0.6)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { on = true }
            }
    }
}
