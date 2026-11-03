import SwiftUI
import Security

// MARK: - Настройки сервера

enum VDConfig {
    static let base = "https://2-27-25-140.sslip.io:8443"
}

// MARK: - Связка ключей (логин и пароль устройства)

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ru.vdvoem.app",
         kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String) {
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func remove(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}

// MARK: - JSON без типа (данные записи едут на сервер как обычный JSON)

enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

// MARK: - Модели обмена

struct VDMember: Codable, Hashable { var id: String; var name: String }
struct VDPair: Codable, Hashable {
    var id: String
    var code: String
    var creator: String
    var members: [VDMember]
}

struct SyncDoc: Codable {
    var cid: String
    var kind: String
    var data: JSONValue?
    var deleted: Bool
    var cts: Double
    var srv: Double? = nil
    var author: String? = nil
}

private struct PullResponse: Decodable { var docs: [SyncDoc]; var cursor: Double; var more: Bool }
private struct PairResponse: Decodable { var pair: VDPair? }

enum SyncStatus: Equatable {
    case notPaired, waitingPartner, connecting, live, offline
}

enum SyncError: Error { case server(String) }

// MARK: - Перспектива
// На сервере всё хранится «глазами создателя пары»: у создателя «я» = .me, у второго телефона роли меняются местами.

extension Who {
    var flipped: Who { self == .me ? .partner : .me }
}

struct Adapter {
    let kind: String
    let snapshot: (AppData, Bool) -> [String: Data]
    let apply: (inout AppData, [(String, Data?)], Bool) -> Void
}

private func adapter<T: Codable & Identifiable>(_ kind: String,
                                                _ kp: WritableKeyPath<AppData, [T]>,
                                                flip: @escaping (T) -> T) -> Adapter
where T.ID: Hashable & CustomStringConvertible {
    Adapter(
        kind: kind,
        snapshot: { d, flipOn in
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            var out: [String: Data] = [:]
            for item in d[keyPath: kp] {
                let c = flipOn ? flip(item) : item
                if let b = try? enc.encode(c) { out[c.id.description] = b }
            }
            return out
        },
        apply: { d, changes, flipOn in
            let dec = JSONDecoder()
            for (cid, payload) in changes {
                if let payload = payload {
                    guard let c = try? dec.decode(T.self, from: payload) else { continue }
                    let local = flipOn ? flip(c) : c
                    if let i = d[keyPath: kp].firstIndex(where: { $0.id == local.id }) {
                        d[keyPath: kp][i] = local
                    } else {
                        d[keyPath: kp].append(local)
                    }
                } else {
                    d[keyPath: kp].removeAll { (flipOn ? flip($0) : $0).id.description == cid }
                }
            }
        }
    )
}

private func makeAdapters() -> [Adapter] {
    [
        adapter("tasks", \AppData.tasks) { t in
            var x = t; x.owner = t.owner?.flipped; x.createdBy = t.createdBy.flipped; return x
        },
        adapter("events", \AppData.events) { $0 },
        adapter("wishes", \AppData.wishes) { w in var x = w; x.owner = w.owner.flipped; return x },
        adapter("lists", \AppData.lists) { $0 },
        adapter("messages", \AppData.messages) { m in var x = m; x.from = m.from.flipped; return x },
        adapter("plans", \AppData.plans) { $0 },
        adapter("notes", \AppData.notes) { $0 },
        adapter("polls", \AppData.polls) { p in
            var x = p
            x.options = p.options.map { o in var y = o; y.voters = o.voters.map { $0.flipped }; return y }
            return x
        },
        adapter("capsules", \AppData.capsules) { c in var x = c; x.from = c.from.flipped; return x },
        adapter("gifts", \AppData.gifts) { $0 },
        adapter("answers", \AppData.answers) { a in
            var x = a; x.me = a.partner; x.partner = a.me; return x
        },
        adapter("moods", \AppData.moods) { m in
            var x = m; x.who = m.who.flipped; x.id = m.day + x.who.rawValue; return x
        },
        adapter("statuses", \AppData.statuses) { s in var x = s; x.who = s.who.flipped; return x },
        adapter("sleeps", \AppData.sleeps) { s in
            var x = s; x.who = s.who.flipped; x.id = s.day + x.who.rawValue; return x
        },
        adapter("counters", \AppData.counters) { $0 },
        adapter("tracks", \AppData.tracks) { t in var x = t; x.who = t.who.flipped; return x },
        adapter("jar", \AppData.jar) { j in var x = j; x.who = j.who.flipped; return x },
        adapter("photos", \AppData.photos) { p in var x = p; x.who = p.who.flipped; return x },
        adapter("reactions", \AppData.reactions) { r in
            var x = r; x.who = r.who.flipped; x.id = r.photo.uuidString + x.who.rawValue; return x
        },
        adapter("pins", \AppData.pins) { p in var x = p; x.who = p.who.flipped; return x },
        adapter("places", \AppData.places) { p in
            var x = p; x.who = p.who.flipped; x.id = x.who.rawValue; return x
        },
        adapter("signals", \AppData.signals) { s in var x = s; x.who = s.who.flipped; return x },
        adapter("pets", \AppData.pets) { p in var x = p; x.fedBy = p.fedBy.flipped; return x },
        adapter("batteries", \AppData.batteries) { b in
            var x = b; x.who = b.who.flipped; x.id = x.who.rawValue; return x
        },
        adapter("matches", \AppData.matches) { GameFlip.flip($0) },
    ]
}

// MARK: - Движок синхронизации

@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var pair: VDPair?
    @Published private(set) var status: SyncStatus = .notPaired
    @Published private(set) var busy = false
    @Published var message: String?

    private weak var store: Store?
    private let adapters = makeAdapters()
    private var cache: [String: [String: Data]] = [:]
    private var outbox: [String: SyncDoc] = [:]
    private var token = ""
    private var myId: String
    private var since: Int64
    private var lastCts: Double = 0
    private var loop: Task<Void, Never>?
    private var tick: Task<Void, Never>?
    private var kickTask: Task<Void, Never>?
    private var flushing = false
    private var pulling = false

    private let outboxURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("vdvoem-outbox.json")

    init() {
        let ud = UserDefaults.standard
        myId = ud.string(forKey: "vd.uid") ?? ""
        since = Int64(ud.integer(forKey: "vd.since"))
        if let d = ud.data(forKey: "vd.pair"), let p = try? JSONDecoder().decode(VDPair.self, from: d) {
            pair = p
        }
        if let d = try? Data(contentsOf: outboxURL),
           let list = try? JSONDecoder().decode([SyncDoc].self, from: d) {
            for x in list { outbox[key(x.kind, x.cid)] = x }
        }
        refreshStatus()
    }

    func attach(_ s: Store) {
        store = s
        guard let p = pair else { return }
        if isSeeded(p) { cache = snapshotAll(s.data) } else { seedAll() }
        start()
    }

    // MARK: Состояние

    var isPaired: Bool { pair != nil }
    private var flipOn: Bool { guard let p = pair else { return false }; return p.creator != myId }

    var statusText: String {
        switch status {
        case .notPaired: return "Пара не подключена"
        case .waitingPartner: return "Ждём партнёра по коду"
        case .connecting: return "Подключаемся…"
        case .live: return "На связи"
        case .offline: return "Нет связи — изменения сохранятся и отправятся позже"
        }
    }

    var partnerOnServer: VDMember? { pair?.members.first { $0.id != myId } }

    private func refreshStatus() {
        guard let p = pair else { status = .notPaired; return }
        if status == .notPaired { status = .connecting }
        if status == .live && p.members.count < 2 { status = .waitingPartner }
    }

    private func key(_ kind: String, _ cid: String) -> String { kind + "|" + cid }
    private func isSeeded(_ p: VDPair) -> Bool { UserDefaults.standard.bool(forKey: "vd.seeded." + p.id) }

    private func nextCts() -> Double {
        lastCts = max(Date().timeIntervalSince1970 * 1000, lastCts + 1)
        return lastCts
    }

    private func snapshotAll(_ d: AppData) -> [String: [String: Data]] {
        let f = flipOn
        var out: [String: [String: Data]] = [:]
        for a in adapters { out[a.kind] = a.snapshot(d, f) }
        return out
    }

    private func saveState() {
        let ud = UserDefaults.standard
        ud.set(Int(since), forKey: "vd.since")
        ud.set(myId, forKey: "vd.uid")
        if let p = pair, let d = try? JSONEncoder().encode(p) { ud.set(d, forKey: "vd.pair") }
        else { ud.removeObject(forKey: "vd.pair") }
    }

    private func saveOutbox() {
        if let d = try? JSONEncoder().encode(Array(outbox.values)) { try? d.write(to: outboxURL, options: .atomic) }
    }

    // MARK: Изменения данных → очередь отправки

    func dataChanged(_ d: AppData) {
        guard pair != nil else { return }
        let f = flipOn
        var any = false
        for a in adapters {
            let new = a.snapshot(d, f)
            let old = cache[a.kind] ?? [:]
            for (cid, bytes) in new where old[cid] != bytes {
                outbox[key(a.kind, cid)] = SyncDoc(cid: cid, kind: a.kind,
                                                   data: try? JSONDecoder().decode(JSONValue.self, from: bytes),
                                                   deleted: false, cts: nextCts())
                any = true
            }
            for cid in old.keys where new[cid] == nil {
                outbox[key(a.kind, cid)] = SyncDoc(cid: cid, kind: a.kind, data: nil, deleted: true, cts: nextCts())
                any = true
            }
            cache[a.kind] = new
        }
        if any { saveOutbox(); kick() }
    }

    private func seedAll() {
        guard let p = pair, let s = store else { return }
        let snaps = snapshotAll(s.data)
        for a in adapters {
            for (cid, bytes) in snaps[a.kind] ?? [:] {
                outbox[key(a.kind, cid)] = SyncDoc(cid: cid, kind: a.kind,
                                                   data: try? JSONDecoder().decode(JSONValue.self, from: bytes),
                                                   deleted: false, cts: nextCts())
            }
        }
        cache = snaps
        UserDefaults.standard.set(true, forKey: "vd.seeded." + p.id)
        saveOutbox()
    }

    /// Отправка с небольшой задержкой, чтобы не слать каждую набранную букву.
    private func kick() {
        kickTask?.cancel()
        kickTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if Task.isCancelled { return }
            await self?.flushSafe()
        }
    }

    // MARK: Сеть

    private static func errText(_ data: Data, _ code: Int) -> String {
        if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let m = o["message"] as? String, !m.isEmpty { return m }
        return "Ошибка сервера (\(code))"
    }

    static func human(_ error: Error) -> String {
        if case SyncError.server(let t) = error { return t }
        if error is URLError { return "Нет связи с сервером. Проверьте интернет и повторите." }
        return "Что-то пошло не так. Повторите позже."
    }

    private func raw(_ path: String, _ body: Data, bearer: String?) async throws -> (Data, Int) {
        guard let url = URL(string: VDConfig.base + path) else { throw SyncError.server("Неверный адрес сервера") }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.httpBody = body
        r.timeoutInterval = 25
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let b = bearer { r.setValue(b, forHTTPHeaderField: "Authorization") }
        let (d, resp) = try await URLSession.shared.data(for: r)
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }

    private func obj(_ dict: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: dict)) ?? Data("{}".utf8)
    }

    private func login() async throws {
        var email = Keychain.get("email")
        var pass = Keychain.get("pass")
        if email == nil || pass == nil {
            let e = UUID().uuidString.lowercased() + "@vdvoem.app"
            let p = UUID().uuidString + UUID().uuidString
            let name = String((store?.p.myName ?? "").prefix(40))
            let (d, code) = try await raw("/api/collections/vd_users/records",
                                          obj(["email": e, "password": p, "passwordConfirm": p, "name": name]),
                                          bearer: nil)
            guard (200..<300).contains(code) else { throw SyncError.server(Self.errText(d, code)) }
            Keychain.set("email", e)
            Keychain.set("pass", p)
            email = e
            pass = p
        }
        let (d, code) = try await raw("/api/collections/vd_users/auth-with-password",
                                      obj(["identity": email ?? "", "password": pass ?? ""]), bearer: nil)
        guard (200..<300).contains(code) else { throw SyncError.server(Self.errText(d, code)) }
        let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        token = o?["token"] as? String ?? ""
        let id = (o?["record"] as? [String: Any])?["id"] as? String ?? ""
        guard !token.isEmpty, !id.isEmpty else { throw SyncError.server("Не удалось войти на сервер") }
        myId = id
        saveState()
    }

    private func send(_ path: String, _ body: Data, retry: Bool = true) async throws -> Data {
        if token.isEmpty { try await login() }
        let (d, code) = try await raw(path, body, bearer: token)
        if code == 401 && retry {
            token = ""
            return try await send(path, body, retry: false)
        }
        guard (200..<300).contains(code) else { throw SyncError.server(Self.errText(d, code)) }
        return d
    }

    /// Загрузка фото на сервер (multipart). Возвращает id записи и имя файла.
    func upload(jpeg: Data, retry: Bool = true) async throws -> (id: String, file: String) {
        if token.isEmpty { try await login() }
        guard let url = URL(string: VDConfig.base + "/api/vd/media") else { throw SyncError.server("Неверный адрес сервера") }
        let boundary = "vd-" + UUID().uuidString
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 90
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.setValue(token, forHTTPHeaderField: "Authorization")
        let (d, resp) = try await URLSession.shared.upload(for: r, from: body)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && retry { token = ""; return try await upload(jpeg: jpeg, retry: false) }
        guard (200..<300).contains(code) else { throw SyncError.server(Self.errText(d, code)) }
        let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        guard let id = o?["id"] as? String, let file = o?["file"] as? String else { throw SyncError.server("Сервер не принял фото") }
        return (id, file)
    }

    // MARK: Пара

    private func setPair(_ data: Data) throws {
        let r = try JSONDecoder().decode(PairResponse.self, from: data)
        let was = pair?.id
        pair = r.pair
        saveState()
        if let p = r.pair {
            if was != p.id {
                since = 0
                cache = [:]
                saveState()
            }
            if !isSeeded(p) { seedAll() }
            refreshStatus()
            start()
        } else {
            stop()
            status = .notPaired
        }
    }

    private func perform(_ work: () async throws -> Void) async -> Bool {
        busy = true
        message = nil
        defer { busy = false }
        do { try await work(); return true }
        catch { message = Self.human(error); return false }
    }

    @discardableResult
    func createPair() async -> Bool {
        await perform { try self.setPair(try await self.send("/api/vd/pair/create", self.obj([:]))) }
    }

    @discardableResult
    func joinPair(_ code: String) async -> Bool {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard c.count >= 4 else { message = "Введите код партнёра"; return false }
        return await perform { try self.setPair(try await self.send("/api/vd/pair/join", self.obj(["code": c]))) }
    }

    @discardableResult
    func leavePair() async -> Bool {
        await perform {
            _ = try await self.send("/api/vd/pair/leave", self.obj([:]))
            self.stop()
            if let p = self.pair { UserDefaults.standard.removeObject(forKey: "vd.seeded." + p.id) }
            self.pair = nil
            self.outbox = [:]
            self.cache = [:]
            self.since = 0
            self.saveState()
            self.saveOutbox()
            self.status = .notPaired
        }
    }

    func refreshPair() async {
        guard pair != nil else { return }
        if let d = try? await send("/api/vd/pair/me", obj([:])),
           let r = try? JSONDecoder().decode(PairResponse.self, from: d), let p = r.pair, p != pair {
            pair = p
            saveState()
            if p.members.count >= 2 && status == .waitingPartner { status = .live }
        }
    }

    // MARK: Обмен данными

    func flushSafe() async {
        guard pair != nil, !flushing else { return }
        flushing = true
        defer { flushing = false }
        do { try await flush() }
        catch { if !(error is CancellationError) { status = .offline } }
    }

    private func flush() async throws {
        while pair != nil, !outbox.isEmpty {
            let batch = Array(outbox.values.sorted { $0.cts < $1.cts }.prefix(100))
            let body = try JSONEncoder().encode(["docs": batch])
            _ = try await send("/api/vd/push", body)
            for d in batch where outbox[key(d.kind, d.cid)]?.cts == d.cts {
                outbox[key(d.kind, d.cid)] = nil
            }
            saveOutbox()
        }
        if status == .offline || status == .connecting { status = (pair?.members.count ?? 0) >= 2 ? .live : .waitingPartner }
    }

    private func pull() async throws {
        guard pair != nil, !pulling else { return }
        pulling = true
        defer { pulling = false }
        var more = true
        while more {
            let res = try await send("/api/vd/pull", obj(["since": NSNumber(value: since)]))
            let r = try JSONDecoder().decode(PullResponse.self, from: res)
            applyRemote(r.docs)
            if r.cursor > Double(since) { since = Int64(r.cursor) }
            saveState()
            more = r.more
        }
        status = (pair?.members.count ?? 0) >= 2 ? .live : .waitingPartner
    }

    private func applyRemote(_ docs: [SyncDoc]) {
        guard let store = store, !docs.isEmpty else { return }
        var changes: [String: [(String, Data?)]] = [:]
        let enc = JSONEncoder()
        for doc in docs {
            guard adapters.contains(where: { $0.kind == doc.kind }) else { continue }
            let k = key(doc.kind, doc.cid)
            if let pending = outbox[k] {
                if pending.cts > doc.cts { continue }   // моя правка новее
                outbox[k] = nil                          // удалённая новее или это моё же эхо
            }
            if doc.deleted {
                changes[doc.kind, default: []].append((doc.cid, nil))
            } else if let v = doc.data, let bytes = try? enc.encode(v) {
                changes[doc.kind, default: []].append((doc.cid, bytes))
            }
        }
        saveOutbox()
        guard !changes.isEmpty else { return }
        var d = store.data
        let f = flipOn
        for a in adapters {
            guard let list = changes[a.kind] else { continue }
            a.apply(&d, list, f)
            cache[a.kind] = a.snapshot(d, f)
        }
        store.data = d
    }

    // MARK: Жизненный цикл и real-time

    func start() {
        guard pair != nil, loop == nil else { return }
        loop = Task { [weak self] in await self?.runLoop() }
        tick = Task { [weak self] in await self?.runTicker() }
    }

    func stop() {
        loop?.cancel(); loop = nil
        tick?.cancel(); tick = nil
        kickTask?.cancel()
    }

    /// Вызывается, когда приложение снова на экране.
    func resume() {
        guard pair != nil else { return }
        if loop == nil { start() }
        Task { await self.flushSafe(); try? await self.pull() }
    }

    private func runLoop() async {
        var backoff = 2.0
        while !Task.isCancelled {
            do {
                if status != .live { status = .connecting }
                try await flush()
                try await pull()
                backoff = 2
                try await listen()
            } catch {
                if Task.isCancelled { return }
                status = .offline
            }
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            backoff = min(backoff * 2, 30)
        }
    }

    /// Резервный опрос раз в 10 секунд: догоняет изменения, если соединение молчит.
    private func runTicker() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            if (pair?.members.count ?? 0) < 2 { await refreshPair() }
            if !outbox.isEmpty { await flushSafe() }
            else { try? await pull() }
        }
    }

    /// Живое соединение PocketBase (SSE): сервер сам сообщает о новых записях пары.
    private func listen() async throws {
        guard let url = URL(string: VDConfig.base + "/api/realtime") else { return }
        var r = URLRequest(url: url)
        r.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        r.timeoutInterval = 3600
        let (bytes, resp) = try await URLSession.shared.bytes(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw SyncError.server("realtime") }
        var event = ""
        for try await line in bytes.lines {
            if line.hasPrefix("event:") {
                event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if event == "PB_CONNECT" {
                    guard let o = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                          let cid = o["clientId"] as? String else { continue }
                    _ = try await send("/api/realtime", obj(["clientId": cid, "subscriptions": ["vd_docs"]]))
                    try await pull()
                } else if event == "vd_docs" {
                    try await pull()
                }
            }
        }
    }
}

// MARK: - Экран «Пара» (онбординг и настройки)

struct PairPanel: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @State private var code = ""
    @State private var confirmLeave = false

    var body: some View {
        VStack(spacing: 14) {
            if let p = sync.pair {
                paired(p)
            } else {
                unpaired
            }
            if let m = sync.message {
                Text(m).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: sync.pair)
    }

    private var unpaired: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                Text("Один из вас создаёт пару").font(.subheadline.weight(.semibold))
                Button {
                    Task { await sync.createPair() }
                } label: {
                    HStack {
                        if sync.busy { ProgressView() }
                        Text("Создать код").font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sync.busy)
            }
            .padding(16).frame(maxWidth: .infinity).card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Второй вводит код партнёра").font(.subheadline.weight(.semibold))
                TextField("ABC123", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.title3.monospaced())
                Button {
                    Task { await sync.joinPair(code) }
                } label: {
                    Text("Подключиться").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(sync.busy || code.trimmingCharacters(in: .whitespaces).count < 4)
            }
            .padding(16).card()
        }
    }

    private func paired(_ p: VDPair) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text("КОД ПАРЫ").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1)
                Text(p.code).font(.system(size: 40, weight: .bold, design: .monospaced)).tracking(6)
                if p.members.count < 2 {
                    ShareLink(item: "Присоединяйся ко мне в «Вдвоём». Мой код: \(p.code)") {
                        Label("Отправить код", systemImage: "square.and.arrow.up")
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity).padding(20).card()

            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(sync.statusText).font(.subheadline)
                Spacer()
            }
            .padding(16).card()

            Button(role: .destructive) { confirmLeave = true } label: {
                Text("Выйти из пары").frame(maxWidth: .infinity)
            }
            .confirmationDialog("Выйти из пары? Данные на этом телефоне останутся, но обмен с партнёром остановится.",
                                isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await sync.leavePair() } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    private var color: Color {
        switch sync.status {
        case .live: return .green
        case .waitingPartner, .connecting: return .orange
        case .offline: return .red
        case .notPaired: return .gray
        }
    }
}
