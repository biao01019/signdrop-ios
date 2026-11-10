import SwiftUI
import UniformTypeIdentifiers

// MARK: - ④ 证书
struct CertificatesView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var engine = SigningEngine.shared
    @State var showImporter = false
    @State var importMessage: String? = nil
    @State var pendingP12: URL? = nil
    @State var p12Password: String = ""

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("证书").font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        CircleBtn("plus")
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                    certCard(certs[0]).padding(.horizontal, 20).padding(.bottom, 16)
                    certCard(certs[1]).padding(.horizontal, 20).padding(.bottom, 24)

                    SectionHeader(title: "签名设备", trailing: "2 / 3 台")
                        .padding(.horizontal, 20).padding(.bottom, 12)
                    deviceCard.padding(.horizontal, 20).padding(.bottom, 16)

                    Button {
                        showImporter = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            Text("导入 .p12 / .mobileprovision").font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.sdBlue)
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .background(Color.card).cornerRadius(20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    if let m = importMessage {
                        Text(m).font(.system(size: 13)).foregroundColor(.sdBlue)
                            .padding(.horizontal, 20).padding(.bottom, 10)
                    }

                    warnCard.padding(.horizontal, 20)
                    Color.clear.frame(height: 110)
                }
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = url.lastPathComponent.lowercased()
            do {
                if name.hasSuffix(".p12") {
                    pendingP12 = url
                    importMessage = "已选择证书，请在弹窗输入证书密码"
                } else if name.hasSuffix(".mobileprovision") {
                    try engine.importProfile(from: url)
                    importMessage = engine.hasP12 ? "描述文件导入成功 ✓" : "描述文件导入成功，还需导入 .p12 证书"
                } else {
                    importMessage = "仅支持 .p12 或 .mobileprovision 文件"
                }
            } catch {
                importMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .alert("输入证书密码", isPresented: Binding(get: { pendingP12 != nil },
                                          set: { if !$0 { pendingP12 = nil } })) {
            TextField("证书导出密码", text: $p12Password)
            Button("确认") {
                if let u = pendingP12 {
                    do {
                        try engine.importP12(from: u, password: p12Password)
                        importMessage = engine.hasProfile ? "证书与描述文件就绪，可以开始签名 ✓" : "证书导入成功，还需导入 .mobileprovision"
                    } catch {
                        importMessage = "证书导入失败"
                    }
                }
                p12Password = ""
            }
            Button("取消", role: .cancel) { pendingP12 = nil }
        }
    }

    private var certs: [CertInfo] { app.certs }

    private func certCard(_ c: CertInfo) -> some View {
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    IconSquare(c.isEnterprise ? "building.2.fill" : "checkmark.shield.fill",
                               bg: c.isEnterprise ? Color.orangeBg : Color.iconSq,
                               fg: c.isEnterprise ? .sdOrange : .sdBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.name).font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                        Text("Team \(c.team) · \(c.kind)").font(.system(size: 13)).foregroundColor(.sub)
                    }
                    Spacer()
                    Badge(text: c.isDefault ? "默认" : "即将到期",
                          style: c.isDefault ? .blue : .orange)
                }
                .padding(18)
                HStack {
                    Text("\(cnDate(c.expire))到期").font(.system(size: 13)).foregroundColor(.sub)
                    Spacer()
                    Text("剩余 \(c.daysLeft) 天")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(c.isEnterprise ? .sdOrange : .sdBlue)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
                ProgressBar(value: c.progress, color: c.isEnterprise ? .sdOrange : .sdBlue)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
    }

    private var deviceCard: some View {
        Card {
            VStack(spacing: 0) {
                ForEach(Array(app.devices.enumerated()), id: \.element.id) { i, d in
                    HStack(spacing: 14) {
                        IconSquare(d.name.contains("iPad") ? "laptopcomputer" : "iphone",
                                   size: 40, iconSize: 17,
                                   bg: Color.circleBtn, fg: .ink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(d.name).font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                            Text("UDID \(d.udid)")
                                .font(.system(size: 12, design: .monospaced)).foregroundColor(.sub)
                        }
                        Spacer()
                        Badge(text: "已激活", style: .green)
                    }
                    .padding(.horizontal, 18).frame(height: 72)
                    if i < app.devices.count - 1 {
                        Divider().background(Color.divider).padding(.leading, 72)
                    }
                }
            }
        }
    }

    private var warnCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 16)).foregroundColor(.sdOrange)
            Text("企业证书签名的 App 需在「设置 > 通用 > VPN 与设备管理」中信任后才能运行")
                .font(.system(size: 13)).foregroundColor(.sdOrange)
        }
        .padding(16)
        .background(Color.warnBg)
        .cornerRadius(16)
    }
}
