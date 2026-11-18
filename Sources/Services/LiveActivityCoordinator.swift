import ActivityKit
import Foundation

@MainActor
public final class LiveActivityCoordinator: ObservableObject {
    @Published public private(set) var isActivityRunning: Bool = false
    @Published public private(set) var areActivitiesEnabled: Bool = ActivityAuthorizationInfo().areActivitiesEnabled
    @Published public private(set) var activeRollID: String?
    @Published public var statusHint: String?

    public init() {
        refreshStatus()
    }

    public func refreshStatus() {
        areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        let existing = Activity<DarkroomActivityAttributes>.activities
        isActivityRunning = !existing.isEmpty
        activeRollID = existing.first?.attributes.rollID
    }

    /// Synchronizes Dynamic Island & Lock Screen Live Activity with the highest-priority darkroom roll.
    public func sync(rolls: [DarkroomRoll], now: Date = Date()) async {
        areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        guard areActivitiesEnabled else {
            isActivityRunning = false
            statusHint = "系统未开启实时活动权限，请在设置中允许 WaitCam 显示灵动岛倒计时。"
            return
        }

        // Priority 1: earliest developing roll; Priority 2: ready-to-reveal unexported roll
        let developingRolls = rolls
            .filter { $0.isDeveloping(at: now) }
            .sorted { $0.unlockAt < $1.unlockAt }
        let readyRolls = rolls
            .filter { $0.isUnlocked(at: now) && $0.exportedAt == nil }
            .sorted { $0.unlockAt > $1.unlockAt }

        let activeCount = developingRolls.count + readyRolls.count
        guard let targetRoll = developingRolls.first ?? readyRolls.first else {
            await endAllActivities()
            return
        }

        let targetID = targetRoll.id.uuidString
        let state = targetRoll.activityState(activeRollCount: activeCount, now: now)
        let staleDate = targetRoll.unlockAt.addingTimeInterval(3600)
        let content = ActivityContent(state: state, staleDate: staleDate)

        let existing = Activity<DarkroomActivityAttributes>.activities
        if let matching = existing.first(where: { $0.attributes.rollID == targetID }) {
            await matching.update(content)
            for other in existing where other.id != matching.id {
                await other.end(nil, dismissalPolicy: .immediate)
            }
            isActivityRunning = true
            activeRollID = targetID
            statusHint = nil
            return
        }

        // End stale activities for other rolls before requesting a clean new Live Activity
        for other in existing {
            await other.end(nil, dismissalPolicy: .immediate)
        }

        do {
            let attributes = DarkroomActivityAttributes(rollID: targetID)
            let created = try Activity<DarkroomActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            isActivityRunning = true
            activeRollID = created.attributes.rollID
            statusHint = nil
        } catch {
            isActivityRunning = false
            statusHint = "灵动岛启动受限（\(error.localizedDescription)）"
        }
    }

    public func endAllActivities() async {
        for activity in Activity<DarkroomActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        isActivityRunning = false
        activeRollID = nil
    }
}
