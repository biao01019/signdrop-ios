# Signdrop · iOS 自签名工具

按设计稿 1:1 复刻的 iOS 自签名 App（SwiftUI），支持：

- 📱 8 个完整界面：我的应用 / 应用详情 / 签名配置 / 证书 / 任务 / 设置 / 登录 / 注册
- 🖋 真实签名流水线：导入 `.ipa` → 解压 → 注入 `.mobileprovision` → 用 `.p12` 证书通过内嵌 `ldid` 重签名 → 重新打包导出
- 🔑 证书管理：导入 `.p12`（Keychain 保存密码）与 `.mobileprovision`，Bundle ID 自动对齐描述文件
- 🔐 登录 / 注册（本地账号，通过 Sign in with Apple 亦可）

## 签名原理

1. 从「证书」页导入 `.p12`（输入导出密码）和 `.mobileprovision`
2. 从「我的应用」右下角 ➕ 选择要签名的 `.ipa`
3. App 自动完成：解压 → 读取描述文件中的 Entitlements / TeamID → 覆盖 `embedded.mobileprovision` → 调整 `CFBundleIdentifier` → 用内嵌 ldid 对主二进制、所有 Frameworks、PlugIns 重签名 → 重新 zip
4. 签名后的 IPA 输出到 App 沙盒 `Documents/Signed/`，可在「文件」App 中取出，随后安装到设备（7 天有效期，到期可一键重签）

## 构建 IPA

推送即触发 GitHub Actions（macOS runner）：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -scheme Signdrop -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
# 打包 Payload → Signdrop.ipa
```

产物：
- Actions Artifact `Signdrop-ipa`
- Release `v1.2.0` 附带 `Signdrop.ipa`

> 本仓库产出的 IPA 为**未签名**状态，安装时用你自己的 Apple ID 通过 Sideloadly / AltStore / iMazing 做一次设备签名（免费 Apple ID 有效期 7 天）；之后即可在 Signdrop 内对任意 IPA 完成 7 天自签循环。
