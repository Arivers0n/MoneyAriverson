import Foundation
import SwiftData
import SwiftUI

struct Insight: Identifiable {
    enum Tone { case good, warn, bad, info }
    let id = UUID()
    let tone: Tone
    let symbol: String
    let text: String
    var color: Color {
        switch tone {
        case .good: return Theme.inc
        case .warn: return Theme.warn
        case .bad: return Theme.exp
        case .info: return Theme.accent
        }
    }
}

@MainActor
enum Advisor {
    // MARK: Подсказки без интернета

    static func insights(txs: [Tx], debts: [Debt], recs: [Recurring], budget: Double) -> [Insight] {
        var out: [Insight] = []
        let now = Date()
        let cur = totals(for: now, txs), prev = totals(for: now.addingMonths(-1), txs)

        // Просрочки
        let ov = allInstallments(debts).filter { $0.st == .overdue && $0.debt.isOut }
        if let x = ov.first {
            out.append(Insight(tone: .bad, symbol: "exclamationmark.triangle.fill",
                               text: "Просрочен платёж «\(x.debt.name)» на \(Fmt.rubU(x.amount)). Каждый день просрочки — пени и минус к кредитной истории."))
        }

        // Темп трат против лимита
        if budget > 0 {
            let day = Double(now.dayNum), days = Double(now.daysInMonth)
            let forecast = cur.exp / max(1, day) * days
            if forecast > budget * 1.08 && cur.exp > 0 {
                out.append(Insight(tone: .warn, symbol: "speedometer",
                                   text: "Тратите быстрее плана: к концу месяца выйдет около \(Fmt.rubU(forecast)) при лимите \(Fmt.rubU(budget)). Чтобы уложиться, держитесь в пределах \(Fmt.rubU(max(0, budget - cur.exp) / max(1, days - day + 1))) в день."))
            } else if cur.exp > 0 && day > 10 {
                out.append(Insight(tone: .good, symbol: "checkmark.circle.fill", text: "Идёте в рамках лимита. Так держать."))
            }
        }

        // Лимиты по категориям
        let limits = CatLimits.load()
        if !limits.isEmpty {
            var spent: [String: Double] = [:]
            for t in cur.items where t.kind == .exp { spent[t.cat, default: 0] += t.amount }
            for (id, lim) in limits.sorted(by: { (spent[$0.key] ?? 0) / max($0.value, 1) > (spent[$1.key] ?? 0) / max($1.value, 1) }) where lim > 0 {
                let s = spent[id] ?? 0, c = Catalog.cat(id)
                if s > lim {
                    out.append(Insight(tone: .bad, symbol: c.symbol, text: "Бюджет «\(c.name)» превышен на \(Fmt.rubU(s - lim)). Лучше притормозить с этой категорией до конца месяца."))
                    break
                } else if s > lim * 0.8 {
                    out.append(Insight(tone: .warn, symbol: c.symbol, text: "По «\(c.name)» потрачено \(Int(s / lim * 100))% бюджета, осталось \(Fmt.rubU(lim - s))."))
                    break
                }
            }
        }

        // Рост категорий (с поправкой на прошедшую часть месяца)
        let frac = Double(now.dayNum) / Double(now.daysInMonth)
        let a = Dictionary(uniqueKeysWithValues: byCategory(cur.items).map { ($0.cat.id, $0.sum) })
        let b = Dictionary(uniqueKeysWithValues: byCategory(prev.items).map { ($0.cat.id, $0.sum) })
        var worst: (String, Double, Double)?
        for (k, v) in a where ["cafe", "fun", "clothes", "other", "gifts"].contains(k) {
            let was = (b[k] ?? 0) * frac
            if v > 2000 && v > was * 1.4 && (worst == nil || v - was > worst!.1 - worst!.2) { worst = (k, v, was) }
        }
        if let w = worst {
            let c = Catalog.cat(w.0)
            out.append(Insight(tone: .warn, symbol: "chart.line.uptrend.xyaxis",
                               text: "«\(c.name)» уже \(Fmt.rubU(w.1)) — заметно больше, чем к этому дню в прошлом месяце. Это то, что легче всего урезать."))
        }

        // Частые мелкие траты
        let cafeCount = cur.items.filter { $0.kind == .exp && $0.cat == "cafe" }.count
        if cafeCount >= 8 {
            let sum = cur.items.filter { $0.kind == .exp && $0.cat == "cafe" }.reduce(0) { $0 + $1.amount }
            out.append(Insight(tone: .info, symbol: "cup.and.saucer.fill",
                               text: "\(cafeCount) \(plural(cafeCount, "раз", "раза", "раз")) кафе и кофе за месяц — \(Fmt.rubU(sum)). Мелочи складываются: это \(Fmt.rubU(sum * 12)) в год."))
        }

        // Микрозаймы
        if let m = debts.first(where: { $0.type == .micro && $0.isOut && !$0.isClosed }) {
            out.append(Insight(tone: .bad, symbol: "flame.fill",
                               text: "Микрозайм «\(m.name)» — самые дорогие деньги. Любые свободные рубли сначала туда: осталось \(Fmt.rubU(m.remaining))."))
        }

        // Долговая нагрузка
        let inc = averageIncome(txs)
        let monthly = allInstallments(debts).filter { $0.debt.isOut && $0.due.sameMonth(now) }.reduce(0) { $0 + $1.plan }
        if inc > 0 && monthly / inc > 0.4 {
            out.append(Insight(tone: .bad, symbol: "scalemass.fill",
                               text: "На кредиты уходит \(Int(monthly / inc * 100))% дохода. Больше 40% — опасная зона: новые займы сейчас лучше не брать."))
        }

        // Подписки
        let subs = recs.filter { $0.kind == .exp }.reduce(0) { $0 + $1.perMonth }
        if subs > 0 && recs.count >= 3 {
            out.append(Insight(tone: .info, symbol: "repeat",
                               text: "Регулярные платежи — \(Fmt.rubU(subs)) в месяц, \(Fmt.rubU(subs * 12)) в год. Проверьте, всеми ли подписками пользуетесь."))
        }
        return out
    }

    // MARK: Контекст для Claude

    static func context(ctx: ModelContext) -> String {
        let txs = ctx.live(Tx.self)
        let debts = ctx.live(Debt.self)
        let recs = ctx.live(Recurring.self)
        let goals = ctx.live(Goal.self)
        let budget = UserDefaults.standard.double(forKey: "budget")
        let now = Date()
        var d: [String: Any] = [:]
        d["сегодня"] = DF.iso(now)
        d["день_месяца"] = "\(now.dayNum) из \(now.daysInMonth)"
        if budget > 0 { d["лимит_расходов_в_месяц"] = budget }
        d["средний_доход_в_месяц"] = Int(averageIncome(txs))
        var months: [[String: Any]] = []
        for k in 0..<3 {
            let t = totals(for: now.addingMonths(-k), txs)
            var cats: [String: Int] = [:]
            for c in byCategory(t.items) { cats[c.cat.name] = Int(c.sum) }
            months.append(["месяц": DF.month(t.month), "доход": Int(t.inc), "расход": Int(t.exp), "по_категориям": cats])
        }
        d["месяцы"] = months
        var notes: [String: Int] = [:]
        for t in totals(for: now, txs).items where t.kind == .exp && !t.note.isEmpty { notes[t.note, default: 0] += Int(t.amount) }
        d["частые_места_этого_месяца"] = notes.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key): \($0.value)" }
        var ds: [[String: Any]] = []
        for x in debts where !x.isClosed {
            ds.append(["название": x.name, "вид": x.type.name, "я_должен": x.isOut, "осталось": Int(x.remaining),
                       "платёж_в_месяц": Int(x.payment), "платежей_осталось": x.schedule().filter { $0.isOpen }.count,
                       "ставка_годовых": x.rate, "просрочено": x.schedule().filter { $0.st == .overdue }.count])
        }
        d["долги"] = ds
        d["регулярные"] = recs.map { "\($0.name): \(Int($0.amount)) ₽ \($0.yearly ? "в год" : "в месяц")" }
        d["копилки"] = goals.map { "\($0.name): \(Int($0.saved)) из \(Int($0.target))" }
        let js = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return js
    }

    static let persona = """
    Ты — личный финансовый советник в приложении «Копилка»: помогаешь человеку с бюджетом, накоплениями и долгами. Пиши по-русски, на «ты», коротко и по делу, как умный друг, а не банк. \
    Опирайся только на данные пользователя, не выдумывай цифр. Давай конкретику: суммы, сроки, порядок действий. \
    Если видишь проблему (лишние траты, просрочки, опасная долговая нагрузка, микрозаймы) — говори прямо, но без морали. \
    Не давай советов по инвестициям в конкретные активы. Без markdown-заголовков и звёздочек; списки — строками с «— ».
    """

    // MARK: Совет дня

    static func cachedTip() -> String? {
        guard UserDefaults.standard.string(forKey: "tipDate") == DF.iso(Date()) else { return nil }
        return UserDefaults.standard.string(forKey: "tipText")
    }

    static func dailyTip(ctx: ModelContext, force: Bool = false) async throws -> String {
        if !force, let t = cachedTip() { return t }
        let prompt = """
        Данные пользователя: \(context(ctx: ctx))
        Дай ОДИН самый полезный на сегодня совет или замечание (2–3 предложения, до 300 знаков): что заметил в тратах, накоплениях или долгах и что конкретно сделать. Если данных мало — посоветуй, с чего начать вести учёт. Без вступлений.
        """
        let t = try await Claude.ask(persona + "\n\n" + prompt, model: Claude.fastModel, maxTokens: 800)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(t, forKey: "tipText")
        UserDefaults.standard.set(DF.iso(Date()), forKey: "tipDate")
        return t
    }
}

// MARK: - Чат с советником

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let fromUser: Bool
    var text: String
}

extension Claude {
    static func chat(system: String, messages: [ChatMessage], model: String? = nil) async throws -> String {
        let msgs: [[String: Any]] = messages.map { ["role": $0.fromUser ? "user" : "assistant", "content": $0.text] }
        let body: [String: Any] = ["model": model ?? smartModel, "max_tokens": 2000, "system": system, "messages": msgs]
        return try await send(body, timeout: 120)
    }
}

struct AdvisorChat: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var input = ""
    @State private var thinking = false
    @State private var err: String?
    @FocusState private var focused: Bool

    let suggestions = [
        "Как мне быстрее закрыть долги?",
        "На чём я трачу лишнее?",
        "Сколько я могу откладывать в месяц?",
        "Составь план на следующий месяц",
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "sparkles").font(.title).foregroundStyle(Theme.accent)
                                Text("Спросите что угодно о своих деньгах").font(.title3.weight(.semibold))
                                Text("Советник видит ваши траты, долги, подписки и копилки — и отвечает с цифрами.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { send(s) } label: {
                                        Text(s).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(12).background(Theme.soft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 8)
                        }
                        ForEach(messages) { m in
                            HStack {
                                if m.fromUser { Spacer(minLength: 40) }
                                Text(m.text)
                                    .textSelection(.enabled)
                                    .padding(12)
                                    .foregroundStyle(m.fromUser ? Theme.onAccent : Color.primary)
                                    .background(m.fromUser ? Theme.accent : Theme.soft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                if !m.fromUser { Spacer(minLength: 24) }
                            }
                            .id(m.id)
                        }
                        if thinking {
                            HStack(spacing: 8) { ProgressView(); Text("Думаю…").foregroundStyle(.secondary) }.id("thinking")
                        }
                        if let err { Text(err).font(.footnote).foregroundStyle(Theme.exp) }
                    }
                    .padding(16)
                }
                .onChange(of: messages) { _, m in
                    if let last = m.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Спросить советника…", text: $input, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Theme.soft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button { send(input) } label: {
                        Image(systemName: "arrow.up").font(.headline).foregroundStyle(Theme.onAccent)
                            .frame(width: 40, height: 40).background(Theme.accent, in: Circle())
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || thinking)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Советник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private func send(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !thinking else { return }
        guard Claude.available else { err = "ИИ недоступен: войдите в аккаунт или добавьте ключ в настройках."; return }
        input = ""; err = nil
        messages.append(ChatMessage(fromUser: true, text: t))
        thinking = true
        let system = Advisor.persona + "\n\nСвежие данные пользователя (JSON): " + Advisor.context(ctx: ctx)
        let history = Array(messages.suffix(16))
        Task {
            defer { thinking = false }
            do {
                let reply = try await Claude.chat(system: system, messages: history)
                messages.append(ChatMessage(fromUser: false, text: reply.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                err = error.localizedDescription
            }
        }
    }
}
