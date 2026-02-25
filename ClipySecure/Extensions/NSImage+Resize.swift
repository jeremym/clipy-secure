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

        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        return pngData
    }
}
