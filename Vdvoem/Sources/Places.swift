import SwiftUI
import MapKit

// MARK: - Карта

struct PlacesView: View {
    @EnvironmentObject var store: Store
    @State private var camera: MapCameraPosition = .automatic
    @State private var draft: DraftPoint?
    @State private var selected: MapPin?

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(store.data.pins) { pin in
                        Annotation(pin.title, coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lon)) {
                            Button { selected = pin; store.tap() } label: { pinView(pin) }.buttonStyle(.plain)
                        }
                    }
                    ForEach(store.data.places) { pt in
                        Annotation(store.name(pt.who), coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon)) {
                            ZStack {
                                Circle().fill(store.color(pt.who).opacity(0.25)).frame(width: 36, height: 36)
                                Circle().fill(store.color(pt.who)).frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                            }
                        }
                    }
                    if let d = draft {
                        Marker("Новая метка", systemImage: "plus", coordinate: d.coord).tint(store.meColor)
                    }
                }
                .mapControls { MapCompass(); MapUserLocationButton() }
                .onTapGesture { point in
                    if let c = proxy.convert(point, from: .local) {
                        withAnimation { draft = DraftPoint(coord: c) }
                        store.tap()
                    }
                }
            }
            VStack(spacing: 8) {
                if let d = store.distanceKm() {
                    Label("Между вами \(d.kmText)", systemImage: "location.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .glassCapsule()
                }
                if store.data.pins.isEmpty && draft == nil {
                    Text("Нажмите на карту, чтобы поставить общую метку")
                        .font(.footnote).padding(.horizontal, 14).padding(.vertical, 9)
                        .glassCapsule()
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("Карта")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { d in
            PinEditor(coord: d.coord) { draft = nil }.environmentObject(store).presentationDetents([.medium])
        }
        .sheet(item: $selected) { pin in
            PinDetail(pinID: pin.id).environmentObject(store).environmentObject(store.sync)
                .presentationDetents([.medium, .large])
        }
    }

    private func pinView(_ pin: MapPin) -> some View {
        let hasPhoto = store.data.photos.contains { $0.pin == pin.id }
        return ZStack(alignment: .topTrailing) {
            Text(pin.emoji).font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(store.color(pin.who), in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(radius: 3, y: 2)
            if hasPhoto {
                Image(systemName: "photo.fill").font(.system(size: 9)).foregroundStyle(.white)
                    .padding(4).background(Color.black.opacity(0.7), in: Circle()).offset(x: 4, y: -4)
            }
        }
    }
}

struct DraftPoint: Identifiable {
    let id = UUID()
    let coord: CLLocationCoordinate2D
}

struct PinEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let coord: CLLocationCoordinate2D
    var onDone: () -> Void
    @State private var title = ""
    @State private var note = ""
    @State private var emoji = "📍"
    private let emojis = ["📍", "❤️", "🍽️", "☕", "🎬", "🏖️", "🏔️", "🎡", "🏠", "🎁", "✈️", "⭐️"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название места", text: $title)
                TextField("Заметка", text: $note, axis: .vertical)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.title2).padding(8)
                                .background(emoji == e ? store.meColor.opacity(0.25) : Color.clear, in: Circle())
                                .onTapGesture { emoji = e }
                        }
                    }
                }
            }
            .navigationTitle("Новая метка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { onDone(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        let t = title.trimmingCharacters(in: .whitespaces)
                        store.data.pins.append(MapPin(title: t.isEmpty ? "Наше место" : t, note: note,
                                                      lat: coord.latitude, lon: coord.longitude, emoji: emoji, who: .me))
                        store.success()
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PinDetail: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let pinID: UUID
    @State private var adding = false

    private var pin: MapPin? { store.data.pins.first { $0.id == pinID } }
    private var photos: [PhotoItem] { store.data.photos.filter { $0.pin == pinID }.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pin {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Text(pin.emoji).font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pin.title).font(.title3.weight(.semibold))
                                Text("Поставил(а) \(store.name(pin.who)) · \(pin.date.agoText)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !pin.note.isEmpty { Text(pin.note) }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(photos) { p in
                                RemoteImage(media: p.media, file: p.file)
                                    .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                            }
                        }
                        Button { adding = true } label: { Label("Добавить фото к месту", systemImage: "photo.badge.plus").bigButton() }
                        Button("Удалить метку", role: .destructive) {
                            store.data.pins.removeAll { $0.id == pinID }
                            for i in store.data.photos.indices where store.data.photos[i].pin == pinID { store.data.photos[i].pin = nil }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(16)
                }
            }
            .background(ThemeBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .sheet(isPresented: $adding) { PhotoComposer(pin: pinID).environmentObject(store).environmentObject(store.sync) }
        }
    }
}
