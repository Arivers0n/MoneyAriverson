import SwiftUI

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
extension View {
    func card(_ padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct SectionTitle: View {
    let text: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction).font(.subheadline.weight(.semibold)).tint(Theme.accent)
            }
        }
        .padding(.bottom, 8)
    }
}

struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct Bar: View {
    let value: Double
    var color: Color = Theme.inc
    var height: CGFloat = 10
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.soft)
                Capsule().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct Ring: View {
    let value: Double
    let color: Color
    var size: CGFloat = 50
    var body: some View {
        ZStack {
            Circle().stroke(Theme.soft, lineWidth: 5)
            Circle().trim(from: 0, to: max(0, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%").font(.caption2.weight(.semibold))
        }
        .frame(width: size, height: size)
    }
}

struct Chip: View {
    let title: String
    var color: Color? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
            .background(selected ? Theme.ink : Theme.soft, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct StatusPill: View {
    let st: InstStatus
    var body: some View {
        Text(st.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
    var color: Color {
        switch st {
        case .ok: return Theme.inc
        case .late: return Theme.warn
        case .overdue: return Theme.exp
        case .due: return Theme.accent
        case .covered: return .secondary
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(maxW, widest), height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct EmptyNote: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

/// Поле суммы, которое принимает и запятую, и точку.
struct AmountField: View {
    @Binding var text: String
    var placeholder = "0"
    var big = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(big ? .system(size: 36, weight: .semibold, design: .rounded) : .body.weight(.semibold))
            Text("₽").font(big ? .system(size: 26, weight: .medium, design: .rounded) : .body).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Конфетти

struct ConfettiView: View {
    struct P { var x: Double; var vx: Double; var vy: Double; var r: Double; var vr: Double; var c: Color; var s: Double }
    @State private var start = Date()
    @State private var parts: [P] = (0..<140).map { _ in
        P(x: 0.5, vx: Double.random(in: -0.6...0.6), vy: Double.random(in: -1.5 ... -0.6), r: Double.random(in: 0...6),
          vr: Double.random(in: -6...6), c: Color(hex: Theme.palette.randomElement() ?? "2B47C9"), s: Double.random(in: 6...11))
    }
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSince(start)
                for p in parts {
                    let x = (p.x + p.vx * t * 0.6) * size.width
                    let y = size.height * 0.42 + (p.vy * t + 0.9 * t * t) * size.height * 0.5
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(p.r + p.vr * t))
                    c.fill(Path(CGRect(x: -p.s / 2, y: -p.s / 4, width: p.s, height: p.s / 2)), with: .color(p.c))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
