import Foundation
import Security
import ZIPFoundation

// MARK: - 签名引擎：IPA 解压 → 注入描述文件 → ldid 重签名 → 重新打包
final class SigningEngine: ObservableObject {

    static let shared = SigningEngine()

    /// Documents 目录结构
    static var importsDir: URL  { dir("Imports") }
    static var workDir: URL     { dir("Work") }
    static var signedDir: URL   { dir("Signed") }
    static var certsDir: URL    { dir("Certs") }

    private static func dir(_ name: String) -> URL {
        let u = FileManager.default.documentsURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: 导入 IPA
    @discardableResult
    func importIPA(from url: URL) throws -> (name: String, sizeMB: Double) {
        let dst = Self.importsDir.appendingPathComponent(url.lastPathComponent)
        if dst != url {
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: url, to: dst)
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Double) ?? 0
        return (url.lastPathComponent, (size / 1024 / 1024 * 10).rounded() / 10)
    }

    // MARK: 导入 .p12 证书 + 描述文件
    func importP12(from url: URL, password: String) throws {
        let dst = Self.certsDir.appendingPathComponent("identity.p12")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
        try KeychainStore.save(password, forKey: "sd_p12_pass")
    }

    func importProfile(from url: URL) throws {
        let dst = Self.certsDir.appendingPathComponent("embedded.mobileprovision")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
    }

    var hasProfile: Bool { FileManager.default.fileExists(atPath: Self.certsDir.appendingPathComponent("embedded.mobileprovision").path) }
    var hasP12: Bool { FileManager.default.fileExists(atPath: Self.certsDir.appendingPathComponent("identity.p12").path) }

    // MARK: 从 .mobileprovision 提取 plist（CMS 包裹，直接定位 XML）
    func extractProfilePlist() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.certsDir.appendingPathComponent("embedded.mobileprovision"))
        guard let xml = data.xmlPlistRange() else { throw SignError.badProfile }
        let plist = try PropertyListSerialization.propertyList(from: xml, format: nil)
        guard let dict = plist as? [String: Any] else { throw SignError.badProfile }
        return dict
    }

    /// 从描述文件生成 entitlements XML
    func writeEntitlements(from profile: [String: Any], to url: URL) throws {
        guard let ents = profile["Entitlements"] as? [String: Any] else { throw SignError.noEntitlements }
        let data = try PropertyListSerialization.data(fromPropertyList: ents, format: .xml, options: 0)
        try data.write(to: url)
    }

    // MARK: p12 → PEM（私钥 + 证书），供 ldid 使用
    func exportPEM() throws -> URL {
        let p12URL = Self.certsDir.appendingPathComponent("identity.p12")
        let data = try Data(contentsOf: p12URL)
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: KeychainStore.load(forKey: "sd_p12_pass") ?? ""
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let arr = items as? [[String: Any]], let first = arr.first,
              let identity = first[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw SignError.badP12
        }        // 证书 → PEM
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let cert else { throw SignError.badP12 }
        let certData = SecCertificateCopyData(cert) as Data
        var pem = "-----BEGIN CERTIFICATE-----\n"
        pem += base64Lines(certData)
        pem += "\n-----END CERTIFICATE-----\n"
        // 私钥 → PKCS#8 PEM
        var key: SecKey?
        SecIdentityCopyPrivateKey(identity, &key)
        guard let key else { throw SignError.badP12 }
        guard let keyData0 = SecKeyCopyExternalRepresentation(key, nil) as Data? else { throw SignError.badP12 }
        var keyData = keyData0
        let attrs = SecKeyCopyAttributes(key) as? [String: Any]
        let keyTypeRaw = attrs?[kSecAttrKeyType as String] as? String ?? ""
        if keyTypeRaw == (kSecAttrKeyTypeECDSA as String) {
            // SEC1 → 包一层 EC PRIVATE KEY（ldid 兼容 PEM EC）
            pem += sec1ToPEM(keyData)
        } else {
            // RSA: SecKeyCopyExternalRepresentation 返回 PKCS#1，包成 PKCS#8
            keyData = pkcs1ToPKCS8(keyData)
            pem += "-----BEGIN PRIVATE KEY-----\n"
            pem += base64Lines(keyData)
            pem += "\n-----END PRIVATE KEY-----\n"
        }
        let out = Self.workDir.appendingPathComponent("identity.pem")
        try pem.data(using: .utf8)!.write(to: out)
        return out
    }

    private func base64Lines(_ d: Data) -> String {
        let b64 = d.base64EncodedString()
        var lines: [String] = []
        var i = b64.startIndex
        while i < b64.endIndex {
            let e = b64.index(i, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append(String(b64[i..<e]))
            i = e
        }
        return lines.joined(separator: "\n")
    }

    /// RSA PKCS#1 → PKCS#8（手工拼 ASN.1 头）
    private func pkcs1ToPKCS8(_ pkcs1: Data) -> Data {
        let pkcs1Len = asn1LenBytes(pkcs1.count)
        let total = pkcs1.count + pkcs1Len.count + 9 // 0x30 tag + len + 15-byte AlgorithmIdentifier minus 6... simplified
        let header: [UInt8] = [0x30] + asn1LenBytes(total + 11) +
            [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x04] +
            asn1LenBytes(pkcs1.count)
        var out = Data(header)
        out.append(pkcs1)
        return out
    }

    /// EC SEC1 raw → PEM
    private func sec1ToPEM(_ raw: Data) -> String {
        var s = "-----BEGIN EC PRIVATE KEY-----\n"
        s += base64Lines(raw)
        s += "\n-----END EC PRIVATE KEY-----\n"
        return s
    }

    private func asn1LenBytes(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        let bytes = withUnsafeBytes(of: UInt16(n).bigEndian) { Array($0).filter { $0 != 0 } }
        return [UInt8(0x80 + bytes.count)] + bytes
    }

    // MARK: posix_spawn 执行 ldid
    @discardableResult
    func runBinary(at path: String, args: [String]) throws -> Int32 {
        chmod(path, 0o755)
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(path)] + args.map { strdup($0) } + [nil]
        var pid: pid_t = 0
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        
        let status = posix_spawn(&pid, path, nil, &attr, &argv, environ)
        guard status == 0 else { throw SignError.spawnFailed(status) }
        var result: Int32 = 0
        waitpid(pid, &result, 0)
        argv.forEach { if let p = $0 { free(p) } }
        return (result >> 8) & 0xff
    }

    var ldidPath: String? {
        Bundle.main.path(forResource: "ldid", ofType: "") ?? Bundle.main.path(forResource: "ldid", ofType: "bin")
    }

    // MARK: 完整签名流水线
    /// 返回签名后的 IPA 路径；onStep 回调步骤进度（0...1）
    func sign(fileName: String,
              keepIcon: Bool = true,
              onProgress: @escaping (Double) -> Void,
              onStep: @escaping (SignStep, Bool) -> Void) throws -> URL {

        let work = Self.workDir
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        // Step 1: 解压
        let ipa = Self.importsDir.appendingPathComponent(fileName)
        onStep(.unzip, false)
        try fm.unzipItem(at: ipa, to: work)
        onStep(.unzip, true)
        onProgress(0.15)

        // Step 2: 校验描述文件
        onStep(.verify, false)
        guard let payload = try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent == "Payload" }),
              let appURL = try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
            throw SignError.noAppBundle
        }
        var profile: [String: Any] = [:]
        if hasProfile {
            profile = try extractProfilePlist()
            if let bid = profile["application-identifier"] as? String {
                let realID = bid.components(separatedBy: ".").dropFirst().joined(separator: ".")
                if !realID.isEmpty && !realID.hasPrefix("*") {
                    let infoPlist = appURL.appendingPathComponent("Info.plist")
                    if var info = try? PropertyListSerialization.propertyList(from: Data(contentsOf: infoPlist), format: nil) as? [String: Any] {
                        info["CFBundleIdentifier"] = realID
                        if !keepIcon { info["CFBundleIconName"] = nil }
                        let d = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
                        try d.write(to: infoPlist)
                    }
                }
            }
        } else {
            throw SignError.noProfile
        }
        let entURL = work.appendingPathComponent("entitlements.plist")
        try writeEntitlements(from: profile, to: entURL)
        onStep(.verify, true)
        onProgress(0.3)

        // Step 3: ldid 重签名（主二进制 + 所有 Frameworks + PlugIns）
        onStep(.resign, false)
        guard let ldid = ldidPath else { throw SignError.noLdid }
        let pem = try exportPEM().path
        // 覆盖 embedded.mobileprovision
        try? fm.removeItem(at: appURL.appendingPathComponent("embedded.mobileprovision"))
        try fm.copyItem(at: Self.certsDir.appendingPathComponent("embedded.mobileprovision"),
                        to: appURL.appendingPathComponent("embedded.mobileprovision"))

        var binaryName = appURL.deletingPathExtension().lastPathComponent
        if let infoData = try? Data(contentsOf: appURL.appendingPathComponent("Info.plist")),
           let infoDict = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
           let exec = infoDict["CFBundleExecutable"] as? String {
            binaryName = exec
        }
        let targets = [appURL.appendingPathComponent(binaryName)]
            + ((try? fm.subdirectories(of: appURL.appendingPathComponent("Frameworks"))) ?? []).map { $0.appendingPathComponent($0.deletingPathExtension().lastPathComponent) }
            + ((try? fm.subdirectories(of: appURL.appendingPathComponent("PlugIns"))) ?? []).flatMap { appex in
                ((try? fm.subdirectories(of: appex.appendingPathComponent("Frameworks"))) ?? []).map { $0.appendingPathComponent($0.deletingPathExtension().lastPathComponent) }
            }
        for target in targets {
            try runBinary(at: ldid, args: ["-S" + entURL.path, "-K", pem, target.path])
        }
        onStep(.resign, true)
        onProgress(0.75)

        // Step 4: 重新打包
        onStep(.pack, false)
        let signedName = fileName.replacingOccurrences(of: ".ipa", with: "") + "-signed.ipa"
        let out = Self.signedDir.appendingPathComponent(signedName)
        try? fm.removeItem(at: out)
        try fm.zipItem(at: payload, to: out)
        onStep(.pack, true)
        onProgress(1.0)

        try? fm.removeItem(at: work)
        return out
    }
}

extension FileManager {
    var documentsURL: URL {
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    func subdirectories(of url: URL) throws -> [URL] {
        try contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}

extension Data {
    /// 定位 CMS 包裹中的 XML plist 范围
    func xmlPlistRange() -> Data? {
        guard let start = range(of: Data("<?xml".utf8)),
              let end = range(of: Data("</plist>".utf8), in: start.upperBound..<endIndex) else { return nil }
        return subdata(in: start.lowerBound..<end.upperBound)
    }
}

enum SignError: LocalizedError {
    case badProfile, noEntitlements, badP12, noAppBundle, noProfile, noLdid, spawnFailed(Int32)
    var errorDescription: String? {
        switch self {
        case .badProfile: return "描述文件无法解析"
        case .noEntitlements: return "描述文件中缺少 Entitlements"
        case .badP12: return "证书或密码错误"
        case .noAppBundle: return "IPA 中找不到 .app 包"
        case .noProfile: return "请先导入 .mobileprovision 描述文件"
        case .noLdid: return "签名组件 ldid 缺失"
        case .spawnFailed(let c): return "签名进程启动失败(\(c))"
        }
    }
}

// MARK: - 轻量 Keychain 存取
enum KeychainStore {
    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key] as CFDictionary)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                    kSecValueData: data] as CFDictionary, nil)
    }
    static func load(forKey key: String) -> String? {
        var out: CFTypeRef?
        let st = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrAccount: key,
                                      kSecReturnData: true] as CFDictionary, &out)
        guard st == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}
