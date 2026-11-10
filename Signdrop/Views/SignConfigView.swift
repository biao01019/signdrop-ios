import SwiftUI
import UniformTypeIdentifiers

// MARK: - ③ 签名配置
struct SignConfigView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = SigningEngine.shared

    var preImported: (name: String, sizeMB: Double)? = nil

    @State var importedIPA: (name: String, sizeMB: Double)? = nil
    @State var keepIcon = true
    @State var showIPAImporter = false
    @State var showError: String? = nil
    @State var signing = false
    @State var progressText = ""
    @State var result: SigningEngine.SignOutput? = nil
    @State var showResult = false
    @State var identityLabel: String = "检测中…"

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    navBar.padding(.bottom, 24)
                    fileCard.padding(.horizontal, 20).padding(.bottom, 22)
                    Group {
                        SectionHeader(title: "签名身份").padding(.horizontal, 20).padding(.bottom, 10)
                        certCard.padding(.horizontal, 20).padding(.bottom, 22)
                        SectionHeader(title: "高级选项").padding(.horizontal, 20).padding(.bottom, 10)
                        optionsCard.padding(.horizontal, 20).padding(.bottom, 14)

                        if let e = showError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13)).foregroundColor(.sdRed)
                                Text(e).font(.system(size: 13)).foregroundColor(.sdRed)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.redBg).cornerRadius(14)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                        }

                        if signing {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.9)
                                Text(progressText).font(.system(size: 13)).foregroundColor(.sub)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 22).padding(.bottom, 12)
                        }

                        PrimaryButton(title: signing ? "正在签名…" : "开始签名") { startSign() }
                            .padding(.horizontal, 20)
                            .disabled(signing || importedIPA == nil)
                            .opacity(importedIPA == nil ? 0.5 : 1)

                        Text("签名在设备本地完成，不上传任何文件")
                            .font(.system(size: 12)).foregroundColor(.faint)
                            .padding(.top, 12)
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .background(Color.bg)
        .onAppear {
            if importedIPA == nil { importedIPA = preImported }
            refreshIdentity()
        }
        .fileImporter(isPresented: $showIPAImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { picked in
            guard case .success(let urls) = picked, let url = urls.first else { return }
            do {
                importedIPA = try engine.importIPA(from: url)
                showError = nil
            } catch {
                showError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showResult) {
            if let r = result {
                SignResultView(output: r) { dismiss() }
            }
        }
    }

    private var navBar: some View {
        HStack {
            Button("取消") { dismiss() }
                .font(.system(size: 16)).foregroundColor(.sdBlue)
            Spacer()
            Text("签名配置").font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
            Spacer()
            Color.clear.frame(width: 44, height: 20)
        }
        .padding(.horizontal, 20)
    }

    private var fileCard: some View {
        Card {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    IconSquare("doc.fill", bg: Color.iconSq)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(importedIPA?.name ?? "未选择 IPA")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(importedIPA == nil ? .sub : .ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(importedIPA.map { String(format: "%.1f MB · 已导入", $0.sizeMB) } ?? "点右侧按钮选择 .ipa")
                            .font(.system(size: 13)).foregroundColor(.sub)
                    }
                    Spacer()
                    Button(importedIPA == nil ? "选择" : "更换") { showIPAImporter = true }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.sdBlue)
                }
                .padding(18)

                let list = engine.importedIPAs()
                if !list.isEmpty {
                    Divider().background(Color.divider).padding(.leading, 18)
                    VStack(spacing: 0) {
                        ForEach(Array(list.prefix(4).enumerated()), id: \.offset) { i, item in
                            Button {
                                importedIPA = item
                            } label: {
                                HStack {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.system(size: 13)).foregroundColor(.faint)
                                    Text(item.name)
                                        .font(.system(size: 13))
                                        .foregroundColor(.ink)
                                        .lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(String(format: "%.1f MB", item.sizeMB))
                                        .font(.system(size: 12)).foregroundColor(.faint)
                                    if importedIPA?.name == item.name {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14)).foregroundColor(.sdBlue)
                                    }
                                }
                                .padding(.horizontal, 18).frame(height: 44)
                            }
                            if i < min(list.count, 4) - 1 {
                                Divider().background(Color.divider).padding(.leading, 44)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var certCard: some View {
        Card {
            HStack(spacing: 14) {
                IconSquare("checkmark.shield.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text(identityLabel)
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                    Text(engine.hasProfile ? "描述文件已导入" : "无描述文件")
                        .font(.system(size: 13)).foregroundColor(.sub)
                }
                Spacer()
                Badge(text: engine.hasProfile || AppleIDService.shared.session != nil ? "就绪" : "ad-hoc",
                      style: engine.hasProfile || AppleIDService.shared.session != nil ? .green : .orange)
            }
            .padding(18)
        }
    }

    private var optionsCard: some View {
        Card {
            VStack(spacing: 0) {
                ToggleRow(title: "保留原始应用图标", isOn: $keepIcon)
                Divider().background(Color.divider).padding(.leading, 18)
                HStack {
                    Text("签名完成后")
                        .font(.system(size: 16)).foregroundColor(.ink)
                    Spacer()
                    Text("导出到「文件」")
                        .font(.system(size: 15)).foregroundColor(.sub)
                }
                .frame(height: 58)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
    }

    // MARK: 身份探测
    private func refreshIdentity() {
        if engine.hasP12, let id = try? engine.loadIdentity() {
            identityLabel = id.label
        } else if AppleIDService.shared.session != nil {
            identityLabel = "Apple ID 直签（\(app.account)）"
        } else if engine.hasProfile {
            identityLabel = "导入的描述文件"
        } else {
            identityLabel = "ad-hoc 签名"
        }
    }

    // MARK: 开始签名
    private func startSign() {
        guard let file = importedIPA else {
            showError = "请先选择要签名的 .ipa 文件"
            return
        }
        signing = true
        showError = nil
        progressText = "准备中…"

        Task {
            do {
                var identity: SigningEngine.Identity? = nil
                var profile: URL? = engine.hasProfile ? engine.profileURL : nil

                // 优先 Apple ID 直签（需已登录 + 填了 UDID）
                if AppleIDService.shared.session != nil, !AppleSigningFlow.shared.udid.isEmpty {
                    await MainActor.run { progressText = "申请 7 天证书…" }
                    let info = try engine.appInfo(ofIPA: file.name)
                    let p = try await AppleSigningFlow.shared.provision(bundleId: info.bundleID,
                                                                       appName: info.name) { msg in
                        DispatchQueue.main.async { progressText = msg }
                    }
                    identity = try p.identity()
                    profile = p.profileURL
                } else if engine.hasP12 {
                    identity = try engine.loadIdentity()
                }

                let output = try engine.sign(fileName: file.name,
                                             keepIcon: keepIcon,
                                             identity: identity,
                                             profileOverride: profile,
                                             onProgress: { p in
                                                 DispatchQueue.main.async {
                                                     app.currentTask?.progress = p
                                                 }
                                             },
                                             onStep: { step, done in
                                                 DispatchQueue.main.async {
                                                     progressText = done ? "\(step.title)完成" : step.title + "…"
                                                     if !done {
                                                         app.currentTask?.step = step
                                                     } else if let next = SignStep(rawValue: step.rawValue + 1) {
                                                         app.currentTask?.step = next
                                                     }
                                                 }
                                             },
                                             onLog: { msg in
                                                 DispatchQueue.main.async { progressText = msg }
                                             })

                await MainActor.run {
                    signing = false
                    app.currentTask = nil
                    // 记入应用列表
                    if !app.apps.contains(where: { $0.bundleID == output.bundleID }) {
                        app.apps.insert(.init(name: output.appName, version: "—", build: "—",
                                              sizeMB: 0, category: "已签名",
                                              bundleID: output.bundleID,
                                              gradient: (0x6A5AF9, 0x2C7BF6), glyph: "app.badge.checkmark",
                                              daysLeft: output.isAdHoc ? nil : 7, badge: .none,
                                              signedAt: Date(),
                                              expireAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()),
                                              fileName: output.ipaURL.lastPathComponent), at: 0)
                    }
                    result = output
                    showResult = true
                }
            } catch {
                await MainActor.run {
                    signing = false
                    app.currentTask = nil
                    showError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - 签名结果
struct SignResultView: View {
    let output: SigningEngine.SignOutput
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xE4E6EC)).frame(width: 36, height: 5).padding(.top, 8)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle().fill(Color.greenBg).frame(width: 76, height: 76)
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold)).foregroundColor(.sdGreen)
                    }
                    .padding(.top, 24)

                    Text("签名完成")
                        .font(.system(size: 22, weight: .bold)).foregroundColor(.ink)
                        .padding(.top, 14)
                    Text(output.appName)
                        .font(.system(size: 14)).foregroundColor(.sub)
                        .padding(.top, 4)

                    Card {
                        VStack(spacing: 0) {
                            InfoRow(label: "Bundle ID", value: output.bundleID, valueColor: .sub)
                            Divider().background(Color.divider)
                            InfoRow(label: "签名方式", value: output.isAdHoc ? "ad-hoc（无证书）" : "证书签名",
                                    valueColor: output.isAdHoc ? .sdOrange : .sdGreen)
                            Divider().background(Color.divider)
                            InfoRow(label: "文件大小",
                                    value: String(format: "%.1f MB", fileSizeMB),
                                    valueColor: .sub)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .padding(.horizontal, 20).padding(.top, 20)

                    if !output.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(output.warnings.prefix(3)), id: \.self) { w in
                                Text("· \(w)").font(.system(size: 11)).foregroundColor(.faint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24).padding(.top, 12)
                    }

                    VStack(spacing: 12) {
                        ShareLink(item: output.ipaURL) {
                            Text("分享 / 保存到文件")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.sdBlue).cornerRadius(18)
                        }
                        Button("完成") { onDone() }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.sub)
                            .frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .padding(.horizontal, 20).padding(.top, 22)

                    Text("文件位置：文件 App → 我的 iPhone → Signdrop → Signed")
                        .font(.system(size: 12)).foregroundColor(.faint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30).padding(.top, 10)
                    Color.clear.frame(height: 30)
                }
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private var fileSizeMB: Double {
        let attrs = try? FileManager.default.attributesOfItem(atPath: output.ipaURL.path)
        return ((attrs?[.size] as? NSNumber)?.doubleValue ?? 0) / 1024 / 1024
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title).font(.system(size: 16)).foregroundColor(.ink)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(.sdGreen).frame(width: 51, height: 31)
        }
        .frame(height: 58)
    }
}
