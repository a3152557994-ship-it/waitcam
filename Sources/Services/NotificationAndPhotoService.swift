import Foundation
import Photos
import UIKit
import UserNotifications

public enum PhotoExportError: LocalizedError {
    case permissionDenied
    case emptySelection
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return WCL10n.pick(
                zh: "请在系统设置中授予 WaitCam「仅添加照片」权限，以便保存显影胶片。",
                en: "Please grant WaitCam 'Add Photos Only' access in Settings to save your developed film."
            )
        case .emptySelection:
            return WCL10n.pick(zh: "当前胶卷还没有可导出的成片。", en: "No developed frames in this roll yet.")
        case .saveFailed(let detail):
            return WCL10n.pick(zh: "写入系统相册失败：\(detail)", en: "Failed to save to Photos: \(detail)")
        }
    }
}

@MainActor
public final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let trialReminderIdentifier = "waitcam.trial.ending.reminder"
    @Published public private(set) var authorizationGranted: Bool = false

    public override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    public func requestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationGranted = true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorizationGranted = granted
        case .denied:
            authorizationGranted = false
        @unknown default:
            authorizationGranted = false
        }
    }

    public func scheduleUnlockNotification(for roll: DarkroomRoll) async {
        await requestPermissionIfNeeded()
        guard authorizationGranted, !roll.shots.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        let identifier = notificationIdentifier(for: roll.id)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let interval = roll.unlockAt.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = WCL10n.pick(zh: "🎞️ 暗房显影完成 · 可以看片了", en: "🎞️ Film Developed · Ready to Open!")
        content.body = WCL10n.pick(
            zh: "《\(roll.title)》共 \(roll.shots.count) 张照片已冲印完毕，点此立即开封并生成 35mm 胶片短片。",
            en: "\(roll.title) (\(roll.shots.count) shots) is ready in the Darkroom! Tap to reveal & share your 35mm Reel."
        )
        content.sound = .default
        content.userInfo = ["rollID": roll.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Schedules a transparent Day-2 reminder (48h after trial start, 24h before billing) to prevent surprise-charge 1★ reviews.
    public func scheduleTrialEndingReminder(afterSeconds: TimeInterval = 48 * 3600) async {
        await requestPermissionIfNeeded()
        guard authorizationGranted else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderIdentifier])

        let content = UNMutableNotificationContent()
        content.title = WCL10n.pick(
            zh: "🔔 WaitCam 免费试用到期温馨提醒",
            en: "🔔 Friendly Reminder: Your WaitCam Trial Ends Tomorrow"
        )
        content.body = WCL10n.pick(
            zh: "您的 3 天免费试用将在 24 小时后结束。希望您喜欢全套夜拍电影胶卷！如需管理订阅，可随时前往系统「设置 > Apple 账户 > 订阅」。",
            en: "Your 3-day free trial ends in 24 hours. Enjoying the cinema film stocks? Keep shooting, or manage anytime in Settings > Apple Account > Subscriptions."
        )
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(5, afterSeconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.trialReminderIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    public func cancelNotification(for rollID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [notificationIdentifier(for: rollID)]
        )
    }

    private func notificationIdentifier(for rollID: UUID) -> String {
        "waitcam.unlock.\(rollID.uuidString)"
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

public enum PhotoLibraryExportService {
    public static func exportBatchJPEGData(_ jpegList: [Data]) async throws -> Int {
        guard !jpegList.isEmpty else {
            throw PhotoExportError.emptySelection
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoExportError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for data in jpegList {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                }
            }
            return jpegList.count
        } catch {
            throw PhotoExportError.saveFailed(error.localizedDescription)
        }
    }

    public static func exportVideoToPhotos(fileURL: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoExportError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
        } catch {
            throw PhotoExportError.saveFailed(error.localizedDescription)
        }
    }
}
