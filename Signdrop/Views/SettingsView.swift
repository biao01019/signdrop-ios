import SwiftUI

// MARK: - ⑥ 设置
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State var autoRemind = true
    @State var keepHistory = true
    @State var copied = false
    @State var anisetteServer = UserDefaults.standard.string(forKey: "sd_anisette_server") ?? AnisetteClient.defaultServer
    @State var udid = UserDefaults.standard.string(forKey: "sd_udid") ?? ""
    @State var appleLoggedIn = AppleIDService.shared.isLoggedIn

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("设置").font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                    accountCard.padding(.horizontal, 20).padding(.bottom, 24)

                    Group {
                        SectionHeader(title: "Apple ID 直签").padding(.horizontal, 20).padding(.bottom, 10)
                        appleCard.padding(.horizontal, 20).padding(.bottom, 24)
                        SectionHeader(title: "签名").padding(.horizontal, 20).padding(.bottom, 10)
                        signCard.padding(.horizontal, 20).padding(.bottom, 24)
                        SectionHeader(title: "设备").padding(.horizontal, 20).padding(.bottom, 10)
                        deviceCard.padding(.horizontal, 20).padding(.bottom, 24)
                        SectionHeader(title: "通用").padding(.horizontal, 20).padding(.bottom, 10)
                        generalCard.padding(.horizontal, 20).padding(.bottom, 18)
                        Text("Signdrop v1.4.0 · 本地签名，数据不出设备")
                            .font(.system(size: 13)).foregroundColor(.faint)
                            .padding(.bottom, 14)
                        logoutButton
                    }
                    Color.clear.frame(height: 130)
                }
            }
        }
    }

    // 退出登录
    private var logoutButton: some View {
        Button {
            AppleIDService.shared.signOut()
            UserDefaults.standard.set(false, forKey: "sd_logged_in")
            UserDefaults.standard.set(false, forKey: "sd_skipped_login")
            app.isLoggedIn = false
            app.account = ""
            app.showLogin = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .semibold))
                Text("退出登录")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.sdRed)
            .frame(maxWidth: .infinity).frame(height: 60)
            .background(Color.card).cornerRadius(20)
        }
        .padding(.horizontal, 20)
    }

    private var accountCard: some View {
        Card {
            HStack(spacing: 14) {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x8A6CF6), Color(hex: 0x6C5CE7)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: "person.fill")
                        .font(.system(size: 19)).foregroundColor(.white))
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.account.isEmpty ? "quantum@icloud.com" : app.account)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                    Text("证书同步已开启 · 5 个应用")
                        .font(.system(size: 13)).foregroundColor(.sub)
                }
                Spacer()
                Badge(text: "已登录", style: .green)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xC4C9D4))
            }
            .padding(18)
        }
    }

    private var appleCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    Text("登录状态").font(.system(size: 16)).foregroundColor(.ink)
                    Spacer()
                    Badge(text: appleLoggedIn ? "已登录" : "未登录",
                          style: appleLoggedIn ? .green : .orange)
                    if appleLoggedIn {
                        Button("退出") {
                            AppleIDService.shared.signOut()
                            appleLoggedIn = false
                            UserDefaults.standard.set(false, forKey: "sd_logged_in")
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.sdRed)
                        .padding(.leading, 8)
                    }
                }
                .frame(height: 54)
                Divider().background(Color.divider)

                VStack(alignment: .leading, spacing: 6) {
                    Text("anisette 服务器").font(.system(size: 13)).foregroundColor(.sub)
                    TextField("https://ani.sidestore.io", text: $anisetteServer)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: anisetteServer) { v in
                            UserDefaults.standard.set(v, forKey: "sd_anisette_server")
                        }
                }
                .padding(.vertical, 10)
                Divider().background(Color.divider)

                VStack(alignment: .leading, spacing: 6) {
                    Text("本机 UDID（Apple ID 直签必填）").font(.system(size: 13)).foregroundColor(.sub)
                    TextField("00008101-000A2F8C8F3A", text: $udid)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: udid) { v in
                            UserDefaults.standard.set(v.trimmingCharacters(in: .whitespaces), forKey: "sd_udid")
                        }
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, 18).padding(.vertical, 4)
        }
    }

    private var signCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    Text("默认证书").font(.system(size: 16)).foregroundColor(.ink)
                    Spacer()
                    Text("个人开发者证书").font(.system(size: 15)).foregroundColor(.sub)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0xC4C9D4))
                }.frame(height: 54)
                Divider().background(Color.divider)
                ToggleRow(title: "到期前自动提醒", isOn: $autoRemind)
                Divider().background(Color.divider)
                ToggleRow(title: "保留签名记录", isOn: $keepHistory)
            }
            .padding(.horizontal, 18).padding(.vertical, 4)
        }
    }

    private var deviceCard: some View {
        Card {
            VStack(spacing: 0) {
                InfoRow(label: "设备名称", value: "iPhone 15 Pro · iOS 18.2", valueColor: .sub)
                Divider().background(Color.divider)
                HStack {
                    Text("UDID").font(.system(size: 15)).foregroundColor(.sub)
                    Spacer()
                    Text("00008101-000A2F8C8F3A")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.ink)
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                        Text(copied ? "已复制" : "复制").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.sdBlue)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.iconSq).cornerRadius(8)
                    .onTapGesture {
                        UIPasteboard.general.string = "00008101-000A2F8C8F3A"
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                }
                .frame(height: 50)
                Text("添加新设备后需重新签名，才能安装到该设备")
                    .font(.system(size: 12)).foregroundColor(.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
    }

    private var generalCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack {
                    Text("外观").font(.system(size: 16)).foregroundColor(.ink)
                    Spacer()
                    Text("跟随系统").font(.system(size: 15)).foregroundColor(.sub)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0xC4C9D4))
                }.frame(height: 54)
                Divider().background(Color.divider)
                HStack {
                    Text("清理缓存").font(.system(size: 16)).foregroundColor(.ink)
                    Spacer()
                    Text("1.2 GB").font(.system(size: 15)).foregroundColor(.sub)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: 0xC4C9D4))
                }.frame(height: 54)
            }
            .padding(.horizontal, 18)
        }
    }
}
