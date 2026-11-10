import SwiftUI

// MARK: - 设计稿配色（1:1 提取）
extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static let bg = Color(hex: 0xF2F3F7)          // 页面背景
    static let card = Color.white                       // 卡片
    static let sdBlue = Color(hex: 0x147AFF)     // 主蓝
    static let ink = Color(hex: 0x17181C)         // 主文字
    static let sub = Color(hex: 0x8A909C)         // 次级文字
    static let faint = Color(hex: 0xAAB0BB)       // 更弱文字
    static let divider = Color(hex: 0xF0F1F5)     // 分割线
    static let track = Color(hex: 0xE9EBF0)       // 进度条轨道
    static let iconSq = Color(hex: 0xEAF3FF)      // 浅蓝图标底
    static let circleBtn = Color(hex: 0xEDEEF3)   // 圆形按钮底

    static let sdGreen = Color(hex: 0x30C759)
    static let greenBg = Color(hex: 0xE7F7EC)
    static let sdOrange = Color(hex: 0xF5A623)
    static let orangeBg = Color(hex: 0xFDF3E1)
    static let sdRed = Color(hex: 0xFF4D4A)
    static let redBg = Color(hex: 0xFDECEC)
    static let warnBg = Color(hex: 0xFFF8E1)
}

// MARK: - 卡片
struct Card<Content: View>: View {
    var corner: CGFloat = 20
    let content: Content
    init(corner: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.corner = corner
        self.content = content()
    }
    var body: some View {
        content
            .background(Color.card)
            .cornerRadius(corner)
    }
}

// MARK: - 章节标题（灰底小字，左右布局）
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(title).font(.system(size: 14)).foregroundColor(Color.sub)
            Spacer()
            if let t = trailing {
                Text(t).font(.system(size: 14)).foregroundColor(Color.sub)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 胶囊徽章
struct Badge: View {
    enum Style { case green, orange, red, blue }
    let text: String
    var style: Style = .green
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg)
            .cornerRadius(9)
    }
    private var fg: Color {
        switch style {
        case .green: return .sdGreen
        case .orange: return .sdOrange
        case .red: return .sdRed
        case .blue: return .sdBlue
        }
    }
    private var bg: Color {
        switch style {
        case .green: return .greenBg
        case .orange: return .orangeBg
        case .red: return .redBg
        case .blue: return .iconSq
        }
    }
}

// MARK: - 圆角方形图标底 + SF Symbol
struct IconSquare: View {
    let systemName: String
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var bg: Color = .iconSq
    var fg: Color = .sdBlue
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .fill(bg)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundColor(fg)
            )
    }
}

// MARK: - 主按钮（大蓝按钮）
struct PrimaryButton: View {
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.sdBlue)
                .cornerRadius(20)
        }
    }
}

// MARK: - 进度条
struct ProgressBar: View {
    var value: Double // 0...1
    var color: Color = .sdBlue
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.track)
                Capsule().fill(color).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - 渐变 App 图标
struct AppIcon: View {
    var size: CGFloat = 52
    var corner: CGFloat = 14
    var gradient: Gradient
    var glyph: String // SF Symbol，白色
    var body: some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(LinearGradient(colors: gradient.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - 浮动 TabBar（胶囊）
struct FloatingTabBar: View {
    @Binding var selection: Int
    let items: [(icon: String, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let active = selection == i
                Button {
                    withAnimation(.spring(response: 0.3)) { selection = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(items[i].title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(active ? .white : Color.sub)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 29)
                            .fill(active ? Color.sdBlue : .clear)
                            .padding(4)
                    )
                }
            }
        }
        .padding(2)
        .background(
            Capsule().fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
        )
    }
}

// MARK: - Home indicator
struct HomeIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.black)
            .frame(width: 134, height: 5)
            .padding(.bottom, 8)
    }
}

// MARK: - 状态栏占位
struct StatusBarSpacer: View {
    var body: some View {
        Color.clear.frame(height: 54)
    }
}
