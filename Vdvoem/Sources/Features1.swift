import SwiftUI
import QuickLook
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Чат

struct ChatView: View {
    @EnvironmentObject var store: Store
    @State private var text = ""
    @EnvironmentObject var sync: SyncEngine
    @State private var sender: Who = .me
    @StateObject private var voice = VoiceRecorder()
    @State private var camera = false
    @State private var sending = false
    @State private var micDenied = false

    private func bubbleRadius() -> CGFloat {
        switch store.p.bubbleStyle {
        case 1: return 12
        case 2: return 5
        default: return 20
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        if store.data.messages.isEmpty {
                            EmptyState(icon: "bubble.left.and.bubble.right", title: "Ваш чат",
                                       text: "Короткие сообщения друг другу. Для общения между двумя телефонами нужна синхронизация.")
                        }
                        ForEach(store.data.messages) { m in
                            HStack {
                                if m.from == .me { Spacer(minLength: 50) }
                                VStack(alignment: m.from == .me ? .trailing : .leading, spacing: 2) {
                                    if m.kind == "voice" { VoiceBubble(m: m) }
                                    else if m.kind == "circle" { CircleBubble(m: m) }
                                    else {
                                        Text(m.text).padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(store.color(m.from), in: RoundedRectangle(cornerRadius: bubbleRadius(), style: .continuous))
                                            .foregroundStyle(store.color(m.from).onAccent)
                                    }
                                    Text(m.date.formatted(Date.FormatStyle().locale(ruLocale).hour().minute())).font(.caption2).foregroundStyle(.secondary)
                                }
                                if m.from == .partner { Spacer(minLength: 50) }
                            }
                            .id(m.id)
                            .transition(.scale(scale: 0.85, anchor: m.from == .me ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                        }
                    }
                    .padding(16)
                    .animation(Motion.spring, value: store.data.messages.count)
                }
                .onChange(of: store.data.messages.count) { _, _ in
                    if let last = store.data.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            composer
        }
        .background { WallpaperView(id: store.p.wallpaper).ignoresSafeArea() }
        .fullScreenCover(isPresented: $camera) {
            CircleCamera { url in
                camera = false
                if let url { Task { await sendCircle(url) } }
            }.ignoresSafeArea()
        }
        .alert("Нет доступа к микрофону", isPresented: $micDenied) {
            Button("OK", role: .cancel) {}
        } message: { Text("Разрешите микрофон для «Вдвоём» в Настройках iPhone.") }
        .hidesDock()
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var composer: some View {
        let empty = text.trimmingCharacters(in: .whitespaces).isEmpty
        HStack(spacing: 10) {
            if voice.recording {
                Button { _ = voice.stop(keep: false); store.tap() } label: {
                    Image(systemName: "trash").font(.system(size: 17, weight: .semibold)).foregroundStyle(.red)
                        .frame(width: 42, height: 42).glass(Circle(), tint: nil)
                }.buttonStyle(PressStyle())
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 9, height: 9).opacity(voice.seconds.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.3)
                    Text(mmss(voice.seconds)).font(.body.monospacedDigit())
                    Capsule().fill(store.meColor).frame(width: 6 + 80 * voice.level, height: 4)
                        .animation(.easeOut(duration: 0.1), value: voice.level)
                    Spacer()
                }
                .padding(.horizontal, 16).frame(height: 42)
                .glass(Capsule(), tint: store.glassTint)
                Button { Task { await sendVoice() } } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(store.meColor.onAccent)
                        .frame(width: 42, height: 42).background(store.meColor, in: Circle())
                }.buttonStyle(PressStyle())
            } else {
                if sync.status == .notPaired {
                    Menu {
                        Button(store.name(.me)) { sender = .me }
                        Button(store.name(.partner)) { sender = .partner }
                    } label: { Circle().fill(store.color(sender)).frame(width: 28, height: 28) }
                }
                TextField("Сообщение", text: $text, axis: .vertical).lineLimit(1...4)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .glass(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: store.glassTint)
                if empty {
                    if sync.status != .notPaired {
                        Button { store.tap(); camera = true } label: {
                            Image(systemName: "video.circle").font(.system(size: 22, weight: .regular))
                                .foregroundStyle(store.meColor)
                                .frame(width: 42, height: 42).glass(Circle(), tint: nil)
                        }.buttonStyle(PressStyle()).disabled(sending)
                        Button {
                            Task {
                                if await voice.start() { store.tap() } else { micDenied = true }
                            }
                        } label: {
                            Image(systemName: "mic.fill").font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(store.meColor.onAccent)
                                .frame(width: 42, height: 42).background(store.meColor, in: Circle())
                        }.buttonStyle(PressStyle()).disabled(sending)
                    } else {
                        sendButton(empty: true)
                    }
                } else {
                    sendButton(empty: false)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .animation(Motion.spring, value: voice.recording)
        .animation(Motion.spring, value: empty)
    }

    private func sendButton(empty: Bool) -> some View {
        Button(action: send) {
            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                .foregroundStyle(store.meColor.onAccent)
                .frame(width: 42, height: 42)
                .background(store.meColor, in: Circle())
                .opacity(empty ? 0.4 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(empty)
    }

    private func sendVoice() async {
        guard let (url, d) = voice.stop(keep: true), let data = try? Data(contentsOf: url) else { store.tap(); return }
        sending = true; defer { sending = false; try? FileManager.default.removeItem(at: url) }
        do {
            let r = try await sync.upload(data: data, name: "voice.m4a", mime: "audio/mp4")
            var m = ChatMessage(text: "🎤 Голосовое", from: .me)
            m.media = r.id; m.file = r.file; m.kind = "voice"; m.dur = d
            store.data.messages.append(m)
            store.sfx(.send)
        } catch { store.tap() }
    }

    private func sendCircle(_ url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let asset = AVURLAsset(url: url)
        let d = (try? await asset.load(.duration).seconds) ?? 0
        sending = true; defer { sending = false; try? FileManager.default.removeItem(at: url) }
        do {
            let r = try await sync.upload(data: data, name: "circle.mov", mime: "video/quicktime")
            var m = ChatMessage(text: "🎥 Кружок", from: .me)
            m.media = r.id; m.file = r.file; m.kind = "circle"; m.dur = d.isFinite ? d : 0
            store.data.messages.append(m)
            store.sfx(.send)
        } catch { store.tap() }
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        store.data.messages.append(ChatMessage(text: t, from: sync.status == .notPaired ? sender : .me))
        text = ""
        store.tap()
        store.sfx(.send)
    }
}

// MARK: - Планы

struct PlansView: View {
    @EnvironmentObject var store: Store
    @State private var adding = false

    var body: some View {
        Screen {
            if store.data.plans.isEmpty {
                EmptyState(icon: "flag", title: "Общие планы", text: "Поездка, ремонт, большая покупка — разбейте на шаги и двигайтесь вместе.",
                           action: "Новый план", onTap: { adding = true })
            }
            ForEach(store.data.plans) { p in
                NavigationLink { PlanDetail(plan: store.bind(\.plans, p)) } label: {
                    let done = p.steps.filter { $0.done }.count
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(p.emoji).font(.title)
                            VStack(alignment: .leading) {
                                Text(p.title).font(.body.weight(.semibold))
                                if let d = p.target {
                                    Text(d.formatted(Date.FormatStyle().locale(ruLocale).day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(done)/\(p.steps.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: p.steps.isEmpty ? 0 : Double(done) / Double(p.steps.count)).tint(store.meColor)
                    }
                    .padding(14).card()
                }
                .buttonStyle(PressStyle())
            }
        }
        .navigationTitle("Планы")
        .pairToolbar(scope: false, add: { adding = true })
        .sheet(isPresented: $adding) { AddPlanSheet() }
    }
}

struct AddPlanSheet: View {
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var emoji = "✈️"
    @State private var hasDate = false
    @State private var date = Date()

    var body: some View {
        FormSheet(title: "Новый план", canSave: !title.trimmingCharacters(in: .whitespaces).isEmpty, onSave: {
            store.data.plans.append(Plan(title: title, emoji: emoji, target: hasDate ? date : nil))
        }) {
            Section {
                TextField("Название", text: $title)
                TextField("Эмодзи", text: $emoji)
                Toggle("Целевая дата", isOn: $hasDate)
                if hasDate { DatePicker("Дата", selection: $date, displayedComponents: .date) }
            }
        }
    }
}

struct PlanDetail: View {
    @EnvironmentObject var store: Store
    @Binding var plan: Plan
    @State private var text = ""

    var body: some View {
        Screen {
            HStack {
                TextField("Новый шаг", text: $text).onSubmit(add)
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title2) }
            }
            .padding(14).card()
            ForEach($plan.steps) { $s in
                HStack(spacing: 12) {
                    Button { s.done.toggle(); store.tap() } label: {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(s.done ? store.meColor : Color.secondary)
                    }.buttonStyle(PressStyle())
                    Text(s.title).strikethrough(s.done)
                    Spacer()
                }
                .padding(14).card()
            }
        }
        .navigationTitle("\(plan.emoji) \(plan.title)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    let id = plan.id
                    store.data.plans.removeAll { $0.id == id }
                } label: { Image(systemName: "trash") }
            }
        }
    }

    private func add() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        plan.steps.append(ListEntry(title: t))
        text = ""
    }
}

// MARK: - Заметки

struct NotesView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Note?

    var body: some View {
        let sorted = store.data.notes.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
        Screen {
            if sorted.isEmpty {
                EmptyState(icon: "note.text", title: "Общие заметки", text: "Пароли от wifi, размеры, идеи — всё в одном месте.",
                           action: "Новая заметка", onTap: { editing = Note(title: "") })
            }
            ForEach(sorted) { n in
                Button { editing = n } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(n.title.isEmpty ? "Без названия" : n.title).font(.body.weight(.semibold))
                            Spacer()
                            if n.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(store.partnerColor) }
                        }
                        if !n.body.isEmpty { Text(n.body).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14).card()
                }
                .buttonStyle(PressStyle())
            }
        }
        .navigationTitle("Заметки")
        .pairToolbar(scope: false, add: { editing = Note(title: "") })
        .sheet(item: $editing) { n in NoteEditor(note: n) }
    }
}

struct NoteEditor: View {
    @EnvironmentObject var store: Store
    @State var note: Note

    var body: some View {
        FormSheet(title: "Заметка", onSave: {
            var n = note
            n.date = Date()
            if let i = store.data.notes.firstIndex(where: { $0.id == n.id }) { store.data.notes[i] = n }
            else if !(n.title.isEmpty && n.body.isEmpty) { store.data.notes.append(n) }
        }) {
            Section {
                TextField("Название", text: $note.title)
                TextField("Текст", text: $note.body, axis: .vertical).lineLimit(5...20)
                Toggle("Закрепить", isOn: $note.pinned)
            }
            if store.data.notes.contains(where: { $0.id == note.id }) {
                Section {
                    Button("Удалить", role: .destructive) {
                        let id = note.id
                        store.data.notes.removeAll { $0.id == id }
                    }
                }
            }
        }
    }
}

// MARK: - Файлы

struct FilesView: View {
    @EnvironmentObject var store: Store
    @State private var importing = false
    @State private var preview: URL?

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Files")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var body: some View {
        Screen {
            if store.data.files.isEmpty {
                EmptyState(icon: "folder", title: "Общие файлы", text: "Билеты, документы, фото. Раздел закрыт Face ID.",
                           action: "Добавить файл", onTap: { importing = true })
            }
            ForEach(store.data.files) { f in
                HStack(spacing: 12) {
                    Image(systemName: "doc").font(.title2).foregroundStyle(store.meColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name).font(.body.weight(.medium)).lineLimit(1)
                        Text(f.date.formatted(Date.FormatStyle().locale(ruLocale).day().month().year())).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ShareLink(item: dir.appendingPathComponent(f.stored)) { Image(systemName: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(f.stored))
                        store.data.files.removeAll { $0.id == f.id }
                    } label: { Image(systemName: "trash").foregroundStyle(.secondary) }
                }
                .padding(14).card()
                .onTapGesture { preview = dir.appendingPathComponent(f.stored) }
            }
        }
        .pairToolbar(scope: false, add: { importing = true })
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { res in
            guard case .success(let urls) = res else { return }
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                let stored = UUID().uuidString + "-" + u.lastPathComponent
                if (try? FileManager.default.copyItem(at: u, to: dir.appendingPathComponent(stored))) != nil {
                    store.data.files.append(FileItem(name: u.lastPathComponent, stored: stored))
                }
            }
        }
        .quickLookPreview($preview)
    }
}

