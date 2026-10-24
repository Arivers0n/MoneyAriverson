import SwiftUI

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
