import Foundation

/// anisette 数据结构 —— Apple 登录接口要求的设备校验头
struct AnisetteHeaders {
    var clientTime: String
    var timeZone: String
    var locale: String
    var deviceUUID: String
    var md: String
    var mdM: String
    var mdRINFO: String
    var mdLU: String
    var srlNo: String

    var dictionary: [String: String] {
        [
            "X-Apple-I-Client-Time": clientTime,
            "X-Apple-I-TimeZone": timeZone,
            "X-Apple-Locale": locale,
            "X-Apple-I-MD": md,
            "X-Apple-I-MD-M": mdM,
            "X-Apple-I-MD-RINFO": mdRINFO,
            "X-Apple-I-MD-LU": mdLU,
            "X-Apple-I-SRL-NO": srlNo,
        ]
    }
}

/// 从远程 anisette 服务器获取设备校验头（iOS 无法本地生成）
final class AnisetteClient {

    static let shared = AnisetteClient()

    /// 默认公开实例；可在设置里改成自建服务器
    static let defaultServer = "https://ani.sidestore.io"
    static let bundleID = "com.signdrop.Signdrop"

    private var cache: AnisetteHeaders?
    private var cacheDate: Date?
    /// 缓存 5 分钟，避免频繁请求
    private let ttl: TimeInterval = 300

    private var server: String {
        UserDefaults.standard.string(forKey: "sd_anisette_server") ?? Self.defaultServer
    }

    func fetch(force: Bool = false) async throws -> AnisetteHeaders {
        if !force, let c = cache, let d = cacheDate, Date().timeIntervalSince(d) < ttl {
            return c
        }
        let headers = try await requestFromServer()
        cache = headers
        cacheDate = Date()
        return headers
    }

    private func requestFromServer() async throws -> AnisetteHeaders {
        guard var url = URL(string: server.trimmingCharacters(in: .whitespaces)) else {
            throw SignError.anisette("服务器地址无效")
        }
        if url.path.isEmpty { url = URL(string: server + "/") ?? url }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        let body: [String: Any] = [
            "client_info": [
                "bundle_id": Self.bundleID,
                "client_description": "Signdrop",
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw SignError.anisette("anisette 服务器无响应（\((resp as? HTTPURLResponse)?.statusCode ?? -1)）")
        }

        // 兼容两种返回：扁平字典 或 {"headers": {...}} / {"data": {...}}
        guard var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SignError.anisette("anisette 返回格式异常")
        }
        if let nested = dict["headers"] as? [String: Any] { dict = nested }
        if let nested = dict["data"] as? [String: Any] { dict = nested }

        func str(_ keys: [String]) -> String? {
            for k in keys {
                if let v = dict[k] as? String, !v.isEmpty { return v }
                if let v = dict[k] as? Int { return String(v) }
            }
            return nil
        }

        guard let md = str(["X-Apple-I-MD", "md"]) else {
            // 服务器需要先 provision 时给出明确提示
            let msg = (dict["message"] as? String) ?? (dict["error"] as? String) ?? "缺少 X-Apple-I-MD"
            throw SignError.anisette("anisette 数据缺失：\(msg)")
        }

        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return AnisetteHeaders(
            clientTime: str(["X-Apple-I-Client-Time", "client_time"]) ?? fmt.string(from: Date()) + "Z",
            timeZone: str(["X-Apple-I-TimeZone", "timezone"]) ?? "GMT+0800",
            locale: str(["X-Apple-Locale", "locale"]) ?? "zh_CN",
            deviceUUID: (str(["X-Apple-I-MD-LU", "local_user_id"]) ?? UUID().uuidString)
                .replacingOccurrences(of: ":", with: "").uppercased(),
            md: md,
            mdM: str(["X-Apple-I-MD-M", "machine_id"]) ?? "",
            mdRINFO: str(["X-Apple-I-MD-RINFO", "routing_info"]) ?? "17106176",
            mdLU: str(["X-Apple-I-MD-LU", "local_user_id"]) ?? "",
            srlNo: str(["X-Apple-I-SRL-NO", "serial_number"]) ?? "0"
        )
    }
}
