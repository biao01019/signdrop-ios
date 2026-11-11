import Foundation
import Security
import CryptoKit

// MARK: - 极简 DER 编码器（PKCS#7 需要的几个基本类型）
enum DER {

    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var v = n
        var bytes: [UInt8] = []
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func tlv(_ tag: UInt8, _ body: [UInt8]) -> [UInt8] {
        [tag] + length(body.count) + body
    }

    static func sequence(_ items: [[UInt8]]) -> [UInt8] {
        tlv(0x30, items.flatMap { $0 })
    }

    static func set(_ items: [[UInt8]]) -> [UInt8] {
        tlv(0x31, items.flatMap { $0 })
    }

    /// 整数（raw 为大端字节，自动去前导零 / 补符号位）
    static func integer(_ raw: [UInt8]) -> [UInt8] {
        var b = raw
        while b.count > 1 && b[0] == 0x00 && b[1] < 0x80 { b.removeFirst() }
        if b.isEmpty { b = [0] }
        if let f = b.first, f & 0x80 != 0 { b.insert(0x00, at: 0) }
        return tlv(0x02, b)
    }

    static func integer(_ v: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var n = v
        if n == 0 { bytes = [0] }
        while n > 0 {
            bytes.insert(UInt8(n & 0xFF), at: 0)
            n >>= 8
        }
        return integer(bytes)
    }

    static func oid(_ body: [UInt8]) -> [UInt8] { tlv(0x06, body) }
    static func octet(_ body: [UInt8]) -> [UInt8] { tlv(0x04, body) }
    static func null() -> [UInt8] { [0x05, 0x00] }
    static func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }

    /// 上下文标签（默认构造型，即 0xA0|tag）
    static func context(_ tag: UInt8, _ body: [UInt8], constructed: Bool = true) -> [UInt8] {
        tlv(constructed ? (0xA0 | tag) : (0x80 | tag), body)
    }

    static func utcTime(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyMMddHHmmss'Z'"
        return tlv(0x17, Array(f.string(from: date).utf8))
    }
}

// MARK: - Apple 代码签名用的 CMS/PKCS#7 SignedData（iOS 无 CMSEncoder，手写 DER）
enum CodeSignCMS {

    private enum OID {
        static let data: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x01]
        static let signedData: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02]
        static let contentType: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x03]
        static let messageDigest: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x04]
        static let signingTime: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x05]
        static let sha256: [UInt8] = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
        static let rsa: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        static let ecdsaSHA256: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x04, 0x03, 0x02]
    }

    struct Signer {
        var certificate: SecCertificate
        var privateKey: SecKey
    }

    /// 生成 CMS 签名 blob（magic 0xfade0cc0），内容为 detached 的 CodeDirectory
    static func signatureBlob(codeDirectory: Data, signer: Signer, extraCerts: [SecCertificate]) throws -> Data {

        let certData = SecCertificateCopyData(signer.certificate) as Data
        let issuer = (SecCertificateCopyNormalizedIssuerSequence(signer.certificate) as Data?) ?? Data()
        let serial = (SecCertificateCopySerialNumberData(signer.certificate, nil) as Data?) ?? Data([0])

        let attrs = [
            DER.sequence([DER.oid(OID.contentType), DER.set([DER.oid(OID.data)])]),
            DER.sequence([DER.oid(OID.messageDigest),
                          DER.set([DER.octet([UInt8](SHA256.hash(data: codeDirectory)))])]),
            DER.sequence([DER.oid(OID.signingTime), DER.set([DER.utcTime(Date())])]),
        ]
        // 签名内容 = authenticatedAttributes 的完整 SET OF 编码
        let attrsDER = DER.set(attrs)

        let keyAttrs = SecKeyCopyAttributes(signer.privateKey) as? [String: Any]
        let isRSA = (keyAttrs?[kSecAttrKeyType as String] as? String) == (kSecAttrKeyTypeRSA as String)
        let algorithm: SecKeyAlgorithm = isRSA ? .rsaSignatureMessagePKCS1v15SHA256
                                              : .ecdsaSignatureMessageX962SHA256

        var error: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(signer.privateKey, algorithm,
                                                  Data(attrsDER) as CFData, &error) as Data? else {
            let msg = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "未知错误"
            throw SignError.cmsFailed(msg)
        }

        let signatureAlgorithm = isRSA
            ? DER.sequence([DER.oid(OID.rsa), DER.null()])
            : DER.sequence([DER.oid(OID.ecdsaSHA256)])

        let signerInfo = DER.sequence([
            DER.integer(1),
            DER.sequence([issuer.isEmpty ? DER.sequence([]) : [UInt8](issuer),
                          DER.integer([UInt8](serial))]),
            DER.sequence([DER.oid(OID.sha256), DER.null()]),
            DER.context(0, attrs.flatMap { $0 }),      // [0] IMPLICIT authenticatedAttributes
            signatureAlgorithm,
            DER.octet([UInt8](sigData)),
        ])

        var certsBytes = [UInt8](certData)
        for c in extraCerts {
            let d = SecCertificateCopyData(c) as Data
            if d != certData { certsBytes += [UInt8](d) }
        }

        let signedData = DER.sequence([
            DER.integer(1),
            DER.set([DER.sequence([DER.oid(OID.sha256), DER.null()])]),
            DER.sequence([DER.oid(OID.data)]),          // detached → 不带内容
            DER.context(0, certsBytes),                 // [0] IMPLICIT certificates
            DER.set([signerInfo]),
        ])

        let contentInfo = DER.sequence([DER.oid(OID.signedData), DER.context(0, signedData)])
        return Data(contentInfo)
    }
}
