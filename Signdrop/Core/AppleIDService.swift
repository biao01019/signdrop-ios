import Foundation

struct AppleSession {
    var username: String
    var gsToken: String
    var identityId: String
    var dsid: String
    var teamId: String?
    var teamName: String?
    var anisette: AnisetteHeaders
}

enum LoginResult {
    case success(AppleSession)
    case needs2FA
    case needsSMS(phone: String)
}

/// Apple ID 登录（GSA SRP + 双重认证），拿到开发者门户用的 GS Token
final class AppleIDService {

    static let shared = AppleIDService()

    private let gsaBase = "https://gsa.apple.com"
    private var pending: Pending?

    private struct Pending {
        var srp: SRPClient
        var username: String
        var password: String
        var anisette: AnisetteHeaders
        var sessionId: String
        var scnt: String
    }

    var session: AppleSession?
    var isLoggedIn: Bool { session?.gsToken.isEmpty == false }

    // MARK: - 登录
    func signIn(username: String, password: String) async throws -> LoginResult {
        let anisette = try await AnisetteClient.shared.fetch(force: true)
        let srp = SRPClient(username: username, password: password)
        let cpd = clientProvidedData(anisette)

        // init
        let initBody: [String: Any] = [
            "o": "init",
            "u": username,
            "ps": "s2k",
            "np": "s2k",
            "cpd": cpd,
            "A2k": srp.aBase64,
        ]
        let (initJSON, _) = try await postGSAAuth(path: "/grandslam/GsService2",
                                                  body: initBody, anisette: anisette)
        guard let fs = initJSON["fs"] as? [String: Any],
              let bStr = fs["B"] as? String,
              let sStr = fs["s"] as? String,
              let bData = Data(base64Encoded: bStr),
              let salt = Data(base64Encoded: sStr) else {
            throw SignError.apple("登录初始化失败：\(statusMessage(initJSON))")
        }

        let B = BigUInt(bData)
        let proofs = try srp.computeProofs(B: B, salt: salt)

        // complete
        let completeBody: [String: Any] = [
            "o": "complete",
            "u": username,
            "m1": proofs.m1.base64EncodedString(),
            "c": fs["c"] as? Int ?? 0,
            "cpd": cpd,
            "ps": "s2k",
            "np": "s2k",
        ]
        let (json, headers) = try await postGSAAuth(path: "/grandslam/GsService2",
                                                   body: completeBody, anisette: anisette)
        let ec = (json["Status"] as? [String: Any])?["ec"] as? Int ?? 0

        let sessionId = headers["X-Apple-ID-Session-Id"] ?? ""
        let scnt = headers["scnt"] ?? ""

        if ec == 0 {
            let s = try await finishSession(username: username, anisette: anisette,
                                            sessionId: sessionId, scnt: scnt, body: json)
            return .success(s)
        }

        if ec == -21669 || ec == -22405 {
            pending = Pending(srp: srp, username: username, password: password,
                              anisette: anisette, sessionId: sessionId, scnt: scnt)
            return .needs2FA
        }

        throw SignError.apple(statusMessage(json))
    }

    /// 提交双重认证验证码
    func submit2FACode(_ code: String) async throws -> AppleSession {
        guard let p = pending else { throw SignError.apple("登录状态已过期，请重新登录") }

        var req = URLRequest(url: URL(string: "\(gsaBase)/auth/verify/trusteddevice/securitycode")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applySessionHeaders(&req, anisette: p.anisette, sessionId: p.sessionId, scnt: p.scnt)
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "securityCode": ["code": code],
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? nil
        let http = resp as? HTTPURLResponse
        var ec = json?["ec"] as? Int
        if ec == nil, let st = json?["Status"] as? [String: Any] { ec = st["ec"] as? Int }
        let errCode = ec ?? 0

        guard http?.statusCode == 200, errCode == 0 else {
            let msg = (json?["em"] as? String) ?? statusMessage(json ?? [:]) ?? "验证码校验失败"
            throw SignError.apple(msg)
        }

        // 信任本设备（失败不阻塞）
        await trustDevice(anisette: p.anisette, sessionId: p.sessionId, scnt: p.scnt)

        let s = try await finishSession(username: p.username, anisette: p.anisette,
                                        sessionId: p.sessionId, scnt: p.scnt, body: json ?? [:])
        pending = nil
        return s
    }

    private func trustDevice(anisette: AnisetteHeaders, sessionId: String, scnt: String) async {
        guard var url = URL(string: "\(gsaBase)/auth/2sv/trust") else { return }
        url.append(queryItems: [URLQueryItem(name: "id", value: UUID().uuidString)])
        var req = URLRequest(url: url)
        applySessionHeaders(&req, anisette: anisette, sessionId: sessionId, scnt: scnt)
        _ = try? await URLSession.shared.data(for: req)
    }

    /// 取 GS Token / Identity ID
    private func finishSession(username: String, anisette: AnisetteHeaders,
                               sessionId: String, scnt: String,
                               body: [String: Any]) async throws -> AppleSession {

        var req = URLRequest(url: URL(string: "\(gsaBase)/grandslam/GsService2/validate")!)
        req.httpMethod = "GET"
        applySessionHeaders(&req, anisette: anisette, sessionId: sessionId, scnt: scnt)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { acc, kv in
            if let k = kv.key as? String, let v = kv.value as? String { acc[k] = v }
        } ?? [:]

        var gsToken = headers["X-Apple-GS-Token"] ?? ""
        var identityId = headers["X-Apple-I-Identity-Id"] ?? ""
        var dsid = headers["X-Apple-DS-Person-Id"] ?? ""

        if gsToken.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let fs = json["fs"] as? [String: Any] {
            gsToken = (fs["sp"] as? String) ?? (fs["GsIdmsToken"] as? String) ?? ""
            identityId = (fs["identityId"] as? String) ?? identityId
            dsid = (fs["dsid"] as? String) ?? (fs["DsPrsId"] as? String) ?? dsid
        }

        guard !gsToken.isEmpty else {
            throw SignError.apple("未能获取 GS Token，请稍后重试或检查 anisette 服务器")
        }

        let s = AppleSession(username: username, gsToken: gsToken, identityId: identityId,
                             dsid: dsid, teamId: nil, teamName: nil, anisette: anisette)
        session = s
        saveSession(s)
        return s
    }

    // MARK: - 请求辅助
    private func clientProvidedData(_ a: AnisetteHeaders) -> [String: Any] {
        [
            "b": AnisetteClient.bundleID,
            "c": a.clientTime,
            "did": a.deviceUUID,
            "k": a.md,
            "l": a.locale,
            "m": a.mdM,
            "p": "iPhone",
            "pc": "iPhone",
            "s": a.srlNo,
            "u": a.mdLU,
        ]
    }

    private func postGSAAuth(path: String, body: [String: Any],
                             anisette: AnisetteHeaders) async throws -> ([String: Any], [String: String]) {
        var req = URLRequest(url: URL(string: gsaBase + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/xml; charset=UTF-8", forHTTPHeaderField: "Accept")
        applyAnisette(&req, anisette)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SignError.apple("网络异常") }
        if http.statusCode >= 400 && http.statusCode != 401 {
            throw SignError.apple("登录接口返回 \(http.statusCode)")
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { acc, kv in
            if let k = kv.key as? String, let v = kv.value as? String { acc[k] = v }
        }
        return (json, headers)
    }

    private func applyAnisette(_ req: inout URLRequest, _ a: AnisetteHeaders) {
        for (k, v) in a.dictionary { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("iPhone", forHTTPHeaderField: "X-Apple-I-Device-Type")
    }

    private func applySessionHeaders(_ req: inout URLRequest, anisette: AnisetteHeaders,
                                     sessionId: String, scnt: String) {
        applyAnisette(&req, anisette)
        if !sessionId.isEmpty { req.setValue(sessionId, forHTTPHeaderField: "X-Apple-ID-Session-Id") }
        if !scnt.isEmpty { req.setValue(scnt, forHTTPHeaderField: "scnt") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func statusMessage(_ json: [String: Any]) -> String {
        if let st = json["Status"] as? [String: Any] {
            let ec = st["ec"] as? Int ?? 0
            let em = st["em"] as? String ?? "未知错误"
            return "\(em)（\(ec)）"
        }
        return (json["em"] as? String) ?? "未知错误"
    }

    // MARK: - 持久化
    private func saveSession(_ s: AppleSession) {
        UserDefaults.standard.set(s.gsToken, forKey: "sd_gs_token")
        UserDefaults.standard.set(s.identityId, forKey: "sd_identity_id")
        UserDefaults.standard.set(s.dsid, forKey: "sd_dsid")
    }

    func restoreIfPossible() {
        let token = UserDefaults.standard.string(forKey: "sd_gs_token") ?? ""
        let identity = UserDefaults.standard.string(forKey: "sd_identity_id") ?? ""
        guard !token.isEmpty else { return }
        session = AppleSession(username: UserDefaults.standard.string(forKey: "sd_account") ?? "",
                               gsToken: token, identityId: identity,
                               dsid: UserDefaults.standard.string(forKey: "sd_dsid") ?? "",
                               teamId: nil, teamName: nil,
                               anisette: AnisetteHeaders(clientTime: "", timeZone: "", locale: "",
                                                         deviceUUID: "", md: "", mdM: "",
                                                         mdRINFO: "", mdLU: "", srlNo: ""))
    }

    func signOut() {
        session = nil
        pending = nil
        ["sd_gs_token", "sd_identity_id", "sd_dsid"].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
