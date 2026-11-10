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
    @State var issuing = false
    @State var issueLog: String?
    @State var detailCert: CertInfo? = nil

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text("证书").font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        // 右上角 + = 导入证书
                        Button {
                            showImporter = true
                        } label: {
                            CircleBtn("plus")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)

                    certCard(certs[0])
                        .padding(.horizontal, 20).padding(.bottom, 16)
                        .contentShape(Rectangle())
                        .onTapGesture { detailCert = certs[0] }
                    certCard(certs[1])
                        .padding(.horizontal, 20).padding(.bottom, 24)
                        .contentShape(Rectangle())
                        .onTapGesture { detailCert = certs[1] }

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

                    Button {
                        issueWithAppleID()
                    } label: {
                        HStack(spacing: 10) {
                            if issuing {
                                ProgressView().tint(.white).scaleEffect(0.9)
                            } else {
                                Image(systemName: "person.badge.key.fill")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            Text(issuing ? "正在申请 7 天证书…" : "用 Apple ID 签发 7 天证书")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .background(Color.sdBlue).cornerRadius(20)
                    }
                    .disabled(issuing)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                    if let log = issueLog {
                        Text(log)
                            .font(.system(size: 12))
                            .foregroundColor(log.contains("完成") || log.contains("就绪") ? .sdGreen : .sub)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let m = importMessage {
                        Text(m).font(.system(size: 13)).foregroundColor(.sdBlue)
                            .padding(.horizontal, 20).padding(.bottom, 10)
                    }

                    warnCard.padding(.horizontal, 20)
                    Color.clear.frame(height: 110)
                }
            }
        }
        // 证书详情页
        .sheet(item: $detailCert) { c in
            CertificateDetailView(cert: c)
                .environmentObject(app)
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

    private func issueWithAppleID() {
        guard AppleIDService.shared.session != nil else {
            issueLog = "请先在登录页使用 Apple ID 登录（设置里可填 anisette 服务器）"
            return
        }
        guard !AppleSigningFlow.shared.udid.isEmpty else {
            issueLog = "请先在「设置 → 本机 UDID」填写设备 UDID"
            return
        }
        issuing = true
        issueLog = "开始申请证书…"

        // 优先用第一个应用的 Bundle ID，没有则用通用 Demo ID
        let bundle = app.apps.first?.bundleID ?? "com.signdrop.demoapp"
        let name = app.apps.first?.name ?? "Signdrop App"

        Task {
            do {
                let r = try await AppleSigningFlow.shared.provision(bundleId: bundle, appName: name) { msg in
                    DispatchQueue.main.async { issueLog = msg }
                }
                // 同步证书卡片信息
                DispatchQueue.main.async {
                    issuing = false
                    if let exp = r.expireDate {
                        app.certs[0].expire = exp
                        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
                        app.certs[0].daysLeft = max(0, days)
                        app.certs[0].progress = max(0.05, min(1, Double(days) / 7.0))
                    }
                    issueLog = "证书已就绪（Team \(r.teamId)），可直接签名"
                }
            } catch {
                DispatchQueue.main.async {
                    issuing = false
                    issueLog = error.localizedDescription
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
