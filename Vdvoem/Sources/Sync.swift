import SwiftUI
import Security
import AuthenticationServices

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
    /// Как устройство вошло: "anon" (безымянный аккаунт), "email" или "yandex".
    @Published private(set) var accountKind: String = UserDefaults.standard.string(forKey: "vd.acc.kind") ?? "anon"
    @Published private(set) var accountEmail: String = UserDefaults.standard.string(forKey: "vd.acc.email") ?? ""

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

    private func raw(_ path: String, _ body: Data, bearer: String?, method: String = "POST") async throws -> (Data, Int) {
        guard let url = URL(string: VDConfig.base + path) else { throw SyncError.server("Неверный адрес сервера") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        if method != "GET" { r.httpBody = body }
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
        if accountKind == "yandex", (Keychain.get("pass") ?? "").isEmpty {
            // Аккаунт Яндекса без пароля: продлеваем сохранённый токен.
            let old = Keychain.get("vdtoken") ?? ""
            let (d, code) = try await raw("/api/collections/vd_users/auth-refresh", Data("{}".utf8), bearer: old)
            guard (200..<300).contains(code),
                  let o = try JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let t = o["token"] as? String, !t.isEmpty else {
                throw SyncError.server("Вход через Яндекс устарел — войдите снова в «Настройки → Аккаунт».")
            }
            token = t
            Keychain.set("vdtoken", t)
            if let id = (o["record"] as? [String: Any])?["id"] as? String { myId = id; saveState() }
            return
        }
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


    // MARK: Аккаунт: почта и Яндекс

    var isSignedIn: Bool { accountKind != "anon" }
    var accountTitle: String { accountKind == "yandex" ? "Яндекс" : "Почта" }

    private func setAccount(kind: String, email: String) {
        accountKind = kind
        accountEmail = email
        UserDefaults.standard.set(kind, forKey: "vd.acc.kind")
        UserDefaults.standard.set(email, forKey: "vd.acc.email")
    }

    private func checkEmail(_ email: String, _ pass: String) -> String? {
        if !email.contains("@") || !email.contains(".") { return "Проверьте адрес почты" }
        if pass.count < 8 { return "Пароль — не короче 8 символов" }
        return nil
    }

    /// Создать аккаунт: безымянный аккаунт телефона получает почту и пароль, пара и данные остаются на месте.
    func registerEmail(_ rawEmail: String, _ pass: String) async -> String? {
        let email = rawEmail.trimmingCharacters(in: .whitespaces).lowercased()
        if let e = checkEmail(email, pass) { return e }
        if isSignedIn { return "Вы уже вошли. Сначала выйдите из аккаунта." }
        busy = true
        defer { busy = false }
        do {
            if token.isEmpty { try await login() }
            let oldPass = Keychain.get("pass") ?? ""
            let (d, code) = try await raw("/api/collections/vd_users/records/" + myId,
                                          obj(["email": email, "password": pass, "passwordConfirm": pass, "oldPassword": oldPass]),
                                          bearer: token, method: "PATCH")
            if code == 400 { return "Эта почта уже занята или указана неверно. Если аккаунт ваш — откройте вкладку «Вход»." }
            guard (200..<300).contains(code) else { return Self.errText(d, code) }
            Keychain.set("email", email)
            Keychain.set("pass", pass)
            token = ""
            try await login()
            setAccount(kind: "email", email: email)
            return nil
        } catch { return Self.human(error) }
    }

    /// Войти в существующий аккаунт по почте и паролю.
    func loginEmail(_ rawEmail: String, _ pass: String) async -> String? {
        let email = rawEmail.trimmingCharacters(in: .whitespaces).lowercased()
        if email.isEmpty || pass.isEmpty { return "Введите почту и пароль" }
        busy = true
        defer { busy = false }
        do {
            let (d, code) = try await raw("/api/collections/vd_users/auth-with-password",
                                          obj(["identity": email, "password": pass]), bearer: nil)
            if code == 400 { return "Неверная почта или пароль" }
            guard (200..<300).contains(code) else { return Self.errText(d, code) }
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            let t = o?["token"] as? String ?? ""
            let id = (o?["record"] as? [String: Any])?["id"] as? String ?? ""
            guard !t.isEmpty, !id.isEmpty else { return "Не удалось войти" }
            try await switchAccount(token: t, id: id, email: email, pass: pass, kind: "email")
            return nil
        } catch { return Self.human(error) }
    }

    /// Войти через Яндекс (окно входа), при первом входе создаётся аккаунт.
    func loginYandex() async -> String? {
        busy = true
        defer { busy = false }
        do {
            guard let mURL = URL(string: VDConfig.base + "/api/collections/vd_users/auth-methods") else { return "Неверный адрес сервера" }
            let (md, mresp) = try await URLSession.shared.data(from: mURL)
            guard (mresp as? HTTPURLResponse)?.statusCode == 200,
                  let mo = try JSONSerialization.jsonObject(with: md) as? [String: Any] else { return "Сервер не ответил" }
            let providers = ((mo["oauth2"] as? [String: Any])?["providers"] as? [[String: Any]])
                ?? (mo["authProviders"] as? [[String: Any]]) ?? []
            guard let p = providers.first(where: { ($0["name"] as? String) == "yandex" }),
                  let authURL = p["authURL"] as? String, let state = p["state"] as? String,
                  let verifier = p["codeVerifier"] as? String else {
                return "Вход через Яндекс на сервере пока не включён. Войдите по почте."
            }
            let redirect = VDConfig.base + "/api/vd/oauth-callback"
            let enc = redirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? redirect
            guard let url = URL(string: authURL + enc) else { return "Неверный адрес входа" }
            let cb = try await OAuthWeb.run(url: url)
            let items = URLComponents(url: cb, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func q(_ n: String) -> String { items.first { $0.name == n }?.value ?? "" }
            if !q("error").isEmpty { return q("error") == "access_denied" ? "Вход отменён" : "Ошибка входа: \(q("error"))" }
            guard q("state") == state, !q("code").isEmpty else { return "Вход отменён или устарел — попробуйте ещё раз" }
            let (d, code) = try await raw("/api/collections/vd_users/auth-with-oauth2",
                                          obj(["provider": "yandex", "code": q("code"), "codeVerifier": verifier, "redirectURL": redirect]),
                                          bearer: nil)
            guard (200..<300).contains(code) else { return "Яндекс (вход): " + Self.errText(d, code) }
            let o = try JSONSerialization.jsonObject(with: d) as? [String: Any]
            let t = o?["token"] as? String ?? ""
            let rec = o?["record"] as? [String: Any]
            let meta = o?["meta"] as? [String: Any]
            let id = rec?["id"] as? String ?? ""
            guard !t.isEmpty, !id.isEmpty else { return "Не удалось войти" }
            var email = (rec?["email"] as? String) ?? (meta?["email"] as? String) ?? ""
            var pass = ""
            var name = (rec?["name"] as? String) ?? (meta?["name"] as? String) ?? ""
            // Пароль устройства (по нему приложение само перезаходит). Если сервер его не принял — живём на токене с продлением.
            let candidate = UUID().uuidString + UUID().uuidString
            if let (sd, sc) = try? await raw("/api/vd/account/setpass", obj(["password": candidate]), bearer: t),
               (200..<300).contains(sc),
               let so = try? JSONSerialization.jsonObject(with: sd) as? [String: Any] {
                pass = candidate
                if let e = so["email"] as? String, !e.isEmpty { email = e }
                if let n = so["name"] as? String, !n.isEmpty { name = n }
            }
            if email.isEmpty { email = id + "@oauth.vdvoem.app" }
            if let s = store, !name.isEmpty, s.p.myName.trimmingCharacters(in: .whitespaces).isEmpty {
                s.data.profile.myName = String(name.prefix(40))
            }
            do { try await switchAccount(token: t, id: id, email: email, pass: pass, kind: "yandex") }
            catch { return "Привязка пары: " + Self.human(error) }
            return nil
        } catch { return Self.human(error) }
    }

    /// Переключиться на другой аккаунт: пара берётся с сервера; пара безымянного аккаунта переезжает, если у нового её нет.
    private func switchAccount(token t: String, id: String, email: String, pass: String, kind: String) async throws {
        let oldEmail = Keychain.get("email") ?? ""
        let oldPass = Keychain.get("pass") ?? ""
        let wasAnon = accountKind == "anon"
        let before = pair?.id
        Keychain.set("email", email)
        Keychain.set("pass", pass)
        if pass.isEmpty { Keychain.set("vdtoken", t) } else { Keychain.remove("vdtoken") }
        token = t
        myId = id
        if wasAnon, oldEmail.hasSuffix("@vdvoem.app"), !oldPass.isEmpty {
            _ = try? await send("/api/vd/account/adopt", obj(["email": oldEmail, "password": oldPass]))
        }
        setAccount(kind: kind, email: email)
        let d = try await send("/api/vd/pair/me", obj([:]))
        let r = try JSONDecoder().decode(PairResponse.self, from: d)
        if r.pair?.id != before {
            stop()
            outbox = [:]
            cache = [:]
            since = 0
            saveOutbox()
        }
        try setPair(d)
        if pair != nil, cache.isEmpty, let s = store { cache = snapshotAll(s.data) }
    }

    /// Выйти из аккаунта: на телефоне остаются данные, но пара отключается; потом можно войти снова.
    func signOut() {
        stop()
        Keychain.remove("email")
        Keychain.remove("pass")
        Keychain.remove("vdtoken")
        token = ""
        myId = ""
        if let p = pair { UserDefaults.standard.removeObject(forKey: "vd.seeded." + p.id) }
        pair = nil
        outbox = [:]
        cache = [:]
        since = 0
        saveState()
        saveOutbox()
        status = .notPaired
        setAccount(kind: "anon", email: "")
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
        .animation(Motion.curve(0.25), value: sync.pair)
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
                Text("Код пары").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                Text(p.code).font(.system(size: 40, weight: .semibold, design: .monospaced)).tracking(6)
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


// MARK: - Окно входа через Яндекс

@MainActor
final class OAuthWeb: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: OAuthWeb?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL) async throws -> URL {
        let w = OAuthWeb()
        current = w
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "vdvoem") { cb, err in
                if let cb { cont.resume(returning: cb) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: SyncError.server("Вход отменён"))
                } else {
                    cont.resume(throwing: SyncError.server(err?.localizedDescription ?? "Не удалось войти"))
                }
            }
            s.presentationContextProvider = w
            s.prefersEphemeralWebBrowserSession = false
            w.session = s
            if !s.start() { cont.resume(throwing: SyncError.server("Не удалось открыть окно входа")) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
