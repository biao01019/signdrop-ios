import Foundation
import SwiftUI

// MARK: - 数据模型
struct SignedApp: Identifiable {
    var id = UUID()
    var name: String
    var version: String
    var build: String
    var sizeMB: Double
    var category: String
    var bundleID: String
    var gradient: (UInt32, UInt32)
    var glyph: String
    var daysLeft: Int?
    var expiredDays: Int = 0
    var badge: BadgeKind = .none
    var signedAt: Date?
    var expireAt: Date?
    var certName: String = "个人开发者证书"
    var fileName: String = ""
    var history: [SignRecord] = []

    enum BadgeKind { case none, soon, resign }
}

struct SignRecord: Identifiable {
    var id = UUID()
    var title: String
    var ok: Bool
    var detail: String
    var date: Date
}

struct CertInfo: Identifiable {
    var id = UUID()
    var name: String
    var team: String
    var kind: String // Apple ID / 企业分发
    var expire: Date
    var daysLeft: Int
    var progress: Double
    var isDefault: Bool
    var isEnterprise: Bool = false
}

struct DeviceInfo: Identifiable {
    var id = UUID()
    var name: String
    var udid: String
    var active: Bool
}

enum SignStep: Int, CaseIterable {
    case unzip, verify, resign, pack
    var title: String {
        switch self {
        case .unzip: return "解压 IPA 安装包"
        case .verify: return "校验描述文件"
        case .resign: return "使用证书重签名"
        case .pack: return "打包并安装到设备"
        }
    }
}

// MARK: - 全局状态
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isLoggedIn: Bool = UserDefaults.standard.bool(forKey: "sd_logged_in")
    @Published var account: String = UserDefaults.standard.string(forKey: "sd_account") ?? ""
    @Published var tab: Int = 0
    @Published var showLogin: Bool = !UserDefaults.standard.bool(forKey: "sd_logged_in")

    @Published var apps: [SignedApp] = [
        .init(name: "Quantum Notes", version: "2.4.1", build: "156", sizeMB: 24.6, category: "效率",
              bundleID: "com.quantum.notes", gradient: (0x6A5AF9, 0x2C7BF6), glyph: "text.alignleft",
              daysLeft: 87, badge: .none, signedAt: date("2026-08-10"), expireAt: date("2026-12-05"),
              fileName: "QuantumNotes.ipa",
              history: [
                  .init(title: "重新签名 · 成功", ok: true, detail: "更新至 v2.4.1 · 证书 8F2K9D", date: date("2026-10-12")),
                  .init(title: "首次签名 · 成功", ok: true, detail: "导入 IPA 并安装到设备", date: date("2026-08-10")),
                  .init(title: "更新签名 · 失败", ok: false, detail: "证书已过期 · 需重新签名", date: date("2026-07-28")),
              ]),
        .init(name: "Muse Player", version: "1.8.0", build: "102", sizeMB: 51.2, category: "影音",
              bundleID: "com.muse.player", gradient: (0xFF5E7E, 0xFF9A6B), glyph: "play.fill",
              daysLeft: 21, badge: .soon),
        .init(name: "Grid Wallet", version: "3.0.2", build: "210", sizeMB: 38.9, category: "财务",
              bundleID: "com.grid.wallet", gradient: (0x00C6A2, 0x0AB5C9), glyph: "square.grid.2x2.fill",
              daysLeft: 0, expiredDays: 2, badge: .resign),
        .init(name: "Lumen Reader", version: "5.1.4", build: "331", sizeMB: 17.4, category: "阅读",
              bundleID: "com.lumen.reader", gradient: (0xFFA43B, 0xFF7B54), glyph: "book.fill",
              daysLeft: 87),
        .init(name: "Aurora Calc", version: "1.2.3", build: "77", sizeMB: 9.8, category: "工具",
              bundleID: "com.aurora.calc", gradient: (0x34D876, 0x0EB25B), glyph: "calculator.fill",
              daysLeft: 45),
    ]

    @Published var certs: [CertInfo] = [
        .init(name: "个人开发者证书", team: "8F2K9D", kind: "Apple ID", expire: date("2027-03-12"),
              daysLeft: 123, progress: 0.6, isDefault: true),
        .init(name: "企业证书 · In-House", team: "QK72LM", kind: "企业分发", expire: date("2026-11-15"),
              daysLeft: 6, progress: 0.08, isDefault: false, isEnterprise: true),
    ]

    @Published var devices: [DeviceInfo] = [
        .init(name: "iPhone 15 Pro", udid: "00008101-000A000A...8F3A", active: true),
        .init(name: "iPad Air", udid: "00008102-000B000B...B21C", active: true),
    ]

    @Published var currentTask: SignTaskModel? = nil

    struct SignTaskModel: Identifiable {
        var id = UUID()
        var fileName: String
        var sizeMB: Double
        var progress: Double
        var step: SignStep
        var targetDevice: String
        var certName: String
        var startTime: Date
        var running: Bool
    }
}

func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: s) ?? Date()
}

func cnDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "yyyy年M月d日"
    return f.string(from: d)
}

func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "M月d日"
    return f.string(from: d)
}
