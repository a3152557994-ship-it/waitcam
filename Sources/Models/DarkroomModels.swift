import Foundation

public enum WCL10n {
    public static var isZh: Bool {
        let code = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return code.hasPrefix("zh")
    }

    public static func pick(zh: String, en: String) -> String {
        isZh ? zh : en
    }
}

public enum FlashPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case on
    case auto
    case off

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .on: return WCL10n.pick(zh: "闪光 ON", en: "FLASH ON")
        case .auto: return WCL10n.pick(zh: "自动 AUTO", en: "AUTO")
        case .off: return WCL10n.pick(zh: "关闭 OFF", en: "FLASH OFF")
        }
    }

    public var symbolName: String {
        switch self {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        case .off: return "bolt.slash.fill"
        }
    }

    public func next() -> FlashPreference {
        switch self {
        case .on: return .auto
        case .auto: return .off
        case .off: return .on
        }
    }
}

public enum FilmStock: String, CaseIterable, Codable, Identifiable, Sendable {
    case party2AM = "party_2am"
    case tungsten800T = "tungsten_800t"
    case chrome100 = "chrome_100"
    case clubMono400 = "club_mono_400"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .party2AM: return WCL10n.pick(zh: "2AM 派对闪光", en: "2AM Party Flash")
        case .tungsten800T: return WCL10n.pick(zh: "800T 霓虹夜色", en: "800T Neon Halation")
        case .chrome100: return WCL10n.pick(zh: "Chrome 100 暖金", en: "Chrome 100 Gold")
        case .clubMono400: return WCL10n.pick(zh: "Club 400 黑白", en: "Club 400 Mono")
        }
    }

    public var shortCode: String {
        switch self {
        case .party2AM: return "2AM FLASH"
        case .tungsten800T: return "800T"
        case .chrome100: return "CH100"
        case .clubMono400: return "BW400"
        }
    }

    public var subtitle: String {
        switch self {
        case .party2AM:
            return WCL10n.pick(zh: "强闪高反差 · 日光微青阴影 · 免费无水印", en: "Punchy xenon flash · Cool-teal shadows · Free")
        case .tungsten800T:
            return WCL10n.pick(zh: "电影级红橙光晕 Halation · 夜店霓虹灵魂卷", en: "Cinema red-orange halation · Nightlife favorite")
        case .chrome100:
            return WCL10n.pick(zh: "复古阳光暖金高光 · 派对人像通透发色", en: "Warm golden highlights · Rich analog skin tones")
        case .clubMono400:
            return WCL10n.pick(zh: "银盐粗颗粒高反差黑白 · 零点街头纪实", en: "Gritty silver-halide B&W · Late-night street vibe")
        }
    }

    public var isoLabel: String {
        switch self {
        case .party2AM: return "ISO 400"
        case .tungsten800T: return "ISO 800"
        case .chrome100: return "ISO 100"
        case .clubMono400: return "ISO 400 BW"
        }
    }

    public var requiresLifetimePro: Bool {
        self != .party2AM
    }
}

public enum DevelopDuration: String, CaseIterable, Codable, Identifiable, Sendable {
    case hours6 = "6h"
    case hours12 = "12h"
    case hours24 = "24h"
    case seconds30Calibration = "30s_lab"

    public var id: String { rawValue }

    public static var productionCases: [DevelopDuration] {
        [.hours6, .hours12, .hours24]
    }

    public var durationSeconds: TimeInterval {
        switch self {
        case .hours6: return 6 * 3600
        case .hours12: return 12 * 3600
        case .hours24: return 24 * 3600
        case .seconds30Calibration: return 30
        }
    }

    public var badgeTitle: String {
        switch self {
        case .hours6: return WCL10n.pick(zh: "6H 速冲", en: "6H FAST")
        case .hours12: return WCL10n.pick(zh: "12H 锁定", en: "12H LOCK")
        case .hours24: return WCL10n.pick(zh: "24H 盲盒", en: "24H DROP")
        case .seconds30Calibration: return WCL10n.pick(zh: "30S 校准", en: "30S DEMO")
        }
    }

    public var detailLabel: String {
        switch self {
        case .hours6: return WCL10n.pick(zh: "6 小时晨醒速冲", en: "6-Hour Morning Reveal")
        case .hours12: return WCL10n.pick(zh: "12 小时次日显影（默认）", en: "12-Hour Next-Day Reveal (Free)")
        case .hours24: return WCL10n.pick(zh: "24 小时隔日惊喜", en: "24-Hour Mystery Drop")
        case .seconds30Calibration: return WCL10n.pick(zh: "30 秒实验室链路实测", en: "30-Second Quick Demo Roll")
        }
    }

    public var requiresCustomTimerUnlock: Bool {
        self == .hours6 || self == .hours24
    }
}

public enum DateStampStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case classic90s = "classic_90s"
    case partyTime = "party_time"
    case cleanOff = "clean_off"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic90s: return WCL10n.pick(zh: "经典橙红日期 ('26 11 18)", en: "90s Quartz Date ('26 11 18)")
        case .partyTime: return WCL10n.pick(zh: "派对时刻戳 ('26 11 18 02:14)", en: "2AM Timestamp ('26 11 18 02:14)")
        case .cleanOff: return WCL10n.pick(zh: "纯净无日期印记", en: "Clean (No Date Stamp)")
        }
    }

    public var requiresLifetimePro: Bool {
        self != .classic90s
    }

    public func formattedStamp(for date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        switch self {
        case .classic90s:
            formatter.dateFormat = "''yy MM dd"
            return formatter.string(from: date)
        case .partyTime:
            formatter.dateFormat = "''yy MM dd HH:mm"
            return formatter.string(from: date)
        case .cleanOff:
            return nil
        }
    }
}

public struct LockedShot: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let frameNumber: Int
    public let capturedAt: Date
    public let encryptedFilename: String
    public let byteSize: Int

    public init(
        id: UUID = UUID(),
        frameNumber: Int,
        capturedAt: Date = Date(),
        encryptedFilename: String,
        byteSize: Int
    ) {
        self.id = id
        self.frameNumber = frameNumber
        self.capturedAt = capturedAt
        self.encryptedFilename = encryptedFilename
        self.byteSize = byteSize
    }
}

public struct DarkroomRoll: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let rollIndex: Int
    public let title: String
    public let filmStock: FilmStock
    public let duration: DevelopDuration
    public let createdAt: Date
    public var lockedAt: Date
    public var unlockAt: Date
    public var isSealed: Bool
    public var isCalibrationDemo: Bool
    public var exportedAt: Date?
    public var shots: [LockedShot]
    public let maxShots: Int

    public init(
        id: UUID = UUID(),
        rollIndex: Int,
        title: String,
        filmStock: FilmStock,
        duration: DevelopDuration,
        createdAt: Date = Date(),
        lockedAt: Date? = nil,
        unlockAt: Date? = nil,
        isSealed: Bool = false,
        isCalibrationDemo: Bool = false,
        exportedAt: Date? = nil,
        shots: [LockedShot] = [],
        maxShots: Int = 24
    ) {
        let baseLockDate = lockedAt ?? createdAt
        self.id = id
        self.rollIndex = rollIndex
        self.title = title
        self.filmStock = filmStock
        self.duration = duration
        self.createdAt = createdAt
        self.lockedAt = baseLockDate
        self.unlockAt = unlockAt ?? baseLockDate.addingTimeInterval(duration.durationSeconds)
        self.isSealed = isSealed
        self.isCalibrationDemo = isCalibrationDemo
        self.exportedAt = exportedAt
        self.shots = shots
        self.maxShots = maxShots
    }

    public func isUnlocked(at now: Date = Date()) -> Bool {
        !shots.isEmpty && now >= unlockAt
    }

    public func isDeveloping(at now: Date = Date()) -> Bool {
        !shots.isEmpty && now < unlockAt
    }

    public func remainingSeconds(at now: Date = Date()) -> Int {
        let delta = unlockAt.timeIntervalSince(now)
        if delta <= 0 { return 0 }
        return Int(ceil(delta))
    }

    public func formattedCountdown(at now: Date = Date()) -> String {
        let total = remainingSeconds(at: now)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    public func progress(at now: Date = Date()) -> Double {
        if now >= unlockAt { return 1.0 }
        let total = max(1.0, unlockAt.timeIntervalSince(lockedAt))
        let elapsed = max(0.0, now.timeIntervalSince(lockedAt))
        return min(1.0, elapsed / total)
    }

    public var isFull: Bool {
        shots.count >= maxShots
    }

    public func activityState(activeRollCount: Int, now: Date = Date()) -> DarkroomActivityAttributes.ContentState {
        DarkroomActivityAttributes.ContentState(
            rollTitle: title,
            filmStockName: filmStock.displayName,
            shotCount: shots.count,
            maxShots: maxShots,
            lockedAt: lockedAt,
            unlockAt: unlockAt,
            activeRollCount: activeRollCount,
            isReadyToReveal: isUnlocked(at: now)
        )
    }
}

public enum PaywallTriggerReason: String, Identifiable, Sendable {
    case parallelRolls
    case customDuration
    case proFilmStock
    case contactSheet
    case manualUpgrade

    public var id: String { rawValue }

    public var headline: String {
        switch self {
        case .parallelRolls:
            return WCL10n.pick(zh: "上一卷仍在暗房显影 · 解锁无限胶卷并行", en: "Unlock Unlimited Parallel Film Rolls")
        case .customDuration:
            return WCL10n.pick(zh: "自定义 6h 速冲 / 24h 盲盒显影", en: "Unlock Custom 6h Fast & 24h Timers")
        case .proFilmStock:
            return WCL10n.pick(zh: "0 元免费试用全套夜拍电影胶卷", en: "Try All Cinema Film Stocks Free")
        case .contactSheet:
            return WCL10n.pick(zh: "生成复古 35mm 接触印相单海报", en: "Unlock 35mm Contact Sheet Posters")
        case .manualUpgrade:
            return WCL10n.pick(zh: "解锁 WaitCam Pro 完整暗房特权", en: "Unlock Full WaitCam Pro Darkroom")
        }
    }

    public var subheadline: String {
        switch self {
        case .parallelRolls:
            return WCL10n.pick(
                zh: "免费畅享 3 天全功能体验（第 2 天自动响铃提醒到期），或选择黑五特惠一次买断永久拥有。",
                en: "Start your 3-day $0 free trial (we'll remind you 24h before it ends), or grab the Black Friday Lifetime pass."
            )
        case .customDuration:
            return WCL10n.pick(
                zh: "想明早 6 小时看片，或锁满 24 小时制造惊喜？免费试用 3 天或一次买断即可自由切换。",
                en: "Want morning 6h reveals or 24h mystery drops? Try Pro free for 3 days or unlock forever."
            )
        case .proFilmStock:
            return WCL10n.pick(
                zh: "涵盖 800T 霓虹红橙光晕、Chrome 100 暖金与 Club 400 银盐黑白，全部本地实时演算无水印直出。",
                en: "Includes 800T Neon Halation, Chrome 100 Gold & Club 400 Mono—rendered 100% offline with zero watermarks."
            )
        case .contactSheet:
            return WCL10n.pick(
                zh: "一键将整卷显影照片排成带齿孔编码的复古底片 Contact Sheet 海报。",
                en: "Turn your entire developed roll into an authentic 35mm sprocket-hole Contact Sheet poster."
            )
        case .manualUpgrade:
            return WCL10n.pick(
                zh: "支持 3 天 $0 免费试用（到期前自动提醒），也支持讨厌订阅者的终身一次性买断。",
                en: "Try everything $0 for 3 days with a guaranteed reminder, or pay once for Lifetime ownership."
            )
        }
    }
}
