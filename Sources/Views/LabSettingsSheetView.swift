import SwiftUI

public struct LabSettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WaitCamViewModel

    public init(viewModel: WaitCamViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section(WCL10n.pick(zh: "复古日期印记 Date Stamp", en: "Quartz Date Stamp")) {
                    ForEach(DateStampStyle.allCases) { style in
                        let locked = style.requiresLifetimePro && !viewModel.storeKit.hasFullPro
                        Button {
                            viewModel.selectDateStampStyle(style)
                        } label: {
                            HStack {
                                Text(style.displayName)
                                    .foregroundStyle(.white)
                                Spacer()
                                if viewModel.selectedDateStamp == style {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.orange)
                                } else if locked {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }

                Section(WCL10n.pick(zh: "30 秒暗房快速体验卷", en: "30-Second Quick Demo Roll")) {
                    Button {
                        Task { await viewModel.create30SecondCalibrationRoll() }
                    } label: {
                        Label(
                            WCL10n.pick(zh: "装入 30 秒极速实测样片卷（3 张）", en: "Load 30s Demo Film Roll (3 Shots)"),
                            systemImage: "bolt.ring.closed"
                        )
                        .foregroundStyle(.orange)
                    }
                    Text(
                        WCL10n.pick(
                            zh: "立即体验「加密锁定 -> 灵动岛倒计时 -> 到点通知 -> 生成 35mm 短片与存相册」完整仪式。",
                            en: "Preview the full 'Encrypted Lock -> Dynamic Island Countdown -> Notification -> 35mm Reel Export' loop in 30 seconds."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section(WCL10n.pick(zh: "会员与买断权益", en: "WaitCam Pro Access")) {
                    HStack {
                        Text(WCL10n.pick(zh: "当前状态", en: "Current Plan"))
                        Spacer()
                        if viewModel.storeKit.hasProLifetime {
                            Text(WCL10n.pick(zh: "Pro 终身买断版", en: "Pro Lifetime")).foregroundStyle(.green)
                        } else if viewModel.storeKit.hasActiveAnnualSubscription {
                            Text(WCL10n.pick(zh: "Pro 年度会员", en: "Pro Yearly")).foregroundStyle(.green)
                        } else if viewModel.storeKit.canUseParallelRollsAndCustomTimer {
                            Text(WCL10n.pick(zh: "轻量暗房扩容版", en: "Darkroom Plus")).foregroundStyle(.cyan)
                        } else {
                            Text(WCL10n.pick(zh: "免费版（2AM 卷无水印）", en: "Free (2AM Flash Roll)")).foregroundStyle(.secondary)
                        }
                    }

                    if !viewModel.storeKit.hasFullPro {
                        Button(WCL10n.pick(zh: "免费试用 3 天 Pro 或查看黑五终身买断", en: "Start 3-Day Free Trial or Lifetime Pass")) {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                viewModel.activePaywall = .manualUpgrade
                            }
                        }
                        .foregroundStyle(.orange)
                    }

                    Button(WCL10n.pick(zh: "恢复购买 Restore Purchases", en: "Restore Purchases")) {
                        Task { await viewModel.storeKit.restorePurchases() }
                    }
                }

                Section(WCL10n.pick(zh: "100% 本地暗房与隐私", en: "100% On-Device Privacy")) {
                    Label(WCL10n.pick(zh: "零云端服务器 · CoreImage 本地实时显影", en: "Zero Cloud Servers · On-Device CoreImage Lab"), systemImage: "cpu")
                    Label(WCL10n.pick(zh: "暗房期间 AES-256 沙盒加密保存防丢片", en: "AES-256 Encrypted Darkroom Vault"), systemImage: "lock.shield")
                    Link(WCL10n.pick(zh: "隐私政策 Privacy Policy", en: "Privacy Policy"), destination: URL(string: "https://a3152557994-ship-it.github.io/waitcam/privacy.html")!)
                    Link(WCL10n.pick(zh: "使用条款 Terms of Use (EULA)", en: "Terms of Use (EULA)"), destination: URL(string: "https://a3152557994-ship-it.github.io/waitcam/terms.html")!)
                    Link(WCL10n.pick(zh: "技术支持 Support", en: "Support"), destination: URL(string: "https://a3152557994-ship-it.github.io/waitcam/support.html")!)
                }
            }
            .navigationTitle(WCL10n.pick(zh: "暗房与胶片设置", en: "Darkroom Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(WCL10n.pick(zh: "完成", en: "Done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
