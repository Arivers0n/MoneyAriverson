import WidgetKit
import SwiftUI

struct QuickEntry: TimelineEntry {
    let date: Date
}

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) { completion(QuickEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: Date())], policy: .never))
    }
}

private let accent = Color(red: 0x2B / 255, green: 0x47 / 255, blue: 0xC9 / 255)
private let green = Color(red: 0x17 / 255, green: 0x80 / 255, blue: 0x5A / 255)

struct QuickButton: View {
    let url: String
    let symbol: String
    let title: String
    let color: Color
    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
        }
    }
}

struct QuickWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuickEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "mic.fill").font(.title2.weight(.semibold))
            }
            .widgetURL(URL(string: "koshelek://voice"))
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.fill").font(.title3)
                VStack(alignment: .leading) {
                    Text("Кошелёк").font(.headline)
                    Text("Записать голосом").font(.caption)
                }
            }
            .widgetURL(URL(string: "koshelek://voice"))
            .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text("Кошелёк").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Link(destination: URL(string: "koshelek://voice")!) {
                    VStack(spacing: 6) {
                        Image(systemName: "mic.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                        Text("Голосом").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Кошелёк · быстрая запись").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    QuickButton(url: "koshelek://voice", symbol: "mic.fill", title: "Голосом", color: accent)
                    QuickButton(url: "koshelek://scan", symbol: "camera.fill", title: "Скан чека", color: green)
                    QuickButton(url: "koshelek://add", symbol: "plus", title: "Вручную", color: .gray)
                }
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }
}

struct QuickWidget: Widget {
    let kind = "KoshelekQuick"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickProvider()) { entry in
            QuickWidgetView(entry: entry)
        }
        .configurationDisplayName("Быстрая запись")
        .description("Голосом, скан чека или вручную — в одно касание.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct KoshelekWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickWidget()
    }
}
