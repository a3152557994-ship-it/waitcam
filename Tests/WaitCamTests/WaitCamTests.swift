import CryptoKit
import Foundation
import StoreKit
import StoreKitTest
import UIKit
import XCTest
@testable import WaitCam

final class WaitCamTests: XCTestCase {
    private var tempVaultRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempVaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("WaitCamTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempVaultRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempVaultRoot, FileManager.default.fileExists(atPath: tempVaultRoot.path) {
            try? FileManager.default.removeItem(at: tempVaultRoot)
        }
        try super.tearDownWithError()
    }

    // MARK: - 1. CoreImage Film Pipeline, Contact Sheet & 35mm Viral Reel MP4

    func testFilmLabRendersAllStocksContactSheetAnd35mmReelMP4() async throws {
        let processor = FilmLabProcessor()
        let rawCG = SimulatedPartySceneRenderer.renderPartySnapshotCGImage(
            size: CGSize(width: 900, height: 1200),
            frameNumber: 3,
            flashOn: true
        )
        let capturedAt = Date(timeIntervalSince1970: 1_794_900_000)

        var renderedImages: [UIImage] = []
        for stock in FilmStock.allCases {
            let jpegData = try processor.processCGImage(
                rawCG,
                stock: stock,
                dateStampStyle: stock == .clubMono400 ? .partyTime : .classic90s,
                capturedAt: capturedAt
            )
            XCTAssertGreaterThan(jpegData.count, 10_000)
            XCTAssertEqual(Array(jpegData.prefix(3)), [0xFF, 0xD8, 0xFF])

            let image = try XCTUnwrap(UIImage(data: jpegData))
            renderedImages.append(image)
        }

        let dummyRoll = DarkroomRoll(
            rollIndex: 1,
            title: "ROLL #01 · 2AM",
            filmStock: .party2AM,
            duration: .hours12
        )
        let sheetData = try XCTUnwrap(processor.renderContactSheet(photos: renderedImages, roll: dummyRoll))
        XCTAssertEqual(Array(sheetData.prefix(3)), [0xFF, 0xD8, 0xFF])

        // Verify 35mm Viral Reel MP4 video export
        let mp4URL = tempVaultRoot.appendingPathComponent("test-reel.mp4")
        let exportedURL = try await processor.render35mmReelVideo(
            photos: Array(renderedImages.prefix(2)),
            roll: dummyRoll,
            outputURL: mp4URL
        )
        let mp4Bytes = try Data(contentsOf: exportedURL)
        XCTAssertGreaterThan(mp4Bytes.count, 5_000)
        // MP4 ISO BMFF box header contains "ftyp" at offset 4..7
        let ftyp = String(data: mp4Bytes.subdata(in: 4..<8), encoding: .ascii)
        XCTAssertEqual(ftyp, "ftyp")
    }

    // MARK: - 2. Encrypted Darkroom Sandbox Lock & Reboot Persistence

    func testDarkroomVaultEncryptsShotsBlocksEarlyRevealAndPersistsAcrossReload() throws {
        let key = SymmetricKey(size: .bits256)
        let vault = try DarkroomVaultService(baseDirectory: tempVaultRoot, overrideKey: key)

        var manifest = try vault.loadManifest()
        let rollID = try XCTUnwrap(manifest.rolls.first?.id)
        XCTAssertEqual(manifest.rolls.first?.duration, .hours12)

        let rawCG = SimulatedPartySceneRenderer.renderPartySnapshotCGImage(size: CGSize(width: 600, height: 800))
        let originalJPEG = try FilmLabProcessor().processCGImage(rawCG, stock: .party2AM, dateStampStyle: .classic90s)
        let captureTime = Date(timeIntervalSince1970: 1_794_800_000)

        let (updatedRoll, shot) = try vault.appendEncryptedShot(
            jpegData: originalJPEG,
            toRollID: rollID,
            in: &manifest,
            capturedAt: captureTime
        )

        XCTAssertEqual(updatedRoll.shots.count, 1)
        XCTAssertEqual(updatedRoll.unlockAt, captureTime.addingTimeInterval(12 * 3600))

        let encryptedURL = vault.encryptedFileURL(for: shot, in: rollID)
        let diskBytes = try Data(contentsOf: encryptedURL)
        XCTAssertNotEqual(Array(diskBytes.prefix(3)), [0xFF, 0xD8, 0xFF])

        let almostUnlocked = updatedRoll.unlockAt.addingTimeInterval(-1)
        XCTAssertThrowsError(try vault.decryptShotData(shot, in: updatedRoll, now: almostUnlocked))

        let reloadedVault = try DarkroomVaultService(baseDirectory: tempVaultRoot, overrideKey: key)
        let reloadedManifest = try reloadedVault.loadManifest()
        let reloadedRoll = try XCTUnwrap(reloadedManifest.rolls.first(where: { $0.id == rollID }))
        let reloadedShot = try XCTUnwrap(reloadedRoll.shots.first)

        let revealedBytes = try reloadedVault.decryptShotData(
            reloadedShot,
            in: reloadedRoll,
            now: reloadedRoll.unlockAt
        )
        XCTAssertEqual(revealedBytes, originalJPEG)
    }

    // MARK: - 3. Live Activity Countdown & Progress State

    func testLiveActivityStateFormattingAndProgress() {
        let lockedAt = Date(timeIntervalSince1970: 1_794_800_000)
        let unlockAt = lockedAt.addingTimeInterval(12 * 3600)
        let state = DarkroomActivityAttributes.ContentState(
            rollTitle: "ROLL #01 · 2AM FLASH",
            filmStockName: "2AM Party Flash",
            shotCount: 6,
            maxShots: 24,
            lockedAt: lockedAt,
            unlockAt: unlockAt,
            activeRollCount: 1,
            isReadyToReveal: false
        )

        let sampleNow = lockedAt.addingTimeInterval(1062)
        XCTAssertEqual(state.formattedCountdown(at: sampleNow), "11:42:18")
        XCTAssertEqual(state.progress(at: sampleNow), 1062.0 / 43200.0, accuracy: 0.0001)
        XCTAssertEqual(state.formattedCountdown(at: unlockAt), "00:00:00")
        XCTAssertEqual(state.progress(at: unlockAt), 1.0, accuracy: 0.0001)
    }

    // MARK: - 4. Hybrid Paywall Gating (Free -> Plus / Annual Trial / Lifetime)

    @MainActor
    func testHybridPaywallEntitlementFlow() throws {
        let key = SymmetricKey(size: .bits256)
        let vault = try DarkroomVaultService(baseDirectory: tempVaultRoot, overrideKey: key)
        let storeKit = StoreKitManager(startTransactionListener: false)
        storeKit.setEntitlementsForTesting(plus: false, lifetime: false, annual: false)

        let viewModel = WaitCamViewModel(
            vault: vault,
            storeKit: storeKit,
            startBackgroundLoops: false
        )

        var manifest = viewModel.manifest
        let activeID = try XCTUnwrap(viewModel.activeRoll?.id)
        let sampleData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let shotNow = Date()
        _ = try vault.appendEncryptedShot(jpegData: sampleData, toRollID: activeID, in: &manifest, capturedAt: shotNow)
        let reloaded = WaitCamViewModel(vault: vault, storeKit: storeKit, startBackgroundLoops: false)

        XCTAssertFalse(reloaded.requestNewRoll(now: shotNow.addingTimeInterval(60)))
        XCTAssertEqual(reloaded.activePaywall, .parallelRolls)

        // Annual 3-day free trial unlocks full Pro just like Lifetime
        storeKit.setEntitlementsForTesting(plus: false, lifetime: false, annual: true)
        reloaded.activePaywall = nil
        reloaded.selectFilmStock(.tungsten800T)
        reloaded.selectDevelopDuration(.hours6)
        XCTAssertNil(reloaded.activePaywall)
        XCTAssertEqual(reloaded.selectedStock, .tungsten800T)
    }

    // MARK: - 5. StoreKit 2 Hybrid Trial Subscription + Lifetime Buyout Verification

    @MainActor
    func testStoreKitConfigurationLoadsHybridTrialAndLifetimeProducts() async throws {
        let bundle = Bundle(for: Self.self)
        let storekitURL = try XCTUnwrap(
            bundle.url(forResource: "WaitCam", withExtension: "storekit")
        )

        let session = try SKTestSession(contentsOf: storekitURL)
        session.disableDialogs = true
        session.clearTransactions()

        let storeManager = StoreKitManager(startTransactionListener: false)
        var reminderScheduled = false
        storeManager.onTrialStartedScheduleReminder = {
            reminderScheduled = true
        }

        await storeManager.loadProducts()
        XCTAssertEqual(storeManager.productsByID.count, 3)

        // Purchase 3-Day Free Trial Annual Subscription and verify Day-2 reminder hook fires
        let ok = await storeManager.purchase(.proAnnual)
        XCTAssertTrue(ok)
        XCTAssertTrue(storeManager.hasActiveAnnualSubscription)
        XCTAssertTrue(storeManager.hasFullPro)
        XCTAssertTrue(reminderScheduled, "Day-2 trial ending reminder must be scheduled upon starting 3-day free trial")
    }

    // MARK: - 6. Global 10-Locale ASO Metadata Verification

    func testGlobal10LocaleASOMetadataCompliesWithAppStoreLimits() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ascURL = projectRoot.appendingPathComponent("release/ASC_METADATA_READY.json")
        let data = try Data(contentsOf: ascURL)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let locs = try XCTUnwrap(root["localizations"] as? [String: [String: Any]])

        XCTAssertEqual(locs.count, 10, "Must include all 10 global high-spending App Store locales")

        for (locale, dict) in locs {
            let name = try XCTUnwrap(dict["name"] as? String)
            let subtitle = try XCTUnwrap(dict["subtitle"] as? String)
            let keywords = try XCTUnwrap(dict["keywords"] as? String)
            XCTAssertLessThanOrEqual(name.count, 30, "\(locale) title exceeds 30 chars (\(name.count)): \(name)")
            XCTAssertLessThanOrEqual(subtitle.count, 30, "\(locale) subtitle exceeds 30 chars (\(subtitle.count)): \(subtitle)")
            XCTAssertLessThanOrEqual(keywords.count, 100, "\(locale) keywords exceed 100 chars (\(keywords.count)): \(keywords)")
        }
    }
}
