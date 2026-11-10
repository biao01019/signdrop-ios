import SwiftUI
import UniformTypeIdentifiers

// MARK: - ③ 签名配置
struct SignConfigView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = SigningEngine.shared

    // 首页 + 号预导入的 IPA
    var preImported: (name: String, sizeMB: Double)? = nil

    @State var importedIPA: (name: String, sizeMB: Double)? = nil
    @State var autoInstall = true
    @State var keepIcon = false
    @State var showIPAImporter = false
    @State var showError: String? = nil
    @State var signing = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    navBar.padding(.bottom, 24)
                    fileCard.padding(.horizontal, 20).padding(.bottom, 22)
                    Group {
                        SectionHeader(title: "签名证书").padding(.horizontal, 20).padding(.bottom, 10)
                        certCard.padding(.horizontal, 20).padding(.bottom, 22)
                        SectionHeader(title: "应用信息").padding(.horizontal, 20).padding(.bottom, 10)
                        appInfoCard.padding(.horizontal, 20).padding(.bottom, 22)
                        SectionHeader(title: "高级选项").padding(.horizontal, 20).padding(.bottom, 10)
                        optionsCard.padding(.horizontal, 20).padding(.bottom, 14)
                        Text("预计耗时 30 秒 · 签名完成后\(autoInstall ? "自动安装到本机" : "导出到文件")")
                            .font(.system(size: 13)).foregroundColor(.faint)
                            .padding(.bottom, 30)
                        if let e = showError {
                            Text(e).font(.system(size: 13)).foregroundColor(.sdRed)
                                .padding(.bottom, 10)
                        }
                        PrimaryButton(title: signing ? "正在签名…" : "开始签名") { startSign() }
                            .padding(.horizontal, 20)
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .background(Color.bg)
        .onAppear {
            if importedIPA == nil { importedIPA = preImported }
        }
        .fileImporter(isPresented: $showIPAImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    let securityScoped = url.startAccessingSecurityScopedResource()
                    defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }
                    importedIPA = try engine.importIPA(from: url)
                    showError = nil
                } catch {
                    showError = "导入失败：\(error.localizedDescription)"
                }
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
            HStack(spacing: 14) {
                IconSquare("doc.fill", bg: Color.iconSq)
                VStack(alignment: .leading, spacing: 4) {
                    Text(importedIPA?.name ?? "QuantumNotes.ipa")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                    Text(importedIPA.map { "\(String(format: "%.1f", $0.sizeMB)) MB · 今天 18:40 导入" }
                         ?? "24.6 MB · 今天 18:40 导入")
                        .font(.system(size: 13)).foregroundColor(.sub)
                }
                Spacer()
                Button("更换") { showIPAImporter = true }
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.sdBlue)
            }
            .padding(18)
        }
    }

    private var certCard: some View {
        Card {
            HStack(spacing: 14) {
                IconSquare("checkmark.shield.fill")
                VStack(alignment: .leading, spacing: 4) {
                    Text("个人开发者证书")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.ink)
                    Text("剩余 123 天 · 设备 \(app.devices.count)/3")
                        .font(.system(size: 13)).foregroundColor(.sub)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: 0xC4C9D4))
            }
            .padding(18)
        }
    }

    private var appInfoCard: some View {
        Card {
            VStack(spacing: 0) {
                InfoRow(label: "显示名称", value: "Quantum Notes", valueColor: .sub)
                Divider().background(Color.divider)
                InfoRow(label: "Bundle ID", value: "com.quantum.notes", valueColor: .sub)
                Divider().background(Color.divider)
                InfoRow(label: "版本号", value: "2.4.1 (156)", valueColor: .sub)
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
        }
    }

    private var optionsCard: some View {
        Card {
            VStack(spacing: 0) {
                ToggleRow(title: "签名完成后自动安装", isOn: $autoInstall)
                Divider().background(Color.divider).padding(.leading, 18)
                ToggleRow(title: "保留原始应用图标", isOn: $keepIcon)
            }
            .padding(.horizontal, 18).padding(.vertical, 8)
        }
    }

    private func startSign() {
        if importedIPA == nil {
            showError = "请先选择要签名的 .ipa 文件"
            return
        }
        guard engine.hasProfile else {
            showError = "请先在「证书」页导入 .p12 与 .mobileprovision"
            return
        }
        signing = true
        app.tab = 2
        app.currentTask = .init(fileName: importedIPA!.name, sizeMB: importedIPA!.sizeMB,
                                progress: 0, step: .unzip, targetDevice: "iPhone 15 Pro",
                                certName: "个人开发者证书", startTime: Date(), running: true)
        dismiss()
        Task {
            do {
                let engine = SigningEngine.shared
                var pem: URL? = nil
                var profile: URL? = nil

                // 已登录 Apple ID 且填了 UDID → 先自动签发 7 天证书与描述文件
                if AppleIDService.shared.session != nil, !AppleSigningFlow.shared.udid.isEmpty {
                    let info = try engine.appInfo(ofIPA: importedIPA!.name)
                    let provision = try await AppleSigningFlow.shared.provision(
                        bundleId: info.bundleID, appName: info.name) { msg in
                        DispatchQueue.main.async { app.currentTask?.running = true; _ = msg }
                    }
                    pem = provision.pemURL
                    profile = provision.profileURL
                }

                let out = try engine.sign(fileName: importedIPA!.name, keepIcon: keepIcon,
                                          pemOverride: pem, profileOverride: profile,
                                          onProgress: { p in
                                              DispatchQueue.main.async {
                                                  app.currentTask?.progress = p
                                              }
                                          },
                                          onStep: { step, done in
                                              DispatchQueue.main.async {
                                                  if !done { app.currentTask?.step = step }
                                                  else if let next = SignStep(rawValue: step.rawValue + 1) {
                                                      app.currentTask?.step = next
                                                  }
                                              }
                                          })
                DispatchQueue.main.async {
                    app.currentTask?.running = false
                    app.currentTask?.progress = 1.0
                    signing = false
                    _ = out
                }
            } catch {
                DispatchQueue.main.async {
                    app.currentTask?.running = false
                    signing = false
                    showError = error.localizedDescription
                }
            }
        }
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
