import Foundation

/// Errors raised by PDFVisualDiff. Every case names what went wrong so a
/// caller can show it as-is.
public enum PDFVisualDiffError: Error, Equatable, CustomStringConvertible {
    case unreadablePDF(String)
    case pageOutOfRange(index: Int, pageCount: Int)
    case unsupportedRotation(degrees: Int)
    case invalidResolution(Double)
    case bitmapContextUnavailable(width: Int, height: Int)
    case bitmapTooLarge(width: Double, height: Double, limit: Int)
    case invalidRegion(index: Int)
    case invalidRaster(width: Int, height: Int, bytes: Int)
    case invalidPageSize(width: Double, height: Double)
    case sizeMismatch(String)
    case inkInRemovedStrip(pixels: Int)
    case artifactWriteFailed(String)

    public var description: String {
        switch self {
        case .unreadablePDF(let path):
            return "cannot open PDF: \(path)"
        case let .pageOutOfRange(index, count):
            return "page index \(index) is outside the document (\(count) page\(count == 1 ? "" : "s"))"
        case .unsupportedRotation(let degrees):
            return "page rotation \(degrees)° is not supported; only unrotated pages can be compared"
        case .invalidResolution(let dpi):
            return "resolution must be between \(Int(PageRaster.minDPI)) and \(Int(PageRaster.maxDPI)) dpi, got \(dpi)"
        case let .bitmapContextUnavailable(width, height):
            return "cannot allocate a \(width)×\(height) bitmap"
        case let .bitmapTooLarge(width, height, limit):
            return "a \(width)×\(height) pixel bitmap exceeds the limit of \(limit) pixels; lower the resolution"
        case let .invalidRaster(width, height, bytes):
            return "a raster must be at least 1 × 1 pixel with width × height × 3 bytes; got \(width) × \(height) with \(bytes) bytes"
        case let .invalidPageSize(width, height):
            return "a page size must be positive and finite, got \(width) × \(height) bp"
        case .invalidRegion(let index):
            return "preserved region \(index) must have finite coordinates and edges, with left < right and top < bottom"
        case .sizeMismatch(let detail):
            return "rasters do not line up: \(detail)"
        case .inkInRemovedStrip(let pixels):
            return "the strip removed by A4 normalization contains \(pixels) inked pixel\(pixels == 1 ? "" : "s"); refusing to crop content"
        case .artifactWriteFailed(let detail):
            return "cannot write diff artifacts: \(detail)"
        }
    }
}
