import Combine
import Foundation
import SwiftUI
import UIKit

@MainActor
public final class WaitCamViewModel: ObservableObject {
    @Published public private(set) var manifest: DarkroomManifest
    @Published public private(set) var now: Date = Date()
    @Published public var flashPreference: FlashPreference = .on
    @Published public var selectedStock: FilmStock = .party2AM
    @Published public var selectedDuration: DevelopDuration = .hours12
    @Published public var selectedDateStamp: DateStampStyle = .classic90s

    @Published public private(set) var isCapturing: Bool = false
    @Published public private(set) var shutterFlashPulse: Bool = false
    @Published public private(set) var isExportingRollID: UUID?
    @Published public var activePaywall: PaywallTriggerReason?
    @Published public var isDarkroomPresented: Bool = false
    @Published public var isSettingsPresented: Bool = false
    @Published public var bannerToast: String?
    @Published public var errorBanner: String?

    @Published public private(set) var unlockedThumbnails: [UUID: [UUID: UIImage]] = [:]
    @Published public var lastGeneratedReelURL: URL?

    public let vault: DarkroomVaultService
    public let filmLab: FilmLabProcessor
    public let cameraService: CameraSessionService
    public let storeKit: StoreKitManager
    public let liveActivity: LiveActivityCoordinator
    public let notificationService: NotificationService

    private var tickerTask: Task<Void, Never>?
    private var previousDevelopingIDs: Set<UUID> = []
    private var toastDismissTask: Task<Void, Never>?

    public init(
        vault: DarkroomVaultService? = nil,
        filmLab: FilmLabProcessor = .shared,
        cameraService: CameraSessionService? = nil,
        storeKit: StoreKitManager? = nil,
        liveActivity: LiveActivityCoordinator? = nil,
        notificationService: NotificationService? = nil,
        startBackgroundLoops: Bool = true
    ) {
        let resolvedVault: DarkroomVaultService
        if let vault {
            resolvedVault = vault
        } else if let defaultVault = try? DarkroomVaultService() {
            resolvedVault = defaultVault
        } else {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("WaitCamFallbackVault", isDirectory: true)
            resolvedVault = try! DarkroomVaultService(baseDirectory: tmp)
        }

        let resolvedStoreKit = storeKit ?? StoreKitManager(startTransactionListener: startBackgroundLoops)
        let resolvedNotification = notificationService ?? NotificationService()
        resolvedStoreKit.onTrialStartedScheduleReminder = { [weak resolvedNotification] in
            await resolvedNotification?.scheduleTrialEndingReminder()
        }

        self.vault = resolvedVault
        self.filmLab = filmLab
        self.cameraService = cameraService ?? CameraSessionService()
        self.storeKit = resolvedStoreKit
        self.liveActivity = liveActivity ?? LiveActivityCoordinator()
        self.notificationService = resolvedNotification

        let loaded = (try? resolvedVault.loadManifest()) ?? DarkroomManifest()
        self.manifest = loaded
        self.previousDevelopingIDs = Set(loaded.rolls.filter { $0.isDeveloping(at: Date()) }.map(\.id))

        if let active = activeRoll {
            self.selectedStock = active.filmStock
            if !active.isCalibrationDemo {
                self.selectedDuration = active.duration
            }
        }

        if startBackgroundLoops {
            startClockTicker()
        }
    }

    deinit {
        tickerTask?.cancel()
        toastDismissTask?.cancel()
    }

    // MARK: - Computed Roll Accessors

    public var activeRoll: DarkroomRoll? {
        if let selectedID = manifest.selectedRollID,
           let matched = manifest.rolls.first(where: { $0.id == selectedID && !$0.isSealed && !$0.isFull }) {
            return matched
        }
        return manifest.rolls.first(where: { !$0.isSealed && !$0.isFull && !$0.isCalibrationDemo })
    }

    public var developingRolls: [DarkroomRoll] {
        manifest.rolls
            .filter { $0.isDeveloping(at: now) }
            .sorted { $0.unlockAt < $1.unlockAt }
    }

    public var unlockedRolls: [DarkroomRoll] {
        manifest.rolls
            .filter { $0.isUnlocked(at: now) }
            .sorted { $0.unlockAt > $1.unlockAt }
    }

    public var readyToRevealCount: Int {
        unlockedRolls.filter { $0.exportedAt == nil }.count
    }

    public var primaryCountdownRoll: DarkroomRoll? {
        developingRolls.first
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        await cameraService.prepareAndStart()
        await storeKit.loadProducts()
        await liveActivity.sync(rolls: manifest.rolls, now: now)
    }

    public func handleSceneDidBecomeActive() async {
        now = Date()
        await storeKit.refreshEntitlements()
        await liveActivity.sync(rolls: manifest.rolls, now: now)
    }

    public func handleDeepLink(_ url: URL) {
        guard url.scheme == "waitcam" else { return }
        if url.host == "darkroom" {
            isDarkroomPresented = true
        }
    }

    // MARK: - Viewfinder Controls & Paywall Gates

    public func cycleFlashPreference() {
        flashPreference = flashPreference.next()
        showToast("闪光灯模式：\(flashPreference.displayTitle)")
    }

    public func selectFilmStock(_ stock: FilmStock) {
        if stock.requiresLifetimePro && !storeKit.hasFullPro {
            activePaywall = .proFilmStock
            return
        }
        selectedStock = stock
        if var roll = activeRoll, roll.shots.isEmpty,
           let idx = manifest.rolls.firstIndex(where: { $0.id == roll.id }) {
            roll = DarkroomRoll(
                id: roll.id,
                rollIndex: roll.rollIndex,
                title: String(format: "ROLL #%02d · %@", roll.rollIndex, stock.shortCode),
                filmStock: stock,
                duration: roll.duration,
                createdAt: roll.createdAt
            )
            manifest.rolls[idx] = roll
            try? vault.saveManifest(manifest)
        }
        showToast("已切换胶卷：\(stock.displayName)")
    }

    public func selectDevelopDuration(_ duration: DevelopDuration) {
        if duration.requiresCustomTimerUnlock && !storeKit.canUseParallelRollsAndCustomTimer {
            activePaywall = .customDuration
            return
        }
        selectedDuration = duration
        if let current = activeRoll, current.shots.isEmpty,
           let idx = manifest.rolls.firstIndex(where: { $0.id == current.id }) {
            let updated = DarkroomRoll(
                id: current.id,
                rollIndex: current.rollIndex,
                title: current.title,
                filmStock: current.filmStock,
                duration: duration,
                createdAt: current.createdAt
            )
            manifest.rolls[idx] = updated
            try? vault.saveManifest(manifest)
            showToast("当前未拍胶卷已设为：\(duration.detailLabel)")
        } else {
            showToast("下一卷将使用：\(duration.detailLabel)")
        }
    }

    public func selectDateStampStyle(_ style: DateStampStyle) {
        if style.requiresLifetimePro && !storeKit.hasFullPro {
            activePaywall = .proFilmStock
            return
        }
        selectedDateStamp = style
    }

    /// Attempts to seal the active roll and load a fresh roll (gated by parallel roll entitlement).
    @discardableResult
    public func requestNewRoll(now: Date = Date()) -> Bool {
        if let current = activeRoll, current.shots.isEmpty {
            showToast("当前胶卷还是全新的（0/\(current.maxShots)），直接拍摄即可。")
            return false
        }

        // Seal current active roll first if it has shots
        if let current = activeRoll, !current.shots.isEmpty,
           let idx = manifest.rolls.firstIndex(where: { $0.id == current.id }) {
            manifest.rolls[idx].isSealed = true
        }

        let canParallel = vault.canCreateParallelRoll(
            in: manifest,
            hasParallelUnlock: storeKit.canUseParallelRollsAndCustomTimer,
            now: now
        )
        guard canParallel else {
            // Keep existing unsealed/sealed roll safely stored and surface impulse paywall
            try? vault.saveManifest(manifest)
            activePaywall = .parallelRolls
            return false
        }

        let stockToUse = (selectedStock.requiresLifetimePro && !storeKit.hasFullPro) ? .party2AM : selectedStock
        let durationToUse = (selectedDuration.requiresCustomTimerUnlock && !storeKit.canUseParallelRollsAndCustomTimer) ? .hours12 : selectedDuration

        let fresh = vault.makeRoll(
            rollIndex: manifest.nextRollNumber,
            stock: stockToUse,
            duration: durationToUse,
            isCalibrationDemo: false
        )
        manifest.nextRollNumber += 1
        manifest.rolls.append(fresh)
        manifest.selectedRollID = fresh.id
        try? vault.saveManifest(manifest)
        showToast("已装入全新胶卷 \(fresh.title)")
        return true
    }

    // MARK: - Capture -> CoreImage Film LUT -> Encrypted Darkroom Vault

    public func captureShutter(now: Date = Date()) async {
        guard !isCapturing else { return }

        // Ensure there is an open roll ready to receive the shot
        if activeRoll == nil {
            let canStart = vault.canCreateParallelRoll(
                in: manifest,
                hasParallelUnlock: storeKit.canUseParallelRollsAndCustomTimer,
                now: now
            )
            if !canStart {
                activePaywall = .parallelRolls
                return
            }
            let stockToUse = (selectedStock.requiresLifetimePro && !storeKit.hasFullPro) ? .party2AM : selectedStock
            let durationToUse = (selectedDuration.requiresCustomTimerUnlock && !storeKit.canUseParallelRollsAndCustomTimer) ? .hours12 : selectedDuration
            let fresh = vault.makeRoll(
                rollIndex: manifest.nextRollNumber,
                stock: stockToUse,
                duration: durationToUse,
                isCalibrationDemo: false
            )
            manifest.nextRollNumber += 1
            manifest.rolls.append(fresh)
            manifest.selectedRollID = fresh.id
        }

        guard let targetRoll = activeRoll else { return }

        isCapturing = true
        errorBanner = nil

        let haptic = UIImpactFeedbackGenerator(style: .heavy)
        haptic.impactOccurred()

        // Visual shutter + flash feedback so users immediately know the frame was taken (fixes 2AM CAM #1 complaint)
        withAnimation(.easeOut(duration: 0.08)) {
            shutterFlashPulse = true
        }

        defer {
            isCapturing = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 140_000_000)
                withAnimation(.easeOut(duration: 0.22)) {
                    self.shutterFlashPulse = false
                }
            }
        }

        do {
            let nextFrame = targetRoll.shots.count + 1
            let captured = try await cameraService.captureFrame(
                flashPreference: flashPreference,
                simulatedFrameNumber: nextFrame
            )

            let effectiveStock = (targetRoll.filmStock.requiresLifetimePro && !storeKit.hasFullPro)
                ? .party2AM
                : targetRoll.filmStock
            let effectiveStamp = (selectedDateStamp.requiresLifetimePro && !storeKit.hasFullPro)
                ? .classic90s
                : selectedDateStamp

            let lab = self.filmLab
            let filmJPEG: Data
            switch captured {
            case .hardwareJPEG(let rawData):
                filmJPEG = try await Task.detached(priority: .userInitiated) {
                    try lab.processPhoto(
                        rawData: rawData,
                        stock: effectiveStock,
                        dateStampStyle: effectiveStamp,
                        capturedAt: now
                    )
                }.value
            case .simulatedCGImage(let cgImage):
                filmJPEG = try await Task.detached(priority: .userInitiated) {
                    try lab.processCGImage(
                        cgImage,
                        stock: effectiveStock,
                        dateStampStyle: effectiveStamp,
                        capturedAt: now
                    )
                }.value
            }

            let (updatedRoll, _) = try vault.appendEncryptedShot(
                jpegData: filmJPEG,
                toRollID: targetRoll.id,
                in: &manifest,
                capturedAt: now
            )

            await notificationService.scheduleUnlockNotification(for: updatedRoll)
            await liveActivity.sync(rolls: manifest.rolls, now: now)

            let countdown = updatedRoll.formattedCountdown(at: now)
            showToast("第 \(updatedRoll.shots.count)/\(updatedRoll.maxShots) 张已锁入暗房 · \(countdown) 后显影")
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    // MARK: - 30s Calibration Demo Roll (Fast Live Activity & Export Verification)

    public func create30SecondCalibrationRoll(now: Date = Date()) async {
        errorBanner = nil
        let rollNumber = manifest.nextRollNumber
        manifest.nextRollNumber += 1

        var demoRoll = vault.makeRoll(
            rollIndex: rollNumber,
            stock: .party2AM,
            duration: .seconds30Calibration,
            isCalibrationDemo: true
        )
        demoRoll.isSealed = true
        manifest.rolls.append(demoRoll)

        do {
            for frame in 1...3 {
                let cg = SimulatedPartySceneRenderer.renderPartySnapshotCGImage(
                    frameNumber: frame + 10,
                    flashOn: true
                )
                let jpeg = try filmLab.processCGImage(
                    cg,
                    stock: .party2AM,
                    dateStampStyle: .classic90s,
                    capturedAt: now
                )
                (demoRoll, _) = try vault.appendEncryptedShot(
                    jpegData: jpeg,
                    toRollID: demoRoll.id,
                    in: &manifest,
                    capturedAt: now
                )
            }
            await notificationService.scheduleUnlockNotification(for: demoRoll)
            await liveActivity.sync(rolls: manifest.rolls, now: now)
            showToast("已装入 30 秒实测胶卷（3 张加密），锁屏与灵动岛已开始倒计时！")
            isSettingsPresented = false
            isDarkroomPresented = true
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    // MARK: - Darkroom Reveal & Batch Export

    public func revealRollPhotosIfUnlocked(_ roll: DarkroomRoll) {
        guard roll.isUnlocked(at: now) else { return }
        if let cached = unlockedThumbnails[roll.id], cached.count == roll.shots.count {
            return
        }

        var loadedMap: [UUID: UIImage] = [:]
        for shot in roll.shots {
            if let data = try? vault.decryptShotData(shot, in: roll, now: now),
               let img = UIImage(data: data) {
                loadedMap[shot.id] = img
            }
        }
        unlockedThumbnails[roll.id] = loadedMap
    }

    public func batchExportRollToPhotos(_ roll: DarkroomRoll) async {
        guard roll.isUnlocked(at: now) else {
            errorBanner = DarkroomVaultError.stillDeveloping(remainingSeconds: roll.remainingSeconds(at: now)).localizedDescription
            return
        }

        isExportingRollID = roll.id
        errorBanner = nil
        defer { isExportingRollID = nil }

        do {
            let jpegList = try vault.decryptAllShots(in: roll, now: now)
            let count = try await PhotoLibraryExportService.exportBatchJPEGData(jpegList)
            if let idx = manifest.rolls.firstIndex(where: { $0.id == roll.id }) {
                manifest.rolls[idx].exportedAt = Date()
                try? vault.saveManifest(manifest)
            }
            await liveActivity.sync(rolls: manifest.rolls, now: Date())
            showToast("🎉 已将整卷 \(count) 张无水印胶片批量保存至系统相册！")
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    public func exportContactSheetPoster(_ roll: DarkroomRoll) async {
        guard storeKit.hasFullPro else {
            activePaywall = .contactSheet
            return
        }
        guard roll.isUnlocked(at: now) else { return }

        isExportingRollID = roll.id
        errorBanner = nil
        defer { isExportingRollID = nil }

        do {
            let jpegList = try vault.decryptAllShots(in: roll, now: now)
            let images = jpegList.compactMap { UIImage(data: $0) }
            guard let posterData = filmLab.renderContactSheet(photos: images, roll: roll) else {
                throw FilmLabError.encodingFailed
            }
            _ = try await PhotoLibraryExportService.exportBatchJPEGData([posterData])
            showToast(WCL10n.pick(zh: "🎞️ 已生成并保存 35mm 整卷接触印相单海报至系统相册！", en: "🎞️ Saved 35mm Contact Sheet poster to Photos!"))
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    public func export35mmReelVideo(_ roll: DarkroomRoll) async {
        guard roll.isUnlocked(at: now) else { return }

        isExportingRollID = roll.id
        errorBanner = nil
        defer { isExportingRollID = nil }

        do {
            let jpegList = try vault.decryptAllShots(in: roll, now: now)
            let images = jpegList.compactMap { UIImage(data: $0) }
            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WaitCam-35mm-Reel-\(roll.rollIndex).mp4")
            let videoURL = try await filmLab.render35mmReelVideo(photos: images, roll: roll, outputURL: outURL)
            self.lastGeneratedReelURL = videoURL
            try? await PhotoLibraryExportService.exportVideoToPhotos(fileURL: videoURL)
            showToast(
                WCL10n.pick(
                    zh: "🎬 已生成 35mm 胶片显影短片并存入相册（可点下方按钮一键晒朋友圈/小红书）！",
                    en: "🎬 35mm Film Reel MP4 saved to Photos & ready to share!"
                )
            )
        } catch {
            errorBanner = error.localizedDescription
        }
    }

    public func deleteRoll(_ roll: DarkroomRoll) async {
        notificationService.cancelNotification(for: roll.id)
        unlockedThumbnails.removeValue(forKey: roll.id)
        try? vault.deleteRoll(roll.id, from: &manifest)
        await liveActivity.sync(rolls: manifest.rolls, now: now)
        showToast("已删除胶卷 \(roll.title)")
    }

    // MARK: - Private Clock & Toast

    private func startClockTicker() {
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { break }
                self.now = Date()
                let currentDeveloping = Set(self.manifest.rolls.filter { $0.isDeveloping(at: self.now) }.map(\.id))
                if currentDeveloping != self.previousDevelopingIDs {
                    self.previousDevelopingIDs = currentDeveloping
                    await self.liveActivity.sync(rolls: self.manifest.rolls, now: self.now)
                }
            }
        }
    }

    public func showToast(_ message: String) {
        bannerToast = message
        toastDismissTask?.cancel()
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                self.bannerToast = nil
            }
        }
    }
}
