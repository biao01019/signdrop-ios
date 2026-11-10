import Foundation
import CryptoKit
import BigInt

/// SRP-6a（RFC 5054 2048-bit 群），Apple ID 登录握手用
struct SRPClient {

    static let N = BigUInt("AC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC3192943DB56050A37329CBB4A099ED8193E0757767A13DD52312AB4B03310DCD7F48A9DA04FD50E8083969EDB767B0CF6095179A163AB3661A05FBD5FAAAE82918A9962F0B93B855F97993EC975EEAA80D740ADBF4FF747359D041D5C33EA71D281E446B14773BCA97B43A23FB801676BD207A436C6481F1D2B9078717461A5B9D32E688F87748544523B524B0D57D5EA77A2775D2ECFA032CFBDBF52FB3786160279004E57AE6AF874E7303CE53299CCC041C7BC308D82A5698F3A8D0C38271AE35F8E9DBFBB694B5C803D89F7AE435DE236D525F54759B65E372FCD68EF20FA7111F9E4AFF73", radix: 16)!

    static let g = BigUInt(2)
    static let width = 384

    let username: String
    let password: String
    private let a: BigUInt
    let A: BigUInt

    init(username: String, password: String) {
        self.username = username
        self.password = password
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        let secret = BigUInt(Data(bytes))
        self.a = secret
        self.A = Self.g.power(secret, modulus: Self.N)
    }

    static func pad(_ n: BigUInt) -> Data {
        let raw = n.serialize()
        if raw.count >= width { return raw }
        return Data(repeating: 0, count: width - raw.count) + raw
    }

    /// 计算 M1 / M2 / K
    func computeProofs(B: BigUInt, salt: Data) throws -> (m1: Data, m2: Data, k: Data) {
        let nBytes = Self.pad(Self.N)
        let gBytes = Self.pad(Self.g)
        let k = BigUInt(Data(SHA256.hash(data: nBytes + gBytes)))

        let upHash = Data(SHA256.hash(data: Data("\(username):\(password)".utf8)))
        let x = BigUInt(Data(SHA256.hash(data: salt + upHash)))

        let u = BigUInt(Data(SHA256.hash(data: Self.pad(A) + Self.pad(B))))

        let v = Self.g.power(x, modulus: Self.N)
        let kgx = (k * v) % Self.N
        // B - kgx (mod N)
        let base = (B + Self.N - (kgx % Self.N)) % Self.N
        let exponent = a + u * x
        let s = base.power(exponent, modulus: Self.N)
        let key = Data(SHA256.hash(data: Self.pad(s)))

        let hN = Data(SHA256.hash(data: nBytes))
        let hg = Data(SHA256.hash(data: gBytes))
        var xor = Data(capacity: hN.count)
        for i in 0..<min(hN.count, hg.count) { xor.append(hN[i] ^ hg[i]) }
        let hU = Data(SHA256.hash(data: Data(username.utf8)))

        var buf = Data()
        buf.append(xor)
        buf.append(hU)
        buf.append(salt)
        buf.append(Self.pad(A))
        buf.append(Self.pad(B))
        buf.append(key)
        let m1 = Data(SHA256.hash(data: buf))

        var buf2 = Data()
        buf2.append(Self.pad(A))
        buf2.append(m1)
        buf2.append(key)
        let m2 = Data(SHA256.hash(data: buf2))

        return (m1, m2, key)
    }

    var aBase64: String { Data(Self.pad(A)).base64EncodedString() }
}
