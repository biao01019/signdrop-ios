import SwiftUI
import AuthenticationServices

// MARK: - ⑦ 登录
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State var email = "quantum@icloud.com"
    @State var password = "signdrop123"
    @State var showPassword = false
    @State var showRegister = false
    @State var loading = false
    @State var errorText: String?
    @State var show2FA = false
    @State var code = ""
    @State var codeError: String?

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 140)

                    // App 图标
                    RoundedRectangle(cornerRadius: 22)
                        .fill(LinearGradient(colors: [Color(hex: 0x7B61FF), Color(hex: 0x5A48E8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                        )
                        .shadow(color: Color(hex: 0x7B61FF).opacity(0.35), radius: 16, y: 8)
                        .padding(.bottom, 28)

                    Text("欢迎回来")
                        .font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        .padding(.bottom, 10)
                    Text("登录后可跨设备同步证书与签名记录")
                        .font(.system(size: 15)).foregroundColor(.sub)
                        .padding(.bottom, 32)

                    // 输入卡片
                    Card {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "envelope")
                                    .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                TextField("邮箱", text: $email)
                                    .font(.system(size: 16)).foregroundColor(.ink)
                                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                            }.frame(height: 56)
                            Divider().background(Color.divider)
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                if showPassword {
                                    TextField("密码", text: $password)
                                        .font(.system(size: 16)).foregroundColor(.ink)
                                } else {
                                    SecureField("密码", text: $password)
                                        .font(.system(size: 16)).foregroundColor(.ink)
                                }
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                }
                            }.frame(height: 56)
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.bottom, 14)

                    HStack {
                        Spacer()
                        Button("忘记密码?") {}
                            .font(.system(size: 14)).foregroundColor(.sdBlue)
                    }
                    .padding(.bottom, 24)

                    // 登录按钮
                    PrimaryButton(title: loading ? "正在登录…" : "登录") { login() }
                    if let e = errorText {
                        Text(e)
                            .font(.system(size: 12))
                            .foregroundColor(.sdRed)
                            .padding(.top, 10)
                    }
                    HStack {
                        Rectangle().fill(Color.divider).frame(height: 1)
                        Text("或使用").font(.system(size: 13)).foregroundColor(.faint).padding(.horizontal, 14)
                        Rectangle().fill(Color.divider).frame(height: 1)
                    }
                    .padding(.vertical, 22)

                    // Apple 登录
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { _ in login() }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .cornerRadius(20)
                    .padding(.bottom, 24)

                    // 三大承诺
                    Card {
                        HStack(spacing: 0) {
                            featureCol("checkmark.shield.fill", "本地签名")
                            Rectangle().fill(Color.divider).frame(width: 1, height: 44)
                            featureCol("lock.fill", "私钥不上传")
                            Rectangle().fill(Color.divider).frame(width: 1, height: 44)
                            featureCol("arrow.right.to.line", "随时可退出")
                        }
                        .padding(.vertical, 16)
                    }
                    .padding(.bottom, 30)

                    HStack(spacing: 6) {
                        Text("还没有账号？").font(.system(size: 14)).foregroundColor(.sub)
                        Button("立即注册") { showRegister = true }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.sdBlue)
                    }
                    .frame(maxWidth: .infinity)

                    Button("暂时跳过，先用导入证书签名") { skipLogin() }
                        .font(.system(size: 13))
                        .foregroundColor(.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $showRegister) { RegisterView().environmentObject(app) }
        .sheet(isPresented: $show2FA) { twoFactorSheet }
    }

    private var twoFactorSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xE4E6EC)).frame(width: 36, height: 5).padding(.top, 8)
            VStack(alignment: .leading, spacing: 0) {
                Text("双重认证")
                    .font(.system(size: 24, weight: .bold)).foregroundColor(.ink)
                    .padding(.top, 26)
                Text("输入受信任设备上显示的 6 位验证码")
                    .font(.system(size: 14)).foregroundColor(.sub)
                    .padding(.top, 8).padding(.bottom, 22)

                Card {
                    TextField("000000", text: $code)
                        .font(.system(size: 26, weight: .semibold, design: .monospaced))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .frame(height: 64)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 12)

                if let e = codeError {
                    Text(e).font(.system(size: 12)).foregroundColor(.sdRed)
                        .padding(.bottom, 8)
                }

                PrimaryButton(title: loading ? "验证中…" : "验证") { submitCode() }
                    .padding(.top, 6)
                Button("取消") {
                    show2FA = false
                    code = ""
                }
                .font(.system(size: 15))
                .foregroundColor(.sub)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .padding(.horizontal, 20)
            Spacer()
        }
        .background(Color.bg.ignoresSafeArea())
        .presentationDetents([.height(400)])
    }

    private func featureCol(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18)).foregroundColor(.sdBlue)
            Text(title).font(.system(size: 13)).foregroundColor(.ink)
        }
        .frame(maxWidth: .infinity)
    }

    private func login() {
        guard !email.isEmpty, password.count >= 4 else {
            errorText = "请输入 Apple ID 与密码"
            return
        }
        loading = true
        errorText = nil
        Task {
            do {
                let result = try await AppleIDService.shared.signIn(username: email, password: password)
                await MainActor.run {
                    loading = false
                    switch result {
                    case .success:
                        completeLogin()
                    case .needs2FA:
                        show2FA = true
                    case .needsSMS(let phone):
                        errorText = "需要短信验证：\(phone)"
                        show2FA = true
                    }
                }
            } catch {
                await MainActor.run {
                    loading = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func submitCode() {
        guard code.count == 6 else { codeError = "请输入 6 位验证码"; return }
        codeError = nil
        loading = true
        Task {
            do {
                _ = try await AppleIDService.shared.submit2FACode(code)
                await MainActor.run {
                    loading = false
                    show2FA = false
                    completeLogin()
                }
            } catch {
                await MainActor.run {
                    loading = false
                    codeError = error.localizedDescription
                }
            }
        }
    }

    private func completeLogin() {
        app.account = email
        app.isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "sd_logged_in")
        UserDefaults.standard.set(email, forKey: "sd_account")
        app.showLogin = false
    }

    private func skipLogin() {
        UserDefaults.standard.set(true, forKey: "sd_skipped_login")
        app.showLogin = false
    }
}

// MARK: - ⑧ 创建账号
struct RegisterView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    @State var email = ""
    @State var code = ""
    @State var password = ""
    @State var showPassword = false
    @State var agreed = true
    @State var countdown = 0
    @State var sendTimer: Timer? = nil

    var strength: Int {
        var s = 0
        if password.count >= 8 { s += 1 }
        if password.range(of: "[A-Z]") != nil { s += 1 }
        if password.range(of: "[0-9]") != nil { s += 1 }
        if password.range(of: "[^A-Za-z0-9]") != nil { s += 1 }
        return min(3, max(1, s))
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusBarSpacer()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        CircleBtn("chevron.left").onTapGesture { dismiss() }
                        Spacer()
                        Text("创建账号").font(.system(size: 17, weight: .bold)).foregroundColor(.ink)
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.bottom, 64)

                    Text("用邮箱注册")
                        .font(.system(size: 34, weight: .bold)).foregroundColor(.ink)
                        .padding(.bottom, 10)
                    Text("仅同步证书状态，私钥始终保存在本机")
                        .font(.system(size: 15)).foregroundColor(.sub)
                        .padding(.bottom, 28)

                    Card {
                        VStack(spacing: 0) {
                            fieldRow(icon: "envelope", placeholder: "输入邮箱地址",
                                     text: $email, keyboard: .emailAddress)
                            Divider().background(Color.divider).padding(.leading, 46)
                            HStack(spacing: 12) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                TextField("6 位验证码", text: $code)
                                    .font(.system(size: 16)).keyboardType(.numberPad)
                                Button {
                                    sendCode()
                                } label: {
                                    Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                                        .font(.system(size: 13, weight: .medium)).foregroundColor(.sdBlue)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.iconSq).cornerRadius(9)
                                }
                                .disabled(countdown > 0)
                            }
                            .frame(height: 56)
                            Divider().background(Color.divider).padding(.leading, 46)
                            HStack(spacing: 12) {
                                Image(systemName: "lock")
                                    .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                Group {
                                    if showPassword { TextField("设置密码（至少 8 位）", text: $password) }
                                    else { SecureField("设置密码（至少 8 位）", text: $password) }
                                }
                                .font(.system(size: 16))
                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
                                }
                            }
                            .frame(height: 56)
                            // 强度条
                            HStack(spacing: 8) {
                                ForEach(0..<4, id: \.self) { i in
                                    Capsule()
                                        .fill(i < strength ? Color.sdGreen : Color.track)
                                        .frame(height: 4)
                                }
                                Text(strengthLabel)
                                    .font(.system(size: 13)).foregroundColor(.sub)
                            }
                            .padding(.bottom, 16)
                        }
                        .padding(.horizontal, 18).padding(.top, 8)
                    }
                    .padding(.bottom, 18)

                    // 权益说明
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            benefitRow("同步证书到期状态（不含私钥）")
                            benefitRow("多设备共用签名记录")
                            benefitRow("随时导出或删除账号数据")
                        }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    .padding(.bottom, 24)

                    // 同意协议
                    HStack(spacing: 10) {
                        Button {
                            agreed.toggle()
                        } label: {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20)).foregroundColor(agreed ? .sdBlue : Color(hex: 0xC4C9D4))
                        }
                        Text("我已阅读并同意").font(.system(size: 14)).foregroundColor(.sub)
                        Text("《用户协议》").font(.system(size: 14)).foregroundColor(.sdBlue)
                        Text("《隐私政策》").font(.system(size: 14)).foregroundColor(.sdBlue)
                        Spacer()
                    }
                    .padding(.bottom, 22)

                    PrimaryButton(title: "注册并登录") { register() }

                    HStack(spacing: 6) {
                        Text("已有账号？").font(.system(size: 14)).foregroundColor(.sub)
                        Button("去登录") { dismiss() }
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(.sdBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(Color.bg.ignoresSafeArea())
    }

    private var strengthLabel: String {
        switch strength {
        case 1: return "较弱"
        case 2: return "一般"
        case 3: return "较强"
        default: return "较强"
        }
    }

    private func fieldRow(icon: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(Color(hex: 0xB0B6C2))
            TextField(placeholder, text: text)
                .font(.system(size: 16)).keyboardType(keyboard)
                .textInputAutocapitalization(.never)
        }
        .frame(height: 56)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17)).foregroundColor(.sdBlue)
            Text(text).font(.system(size: 14)).foregroundColor(.ink)
            Spacer()
        }
        .frame(height: 40)
    }

    private func sendCode() {
        guard email.contains("@") else { return }
        countdown = 60
        sendTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            countdown -= 1
            if countdown <= 0 { sendTimer?.invalidate(); sendTimer = nil }
        }
    }

    private func register() {
        guard agreed, email.contains("@"), password.count >= 8 else { return }
        app.account = email
        app.isLoggedIn = true
        UserDefaults.standard.set(true, forKey: "sd_logged_in")
        UserDefaults.standard.set(email, forKey: "sd_account")
        app.showLogin = false
    }
}
