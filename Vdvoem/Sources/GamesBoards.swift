import SwiftUI

@MainActor private func ownerColor(_ store: Store, _ v: Int) -> Color {
    store.color(GameLogic.owner(v))
}

// MARK: - Точки и квадратики

struct DotsBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    let send: (Int) -> Void
    let enabled: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                score(.me)
                Spacer()
                score(.partner)
            }
            GeometryReader { g in
                let pad: CGFloat = 18
                let s = (min(g.size.width, 420) - pad * 2) / 4
                ZStack(alignment: .topLeading) {
                    // клетки
                    ForEach(0..<16, id: \.self) { b in
                        let v = m.board[40 + b]
                        let r = b / 4, c = b % 4
                        RoundedRectangle(cornerRadius: Theme.r(6), style: .continuous)
                            .fill(v == 0 ? Color.clear : ownerColor(store, v).opacity(0.38))
                            .frame(width: s - 6, height: s - 6)
                            .overlay(Text(v == 0 ? "" : String(store.name(GameLogic.owner(v) ?? .me).prefix(1)).uppercased())
                                .font(.system(size: s * 0.38, weight: .medium)).foregroundStyle(ownerColor(store, v)))
                            .offset(x: pad + CGFloat(c) * s + 3, y: pad + CGFloat(r) * s + 3)
                            .animation(Motion.spring, value: v)
                    }
                    // рёбра
                    ForEach(0..<40, id: \.self) { e in
                        let horiz = e < 20
                        let i = horiz ? e : e - 20
                        let r = horiz ? i / 4 : i / 5
                        let c = horiz ? i % 4 : i % 5
                        let v = m.board[e]
                        let cx = pad + (horiz ? (CGFloat(c) + 0.5) * s : CGFloat(c) * s)
                        let cy = pad + (horiz ? CGFloat(r) * s : (CGFloat(r) + 0.5) * s)
                        Button { send(e) } label: {
                            Capsule()
                                .fill(v == 0 ? Color.primary.opacity(0.12) : ownerColor(store, v))
                                .frame(width: horiz ? s - 14 : 7, height: horiz ? 7 : s - 14)
                                .overlay(Capsule().stroke(.white.opacity(m.last == e ? 0.9 : 0), lineWidth: 2))
                                .frame(width: horiz ? s - 6 : 30, height: horiz ? 30 : s - 6)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .disabled(v != 0 || !enabled)
                        .position(x: cx, y: cy)
                    }
                    // точки
                    ForEach(0..<25, id: \.self) { d in
                        Circle().fill(Color.primary.opacity(0.75)).frame(width: 11, height: 11)
                            .position(x: pad + CGFloat(d % 5) * s, y: pad + CGFloat(d / 5) * s)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: min(g.size.width, 420), height: s * 4 + pad * 2)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 400)
            Text("Замкнули квадрат — ходите ещё раз").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func score(_ w: Who) -> some View {
        let n = m.board[40...].filter { $0 == GameLogic.piece(w) }.count
        return HStack(spacing: 8) {
            Circle().fill(store.color(w)).frame(width: 12, height: 12)
            Text("\(store.name(w)): \(n)").font(.headline.monospacedDigit())
        }
    }
}

// MARK: - Шашки

struct CheckersBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    let send: (Int) -> Void
    let enabled: Bool
    @State private var sel: Int?

    private var all: [CMove] { Checkers.moves(m.board, who: m.turn, chain: m.aux) }
    private var targets: [CMove] {
        guard let s = sel ?? m.aux else { return [] }
        return all.filter { $0.from == s }
    }

    var body: some View {
        let movable = Set(all.map(\.from))
        let tgt = Set(targets.map(\.to))
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { c in
                            let i = r * 8 + c
                            let dark = (r + c) % 2 == 1
                            let v = m.board[i]
                            Button { tap(i) } label: {
                                ZStack {
                                    Rectangle().fill(dark ? Color(hex: "8B5E3C") : Color(hex: "F0D9B5"))
                                    if tgt.contains(i) { Circle().fill(Color.green.opacity(0.65)).frame(width: 14, height: 14) }
                                    if v != 0 {
                                        let col = ownerColor(store, v)
                                        Circle().fill(RadialGradient(colors: [col.opacity(0.75), col], center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 24))
                                            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                                            .overlay(Circle().stroke(Color.yellow, lineWidth: (sel ?? m.aux) == i ? 4 : (enabled && movable.contains(i) && sel == nil ? 2 : 0)))
                                            .overlay(v >= 3 ? Image(systemName: "crown.fill").font(.system(size: 14)).foregroundStyle(.white) : nil)
                                            .padding(4)
                                            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
                                            .transition(.scale)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.r(12), style: .continuous))
            .frame(maxWidth: 440)
            Text(m.aux != nil ? "Продолжайте бить этой же шашкой" : (all.contains { $0.cap != nil } ? "Бить обязательно" : " "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: m.moves) { _, _ in sel = nil }
    }

    private func tap(_ i: Int) {
        guard enabled else { return }
        if let s = sel ?? m.aux, let mv = all.first(where: { $0.from == s && $0.to == i }) {
            send(mv.from * 64 + mv.to); sel = nil; return
        }
        if m.aux == nil, all.contains(where: { $0.from == i }) { sel = i; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        else if m.aux == nil { sel = nil }
    }
}

// MARK: - Морской бой

struct BattleshipBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    @State private var layout = Battleship.randomLayout()

    private var myReady: Bool { (m.aux ?? 0) & 1 != 0 }

    var body: some View {
        VStack(spacing: 14) {
            if !myReady {
                Text("Расставьте корабли").font(.headline)
                grid(ships: layout, shotsAt: nil, enemy: false, size: 330)
                HStack(spacing: 12) {
                    Button { withAnimation { layout = Battleship.randomLayout() }; store.tap() } label: {
                        Label("Перемешать", systemImage: "shuffle").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .glass(RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous), interactive: true)
                    }.buttonStyle(PressStyle())
                    Button { store.readyFleet(m.id, layout: layout) } label: { Text("Готов").bigButton() }
                }
                Text("Флот: 1×4, 2×3, 3×2, 4×1 клетки").font(.footnote).foregroundStyle(.secondary)
            } else if !Battleship.bothReady(m) {
                grid(ships: Array(m.board[0..<100]), shotsAt: nil, enemy: false, size: 300)
                HStack { ProgressView(); Text("Ждём, пока \(store.name(.partner)) расставит корабли…").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text(m.turn == .me ? "Стреляйте по полю соперника" : "Стреляет \(store.name(.partner))").font(.subheadline.weight(.semibold))
                grid(ships: nil, shotsAt: Array(m.board[300..<400]), enemy: true, size: 340)
                Text("Ваш флот").font(.caption).foregroundStyle(.secondary)
                grid(ships: Array(m.board[0..<100]), shotsAt: Array(m.board[200..<300]), enemy: false, size: 200)
                let left = (0..<100).filter { m.board[$0] == 1 && m.board[200 + $0] != 2 }.count
                Text("Целых клеток у вас: \(left)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func grid(ships: [Int]?, shotsAt: [Int]?, enemy: Bool, size: CGFloat) -> some View {
        let cell = size / 10
        return VStack(spacing: 0) {
            ForEach(0..<10, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { c in
                        let i = r * 10 + c
                        let ship = ships?[i] == 1
                        let shot = shotsAt?[i] ?? 0
                        Button {
                            if enemy, m.turn == .me, shot == 0 { withAnimation(Motion.spring) { store.move(m.id, i, by: .me) } }
                        } label: {
                            ZStack {
                                Rectangle().fill(Color(hex: enemy ? "1F6F9E" : "2F86B8").opacity(0.55))
                                Rectangle().stroke(.white.opacity(0.25), lineWidth: 0.5)
                                if ship { RoundedRectangle(cornerRadius: Theme.r(3)).fill(Color(hex: "E7ECF3")).padding(1.5) }
                                if shot == 1 { Circle().fill(.white.opacity(0.85)).frame(width: cell * 0.2) }
                                if shot == 2 { Image(systemName: "xmark").font(.system(size: cell * 0.6, weight: .medium)).foregroundStyle(Color(hex: "FF4D4D")) }
                            }
                            .frame(width: cell, height: cell)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous).stroke(.white.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Дурак

struct PlayingCard: View {
    let id: Int
    var faceDown = false
    var highlight = false
    var width: CGFloat = 52

    var body: some View {
        let h = width * 1.4
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                .fill(faceDown ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "7C6BE0"), Color(hex: "4C9AF0")], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white))
            RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
                .stroke(highlight ? Color.yellow : Color.black.opacity(0.15), lineWidth: highlight ? 3 : 1)
            if faceDown {
                Image(systemName: "heart.fill").font(.system(size: width * 0.35)).foregroundStyle(.white.opacity(0.6))
            } else {
                VStack(spacing: 0) {
                    Text(Durak.ranks[id % 9]).font(.system(size: width * 0.38, weight: .medium))
                    Text(Durak.suits[id / 9]).font(.system(size: width * 0.42))
                }
                .foregroundStyle(Durak.isRed(id) ? Color(hex: "E5322D") : Color.black)
            }
        }
        .frame(width: width, height: h)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
        .offset(y: highlight ? -8 : 0)
    }
}

struct DurakBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    let send: (Int) -> Void

    private var myHand: [Int] { Durak.hand(m.board, .me).sorted { ($0 / 9 == (m.aux ?? 0) ? 100 : 0) + $0 % 9 < ($1 / 9 == (m.aux ?? 0) ? 100 : 0) + $1 % 9 } }
    private var theirCount: Int { Durak.hand(m.board, .partner).count }
    private var table: [Int] { m.table ?? [] }

    var body: some View {
        let play = Set(Durak.playable(m, who: .me))
        let open = Durak.firstOpen(m)
        let iAttack = m.starter == .me
        VStack(spacing: 14) {
            // колода и козырь
            HStack(spacing: 14) {
                ZStack {
                    if let tr = m.extra?.last { PlayingCard(id: tr, width: 44).rotationEffect(.degrees(90)).offset(x: 14) }
                    if !(m.extra ?? []).isEmpty { PlayingCard(id: 0, faceDown: true, width: 44) }
                }
                .frame(width: 80, height: 70)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Козырь \(Durak.suits[m.aux ?? 0])").font(.headline).foregroundStyle((m.aux == 1 || m.aux == 2) ? Color(hex: "E5322D") : .primary)
                    Text("В колоде: \((m.extra ?? []).count)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    HStack(spacing: -26) { ForEach(0..<min(theirCount, 8), id: \.self) { i in PlayingCard(id: 0, faceDown: true, width: 30).rotationEffect(.degrees(Double(i - 4) * 3)) } }
                    Text("\(store.name(.partner)): \(theirCount)").font(.caption.weight(.semibold))
                }
            }
            .padding(12).card()

            // стол
            VStack(spacing: 6) {
                if table.isEmpty { Text(iAttack ? "Ходите любой картой" : "Ждите атаку").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 110) }
                else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(stride(from: 0, to: table.count, by: 2)), id: \.self) { i in
                                ZStack(alignment: .topLeading) {
                                    PlayingCard(id: table[i], width: 54)
                                    if table[i + 1] >= 0 { PlayingCard(id: table[i + 1], width: 54).offset(x: 20, y: 22).rotationEffect(.degrees(8)) }
                                }
                                .frame(width: 84, height: 110)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(height: 118)
                }
            }
            .padding(10).frame(maxWidth: .infinity).card()

            // кнопки
            HStack(spacing: 12) {
                if m.turn == .me, iAttack, !table.isEmpty, open == nil {
                    Button { send(100) } label: { Text("Бито").bigButton() }
                }
                if m.turn == .me, !iAttack, open != nil {
                    Button { send(101) } label: { Text("Беру").bigButton() }
                }
            }

            // рука
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -10) {
                    ForEach(myHand, id: \.self) { c in
                        Button { if play.contains(c) { send(c) } } label: {
                            PlayingCard(id: c, highlight: play.contains(c), width: 58)
                                .opacity(m.turn == .me && !play.contains(c) ? 0.55 : 1)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            }
            Text(m.turn == .me ? (iAttack ? (open == nil && !table.isEmpty ? "Подкиньте карту того же достоинства или нажмите «Бито»" : "Ваша атака") : "Побейте карту старше мастью или козырем — или возьмите") : "Ходит \(store.name(.partner))")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .animation(Motion.spring, value: m.moves)
    }
}

// MARK: - Найди пару

struct MemoryBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    let send: (Int) -> Void
    let enabled: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                ForEach(Who.allCases, id: \.self) { w in
                    HStack(spacing: 6) {
                        Circle().fill(store.color(w)).frame(width: 12, height: 12)
                        Text("\(store.name(w)): \(m.board.filter { $0 == GameLogic.piece(w) }.count / 2)").font(.headline.monospacedDigit())
                    }
                    if w == .me { Spacer() }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(0..<16, id: \.self) { i in
                    let v = m.board[i]
                    let face = (m.extra?[i]).map { MemoryGame.faces[$0] } ?? "?"
                    Button { send(i) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.r(16), style: .continuous)
                                .fill(v == 0 ? AnyShapeStyle(LinearGradient(colors: [store.meColor, store.partnerColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : (v == 3 ? AnyShapeStyle(Color.white) : AnyShapeStyle(ownerColor(store, v).opacity(0.3))))
                            if v == 0 { Image(systemName: "questionmark").font(.title2.weight(.medium)).foregroundStyle(.white.opacity(0.7)) }
                            else { Text(face).font(.system(size: 38)) }
                        }
                        .aspectRatio(0.85, contentMode: .fit)
                        .rotation3DEffect(.degrees(v == 0 ? 0 : 360), axis: (x: 0, y: 1, z: 0))
                        .animation(Motion.curve(0.4), value: v)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!enabled || v != 0)
                }
            }
            .frame(maxWidth: 420)
            Text(m.aux != nil ? "Не совпало — следующий ход соперника" : "Откройте две одинаковые карточки").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Камень-ножницы-бумага

struct RPSBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    private let items = [(1, "✊", "Камень"), (2, "✌️", "Ножницы"), (3, "✋", "Бумага")]

    private var mine: Int { m.board.count == 2 ? m.board[0] : 0 }
    private var theirs: Int { m.board.count == 2 ? m.board[1] : 0 }
    private var done: Bool { mine != 0 && theirs != 0 }
    private func emoji(_ v: Int) -> String { items.first { $0.0 == v }?.1 ?? "❔" }

    var body: some View {
        let e = m.extra ?? [0, 0, 1]
        VStack(spacing: 18) {
            HStack(spacing: 30) {
                scoreView(.me, e[0])
                Text(":").font(.largeTitle.weight(.medium)).foregroundStyle(.secondary)
                scoreView(.partner, e[1])
            }
            HStack(spacing: 20) {
                hand(mine == 0 ? "❔" : emoji(mine), who: .me)
                Text("VS").font(.headline).foregroundStyle(.secondary)
                hand(done ? emoji(theirs) : (theirs == 0 ? "❔" : "🤫"), who: .partner)
            }
            .frame(height: 150)
            Text(resultText).font(.headline).frame(height: 24)
            if m.state == .playing {
                HStack(spacing: 12) {
                    ForEach(items, id: \.0) { it in
                        Button { store.move(m.id, it.0, by: .me) } label: {
                            VStack(spacing: 4) {
                                Text(it.1).font(.system(size: 44))
                                Text(it.2).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .glass(RoundedRectangle(cornerRadius: Theme.r(22), style: .continuous), interactive: true)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(mine != 0 && !done)
                        .opacity(mine != 0 && !done ? 0.4 : 1)
                    }
                }
                Text("Побеждает тот, кто первым выиграет два раунда").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .animation(Motion.spring, value: m.moves)
    }

    private func scoreView(_ w: Who, _ n: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(n)").font(.system(size: 44, weight: .medium)).contentTransition(.numericText())
            Text(store.name(w)).font(.caption.weight(.semibold)).foregroundStyle(store.color(w)).lineLimit(1)
        }
    }

    private func hand(_ s: String, who: Who) -> some View {
        Text(s).font(.system(size: 76)).frame(width: 120, height: 120)
            .background(store.color(who).opacity(0.18), in: Circle())
            .overlay(Circle().stroke(store.color(who).opacity(0.5), lineWidth: 2))
            .transition(.scale)
    }

    private var resultText: String {
        guard done else { return mine == 0 ? "Выберите ход" : "Ждём ход соперника…" }
        if mine == theirs { return "Ничья — играем ещё" }
        let win = (mine == 1 && theirs == 2) || (mine == 2 && theirs == 3) || (mine == 3 && theirs == 1)
        return win ? "Вы выиграли раунд!" : "Раунд за \(store.name(.partner))"
    }
}

// MARK: - Виселица

struct HangmanBoard: View {
    @EnvironmentObject var store: Store
    let m: GameMatch
    let send: (Int) -> Void
    @State private var input = ""

    private var iSet: Bool { m.starter == .me }

    var body: some View {
        VStack(spacing: 16) {
            if m.word == nil {
                if iSet {
                    VStack(spacing: 12) {
                        Text("Загадайте слово").font(.headline)
                        Text("От 3 до 14 русских букв. \(store.name(.partner)) будет угадывать.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        TextField("Слово", text: $input).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .padding(14).background(Pal.field, in: RoundedRectangle(cornerRadius: Theme.r(14), style: .continuous))
                        Button { store.setHangmanWord(m.id, input) } label: {
                            Text("Загадать").bigButton().opacity((3...14).contains(Hangman.normalize(input).count) ? 1 : 0.4)
                        }
                        .disabled(!(3...14).contains(Hangman.normalize(input).count))
                    }
                    .padding(16).card()
                } else {
                    HStack { ProgressView(); Text("\(store.name(m.starter)) загадывает слово…").foregroundStyle(.secondary) }.padding(.top, 40)
                }
            } else {
                let w = m.word ?? ""
                let g = m.guesses ?? ""
                let wrong = Hangman.wrongCount(m)
                Gallows(stage: wrong).stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 180, height: 170)
                    .animation(Motion.curve(0.3), value: wrong)
                HStack(spacing: 6) {
                    ForEach(Array(w.enumerated()), id: \.offset) { _, ch in
                        let shown = g.contains(ch) || m.state != .playing || iSet
                        Text(shown ? String(ch) : " ")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(g.contains(ch) ? Color.primary : Color.red.opacity(0.8))
                            .frame(width: 26, height: 36)
                            .overlay(Rectangle().frame(height: 3).foregroundStyle(Color.primary.opacity(0.5)), alignment: .bottom)
                    }
                }
                Text("Ошибок: \(wrong) из \(Hangman.maxWrong)").font(.footnote).foregroundStyle(.secondary)
                if !iSet && m.state == .playing {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(Array(Hangman.alphabet.enumerated()), id: \.offset) { i, ch in
                            let used = g.contains(ch)
                            let bad = used && !w.contains(ch)
                            Button { send(i) } label: {
                                Text(String(ch)).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .foregroundStyle(used ? .white : .primary)
                                    .background(used ? (bad ? Color.red.opacity(0.7) : Color(hex: "34C38F")) : Pal.card, in: RoundedRectangle(cornerRadius: Theme.r(10), style: .continuous))
                            }
                            .buttonStyle(PressStyle())
                            .disabled(used || m.turn != .me)
                        }
                    }
                } else if iSet && m.state == .playing {
                    Text("\(store.name(.partner)) угадывает ваше слово").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct Gallows: Shape {
    let stage: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        if stage >= 0 { p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w * 0.55, y: h)) }
        p.move(to: CGPoint(x: w * 0.15, y: h)); p.addLine(to: CGPoint(x: w * 0.15, y: 0))
        p.move(to: CGPoint(x: w * 0.15, y: 0)); p.addLine(to: CGPoint(x: w * 0.6, y: 0))
        p.move(to: CGPoint(x: w * 0.6, y: 0)); p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.15))
        if stage >= 1 { p.addEllipse(in: CGRect(x: w * 0.6 - 14, y: h * 0.15, width: 28, height: 28)) }
        if stage >= 2 { p.move(to: CGPoint(x: w * 0.6, y: h * 0.15 + 28)); p.addLine(to: CGPoint(x: w * 0.6, y: h * 0.58)) }
        if stage >= 3 { p.move(to: CGPoint(x: w * 0.6, y: h * 0.3)); p.addLine(to: CGPoint(x: w * 0.6 - 22, y: h * 0.46)) }
        if stage >= 4 { p.move(to: CGPoint(x: w * 0.6, y: h * 0.3)); p.addLine(to: CGPoint(x: w * 0.6 + 22, y: h * 0.46)) }
        if stage >= 5 { p.move(to: CGPoint(x: w * 0.6, y: h * 0.58)); p.addLine(to: CGPoint(x: w * 0.6 - 20, y: h * 0.8)) }
        if stage >= 6 { p.move(to: CGPoint(x: w * 0.6, y: h * 0.58)); p.addLine(to: CGPoint(x: w * 0.6 + 20, y: h * 0.8)) }
        return p
    }
}
