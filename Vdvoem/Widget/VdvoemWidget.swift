import AppIntents
import WidgetKit
import SwiftUI
import UIKit

// MARK: - Выбор содержимого

enum VDContent: String, AppEnum {
    case overview, status, mood, distance, photo, together

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Что показывать")
    static var caseDisplayRepresentations: [VDContent: DisplayRepresentation] = [
        .overview: DisplayRepresentation(title: "Всё сразу"),
        .status: DisplayRepresentation(title: "Статус партнёра"),
        .mood: DisplayRepresentation(title: "Настроение"),
        .distance: DisplayRepresentation(title: "Расстояние"),
        .photo: DisplayRepresentation(title: "Общее фото"),
        .together: DisplayRepresentation(title: "Дней вместе")
    ]
}

struct VDConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Что показывать"
    static var description = IntentDescription("Статус, настроение, расстояние или общее фото.")

    @Parameter(title: "Показывать", default: .overview)
    var content: VDContent
}

// MARK: - Данные

struct VDEntry: TimelineEntry {
    let date: Date
    let content: VDContent
    let snap: VDSnapshot
    let photo: UIImage?
    let hasData: Bool
}

struct VDProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> VDEntry {
        VDEntry(date: Date(), content: .overview, snap: .sample(), photo: nil, hasData: true)
    }

    func snapshot(for configuration: VDConfigIntent, in context: Context) async -> VDEntry {
        make(configuration.content, sample: context.isPreview)
    }

    func timeline(for configuration: VDConfigIntent, in context: Context) async -> Timeline<VDEntry> {
        let e = make(configuration.content, sample: false)
        var next = Date().addingTimeInterval(15 * 60)
        if let x = e.snap.statusExpires, x > Date(), x < next { next = x.addingTimeInterval(1) }
        return Timeline(entries: [e], policy: .after(next))
    }

    private func make(_ c: VDContent, sample: Bool) -> VDEntry {
        let real = sample ? nil : WidgetShared.readSnapshot()
        var photo: UIImage?
        if !sample, real?.hasPhoto == true, let d = WidgetShared.readPhoto() { photo = UIImage(data: d) }
        return VDEntry(date: Date(), content: c, snap: real ?? .sample(), photo: photo, hasData: real != nil || sample)
    }
}

// MARK: - Вёрстка

private func hex(_ s: String) -> Color {
    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)
    return Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
}

private extension VDSnapshot {
    func activeStatus(_ now: Date) -> Bool {
        guard !statusTitle.isEmpty else { return false }
        if let x = statusExpires { return x > now }
        return true
    }
}

struct VDView: View {
    @Environment(\.widgetFamily) private var family
    let entry: VDEntry

    private var s: VDSnapshot { entry.snap }
    private var partner: Color { hex(s.partnerHex) }
    private var me: Color { hex(s.myHex) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(URL(string: "vdvoem://home"))
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        if family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline {
            Color.clear
        } else if entry.content == .photo, let p = entry.photo {
            Image(uiImage: p).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [partner.opacity(0.28), Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
        }
    }

    // Статус-блок

    private var statusBlock: some View {
        let active = s.activeStatus(entry.date)
        let tint = active ? hex(s.statusHex) : partner
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(partner).frame(width: 8, height: 8)
                Text(s.partnerName).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(spacing: 8) {
                Image(systemName: active ? s.statusSymbol : "moon.zzz").font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
                Text(active ? s.statusTitle : "нет статуса").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            }
            if active, !s.statusNote.isEmpty {
                Text(s.statusNote).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var moodBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Настроение").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                VStack(spacing: 0) { Text(s.myMoodEmoji.isEmpty ? "—" : s.myMoodEmoji).font(.system(size: 30)); Text(s.myName).font(.system(size: 9)).foregroundStyle(me).lineLimit(1) }
                VStack(spacing: 0) { Text(s.partnerMoodEmoji.isEmpty ? "—" : s.partnerMoodEmoji).font(.system(size: 30)); Text(s.partnerName).font(.system(size: 9)).foregroundStyle(partner).lineLimit(1) }
            }
        }
    }

    private var distanceBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Между нами", systemImage: "location.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(s.distanceText.isEmpty ? "—" : s.distanceText).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
        }
    }

    private var togetherBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Вместе", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(partner)
            Text("\(s.daysTogether)").font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            Text("дней").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var photoBlock: some View {
        ZStack(alignment: .bottomLeading) {
            if entry.photo == nil {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle").font(.title)
                    Text("Нет общих фото").font(.caption)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !s.photoCaption.isEmpty {
                Text(s.photoCaption).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            }
        }
    }

    // Размеры

    @ViewBuilder private var small: some View {
        switch entry.content {
        case .status: padded(statusBlock)
        case .mood: padded(moodBlock)
        case .distance: padded(distanceBlock)
        case .together: padded(togetherBlock)
        case .photo: photoBlock
        case .overview:
            padded(VStack(alignment: .leading, spacing: 10) {
                statusBlock
                Divider()
                HStack { Text(s.distanceText.isEmpty ? "—" : s.distanceText).font(.subheadline.weight(.bold)); Spacer(); Text(s.partnerMoodEmoji).font(.title3) }
            })
        }
    }

    @ViewBuilder private var medium: some View {
        switch entry.content {
        case .photo: photoBlock
        case .status: padded(HStack { statusBlock; Spacer(); moodBlock })
        default:
            padded(HStack(alignment: .top, spacing: 14) {
                statusBlock.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    distanceBlock
                    HStack(spacing: 8) { Text(s.myMoodEmoji); Text(s.partnerMoodEmoji); Spacer(); Label("\(s.daysTogether)", systemImage: "heart.fill").font(.caption.weight(.bold)).foregroundStyle(partner) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            })
        }
    }

    private func padded<V: View>(_ v: V) -> some View {
        v.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // Экран блокировки

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch entry.content {
            case .mood: Text(s.partnerMoodEmoji.isEmpty ? "❤️" : s.partnerMoodEmoji).font(.title)
            case .distance: Text(s.distanceText.isEmpty ? "—" : s.distanceText).font(.caption.weight(.bold)).minimumScaleFactor(0.5)
            case .together: VStack(spacing: 0) { Text("\(s.daysTogether)").font(.headline); Image(systemName: "heart.fill").font(.caption2) }
            default:
                if s.activeStatus(entry.date) { Image(systemName: s.statusSymbol).font(.title3) } else { Image(systemName: "heart.fill") }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.partnerName).font(.caption.weight(.semibold))
            Text(s.activeStatus(entry.date) ? s.statusTitle : "нет статуса").font(.headline).lineLimit(1)
            Text([s.distanceText, s.partnerMoodEmoji].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Text("\(s.partnerName): \(s.activeStatus(entry.date) ? s.statusTitle : "—") \(s.partnerMoodEmoji)")
    }
}

// MARK: - Виджет и набор

struct VdvoemWidget: Widget {
    let kind = "VdvoemMain"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: VDConfigIntent.self, provider: VDProvider()) { entry in
            VDView(entry: entry)
        }
        .configurationDisplayName("Вдвоём")
        .description("Статус партнёра, настроение, расстояние и общее фото.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

@main
struct VdvoemWidgetBundle: WidgetBundle {
    var body: some Widget { VdvoemWidget() }
}
