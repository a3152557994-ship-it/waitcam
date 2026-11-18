import Foundation
import StoreKit
import UIKit

/// Hybrid top-converting monetization model:
/// 1) 3-Day Free Trial -> Auto-Renewing Yearly Plan ($14.99/yr or ¥38/yr) with Day-2 Reminder Notification
/// 2) Black Friday Lifetime One-Time Buyout ($9.99 or ¥28) for subscription-averse buyers
/// 3) Darkroom Plus Mini Unlock ($2.99 or ¥8) as gentle step-down / abandon offer
public enum WaitCamProduct: String, CaseIterable, Identifiable, Sendable {
    case proAnnual = "com.yanghe.waitcam.pro.annual"
    case proLifetime = "com.yanghe.waitcam.pro.lifetime"
    case darkroomPlus = "com.yanghe.waitcam.darkroom.plus"

    public var id: String { rawValue }

    public var isSubscription: Bool {
        self == .proAnnual
    }

    public var shortTitle: String {
        switch self {
        case .proAnnual:
            return WCL10n.pick(zh: "年度全能会员 (先免费用 3 天)", en: "Yearly Pro (3-Day Free Trial)")
        case .proLifetime:
            return WCL10n.pick(zh: "黑五特惠 · 终身一次买断", en: "Black Friday · Lifetime Unlock")
        case .darkroomPlus:
            return WCL10n.pick(zh: "轻量暗房扩容包 (仅并行+定时)", en: "Darkroom Plus (Rolls + Timers)")
        }
    }

    public var badgeText: String {
        switch self {
        case .proAnnual:
            return WCL10n.pick(zh: "0元先玩 · 第2天提醒", en: "MOST POPULAR · $0 TODAY")
        case .proLifetime:
            return WCL10n.pick(zh: "5折买断 · 零续费", en: "50% OFF · PAY ONCE")
        case .darkroomPlus:
            return WCL10n.pick(zh: "省钱微氪", en: "LITE PASS")
        }
    }

    public var subtitle: String {
        switch self {
        case .proAnnual:
            return WCL10n.pick(
                zh: "今日 ¥0 解锁全套电影胶卷、无限并行与印相单；到期前 24h 自动发通知提醒，随时可取消",
                en: "Unlock all 4 cinema film stocks, parallel rolls & contact sheets for $0 today. Reminder 24h before trial ends."
            )
        case .proLifetime:
            return WCL10n.pick(
                zh: "讨厌订阅？一次付清永久拥有全部 Pro 胶卷与后续所有新胶片更新，绝无自动扣费",
                en: "Hate subscriptions? Pay once, own every Pro film stock, custom timer & future darkroom update forever."
            )
        case .darkroomPlus:
            return WCL10n.pick(
                zh: "仅解锁无限胶卷并行显影 + 6h / 12h / 24h 自定义显影倒计时（一次买断）",
                en: "One-time unlock for unlimited parallel rolls + 6h / 12h / 24h custom timers only."
            )
        }
    }

    public var billingNote: String {
        switch self {
        case .proAnnual:
            return WCL10n.pick(zh: "3天免费，后 /年", en: "3d free, then /yr")
        case .proLifetime, .darkroomPlus:
            return WCL10n.pick(zh: "一次付清", en: "One-time")
        }
    }

    public var fallbackDisplayPrice: String {
        let isChinaStore = Locale.current.currency?.identifier == "CNY" || WCL10n.isZh
        switch self {
        case .proAnnual:
            return isChinaStore ? "¥38.00" : "$14.99"
        case .proLifetime:
            return isChinaStore ? "¥28.00" : "$9.99"
        case .darkroomPlus:
            return isChinaStore ? "¥8.00" : "$2.99"
        }
    }
}

@MainActor
public final class StoreKitManager: ObservableObject {
    private static let plusUnlockedKey = "waitcam.entitlement.darkroomPlus"
    private static let lifetimeUnlockedKey = "waitcam.entitlement.proLifetime"
    private static let annualActiveKey = "waitcam.entitlement.proAnnualActive"

    @Published public private(set) var hasDarkroomPlus: Bool
    @Published public private(set) var hasProLifetime: Bool
    @Published public private(set) var hasActiveAnnualSubscription: Bool
    @Published public private(set) var productsByID: [String: Product] = [:]
    @Published public private(set) var isLoadingProducts: Bool = false
    @Published public private(set) var isPurchasing: Bool = false
    @Published public var statusMessage: String?
    @Published public var errorMessage: String?

    public var onTrialStartedScheduleReminder: (() async -> Void)?
    private var updatesTask: Task<Void, Never>?

    public var canUseParallelRollsAndCustomTimer: Bool {
        hasDarkroomPlus || hasProLifetime || hasActiveAnnualSubscription
    }

    public var hasFullPro: Bool {
        hasProLifetime || hasActiveAnnualSubscription
    }

    public init(startTransactionListener: Bool = true) {
        let defaults = UserDefaults.standard
        self.hasDarkroomPlus = defaults.bool(forKey: Self.plusUnlockedKey)
        self.hasProLifetime = defaults.bool(forKey: Self.lifetimeUnlockedKey)
        self.hasActiveAnnualSubscription = defaults.bool(forKey: Self.annualActiveKey)

        if startTransactionListener {
            self.updatesTask = Task { [weak self] in
                await self?.listenForTransactions()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func displayPrice(for item: WaitCamProduct) -> String {
        productsByID[item.rawValue]?.displayPrice ?? item.fallbackDisplayPrice
    }

    public func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let ids = WaitCamProduct.allCases.map(\.rawValue)
            let fetched = try await Product.products(for: ids)
            var mapped: [String: Product] = [:]
            for product in fetched {
                mapped[product.id] = product
            }
            self.productsByID = mapped
            await refreshEntitlements()
        } catch {
            self.statusMessage = nil
        }
    }

    public func refreshEntitlements() async {
        var foundPlus = false
        var foundLifetime = false
        var foundAnnual = false
        let now = Date()

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                switch transaction.productID {
                case WaitCamProduct.darkroomPlus.rawValue:
                    foundPlus = true
                case WaitCamProduct.proLifetime.rawValue:
                    foundLifetime = true
                case WaitCamProduct.proAnnual.rawValue:
                    if let exp = transaction.expirationDate {
                        if exp > now { foundAnnual = true }
                    } else {
                        foundAnnual = true
                    }
                default:
                    break
                }
            }
        }

        if foundPlus { setPlusUnlocked(true) }
        if foundLifetime { setLifetimeUnlocked(true) }
        setAnnualActive(foundAnnual)
    }

    public func purchase(_ item: WaitCamProduct) async -> Bool {
        errorMessage = nil
        statusMessage = nil

        if productsByID[item.rawValue] == nil {
            await loadProducts()
        }

        guard let product = productsByID[item.rawValue] else {
            errorMessage = WCL10n.pick(
                zh: "暂未获取到 App Store 商品信息，请检查网络后重试。",
                en: "Unable to load App Store product info right now. Please check your connection."
            )
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                applyEntitlement(productID: transaction.productID, expirationDate: transaction.expirationDate)
                await transaction.finish()

                if item == .proAnnual {
                    await onTrialStartedScheduleReminder?()
                    statusMessage = WCL10n.pick(
                        zh: "🎉 已开启 3 天免费试用并设好第 2 天到期提醒通知！",
                        en: "🎉 3-Day Free Trial started! Day-2 reminder notification scheduled."
                    )
                } else if item == .proLifetime {
                    statusMessage = WCL10n.pick(
                        zh: "🎉 已永久买断解锁 WaitCam Pro 全部胶卷与暗房特权！",
                        en: "🎉 WaitCam Pro Lifetime unlocked forever!"
                    )
                } else {
                    statusMessage = WCL10n.pick(
                        zh: "✅ 已解锁无限并行胶卷与自定义显影时长！",
                        en: "✅ Unlimited parallel rolls & custom timers unlocked!"
                    )
                }
                return true
            case .userCancelled:
                statusMessage = WCL10n.pick(
                    zh: "未扣款，您仍可继续免费无水印拍摄 2AM 派对闪光卷。",
                    en: "No charge made. Enjoy shooting free watermark-free 2AM Flash rolls anytime."
                )
                return false
            case .pending:
                statusMessage = WCL10n.pick(
                    zh: "交易正在等待系统或家人共享审批。",
                    en: "Purchase is pending Ask to Buy / system approval."
                )
                return false
            @unknown default:
                errorMessage = WCL10n.pick(zh: "购买未完成，请稍后重试。", en: "Purchase could not be completed.")
                return false
            }
        } catch {
            errorMessage = WCL10n.pick(
                zh: "内购失败：\(error.localizedDescription)",
                en: "Purchase failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    public func restorePurchases() async {
        errorMessage = nil
        statusMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if hasFullPro {
                statusMessage = WCL10n.pick(
                    zh: "✅ 已成功恢复 WaitCam Pro 全部权益！",
                    en: "✅ WaitCam Pro access successfully restored!"
                )
            } else if canUseParallelRollsAndCustomTimer {
                statusMessage = WCL10n.pick(
                    zh: "✅ 已成功恢复暗房扩容包权益！",
                    en: "✅ Darkroom Plus access successfully restored!"
                )
            } else {
                statusMessage = WCL10n.pick(
                    zh: "未找到历史购买记录；您可随时免费使用 2AM 基础闪光卷。",
                    en: "No active purchases found. 2AM Party Flash remains 100% free."
                )
            }
        } catch {
            errorMessage = WCL10n.pick(
                zh: "恢复购买失败：\(error.localizedDescription)",
                en: "Restore failed: \(error.localizedDescription)"
            )
        }
    }

    public func setEntitlementsForTesting(plus: Bool, lifetime: Bool, annual: Bool = false) {
        setPlusUnlocked(plus)
        setLifetimeUnlocked(lifetime)
        setAnnualActive(annual)
    }

    private func applyEntitlement(productID: String, expirationDate: Date?) {
        switch productID {
        case WaitCamProduct.darkroomPlus.rawValue:
            setPlusUnlocked(true)
        case WaitCamProduct.proLifetime.rawValue:
            setLifetimeUnlocked(true)
        case WaitCamProduct.proAnnual.rawValue:
            if let exp = expirationDate {
                setAnnualActive(exp > Date())
            } else {
                setAnnualActive(true)
            }
        default:
            break
        }
    }

    private func setPlusUnlocked(_ unlocked: Bool) {
        hasDarkroomPlus = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.plusUnlockedKey)
    }

    private func setLifetimeUnlocked(_ unlocked: Bool) {
        hasProLifetime = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.lifetimeUnlockedKey)
    }

    private func setAnnualActive(_ active: Bool) {
        hasActiveAnnualSubscription = active
        UserDefaults.standard.set(active, forKey: Self.annualActiveKey)
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard !Task.isCancelled else { break }
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    applyEntitlement(productID: transaction.productID, expirationDate: transaction.expirationDate)
                } else if transaction.productID == WaitCamProduct.proAnnual.rawValue {
                    setAnnualActive(false)
                }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let signed):
            return signed
        }
    }
}
