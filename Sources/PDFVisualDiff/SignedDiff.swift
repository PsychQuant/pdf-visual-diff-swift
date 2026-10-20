import Foundation

/// D = output − original, for every pixel and every RGB channel, as a signed
/// value in −255…255.
///
/// Both rasters are aligned at their top-left corner and compared over their
/// common width and height. No threshold, binarization or morphology is ever
/// applied: a single differing channel of a single pixel is a change.
public struct SignedDiff: Sendable {
    public let width: Int
    public let height: Int
    public let dpi: Double
    /// Row-major, top row first: `values[(y * width + x) * 3 + c]`.
    public let values: [Int16]
    /// Pixels with a non-zero difference in at least one channel.
    public let changedPixelCount: Int
    /// Per-channel minimum of D (R, G, B) over every compared pixel.
    public let channelMin: [Int16]
    /// Per-channel maximum of D (R, G, B) over every compared pixel.
    public let channelMax: [Int16]
    /// True when both pages have the same size in bp and both rasters the
    /// same width and height. When they differ, pixels outside the common
    /// region exist on one side only and D says nothing about them; a page
    /// size difference smaller than a pixel would not show in D at all.
    public let sizesMatch: Bool

    public init(original: PageRaster, output: PageRaster) throws {
        guard original.dpi == output.dpi else {
            throw PDFVisualDiffError.sizeMismatch("original rendered at \(original.dpi) dpi, output at \(output.dpi) dpi")
        }
        let width = min(original.width, output.width)
        let height = min(original.height, output.height)
        var values = [Int16](repeating: 0, count: width * height * 3)
        var changed = 0
        // PageRaster guarantees at least one pixel, so the common region is
        // never empty and the extremes start from the first compared pixel.
        var low: [Int16] = [.max, .max, .max]
        var high: [Int16] = [.min, .min, .min]
        for y in 0..<height {
            let rowA = y * original.width * 3
            let rowB = y * output.width * 3
            let rowD = y * width * 3
            for x in 0..<width {
                var any = false
                for c in 0..<3 {
                    let d = Int16(output.pixels[rowB + x * 3 + c]) - Int16(original.pixels[rowA + x * 3 + c])
                    values[rowD + x * 3 + c] = d
                    if d != 0 { any = true }
                    if d < low[c] { low[c] = d }
                    if d > high[c] { high[c] = d }
                }
                if any { changed += 1 }
            }
        }
        self.width = width
        self.height = height
        self.dpi = original.dpi
        self.values = values
        self.changedPixelCount = changed
        self.channelMin = low
        self.channelMax = high
        self.sizesMatch = original.width == output.width && original.height == output.height
            && original.pageSize == output.pageSize
    }

    /// Bitmap pixels per bp.
    public var scale: Double { dpi / 72 }

    /// D of the three channels at one pixel.
    public func d(x: Int, y: Int) -> [Int16] {
        let i = (y * width + x) * 3
        return [values[i], values[i + 1], values[i + 2]]
    }

    public func isChanged(x: Int, y: Int) -> Bool {
        let i = (y * width + x) * 3
        return values[i] != 0 || values[i + 1] != 0 || values[i + 2] != 0
    }
}
