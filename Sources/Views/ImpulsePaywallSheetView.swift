import SwiftUI

public struct ImpulsePaywallSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var storeKit: StoreKitManager
    public let reason: PaywallTriggerReason

    @State private var selectedProduct: WaitCamProduct = .proAnnual
    @State private var showLiteAbandonOffer: Bool = false

    public init(storeKit: StoreKitManager, reason: PaywallTriggerReason) {
        self.storeKit = storeKit
        self.reason = reason
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                headerBar
                if selectedProduct == .proAnnual {
                    trialTimelineCard
                } else {
                    lifetimeGuaranteeBadge
                }
                productCards
                ctaSection
                complianceFooter
            }
            .padding(20)
        }
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            await storeKit.loadProducts()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    WCL10n.pick(zh: "WAITCAM PRO 暗房特权", en: "WAITCAM PRO DARKROOM"),
                    systemImage: "film.stack.fill"
                )
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.16), in: Capsule())

                Text(reason.headline)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(reason.subheadline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .accessibilityLabel(WCL10n.pick(zh: "关闭", en: "Close"))
        }
    }

    /// Anti-1★ Dispo Scam Fix: Transparent 3-day free trial timeline with Day-2 notification guarantee
    private var trialTimelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            timelineRow(
                icon: "lock.open.fill",
                color: .green,
                title: WCL10n.pick(zh: "今天：¥0 免费解锁全部功能", en: "Today: $0 Instant Full Unlock"),
                desc: WCL10n.pick(zh: "立即畅拍 800T 霓虹、Chrome 100、无限并行卷与 6h 速冲", en: "Shoot 800T Halation, Chrome 100, parallel rolls & 6h fast reveal")
            )
            timelineRow(
                icon: "bell.badge.fill",
                color: .orange,
                title: WCL10n.pick(zh: "第 2 天：自动响铃提醒到期", en: "Day 2: Automatic Trial Reminder"),
                desc: WCL10n.pick(zh: "扣款前 24 小时发送本地通知提醒，绝无悄悄扣费套路", en: "We notify you 24 hours before trial ends—zero surprise charges")
            )
            timelineRow(
                icon: "checkmark.seal.fill",
                color: .cyan,
                title: WCL10n.pick(zh: "第 3 天：开始年度会员（随时一键取消）", en: "Day 3: Yearly Plan Starts (Cancel Anytime)"),
                desc: WCL10n.pick(zh: "不满意在系统设置点一下即可取消，不花一分冤枉钱", en: "Cancel in 1 tap in iOS Settings before Day 3 to pay $0.00")
            )
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
    }

    private func timelineRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
    }

    private var lifetimeGuaranteeBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.green)
            Text(
                WCL10n.pick(
                    zh: "黑五限时特惠：一次付清永久买断，零后续自动扣费，支持家人共享",
                    en: "Black Friday Special: One-time payment, zero recurring fees, Family Sharing included"
                )
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.38), lineWidth: 1)
        }
    }

    private var productCards: some View {
        VStack(spacing: 10) {
            productCard(.proAnnual)
            productCard(.proLifetime)
            if showLiteAbandonOffer {
                productCard(.darkroomPlus)
            }
        }
    }

    private func productCard(_ item: WaitCamProduct) -> some View {
        let selected = selectedProduct == item
        let accent: Color = {
            switch item {
            case .proAnnual: return Color(red: 1.0, green: 0.50, blue: 0.16)
            case .proLifetime: return Color.green
            case .darkroomPlus: return Color.cyan
            }
        }()

        return Button {
            selectedProduct = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? accent : .white.opacity(0.45))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(item.shortTitle)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        Text(item.badgeText)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent, in: Capsule())
                    }
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(storeKit.displayPrice(for: item))
                        .font(.headline.monospacedDigit().weight(.heavy))
                        .foregroundStyle(accent)
                    Text(item.billingNote)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
            .padding(13)
            .background(
                selected ? accent.opacity(0.14) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? accent : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var ctaButtonTitle: String {
        switch selectedProduct {
        case .proAnnual:
            return WCL10n.pick(
                zh: "0 元开启 3 天免费试用（之后 \(storeKit.displayPrice(for: .proAnnual))/年）",
                en: "Start 3-Day Free Trial (then \(storeKit.displayPrice(for: .proAnnual))/yr)"
            )
        case .proLifetime:
            return WCL10n.pick(
                zh: "一次买断永久解锁 — \(storeKit.displayPrice(for: .proLifetime))",
                en: "Unlock Lifetime Forever — \(storeKit.displayPrice(for: .proLifetime))"
            )
        case .darkroomPlus:
            return WCL10n.pick(
                zh: "解锁轻量扩容包 — \(storeKit.displayPrice(for: .darkroomPlus))",
                en: "Unlock Darkroom Plus — \(storeKit.displayPrice(for: .darkroomPlus))"
            )
        }
    }

    private var ctaSection: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    let ok = await storeKit.purchase(selectedProduct)
                    if ok {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if storeKit.isPurchasing {
                        ProgressView().tint(.black)
                    }
                    Text(ctaButtonTitle)
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 1.0, green: 0.48, blue: 0.17))
            .foregroundStyle(.black)
            .disabled(storeKit.isPurchasing)

            Button {
                if !showLiteAbandonOffer {
                    withAnimation(.spring(duration: 0.25)) {
                        showLiteAbandonOffer = true
                        selectedProduct = .darkroomPlus
                    }
                } else {
                    dismiss()
                }
            } label: {
                Text(
                    showLiteAbandonOffer
                        ? WCL10n.pick(zh: "暂不升级，继续免费无水印拍 2AM 派对闪光卷 →", en: "Continue Free with 2AM Flash Roll (No Watermark) →")
                        : WCL10n.pick(zh: "觉得贵？点此查看轻量扩容包或继续免费拍片", en: "Just need parallel rolls? See Lite Pass or continue free")
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.68))
            }
            .padding(.top, 2)

            if let status = storeKit.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .multilineTextAlignment(.center)
            }
            if let error = storeKit.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var complianceFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                Button(WCL10n.pick(zh: "恢复购买", en: "Restore Purchases")) {
                    Task {
                        await storeKit.restorePurchases()
                        if storeKit.canUseParallelRollsAndCustomTimer || storeKit.hasFullPro {
                            dismiss()
                        }
                    }
                }
                .foregroundStyle(.white.opacity(0.85))

                Link(
                    WCL10n.pick(zh: "隐私政策", en: "Privacy Policy"),
                    destination: URL(string: "https://a3152557994-ship-it.github.io/waitcam/privacy.html")!
                )
                Link(
                    WCL10n.pick(zh: "使用条款 (EULA)", en: "Terms of Use (EULA)"),
                    destination: URL(string: "https://a3152557994-ship-it.github.io/waitcam/terms.html")!
                )
            }
            .font(.caption)

            Text(
                WCL10n.pick(
                    zh: "年度订阅含 3 天免费试用，试用期结束前至少 24 小时未在「设置 > Apple 账户 > 订阅」取消将自动按年续费；终身版与扩容包为一次性买断永不续费。",
                    en: "Yearly subscription includes a 3-day free trial and auto-renews annually unless cancelled at least 24 hours before trial end in Settings > Apple Account > Subscriptions. Lifetime & Lite passes are one-time purchases."
                )
            )
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}
