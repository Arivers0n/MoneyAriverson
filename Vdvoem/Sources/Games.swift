import SwiftUI

// MARK: - Правила игр (без интерфейса)
// Доска хранится глазами «я»: 1 — мои фишки, 2 — фишки партнёра. На втором телефоне синхронизация переворачивает значения.

enum GameLogic {
    static func initialBoard(_ k: GameKind) -> [Int] {
        var b = Array(repeating: 0, count: k.size.rows * k.size.cols)
        if k == .reversi { b[3 * 8 + 3] = 2; b[4 * 8 + 4] = 2; b[3 * 8 + 4] = 1; b[4 * 8 + 3] = 1 }
        return b
    }

    static func other(_ w: Who) -> Who { w == .me ? .partner : .me }
    static func piece(_ w: Who) -> Int { w == .me ? 1 : 2 }

    private static let dirs8 = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]

    static func dropRow(_ b: [Int], col: Int, rows: Int, cols: Int) -> Int? {
        for r in stride(from: rows - 1, through: 0, by: -1) where b[r * cols + col] == 0 { return r }
        return nil
    }

    static func flips(_ b: [Int], idx: Int, p: Int) -> [Int] {
        guard b[idx] == 0 else { return [] }
        let r0 = idx / 8, c0 = idx % 8
        var out: [Int] = []
        for (dr, dc) in dirs8 {
            var line: [Int] = []
            var r = r0 + dr, c = c0 + dc
            while r >= 0, r < 8, c >= 0, c < 8, b[r * 8 + c] == 3 - p {
                line.append(r * 8 + c)
                r += dr; c += dc
            }
            if !line.isEmpty, r >= 0, r < 8, c >= 0, c < 8, b[r * 8 + c] == p { out += line }
        }
        return out
    }

    /// Допустимые ходы: клетки (крестики-нолики, реверси) или столбцы (4 в ряд).
    static func validMoves(_ k: GameKind, _ b: [Int], _ who: Who) -> [Int] {
        switch k {
        case .ttt: return b.indices.filter { b[$0] == 0 }
        case .four: return (0..<7).filter { b[$0] == 0 }
        case .reversi: return b.indices.filter { !flips(b, idx: $0, p: piece(who)).isEmpty }
        }
    }

    /// Выигрышная линия (для крестиков-ноликов и 4 в ряд).
    static func winCells(_ k: GameKind, _ b: [Int]) -> [Int]? {
        let (rows, cols) = k.size
        let need = k == .ttt ? 3 : 4
        guard k != .reversi else { return nil }
        for r in 0..<rows {
            for c in 0..<cols {
                let p = b[r * cols + c]
                if p == 0 { continue }
                for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
                    var cells = [r * cols + c]
                    var rr = r + dr, cc = c + dc
                    while rr >= 0, rr < rows, cc >= 0, cc < cols, b[rr * cols + cc] == p, cells.count < need {
                        cells.append(rr * cols + cc)
                        rr += dr; cc += dc
                    }
                    if cells.count == need { return cells }
                }
            }
        }
        return nil
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, m.turn == who, validMoves(m.kind, m.board, who).contains(move) else { return nil }
        var n = m
        let p = piece(who)
        let (rows, cols) = m.kind.size
        var cell = move
        switch m.kind {
        case .ttt:
            n.board[move] = p
        case .four:
            guard let r = dropRow(m.board, col: move, rows: rows, cols: cols) else { return nil }
            cell = r * cols + move
            n.board[cell] = p
        case .reversi:
            for f in flips(m.board, idx: move, p: p) { n.board[f] = p }
            n.board[move] = p
        }
        n.moves += 1
        n.last = cell
        n.updated = Date()
        switch m.kind {
        case .ttt, .four:
            if winCells(m.kind, n.board) != nil { n.state = .won; n.winner = who }
            else if !n.board.contains(0) { n.state = .draw }
            else { n.turn = other(who) }
        case .reversi:
            let opp = other(who)
            if !validMoves(.reversi, n.board, opp).isEmpty { n.turn = opp }
            else if !validMoves(.reversi, n.board, who).isEmpty { n.turn = who }
            else {
                let a = n.board.filter { $0 == 1 }.count, b = n.board.filter { $0 == 2 }.count
                if a == b { n.state = .draw } else { n.state = .won; n.winner = a > b ? .me : .partner }
            }
        }
        return n
    }
}

// MARK: - Действия в хранилище

extension Store {
    @discardableResult
    func newMatch(_ k: GameKind, starter: Who = .me) -> GameMatch {
        let m = GameMatch(kind: k, board: GameLogic.initialBoard(k), turn: starter, starter: starter)
        data.matches.append(m)
        tap()
        return m
    }

    func match(_ id: UUID) -> GameMatch? { data.matches.first { $0.id == id } }

    func move(_ id: UUID, _ index: Int, by who: Who) {
        guard let i = data.matches.firstIndex(where: { $0.id == id }),
              let n = GameLogic.play(data.matches[i], move: index, by: who) else { return }
        data.matches[i] = n
        if n.state == .won { success() } else { tap() }
    }

    func deleteMatch(_ id: UUID) { data.matches.removeAll { $0.id == id } }

    func myTurnCount() -> Int {
        data.matches.filter { $0.state == .playing && $0.turn == .me }.count
    }
}

// MARK: - Список игр

struct GamesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @State private var openID: UUID?

    private var playing: [GameMatch] { store.data.matches.filter { $0.state == .playing }.sorted { $0.updated > $1.updated } }
    private var finished: [GameMatch] { store.data.matches.filter { $0.state != .playing }.sorted { $0.updated > $1.updated } }

    var body: some View {
        Screen {
            HStack {
                stat(.me)
                Divider().frame(height: 50)
                stat(.partner)
            }
            .padding(18).card()

            SectionTitle("Новая партия")
            VStack(spacing: 0) {
                ForEach(GameKind.allCases) { k in
                    Button {
                        let m = store.newMatch(k)
                        openID = m.id
                    } label: { row(k.title, k.icon, "Позвать \(store.name(.partner)) сыграть") }
                    .buttonStyle(.plain)
                    if k != GameKind.allCases.last { Divider().padding(.leading, 72) }
                }
            }
            .card()

            if !playing.isEmpty {
                SectionTitle("Идут сейчас")
                VStack(spacing: 0) {
                    ForEach(playing) { m in
                        Button { openID = m.id } label: { matchRow(m) }.buttonStyle(.plain)
                        if m.id != playing.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .card()
            }
            if !finished.isEmpty {
                SectionTitle("Сыграны")
                VStack(spacing: 0) {
                    ForEach(finished.prefix(10)) { m in
                        Button { openID = m.id } label: { matchRow(m) }.buttonStyle(.plain)
                        if m.id != finished.prefix(10).last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .card()
            }

            Text(sync.status == .notPaired
                 ? "Пока вы не соединились с партнёром, партии идут на одном телефоне — передавайте его друг другу."
                 : "Ходите с разных телефонов: ход партнёра появится у вас сразу. Фоновых уведомлений нет — откройте приложение.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Игры")
        .navigationDestination(item: $openID) { id in MatchView(matchID: id) }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.data.matches.count)
    }

    private func stat(_ w: Who) -> some View {
        HStack(spacing: 10) {
            Circle().fill(store.color(w)).frame(width: 18, height: 18)
            VStack(alignment: .leading) {
                Text("\(store.wins(w))").font(.title.bold().monospacedDigit()).contentTransition(.numericText())
                Text("\(store.name(w)) · побед").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func matchRow(_ m: GameMatch) -> some View {
        let sub: String
        switch m.state {
        case .playing:
            sub = sync.status == .notPaired ? "Ход: \(store.name(m.turn))"
                : (m.turn == .me ? "Ваш ход" : "Ждём ход: \(store.name(m.turn))")
        case .won: sub = "Победа: \(store.name(m.winner ?? .me))"
        case .draw: sub = "Ничья"
        }
        return row(m.kind.title, m.kind.icon, sub, highlight: m.state == .playing && m.turn == .me && sync.status != .notPaired)
    }

    private func row(_ t: String, _ icon: String, _ sub: String, highlight: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                .background(highlight ? store.meColor.opacity(0.25) : Pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.body.weight(.medium))
                Text(sub).font(.caption).foregroundStyle(highlight ? store.meColor : .secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }
}

// MARK: - Партия

struct MatchView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss
    let matchID: UUID

    private var m: GameMatch? { store.match(matchID) }
    private var hotSeat: Bool { sync.status == .notPaired }

    var body: some View {
        Group {
            if let m {
                VStack(spacing: 18) {
                    header(m)
                    board(m).padding(.horizontal, 16)
                    footer(m)
                    Spacer()
                }
                .padding(.top, 16)
            } else {
                EmptyState(icon: "gamecontroller", title: "Партия удалена", text: "")
            }
        }
        .background(ThemeBackground())
        .navigationTitle(m?.kind.title ?? "Игра")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if m != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Удалить партию", role: .destructive) { store.deleteMatch(matchID); dismiss() }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .onChange(of: m?.moves) { _, _ in
            if let m, m.state == .playing, m.turn == .me, !hotSeat { store.tap() }
        }
    }

    private func header(_ m: GameMatch) -> some View {
        let text: String
        var who: Who? = m.turn
        switch m.state {
        case .playing: text = hotSeat ? "Ход: \(store.name(m.turn))" : (m.turn == .me ? "Ваш ход" : "Ход: \(store.name(m.turn))")
        case .won: text = "Победил(а) \(store.name(m.winner ?? .me))"; who = m.winner
        case .draw: text = "Ничья"; who = nil
        }
        return HStack(spacing: 8) {
            if let who { Circle().fill(store.color(who)).frame(width: 14, height: 14) }
            Text(text).font(.headline).contentTransition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: text)
    }

    private func footer(_ m: GameMatch) -> some View {
        Group {
            if m.state != .playing {
                Button {
                    let n = store.newMatch(m.kind, starter: GameLogic.other(m.starter))
                    _ = n
                    dismiss()
                } label: { Text("Реванш").bigButton() }
                    .padding(.horizontal, 16)
            } else if !hotSeat && m.turn != .me {
                Text("Ждём ход партнёра…").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func canTap(_ m: GameMatch) -> Bool {
        m.state == .playing && (hotSeat || m.turn == .me)
    }

    private func tryMove(_ m: GameMatch, _ index: Int) {
        guard canTap(m) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { store.move(m.id, index, by: m.turn) }
    }

    @ViewBuilder
    private func board(_ m: GameMatch) -> some View {
        let win = Set(GameLogic.winCells(m.kind, m.board) ?? [])
        switch m.kind {
        case .ttt: tttBoard(m, win)
        case .four: fourBoard(m, win)
        case .reversi: reversiBoard(m)
        }
    }

    private func tttBoard(_ m: GameMatch, _ win: Set<Int>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(0..<9, id: \.self) { i in
                let p = m.board[i]
                Button { tryMove(m, i) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(win.contains(i) ? store.color(m.winner).opacity(0.28) : Pal.card)
                        if p != 0 {
                            Image(systemName: p == 1 ? "xmark" : "circle")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(store.color(p == 1 ? .me : .partner))
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 420)
    }

    private func fourBoard(_ m: GameMatch, _ win: Set<Int>) -> some View {
        let valid = Set(GameLogic.validMoves(.four, m.board, m.turn))
        return HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { c in
                Button { tryMove(m, c) } label: {
                    VStack(spacing: 5) {
                        ForEach(0..<6, id: \.self) { r in
                            let i = r * 7 + c
                            let p = m.board[i]
                            Circle()
                                .fill(p == 0 ? Pal.bg : store.color(p == 1 ? .me : .partner))
                                .overlay(Circle().stroke(win.contains(i) ? Color.primary : .clear, lineWidth: 3))
                                .aspectRatio(1, contentMode: .fit)
                                .transition(.move(edge: .top))
                        }
                    }
                    .padding(4)
                    .background(Pal.card.opacity(valid.contains(c) && canTap(m) ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 460)
    }

    private func reversiBoard(_ m: GameMatch) -> some View {
        let valid = Set(GameLogic.validMoves(.reversi, m.board, m.turn))
        return VStack(spacing: 2) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<8, id: \.self) { c in
                        let i = r * 8 + c
                        let p = m.board[i]
                        Button { tryMove(m, i) } label: {
                            ZStack {
                                Rectangle().fill(Color(hex: (r + c) % 2 == 0 ? "2F7D5B" : "2A7253"))
                                if p != 0 {
                                    Circle().fill(store.color(p == 1 ? .me : .partner)).padding(4)
                                        .overlay(Circle().stroke(.white.opacity(m.last == i ? 0.9 : 0), lineWidth: 2).padding(4))
                                        .transition(.scale)
                                } else if valid.contains(i) && canTap(m) {
                                    Circle().fill(.white.opacity(0.35)).frame(width: 8, height: 8)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                Label("\(m.board.filter { $0 == 1 }.count)", systemImage: "circle.fill").foregroundStyle(store.meColor)
                Spacer()
                Label("\(m.board.filter { $0 == 2 }.count)", systemImage: "circle.fill").foregroundStyle(store.partnerColor)
            }
            .font(.subheadline.weight(.semibold)).padding(.top, 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: 460)
    }
}
