import ActivityKit
import Foundation

/// Shared Live Activity & Lock Screen contract compiled into both WaitCam and WaitCamWidgets.
/// Strictly Foundation + ActivityKit only (zero UIKit references for extension safety).
public struct DarkroomActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public let rollTitle: String
        public let filmStockName: String
        public let shotCount: Int
        public let maxShots: Int
        public let lockedAt: Date
        public let unlockAt: Date
        public let activeRollCount: Int
        public let isReadyToReveal: Bool

        public init(
            rollTitle: String,
            filmStockName: String,
            shotCount: Int,
            maxShots: Int,
            lockedAt: Date,
            unlockAt: Date,
            activeRollCount: Int,
            isReadyToReveal: Bool
        ) {
            self.rollTitle = rollTitle
            self.filmStockName = filmStockName
            self.shotCount = shotCount
            self.maxShots = maxShots
            self.lockedAt = lockedAt
            self.unlockAt = unlockAt
            self.activeRollCount = activeRollCount
            self.isReadyToReveal = isReadyToReveal
        }

        public func remainingSeconds(at now: Date = Date()) -> Int {
            let delta = unlockAt.timeIntervalSince(now)
            if delta <= 0 { return 0 }
            return Int(ceil(delta))
        }

        public func progress(at now: Date = Date()) -> Double {
            if isReadyToReveal || now >= unlockAt {
                return 1.0
            }
            let total = max(1.0, unlockAt.timeIntervalSince(lockedAt))
            let elapsed = max(0.0, now.timeIntervalSince(lockedAt))
            return min(1.0, elapsed / total)
        }

        public func formattedCountdown(at now: Date = Date()) -> String {
            let totalSeconds = remainingSeconds(at: now)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
    }

    public let rollID: String

    public init(rollID: String) {
        self.rollID = rollID
    }
}
