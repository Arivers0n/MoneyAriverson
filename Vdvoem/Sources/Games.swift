import SwiftUI

struct GamesView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Screen {
            HStack {
                stat(.me)
                Divider().frame(height: 50)
                stat(.partner)
            }
            .padding(18).card()

            SectionTitle("На двоих")
            VStack(spacing: 0) {
                link("Крестики-нолики", "number") { TicTacToeGame() }
                link("4 в ряд", "square.grid.3x3.square") { ConnectFourGame() }
                link("Реверси", "circle.lefthalf.filled") { ReversiGame() }
                soon("Точки и квадратики", "circle.grid.3x3.fill")
                soon("Шашки", "circle.circle")
                soon("Морской бой", "sailboat")
                soon("Дурак", "suit.spade")
            }
            .card()
            Text("Игры на одном телефоне — передавайте друг другу. За победу — очко. Каждые 5 очков — новый уровень.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Игры")
    }

    private func stat(_ w: Who) -> some View {
        let pts = w == .me ? store.data.pointsMe : store.data.pointsPartner
        return HStack(spacing: 10) {
            Circle().fill(store.color(w)).frame(width: 18, height: 18)
            VStack(alignment: .leading) {
                Text("\(pts)").font(.title.bold().monospacedDigit())
                Text("\(store.name(w)) · ур. \(store.level(w))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func link<D: View>(_ t: String, _ icon: String, @ViewBuilder _ dest: @escaping () -> D) -> some View {
        VStack(spacing: 0) {
            NavigationLink { dest().navigationTitle(t).navigationBarTitleDisplayMode(.inline) } label: {
                row(t, icon, "Новая партия", chevron: true)
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 72)
        }
    }

    private func soon(_ t: String, _ icon: String) -> some View {
        VStack(spacing: 0) {
            row(t, icon, "Скоро", chevron: false).opacity(0.5)
            if t != "Дурак" { Divider().padding(.leading, 72) }
        }
    }

    private func row(_ t: String, _ icon: String, _ sub: String, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                .background(Pal.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(t).font(.body.weight(.medium))
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if chevron { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
    }
}

// MARK: - Общие части игр

private struct GameFrame<Content: View>: View {
    @EnvironmentObject var store: Store
    let status: String
    let turn: Who?
    let onReset: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                if let turn { Circle().fill(store.color(turn)).frame(width: 14, height: 14) }
                Text(status).font(.headline)
            }
            .padding(.top, 20)
            content.padding(.horizontal, 16)
            Button(action: onReset) { Text("Новая партия").bigButton() }.padding(.horizontal, 16)
            Spacer()
        }
        .background(Pal.bg.ignoresSafeArea())
    }
}

// MARK: - Крестики-нолики

struct TicTacToeGame: View {
    @EnvironmentObject var store: Store
    @State private var board = Array(repeating: 0, count: 9)   // 1 — я, 2 — партнёр
    @State private var turn = 1
    @State private var winner = 0
    private let lines = [[0,1,2],[3,4,5],[6,7,8],[0,3,6],[1,4,7],[2,5,8],[0,4,8],[2,4,6]]

    var body: some View {
        GameFrame(status: status, turn: winner == 0 ? (turn == 1 ? .me : .partner) : nil, onReset: reset) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(0..<9, id: \.self) { i in
                    Button { play(i) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: min(store.radius, 20), style: .continuous).fill(Pal.card)
                            if board[i] == 1 { Image(systemName: "xmark").font(.system(size: 44, weight: .bold)).foregroundStyle(store.meColor) }
                            if board[i] == 2 { Image(systemName: "circle").font(.system(size: 44, weight: .bold)).foregroundStyle(store.partnerColor) }
                        }
                        .aspectRatio(1, contentMode: .fit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var status: String {
        if winner == 3 { return "Ничья" }
        if winner > 0 { return "Победил(а) \(store.name(winner == 1 ? .me : .partner))" }
        return "Ход: \(store.name(turn == 1 ? .me : .partner))"
    }

    private func play(_ i: Int) {
        guard winner == 0, board[i] == 0 else { return }
        board[i] = turn
        store.tap()
        if lines.contains(where: { $0.allSatisfy { board[$0] == turn } }) {
            winner = turn
            store.addPoints(turn == 1 ? .me : .partner)
            store.success()
        } else if !board.contains(0) { winner = 3 }
        else { turn = 3 - turn }
    }

    private func reset() { board = Array(repeating: 0, count: 9); winner = 0; turn = 1 }
}

// MARK: - 4 в ряд

struct ConnectFourGame: View {
    @EnvironmentObject var store: Store
    private let rows = 6, cols = 7
    @State private var board = Array(repeating: Array(repeating: 0, count: 7), count: 6)
    @State private var turn = 1
    @State private var winner = 0

    var body: some View {
        GameFrame(status: status, turn: winner == 0 ? (turn == 1 ? .me : .partner) : nil, onReset: reset) {
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(0..<cols, id: \.self) { c in
                            Circle()
                                .fill(board[r][c] == 0 ? Pal.field : (board[r][c] == 1 ? store.meColor : store.partnerColor))
                                .aspectRatio(1, contentMode: .fit)
                                .contentShape(Circle())
                                .onTapGesture { drop(c) }
                        }
                    }
                }
            }
            .padding(10).card()
        }
    }

    private var status: String {
        if winner == 3 { return "Ничья" }
        if winner > 0 { return "Победил(а) \(store.name(winner == 1 ? .me : .partner))" }
        return "Ход: \(store.name(turn == 1 ? .me : .partner))"
    }

    private func drop(_ c: Int) {
        guard winner == 0 else { return }
        guard let r = (0..<rows).reversed().first(where: { board[$0][c] == 0 }) else { return }
        board[r][c] = turn
        store.tap()
        if wins(r, c) {
            winner = turn
            store.addPoints(turn == 1 ? .me : .partner)
            store.success()
        } else if !board[0].contains(0) { winner = 3 }
        else { turn = 3 - turn }
    }

    private func wins(_ r: Int, _ c: Int) -> Bool {
        let p = board[r][c]
        for (dr, dc) in [(0, 1), (1, 0), (1, 1), (1, -1)] {
            var n = 1
            for s in [1, -1] {
                var rr = r + dr * s, cc = c + dc * s
                while rr >= 0, rr < rows, cc >= 0, cc < cols, board[rr][cc] == p {
                    n += 1; rr += dr * s; cc += dc * s
                }
            }
            if n >= 4 { return true }
        }
        return false
    }

    private func reset() { board = Array(repeating: Array(repeating: 0, count: 7), count: 6); winner = 0; turn = 1 }
}

// MARK: - Реверси

struct ReversiGame: View {
    @EnvironmentObject var store: Store
    @State private var b = ReversiGame.initial()
    @State private var turn = 1
    @State private var finished = false
    private let dirs = [(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]

    static func initial() -> [[Int]] {
        var g = Array(repeating: Array(repeating: 0, count: 8), count: 8)
        g[3][3] = 2; g[4][4] = 2; g[3][4] = 1; g[4][3] = 1
        return g
    }

    private func flips(_ r: Int, _ c: Int, _ p: Int, _ g: [[Int]]) -> [(Int, Int)] {
        guard g[r][c] == 0 else { return [] }
        var out: [(Int, Int)] = []
        for (dr, dc) in dirs {
            var rr = r + dr, cc = c + dc
            var line: [(Int, Int)] = []
            while rr >= 0, rr < 8, cc >= 0, cc < 8, g[rr][cc] == 3 - p {
                line.append((rr, cc)); rr += dr; cc += dc
            }
            if rr >= 0, rr < 8, cc >= 0, cc < 8, g[rr][cc] == p { out += line }
        }
        return out
    }

    private func hasMove(_ p: Int) -> Bool {
        for r in 0..<8 { for c in 0..<8 where !flips(r, c, p, b).isEmpty { return true } }
        return false
    }

    private var counts: (Int, Int) {
        let all = b.flatMap { $0 }
        return (all.filter { $0 == 1 }.count, all.filter { $0 == 2 }.count)
    }

    private var status: String {
        let (a, p) = counts
        if finished {
            if a == p { return "Ничья \(a):\(p)" }
            return "Победил(а) \(store.name(a > p ? .me : .partner)) · \(a):\(p)"
        }
        return "Ход: \(store.name(turn == 1 ? .me : .partner)) · \(a):\(p)"
    }

    var body: some View {
        GameFrame(status: status, turn: finished ? nil : (turn == 1 ? .me : .partner), onReset: reset) {
            VStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<8, id: \.self) { c in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Pal.card)
                                if b[r][c] != 0 {
                                    Circle().fill(b[r][c] == 1 ? store.meColor : store.partnerColor).padding(4)
                                } else if !finished && !flips(r, c, turn, b).isEmpty {
                                    Circle().fill(store.color(turn == 1 ? .me : .partner).opacity(0.3)).frame(width: 8, height: 8)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .onTapGesture { play(r, c) }
                        }
                    }
                }
            }
        }
    }

    private func play(_ r: Int, _ c: Int) {
        guard !finished else { return }
        let f = flips(r, c, turn, b)
        guard !f.isEmpty else { return }
        b[r][c] = turn
        for (fr, fc) in f { b[fr][fc] = turn }
        store.tap()
        turn = 3 - turn
        if !hasMove(turn) {
            turn = 3 - turn
            if !hasMove(turn) {
                finished = true
                let (a, p) = counts
                if a != p { store.addPoints(a > p ? .me : .partner); store.success() }
            }
        }
    }

    private func reset() { b = ReversiGame.initial(); turn = 1; finished = false }
}
