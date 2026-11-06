// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ImageIO

/// Looks at the wallpaper right around the notch to tell whether it's light or dark, so the
/// glow and the opening animation can use colours that show up on it. White light on a white
/// wallpaper is invisible; dark ink with coloured halos isn't.
enum BackdropProbe {
    /// The screen with the notch, or the main screen.
    @MainActor
    static var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    @MainActor
    static func wallpaperURL() -> URL? {
        guard let screen else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    /// How bright the top middle of the wallpaper is (where the notch sits), 0…1. Nil when the
    /// wallpaper can't be read, like some of Apple's moving wallpapers.
    static func brightness(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else { return nil }

        // The middle 40% of the top 8%: the menu bar around the notch.
        let band = CGRect(x: Int(Double(image.width) * 0.3), y: 0,
                          width: max(1, Int(Double(image.width) * 0.4)),
                          height: max(1, Int(Double(image.height) * 0.08)))
        guard let crop = image.cropping(to: band) else { return nil }

        let width = 24, height = 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            total += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
        return total / Double(width * height)
    }
}
