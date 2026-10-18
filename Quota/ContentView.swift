import SwiftUI

private enum AppTab: Hashable {
    case quota
    case settings
}

struct ContentView: View {
    @AppStorage("hasGrantedNetworkAccess") private var hasGrantedNetworkAccess = false

    var body: some View {
        Group {
            if hasGrantedNetworkAccess {
                MainTabView()
            } else {
                InitView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasGrantedNetworkAccess = true
                    }
                }
            }
        }
    }
}

private struct MainTabView: View {
    @State private var selectedTab: AppTab = .quota

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationView {
                BalanceView {
                    selectedTab = .settings
                }
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Usage", systemImage: "creditcard")
            }
            .tag(AppTab.quota)

            NavigationView {
                SettingsView()
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .accentColor(QuotaColors.accent)
    }
}

private struct InitView: View {
    let onAllow: () -> Void

    @State private var showsNetworkPrompt = false
    @State private var wasDeclined = false

    var body: some View {
        ZStack {
            QuotaColors.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                Text("Q")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color(uiColor: .systemBackground))
                    .frame(width: 58, height: 58)
                    .background(QuotaColors.primaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("init")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundColor(QuotaColors.primaryText)
                    .padding(.top, 24)

                Text("Quota needs network access before it can read API usage.")
                    .font(.body)
                    .foregroundColor(QuotaColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                if wasDeclined {
                    Text("Network access is required to continue.")
                        .font(.footnote.weight(.medium))
                        .foregroundColor(QuotaColors.danger)
                        .padding(.top, 18)
                }

                Button {
                    showsNetworkPrompt = true
                } label: {
                    Text("allow network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 28)

                Spacer()

                Text("Requests to enabled model providers are sent directly from this device.")
                    .font(.caption)
                    .foregroundColor(QuotaColors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .onAppear {
            guard !showsNetworkPrompt else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                showsNetworkPrompt = true
            }
        }
        .alert("允许 Quota 使用网络？", isPresented: $showsNetworkPrompt) {
            Button("不允许", role: .cancel) {
                wasDeclined = true
            }
            Button("允许") {
                onAllow()
            }
        } message: {
            Text("联网后才能查询已启用模型厂商的余额和 API 用量。")
        }
    }
}
