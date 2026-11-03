import Foundation

// MARK: - Правила игр (без интерфейса)
// Доска хранится глазами «я»: 1 — мои, 2 — партнёра. На втором телефоне синхронизация переворачивает данные (см. GameFlip).

enum GameLogic {
    static func other(_ w: Who) -> Who { w == .me ? .partner : .me }
    static func piece(_ w: Who) -> Int { w == .me ? 1 : 2 }
    static func owner(_ v: Int) -> Who? { v == 0 ? nil : (v % 2 == 1 ? .me : .partner) }

    // MARK: Создание партии

    static func make(_ k: GameKind, starter: Who) -> GameMatch {
        var m = GameMatch(kind: k, board: [], turn: starter, starter: starter)
        switch k {
        case .ttt, .four, .reversi:
            m.board = classicBoard(k)
        case .checkers:
            var b = Array(repeating: 0, count: 64)
            for r in 0..<8 { for c in 0..<8 where (r + c) % 2 == 1 {
                if r < 3 { b[r * 8 + c] = 2 } else if r > 4 { b[r * 8 + c] = 1 }
            } }
            m.board = b
        case .dots:
            m.board = Array(repeating: 0, count: 56)
        case .battleship:
            m.board = Array(repeating: 0, count: 400)
            m.aux = 0
        case .durak:
            var deck = Array(0..<36).shuffled()
            var b = Array(repeating: 0, count: 36)
            for _ in 0..<6 { b[deck.removeFirst()] = 1; b[deck.removeFirst()] = 2 }
            let trump = deck.last! / 9
            let lowest: (Int) -> Int? = { p in (0..<36).filter { b[$0] == p && $0 / 9 == trump }.map { $0 % 9 }.min() }
            let mine = lowest(1) ?? 99, theirs = lowest(2) ?? 99
            let att: Who = mine < theirs ? .me : (theirs < mine ? .partner : starter)
            m.board = b
            m.extra = deck
            m.aux = trump
            m.table = []
            m.starter = att
            m.turn = att
        case .memory:
            m.board = Array(repeating: 0, count: 16)
            m.extra = (0..<8).flatMap { [$0, $0] }.shuffled()
        case .rps:
            m.board = [0, 0]
            m.extra = [0, 0, 1]
        case .hangman:
            m.board = []
            m.word = nil
            m.guesses = ""
        }
        return m
    }

    // MARK: Ходы

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        switch m.kind {
        case .ttt, .four, .reversi: return playClassic(m, move: move, by: who)
        case .checkers: return Checkers.play(m, move: move, by: who)
        case .dots: return Dots.play(m, move: move, by: who)
        case .battleship: return Battleship.play(m, move: move, by: who)
        case .durak: return Durak.play(m, move: move, by: who)
        case .memory: return MemoryGame.play(m, move: move, by: who)
        case .rps: return RPS.play(m, move: move, by: who)
        case .hangman: return Hangman.play(m, move: move, by: who)
        }
    }

    // MARK: Классика (крестики-нолики, 4 в ряд, реверси)

    static func classicBoard(_ k: GameKind) -> [Int] {
        var b = Array(repeating: 0, count: k.size.rows * k.size.cols)
        if k == .reversi { b[3 * 8 + 3] = 2; b[4 * 8 + 4] = 2; b[3 * 8 + 4] = 1; b[4 * 8 + 3] = 1 }
        return b
    }

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
        default: return []
        }
    }

    /// Выигрышная линия (для крестиков-ноликов и 4 в ряд).
    static func winCells(_ k: GameKind, _ b: [Int]) -> [Int]? {
        guard k == .ttt || k == .four else { return nil }
        let (rows, cols) = k.size
        let need = k == .ttt ? 3 : 4
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

    private static func playClassic(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
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
        default: return nil
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
        default: break
        }
        return n
    }

    static func finish(_ m: inout GameMatch, winner: Who?) {
        if let winner { m.state = .won; m.winner = winner } else { m.state = .draw }
    }
}

// MARK: - Переворот данных для второго телефона

enum GameFlip {
    private static func swap12(_ v: Int) -> Int { v == 1 ? 2 : (v == 2 ? 1 : v) }

    static func flip(_ m: GameMatch) -> GameMatch {
        var x = m
        x.turn = m.turn.flipped
        x.starter = m.starter.flipped
        x.winner = m.winner?.flipped
        switch m.kind {
        case .ttt, .four, .reversi, .dots, .durak, .memory:
            x.board = m.board.map(swap12)
        case .checkers:
            x.board = m.board.reversed().map { v in v == 1 ? 2 : (v == 2 ? 1 : (v == 3 ? 4 : (v == 4 ? 3 : v))) }
            x.last = m.last >= 0 ? 63 - m.last : m.last
            x.aux = m.aux.map { 63 - $0 }
        case .battleship:
            if m.board.count == 400 {
                x.board = Array(m.board[100..<200]) + Array(m.board[0..<100]) + Array(m.board[300..<400]) + Array(m.board[200..<300])
            }
            if let a = m.aux { x.aux = ((a & 1) << 1) | ((a >> 1) & 1) }
        case .rps:
            if m.board.count == 2 { x.board = [m.board[1], m.board[0]] }
            if var e = m.extra, e.count == 3 { e.swapAt(0, 1); x.extra = e }
        case .hangman:
            break
        }
        return x
    }
}

// MARK: - Точки и квадратики (поле 4×4 клетки)
// board: 0..19 горизонтальные рёбра [r*4+c], 20..39 вертикальные [20 + r*5+c], 40..55 клетки [40 + r*4+c].

enum Dots {
    static func boxes(forEdge e: Int) -> [Int] {
        var out: [Int] = []
        if e < 20 {
            let r = e / 4, c = e % 4
            if r > 0 { out.append((r - 1) * 4 + c) }
            if r < 4 { out.append(r * 4 + c) }
        } else {
            let i = e - 20, r = i / 5, c = i % 5
            if c > 0 { out.append(r * 4 + c - 1) }
            if c < 4 { out.append(r * 4 + c) }
        }
        return out
    }

    static func edges(ofBox b: Int) -> [Int] {
        let r = b / 4, c = b % 4
        return [r * 4 + c, (r + 1) * 4 + c, 20 + r * 5 + c, 20 + r * 5 + c + 1]
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, m.turn == who, move >= 0, move < 40, m.board[move] == 0 else { return nil }
        var n = m
        n.board[move] = GameLogic.piece(who)
        var got = false
        for b in boxes(forEdge: move) where n.board[40 + b] == 0 && edges(ofBox: b).allSatisfy({ n.board[$0] != 0 }) {
            n.board[40 + b] = GameLogic.piece(who)
            got = true
        }
        n.moves += 1; n.last = move; n.updated = Date()
        if !n.board[40...].contains(0) {
            let a = n.board[40...].filter { $0 == 1 }.count, c = n.board[40...].filter { $0 == 2 }.count
            GameLogic.finish(&n, winner: a == c ? nil : (a > c ? .me : .partner))
        } else if !got {
            n.turn = GameLogic.other(who)
        }
        return n
    }
}

// MARK: - Шашки (русские)

struct CMove: Hashable { let from: Int; let to: Int; let cap: Int? }

enum Checkers {
    private static let dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    private static func inb(_ r: Int, _ c: Int) -> Bool { r >= 0 && r < 8 && c >= 0 && c < 8 }

    static func moves(_ b: [Int], who: Who, chain: Int?) -> [CMove] {
        var caps: [CMove] = [], quiet: [CMove] = []
        let squares = chain.map { [$0] } ?? Array(0..<64)
        let enemy = GameLogic.other(who)
        for s in squares {
            let v = b[s]
            guard GameLogic.owner(v) == who else { continue }
            let king = v >= 3
            let r = s / 8, c = s % 8
            for (dr, dc) in dirs {
                if king {
                    var rr = r + dr, cc = c + dc
                    while inb(rr, cc), b[rr * 8 + cc] == 0 { quiet.append(CMove(from: s, to: rr * 8 + cc, cap: nil)); rr += dr; cc += dc }
                    if inb(rr, cc), GameLogic.owner(b[rr * 8 + cc]) == enemy {
                        let cap = rr * 8 + cc
                        var lr = rr + dr, lc = cc + dc
                        while inb(lr, lc), b[lr * 8 + lc] == 0 { caps.append(CMove(from: s, to: lr * 8 + lc, cap: cap)); lr += dr; lc += dc }
                    }
                } else {
                    let rr = r + dr, cc = c + dc
                    let fwd = who == .me ? -1 : 1
                    if dr == fwd, inb(rr, cc), b[rr * 8 + cc] == 0 { quiet.append(CMove(from: s, to: rr * 8 + cc, cap: nil)) }
                    let r2 = r + 2 * dr, c2 = c + 2 * dc
                    if inb(r2, c2), GameLogic.owner(b[rr * 8 + cc]) == enemy, b[r2 * 8 + c2] == 0 {
                        caps.append(CMove(from: s, to: r2 * 8 + c2, cap: rr * 8 + cc))
                    }
                }
            }
        }
        if !caps.isEmpty { return caps }
        return chain == nil ? quiet : []
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, m.turn == who else { return nil }
        let from = move / 64, to = move % 64
        guard let mv = moves(m.board, who: who, chain: m.aux).first(where: { $0.from == from && $0.to == to }) else { return nil }
        var n = m
        let v = n.board[from]
        n.board[to] = v
        n.board[from] = 0
        if let c = mv.cap { n.board[c] = 0 }
        var promoted = false
        if v < 3, (who == .me && to / 8 == 0) || (who == .partner && to / 8 == 7) { n.board[to] = v + 2; promoted = true }
        _ = promoted
        n.moves += 1; n.last = to; n.updated = Date()
        if mv.cap != nil, !moves(n.board, who: who, chain: to).isEmpty, moves(n.board, who: who, chain: to).allSatisfy({ $0.cap != nil }) {
            n.aux = to
            return n
        }
        n.aux = nil
        let opp = GameLogic.other(who)
        if moves(n.board, who: opp, chain: nil).isEmpty { GameLogic.finish(&n, winner: who) } else { n.turn = opp }
        return n
    }
}

// MARK: - Морской бой
// board (в моём виде): 0..99 мой флот, 100..199 флот соперника, 200..299 выстрелы по мне, 300..399 мои выстрелы.
// aux: бит 0 — я расставил, бит 1 — соперник расставил. Выстрелы: 1 — мимо, 2 — попадание.

enum Battleship {
    static let fleet = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1]

    static func randomLayout() -> [Int] {
        var grid = Array(repeating: 0, count: 100)
        func free(_ r: Int, _ c: Int) -> Bool {
            for dr in -1...1 { for dc in -1...1 {
                let rr = r + dr, cc = c + dc
                if rr >= 0, rr < 10, cc >= 0, cc < 10, grid[rr * 10 + cc] != 0 { return false }
            } }
            return true
        }
        for len in fleet {
            var placed = false
            var tries = 0
            while !placed && tries < 500 {
                tries += 1
                let horiz = Bool.random()
                let r = Int.random(in: 0..<(horiz ? 10 : 11 - len)), c = Int.random(in: 0..<(horiz ? 11 - len : 10))
                let cells = (0..<len).map { horiz ? (r, c + $0) : (r + $0, c) }
                if cells.allSatisfy({ free($0.0, $0.1) }) {
                    for (rr, cc) in cells { grid[rr * 10 + cc] = 1 }
                    placed = true
                }
            }
            if !placed { return randomLayout() }
        }
        return grid
    }

    static func ready(_ m: GameMatch, layout: [Int], by who: Who) -> GameMatch? {
        guard m.kind == .battleship, m.state == .playing, layout.count == 100 else { return nil }
        var n = m
        let bit = who == .me ? 1 : 2
        guard (n.aux ?? 0) & bit == 0 else { return nil }
        if who == .me { for i in 0..<100 { n.board[i] = layout[i] } }
        else { for i in 0..<100 { n.board[100 + i] = layout[i] } }
        n.aux = (n.aux ?? 0) | bit
        n.updated = Date()
        return n
    }

    static func bothReady(_ m: GameMatch) -> Bool { (m.aux ?? 0) == 3 }

    static func shipCells(_ b: [Int], base: Int, from: Int) -> [Int] {
        var seen = Set<Int>(), stack = [from]
        while let s = stack.popLast() {
            if seen.contains(s) || b[base + s] != 1 { continue }
            seen.insert(s)
            let r = s / 10, c = s % 10
            if r > 0 { stack.append(s - 10) }
            if r < 9 { stack.append(s + 10) }
            if c > 0 { stack.append(s - 1) }
            if c < 9 { stack.append(s + 1) }
        }
        return Array(seen)
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, bothReady(m), m.turn == who, move >= 0, move < 100 else { return nil }
        // Стреляющий всегда «я» в своём виде: по чужому полю — сегмент 300, флот соперника — 100.
        // Для who == .partner (игра с одного телефона невозможна) логика не нужна.
        guard who == .me else { return nil }
        guard m.board[300 + move] == 0 else { return nil }
        var n = m
        n.moves += 1; n.last = move; n.updated = Date()
        if n.board[100 + move] == 1 {
            n.board[300 + move] = 2
            let ship = shipCells(n.board, base: 100, from: move)
            if ship.allSatisfy({ n.board[300 + $0] == 2 }) {
                for s in ship {
                    let r = s / 10, c = s % 10
                    for dr in -1...1 { for dc in -1...1 {
                        let rr = r + dr, cc = c + dc
                        if rr >= 0, rr < 10, cc >= 0, cc < 10, n.board[300 + rr * 10 + cc] == 0 { n.board[300 + rr * 10 + cc] = 1 }
                    } }
                }
            }
            let total = n.board[100..<200].filter { $0 == 1 }.count
            let hits = (0..<100).filter { n.board[100 + $0] == 1 && n.board[300 + $0] == 2 }.count
            if hits == total { GameLogic.finish(&n, winner: .me) }
        } else {
            n.board[300 + move] = 1
            n.turn = .partner
        }
        return n
    }
}

// MARK: - Дурак (подкидной, 36 карт)
// card = suit*9 + rank; suit: 0 ♣, 1 ♦, 2 ♥, 3 ♠; rank 0..8 = 6..Т.
// board[card]: 0 колода, 1 у меня, 2 у соперника, 3 на столе, 5 бито. extra — колода (первая — верхняя, последняя — козырь).
// table — пары [атака, защита или -1]. aux — козырная масть. starter — атакующий. Ходы: 0..35 карта, 100 «бито», 101 «беру».

enum Durak {
    static let suits = ["♣", "♦", "♥", "♠"]
    static let ranks = ["6", "7", "8", "9", "10", "В", "Д", "К", "Т"]
    static func name(_ c: Int) -> String { ranks[c % 9] + suits[c / 9] }
    static func isRed(_ c: Int) -> Bool { c / 9 == 1 || c / 9 == 2 }

    static func hand(_ b: [Int], _ w: Who) -> [Int] { (0..<36).filter { b[$0] == GameLogic.piece(w) } }

    static func beats(_ def: Int, _ att: Int, trump: Int) -> Bool {
        if def / 9 == att / 9 { return def % 9 > att % 9 }
        return def / 9 == trump && att / 9 != trump
    }

    static func firstOpen(_ m: GameMatch) -> Int? {
        guard let t = m.table else { return nil }
        var i = 0
        while i + 1 < t.count { if t[i + 1] == -1 { return i }; i += 2 }
        return nil
    }

    static func canAttackWith(_ m: GameMatch, card: Int) -> Bool {
        let t = m.table ?? []
        if t.isEmpty { return true }
        let ranks = Set(t.filter { $0 >= 0 }.map { $0 % 9 })
        return ranks.contains(card % 9) && t.count / 2 < 6
    }

    /// Какие карты из руки можно сыграть прямо сейчас (для подсветки).
    static func playable(_ m: GameMatch, who: Who) -> [Int] {
        guard m.state == .playing, m.turn == who else { return [] }
        let h = hand(m.board, who)
        let trump = m.aux ?? 0
        if let open = firstOpen(m) {
            guard who != m.starter, let t = m.table else { return [] }
            return h.filter { beats($0, t[open], trump: trump) }
        }
        guard who == m.starter else { return [] }
        let opp = hand(m.board, GameLogic.other(who)).count
        guard opp > 0 else { return [] }
        return h.filter { canAttackWith(m, card: $0) }
    }

    private static func draw(_ n: inout GameMatch, _ w: Who) {
        var deck = n.extra ?? []
        while hand(n.board, w).count < 6, !deck.isEmpty { n.board[deck.removeFirst()] = GameLogic.piece(w) }
        n.extra = deck
    }

    private static func checkEnd(_ n: inout GameMatch) {
        guard (n.extra ?? []).isEmpty, (n.table ?? []).isEmpty else { return }
        let a = hand(n.board, .me).count, b = hand(n.board, .partner).count
        if a == 0 && b == 0 { GameLogic.finish(&n, winner: nil) }
        else if a == 0 { GameLogic.finish(&n, winner: .me) }
        else if b == 0 { GameLogic.finish(&n, winner: .partner) }
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, m.turn == who else { return nil }
        var n = m
        let attacker = m.starter, defender = GameLogic.other(m.starter)
        var t = m.table ?? []
        n.moves += 1; n.updated = Date()
        if move >= 0 && move < 36 {
            guard playable(m, who: who).contains(move) else { return nil }
            n.last = move
            n.board[move] = 3
            if who == attacker, firstOpen(m) == nil {
                t += [move, -1]
                n.turn = defender
            } else if let open = firstOpen(m) {
                t[open + 1] = move
                n.turn = Durak.firstOpen({ var x = m; x.table = t; return x }()) == nil ? attacker : defender
            }
            n.table = t
            // Если у защитника не осталось карт, а всё побито — ход атакующего (можно «бито»).
            return n
        }
        if move == 100 {
            guard who == attacker, !t.isEmpty, firstOpen(m) == nil else { return nil }
            for c in t where c >= 0 { n.board[c] = 5 }
            n.table = []
            draw(&n, attacker); draw(&n, defender)
            n.starter = defender
            n.turn = defender
            checkEnd(&n)
            return n
        }
        if move == 101 {
            guard who == defender, firstOpen(m) != nil else { return nil }
            for c in t where c >= 0 { n.board[c] = GameLogic.piece(defender) }
            n.table = []
            draw(&n, attacker)
            n.turn = attacker
            checkEnd(&n)
            return n
        }
        return nil
    }
}

// MARK: - Найди пару
// board: 0 закрыта, 1/2 — угадана мной/соперником, 3 — открыта сейчас. extra — раскладка (номер картинки). aux — пара, показанная и не совпавшая (a*16+b).

enum MemoryGame {
    static let faces = ["🍓", "🐱", "🚀", "🌈", "🍕", "🎈", "🦄", "🌻"]

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, m.turn == who, move >= 0, move < 16, let layout = m.extra else { return nil }
        var n = m
        if let p = n.aux { n.board[p / 16] = 0; n.board[p % 16] = 0; n.aux = nil }
        guard n.board[move] == 0 else { return nil }
        n.moves += 1; n.last = move; n.updated = Date()
        let open = (0..<16).filter { n.board[$0] == 3 }
        if open.isEmpty {
            n.board[move] = 3
        } else {
            let j = open[0]
            if layout[j] == layout[move] {
                n.board[j] = GameLogic.piece(who); n.board[move] = GameLogic.piece(who)
                if !n.board.contains(0) {
                    let a = n.board.filter { $0 == 1 }.count, b = n.board.filter { $0 == 2 }.count
                    GameLogic.finish(&n, winner: a == b ? nil : (a > b ? .me : .partner))
                }
            } else {
                n.board[move] = 3
                n.aux = j * 16 + move
                n.turn = GameLogic.other(who)
            }
        }
        return n
    }
}

// MARK: - Камень-ножницы-бумага
// board [мой выбор, выбор соперника]: 0 нет, 1 камень, 2 ножницы, 3 бумага. extra [мои победы, победы соперника, раунд].

enum RPS {
    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, (1...3).contains(move), m.board.count == 2, var e = m.extra, e.count == 3 else { return nil }
        var n = m
        if n.board[0] != 0 && n.board[1] != 0 { n.board = [0, 0] }          // новый раунд
        let idx = who == .me ? 0 : 1
        guard n.board[idx] == 0 else { return nil }
        n.board[idx] = move
        n.updated = Date(); n.moves += 1
        if n.board[0] != 0 && n.board[1] != 0 {
            let a = n.board[0], b = n.board[1]
            if a != b {
                let meWins = (a == 1 && b == 2) || (a == 2 && b == 3) || (a == 3 && b == 1)
                if meWins { e[0] += 1 } else { e[1] += 1 }
            }
            e[2] += 1
            n.extra = e
            if e[0] >= 2 { GameLogic.finish(&n, winner: .me) }
            else if e[1] >= 2 { GameLogic.finish(&n, winner: .partner) }
        }
        return n
    }
}

// MARK: - Виселица
// word — слово (заглавные), guesses — названные буквы. starter — загадавший, turn — угадывающий. Ход: номер буквы в алфавите.

enum Hangman {
    static let alphabet = Array("АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ")
    static let maxWrong = 7

    static func normalize(_ s: String) -> String {
        String(s.uppercased().replacingOccurrences(of: "Ё", with: "Е").filter { alphabet.contains($0) })
    }

    static func wrongCount(_ m: GameMatch) -> Int {
        guard let w = m.word, let g = m.guesses else { return 0 }
        return g.filter { !w.contains($0) }.count
    }

    static func setWord(_ m: GameMatch, word: String, by who: Who) -> GameMatch? {
        let w = normalize(word)
        guard m.kind == .hangman, m.word == nil, m.starter == who, (3...14).contains(w.count) else { return nil }
        var n = m
        n.word = w
        n.guesses = ""
        n.turn = GameLogic.other(who)
        n.updated = Date()
        return n
    }

    static func play(_ m: GameMatch, move: Int, by who: Who) -> GameMatch? {
        guard m.state == .playing, let w = m.word, m.turn == who, who != m.starter,
              move >= 0, move < alphabet.count else { return nil }
        let ch = alphabet[move]
        var n = m
        let g = m.guesses ?? ""
        guard !g.contains(ch) else { return nil }
        n.guesses = g + String(ch)
        n.moves += 1; n.updated = Date()
        if w.allSatisfy({ n.guesses!.contains($0) }) { GameLogic.finish(&n, winner: who) }
        else if wrongCount(n) >= maxWrong { GameLogic.finish(&n, winner: m.starter) }
        return n
    }
}
