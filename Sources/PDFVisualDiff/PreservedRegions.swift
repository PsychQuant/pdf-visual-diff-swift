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
    /// The largest unchecked-pixel count reported; larger areas saturate here.
    static let uncheckedCap = 4_611_686_018_427_387_904.0  // 2^62

    /// `rects` are in bp with a top-left origin. A rectangle with a
    /// non-finite coordinate or no area is refused.
    public static func check(_ rects: [CGRect], diff: SignedDiff) throws -> [PreservedRegionResult] {
        let s = diff.scale
        return try rects.enumerated().map { index, rect in
            let edges = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
            guard edges.allSatisfy(\.isFinite), rect.size.width > 0, rect.size.height > 0 else {
                throw PDFVisualDiffError.invalidRegion(index: index)
            }
            // Pixel edges in Double: a region far off the page keeps its true
            // size here, so it can never collapse to an empty, passing region.
            let px0 = (rect.minX * s).rounded(.down), py0 = (rect.minY * s).rounded(.down)
            let px1 = (rect.maxX * s).rounded(.up), py1 = (rect.maxY * s).rounded(.up)
            guard [px0, py0, px1, py1].allSatisfy(\.isFinite) else {
                throw PDFVisualDiffError.invalidRegion(index: index)
            }
            let x0 = Int(max(0, min(Double(diff.width), px0))), y0 = Int(max(0, min(Double(diff.height), py0)))
            let x1 = Int(max(0, min(Double(diff.width), px1))), y1 = Int(max(0, min(Double(diff.height), py1)))
            var changed = 0, checked = 0
            if x0 < x1 && y0 < y1 {
                checked = (x1 - x0) * (y1 - y0)
                for y in y0..<y1 {
                    for x in x0..<x1 where diff.isChanged(x: x, y: y) { changed += 1 }
                }
            }
            // The area can exceed Int (or even Double) range; 2^62 is a cap
            // that converts to Int exactly, unlike Double(Int.max) = 2^63.
            let area = (px1 - px0) * (py1 - py0)
            var unchecked = area == Double(checked) ? 0 : Int(min(max(1, area - Double(checked)), Self.uncheckedCap))
            // Decided in bp, not from pixel arithmetic: far away, floating
            // point can lose a region's width entirely, and the rasters round
            // up past the page edge, but a region that is not wholly on the
            // page area both documents share can never pass.
            let insideCompared = rect.minX >= 0 && rect.minY >= 0
                && rect.maxX <= Double(diff.pageSize.width) && rect.maxY <= Double(diff.pageSize.height)
                && rect.maxX * s <= Double(diff.width) && rect.maxY * s <= Double(diff.height)
            if !insideCompared { unchecked = max(1, unchecked) }
            return PreservedRegionResult(index: index, left: rect.minX, top: rect.minY,
                                         right: rect.maxX, bottom: rect.maxY, changedPixels: changed,
                                         uncheckedPixels: unchecked)
        }
    }
}
