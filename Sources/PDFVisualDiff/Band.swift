import Foundation

/// A horizontal band of flagged pixels, reported in bp with a top-left
/// origin so it can be compared with positions on the printed page.
public struct Band: Codable, Equatable, Sendable {
    public let top: Double
    public let bottom: Double
    public let left: Double
    public let right: Double
    public let pixels: Int

    public init(top: Double, bottom: Double, left: Double, right: Double, pixels: Int) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
        self.pixels = pixels
    }

    /// Groups flagged pixels into horizontal bands. Rows that are more than
    /// `gap` pixels apart start a new band. This only shapes the report; the
    /// pixel counts are never reduced.
    static func bands(width: Int, height: Int, scale: Double, gap: Int = 6, flagged: (Int, Int) -> Bool) -> [Band] {
        var result: [Band] = []
        var start = -1, end = -1, minX = Int.max, maxX = -1, count = 0
        func close() {
            guard start >= 0 else { return }
            result.append(Band(top: Double(start) / scale, bottom: Double(end + 1) / scale,
                               left: Double(minX) / scale, right: Double(maxX + 1) / scale, pixels: count))
            start = -1; end = -1; minX = .max; maxX = -1; count = 0
        }
        for y in 0..<height {
            var rowCount = 0, rowMin = Int.max, rowMax = -1
            for x in 0..<width where flagged(x, y) {
                rowCount += 1
                if x < rowMin { rowMin = x }
                if x > rowMax { rowMax = x }
            }
            guard rowCount > 0 else { continue }
            if start >= 0 && y - end > gap { close() }
            if start < 0 { start = y }
            end = y
            count += rowCount
            minX = min(minX, rowMin)
            maxX = max(maxX, rowMax)
        }
        close()
        return result
    }
}
