import CryptoKit
import Foundation
import Security

public enum DarkroomVaultError: LocalizedError, Equatable {
    case stillDeveloping(remainingSeconds: Int)
    case shotNotFound
    case rollNotFound
    case freeTierParallelLimitReached
    case storageFailure(String)

    public var errorDescription: String? {
        switch self {
        case .stillDeveloping(let remaining):
            let h = remaining / 3600
            let m = (remaining % 3600) / 60
            let s = remaining % 60
            return String(format: "底片仍在暗房显影锁定中（还剩 %02d:%02d:%02d），到点后自动解锁", h, m, s)
        case .shotNotFound:
            return "未找到对应的暗房加密底片"
        case .rollNotFound:
            return "未找到对应的胶卷记录"
        case .freeTierParallelLimitReached:
            return "免费版一次仅支持显影 1 卷胶片，解锁「暗房扩容」或「终身买断」即可无限多卷并行。"
        case .storageFailure(let detail):
            return "暗房沙盒存储异常：\(detail)"
        }
    }
}

public struct DarkroomManifest: Codable, Sendable {
    public var nextRollNumber: Int
    public var rolls: [DarkroomRoll]
    public var selectedRollID: UUID?

    public init(nextRollNumber: Int = 1, rolls: [DarkroomRoll] = [], selectedRollID: UUID? = nil) {
        self.nextRollNumber = nextRollNumber
        self.rolls = rolls
        self.selectedRollID = selectedRollID
    }
}

/// Encrypted local sandbox darkroom vault under Application Support/WaitCamDarkroom.
/// Never stores plaintext thumbnails or writes unfinished shots to the system Photo Library.
public final class DarkroomVaultService: @unchecked Sendable {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let manifestURL: URL
    private let rollsDirectory: URL
    private let keyFileURL: URL
    private let encryptionKey: SymmetricKey
    private let lock = NSLock()

    public init(
        baseDirectory: URL? = nil,
        overrideKey: SymmetricKey? = nil,
        keychainAccount: String = "com.yanghe.waitcam.darkroom.aes256"
    ) throws {
        self.fileManager = .default

        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            base = appSupport.appendingPathComponent("WaitCamDarkroom", isDirectory: true)
        }

        self.rootDirectory = base
        self.manifestURL = base.appendingPathComponent("manifest.json", isDirectory: false)
        self.rollsDirectory = base.appendingPathComponent("rolls", isDirectory: true)
        self.keyFileURL = base.appendingPathComponent(".vault_key.bin", isDirectory: false)

        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rollsDirectory, withIntermediateDirectories: true)

        if let overrideKey {
            self.encryptionKey = overrideKey
        } else {
            self.encryptionKey = try Self.loadOrCreateSymmetricKey(
                keychainAccount: keychainAccount,
                fallbackURL: keyFileURL,
                fileManager: fileManager
            )
        }
    }

    // MARK: - Manifest Persistence

    public func loadManifest() throws -> DarkroomManifest {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: manifestURL.path) else {
            let initialRoll = makeRoll(rollIndex: 1, stock: .party2AM, duration: .hours12, isCalibrationDemo: false)
            let manifest = DarkroomManifest(nextRollNumber: 2, rolls: [initialRoll], selectedRollID: initialRoll.id)
            try persistManifestLocked(manifest)
            return manifest
        }

        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DarkroomManifest.self, from: data)
    }

    public func saveManifest(_ manifest: DarkroomManifest) throws {
        lock.lock()
        defer { lock.unlock() }
        try persistManifestLocked(manifest)
    }

    private func persistManifestLocked(_ manifest: DarkroomManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Roll & Encrypted Shot Operations

    public func makeRoll(
        rollIndex: Int,
        stock: FilmStock,
        duration: DevelopDuration,
        isCalibrationDemo: Bool
    ) -> DarkroomRoll {
        let title = isCalibrationDemo
            ? String(format: "DEMO #%02d · 30s实测卷", rollIndex)
            : String(format: "ROLL #%02d · %@", rollIndex, stock.shortCode)
        return DarkroomRoll(
            rollIndex: rollIndex,
            title: title,
            filmStock: stock,
            duration: duration,
            isCalibrationDemo: isCalibrationDemo
        )
    }

    public func canCreateParallelRoll(
        in manifest: DarkroomManifest,
        hasParallelUnlock: Bool,
        now: Date = Date()
    ) -> Bool {
        if hasParallelUnlock { return true }
        // Free users may have only 1 active developing roll at a time.
        let developingCount = manifest.rolls.filter { !$0.isCalibrationDemo && $0.isDeveloping(at: now) }.count
        return developingCount == 0
    }

    /// Encrypts rendered JPEG data with AES-256-GCM and commits atomically to sandbox disk.
    public func appendEncryptedShot(
        jpegData: Data,
        toRollID rollID: UUID,
        in manifest: inout DarkroomManifest,
        capturedAt: Date = Date()
    ) throws -> (roll: DarkroomRoll, shot: LockedShot) {
        lock.lock()
        defer { lock.unlock() }

        guard let index = manifest.rolls.firstIndex(where: { $0.id == rollID }) else {
            throw DarkroomVaultError.rollNotFound
        }

        let rollDir = rollsDirectory.appendingPathComponent(rollID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rollDir, withIntermediateDirectories: true)

        let shotID = UUID()
        let filename = "\(shotID.uuidString).enc"
        let fileURL = rollDir.appendingPathComponent(filename, isDirectory: false)

        let sealed = try AES.GCM.seal(jpegData, using: encryptionKey)
        guard let combined = sealed.combined else {
            throw DarkroomVaultError.storageFailure("AES-GCM combined payload generation failed")
        }

        try combined.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        var roll = manifest.rolls[index]
        if roll.shots.isEmpty {
            // Anchor the darkroom countdown from the moment the first shot enters the vault.
            roll.lockedAt = capturedAt
            roll.unlockAt = capturedAt.addingTimeInterval(roll.duration.durationSeconds)
        }

        let shot = LockedShot(
            id: shotID,
            frameNumber: roll.shots.count + 1,
            capturedAt: capturedAt,
            encryptedFilename: filename,
            byteSize: jpegData.count
        )
        roll.shots.append(shot)
        if roll.isFull {
            roll.isSealed = true
        }
        manifest.rolls[index] = roll
        try persistManifestLocked(manifest)

        return (roll, shot)
    }

    /// Strictly refuses decryption until `now >= roll.unlockAt`.
    public func decryptShotData(
        _ shot: LockedShot,
        in roll: DarkroomRoll,
        now: Date = Date()
    ) throws -> Data {
        guard roll.isUnlocked(at: now) else {
            throw DarkroomVaultError.stillDeveloping(remainingSeconds: roll.remainingSeconds(at: now))
        }

        let fileURL = rollsDirectory
            .appendingPathComponent(roll.id.uuidString, isDirectory: true)
            .appendingPathComponent(shot.encryptedFilename, isDirectory: false)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw DarkroomVaultError.shotNotFound
        }

        let encrypted = try Data(contentsOf: fileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }

    public func decryptAllShots(in roll: DarkroomRoll, now: Date = Date()) throws -> [Data] {
        guard roll.isUnlocked(at: now) else {
            throw DarkroomVaultError.stillDeveloping(remainingSeconds: roll.remainingSeconds(at: now))
        }
        return try roll.shots.map { shot in
            try decryptShotData(shot, in: roll, now: now)
        }
    }

    public func encryptedFileURL(for shot: LockedShot, in rollID: UUID) -> URL {
        rollsDirectory
            .appendingPathComponent(rollID.uuidString, isDirectory: true)
            .appendingPathComponent(shot.encryptedFilename, isDirectory: false)
    }

    public func deleteRoll(_ rollID: UUID, from manifest: inout DarkroomManifest) throws {
        lock.lock()
        defer { lock.unlock() }

        manifest.rolls.removeAll { $0.id == rollID }
        let rollDir = rollsDirectory.appendingPathComponent(rollID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: rollDir.path) {
            try? fileManager.removeItem(at: rollDir)
        }

        if manifest.selectedRollID == rollID {
            manifest.selectedRollID = manifest.rolls.first(where: { !$0.isSealed && !$0.isFull })?.id
        }
        try persistManifestLocked(manifest)
    }

    // MARK: - Keychain / Protected Key Management

    private static func loadOrCreateSymmetricKey(
        keychainAccount: String,
        fallbackURL: URL,
        fileManager: FileManager
    ) throws -> SymmetricKey {
        if let existing = readKeyFromKeychain(account: keychainAccount) {
            return existing
        }

        if fileManager.fileExists(atPath: fallbackURL.path),
           let raw = try? Data(contentsOf: fallbackURL),
           raw.count == 32 {
            return SymmetricKey(data: raw)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        if !saveKeyToKeychain(keyData, account: keychainAccount) {
            try keyData.write(to: fallbackURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return newKey
    }

    private static func readKeyFromKeychain(account: String) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yanghe.waitcam.vault",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    private static func saveKeyToKeychain(_ data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yanghe.waitcam.vault",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
}
