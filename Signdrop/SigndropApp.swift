import SwiftUI

@main
struct SigndropApp: App {
    @StateObject var app = AppState.shared
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                switch app.tab {
                case 0: AppsView()
                case 1: CertificatesView()
                case 2: TasksView()
                case 3: SettingsView()
                default: EmptyView()
                }
            }
            .fullScreenCover(isPresented: $app.showLogin) {
                LoginView()
                    .environmentObject(app)
            }
        }
    }
}
