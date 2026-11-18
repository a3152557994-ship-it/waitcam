import AVFoundation
import Foundation
import SwiftUI
import UIKit

public enum CameraCaptureOutput: Sendable {
    case hardwareJPEG(Data)
    case simulatedCGImage(CGImage)
}

public enum CameraServiceError: LocalizedError {
    case permissionDenied
    case sessionUnavailable
    case captureInProgress
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "请在系统设置中允许 WaitCam 访问相机，以使用强闪光胶片拍摄。"
        case .sessionUnavailable:
            return "相机硬件尚未准备就绪，请稍候重试。"
        case .captureInProgress:
            return "正在处理上一张暗房底片，请稍等片刻。"
        case .encodingFailed:
            return "相机捕获数据异常，请重新拍摄。"
        }
    }
}

private final class CameraCapturePipeline: @unchecked Sendable {
    let session = AVCaptureSession()
    let sessionQueue = DispatchQueue(label: "com.yanghe.waitcam.camera.session", qos: .userInitiated)
    let photoOutput = AVCapturePhotoOutput()

    private var isConfigured = false
    private var activeInput: AVCaptureDeviceInput?

    func configureAndStart(position: AVCaptureDevice.Position, completion: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async { [self] in
            if !isConfigured {
                session.beginConfiguration()
                session.sessionPreset = .photo

                if let device = Self.discoverCamera(position: position),
                   let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    activeInput = input
                }

                if session.canAddOutput(photoOutput) {
                    session.addOutput(photoOutput)
                }

                session.commitConfiguration()
                isConfigured = true
            }

            if !session.isRunning {
                session.startRunning()
            }
            completion(session.isRunning)
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
            completion()
        }
    }

    func switchPosition(_ position: AVCaptureDevice.Position, completion: @escaping @Sendable () -> Void) {
        sessionQueue.async { [self] in
            session.beginConfiguration()
            if let current = activeInput {
                session.removeInput(current)
                activeInput = nil
            }
            if let device = Self.discoverCamera(position: position),
               let newInput = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(newInput) {
                session.addInput(newInput)
                activeInput = newInput
            }
            session.commitConfiguration()
            completion()
        }
    }

    func captureJPEG(desiredAVFlash: AVCaptureDevice.FlashMode, delegate: AVCapturePhotoCaptureDelegate) {
        sessionQueue.async { [self] in
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            // Safety check: only assign flashMode when hardware photoOutput supports it
            if photoOutput.supportedFlashModes.contains(desiredAVFlash) {
                settings.flashMode = desiredAVFlash
            } else if photoOutput.supportedFlashModes.contains(.off) {
                settings.flashMode = .off
            }
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    static func discoverCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return wide
        }
        return AVCaptureDevice.default(for: .video)
    }
}

@MainActor
public final class CameraSessionService: NSObject, ObservableObject {
    @Published public private(set) var authorizationStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published public private(set) var isSessionRunning: Bool = false
    @Published public private(set) var isUsingSimulatedSensor: Bool = false
    @Published public private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published public private(set) var isFrontScreenFlashActive: Bool = false

    public var session: AVCaptureSession { pipeline.session }

    private let pipeline = CameraCapturePipeline()
    private var photoContinuation: CheckedContinuation<Data, Error>?

    public override init() {
        super.init()
    }

    public func prepareAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        authorizationStatus = status

        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }

        guard authorizationStatus == .authorized || hasNoPhysicalCamera() else {
            isSessionRunning = false
            return
        }

        if hasNoPhysicalCamera() {
            isUsingSimulatedSensor = true
            isSessionRunning = true
            return
        }

        isUsingSimulatedSensor = false
        let position = cameraPosition

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.configureAndStart(position: position) { running in
                Task { @MainActor [weak self] in
                    self?.isSessionRunning = running
                    continuation.resume()
                }
            }
        }
    }

    public func stop() {
        guard !isUsingSimulatedSensor else {
            isSessionRunning = false
            return
        }
        pipeline.stop {
            Task { @MainActor [weak self] in
                self?.isSessionRunning = false
            }
        }
    }

    public func toggleCameraPosition() async {
        let next: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        cameraPosition = next
        guard !isUsingSimulatedSensor else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pipeline.switchPosition(next) {
                continuation.resume()
            }
        }
    }

    public func captureFrame(flashPreference: FlashPreference, simulatedFrameNumber: Int) async throws -> CameraCaptureOutput {
        if isUsingSimulatedSensor {
            if flashPreference == .on {
                await triggerRetinaScreenFlash()
            }
            let cg = SimulatedPartySceneRenderer.renderPartySnapshotCGImage(
                frameNumber: simulatedFrameNumber,
                flashOn: flashPreference != .off
            )
            return .simulatedCGImage(cg)
        }

        guard authorizationStatus == .authorized else {
            throw CameraServiceError.permissionDenied
        }
        guard photoContinuation == nil else {
            throw CameraServiceError.captureInProgress
        }

        if cameraPosition == .front && flashPreference == .on {
            await triggerRetinaScreenFlash()
        }

        let desiredAVFlash: AVCaptureDevice.FlashMode
        switch flashPreference {
        case .on: desiredAVFlash = .on
        case .auto: desiredAVFlash = .auto
        case .off: desiredAVFlash = .off
        }

        let data: Data = try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation
            self.pipeline.captureJPEG(desiredAVFlash: desiredAVFlash, delegate: self)
        }
        return .hardwareJPEG(data)
    }

    private func triggerRetinaScreenFlash() async {
        isFrontScreenFlashActive = true
        try? await Task.sleep(nanoseconds: 160_000_000)
        isFrontScreenFlashActive = false
    }

    private func hasNoPhysicalCamera() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return CameraCapturePipeline.discoverCamera(position: cameraPosition) == nil
        #endif
    }
}

extension CameraSessionService: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor [weak self] in
            guard let self, let continuation = self.photoContinuation else { return }
            self.photoContinuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: CameraServiceError.encodingFailed)
            }
        }
    }
}

public struct CameraPreviewRepresentable: UIViewRepresentable {
    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: PreviewHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

public final class PreviewHostView: UIView {
    public override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    public var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
