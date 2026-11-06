import SwiftUI

// MARK: - Действия в хранилище

extension Store {
    @discardableResult
    func newMatch(_ k: GameKind, starter: Who = .me) -> GameMatch {
        let m = GameLogic.make(k, starter: starter)
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

    func setHangmanWord(_ id: UUID, _ word: String) {
        guard let i = data.matches.firstIndex(where: { $0.id == id }),
              let n = Hangman.setWord(data.matches[i], word: word, by: .me) else { return }
        data.matches[i] = n
        success()
    }

    func readyFleet(_ id: UUID, layout: [Int]) {
        guard let i = data.matches.firstIndex(where: { $0.id == id }),
              let n = Battleship.ready(data.matches[i], layout: layout, by: .me) else { return }
        data.matches[i] = n
        success()
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
    @State private var appeared = false

    private var playing: [GameMatch] { store.data.matches.filter { $0.state == .playing }.sorted { $0.updated > $1.updated } }
    private var finished: [GameMatch] { store.data.matches.filter { $0.state != .playing }.sorted { $0.updated > $1.updated } }

    var body: some View {
        Screen {
            scoreboard

            SectionTitle("Новая партия")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(GameKind.allCases.enumerated()), id: \.element) { idx, k in
                    let locked = k.needsPair && sync.status == .notPaired
                    Button {
                        let m = store.newMatch(k)
                        openID = m.id
                    } label: { kindTile(k, locked: locked) }
                    .buttonStyle(PressStyle())
                    .disabled(locked)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .animation(Motion.spring.delay(Double(idx) * 0.035), value: appeared)
                }
            }

            if !playing.isEmpty {
                SectionTitle("Идут сейчас")
                VStack(spacing: 0) {
                    ForEach(playing) { m in
                        Button { openID = m.id } label: { matchRow(m) }.buttonStyle(PressStyle())
                        if m.id != playing.last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .card()
            }
            if !finished.isEmpty {
                SectionTitle("Сыграны")
                VStack(spacing: 0) {
                    ForEach(finished.prefix(10)) { m in
                        Button { openID = m.id } label: { matchRow(m) }.buttonStyle(PressStyle())
                        if m.id != finished.prefix(10).last?.id { Divider().padding(.leading, 72) }
                    }
                }
                .card()
            }

            Text(sync.status == .notPaired
                 ? "Пока вы не соединились с партнёром, партии идут на одном телефоне — передавайте его друг другу."
                 : "Играйте с разных телефонов: ход партнёра появится у вас сразу. Игры со скрытыми картами и флотом (Морской бой, Дурак, Камень-ножницы-бумага, Виселица) доступны после соединения.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { appeared = true }
        .navigationTitle("Игры")
        .navigationDestination(item: $openID) { id in MatchView(matchID: id) }
        .animation(Motion.spring, value: store.data.matches.count)
    }

    private func kindTile(_ k: GameKind, locked: Bool) -> some View {
        let c = Color(hex: k.hex)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.r(26), style: .continuous)
                .fill(LinearGradient(colors: [c.opacity(0.34), c.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: Theme.r(26), style: .continuous)
                .stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            Text(k.art).font(.system(size: 64)).rotationEffect(.degrees(-10)).opacity(0.9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(.trailing, 8).padding(.bottom, 2)
                .shadow(color: c.opacity(0.4), radius: 10, y: 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 6)
                Text(k.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(2).minimumScaleFactor(0.8).frame(maxWidth: 110, alignment: .leading)
                Text(locked ? "Нужна пара" : k.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 110, alignment: .leading)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 138, maxHeight: 138, alignment: .topLeading)
        .opacity(locked ? 0.5 : 1)
    }

    private var scoreboard: some View {
        let a = store.wins(.me), b = store.wins(.partner)
        return HStack(spacing: 0) {
            side(.me, n: a, leads: a > b)
            VStack(spacing: 4) {
                Text("VS").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 2, height: 44)
            }
            side(.partner, n: b, leads: b > a)
        }
        .padding(.vertical, 18)
        .background(
            LinearGradient(colors: [store.meColor.opacity(0.22), store.partnerColor.opacity(0.22)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: Theme.r(28), style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.r(28), style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
        .animation(Motion.spring, value: a)
        .animation(Motion.spring, value: b)
    }

    private func side(_ w: Who, n: Int, leads: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                PlayerAvatar(who: w, size: 50).padding(.top, 10)
                if leads {
                    Image(systemName: "crown.fill").font(.system(size: 16)).foregroundStyle(Color(hex: "F5B83D"))
                        .shadow(color: Color(hex: "F5B83D").opacity(0.6), radius: 4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Text("\(n)").font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit()).contentTransition(.numericText())
            Text("\(store.name(w)) · побед").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
                .background(highlight ? store.meColor.opacity(0.25) : Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
                .background { if highlight { PulseRing(color: store.meColor).padding(2) } }
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
        .overlay {
            if let m, m.state == .won, let w = m.winner {
                ConfettiBurst(colors: [store.color(w), Color(hex: "F5B83D"), Color(hex: "FF9AA8"), Color(hex: "8EC5FF"), Color(hex: "B7A6FF")])
                    .id(m.id.uuidString + "win")
            }
        }
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
        .onChange(of: m?.state) { _, st in
            if st == .won { store.tap() }
        }
    }

    private func playingText(_ m: GameMatch) -> String {
        switch m.kind {
        case .rps: return "Раунд \(m.extra?.last ?? 1)"
        case .battleship where !Battleship.bothReady(m): return "Расстановка флота"
        case .hangman where m.word == nil: return m.starter == .me ? "Загадайте слово" : "\(store.name(m.starter)) загадывает слово"
        case .hangman: return m.starter == .me ? "\(store.name(.partner)) угадывает" : "Угадывайте слово"
        case .durak:
            if m.turn == .me { return m.starter == .me ? "Ваша атака" : "Ваша защита" }
            return "Ход: \(store.name(m.turn))"
        default:
            return hotSeat ? "Ход: \(store.name(m.turn))" : (m.turn == .me ? "Ваш ход" : "Ход: \(store.name(m.turn))")
        }
    }

    private func header(_ m: GameMatch) -> some View {
        let text: String
        var who: Who? = m.turn
        switch m.state {
        case .playing: text = playingText(m)
        case .won: text = "Победил(а) \(store.name(m.winner ?? .me))"; who = m.winner
        case .draw: text = "Ничья"; who = nil
        }
        return TurnBanner(turn: m.state == .playing ? who : nil, text: text)
            .padding(.horizontal, 16)
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
            } else if !hotSeat && m.turn != .me && m.kind != .rps && !(m.kind == .battleship && !Battleship.bothReady(m)) && !(m.kind == .hangman && m.word == nil) {
                HStack(spacing: 8) { Text("Ждём ход партнёра").font(.footnote).foregroundStyle(.secondary); TypingDots() }
            }
        }
    }

    private func canTap(_ m: GameMatch) -> Bool {
        m.state == .playing && (hotSeat || m.turn == .me)
    }

    private func tryMove(_ m: GameMatch, _ index: Int) {
        guard canTap(m) else { return }
        withAnimation(Motion.spring) { store.move(m.id, index, by: m.turn) }
    }

    @ViewBuilder
    private func board(_ m: GameMatch) -> some View {
        let win = Set(GameLogic.winCells(m.kind, m.board) ?? [])
        switch m.kind {
        case .ttt: tttBoard(m, win)
        case .four: fourBoard(m, win)
        case .reversi: reversiBoard(m)
        case .dots: DotsBoard(m: m, send: { tryMove(m, $0) }, enabled: canTap(m))
        case .checkers: CheckersBoard(m: m, send: { tryMove(m, $0) }, enabled: canTap(m))
        case .battleship: BattleshipBoard(m: m)
        case .durak: DurakBoard(m: m, send: { tryMove(m, $0) })
        case .memory: MemoryBoard(m: m, send: { tryMove(m, $0) }, enabled: canTap(m))
        case .rps: RPSBoard(m: m)
        case .hangman: HangmanBoard(m: m, send: { tryMove(m, $0) })
        }
    }

    private func tttBoard(_ m: GameMatch, _ win: Set<Int>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(0..<9, id: \.self) { i in
                let p = m.board[i]
                Button { tryMove(m, i) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.r(18), style: .continuous)
                            .fill(win.contains(i) ? store.color(m.winner).opacity(0.28) : Pal.card.opacity(0.75))
                        if p != 0 {
                            DrawnMark(isX: p == 1, color: store.color(p == 1 ? .me : .partner))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(PressStyle())
            }
        }
        .boardPanel()
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
                            DropDisc(owner: m.board[i], row: r, win: win.contains(i))
                        }
                    }
                    .padding(4)
                    .background(Pal.card.opacity(valid.contains(c) && canTap(m) ? 1 : 0.7), in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .boardPanel()
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
                                FlipDisc(owner: p, isLast: m.last == i)
                                if p == 0, valid.contains(i), canTap(m) {
                                    Circle().fill(.white.opacity(0.35)).frame(width: 8, height: 8)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                        .buttonStyle(PressStyle())
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous))
        .boardPanel()
        .frame(maxWidth: 460)
    }
}
