import Foundation
import Security
import SwiftData
import UIKit

// MARK: - Ключ API в связке ключей

enum Keychain {
    private static let service = "ru.koshelek.app"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: AnyObject?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
            let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        }
        set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            SecItemDelete(q as CFDictionary)
            guard let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
            var add = q
            add[kSecValueData as String] = Data(v.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
    static var hasKey: Bool { apiKey != nil }
}

// MARK: - Claude API

enum ClaudeError: LocalizedError {
    case noKey, http(Int, String), badReply, network(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Добавьте ключ Claude API в настройках."
        case .http(let code, let msg):
            if code == 401 { return "Ключ API не подходит. Проверьте его в настройках." }
            if code == 429 { return "Слишком много запросов. Попробуйте через минуту." }
            if code == 400 && msg.contains("credit") { return "На балансе API закончились деньги. Пополните его в консоли Anthropic." }
            if code >= 500 { return "Сервис Claude временно недоступен. Попробуйте позже." }
            return "Ошибка Claude (\(code)): \(msg.prefix(140))"
        case .badReply: return "Не удалось разобрать ответ. Попробуйте сказать иначе."
        case .network(let m): return "Нет связи с Claude: \(m)"
        }
    }
}

enum Claude {
    static let fastModel = "claude-haiku-5-5"
    static let smartModel = "claude-sonnet-5-5"

    static func ask(_ prompt: String, images: [Data] = [], model: String = fastModel, maxTokens: Int = 2048) async throws -> String {
        guard let key = Keychain.apiKey else { throw ClaudeError.noKey }
        var content: [[String: Any]] = images.map {
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        content.append(["type": "text", "text": prompt])
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "messages": [["role": "user", "content": content]]]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw ClaudeError.network(error.localizedDescription) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard code == 200 else {
            let msg = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.http(code, msg)
        }
        let blocks = obj?["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else { throw ClaudeError.badReply }
        return text
    }

    /// Достаёт JSON из ответа (целиком, из блока ``` или от первой скобки до последней).
    static func json(_ prompt: String, images: [Data] = []) async throws -> Any {
        let text = try await ask(prompt, images: images)
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = s.range(of: "```") {
            var inner = String(s[r.upperBound...])
            if let nl = inner.firstIndex(of: "\n") { inner = String(inner[inner.index(after: nl)...]) }
            if let end = inner.range(of: "```") { inner = String(inner[..<end.lowerBound]) }
            s = inner
        }
        if let d = s.data(using: .utf8), let v = try? JSONSerialization.jsonObject(with: d) { return v }
        let starts = [s.firstIndex(of: "["), s.firstIndex(of: "{")].compactMap { $0 }
        let ends = [s.lastIndex(of: "]"), s.lastIndex(of: "}")].compactMap { $0 }
        if let a = starts.min(), let b = ends.max(), a < b,
           let d = String(s[a...b]).data(using: .utf8), let v = try? JSONSerialization.jsonObject(with: d) { return v }
        throw ClaudeError.badReply
    }
}

// MARK: - Подготовка картинок

enum ImagePrep {
    static func jpeg(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        return jpeg(img)
    }
    static func jpeg(_ img: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let s = img.size
        let k = min(1, maxSide / max(s.width, s.height))
        let size = CGSize(width: s.width * k, height: s.height * k)
        let r = UIGraphicsImageRenderer(size: size)
        let out = r.image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.72)
    }
}

// MARK: - Разбор речи, чеков, графиков

@MainActor
enum Brain {
    static var todayLine: String {
        "Сегодня \(DF.iso(Date())) (\(DF.s(Date(), "EEEE")))."
    }

    static func contextLines(ctx: ModelContext) -> String {
        let debts = ((try? ctx.fetch(FetchDescriptor<Debt>())) ?? []).filter { !$0.isClosed }
        let goals = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
        let accs = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        var t = ""
        if !accs.isEmpty {
            let arr = accs.map { ["id": $0.uid.uuidString, "название": $0.name] }
            let js = (try? JSONSerialization.data(withJSONObject: arr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            t += "\nСчета пользователя: \(js)\nЕсли человек назвал, откуда платил или куда пришли деньги («с карты», «наличкой», «на Сбер»), добавь к операции \"acc\":\"<id>\" подходящего счёта. Если не назвал — не добавляй."
        }
        t += "\nЕсли человек говорит о регулярном платеже или подписке («каждый месяц», «ежемесячно», «раз в год», «подписка ... списывается 15-го») — добавь {\"kind\":\"rec\",\"type\":\"exp\"|\"inc\",\"amount\":число,\"cat\":\"id\",\"note\":\"название\",\"day\":число месяца,\"yearly\":false,\"month\":номер месяца для годовых}. Если при этом он сказал, что уже заплатил сейчас, — добавь ещё и обычную операцию."
        if !debts.isEmpty {
            let arr: [[String: Any]] = debts.map { d in
                var o: [String: Any] = ["id": d.uid.uuidString, "название": d.name, "кредитор": d.lender, "вид": d.type.name,
                                        "кто_должен": d.isOut ? "пользователь должен" : "должны пользователю"]
                if let nx = d.nextInst { o["след_платёж"] = ["сумма": nx.amount, "дата": DF.iso(nx.due)] }
                return o
            }
            let js = (try? JSONSerialization.data(withJSONObject: arr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            t += "\nДолги и кредиты пользователя: \(js)\nЕсли человек говорит, что заплатил, внёс, закинул, погасил по кредиту/займу/кредитке/долгу (или ему вернули долг) — верни {\"kind\":\"debt\",\"debt\":\"<id>\",\"amount\":число,\"date\":\"YYYY-MM-DD\"} для подходящего долга. Если сумму не назвал — возьми сумму следующего платежа. Такие платежи НЕ дублируй обычной тратой."
        }
        if !goals.isEmpty {
            let arr = goals.map { ["id": $0.uid.uuidString, "название": $0.name] }
            let js = (try? JSONSerialization.data(withJSONObject: arr)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            t += "\nКопилки пользователя: \(js)\nЕсли человек отложил, положил, закинул в копилку/на цель — верни {\"kind\":\"goal\",\"goal\":\"<id>\",\"amount\":число,\"date\":\"YYYY-MM-DD\"}; если взял из копилки — amount отрицательный. НЕ дублируй обычной тратой."
        }
        return t
    }

    static func clean(_ raw: Any, ctx: ModelContext) -> [ParsedItem] {
        var arr: [[String: Any]] = []
        if let a = raw as? [[String: Any]] { arr = a }
        else if let o = raw as? [String: Any], let a = o["items"] as? [[String: Any]] { arr = a }
        let debts = (try? ctx.fetch(FetchDescriptor<Debt>())) ?? []
        let goals = (try? ctx.fetch(FetchDescriptor<Goal>())) ?? []
        let accs = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        let limit = Date().addingMonths(1)
        func num(_ v: Any?) -> Double {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return parseAmount(s) ?? 0 }
            return 0
        }
        return arr.compactMap { x -> ParsedItem? in
            let raw = num(x["amount"])
            let amount = (abs(raw) * 100).rounded() / 100
            guard amount > 0 else { return nil }
            var date = (x["date"] as? String).flatMap { DF.parseISO($0) } ?? Date().noon
            if date > limit { date = Date().noon }
            var it = ParsedItem(amount: amount, amountText: Fmt.input(amount), date: date)
            if (x["kind"] as? String) == "debt", let s = x["debt"] as? String, let d = debts.first(where: { $0.uid.uuidString == s }), !d.isClosed {
                it.kind = .debt; it.debtID = d.uid; it.note = d.name
                return it
            }
            if (x["kind"] as? String) == "goal", let s = x["goal"] as? String, let g = goals.first(where: { $0.uid.uuidString == s }) {
                it.kind = .goal; it.goalID = g.uid; it.note = g.name; it.sign = raw < 0 ? -1 : 1
                return it
            }
            if let s = x["acc"] as? String, let a = accs.first(where: { $0.uid.uuidString == s }) { it.accID = a.uid }
            if (x["kind"] as? String) == "rec" {
                it.kind = .rec
                it.recDay = Int(num(x["day"])) > 0 ? Int(num(x["day"])) : Date().dayNum
                it.recYearly = (x["yearly"] as? Bool) ?? false
                it.recMonth = Int(num(x["month"])) > 0 ? Int(num(x["month"])) : Date().monthNum
            }
            it.type = (x["type"] as? String) == "inc" ? .inc : .exp
            it.cat = Catalog.valid((x["cat"] as? String) ?? "", for: it.type)
            it.note = String(((x["note"] as? String) ?? "").prefix(80))
            return it
        }
    }

    static func parseSpeech(_ text: String, ctx: ModelContext) async throws -> [ParsedItem] {
        guard Keychain.hasKey else { return LocalParser.parse(text) }
        let prompt = """
        Ты помогаешь вести личный бюджет в рублях. \(todayLine)
        Пользователь рассказал (голосовая диктовка или быстрая запись — разговорная речь, с паразитами, ошибками распознавания и оговорками):
        «\(text)»
        \(Catalog.describe())\(contextLines(ctx: ctx))
        Правила:
        - Выдели каждую реально совершённую денежную операцию. То, что человек только планирует или хочет, не добавляй.
        - Если человек поправился («ой нет, не пятьсот, а шестьсот») — бери исправленное.
        - Числа словами и сленг: «полторы тыщи»=1500, «тыща», «штука», «косарь»=1000, «пятихатка»=500, «полтос»=50, «сотка»=100, «пятёрка» в контексте тысяч=5000, «восемь пятьсот», «восемь с половиной» (о тысячах)=8500, «к» и «тыс»=×1000. «где-то», «примерно», «около» — бери названное число.
        - Даты: «вчера», «позавчера», «в пятницу», «на выходных» переведи в YYYY-MM-DD, не позже сегодня. Если не сказано — сегодня.
        - Обычные операции: {"kind":"tx","type":"exp"|"inc","amount":число,"cat":"id","date":"YYYY-MM-DD","note":"коротко, с большой буквы, до 40 символов"}. Магазин или место — в note.
        Ответь только JSON-массивом операций. Если денежных операций нет — [].
        """
        let raw = try await Claude.json(prompt)
        let items = clean(raw, ctx: ctx)
        return items.isEmpty ? LocalParser.parse(text) : items
    }

    static func parseReceipts(_ images: [Data], ctx: ModelContext) async throws -> [ParsedItem] {
        let prompt = """
        Ты помогаешь вести личный бюджет в рублях. \(todayLine)
        На изображениях — кассовые чеки, электронные чеки или скриншоты банковского приложения (история операций, уведомления, переводы).
        \(Catalog.describe())
        Правила:
        - Чек: обычно одна операция на чек на итоговую сумму с датой чека. Если в чеке явно разные категории (например, продукты и одежда), раздели по категориям, суммы должны сходиться с итогом. note — название магазина.
        - Скриншот банка: каждая видимая операция отдельно. Поступления — inc, списания — exp. Переводы между своими счетами и пополнения своих вкладов пропусти. note — получатель/магазин как на экране.
        - Даты в формате YYYY-MM-DD. Если год не виден — текущий или прошлый, чтобы дата была не позже сегодня. Если даты нет — сегодня.
        Ответь только JSON-массивом: [{"kind":"tx","type":"exp","amount":1234.5,"cat":"food","date":"\(DF.iso(Date()))","note":"Пятёрочка"}]. Если операций не видно — [].
        """
        return clean(try await Claude.json(prompt, images: images), ctx: ctx)
    }

    struct DebtDraft {
        var name = "", lender = "", type: DebtType = .credit
        var total = 0.0, payment = 0.0, n = 1, first = Date().noon, rate = 0.0
    }

    static func parseDebt(_ images: [Data]) async throws -> DebtDraft {
        let prompt = """
        \(todayLine) На изображениях — график платежей, договор или экран кредита/займа/кредитной карты из приложения банка или МФО.
        Извлеки данные для учёта ОСТАВШЕЙСЯ части долга:
        - name: короткое название по-русски («Кредит наличными», «Ипотека», «Кредитная карта»)
        - lender: банк или МФО
        - dtype: "credit" | "card" | "micro"
        - total: сколько всего осталось заплатить (сумма будущих неоплаченных платежей вместе с процентами; если видна только сумма к погашению — она)
        - payment: ежемесячный платёж (для разового займа = total)
        - n: сколько платежей осталось (для разового = 1)
        - first: дата ближайшего неоплаченного платежа YYYY-MM-DD
        - rate: ставка в % годовых числом или null (дневную ставку умножь на 365)
        Ответь только JSON-объектом: {"name":"","lender":"","dtype":"credit","total":0,"payment":0,"n":0,"first":"\(DF.iso(Date()))","rate":null}
        """
        guard let o = try await Claude.json(prompt, images: images) as? [String: Any] else { throw ClaudeError.badReply }
        func num(_ v: Any?) -> Double {
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return parseAmount(s) ?? 0 }
            return 0
        }
        var d = DebtDraft()
        d.name = String(((o["name"] as? String) ?? "").prefix(40))
        d.lender = String(((o["lender"] as? String) ?? "").prefix(40))
        if let t = o["dtype"] as? String, let dt = DebtType(rawValue: t), dt != .person { d.type = dt }
        d.total = num(o["total"]); d.payment = num(o["payment"]); d.n = max(1, Int(num(o["n"])))
        if let f = (o["first"] as? String).flatMap({ DF.parseISO($0) }) { d.first = f }
        d.rate = num(o["rate"])
        if d.n <= 1 { d.payment = d.total }
        guard d.total > 0 else { throw ClaudeError.badReply }
        return d
    }

    static func review(_ data: [String: Any], monthTitle: String) async throws -> String {
        let js = (try? JSONSerialization.data(withJSONObject: data)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let prompt = """
        Ты — внимательный финансовый помощник. Сделай короткий разбор личных финансов за \(monthTitle.lowercased()) по данным ниже (суммы в рублях). Обращайся на «ты», пиши по-русски, живо и по делу.
        Формат: 5–8 пунктов, каждый с новой строки и начинается с «— ». Без заголовков, без markdown и звёздочек. Сначала что хорошо, потом проблемы (перерасход, рост категорий, долговая нагрузка, просрочки), в конце 2–3 конкретных совета с суммами. Если месяц ещё идёт, учитывай это. Не выдумывай данных, которых нет.
        Данные: \(js)
        """
        return try await Claude.ask(prompt, model: Claude.smartModel, maxTokens: 1500)
    }
}

// MARK: - Разбор без ИИ

enum LocalParser {
    static let keywords: [(String, String)] = [
        ("salary", "зарплат|зп(?![а-яё])|аванс|получк"), ("side", "подработ|фриланс|халтур"), ("cashback", "кэшб|кешб"),
        ("cafe", "кафе|кофе|ресторан|бургер|пицц|шаурм|обед|ужин|кофейн|роллы|суши|доставк[аи] еды"),
        ("transport", "такси|метро|автобус|бензин|азс|заправ|проезд|парковк|каршер|электричк"),
        ("food", "продукт|магазин|пят[её]рочк|магнит|ашан|перекр[её]ст|лент[аы]|вкусвилл|мария|ярче|хлеб|молоко|еда"),
        ("home", "квартир|аренд|жкх|жку|коммунал"), ("loans", "кредит|займ|ипотек|долг"),
        ("subs", "подписк|яндекс плюс|кинопоиск|иви|okko|icloud"), ("phone", "связь|телефон|интернет|мтс|билайн|мегафон|теле2"),
        ("health", "аптек|лекарств|врач|больниц|стоматолог|анализ"), ("clothes", "одежд|обув|кроссовк|куртк|джинс"),
        ("fun", "кино|игр|steam|концерт|клуб|скин"), ("gifts", "подар"),
    ]

    static func parse(_ text: String) -> [ParsedItem] {
        let lt = text.lowercased()
        var date = Date().noon
        if lt.contains("позавчера") { date = Date().addingDays(-2).noon } else if lt.contains("вчера") { date = Date().addingDays(-1).noon }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: ",;\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let numRe = try? NSRegularExpression(pattern: "(\\d[\\d\\s]*(?:[.,]\\d+)?)\\s*(тыс[а-яё.]*|к(?![а-яё])|k(?![a-z]))?", options: [.caseInsensitive]) else { return [] }
        var out: [ParsedItem] = []
        for p in parts {
            let ns = p as NSString
            guard let m = numRe.firstMatch(in: p, range: NSRange(location: 0, length: ns.length)) else { continue }
            guard var amount = parseAmount(ns.substring(with: m.range(at: 1))) else { continue }
            if m.range(at: 2).location != NSNotFound { amount *= 1000 }
            guard amount > 0 else { continue }
            let low = p.lowercased()
            var cat: String? = nil
            for (c, pat) in keywords where low.range(of: pat, options: .regularExpression) != nil { cat = c; break }
            let isInc = (cat.map { Catalog.cat($0).kind == .inc } ?? false) || low.range(of: "получил|пришл|доход|заработал", options: .regularExpression) != nil
            let type: TxKind = isInc ? .inc : .exp
            let catID = Catalog.valid(cat ?? "", for: type)
            var note = ns.replacingCharacters(in: m.range, with: "")
            for w in ["позавчера", "вчера", "сегодня", "рублей", "рубля", "руб", "₽"] { note = note.replacingOccurrences(of: w, with: "", options: .caseInsensitive) }
            note = note.split(separator: " ").joined(separator: " ").capitalizedFirst
            out.append(ParsedItem(type: type, cat: catID, amount: amount, amountText: Fmt.input(amount), date: date, note: String(note.prefix(40))))
        }
        return out
    }
}
