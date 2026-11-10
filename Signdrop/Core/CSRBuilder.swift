import Foundation
import Security

/// 手写 PKCS#10 CSR 生成（Security 框架不提供，需自行拼 ASN.1）
enum CSRBuilder {

    /// 生成 2048 位 RSA 私钥（保存在 App Keychain）
    static func generatePrivateKey(tag: String) throws -> SecKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(tag.utf8),
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw SignError.apple("生成密钥失败：\(error?.takeRetainedValue().localizedDescription ?? "")")
        }
        return key
    }

    static func loadPrivateKey(tag: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return (item as! SecKey)
    }

    static func privateKeyPEM(tag: String) throws -> String {
        guard let key = loadPrivateKey(tag: tag) ?? (try? generatePrivateKey(tag: tag)) else {
            throw SignError.apple("读取密钥失败")
        }
        guard let raw = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            throw SignError.apple("导出密钥失败")
        }
        let pkcs8 = ASN1.pkcs1ToPKCS8(raw)
        return "-----BEGIN PRIVATE KEY-----\n" + ASN1.base64Lines(pkcs8) + "\n-----END PRIVATE KEY-----\n"
    }

    /// 生成 CSR（DER）
    static func makeCSR(commonName: String, teamId: String, keyTag: String) throws -> (der: Data, keyTag: String) {
        let key: SecKey
        if let existing = loadPrivateKey(tag: keyTag) {
            key = existing
        } else {
            key = try generatePrivateKey(tag: keyTag)
        }
        guard let pub = SecKeyCopyPublicKey(key),
              let pubRaw = SecKeyCopyExternalRepresentation(pub, nil) as Data? else {
            throw SignError.apple("获取公钥失败")
        }

        // SubjectPublicKeyInfo
        let rsaOID = ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
        let algId = ASN1.seq(rsaOID + ASN1.null())
        let spki = ASN1.seq(algId + ASN1.bitString(pubRaw))

        // Subject
        let cn = ASN1.set(ASN1.seq(ASN1.oid([0x55, 0x04, 0x03]) + ASN1.utf8(commonName)))
        let ou = ASN1.set(ASN1.seq(ASN1.oid([0x55, 0x04, 0x0B]) + ASN1.utf8(teamId)))
        let subject = ASN1.seq(cn + ou)

        // CertificationRequestInfo
        let cri = ASN1.seq(ASN1.integer(0) + subject + spki + Data([0xA0, 0x00]))

        var error: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                              cri as CFData, &error) as Data? else {
            throw SignError.apple("CSR 签名失败：\(error?.takeRetainedValue().localizedDescription ?? "")")
        }

        let sha256OID = ASN1.oid([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
        let sigAlg = ASN1.seq(sha256OID + ASN1.null())
        let csr = ASN1.seq(cri + sigAlg + ASN1.bitString(sig))

        return (csr, keyTag)
    }

    static func privateKeyTag(commonName: String) -> String {
        "com.signdrop.key.\(commonName)"
    }
}

// MARK: - 极简 DER 编码
enum ASN1 {
    static func len(_ n: Int) -> Data {
        if n < 0x80 { return Data([UInt8(n)]) }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return Data([UInt8(0x80 | bytes.count)] + bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + len(content.count) + content
    }

    static func seq(_ content: Data) -> Data { tlv(0x30, content) }
    static func set(_ content: Data) -> Data { tlv(0x31, content) }
    static func null() -> Data { Data([0x05, 0x00]) }
    static func integer(_ v: Int) -> Data { tlv(0x02, Data([UInt8(v)])) }
    static func oid(_ body: [UInt8]) -> Data { tlv(0x06, Data(body)) }
    static func utf8(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func bitString(_ d: Data) -> Data { tlv(0x03, Data([0x00]) + d) }

    static func base64Lines(_ d: Data) -> String {
        let b64 = d.base64EncodedString()
        var out: [String] = []
        var i = b64.startIndex
        while i < b64.endIndex {
            let e = b64.index(i, offsetBy: 64, limitedBy: b64.endIndex) ?? b64.endIndex
            out.append(String(b64[i..<e]))
            i = e
        }
        return out.joined(separator: "\n")
    }

    /// RSA PKCS#1 → PKCS#8
    static func pkcs1ToPKCS8(_ pkcs1: Data) -> Data {
        let alg = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86,
                        0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let inner = alg + Data([0x04]) + len(pkcs1.count) + pkcs1
        return seq(inner)
    }
}
