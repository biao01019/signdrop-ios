import SwiftUI

// MARK: - 证书详情
struct CertificateDetailView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    let cert: CertInfo
    @State var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // 导航
                    HStack {
                        Button { dismiss() } label: { CircleBtn("chevron.left") }
                        Spacer()
                        Text("证书详情").font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    // 证书头部
                    HStack(alignment: .center, spacing: 16) {
                        IconSquare(cert.isEnterprise ? "building.2.fill" : "checkmark.shield.fill",
                                   size: 72, iconSize: 32,
                                   bg: cert.isEnterprise ? Color.orangeBg : Color.iconSq,
                                   fg: cert.isEnterprise ? .sdOrange : .sdBlue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(cert.name).font(.system(size: 22, weight: .bold)).foregroundColor(.ink)
                            Text("\(cert.kind) · Team \(cert.team)")
                                .font(.system(size: 13)).foregroundColor(.sub)
                            HStack(spacing: 8) {
                                Badge(text: cert.isEnterprise ? "企业分发" : "个人开发",
                                      style: cert.isEnterprise ? .orange : .blue)
                                Badge(text: cert.isDefault ? "默认证书" : "备用",
                                      style: cert.isDefault ? .green : .blue)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // 有效期卡片
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("剩余 \(cert.daysLeft) 天")
                                .font(.system(size: 20, weight: .bold)).foregroundColor(.ink)
                            Spacer()
                            Text("\(cnDate(cert.expire))到期")
                                .font(.system(size: 13)).foregroundColor(.sub)
                        }
                        ProgressBar(value: cert.progress,
                                    color: cert.isEnterprise ? .sdOrange : .sdBlue)
                        Text(cert.isEnterprise
                             ? "企业证书无固定有效期上限，按协议年审续期"
                             : (cert.daysLeft <= 7
                                ? "即将到期：重新点「用 Apple ID 签发 7 天证书」即可续签"
                                : "将于到期前 7 天自动提醒续签"))
                            .font(.system(size: 12)).foregroundColor(.faint)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card)
                    .cornerRadius(20)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    // 详细信息
                    Card {
                        VStack(spacing: 0) {
                            InfoRow(label: "证书名称", value: cert.name)
                            Divider().background(Color.divider)
                            InfoRow(label: "证书类型", value: cert.kind)
                            Divider().background(Color.divider)
                            InfoRow(label: "Team ID", value: cert.team)
                            Divider().background(Color.divider)
                            InfoRow(label: "签发日期", value: cnDate(issuedDate))
                            Divider().background(Color.divider)
                            InfoRow(label: "到期日期", value: cnDate(cert.expire))
                            Divider().background(Color.divider)
                            InfoRow(label: "签名设备", value: "\(app.devices.count) / 3 台", valueColor: .sub)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // 操作
                    VStack(spacing: 12) {
                        Button {
                            for i in app.certs.indices { app.certs[i].isDefault = (app.certs[i].id == cert.id) }
                            dismiss()
                        } label: {
                            Text(cert.isDefault ? "已是默认证书" : "设为默认证书")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(cert.isDefault ? Color.sub : Color.sdBlue)
                                .cornerRadius(16)
                        }
                        .disabled(cert.isDefault)

                        Button {
                            confirmDelete = true
                        } label: {
                            Text("删除证书")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.sdRed)
                                .frame(maxWidth: .infinity).frame(height: 56)
                                .background(Color.card).cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    Color.clear.frame(height: 40)
                }
            }
        }
        .background(Color.bg)
        .alert("删除证书？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) {
                if let idx = app.certs.firstIndex(where: { $0.id == cert.id }) {
                    app.certs.remove(at: idx)
                }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后使用该证书签名的应用需重新签名才能启动")
        }
    }

    // 以剩余天数反推签发日（个人证书 7 天 / 企业按年）
    private var issuedDate: Date {
        let span = cert.isEnterprise ? 365 : max(cert.daysLeft, 1)
        return Calendar.current.date(byAdding: .day, value: -span, to: cert.expire) ?? cert.expire
    }
}
