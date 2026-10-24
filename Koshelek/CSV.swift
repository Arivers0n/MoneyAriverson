import Foundation
import SwiftData

enum CSV {
    static let header = ["Дата", "Тип", "Сумма", "Категория", "Счёт", "Куда", "Заметка"]

    static func exportFile(txs: [Tx], accounts: [Account]) -> URL? {
        func name(_ id: UUID?) -> String { accounts.first { $0.uid == id }?.name ?? "" }
        var rows = [header]
        for t in txs.sorted(by: { $0.date < $1.date }) {
            rows.append([DF.iso(t.date), t.kind == .inc ? "Доход" : (t.kind == .exp ? "Расход" : "Перевод"),
                         Fmt.input(t.amount), t.kind == .tr ? "" : Catalog.cat(t.cat).name, name(t.accID), name(t.toID), t.note])
        }
        let text = "\u{FEFF}" + rows.map { $0.map(quote).joined(separator: ";") }.joined(separator: "\r\n")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("koshelek-\(DF.iso(Date())).csv")
        do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private static func quote(_ v: String) -> String {
        v.contains(";") || v.contains("\"") || v.contains("\n") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", inQ = false
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        let sep: Character = (text.contains(";") ? ";" : ",")
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQ {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQ = false }
                } else { field.append(c) }
            } else if c == "\"" { inQ = true }
            else if c == sep { row.append(field); field = "" }
            else if c == "\n" || c == "\r" {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    /// Импорт выгрузки из веб-версии Кошелька (или этой же). Возвращает число добавленных операций.
    @MainActor
    static func importCSV(_ text: String, ctx: ModelContext) -> Int {
        let rows = parse(text)
        guard rows.count > 1 else { return 0 }
        var accs = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
        func acc(_ n: String) -> UUID? {
            let n = n.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return nil }
            if let a = accs.first(where: { $0.name == n }) { return a.uid }
            let a = Account(name: n, start: 0, hex: Theme.palette[accs.count % Theme.palette.count])
            ctx.insert(a); accs.append(a)
            return a.uid
        }
        var count = 0
        for r in rows.dropFirst() where r.count >= 3 {
            guard let date = DF.parseISO(r[0]), let amount = parseAmount(r[2]), amount > 0 else { continue }
            let kind: TxKind = r[1] == "Доход" ? .inc : (r[1] == "Перевод" ? .tr : .exp)
            let cat = kind == .tr ? "" : Catalog.byName(r.count > 3 ? r[3] : "", kind: kind)
            let t = Tx(kind: kind, amount: amount, cat: cat, note: r.count > 6 ? r[6] : "", date: date,
                       accID: acc(r.count > 4 ? r[4] : ""), toID: kind == .tr ? acc(r.count > 5 ? r[5] : "") : nil)
            ctx.insert(t)
            count += 1
        }
        try? ctx.save()
        return count
    }
}
