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
            // 液态玻璃 TabBar：全局唯一，四个页面共用
            .overlay(alignment: .bottom) {
                VStack(spacing: 10) {
                    FloatingTabBar(selection: $app.tab, items: [
                        ("square.grid.2x2.fill", "应用"),
                        ("checkmark.shield", "证书"),
                        ("clock", "任务"),
                        ("slider.horizontal.3", "设置"),
                    ])
                    HomeIndicator()
                }
            }
        }
        .fullScreenCover(isPresented: $app.showLogin) {
            LoginView()
                .environmentObject(app)
        }
        .onAppear {
            AppleIDService.shared.restoreIfPossible()
        }
    }
}
