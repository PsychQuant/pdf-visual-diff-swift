import CoreGraphics
import Foundation

public struct PreservedRegionResult: Codable, Equatable, Sendable {
    public let index: Int
    /// Left, top, right, bottom in bp with a top-left origin.
    public let left: Double
    public let top: Double
    public let right: Double
    public let bottom: Double
    public let changedPixels: Int
    /// Pixels of the region outside the compared area (beyond either page or
    /// at negative coordinates). They were never compared, so a region with
    /// any of them cannot pass.
    public let uncheckedPixels: Int

    public var passed: Bool { changedPixels == 0 && uncheckedPixels == 0 }
}

/// Regions that must come out unchanged: D has to be 0 in every channel of
/// every pixel that touches the rectangle, even partly, and every such pixel
/// has to lie inside the compared area.
public enum PreservedRegions {
    /// `rects` are in bp with a top-left origin. A rectangle with a
    /// non-finite coordinate or no area is refused.
    public static func check(_ rects: [CGRect], diff: SignedDiff) throws -> [PreservedRegionResult] {
        let s = diff.scale
        // Pixel indices this far out are never in a bitmap; clamping first
        // keeps the Int conversion in range for any finite input.
        let limit = Double(PageRaster.maxPixelCount)
        func pixel(_ value: Double, _ rule: FloatingPointRoundingRule) -> Int {
            Int(max(-limit, min(limit, (value * s).rounded(rule))))
        }
        return try rects.enumerated().map { index, rect in
            let edges = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
            guard edges.allSatisfy(\.isFinite), rect.size.width > 0, rect.size.height > 0 else {
                throw PDFVisualDiffError.invalidRegion(index: index)
            }
            let px0 = pixel(rect.minX, .down), py0 = pixel(rect.minY, .down)
            let px1 = pixel(rect.maxX, .up), py1 = pixel(rect.maxY, .up)
            let x0 = max(0, px0), y0 = max(0, py0)
            let x1 = min(diff.width, px1), y1 = min(diff.height, py1)
            var changed = 0, checked = 0
            if x0 < x1 && y0 < y1 {
                checked = (x1 - x0) * (y1 - y0)
                for y in y0..<y1 {
                    for x in x0..<x1 where diff.isChanged(x: x, y: y) { changed += 1 }
                }
            }
            return PreservedRegionResult(index: index, left: rect.minX, top: rect.minY,
                                         right: rect.maxX, bottom: rect.maxY, changedPixels: changed,
                                         uncheckedPixels: (px1 - px0) * (py1 - py0) - checked)
        }
    }
}
