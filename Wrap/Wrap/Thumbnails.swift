import AppKit
import ImageIO
import SwiftData

enum Thumbnails {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    static func image(for shot: Shot, size: CGFloat) -> NSImage? {
        guard let data = shot.referenceImage else { return nil }
        let key = "\(shot.persistentModelID.hashValue)-\(data.count)-\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = downsample(data, maxPixel: size * 2) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
