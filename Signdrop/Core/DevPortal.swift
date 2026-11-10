import Foundation

/// 苹果开发者门户接口（个人/免费团队通用，QH65B2 版本）
final class DevPortal {

    static let shared = DevPortal()

    private let base = "https://developerservices2.apple.com/services/QH65B2/"

    private var clientId: String {
        if let v = UserDefaults.standard.string(forKey: "sd_client_id"), !v.isEmpty { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: "sd_client_id")
        return v
    }

    // MARK: - 通用请求
    private func post(_ action: String, _ params: [String: Any], session: AppleSession) async throws -> [String: Any] {
        guard let url = URL(string: base + action) else { throw SignError.apple("接口地址异常") }
        var items: [(String, String)] = []
        for (k, v) in params {
            if let arr = v as? [String] {
                for s in arr { items.append((k + "[]", s)) }
            } else if let arr = v as? [Int] {
                for s in arr { items.append((k + "[]", String(s))) }
            } else {
                items.append((k, "\(v)"))
            }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Xcode 15.0 (15A240d)", forHTTPHeaderField: "User-Agent")
        req.setValue(session.gsToken, forHTTPHeaderField: "X-Apple-GS-Token")
        if !session.identityId.isEmpty {
            req.setValue(session.identityId, forHTTPHeaderField: "X-Apple-I-Identity-Id")
        }
        for (k, v) in session.anisette.dictionary where !v.isEmpty {
            req.setValue(v, forHTTPHeaderField: k)
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let bodyString = items.map { k, v in
            let ek = k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        req.httpBody = bodyString.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SignError.apple("网络异常") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SignError.apple("开发者接口返回异常（HTTP \(http.statusCode)）")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SignError.apple("登录状态已失效，请重新用 Apple ID 登录")
        }
        let code = json["resultCode"] as? Int ?? 0
        if code != 0 {
            let msg = (json["userString"] as? String)
                ?? (json["resultString"] as? String)
                ?? "错误码 \(code)"
            throw SignError.apple(msg)
        }
        return json
    }

    private func baseParams(_ teamId: String?) -> [String: Any] {
        var p: [String: Any] = ["clientId": clientId, "protocolVersion": "QH65B2"]
        if let t = teamId { p["teamId"] = t }
        return p
    }

    // MARK: - 团队
    func listTeams(session: AppleSession) async throws -> [(id: String, name: String, type: String)] {
        let json = try await post("listTeams.action", baseParams(nil), session: session)
        let teams = (json["teams"] as? [[String: Any]]) ?? []
        return teams.compactMap { t in
            guard let id = t["teamId"] as? String else { return nil }
            return (id, (t["name"] as? String) ?? "Personal Team", (t["type"] as? String) ?? "")
        }
    }

    // MARK: - 设备
    func listDevices(teamId: String, session: AppleSession) async throws -> [[String: Any]] {
        var p = baseParams(teamId)
        p["includeRemovedDevices"] = "true"
        let json = try await post("ios/listDevices.action", p, session: session)
        return (json["devices"] as? [[String: Any]]) ?? []
    }

    @discardableResult
    func registerDevice(teamId: String, name: String, udid: String, session: AppleSession) async throws -> String {
        // 已注册则直接复用
        if let existing = try? await listDevices(teamId: teamId, session: session),
           let hit = existing.first(where: { ($0["deviceNumber"] as? String) == udid }),
           let id = hit["deviceId"] as? String {
            return id
        }
        var p = baseParams(teamId)
        p["name"] = name
        p["deviceNumber"] = udid
        let json = try await post("ios/addDevice.action", p, session: session)
        if let d = json["device"] as? [String: Any], let id = d["deviceId"] as? String {
            return id
        }
        throw SignError.apple("注册设备失败")
    }

    // MARK: - 证书
    func submitCSR(teamId: String, csrDER: Data, machineName: String, session: AppleSession) async throws -> (id: String, der: Data) {
        var p = baseParams(teamId)
        p["csrContent"] = csrDER.base64EncodedString()
        p["machineName"] = machineName
        p["machineId"] = clientId
        let json = try await post("ios/submitDevelopmentCSR.action", p, session: session)
        guard let cert = json["cert"] as? [String: Any] ?? json["certificate"] as? [String: Any],
              let id = cert["certificateId"] as? String else {
            throw SignError.apple("签发证书失败")
        }
        let content = (cert["certificateContent"] as? String) ?? ""
        guard let der = Data(base64Encoded: content) else {
            throw SignError.apple("证书内容解析失败")
        }
        return (id, der)
    }

    func listCertificates(teamId: String, session: AppleSession) async throws -> [[String: Any]] {
        var p = baseParams(teamId)
        p["types"] = "Development"
        let json = try await post("ios/listAllDevelopmentCerts.action", p, session: session)
        return (json["certificates"] as? [[String: Any]]) ?? []
    }

    // MARK: - App ID
    func addAppID(teamId: String, identifier: String, name: String, session: AppleSession) async throws -> String {
        var p = baseParams(teamId)
        p["identifier"] = identifier
        p["name"] = name
        p["features"] = ""
        do {
            let json = try await post("ios/addAppId.action", p, session: session)
            if let appId = json["appId"] as? [String: Any], let id = appId["appIdId"] as? String {
                return id
            }
            throw SignError.apple("创建 App ID 失败")
        } catch {
            // 已存在则查找现有 App ID
            if let existing = try? await listAppIDs(teamId: teamId, session: session),
               let hit = existing.first(where: { ($0["identifier"] as? String) == identifier }),
               let id = hit["appIdId"] as? String {
                return id
            }
            throw error
        }
    }

    func listAppIDs(teamId: String, session: AppleSession) async throws -> [[String: Any]] {
        var p = baseParams(teamId)
        p["onlyFreeApps"] = "false"
        let json = try await post("ios/listAppIds.action", p, session: session)
        return (json["appIds"] as? [[String: Any]]) ?? []
    }

    // MARK: - 描述文件
    func addProvision(teamId: String, appIdId: String, deviceIds: [String],
                      certIds: [String], session: AppleSession) async throws {
        var p = baseParams(teamId)
        p["appIdId"] = appIdId
        p["deviceIds"] = deviceIds
        p["certIds"] = certIds
        p["distributionType"] = "limited"
        p["subType"] = "development"
        _ = try await post("ios/addProvision.action", p, session: session)
    }

    func downloadProfile(teamId: String, appIdId: String, session: AppleSession) async throws -> Data {
        var p = baseParams(teamId)
        p["appIdId"] = appIdId
        p["subType"] = "development"
        let json = try await post("ios/downloadTeamProvisioningProfile.action", p, session: session)
        guard let b64 = json["provisioningProfile"] as? String,
              let data = Data(base64Encoded: b64) else {
            throw SignError.apple("下载描述文件失败")
        }
        return data
    }
}
