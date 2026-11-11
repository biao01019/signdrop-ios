import Foundation
import Security
import CryptoKit
import ZIPFoundation

// MARK: - 签名引擎
/// 全程在 App 进程内完成：解压 → 注入描述文件 → 逐层 Mach-O 重签名 → 打包为合法 IPA
/// 不执行任何外部二进制（iOS 沙盒禁止），也不依赖网络。
final class SigningEngine: ObservableObject {

    static let shared = SigningEngine()

    // MARK: 目录
    static var importsDir: URL { dir("Imports") }
    static var workDir: URL    { dir("Work") }
    static var signedDir: URL  { dir("Signed") }
    static var certsDir: URL   { dir("Certs") }

    private static func dir(_ name: String) -> URL {
        let u = FileManager.default.documentsURL.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: 模型
    struct Identity {
        var label: String
        var certificate: SecCertificate
        var privateKey: SecKey
        var teamID: String?
    }

    struct SignOutput {
        var ipaURL: URL
        var appName: String
        var bundleID: String
        var isAdHoc: Bool
        var warnings: [String]
    }

    // MARK: - 导入 IPA（真正复制进沙盒）
    @discardableResult
    func importIPA(from url: URL) throws -> (name: String, sizeMB: Double) {
        let name = url.lastPathComponent
        guard name.lowercased().hasSuffix(".ipa") else { throw SignError.notIPA }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let dst = Self.importsDir.appendingPathComponent(name)
        if dst.standardizedFileURL != url.standardizedFileURL {
            try? fm.removeItem(at: dst)
            do {
                try fm.copyItem(at: url, to: dst)
            } catch {
                // iCloud 未下载时先取到本地再复制
                let tmp = fm.temporaryDirectory.appendingPathComponent(name)
                try? fm.removeItem(at: tmp)
                try fm.copyItem(at: url, to: tmp)
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: tmp, to: dst)
                try? fm.removeItem(at: tmp)
            }
        }
        let attrs = (try? fm.attributesOfItem(atPath: dst.path)) ?? [:]
        let size = ((attrs[.size] as? NSNumber)?.doubleValue ?? 0) / 1024 / 1024
        guard size > 0 else { throw SignError.notIPA }
        return (name, (size * 10).rounded() / 10)
    }

    /// 已导入的 IPA 列表（含通过「文件」App 拖入的）
    func importedIPAs() -> [(name: String, sizeMB: Double)] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: Self.importsDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return items
            .filter { $0.pathExtension.lowercased() == "ipa" }
            .compactMap { u in
                let size = ((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                guard size > 0 else { return nil }
                return (u.lastPathComponent, (Double(size) / 1024 / 1024 * 10).rounded() / 10)
            }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - 证书
    func importP12(from url: URL, password: String) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dst = Self.certsDir.appendingPathComponent("identity.p12")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
        KeychainStore.save(password, forKey: "sd_p12_pass")
        // 立即校验一次，密码错误当场报出来
        _ = try loadIdentity()
    }

    func importProfile(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dst = Self.certsDir.appendingPathComponent("embedded.mobileprovision")
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: url, to: dst)
        _ = try extractProfilePlist(at: dst)
    }

    var hasProfile: Bool {
        FileManager.default.fileExists(atPath: Self.certsDir.appendingPathComponent("embedded.mobileprovision").path)
    }
    var hasP12: Bool {
        FileManager.default.fileExists(atPath: Self.certsDir.appendingPathComponent("identity.p12").path)
    }

    var profileURL: URL { Self.certsDir.appendingPathComponent("embedded.mobileprovision") }

    /// 从已导入的 p12 取签名身份
    func loadIdentity() throws -> Identity {
        let p12URL = Self.certsDir.appendingPathComponent("identity.p12")
        guard FileManager.default.fileExists(atPath: p12URL.path) else { throw SignError.noP12 }
        let data = try Data(contentsOf: p12URL)
        let password = KeychainStore.load(forKey: "sd_p12_pass") ?? ""
        var items: CFArray?
        let opts: [String: Any] = [kSecImportExportPassphrase as String: password]
        let status = SecPKCS12Import(data as CFData, opts as CFDictionary, &items)
        guard status == errSecSuccess,
              let arr = items as? [[String: Any]],
              let dict = arr.first,
              let identity = dict[kSecImportItemIdentity as String] as! SecIdentity? else {
            throw SignError.badP12
        }
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        var key: SecKey?
        SecIdentityCopyPrivateKey(identity, &key)
        guard let cert, let key else { throw SignError.badP12 }

        let team = Self.organizationalUnit(from: cert)
        let cn = (SecCertificateCopySubjectSummary(cert) as String?) ?? "导入证书"
        return Identity(label: cn, certificate: cert, privateKey: key, teamID: team)
    }

    /// iOS 上没有 SecCertificateCopyValues（macOS 专属），这里直接扫 DER 里的 OU 字段（OID 2.5.4.11）。
    /// Apple 开发证书的 OU 就是 Team ID（10 位大写字母/数字）。
    static func organizationalUnit(from cert: SecCertificate) -> String? {
        let der = [UInt8](SecCertificateCopyData(cert) as Data)
        let ouOID: [UInt8] = [0x06, 0x03, 0x55, 0x04, 0x0B]
        var i = 0
        while i + ouOID.count < der.count {
            if Array(der[i..<(i + ouOID.count)]) == ouOID {
                var j = i + ouOID.count
                let tag = der[j]; j += 1
                guard j < der.count else { break }
                var len = Int(der[j]); j += 1
                if len & 0x80 != 0 {
                    let n = len & 0x7F
                    guard n >= 1, n <= 3, j + n <= der.count else { i += 1; continue }
                    var v = 0
                    for k in 0..<n { v = (v << 8) | Int(der[j + k]) }
                    j += n; len = v
                }
                if (tag == 0x0C || tag == 0x13 || tag == 0x16), len > 0, j + len <= der.count {
                    let s = String(decoding: der[j..<(j + len)], as: UTF8.self)
                    if s.count == 10, s.allSatisfy({ ($0.isUppercase || $0.isNumber) && $0.isASCII }) {
                        return s
                    }
                }
            }
            i += 1
        }
        return nil
    }

    /// 证书链上需要的中间证书（p12 里通常没有，必须随 CMS 提供）
    func intermediateCertificates() -> [SecCertificate] {
        var out: [SecCertificate] = []
        for name in ["AppleWWDRCAG4", "AppleWWDRCAG3"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "cer"),
                  let data = try? Data(contentsOf: url),
                  let c = SecCertificateCreateWithData(nil, data as CFData) else { continue }
            out.append(c)
        }
        return out
    }

    // MARK: - 描述文件
    func extractProfilePlist(at url: URL? = nil) throws -> [String: Any] {
        let target = url ?? profileURL
        let data: Data
        do { data = try Data(contentsOf: target) } catch { throw SignError.noProfile }
        // 兼容裸 plist 与 CMS 包裹
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = plist as? [String: Any], dict["Entitlements"] != nil {
            return dict
        }
        guard let xml = data.xmlPlistRange() else { throw SignError.badProfile }
        let plist = try PropertyListSerialization.propertyList(from: xml, format: nil)
        guard let dict = plist as? [String: Any] else { throw SignError.badProfile }
        return dict
    }

    func writeEntitlements(from profile: [String: Any], bundleID: String, teamID: String?, to url: URL) throws {
        guard var ents = profile["Entitlements"] as? [String: Any] else { throw SignError.noEntitlements }
        if let team = teamID ?? (profile["TeamIdentifier"] as? [String])?.first {
            ents["application-identifier"] = "\(team).\(bundleID)"
            if var groups = ents["keychain-access-groups"] as? [String], !groups.isEmpty {
                groups[0] = "\(team).\(bundleID)"
                ents["keychain-access-groups"] = groups
            }
        }
        let data = try PropertyListSerialization.data(fromPropertyList: ents, format: .xml, options: 0)
        try data.write(to: url)
    }

    // MARK: - 主流程
    func sign(fileName: String,
              keepIcon: Bool = true,
              identity: Identity?,
              profileOverride: URL? = nil,
              onProgress: @escaping (Double) -> Void,
              onStep: @escaping (SignStep, Bool) -> Void,
              onLog: @escaping (String) -> Void = { _ in }) throws -> SignOutput {

        let fm = FileManager.default
        let work = Self.workDir
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        var warnings: [String] = []

        // ---- 1. 解压 ----
        let ipaURL = Self.importsDir.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: ipaURL.path) else { throw SignError.fileMissing(fileName) }
        onStep(.unzip, false)
        onLog("解压 \(fileName)…")
        try fm.unzipItem(at: ipaURL, to: work)
        onStep(.unzip, true)
        onProgress(0.12)

        // ---- 2. 定位 .app ----
        guard let payload = try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.lowercased() == "payload" }),
              let appURL = try? fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension.lowercased() == "app" }) else {
            throw SignError.noAppBundle
        }
        let infoURL = appURL.appendingPathComponent("Info.plist")
        guard var info = (try? PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil)) as? [String: Any] else {
            throw SignError.noAppBundle
        }
        var bundleID = info["CFBundleIdentifier"] as? String ?? "com.signdrop.unknown"
        var appName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        onLog("应用：\(appName)（\(bundleID)）")
        onProgress(0.2)

        // ---- 3. 描述文件 / Entitlements ----
        onStep(.verify, false)
        let pURL = profileOverride ?? profileURL
        var entitlementsData: Data?
        var teamID = identity?.teamID

        if fm.fileExists(atPath: pURL.path) {
            let profile = try extractProfilePlist(at: pURL)
            if teamID == nil { teamID = (profile["TeamIdentifier"] as? [String])?.first }
            if let appID = profile["application-identifier"] as? String,
               let dot = appID.firstIndex(of: ".") {
                let suffix = String(appID[appID.index(after: dot)...])
                if !suffix.isEmpty, !suffix.contains("*"), suffix != bundleID {
                    bundleID = suffix
                    onLog("Bundle ID 对齐描述文件：\(bundleID)")
                }
            }
            let entURL = work.appendingPathComponent("entitlements.plist")
            try writeEntitlements(from: profile, bundleID: bundleID, teamID: teamID, to: entURL)
            entitlementsData = try Data(contentsOf: entURL)
            onLog("描述文件就绪（Team \(teamID ?? "?")）")
        } else if identity != nil {
            throw SignError.noProfile
        } else {
            onLog("未提供描述文件 → 使用 ad-hoc 签名（TrollStore / 越狱设备可用）")
        }

        // ---- 4. 写入 Info.plist 与描述文件 ----
        info["CFBundleIdentifier"] = bundleID
        info.removeValue(forKey: "CFBundleResourceSpecification")
        if !keepIcon { info["CFBundleIconName"] = nil }
        let newInfo = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try newInfo.write(to: infoURL)
        let infoForHash = newInfo

        if entitlementsData != nil {
            let embedded = appURL.appendingPathComponent("embedded.mobileprovision")
            try? fm.removeItem(at: embedded)
            try fm.copyItem(at: pURL, to: embedded)
        }
        onStep(.verify, true)
        onProgress(0.3)

        // ---- 5. 清掉旧签名 ----
        var oldSignatures: [URL] = []
        if let en = fm.enumerator(at: appURL, includingPropertiesForKeys: nil) {
            for case let u as URL in en where u.lastPathComponent == "_CodeSignature" {
                oldSignatures.append(u)
            }
        }
        for u in oldSignatures { try? fm.removeItem(at: u) }
        if !oldSignatures.isEmpty { onLog("已清理 \(oldSignatures.count) 个旧签名目录") }

        // ---- 6. 逐层重签名 ----
        onStep(.resign, false)
        let mainBinaryName = info["CFBundleExecutable"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let mainBinary = appURL.appendingPathComponent(mainBinaryName)

        var machOFiles: [URL] = []
        if let en = fm.enumerator(at: appURL, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in en {
                let isFile = (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile, u.path != mainBinary.path else { continue }
                if MachOSigner.isMachO(u) { machOFiles.append(u) }
            }
        }
        // 深的先签（framework / dylib / appex 先于外层）
        machOFiles.sort { $0.pathComponents.count > $1.pathComponents.count }

        let signer = identity.map { CodeSignCMS.Signer(certificate: $0.certificate, privateKey: $0.privateKey) }
        let extraCerts = intermediateCertificates()

        for file in machOFiles {
            let rel = file.path.replacingOccurrences(of: appURL.path + "/", with: "")
            var identifier = bundleID + "." + file.lastPathComponent
            if let range = rel.range(of: ".framework/") {
                identifier = String(rel[rel.startIndex..<range.lowerBound]).components(separatedBy: "/").last ?? identifier
            } else if rel.contains(".appex/") {
                identifier = bundleID + ".appex"
            } else if file.pathExtension.lowercased() == "dylib" {
                identifier = file.deletingPathExtension().lastPathComponent
            }
            let isAppexBinary = rel.contains(".appex/") && !rel.contains(".appex/Frameworks/")
            do {
                try MachOSigner.sign(fileAt: file,
                                     options: .init(identifier: identifier,
                                                    entitlements: isAppexBinary ? entitlementsData : nil,
                                                    signer: signer,
                                                    extraCertificates: extraCerts,
                                                    isMainExecutable: false,
                                                    teamIdentifier: teamID),
                                     infoPlist: nil)
            } catch {
                warnings.append("跳过 \(rel)：\(error.localizedDescription)")
            }
        }
        onProgress(0.55)

        // 主二进制
        do {
            try MachOSigner.sign(fileAt: mainBinary,
                                 options: .init(identifier: bundleID,
                                                entitlements: entitlementsData,
                                                signer: signer,
                                                extraCertificates: extraCerts,
                                                isMainExecutable: true,
                                                teamIdentifier: teamID),
                                 infoPlist: infoForHash)
            onLog("主二进制已签名（\(signer == nil ? "ad-hoc" : "证书")）")
        } catch {
            throw SignError.signFailed(error.localizedDescription)
        }
        onStep(.resign, true)
        onProgress(0.8)

        // ---- 7. 打包 ----
        onStep(.pack, false)
        let base = fileName.replacingOccurrences(of: ".ipa", with: "", options: .caseInsensitive)
        let out = Self.signedDir.appendingPathComponent("\(base)-signed.ipa")
        try writeIPA(payloadDir: payload, to: out)
        onLog("已打包：\(out.lastPathComponent)（\((fileSize(out) / 1024 / 1024 * 10).rounded() / 10) MB）")
        onStep(.pack, true)
        onProgress(1.0)

        return SignOutput(ipaURL: out, appName: appName, bundleID: bundleID,
                          isAdHoc: signer == nil, warnings: warnings)
    }

    private func fileSize(_ url: URL) -> Double {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = attrs[.size] as? NSNumber else { return 0 }
        return n.doubleValue
    }

    // MARK: - 打包为合法 IPA（顶层 Payload/，权限 755）
    func writeIPA(payloadDir: URL, to out: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: out)
        let archive = try Archive(url: out, accessMode: .create)

        struct Item { let path: String; let url: URL; let isDir: Bool }
        var items: [Item] = [Item(path: "Payload", url: payloadDir, isDir: true)]
        if let en = fm.enumerator(at: payloadDir, includingPropertiesForKeys: [.isDirectoryKey]) {
            for case let u as URL in en {
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let rel = u.path.replacingOccurrences(of: payloadDir.path + "/", with: "")
                items.append(Item(path: "Payload/" + rel, url: u, isDir: isDir))
            }
        }

        for item in items {
            if item.isDir {
                try archive.addEntry(with: item.path + "/", type: Entry.EntryType.directory,
                                     uncompressedSize: Int64(0), modificationDate: Date(),
                                     permissions: UInt16(0o755), compressionMethod: CompressionMethod.none,
                                     bufferSize: 4096, progress: nil,
                                     provider: { (_: Int, _: Int) throws -> Data in Data() })
            } else {
                let attrs = (try? fm.attributesOfItem(atPath: item.url.path)) ?? [:]
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let perms: UInt16 = MachOSigner.isMachO(item.url) ? 0o755 : 0o644
                try archive.addEntry(with: item.path, type: Entry.EntryType.file,
                                     uncompressedSize: Int64(size), modificationDate: Date(),
                                     permissions: UInt16(perms), compressionMethod: CompressionMethod.deflate,
                                     bufferSize: 1 << 20, progress: nil,
                                     provider: { (position: Int, length: Int) throws -> Data in
                    guard let h = try? FileHandle(forReadingFrom: item.url) else { return Data() }
                    defer { try? h.close() }
                    try? h.seek(toOffset: UInt64(position))
                    return h.readData(ofLength: length)
                })
            }
        }
    }

    // MARK: - 读取 IPA 基本信息（用于 Apple ID 直签创建 App ID）
    func appInfo(ofIPA fileName: String) throws -> (bundleID: String, name: String) {
        let ipa = Self.importsDir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: ipa.path) else { throw SignError.fileMissing(fileName) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("info-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.unzipItem(at: ipa, to: tmp)
        guard let payload = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
                .first(where: { $0.lastPathComponent.lowercased() == "payload" }),
              let app = try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension.lowercased() == "app" }),
              let data = try? Data(contentsOf: app.appendingPathComponent("Info.plist")),
              let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let bid = dict["CFBundleIdentifier"] as? String else {
            throw SignError.noAppBundle
        }
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent
        return (bid, name)
    }
}

// MARK: - 工具
extension FileManager {
    var documentsURL: URL { urls(for: .documentDirectory, in: .userDomainMask)[0] }
}

extension Data {
    /// 定位 CMS 包裹中的 XML plist 范围
    func xmlPlistRange() -> Data? {
        guard let start = range(of: Data("<?xml".utf8)) else { return nil }
        guard let end = range(of: Data("</plist>".utf8), in: start.lowerBound..<endIndex) else { return nil }
        return subdata(in: start.lowerBound..<end.upperBound)
    }
}

enum SignError: LocalizedError {
    case badProfile, noEntitlements, badP12, noAppBundle, noProfile, noP12
    case notIPA
    case fileMissing(String)
    case cmsFailed(String)
    case signFailed(String)
    case anisette(String)
    case apple(String)

    var errorDescription: String? {
        switch self {
        case .badProfile: return "描述文件无法解析"
        case .noEntitlements: return "描述文件中缺少 Entitlements"
        case .badP12: return "证书或密码错误"
        case .noAppBundle: return "IPA 中找不到 .app 包"
        case .noProfile: return "缺少 .mobileprovision 描述文件（用证书签名必须导入）"
        case .noP12: return "请先导入 .p12 证书"
        case .notIPA: return "请选择 .ipa 文件"
        case .fileMissing(let n): return "找不到已导入的文件：\(n)，请重新导入"
        case .cmsFailed(let m): return "证书签名失败：\(m)"
        case .signFailed(let m): return "签名失败：\(m)"
        case .anisette(let m): return m
        case .apple(let m): return m
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
