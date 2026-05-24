import SwiftUI

@main
struct AccountantAppApp: App {
    @StateObject private var appState: AppState

    init() {
        let repository = LocalJSONLedgerRepository.live()
        let classificationRuleRepository = LocalJSONClassificationRuleRepository.live()
        _appState = StateObject(
            wrappedValue: AppState(repository: repository, classificationRuleRepository: classificationRuleRepository)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task {
                    await appState.loadIfNeeded()
                }
        }
    }
}
