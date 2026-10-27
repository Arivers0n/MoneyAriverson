import AppIntents
import WidgetKit
import SwiftUI
import UIKit

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
                    Text("Копилка").font(.headline)
                    Text("Сказать голосом").font(.caption)
                }
            }
            .widgetURL(URL(string: "koshelek://voice"))
            .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 8) {
                Text("Копилка").font(.caption.weight(.bold)).foregroundStyle(.secondary)
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
                Text("Копилка · быстрая запись").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    QuickButton(url: "koshelek://voice", symbol: "mic.fill", title: "Голосом", color: accent)
                    QuickButton(url: "koshelek://scan", symbol: "camera.fill", title: "Скан чека", color: green)
                    QuickButton(url: "koshelek://goals", symbol: "banknote.fill", title: "Копилки", color: Color(red: 0x8A / 255, green: 0x4F / 255, blue: 0xD0 / 255))
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
        .description("Голосом, скан чека или копилки — в одно касание.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Свой виджет из конструктора

struct SlotEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Виджет")
    static var defaultQuery = SlotQuery()

    var id: Int
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SlotQuery: EntityQuery {
    private func all() -> [SlotEntity] {
        let set = WidgetShared.readConfigs() ?? WidgetConfigSet.makeDefault()
        return set.slots.map { SlotEntity(id: $0.id, name: $0.name) }
    }

    func entities(for identifiers: [Int]) async throws -> [SlotEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SlotEntity] { all() }

    func defaultResult() async -> SlotEntity? { all().first }
}

struct SelectSlotIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Какой виджет показать"
    static var description = IntentDescription("Выберите один из своих дизайнов из конструктора Копилки.")

    @Parameter(title: "Виджет")
    var slot: SlotEntity?
}

struct DesignEntry: TimelineEntry {
    let date: Date
    let design: WidgetDesign
    let snapshot: WidgetSnapshot
    /// Реальные данные приложения дошли до виджета (иначе показываем пример).
    let hasData: Bool
    let petImage: UIImage?
}

extension WidgetFamily {
    var designKind: WidgetFamilyKind {
        switch self {
        case .systemSmall: return .small
        case .systemMedium: return .medium
        case .systemLarge: return .large
        case .accessoryCircular: return .lockCircular
        case .accessoryRectangular: return .lockRectangular
        case .accessoryInline: return .lockInline
        default: return .medium
        }
    }
}

struct DesignProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DesignEntry {
        makeEntry(slot: 1, family: context.family.designKind, sample: true)
    }

    func snapshot(for configuration: SelectSlotIntent, in context: Context) async -> DesignEntry {
        makeEntry(slot: configuration.slot?.id ?? 1, family: context.family.designKind, sample: context.isPreview)
    }

    func timeline(for configuration: SelectSlotIntent, in context: Context) async -> Timeline<DesignEntry> {
        let entry = makeEntry(slot: configuration.slot?.id ?? 1, family: context.family.designKind, sample: false)
        // Раз в полчаса и обязательно после полуночи: «сегодня» и месяц сбрасываются.
        let cal = Calendar.current
        let half = Date().addingTimeInterval(30 * 60)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? half
        let midnight = cal.startOfDay(for: tomorrow).addingTimeInterval(5)
        return Timeline(entries: [entry], policy: .after(min(half, midnight)))
    }

    private func makeEntry(slot: Int, family: WidgetFamilyKind, sample: Bool) -> DesignEntry {
        let configs = (WidgetShared.readConfigs() ?? WidgetConfigSet.makeDefault()).validated()
        let design = configs.slot(slot)?.design(for: family) ?? WidgetPresets.make(.kopilka, for: family)
        let real = sample ? nil : WidgetShared.readSnapshot()
        let snapshot = real ?? WidgetSnapshot.sample()
        var pet: UIImage?
        if snapshot.hasPetImage, let data = WidgetShared.readPet() { pet = UIImage(data: data) }
        return DesignEntry(date: .now, design: design, snapshot: snapshot, hasData: real != nil || sample, petImage: pet)
    }
}

struct DesignEntryView: View {
    let entry: DesignEntry

    var body: some View {
        if entry.design.family.isLockScreen {
            WidgetLockView(design: entry.design, snapshot: entry.snapshot, now: entry.date, systemBackground: true)
                .widgetURL(URL(string: "koshelek://home"))
                .containerBackground(for: .widget) { Color.clear }
        } else {
            WidgetDesignView(design: entry.design, snapshot: entry.snapshot, now: entry.date, petImage: entry.petImage)
                .overlay(alignment: .topTrailing) { warning }
                .widgetURL(URL(string: "koshelek://home"))
                .containerBackground(for: .widget) {
                    WidgetBackgroundView(background: entry.design.background)
                }
        }
    }

    @ViewBuilder
    private var warning: some View {
        if !entry.hasData {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.yellow)
                .padding(8)
        }
    }
}

struct KoshelekDesignWidget: Widget {
    let kind = "KoshelekDesign"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectSlotIntent.self, provider: DesignProvider()) { entry in
            DesignEntryView(entry: entry)
        }
        .configurationDisplayName("Мой виджет")
        .description("Ваш дизайн из конструктора: бюджет, баланс, копилка, напарник.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct KoshelekWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickWidget()
        KoshelekDesignWidget()
    }
}
