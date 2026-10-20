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

    public var passed: Bool { changedPixels == 0 }
}

/// Regions that must come out unchanged: D has to be 0 in every channel of
/// every pixel that touches the rectangle, even partly.
public enum PreservedRegions {
    /// `rects` are in bp with a top-left origin.
    public static func check(_ rects: [CGRect], diff: SignedDiff) -> [PreservedRegionResult] {
        let s = diff.scale
        return rects.enumerated().map { index, rect in
            let x0 = max(0, Int((rect.minX * s).rounded(.down)))
            let y0 = max(0, Int((rect.minY * s).rounded(.down)))
            let x1 = min(diff.width, Int((rect.maxX * s).rounded(.up)))
            let y1 = min(diff.height, Int((rect.maxY * s).rounded(.up)))
            var changed = 0
            if x0 < x1 && y0 < y1 {
                for y in y0..<y1 {
                    for x in x0..<x1 where diff.isChanged(x: x, y: y) { changed += 1 }
                }
            }
            return PreservedRegionResult(index: index, left: rect.minX, top: rect.minY,
                                         right: rect.maxX, bottom: rect.maxY, changedPixels: changed)
        }
    }
}
