import AppKit
import Foundation

extension NSImage {
    func resizedToThumbnail(maxWidth: CGFloat = 200) -> Data? {
        let originalSize = size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let targetSize: NSSize
        if originalSize.width <= maxWidth {
            targetSize = originalSize
        } else {
            let scale = maxWidth / originalSize.width
            targetSize = NSSize(
                width: maxWidth,
                height: originalSize.height * scale
            )
        }

        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let rep = bitmapRep,
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
