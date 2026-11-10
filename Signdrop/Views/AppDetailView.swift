import SwiftUI

// MARK: - ② 应用详情
struct AppDetailView: View {
    @EnvironmentObject var app: AppState
    let item: SignedApp
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 导航
                    HStack {
                        CircleBtn("chevron.left").onTapGesture { dismiss() }
                        Spacer()
                        Text("应用详情").font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // 头部
                    HStack(alignment: .top, spacing: 16) {
                        AppIcon(size: 80, corner: 22,
                                gradient: Gradient(colors: [Color(hex: item.gradient.0), Color(hex: item.gradient.1)]),
                                glyph: item.glyph)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.system(size: 24, weight: .bold)).foregroundColor(.ink)
                            Text("v\(item.version) · \(String(format: "%.1f", item.sizeMB)) MB · \(item.category)")
                                .font(.system(size: 13)).foregroundColor(.sub)
                            HStack(spacing: 8) {
                                Badge(text: "已签名", style: .green)
                                Badge(text: "个人证书", style: .blue)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // 签名信息
                    infoCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                    // 剩余天数
                    remainCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    // 操作按钮
                    HStack(spacing: 12) {
                        Button {
                            app.tab = 2
                            app.currentTask = .init(fileName: item.fileName, sizeMB: item.sizeMB,
                                                    progress: 0.3, step: .resign,
                                                    targetDevice: "iPhone 15 Pro",
                                                    certName: item.certName,
                                                    startTime: Date(), running: true)
                            dismiss()
                        } label: {
                            Text("重新签名")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.sdBlue).cornerRadius(16)
                        }
                        Button {
                        } label: {
                            Text("卸载")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.sdRed)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.card).cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    SectionHeader(title: "签名记录", trailing: "3 次")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    historyCard.padding(.horizontal, 20)
                    Color.clear.frame(height: 60)
                }
            }
        }
        .background(Color.bg)
    }

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("签名信息").font(.system(size: 13)).foregroundColor(.sub).padding(.bottom, 12)
                InfoRow(label: "签名证书", value: item.certName)
                InfoRow(label: "Bundle ID", value: item.bundleID)
                InfoRow(label: "签名时间", value: item.signedAt.map(cnDate) ?? "—")
            }
            .padding(18)
        }
    }

    private var remainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("剩余 87 天").font(.system(size: 20, weight: .bold)).foregroundColor(.ink)
                    Spacer()
                    Text("2026年12月5日到期").font(.system(size: 13)).foregroundColor(.sub)
                }
                ProgressBar(value: 0.87, color: .sdGreen)
                Text("将于到期前 7 天自动提醒重新签名")
                    .font(.system(size: 12)).foregroundColor(.faint)
            }
            .padding(18)
        }
    }

    private var historyCard: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(item.history.enumerated()), id: \.element.id) { i, r in
                    HStack(alignment: .center, spacing: 12) {
                        Circle().fill(r.ok ? Color.sdGreen : Color.sdRed).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.ink)
                            Text(r.detail).font(.system(size: 13)).foregroundColor(.sub)
                        }
                        Spacer()
                        Text(shortDate(r.date)).font(.system(size: 13)).foregroundColor(.faint)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 62)
                    if i < item.history.count - 1 {
                        Divider().background(Color.divider).padding(.leading, 38)
                    }
                }
            }
        }
    }
}

// MARK: 信息行
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .ink
    var body: some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundColor(.sub)
            Spacer()
            Text(value).font(.system(size: 15, weight: .medium)).foregroundColor(valueColor)
        }
        .frame(height: 44)
    }
}
