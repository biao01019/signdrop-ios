import Foundation
import Security
import CryptoKit

// MARK: - 进程内 Mach-O 重签名（不依赖 ldid、不 exec 任何外部程序）
/// iOS 沙盒禁止执行 App 包内的第三方二进制，因此签名必须在进程内完成：
/// 解析 load commands → 重写 LC_CODE_SIGNATURE → 生成 CodeDirectory(page hashes)
/// → 组装 SuperBlob(CD + Requirements + Entitlements + CMS) → 回写文件
final class MachOSigner {

    struct Options {
        var identifier: String
        var entitlements: Data? = nil
        var signer: CodeSignCMS.Signer? = nil
        var extraCertificates: [SecCertificate] = []
        var isMainExecutable: Bool = false
        var teamIdentifier: String? = nil
    }

    private static let LC_SEGMENT_64: UInt32 = 0x19
    private static let LC_CODE_SIGNATURE: UInt32 = 0x1D
    private static let CSMAGIC_CODEDIRECTORY: UInt32 = 0xFADE0C02
    private static let CSMAGIC_REQUIREMENTS: UInt32 = 0xFADE0C01
    private static let CSMAGIC_ENTITLEMENTS: UInt32 = 0xFADE7171
    private static let CSMAGIC_EMBEDDED_SIGNATURE: UInt32 = 0xFADE0CC0
    private static let pageSize = 4096

    // MARK: 判断是否为 Mach-O
    static func isMachO(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let head = h.readData(ofLength: 8)
        guard head.count >= 4 else { return false }
        let b = [UInt8](head)
        let le = UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
        let be = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        if le == 0xFEEDFACF || le == 0xFEEDFACE { return true }
        if be == 0xCAFEBABE || be == 0xCAFEBABF { return true }
        return false
    }

    // MARK: 主入口
    static func sign(fileAt url: URL, options: Options, infoPlist: Data?) throws {
        let raw = try Data(contentsOf: url)
        let thin = try thinBinary(raw)
        var bytes = [UInt8](thin)

        guard bytes.count >= 32, u32(bytes, 0) == 0xFEEDFACF else {
            throw MachOSignError.notMachO
        }
        let ncmds = Int(u32(bytes, 16))
        var off = 32
        var csCmd: Int?
        var csDataOff = 0
        var textFileOff: UInt64 = 0
        var textFileSize: UInt64 = 0
        var leCmd: Int?
        var leFileOff: UInt64 = 0

        for _ in 0..<ncmds {
            guard off + 8 <= bytes.count else { throw MachOSignError.badLayout }
            let cmd = u32(bytes, off)
            let size = Int(u32(bytes, off + 4))
            guard size >= 8, off + size <= bytes.count else { throw MachOSignError.badLayout }
            if cmd == LC_CODE_SIGNATURE {
                csCmd = off
                csDataOff = Int(u32(bytes, off + 8))
            } else if cmd == LC_SEGMENT_64 {
                let nameBytes = Array(bytes[(off + 8)..<(off + 24)])
                let name = String(bytes: nameBytes.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
                if name == "__TEXT" {
                    textFileOff = u64(bytes, off + 40)
                    textFileSize = u64(bytes, off + 48)
                } else if name == "__LINKEDIT" {
                    leCmd = off
                    leFileOff = u64(bytes, off + 40)
                }
            }
            off += size
        }
        guard let csOff = csCmd else { throw MachOSignError.noCodeSignatureSlot }
        let codeLimit = csDataOff
        guard codeLimit > 32, codeLimit <= bytes.count else { throw MachOSignError.badLayout }

        // ---- 1. CodeDirectory ----
        let nSpecial = 5
        let nCodeSlots = (codeLimit + pageSize - 1) / pageSize
        let identBytes = Array(options.identifier.utf8) + [0]
        let teamBytes: [UInt8] = {
            guard let t = options.teamIdentifier, !t.isEmpty else { return [] }
            return Array(t.utf8) + [0]
        }()
        let headerLen = 88
        let identOffset = headerLen
        let teamOffset = teamBytes.isEmpty ? 0 : headerLen + identBytes.count
        var stringsEnd = headerLen + identBytes.count + teamBytes.count
        stringsEnd += (4 - stringsEnd % 4) % 4
        let hashOffset = stringsEnd + nSpecial * 32
        let cdLength = hashOffset + nCodeSlots * 32

        var cd = [UInt8](repeating: 0, count: cdLength)
        w32(&cd, 0, CSMAGIC_CODEDIRECTORY)
        w32(&cd, 4, UInt32(cdLength))
        w32(&cd, 8, 0x20400)
        w32(&cd, 12, options.signer == nil ? 0x2 : 0)   // CS_ADHOC
        w32(&cd, 16, UInt32(hashOffset))
        w32(&cd, 20, UInt32(identOffset))
        w32(&cd, 24, UInt32(nSpecial))
        w32(&cd, 28, UInt32(nCodeSlots))
        w32(&cd, 32, UInt32(codeLimit))
        cd[36] = 32        // hashSize
        cd[37] = 2         // hashType = SHA256
        cd[38] = 0         // platform
        cd[39] = 12        // pageSize = 1 << 12
        w64(&cd, 56, UInt64(codeLimit))   // codeLimit64
        w64(&cd, 64, textFileOff)         // execSegBase
        w64(&cd, 72, textFileSize)        // execSegLimit
        w64(&cd, 80, options.isMainExecutable ? 1 : 0)  // execSegFlags

        cd.replaceSubrange(identOffset..<(identOffset + identBytes.count), with: identBytes)
        if !teamBytes.isEmpty {
            cd.replaceSubrange(teamOffset..<(teamOffset + teamBytes.count), with: teamBytes)
        }

        // 页哈希
        let limit = codeLimit
        for i in 0..<nCodeSlots {
            let start = i * pageSize
            let end = min(start + pageSize, limit)
            var page = Array(bytes[start..<end])
            if page.count < pageSize { page += [UInt8](repeating: 0, count: pageSize - page.count) }
            let h = [UInt8](SHA256.hash(data: Data(page)))
            let pos = hashOffset + i * 32
            cd.replaceSubrange(pos..<(pos + 32), with: h)
        }

        // ---- 2. 附属 blob ----
        let requirements = le32(CSMAGIC_REQUIREMENTS) + le32(12) + le32(0)
        var entitlementsBlob: [UInt8]?
        if let ent = options.entitlements, !ent.isEmpty {
            var b = le32(CSMAGIC_ENTITLEMENTS) + le32(UInt32(8 + ent.count))
            b += [UInt8](ent)
            entitlementsBlob = b
        }

        // special slots（-1 Info.plist, -2 Requirements, -3/-4 空, -5 Entitlements）
        func putSpecial(_ slot: Int, _ hash: [UInt8]) {
            let pos = hashOffset - slot * 32
            guard pos >= 0, pos + 32 <= cd.count else { return }
            cd.replaceSubrange(pos..<(pos + 32), with: hash)
        }
        if let info = infoPlist, !info.isEmpty {
            putSpecial(1, [UInt8](SHA256.hash(data: info)))
        }
        putSpecial(2, [UInt8](SHA256.hash(data: Data(requirements))))
        if let ent = entitlementsBlob {
            putSpecial(5, [UInt8](SHA256.hash(data: Data(ent))))
        }

        // ---- 3. SuperBlob ----
        var blobs: [(UInt32, [UInt8])] = [(0, cd), (2, requirements)]
        if let ent = entitlementsBlob { blobs.append((5, ent)) }
        if let signer = options.signer {
            let cms = try CodeSignCMS.signatureBlob(codeDirectory: Data(cd),
                                                   signer: signer,
                                                   extraCerts: options.extraCertificates)
            blobs.append((0x10000, [UInt8](cms)))
        }

        var index: [UInt8] = []
        var body: [UInt8] = []
        var cursor = 12 + blobs.count * 8
        for (type, blob) in blobs {
            index += le32(type) + le32(UInt32(cursor))
            body += blob
            let pad = (4 - blob.count % 4) % 4
            body += [UInt8](repeating: 0, count: pad)
            cursor += blob.count + pad
        }
        var sb = le32(CSMAGIC_EMBEDDED_SIGNATURE) + le32(UInt32(cursor)) + le32(UInt32(blobs.count))
        sb += index
        sb += body

        // ---- 4. 回写 ----
        var out = Array(bytes[0..<codeLimit])
        out += sb
        let padTo16 = (16 - out.count % 16) % 16
        out += [UInt8](repeating: 0, count: padTo16)
        let sigSize = sb.count + padTo16
        w32(&out, csOff + 12, UInt32(sigSize))

        if let le = leCmd {
            let newFileSize = UInt64(out.count)
            if newFileSize > leFileOff {
                let fs = newFileSize - leFileOff
                w64(&out, le + 48, fs)                       // __LINKEDIT.filesize
                let aligned = (fs + 0x3FFF) & ~0x3FFF
                if aligned > u64(out, le + 32) {             // __LINKEDIT.vmsize
                    w64(&out, le + 32, aligned)
                }
            }
        }

        try Data(out).write(to: url)
    }

    // MARK: FAT → 单 arm64
    private static func thinBinary(_ data: Data) throws -> Data {
        let b = [UInt8](data)
        guard b.count >= 8 else { throw MachOSignError.notMachO }
        if u32(b, 0) == 0xFEEDFACF { return data }
        let be = (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        guard be == 0xCAFEBABE else { throw MachOSignError.notMachO }
        let n = Int((UInt32(b[4]) << 24) | (UInt32(b[5]) << 16) | (UInt32(b[6]) << 8) | UInt32(b[7]))
        guard n > 0, b.count >= 8 + n * 20 else { throw MachOSignError.badLayout }
        var chosen: (Int, Int)?
        var fallback: (Int, Int)?
        for i in 0..<n {
            let base = 8 + i * 20
            let cpu = (UInt32(b[base]) << 24) | (UInt32(b[base + 1]) << 16)
                | (UInt32(b[base + 2]) << 8) | UInt32(b[base + 3])
            let offset = Int((UInt32(b[base + 8]) << 24) | (UInt32(b[base + 9]) << 16)
                | (UInt32(b[base + 10]) << 8) | UInt32(b[base + 11]))
            let size = Int((UInt32(b[base + 12]) << 24) | (UInt32(b[base + 13]) << 16)
                | (UInt32(b[base + 14]) << 8) | UInt32(b[base + 15]))
            guard offset >= 0, size > 0, offset + size <= b.count else { continue }
            if cpu == 0x0100000C { chosen = (offset, size); break }   // arm64
            if cpu == 0x01000007, fallback == nil { fallback = (offset, size) } // arm64_32 / x86_64? 兜底
        }
        guard let s = chosen ?? fallback else { throw MachOSignError.noArm64Slice }
        return data.subdata(in: s.0..<(s.0 + s.1))
    }

    // MARK: 字节工具
    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
    private static func u64(_ b: [UInt8], _ o: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in (0..<8).reversed() { v = (v << 8) | UInt64(b[o + i]) }
        return v
    }
    private static func w32(_ b: inout [UInt8], _ o: Int, _ v: UInt32) {
        guard o + 4 <= b.count else { return }
        b[o] = UInt8(v & 0xFF)
        b[o + 1] = UInt8((v >> 8) & 0xFF)
        b[o + 2] = UInt8((v >> 16) & 0xFF)
        b[o + 3] = UInt8((v >> 24) & 0xFF)
    }
    private static func w64(_ b: inout [UInt8], _ o: Int, _ v: UInt64) {
        guard o + 8 <= b.count else { return }
        for i in 0..<8 { b[o + i] = UInt8((v >> (8 * UInt64(i))) & 0xFF) }
    }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}

enum MachOSignError: LocalizedError {
    case notMachO
    case noArm64Slice
    case noCodeSignatureSlot
    case badLayout

    var errorDescription: String? {
        switch self {
        case .notMachO: return "不是可执行文件（非 Mach-O）"
        case .noArm64Slice: return "二进制中没有 arm64 架构"
        case .noCodeSignatureSlot: return "二进制缺少签名段（LC_CODE_SIGNATURE），此包需先在电脑端处理"
        case .badLayout: return "二进制结构异常，无法解析"
        }
    }
}
