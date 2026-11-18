import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import UIKit

public enum FilmLabError: LocalizedError {
    case invalidInputImage
    case renderFailed
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidInputImage: return "无法解析拍摄图像数据"
        case .renderFailed: return "胶片显影引擎渲染失败"
        case .encodingFailed: return "高清成片编码失败"
        }
    }
}

/// On-device CoreImage film processor using a single shared GPU-backed CIContext.
/// Guarantees zero intermediate caching leaks and zero App watermarks.
public final class FilmLabProcessor: @unchecked Sendable {
    public static let shared = FilmLabProcessor()

    private let ciContext: CIContext
    private let maxDimension: CGFloat = 3024

    public init() {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        self.ciContext = CIContext(options: [
            .cacheIntermediates: false,
            .workingColorSpace: srgb,
            .outputColorSpace: srgb
        ])
    }

    /// Processes raw camera JPEG data into a finished watermark-free retro film JPEG.
    public func processPhoto(
        rawData: Data,
        stock: FilmStock,
        dateStampStyle: DateStampStyle,
        capturedAt: Date = Date()
    ) throws -> Data {
        guard var inputImage = CIImage(data: rawData, options: [.applyOrientationProperty: true]) else {
            throw FilmLabError.invalidInputImage
        }
        return try renderPipeline(
            inputImage: &inputImage,
            stock: stock,
            dateStampStyle: dateStampStyle,
            capturedAt: capturedAt
        )
    }

    /// Processes a CGImage directly (used by simulator capture or unit tests).
    public func processCGImage(
        _ cgImage: CGImage,
        stock: FilmStock,
        dateStampStyle: DateStampStyle,
        capturedAt: Date = Date()
    ) throws -> Data {
        var inputImage = CIImage(cgImage: cgImage)
        return try renderPipeline(
            inputImage: &inputImage,
            stock: stock,
            dateStampStyle: dateStampStyle,
            capturedAt: capturedAt
        )
    }

    private func renderPipeline(
        inputImage: inout CIImage,
        stock: FilmStock,
        dateStampStyle: DateStampStyle,
        capturedAt: Date
    ) throws -> Data {
        try autoreleasepool {
            // Normalize origin to (0, 0)
            let origin = inputImage.extent.origin
            if origin != .zero {
                inputImage = inputImage.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
            }

            // Cap max edge to 3024px to prevent memory spikes during rapid party bursts
            let currentMax = max(inputImage.extent.width, inputImage.extent.height)
            if currentMax > maxDimension && currentMax > 0 {
                let scale = maxDimension / currentMax
                let lanczos = CIFilter.lanczosScaleTransform()
                lanczos.inputImage = inputImage
                lanczos.scale = Float(scale)
                lanczos.aspectRatio = 1.0
                if let scaled = lanczos.outputImage {
                    inputImage = scaled
                }
            }

            let extent = inputImage.extent.integral
            guard !extent.isEmpty else { throw FilmLabError.invalidInputImage }

            var working = applyFlashHighlightRecovery(inputImage)
            working = applyStockGrading(working, stock: stock, extent: extent)
            working = applyFilmGrain(working, strength: grainStrength(for: stock), extent: extent)
            working = applyOpticalVignette(working, intensity: vignetteIntensity(for: stock), extent: extent)
            working = working.cropped(to: extent)

            guard let cgOutput = ciContext.createCGImage(working, from: extent) else {
                throw FilmLabError.renderFailed
            }

            return try stampDateAndEncodeJPEG(
                cgImage: cgOutput,
                dateStampStyle: dateStampStyle,
                capturedAt: capturedAt
            )
        }
    }

    private func applyFlashHighlightRecovery(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(0.82, forKey: "inputHighlightAmount")
        filter.setValue(0.18, forKey: "inputShadowAmount")
        return filter.outputImage ?? image
    }

    private func applyStockGrading(_ image: CIImage, stock: FilmStock, extent: CGRect) -> CIImage {
        var graded = image

        switch stock {
        case .party2AM:
            // Cool-teal shadows + punchy disposable flash warmth in skin & mids
            if let temp = CIFilter(name: "CITemperatureAndTint") {
                temp.setValue(graded, forKey: kCIInputImageKey)
                temp.setValue(CIVector(x: 6200, y: 4), forKey: "inputNeutral")
                temp.setValue(CIVector(x: 6550, y: -4), forKey: "inputTargetNeutral")
                graded = temp.outputImage ?? graded
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(graded, forKey: kCIInputImageKey)
                controls.setValue(1.12, forKey: kCIInputContrastKey)
                controls.setValue(1.08, forKey: kCIInputSaturationKey)
                controls.setValue(0.02, forKey: kCIInputBrightnessKey)
                graded = controls.outputImage ?? graded
            }
            if let matrix = CIFilter(name: "CIColorMatrix") {
                matrix.setValue(graded, forKey: kCIInputImageKey)
                matrix.setValue(CIVector(x: 1.03, y: 0.02, z: -0.02, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 0.0, y: 1.01, z: 0.02, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: -0.02, y: 0.03, z: 0.96, w: 0), forKey: "inputBVector")
                matrix.setValue(CIVector(x: 0.01, y: 0.015, z: 0.025, w: 0), forKey: "inputBiasVector")
                graded = matrix.outputImage ?? graded
            }

        case .tungsten800T:
            // Tungsten cool midtones + iconic red-orange halation around party lights
            if let temp = CIFilter(name: "CITemperatureAndTint") {
                temp.setValue(graded, forKey: kCIInputImageKey)
                temp.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                temp.setValue(CIVector(x: 4900, y: 6), forKey: "inputTargetNeutral")
                graded = temp.outputImage ?? graded
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(graded, forKey: kCIInputImageKey)
                controls.setValue(1.16, forKey: kCIInputContrastKey)
                controls.setValue(1.10, forKey: kCIInputSaturationKey)
                graded = controls.outputImage ?? graded
            }
            graded = applyHalation(to: graded, extent: extent)

        case .chrome100:
            // Warm Kodak-inspired golden highlights and creamy midtones
            if let temp = CIFilter(name: "CITemperatureAndTint") {
                temp.setValue(graded, forKey: kCIInputImageKey)
                temp.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                temp.setValue(CIVector(x: 7300, y: -6), forKey: "inputTargetNeutral")
                graded = temp.outputImage ?? graded
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(graded, forKey: kCIInputImageKey)
                controls.setValue(1.08, forKey: kCIInputContrastKey)
                controls.setValue(1.18, forKey: kCIInputSaturationKey)
                controls.setValue(0.03, forKey: kCIInputBrightnessKey)
                graded = controls.outputImage ?? graded
            }
            if let matrix = CIFilter(name: "CIColorMatrix") {
                matrix.setValue(graded, forKey: kCIInputImageKey)
                matrix.setValue(CIVector(x: 1.05, y: 0.03, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 0.01, y: 1.01, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 0, y: 0.01, z: 0.91, w: 0), forKey: "inputBVector")
                matrix.setValue(CIVector(x: 0.02, y: 0.01, z: 0.0, w: 0), forKey: "inputBiasVector")
                graded = matrix.outputImage ?? graded
            }

        case .clubMono400:
            // High-contrast silver gelatin black & white
            if let mono = CIFilter(name: "CIColorMonochrome") {
                mono.setValue(graded, forKey: kCIInputImageKey)
                mono.setValue(CIColor(red: 0.96, green: 0.95, blue: 0.92), forKey: kCIInputColorKey)
                mono.setValue(1.0, forKey: kCIInputIntensityKey)
                graded = mono.outputImage ?? graded
            }
            if let controls = CIFilter(name: "CIColorControls") {
                controls.setValue(graded, forKey: kCIInputImageKey)
                controls.setValue(1.32, forKey: kCIInputContrastKey)
                controls.setValue(0.02, forKey: kCIInputBrightnessKey)
                graded = controls.outputImage ?? graded
            }
        }

        return graded.cropped(to: extent)
    }

    private func applyHalation(to image: CIImage, extent: CGRect) -> CIImage {
        guard let threshold = CIFilter(name: "CIColorMatrix"),
              let clamp = CIFilter(name: "CIColorClamp"),
              let blur = CIFilter(name: "CIGaussianBlur"),
              let add = CIFilter(name: "CIAdditionCompositing") else {
            return image
        }
        threshold.setValue(image, forKey: kCIInputImageKey)
        threshold.setValue(CIVector(x: 3.4, y: 0.0, z: 0.0, w: 0), forKey: "inputRVector")
        threshold.setValue(CIVector(x: 0.75, y: 0.0, z: 0.0, w: 0), forKey: "inputGVector")
        threshold.setValue(CIVector(x: 0.18, y: 0.0, z: 0.0, w: 0), forKey: "inputBVector")
        threshold.setValue(CIVector(x: -2.6, y: -0.58, z: -0.14, w: 0), forKey: "inputBiasVector")
        guard let extracted = threshold.outputImage else { return image }

        clamp.setValue(extracted, forKey: kCIInputImageKey)
        clamp.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputMinComponents")
        clamp.setValue(CIVector(x: 0.75, y: 0.24, z: 0.08, w: 1), forKey: "inputMaxComponents")
        guard let clamped = clamp.outputImage else { return image }

        let radius = max(10.0, min(28.0, extent.width * 0.015))
        blur.setValue(clamped.cropped(to: extent), forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)
        guard let halo = blur.outputImage?.cropped(to: extent) else { return image }

        add.setValue(halo, forKey: kCIInputImageKey)
        add.setValue(image, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: extent) ?? image
    }

    private func applyFilmGrain(_ image: CIImage, strength: CGFloat, extent: CGRect) -> CIImage {
        guard let noiseGen = CIFilter(name: "CIRandomGenerator"),
              let noiseOutput = noiseGen.outputImage else {
            return image
        }
        // CRITICAL: crop infinite random generator immediately to finite bounds
        let croppedNoise = noiseOutput.cropped(to: extent)

        guard let mono = CIFilter(name: "CIColorControls") else { return image }
        mono.setValue(croppedNoise, forKey: kCIInputImageKey)
        mono.setValue(0.0, forKey: kCIInputSaturationKey)
        mono.setValue(1.35, forKey: kCIInputContrastKey)
        guard let monoNoise = mono.outputImage else { return image }

        guard let alphaScale = CIFilter(name: "CIColorMatrix") else { return image }
        alphaScale.setValue(monoNoise, forKey: kCIInputImageKey)
        alphaScale.setValue(CIVector(x: 0, y: 0, z: 0, w: strength), forKey: "inputAVector")
        guard let subtleGrain = alphaScale.outputImage else { return image }

        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return image }
        blend.setValue(subtleGrain, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    private func applyOpticalVignette(_ image: CIImage, intensity: Double, extent: CGRect) -> CIImage {
        guard let vignette = CIFilter(name: "CIVignette") else { return image }
        vignette.setValue(image, forKey: kCIInputImageKey)
        vignette.setValue(intensity, forKey: kCIInputIntensityKey)
        vignette.setValue(1.65, forKey: kCIInputRadiusKey)
        return vignette.outputImage?.cropped(to: extent) ?? image
    }

    private func grainStrength(for stock: FilmStock) -> CGFloat {
        switch stock {
        case .party2AM: return 0.22
        case .tungsten800T: return 0.26
        case .chrome100: return 0.16
        case .clubMono400: return 0.32
        }
    }

    private func vignetteIntensity(for stock: FilmStock) -> Double {
        switch stock {
        case .party2AM: return 0.55
        case .tungsten800T: return 0.62
        case .chrome100: return 0.42
        case .clubMono400: return 0.68
        }
    }

    private func stampDateAndEncodeJPEG(
        cgImage: CGImage,
        dateStampStyle: DateStampStyle,
        capturedAt: Date
    ) throws -> Data {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIImage(cgImage: cgImage).draw(in: rect)

            if let stamp = dateStampStyle.formattedStamp(for: capturedAt) {
                drawQuartzDateStamp(stamp, in: size, context: ctx.cgContext)
            }
        }

        guard let jpegData = renderedImage.jpegData(compressionQuality: 0.90) else {
            throw FilmLabError.encodingFailed
        }
        return jpegData
    }

    private func drawQuartzDateStamp(_ text: String, in canvasSize: CGSize, context: CGContext) {
        let fontSize = max(24.0, min(canvasSize.width, canvasSize.height) * 0.034)
        let font = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)

        let shadow = NSShadow()
        shadow.shadowColor = UIColor(red: 1.0, green: 0.22, blue: 0.0, alpha: 0.88)
        shadow.shadowBlurRadius = fontSize * 0.38
        shadow.shadowOffset = .zero

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 1.0, green: 0.46, blue: 0.14, alpha: 0.95),
            .shadow: shadow
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()
        let marginX = canvasSize.width * 0.055
        let marginY = canvasSize.height * 0.048
        let point = CGPoint(
            x: canvasSize.width - marginX - textSize.width,
            y: canvasSize.height - marginY - textSize.height
        )

        context.saveGState()
        attrString.draw(at: point)
        context.restoreGState()
    }

    /// Generates a 3-column analog celluloid Contact Sheet poster JPEG for unlocked rolls (Pro feature).
    public func renderContactSheet(photos: [UIImage], roll: DarkroomRoll) -> Data? {
        guard !photos.isEmpty else { return nil }

        let columns = 3
        let rows = Int(ceil(Double(photos.count) / Double(columns)))
        let width: CGFloat = 1440
        let sidePad: CGFloat = 72
        let topHeader: CGFloat = 190
        let bottomFooter: CGFloat = 110
        let gutter: CGFloat = 34
        let cellW = (width - sidePad * 2 - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        let cellH = cellW * (4.0 / 3.0)
        let rowSpacing: CGFloat = 58
        let height = topHeader + CGFloat(rows) * (cellH + rowSpacing) + bottomFooter

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let sheet = renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Sprocket holes along left and right film borders
            UIColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1.0).setFill()
            var yPos: CGFloat = 36
            while yPos < height - 36 {
                let leftHole = UIBezierPath(roundedRect: CGRect(x: 20, y: yPos, width: 22, height: 30), cornerRadius: 5)
                let rightHole = UIBezierPath(roundedRect: CGRect(x: width - 42, y: yPos, width: 22, height: 30), cornerRadius: 5)
                leftHole.fill()
                rightHole.fill()
                yPos += 62
            }

            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 34, weight: .bold),
                .foregroundColor: UIColor(red: 1.0, green: 0.48, blue: 0.2, alpha: 1.0)
            ]
            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(white: 0.68, alpha: 1.0)
            ]
            NSString(string: "WAITCAM 35MM CONTACT SHEET // \(roll.title.uppercased())")
                .draw(at: CGPoint(x: sidePad, y: 56), withAttributes: titleAttr)
            NSString(string: "\(roll.filmStock.displayName) · \(roll.duration.detailLabel) · \(photos.count) EXP")
                .draw(at: CGPoint(x: sidePad, y: 110), withAttributes: subAttr)

            let frameLabelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(red: 1.0, green: 0.65, blue: 0.28, alpha: 0.9)
            ]

            for (idx, photo) in photos.enumerated() {
                let col = idx % columns
                let row = idx / columns
                let x = sidePad + CGFloat(col) * (cellW + gutter)
                let y = topHeader + CGFloat(row) * (cellH + rowSpacing)
                let targetRect = CGRect(x: x, y: y, width: cellW, height: cellH)

                cg.saveGState()
                UIBezierPath(roundedRect: targetRect, cornerRadius: 6).addClip()
                drawAspectFill(photo, in: targetRect)
                cg.restoreGState()

                NSString(string: String(format: "%02dA", idx + 1))
                    .draw(at: CGPoint(x: x + 4, y: y + cellH + 10), withAttributes: frameLabelAttr)
            }

            let footerText = "DEVELOPED LOCALLY AFTER \(roll.duration.badgeTitle) · ZERO CLOUD UPLOAD"
            NSString(string: footerText).draw(at: CGPoint(x: sidePad, y: height - 66), withAttributes: subAttr)
        }

        return sheet.jpegData(compressionQuality: 0.92)
    }

    /// Generates a viral 9:16 (1080x1920) 35mm sprocket-hole film Reel MP4 video (Lapse 5★ feature)
    /// with subtle analog film border code ("SHOT ON WAITCAM · 35MM DARKROOM") for organic social sharing.
    public func render35mmReelVideo(photos: [UIImage], roll: DarkroomRoll, outputURL: URL) async throws -> URL {
        guard !photos.isEmpty else { throw FilmLabError.invalidInputImage }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let width = 720
        let height = 1280
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attrs)
        guard writer.canAdd(input) else { throw FilmLabError.encodingFailed }
        writer.add(input)

        guard writer.startWriting() else { throw FilmLabError.encodingFailed }
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 12
        let framesPerPhoto = 8 // ~0.67s snappy party disposable montage per shot
        var frameIndex: Int64 = 0

        for (idx, photo) in photos.prefix(12).enumerated() {
            let frameUIImage = renderReelFrame(photo: photo, roll: roll, shotIndex: idx + 1, totalShots: photos.count, size: CGSize(width: width, height: height))
            guard let pb = makePixelBuffer(from: frameUIImage, width: width, height: height) else {
                throw FilmLabError.encodingFailed
            }
            for _ in 0..<framesPerPhoto {
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                let time = CMTime(value: frameIndex, timescale: fps)
                if !adaptor.append(pb, withPresentationTime: time) {
                    throw FilmLabError.encodingFailed
                }
                frameIndex += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FilmLabError.encodingFailed
        }
        return outputURL
    }

    private func renderReelFrame(photo: UIImage, roll: DarkroomRoll, shotIndex: Int, totalShots: Int, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // 35mm film sprocket holes along left & right edges
            UIColor(red: 0.13, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
            var y: CGFloat = 28
            while y < size.height - 28 {
                UIBezierPath(roundedRect: CGRect(x: 16, y: y, width: 18, height: 26), cornerRadius: 4).fill()
                UIBezierPath(roundedRect: CGRect(x: size.width - 34, y: y, width: 18, height: 26), cornerRadius: 4).fill()
                y += 52
            }

            // Top analog film edge code (natural word-of-mouth stamp)
            let edgeAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .bold),
                .foregroundColor: UIColor(red: 1.0, green: 0.50, blue: 0.18, alpha: 0.95)
            ]
            NSString(string: "WAITCAM 35MM // \(roll.filmStock.shortCode)")
                .draw(at: CGPoint(x: 54, y: 62), withAttributes: edgeAttr)

            let photoRect = CGRect(x: 54, y: 120, width: size.width - 108, height: (size.width - 108) * (4.0 / 3.0))
            cg.saveGState()
            UIBezierPath(roundedRect: photoRect, cornerRadius: 10).addClip()
            drawAspectFill(photo, in: photoRect)
            cg.restoreGState()

            let subAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(white: 0.72, alpha: 1.0)
            ]
            NSString(string: String(format: "FRAME %02d/%02d · DEVELOPED IN %@ DARKROOM", shotIndex, totalShots, roll.duration.rawValue.uppercased()))
                .draw(at: CGPoint(x: 54, y: photoRect.maxY + 28), withAttributes: subAttr)
        }
    }

    private func makePixelBuffer(from image: UIImage, width: Int, height: Int) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        var pxBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            nil,
            &pxBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pxBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }

        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private func drawAspectFill(_ image: UIImage, in rect: CGRect) {
        let imgSize = image.size
        guard imgSize.width > 0, imgSize.height > 0 else { return }
        let scale = max(rect.width / imgSize.width, rect.height / imgSize.height)
        let drawSize = CGSize(width: imgSize.width * scale, height: imgSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
    }
}
