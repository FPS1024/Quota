import SwiftUI

@main
struct QuotaApp: App {
    @StateObject private var store = ProviderStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
