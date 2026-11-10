import Foundation

/// 一键流程：Apple ID 已登录 → 注册设备 → 申请证书 → 创建 App ID/描述文件 → 交给签名引擎
final class AppleSigningFlow {

    static let shared = AppleSigningFlow()

    struct ProvisionResult {
        var pemURL: URL
        var profileURL: URL
        var certId: String
        var teamId: String
        var expireDate: Date?
    }

    /// 设备 UDID（系统不开放给 App，需用户在设置里手动填一次）
    var udid: String {
        get { UserDefaults.standard.string(forKey: "sd_udid") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "sd_udid") }
    }

    func provision(bundleId: String,
                   appName: String,
                   log: @escaping (String) -> Void) async throws -> ProvisionResult {

        guard let session = AppleIDService.shared.session else {
            throw SignError.apple("请先用 Apple ID 登录")
        }
        guard !udid.isEmpty, udid.count >= 20 else {
            throw SignError.apple("请先在「设置 → 设备」中填写本机 UDID（20 位以上）")
        }

        let portal = DevPortal.shared

        // 1. 团队
        log("读取开发者团队…")
        let teams = try await portal.listTeams(session: session)
        guard let team = teams.first(where: { $0.type.lowercased() != "company" }) ?? teams.first else {
            throw SignError.apple("该 Apple ID 没有可用团队，请先在 Apple Developer 同意协议")
        }
        log("团队：\(team.name)（\(team.id)）")

        // 2. 注册设备
        log("注册设备 UDID…")
        let deviceId = try await portal.registerDevice(teamId: team.id,
                                                       name: "Signdrop Device",
                                                       udid: udid, session: session)
        log("设备已注册（\(deviceId)）")

        // 3. 申请证书
        log("生成密钥并提交 CSR…")
        let keyTag = CSRBuilder.privateKeyTag(commonName: "Signdrop")
        let csr = try CSRBuilder.makeCSR(commonName: "Signdrop", teamId: team.id, keyTag: keyTag)
        let cert = try await portal.submitCSR(teamId: team.id,
                                              csrDER: csr.der,
                                              machineName: "Signdrop",
                                              session: session)
        log("证书签发成功（\(cert.id)）")

        // 4. App ID
        log("创建 App ID：\(bundleId)")
        let appIdId = try await portal.addAppID(teamId: team.id,
                                                identifier: bundleId,
                                                name: appName, session: session)

        // 5. 描述文件
        log("生成描述文件…")
        let devices = try await portal.listDevices(teamId: team.id, session: session)
        let deviceIds = devices.compactMap { $0["deviceId"] as? String }
        try await portal.addProvision(teamId: team.id, appIdId: appIdId,
                                      deviceIds: deviceIds, certIds: [cert.id],
                                      session: session)
        let profileData = try await portal.downloadProfile(teamId: team.id,
                                                           appIdId: appIdId, session: session)
        log("描述文件已下载（\(profileData.count / 1024) KB）")

        // 6. 落盘 PEM（私钥 + 证书）与描述文件
        let pemKey = try CSRBuilder.privateKeyPEM(tag: keyTag)
        let pem = pemKey + "-----BEGIN CERTIFICATE-----\n"
            + ASN1.base64Lines(cert.der) + "\n-----END CERTIFICATE-----\n"
        let work = SigningEngine.workDir
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let pemURL = work.appendingPathComponent("apple-identity.pem")
        try pem.data(using: .utf8)?.write(to: pemURL)

        let profileURL = work.appendingPathComponent("apple-embedded.mobileprovision")
        try profileData.write(to: profileURL)

        // 7. 记录到期时间
        var expire: Date? = nil
        if let xml = profileData.xmlPlistRange(),
           let dict = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] {
            expire = dict["ExpirationDate"] as? Date
        }
        log("完成，可开始签名")

        return ProvisionResult(pemURL: pemURL, profileURL: profileURL,
                               certId: cert.id, teamId: team.id, expireDate: expire)
    }
}
