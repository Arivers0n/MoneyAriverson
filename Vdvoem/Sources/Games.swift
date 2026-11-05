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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(GameKind.allCases) { k in
                    let locked = k.needsPair && sync.status == .notPaired
                    Button {
                        let m = store.newMatch(k)
                        openID = m.id
                    } label: { kindTile(k, locked: locked) }
                    .buttonStyle(PressStyle())
                    .disabled(locked)
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
                 : "Играйте с разных телефонов: ход партнёра появится у вас сразу. Игры со скрытыми картами и флотом (Морской бой, Дурак, Камень-ножницы-бумага, Виселица) доступны после соединения. Фоновых уведомлений нет — откройте приложение.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Игры")
        .navigationDestination(item: $openID) { id in MatchView(matchID: id) }
        .animation(Motion.spring, value: store.data.matches.count)
    }

    private func kindTile(_ k: GameKind, locked: Bool) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ArtIcon(symbol: k.icon, color: Color(hex: k.hex), size: 26)
                Spacer(minLength: 0)
                if locked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 6)
            Text(k.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(locked ? "Нужна пара" : k.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, maxHeight: 132, alignment: .topLeading)
        .card()
        .opacity(locked ? 0.5 : 1)
    }

    private func stat(_ w: Who) -> some View {
        HStack(spacing: 10) {
            Circle().fill(store.color(w)).frame(width: 18, height: 18)
            VStack(alignment: .leading) {
                Text("\(store.wins(w))").font(.title.weight(.semibold).monospacedDigit()).contentTransition(.numericText())
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
                .background(highlight ? store.meColor.opacity(0.25) : Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
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
        return HStack(spacing: 8) {
            if let who { Circle().fill(store.color(who)).frame(width: 14, height: 14) }
            Text(text).font(.headline).contentTransition(.opacity)
        }
        .animation(Motion.curve(0.2), value: text)
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
                Text("Ждём ход партнёра…").font(.footnote).foregroundStyle(.secondary)
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
                            .fill(win.contains(i) ? store.color(m.winner).opacity(0.28) : Pal.card)
                        if p != 0 {
                            Image(systemName: p == 1 ? "xmark" : "circle")
                                .font(.system(size: 44, weight: .semibold))
                                .foregroundStyle(store.color(p == 1 ? .me : .partner))
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
                .buttonStyle(PressStyle())
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
                    .background(Pal.card.opacity(valid.contains(c) && canTap(m) ? 1 : 0.7), in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                }
                .buttonStyle(PressStyle())
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
        .frame(maxWidth: 460)
    }
}
