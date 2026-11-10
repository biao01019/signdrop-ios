import SwiftUI
import UniformTypeIdentifiers

// MARK: - ① 我的应用
struct AppsView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var engine = SigningEngine.shared
    @State var showIPAImporter = false
    @State var pendingIPA: (name: String, sizeMB: Double)? = nil
    @State var showSignConfig = false
    @State var detailApp: SignedApp? = nil
    @State var importError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 大标题 + 右侧圆形按钮
                    HStack(alignment: .center) {
                        Text("我的应用")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.ink)
                        Spacer()
                        HStack(spacing: 12) {
                            CircleBtn("magnifyingglass")
                            CircleBtn("ellipsis")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // 证书卡片
                    certCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    SectionHeader(title: "已安装应用", trailing: "\(app.apps.count) 个")
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    // 应用列表
                    Card(corner: 20) {
                        VStack(spacing: 0) {
                            ForEach(Array(app.apps.enumerated()), id: \.element.id) { i, item in
                                AppRow(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { detailApp = item }
                                if i < app.apps.count - 1 {
                                    Divider().background(Color.divider).padding(.leading, 88)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            Spacer(minLength: 0)
        }
        // 应用详情 sheet（挂在 ScrollView 上，避免与下方 sheet 冲突）
        .sheet(item: $detailApp) { item in
            AppDetailView(item: item)
        }
        // 添加应用：右下角 + → 选择 IPA → 进入签名配置
        .overlay(alignment: .bottomTrailing) {
            Button {
                showIPAImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(Color.sdBlue))
                    .shadow(color: Color.sdBlue.opacity(0.4), radius: 12, y: 6)
            }
            .padding(.trailing, 24)
            .padding(.bottom, 108)
            .fileImporter(isPresented: $showIPAImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { picked in
                guard case .success(let urls) = picked, let url = urls.first else { return }
                do {
                    // 真正复制到沙盒 Imports 目录，签名时才能读到
                    pendingIPA = try engine.importIPA(from: url)
                    showSignConfig = true
                } catch {
                    importError = error.localizedDescription
                }
            }
            .alert("导入失败", isPresented: Binding(get: { importError != nil },
                                              set: { if !$0 { importError = nil } })) {
                Button("好", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        // 签名配置 sheet（挂在独立的 Color.clear 锚点上）
        .background(Color.clear.sheet(isPresented: $showSignConfig) {
            SignConfigView(preImported: pendingIPA)
        })
    }

    private var certCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    IconSquare("checkmark.shield.fill")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.certs.first?.name ?? "个人开发者证书")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.ink)
                        Text("Team \(app.certs.first?.team ?? "8F2K9D") · \(app.certs.first.map { "\(cnDate($0.expire))到期" } ?? "2027年3月12日到期")")
                            .font(.system(size: 13))
                            .foregroundColor(.sub)
                    }
                    Spacer()
                    Badge(text: "有效", style: .green)
                }
                ProgressBar(value: app.certs.first?.progress ?? 0.55)
                    .padding(.top, 14)
                HStack {
                    Text("剩余 \(app.certs.first?.daysLeft ?? 123) 天").font(.system(size: 13)).foregroundColor(.sub)
                    Spacer()
                    Button("管理证书") { app.tab = 1 }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.sdBlue)
                }
                .padding(.top, 10)
            }
            .padding(18)
        }
    }
}

// MARK: 应用行
struct AppRow: View {
    let item: SignedApp
    var body: some View {
        HStack(spacing: 14) {
            AppIcon(gradient: Gradient(colors: [Color(hex: item.gradient.0), Color(hex: item.gradient.1)]),
                    glyph: item.glyph)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.ink)
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.sub)
                    switch item.badge {
                    case .soon: Badge(text: "即将到期", style: .orange)
                    case .resign: Badge(text: "需要重签", style: .red)
                    case .none: EmptyView()
                    }
                }
            }
            Spacer()
            if item.badge == .none {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xC4C9D4))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 82)
    }
    private var subtitle: String {
        if let d = item.daysLeft, d > 0 {
            return "v\(item.version) · 剩余 \(d) 天"
        }
        return "v\(item.version) · 已过期 \(item.expiredDays) 天"
    }
}

// MARK: 圆形小按钮
struct CircleBtn: View {
    let icon: String

    init(_ icon: String) { self.icon = icon }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.ink)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.circleBtn))
    }
}
