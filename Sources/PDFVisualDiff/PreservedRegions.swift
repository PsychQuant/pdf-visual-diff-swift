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
    /// How far a region may reach past the page edge and still count as on
    /// the page: half of 0.01 bp, so a page size printed to two decimals
    /// (595.28 for 595.2756) can be typed back as a region.
    public static let pageEdgeSlack = 0.005

    /// `rects` are in bp with a top-left origin. A rectangle with a
    /// non-finite coordinate or no area is refused.
    public static func check(_ rects: [CGRect], diff: SignedDiff) throws -> [PreservedRegionResult] {
        let s = diff.scale
        return try rects.enumerated().map { index, given in
            let edges = [given.origin.x, given.origin.y, given.size.width, given.size.height]
            guard edges.allSatisfy(\.isFinite), given.size.width > 0, given.size.height > 0 else {
                throw PDFVisualDiffError.invalidRegion(index: index)
            }
            // A right or bottom edge within the slack past the page edge is
            // taken as the page edge, so the raster's own edge cannot veto it.
            var rect = given
            let pageWidth = Double(diff.pageSize.width), pageHeight = Double(diff.pageSize.height)
            if rect.minX < pageWidth, rect.maxX > pageWidth, rect.maxX <= pageWidth + Self.pageEdgeSlack {
                rect.size.width = pageWidth - rect.minX
            }
            if rect.minY < pageHeight, rect.maxY > pageHeight, rect.maxY <= pageHeight + Self.pageEdgeSlack {
                rect.size.height = pageHeight - rect.minY
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
                && rect.maxX <= Double(diff.pageSize.width) + Self.pageEdgeSlack
                && rect.maxY <= Double(diff.pageSize.height) + Self.pageEdgeSlack
                && rect.maxX * s <= Double(diff.width) && rect.maxY * s <= Double(diff.height)
            if !insideCompared {
                // The part past the shared page counts as unchecked even where
                // the rounded-up raster has pixels for it.
                let pageWidth = Double(diff.pageSize.width) * s, pageHeight = Double(diff.pageSize.height) * s
                let onPage = max(0, min(rect.maxX * s, pageWidth) - max(rect.minX * s, 0))
                    * max(0, min(rect.maxY * s, pageHeight) - max(rect.minY * s, 0))
                let past = (rect.width * s) * (rect.height * s) - onPage
                let pastPixels = past.isFinite ? Int(min(max(1, past.rounded(.up)), Self.uncheckedCap)) : Int(Self.uncheckedCap)
                unchecked = max(unchecked, pastPixels)
            }
            return PreservedRegionResult(index: index, left: given.minX, top: given.minY,
                                         right: given.maxX, bottom: given.maxY, changedPixels: changed,
                                         uncheckedPixels: unchecked)
        }
    }
}
