import SwiftUI

struct WalletView: View {
    @EnvironmentObject var router: Router
    static let sections = ["Обзор", "Долги", "Планы", "Анализ"]
    var body: some View {
        switch router.wallet {
        case 1: DebtsView()
        case 2: PlansView()
        case 3: StatsView()
        default: BudgetView()
        }
    }
}

struct WalletHeader: View {
    let title: String
    var onAdd: (() -> Void)?
    var body: some View {
        HStack {
            Text(title).font(.system(size: 32, weight: .bold, design: .rounded))
            Spacer()
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.headline).frame(width: 40, height: 40).background(Theme.soft, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
