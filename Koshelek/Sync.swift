import Foundation
import Security
import SwiftData
import AuthenticationServices
import SwiftUI

// MARK: - Текущее пространство (личный или семейный бюджет)

enum Space {
    static let localID = "local"
    static var current: String {
        get { UserDefaults.standard.string(forKey: "space") ?? localID }
        set { UserDefaults.standard.set(newValue, forKey: "space") }
    }
}

// MARK: - Синхронизируемые записи

protocol Synced: PersistentModel {
    static var kind: String { get }
    var uid: UUID { get set }
    var space: String { get set }
    var updatedAt: Date { get set }
    var dirty: Bool { get set }
    var removed: Bool { get set }
    var author: String { get set }
    func payload() -> [String: Any]
    func apply(_ d: [String: Any])
}

extension Synced {
    /// Удаление, которое дойдёт до других устройств.
    func softDelete() {
        removed = true
        dirty = true
        updatedAt = Date()
    }
    var isLive: Bool { !removed && (space == Space.current || (space.isEmpty && Space.current == Space.localID)) }
}

extension Array where Element: Synced {
    var live: [Element] { filter { $0.isLive } }
}

extension ModelContext {
    func live<T: Synced>(_ type: T.Type) -> [T] {
        ((try? fetch(FetchDescriptor<T>())) ?? []).live
    }

    /// Сохранить с пометкой изменённых записей для синхронизации и автоправилами копилок.
    @MainActor
    func commit() {
        let now = Date()
        let me = SyncEngine.shared.userID
        var autoNotes: [String] = []
        for m in insertedModelsArray {
            if let t = m as? Tx, t.space.isEmpty { autoNotes += Savings.applyRules(to: t, ctx: self) }
        }
        for m in insertedModelsArray + changedModelsArray {
            guard let s = m as? any Synced else { continue }
            if s.space.isEmpty { s.space = Space.current }
            if s.author.isEmpty && !me.isEmpty && insertedModelsArray.contains(where: { $0.persistentModelID == m.persistentModelID }) { s.author = me }
            s.dirty = true
            s.updatedAt = now
        }
        do { try save() } catch { print("save error", error) }
        if !autoNotes.isEmpty { Router.shared.say(autoNotes.joined(separator: " · ")) }
        SyncEngine.shared.schedulePush()
        WidgetStore.shared.scheduleRefresh()
    }
}

// Значения из JSON
func jNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? 0 }
    return 0
}
func jStr(_ v: Any?) -> String { (v as? String) ?? "" }
func jBool(_ v: Any?) -> Bool { (v as? Bool) ?? ((v as? NSNumber)?.boolValue ?? false) }
func jDate(_ v: Any?) -> Date { Date(timeIntervalSince1970: jNum(v)) }
func jUUID(_ v: Any?) -> UUID? { (v as? String).flatMap { UUID(uuidString: $0) } }
func jsonObject(_ data: Data) -> Any { (try? JSONSerialization.jsonObject(with: data)) ?? NSNull() }
func jsonData(_ obj: Any?) -> Data {
    guard let obj, !(obj is NSNull), JSONSerialization.isValidJSONObject(obj) else { return Data() }
    return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
}

extension Tx: Synced {
    static var kind: String { "tx" }
    func payload() -> [String: Any] {
        var d: [String: Any] = ["type": kindRaw, "amount": amount, "cat": cat, "note": note,
                                "date": date.timeIntervalSince1970, "created": created.timeIntervalSince1970]
        if let accID { d["acc"] = accID.uuidString }
        if let toID { d["to"] = toID.uuidString }
        if let recID { d["rec"] = recID.uuidString }
        return d
    }
    func apply(_ d: [String: Any]) {
        kindRaw = jStr(d["type"]).isEmpty ? "exp" : jStr(d["type"])
        amount = jNum(d["amount"]); cat = jStr(d["cat"]); note = jStr(d["note"])
        date = jDate(d["date"]); created = jDate(d["created"])
        accID = jUUID(d["acc"]); toID = jUUID(d["to"]); recID = jUUID(d["rec"])
    }
}

extension Account: Synced {
    static var kind: String { "acc" }
    func payload() -> [String: Any] { ["name": name, "start": start, "hex": hex, "created": created.timeIntervalSince1970] }
    func apply(_ d: [String: Any]) {
        name = jStr(d["name"]); start = jNum(d["start"]); hex = jStr(d["hex"]).isEmpty ? hex : jStr(d["hex"]); created = jDate(d["created"])
    }
}

extension Debt: Synced {
    static var kind: String { "debt" }
    func payload() -> [String: Any] {
        ["type": typeRaw, "dirIn": dirIn, "name": name, "lender": lender, "total": total, "payment": payment, "n": n,
         "first": first.timeIntervalSince1970, "rate": rate, "created": created.timeIntervalSince1970,
         "payments": jsonObject(paymentsData), "extras": jsonObject(extraData)]
    }
    func apply(_ d: [String: Any]) {
        typeRaw = jStr(d["type"]); dirIn = jBool(d["dirIn"]); name = jStr(d["name"]); lender = jStr(d["lender"])
        total = jNum(d["total"]); payment = jNum(d["payment"]); n = max(1, Int(jNum(d["n"])))
        first = jDate(d["first"]); rate = jNum(d["rate"]); created = jDate(d["created"])
        paymentsData = jsonData(d["payments"]); extraData = jsonData(d["extras"])
    }
}

extension Recurring: Synced {
    static var kind: String { "rec" }
    func payload() -> [String: Any] {
        ["name": name, "amount": amount, "type": kindRaw, "cat": cat, "day": day, "yearly": yearly, "month": month,
         "created": created.timeIntervalSince1970]
    }
    func apply(_ d: [String: Any]) {
        name = jStr(d["name"]); amount = jNum(d["amount"]); kindRaw = jStr(d["type"]).isEmpty ? "exp" : jStr(d["type"])
        cat = jStr(d["cat"]); day = max(1, Int(jNum(d["day"]))); yearly = jBool(d["yearly"]); month = max(1, Int(jNum(d["month"])))
        created = jDate(d["created"])
    }
}

extension Goal: Synced {
    static var kind: String { "goal" }
    func payload() -> [String: Any] {
        var d: [String: Any] = ["name": name, "target": target, "hex": hex, "created": created.timeIntervalSince1970,
                                "log": jsonObject(logData), "autoPercent": autoPercent, "roundUp": roundUp, "symbol": symbol]
        if let deadline { d["deadline"] = deadline.timeIntervalSince1970 }
        return d
    }
    func apply(_ d: [String: Any]) {
        name = jStr(d["name"]); target = jNum(d["target"]); hex = jStr(d["hex"]).isEmpty ? hex : jStr(d["hex"])
        created = jDate(d["created"]); logData = jsonData(d["log"])
        deadline = d["deadline"] == nil ? nil : jDate(d["deadline"])
        autoPercent = jNum(d["autoPercent"]); roundUp = Int(jNum(d["roundUp"]))
        symbol = jStr(d["symbol"]).isEmpty ? "banknote.fill" : jStr(d["symbol"])
    }
}

// MARK: - Пространства

struct Member: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let email: String
    var display: String { name.isEmpty ? email : name }
}

struct SpaceInfo: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let code: String
    let owner: String
    let personal: Bool
    let members: [Member]
}

// MARK: - Движок синхронизации

@MainActor
final class SyncEngine: ObservableObject {
    static let shared = SyncEngine()

    enum State: Equatable { case off, idle, syncing, error(String) }

    @Published var state: State = .off
    @Published var lastSync: Date? = UserDefaults.standard.object(forKey: "lastSync") as? Date
    @Published var spaces: [SpaceInfo] = []
    @Published var userName = UserDefaults.standard.string(forKey: "userName") ?? ""
    @Published var userEmail = UserDefaults.standard.string(forKey: "userEmail") ?? ""
    @Published var spaceVersion = 0

    /// Сервер Копилки по умолчанию — вшит в приложение, чтобы друзьям и семье ничего не вводить.
    static let defaultServer = ServerDefaults.url

    var server: String {
        get {
            let s = UserDefaults.standard.string(forKey: "server") ?? ""
            return s.isEmpty ? Self.defaultServer : s
        }
        set { UserDefaults.standard.set(newValue, forKey: "server") }
    }
    var userID: String { UserDefaults.standard.string(forKey: "userID") ?? "" }
    var token: String? { Keychain.get("pb-token") }
    var loggedIn: Bool { token != nil && !server.isEmpty }
    var currentSpace: SpaceInfo? { spaces.first { $0.id == Space.current } }
    var isShared: Bool { (currentSpace?.members.count ?? 0) > 1 }

    private var pushTask: Task<Void, Never>?
    private var running = false

    init() {
        if let d = UserDefaults.standard.data(forKey: "spaces"), let s = try? JSONDecoder().decode([SpaceInfo].self, from: d) { spaces = s }
        state = loggedIn ? .idle : .off
    }

    func memberName(_ id: String) -> String? {
        guard !id.isEmpty, id != userID else { return nil }
        return currentSpace?.members.first { $0.id == id }?.display
    }

    // MARK: Сеть

    struct APIError: LocalizedError {
        let message: String
        let status: Int
        var errorDescription: String? { message }
    }

    static func normalize(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return u }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    private func call(_ path: String, _ body: [String: Any]? = nil, auth: Bool = true, retry: Bool = true) async throws -> [String: Any] {
        guard let url = URL(string: server + path) else { throw APIError(message: "Неверный адрес сервера", status: 0) }
        var req = URLRequest(url: url)
        req.httpMethod = body == nil ? "GET" : "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let t = token { req.setValue(t, forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw APIError(message: "Нет связи с сервером", status: 0) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        if code == 401 && auth && retry {
            if await refreshToken() { return try await call(path, body, auth: auth, retry: false) }
            logout(keepData: true)
            throw APIError(message: "Сессия истекла — войдите снова", status: 401)
        }
        guard (200..<300).contains(code) else {
            var msg = jStr(obj["message"])
            if let fields = obj["data"] as? [String: Any] {
                for (k, v) in fields {
                    let fm = jStr((v as? [String: Any])?["message"])
                    let c = jStr((v as? [String: Any])?["code"])
                    if c == "validation_not_unique" && k == "email" { msg = "Этот email уже зарегистрирован — войдите" ; break }
                    if !fm.isEmpty { msg = "\(k): \(fm)" }
                }
            }
            if code == 400 && path.contains("auth-with-password") { msg = "Неверная почта или пароль" }
            throw APIError(message: msg.isEmpty ? "Ошибка сервера (\(code))" : msg, status: code)
        }
        return obj
    }

    private func refreshToken() async -> Bool {
        guard token != nil else { return false }
        guard let obj = try? await call("/api/collections/users/auth-refresh", [:], auth: true, retry: false),
              let t = obj["token"] as? String else { return false }
        Keychain.set("pb-token", t)
        return true
    }

    func ping(_ address: String) async -> Bool {
        let s = Self.normalize(address)
        guard let url = URL(string: s + "/api/kp/ping") else { return false }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(data: data, encoding: .utf8)?.contains("kopilka") ?? false
    }

    // MARK: Вход

    func register(server addr: String, name: String, email: String, password: String, ctx: ModelContext) async throws {
        server = Self.normalize(addr)
        _ = try await call("/api/collections/users/records",
                           ["email": email, "password": password, "passwordConfirm": password, "name": name, "emailVisibility": true], auth: false)
        try await login(server: addr, email: email, password: password, ctx: ctx)
    }

    func login(server addr: String, email: String, password: String, ctx: ModelContext) async throws {
        server = Self.normalize(addr)
        let obj = try await call("/api/collections/users/auth-with-password", ["identity": email, "password": password], auth: false)
        // Записи, сделанные до входа, переезжают в личный бюджет
        try await finishLogin(obj, ctx: ctx)
    }

    // MARK: Вход через Google (OAuth2 в PocketBase)

    struct OAuthProvider {
        let authURL: String
        let codeVerifier: String
        let state: String
    }

    /// Какие сервисы входа включены на сервере: google, yandex, apple.
    func oauthProviders(_ address: String) async -> [String: OAuthProvider] {
        let s = Self.normalize(address)
        guard let url = URL(string: s + "/api/collections/users/auth-methods"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = jsonObject(data) as? [String: Any] else { return [:] }
        let list = ((obj["oauth2"] as? [String: Any])?["providers"] as? [[String: Any]]) ?? (obj["authProviders"] as? [[String: Any]]) ?? []
        var out: [String: OAuthProvider] = [:]
        for g in list {
            let auth = jStr(g["authURL"]).isEmpty ? jStr(g["authUrl"]) : jStr(g["authURL"])
            out[jStr(g["name"])] = OAuthProvider(authURL: auth, codeVerifier: jStr(g["codeVerifier"]), state: jStr(g["state"]))
        }
        return out
    }

    @MainActor
    func loginWithOAuth(_ provider: String, server addr: String, ctx: ModelContext) async throws {
        let base = Self.normalize(addr)
        guard let p = await oauthProviders(base)[provider] else {
            throw APIError(message: "На сервере не включён этот способ входа", status: 0)
        }
        let redirect = base + "/api/kp/oauth-callback"
        let enc = redirect.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? redirect
        guard let url = URL(string: p.authURL + enc) else { throw APIError(message: "Неверный адрес входа", status: 0) }
        let callback = try await OAuthWeb.run(url: url)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ n: String) -> String { items.first { $0.name == n }?.value ?? "" }
        if !q("error").isEmpty {
            if q("error") == "user_cancelled_authorize" || q("error") == "access_denied" { throw APIError(message: "Вход отменён", status: -1) }
            throw APIError(message: "Ошибка входа: \(q("error"))", status: 0)
        }
        guard q("state") == p.state, !q("code").isEmpty else { throw APIError(message: "Вход отменён или устарел — попробуйте ещё раз", status: 0) }
        server = base
        let obj = try await call("/api/collections/users/auth-with-oauth2",
                                 ["provider": provider, "code": q("code"), "codeVerifier": p.codeVerifier, "redirectURL": redirect], auth: false)
        try await finishLogin(obj, ctx: ctx)
    }

    private func finishLogin(_ obj: [String: Any], ctx: ModelContext) async throws {
        guard let t = obj["token"] as? String, let rec = obj["record"] as? [String: Any] else {
            throw APIError(message: "Сервер вернул неожиданный ответ", status: 0)
        }
        Keychain.set("pb-token", t)
        UserDefaults.standard.set(jStr(rec["id"]), forKey: "userID")
        var name = jStr(rec["name"])
        if name.isEmpty, let meta = obj["meta"] as? [String: Any] { name = jStr(meta["name"]) }
        userName = name; userEmail = jStr(rec["email"])
        UserDefaults.standard.set(userName, forKey: "userName")
        UserDefaults.standard.set(userEmail, forKey: "userEmail")
        try await loadSpaces()
        if let personal = spaces.first(where: { $0.personal && $0.owner == userID }) {
            adoptLocal(into: personal.id, ctx: ctx)
            switchTo(personal.id)
        }
        state = .idle
        await refreshAIStatus()
        await sync(ctx: ctx)
        await joinPending(ctx: ctx)
    }

    /// Вступить в бюджет по коду из ссылки-приглашения, если он ждёт входа.
    func joinPending(ctx: ModelContext) async {
        guard let code = UserDefaults.standard.string(forKey: "pendingJoin"), !code.isEmpty, loggedIn else { return }
        UserDefaults.standard.removeObject(forKey: "pendingJoin")
        if spaces.contains(where: { $0.code.uppercased() == code }) { return }
        do {
            try await join(code: code, ctx: ctx)
            Router.shared.say("Вы в общем бюджете «\(currentSpace?.name ?? "Семья")»")
            Haptic.success()
        } catch {
            Router.shared.say("Не удалось вступить: \(error.localizedDescription)")
        }
    }

    /// Включён ли на сервере общий ИИ (тогда ключ в приложении не нужен).
    func refreshAIStatus() async {
        guard let obj = try? await call("/api/kp/ai/status") else { return }
        UserDefaults.standard.set(jBool(obj["enabled"]), forKey: "serverAI")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "serverAICheck")
        objectWillChange.send()
    }

    func logout(keepData: Bool) {
        UserDefaults.standard.set(false, forKey: "serverAI")
        Keychain.set("pb-token", nil)
        state = .off
        objectWillChange.send()
    }

    private func adoptLocal(into id: String, ctx: ModelContext) {
        func move<T: Synced>(_ t: T.Type) {
            for m in (try? ctx.fetch(FetchDescriptor<T>())) ?? [] where m.space.isEmpty || m.space == Space.localID {
                m.space = id; m.dirty = true; m.updatedAt = Date()
                if m.author.isEmpty { m.author = userID }
            }
        }
        move(Tx.self); move(Account.self); move(Debt.self); move(Recurring.self); move(Goal.self)
        if let c = UserDefaults.standard.data(forKey: "cats:\(Space.localID)"), UserDefaults.standard.data(forKey: "cats:\(id)") == nil {
            UserDefaults.standard.set(c, forKey: "cats:\(id)")
            UserDefaults.standard.set(true, forKey: "prefsDirty:\(id)")
        }
        if let l = UserDefaults.standard.data(forKey: "catLimits:\(Space.localID)"), UserDefaults.standard.data(forKey: "catLimits:\(id)") == nil {
            UserDefaults.standard.set(l, forKey: "catLimits:\(id)")
            UserDefaults.standard.set(true, forKey: "prefsDirty:\(id)")
        }
        let b = UserDefaults.standard.double(forKey: "budget:\(Space.localID)")
        if b > 0 && UserDefaults.standard.double(forKey: "budget:\(id)") == 0 {
            UserDefaults.standard.set(b, forKey: "budget:\(id)")
            UserDefaults.standard.set(true, forKey: "prefsDirty:\(id)")
        }
        try? ctx.save()
    }

    // MARK: Пространства

    func loadSpaces() async throws {
        let obj = try await call("/api/kp/spaces", [:])
        let arr = obj["spaces"] as? [[String: Any]] ?? []
        spaces = arr.compactMap(Self.parseSpace)
        if let d = try? JSONEncoder().encode(spaces) { UserDefaults.standard.set(d, forKey: "spaces") }
        if !spaces.contains(where: { $0.id == Space.current }), let p = spaces.first(where: { $0.personal }) { switchTo(p.id) }
    }

    static func parseSpace(_ o: [String: Any]) -> SpaceInfo? {
        guard let id = o["id"] as? String else { return nil }
        let ms = (o["members"] as? [[String: Any]] ?? []).map { Member(id: jStr($0["id"]), name: jStr($0["name"]), email: jStr($0["email"])) }
        return SpaceInfo(id: id, name: jStr(o["name"]), code: jStr(o["code"]), owner: jStr(o["owner"]), personal: jBool(o["personal"]), members: ms)
    }

    func switchTo(_ id: String) {
        let old = Space.current
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: "budget"), forKey: "budget:\(old)")
        Space.current = id
        CategoryPrefs.shared.reload()
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: "budget:\(id)"), forKey: "budget")
        spaceVersion += 1
    }

    func createSpace(name: String) async throws -> SpaceInfo? {
        let obj = try await call("/api/kp/space/create", ["name": name])
        try await loadSpaces()
        return (obj["space"] as? [String: Any]).flatMap(Self.parseSpace)
    }

    func join(code: String, ctx: ModelContext) async throws {
        let obj = try await call("/api/kp/space/join", ["code": code])
        try await loadSpaces()
        if let s = (obj["space"] as? [String: Any]).flatMap(Self.parseSpace) {
            switchTo(s.id)
            await sync(ctx: ctx)
        }
    }

    func leave(_ id: String) async throws {
        _ = try await call("/api/kp/space/leave", ["space": id])
        try await loadSpaces()
    }

    func update(_ id: String, name: String? = nil, newCode: Bool = false, kick: String? = nil) async throws {
        var b: [String: Any] = ["space": id]
        if let name { b["name"] = name }
        if newCode { b["newCode"] = true }
        if let kick { b["kick"] = kick }
        _ = try await call("/api/kp/space/update", b)
        try await loadSpaces()
    }

    // MARK: Бюджет (лимит) — тоже синхронизируется

    func setBudget(_ v: Double) {
        UserDefaults.standard.set(v, forKey: "budget")
        UserDefaults.standard.set(v, forKey: "budget:\(Space.current)")
        UserDefaults.standard.set(true, forKey: "prefsDirty:\(Space.current)")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefsTs:\(Space.current)")
        schedulePush()
    }

    // MARK: Синхронизация

    func schedulePush() {
        guard loggedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.sync(ctx: Store.container.mainContext)
        }
    }

    func sync(ctx: ModelContext) async {
        guard loggedIn, !running, !TestData.isActive else { return }
        let space = Space.current
        guard space != Space.localID else { return }
        running = true
        state = .syncing
        defer { running = false }
        do {
            ctx.commitIfNeeded()
            try await push(space: space, ctx: ctx)
            try await pull(space: space, ctx: ctx)
            lastSync = Date()
            UserDefaults.standard.set(lastSync, forKey: "lastSync")
            state = .idle
            if spaces.isEmpty || Int.random(in: 0..<10) == 0 { try? await loadSpaces() }
            let last = UserDefaults.standard.double(forKey: "serverAICheck")
            if Date().timeIntervalSince1970 - last > 1800 { await refreshAIStatus() }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func dirtyDocs<T: Synced>(_ t: T.Type, space: String, ctx: ModelContext) -> ([[String: Any]], [T]) {
        let items = ((try? ctx.fetch(FetchDescriptor<T>())) ?? []).filter { $0.dirty && $0.space == space }
        let docs: [[String: Any]] = items.map { m in
            ["cid": m.uid.uuidString, "kind": T.kind, "data": m.payload(), "deleted": m.removed,
             "cts": m.updatedAt.timeIntervalSince1970 * 1000, "author": m.author]
        }
        return (docs, items)
    }

    private func push(space: String, ctx: ModelContext) async throws {
        var docs: [[String: Any]] = []
        var sent: [any Synced] = []
        func add<T: Synced>(_ t: T.Type) {
            let (d, items) = dirtyDocs(t, space: space, ctx: ctx)
            docs += d
            sent += items.map { $0 as any Synced }
        }
        add(Account.self); add(Debt.self); add(Recurring.self); add(Goal.self); add(Tx.self)
        if UserDefaults.standard.bool(forKey: "prefsDirty:\(space)") {
            let limits = (UserDefaults.standard.data(forKey: "catLimits:\(space)")).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
            docs.append(["cid": "prefs", "kind": "prefs", "data": ["budget": UserDefaults.standard.double(forKey: "budget:\(space)"), "catLimits": limits, "cats": CategoryPrefs.storedJSON(space: space)],
                         "deleted": false, "cts": UserDefaults.standard.double(forKey: "prefsTs:\(space)") * 1000])
        }
        guard !docs.isEmpty else { return }
        var i = 0
        while i < docs.count {
            let chunk = Array(docs[i..<min(i + 400, docs.count)])
            _ = try await call("/api/kp/push", ["space": space, "docs": chunk])
            i += 400
        }
        for s in sent { s.dirty = false }
        UserDefaults.standard.set(false, forKey: "prefsDirty:\(space)")
        try? ctx.save()
    }

    private func pull(space: String, ctx: ModelContext) async throws {
        let key = "cursor:\(space)"
        var cursor = UserDefaults.standard.double(forKey: key)
        var changed = false
        while true {
            let obj = try await call("/api/kp/pull", ["space": space, "since": cursor])
            let docs = obj["docs"] as? [[String: Any]] ?? []
            if !docs.isEmpty { applyRemote(docs, space: space, ctx: ctx); changed = true }
            cursor = jNum(obj["cursor"])
            UserDefaults.standard.set(cursor, forKey: key)
            if !jBool(obj["more"]) { break }
        }
        if changed { try? ctx.save(); Notifier.reschedule(ctx: ctx) }
    }

    func applyRemote(_ docs: [[String: Any]], space: String, ctx: ModelContext, local: Bool = false) {
        var byKind: [String: [[String: Any]]] = [:]
        for d in docs { byKind[jStr(d["kind"]), default: []].append(d) }
        func merge<T: Synced>(_ t: T.Type, make: () -> T) {
            guard let list = byKind[T.kind], !list.isEmpty else { return }
            let all = (try? ctx.fetch(FetchDescriptor<T>())) ?? []
            var map: [String: T] = [:]
            for m in all { map[m.uid.uuidString] = m }
            for d in list {
                let cid = jStr(d["cid"])
                let cts = Date(timeIntervalSince1970: jNum(d["cts"]) / 1000)
                if let m = map[cid] {
                    if m.dirty && m.updatedAt > cts { continue }   // локальная правка новее — отправим её
                    if local && !m.removed && m.updatedAt > cts { continue }
                    m.apply(d["data"] as? [String: Any] ?? [:])
                    m.removed = jBool(d["deleted"]); m.updatedAt = local ? Date() : cts; m.author = jStr(d["author"]); m.space = space; m.dirty = local
                } else {
                    if jBool(d["deleted"]) { continue }
                    let m = make()
                    if let u = UUID(uuidString: cid) { m.uid = u }
                    m.apply(d["data"] as? [String: Any] ?? [:])
                    m.space = space; m.updatedAt = local ? Date() : cts; m.author = jStr(d["author"]); m.dirty = local; m.removed = false
                    ctx.insert(m)
                    map[cid] = m
                }
            }
        }
        merge(Account.self) { Account(name: "", start: 0, hex: "2B47C9") }
        merge(Debt.self) { Debt(type: .credit, dirIn: false, name: "", lender: "", total: 0, payment: 0, n: 1, first: Date(), rate: 0) }
        merge(Recurring.self) { Recurring(name: "", amount: 0, kind: .exp, cat: "other", day: 1, yearly: false, month: 1) }
        merge(Goal.self) { Goal(name: "", target: 0, deadline: nil, hex: "2B47C9") }
        merge(Tx.self) { Tx(kind: .exp, amount: 0, cat: "other", note: "", date: Date()) }
        if let p = byKind["prefs"]?.last, local || !UserDefaults.standard.bool(forKey: "prefsDirty:\(space)") {
            let b = jNum((p["data"] as? [String: Any])?["budget"])
            UserDefaults.standard.set(b, forKey: "budget:\(space)")
            CategoryPrefs.shared.applyRemote((p["data"] as? [String: Any])?["cats"], space: space)
            if let l = (p["data"] as? [String: Any])?["catLimits"] as? [String: Any] {
                let v = l.mapValues { jNum($0) }
                UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: "catLimits:\(space)")
            }
            if Space.current == space { UserDefaults.standard.set(b, forKey: "budget") }
            if local {
                UserDefaults.standard.set(true, forKey: "prefsDirty:\(space)")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "prefsTs:\(space)")
            }
        }
    }
}

// MARK: - Резервная копия и полная очистка

enum Backup {
    /// JSON со всеми записями текущего пространства: счета, долги, платежи, копилки, операции и настройки.
    @MainActor
    static func exportFile(ctx: ModelContext) -> URL? {
        let space = Space.current
        var docs: [[String: Any]] = []
        func add<T: Synced>(_ t: T.Type) {
            for m in ctx.live(t) {
                docs.append(["cid": m.uid.uuidString, "kind": T.kind, "data": m.payload(), "deleted": false,
                             "cts": m.updatedAt.timeIntervalSince1970 * 1000, "author": m.author])
            }
        }
        add(Account.self); add(Debt.self); add(Recurring.self); add(Goal.self); add(Tx.self)
        let limits = (UserDefaults.standard.data(forKey: "catLimits:\(space)")).flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        docs.append(["cid": "prefs", "kind": "prefs", "deleted": false, "cts": Date().timeIntervalSince1970 * 1000,
                     "data": ["budget": UserDefaults.standard.double(forKey: "budget"), "catLimits": limits, "cats": CategoryPrefs.storedJSON(space: space)]])
        let root: [String: Any] = ["app": "kopilka", "version": 1, "created": Date().timeIntervalSince1970, "docs": docs]
        let data = jsonData(root)
        guard !data.isEmpty else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Копилка \(DF.s(Date(), "yyyy-MM-dd")).json")
        try? data.write(to: url)
        return url
    }

    /// Восстановить из файла. Записи с тем же id обновляются, новые добавляются. Возвращает число записей.
    @MainActor
    static func restore(_ data: Data, ctx: ModelContext) -> Int? {
        guard let root = jsonObject(data) as? [String: Any], jStr(root["app"]) == "kopilka",
              let docs = root["docs"] as? [[String: Any]] else { return nil }
        let space = Space.current
        SyncEngine.shared.applyRemote(docs, space: space, ctx: ctx, local: true)
        try? ctx.save()
        SyncEngine.shared.schedulePush()
        Notifier.reschedule(ctx: ctx)
        return docs.filter { jStr($0["kind"]) != "prefs" }.count
    }

    /// Удалить все записи текущего пространства (удаление уйдёт и на другие устройства).
    @MainActor
    static func wipe(ctx: ModelContext) {
        func del<T: Synced>(_ t: T.Type) { for m in ctx.live(t) { m.softDelete() } }
        del(Tx.self); del(Recurring.self); del(Goal.self); del(Debt.self); del(Account.self)
        ctx.commit()
        Notifier.reschedule(ctx: ctx)
    }
}

extension ModelContext {
    /// Перед сетевой синхронизацией дописываем в базу то, что ещё не сохранено.
    @MainActor
    func commitIfNeeded() {
        if hasChanges { commit() }
    }
}

// MARK: - Простой доступ к связке ключей

extension Keychain {
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ru.koshelek.app",
                                kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ru.koshelek.app", kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

// MARK: - Окно входа Google

@MainActor
final class OAuthWeb: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: OAuthWeb?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL) async throws -> URL {
        let w = OAuthWeb()
        current = w
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "koshelek") { cb, err in
                if let cb { cont.resume(returning: cb) }
                else if let e = err as? ASWebAuthenticationSessionError, e.code == .canceledLogin {
                    cont.resume(throwing: SyncEngine.APIError(message: "Вход отменён", status: -1))
                } else {
                    cont.resume(throwing: SyncEngine.APIError(message: err?.localizedDescription ?? "Не удалось войти", status: 0))
                }
            }
            s.presentationContextProvider = w
            s.prefersEphemeralWebBrowserSession = false
            w.session = s
            if !s.start() { cont.resume(throwing: SyncEngine.APIError(message: "Не удалось открыть окно входа", status: 0)) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}
