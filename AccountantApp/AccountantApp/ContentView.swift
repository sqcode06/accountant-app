import SwiftUI

import AccountantCore

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Accountant")
                .font(.largeTitle.bold())

            Text("AccountantCore connected")
                .foregroundStyle(.secondary)

            Text(sampleSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var sampleSummary: String {
        let eur = Currency("EUR")
        let bank = Account(name: "Bank", kind: .asset)

        var ledger = Ledger()
        ledger.addAccount(bank)

        let summaries = ledger.accountBalanceSummaries(
            currency: eur,
            asOf: Date()
        )

        return "Accounts: \(summaries.count)"
    }
}

#Preview {
    ContentView()
}
