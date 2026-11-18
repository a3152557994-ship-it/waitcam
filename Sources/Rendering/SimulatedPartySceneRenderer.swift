import CoreGraphics
import Foundation
import UIKit

/// Generates crisp nocturnal party snapshots for iOS Simulator previews and XCTest verification
/// where no physical rear camera sensor is attached.
public enum SimulatedPartySceneRenderer {
    public static func renderPartySnapshotCGImage(
        size: CGSize = CGSize(width: 1200, height: 1600),
        frameNumber: Int = 1,
        flashOn: Bool = true
    ) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // Deep midnight club gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: 0.05, green: 0.04, blue: 0.11, alpha: 1.0).cgColor,
                UIColor(red: 0.12, green: 0.05, blue: 0.16, alpha: 1.0).cgColor,
                UIColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1.0).cgColor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.55, 1.0]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // Shifting neon bokeh lights by frame number
            let shift = CGFloat((frameNumber * 73) % 240)
            let bokehSpecs: [(CGPoint, CGFloat, UIColor)] = [
                (CGPoint(x: size.width * 0.22 + shift * 0.3, y: size.height * 0.24), 140, UIColor(red: 1.0, green: 0.28, blue: 0.42, alpha: 0.45)),
                (CGPoint(x: size.width * 0.78 - shift * 0.25, y: size.height * 0.28), 165, UIColor(red: 0.18, green: 0.76, blue: 1.0, alpha: 0.42)),
                (CGPoint(x: size.width * 0.55, y: size.height * 0.16), 95, UIColor(red: 1.0, green: 0.72, blue: 0.22, alpha: 0.50)),
                (CGPoint(x: size.width * 0.18, y: size.height * 0.58), 120, UIColor(red: 0.88, green: 0.34, blue: 0.96, alpha: 0.35))
            ]

            for (center, radius, color) in bokehSpecs {
                let bokehColors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
                if let rad = CGGradient(colorsSpace: colorSpace, colors: bokehColors, locations: [0.0, 1.0]) {
                    cg.drawRadialGradient(
                        rad,
                        startCenter: center,
                        startRadius: 4,
                        endCenter: center,
                        endRadius: radius,
                        options: []
                    )
                }
            }

            // Flash-lit foreground subject silhouette + warm skin/champagne glass card
            if flashOn {
                let flashCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
                let flashColors = [
                    UIColor(red: 1.0, green: 0.96, blue: 0.88, alpha: 0.38).cgColor,
                    UIColor(red: 1.0, green: 0.88, blue: 0.72, alpha: 0.0).cgColor
                ] as CFArray
                if let flashGrad = CGGradient(colorsSpace: colorSpace, colors: flashColors, locations: [0.0, 1.0]) {
                    cg.drawRadialGradient(
                        flashGrad,
                        startCenter: flashCenter,
                        startRadius: 20,
                        endCenter: flashCenter,
                        endRadius: size.width * 0.55,
                        options: []
                    )
                }
            }

            // Stylized neon sign "2AM CLUB" inside scene
            let neonBox = CGRect(
                x: size.width * 0.22,
                y: size.height * 0.39,
                width: size.width * 0.56,
                height: 150
            )
            UIColor(red: 1.0, green: 0.36, blue: 0.18, alpha: 0.85).setStroke()
            let border = UIBezierPath(roundedRect: neonBox, cornerRadius: 22)
            border.lineWidth = 6
            border.stroke()

            let signAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 58, weight: .black),
                .foregroundColor: UIColor(red: 1.0, green: 0.92, blue: 0.75, alpha: 0.95)
            ]
            let signText = NSString(string: String(format: "2AM PARTY #%02d", frameNumber))
            let signSize = signText.size(withAttributes: signAttr)
            signText.draw(
                at: CGPoint(x: neonBox.midX - signSize.width / 2, y: neonBox.midY - signSize.height / 2),
                withAttributes: signAttr
            )

            // Foreground film table / glass glint
            UIColor(white: 0.14, alpha: 0.95).setFill()
            cg.fill(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28))

            let cupRect = CGRect(x: size.width * 0.42, y: size.height * 0.62, width: 150, height: 220)
            UIColor(red: 0.98, green: 0.78, blue: 0.34, alpha: 0.85).setFill()
            UIBezierPath(roundedRect: cupRect, cornerRadius: 26).fill()
            UIColor(white: 1.0, alpha: flashOn ? 0.72 : 0.25).setFill()
            UIBezierPath(roundedRect: CGRect(x: cupRect.minX + 16, y: cupRect.minY + 18, width: 22, height: 150), cornerRadius: 10).fill()

            _ = rect
        }

        return image.cgImage!
    }
}
