import SwiftUI

// MARK: - ⑥ 设置
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @State var autoRemind = true
    @State var keepHistory = true
    @State var copied = false

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
                        SectionHeader(title: "签名").padding(.horizontal, 20).padding(.bottom, 10)
                        signCard.padding(.horizontal, 20).padding(.bottom, 24)
                        SectionHeader(title: "设备").padding(.horizontal, 20).padding(.bottom, 10)
                        deviceCard.padding(.horizontal, 20).padding(.bottom, 24)
                        SectionHeader(title: "通用").padding(.horizontal, 20).padding(.bottom, 10)
                        generalCard.padding(.horizontal, 20).padding(.bottom, 18)
                        Text("Signdrop v1.2.0 · 本地签名，数据不出设备")
                            .font(.system(size: 13)).foregroundColor(.faint)
                    }
                    Color.clear.frame(height: 110)
                }
            }
        }
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
