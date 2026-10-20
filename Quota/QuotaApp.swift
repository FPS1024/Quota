import SwiftUI

@main
struct QuotaApp: App {
    @StateObject private var store = ProviderStore()
    @StateObject private var codexUsageStore = CodexUsageStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(codexUsageStore)
        }
    }
}
