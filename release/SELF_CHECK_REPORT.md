# WaitCam 48h MVP 自检与真机调试报告

> 生成时间：2026-11-16 · 工程根目录：`/Users/wang/OPC/projects/waitcam`

## 一、实测验证结论（均在最终编辑后实跑通过）

1. **iOS 18+ 模拟器编译与全量单元测试（`iPhone 18 Pro`, `iphonesimulator27.2`）**
   - 执行命令：`xcodebuild test -project /Users/wang/OPC/projects/waitcam/WaitCam.xcodeproj -scheme WaitCam -destination 'platform=iOS Simulator,id=15A596B0-664F-4DE4-B7E8-38F9CEAF9C32' CODE_SIGNING_ALLOWED=NO`
   - 实测结果：**`** TEST SUCCEEDED **`（6/6 用例全部通过，0 失败，耗时 0.355s）**：
     - `testASOMetadataCompliesWithAppStoreLimits`：校验中英文标题 ≤30 字符、副标题 ≤30 字符、关键词 ≤100 字符且完整包含指定热词。
     - `testDarkroomVaultEncryptsShotsBlocksEarlyRevealAndPersistsAcrossReload`：验证 AES-256-GCM 沙盒密文非明文 JPEG、11:59:59 时拒绝解密、重启重载零丢片、满 12 小时后无损解密还原。
     - `testFilmLabRendersAllStocksAndContactSheetToValidJPEG`：验证 `party2AM`、`tungsten800T`、`chrome100`、`clubMono400` 滤镜、日期印记及 35mm 接触印相单均输出有效 sRGB JPEG（无水印）。
     - `testFreeTierAndOneTimePaywallEntitlementFlow`：验证免费版单卷 12h 畅拍、多卷并行/6h·24h 自定义时间/Pro 胶卷付费墙触发，以及 ¥6 (`darkroom.plus`) 与 ¥12 (`pro.lifetime`) 权益升级。
     - `testLiveActivityStateFormattingAndProgress`：验证灵动岛倒计时格式化（如 `11:42:18`）与进度条比例计算。
     - `testStoreKitConfigurationLoadsProductsWithoutSubscriptions`：使用 `SKTestSession` 加载 `WaitCam.storekit`，确认零订阅组（`subscriptionGroups.isEmpty`），并通过真实 StoreKit 2 `Product.products(for:)` 与 `lifetime.purchase()` 完成本地交易签名验证。

2. **iOS 真机 `arm64` Release 构建与商店合规自检（`iphoneos27.2`）**
   - 执行命令：`xcodebuild build -project /Users/wang/OPC/projects/waitcam/WaitCam.xcodeproj -scheme WaitCam -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
   - 实测结果：**`** BUILD SUCCEEDED **`，且 `builtin-validationUtility ... -validate-for-store` **0 警告通过**。
   - 嵌入式插件核验：`WaitCam.app/PlugIns/WaitCamWidgets.appex` 已正确嵌入，内部包含 `Info.plist`、`PrivacyInfo.xcprivacy` 与 `WaitCamWidgets` arm64 可执行文件。
   - AppIcon 核验：`Resources/Assets.xcassets/AppIcon.appiconset/icon-ios-1024.png` 实测 `1024×1024` 且 `hasAlpha: no`（24-bit 纯 RGB）。

---

## 二、真机一步编译测试指引

1. 在 Xcode 打开 `/Users/wang/OPC/projects/waitcam/WaitCam.xcodeproj`（当前已预设个人团队 `DEVELOPMENT_TEAM = KU364788TC`、Automatic Signing 与 Scheme 关联的 `Config/WaitCam.storekit`）。
2. 数据线连接实体 iPhone，选择顶部目标设备为真机，按 `Cmd + R` 运行：
   - **真机拍摄 & 强闪光**：首页默认开启 `闪光 ON` 与免费 `2AM 派对闪光卷`，拍照后左下角立即显示精确倒计时（默认 12 小时）并同步至灵动岛与锁屏组件。
   - **30 秒完整闭环快速验收（无需苦等 12 小时）**：点击右上角「实验室设置」或进入「暗房保险箱」右上角点 **`30s 实测卷`**，系统会立刻生成 3 张加密样片并启动 30 秒灵动岛倒计时 -> 30 秒后弹出本地通知 -> 点击直达暗房一键批量存入系统相册。
   - **StoreKit 2 买断闭环**：点选 `6H / 24H`、`+ 装新卷` 或 `800T` 胶卷即可调起非订阅买断页，在真机调试环境直接走通 `$0.99 / ¥6` 与 `$1.99 / ¥12` 本地 StoreKit 2 买断及恢复购买。

---

## 三、待上架前最后 2 项外部动作（不在本机纯工程范围）

1. 将 `/Users/wang/OPC/projects/waitcam/docs/`（`privacy.html`、`terms.html`、`support.html`、`index.html`）推送至 GitHub Pages 仓库 `a3152557994-ship-it/waitcam`，使预设 URL 生效。
2. 在 App Store Connect 后台创建 `com.yanghe.waitcam` 与 `com.yanghe.waitcam.widgets` 两个 Bundle ID、配置 `Non-Consumable` 商品（ID 见 `release/ASC_METADATA_READY.json`）后即可 Archive 提审。
