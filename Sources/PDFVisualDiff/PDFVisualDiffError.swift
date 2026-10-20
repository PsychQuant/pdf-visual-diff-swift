import Foundation

/// Errors raised by PDFVisualDiff. Every case names what went wrong so a
/// caller can show it as-is.
public enum PDFVisualDiffError: Error, Equatable, CustomStringConvertible {
    case unreadablePDF(String)
    case pageOutOfRange(index: Int, pageCount: Int)
    case unsupportedRotation(degrees: Int)
    case invalidResolution(Double)
    case bitmapContextUnavailable(width: Int, height: Int)
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
            return "resolution must be a positive finite number of dpi, got \(dpi)"
        case let .bitmapContextUnavailable(width, height):
            return "cannot allocate a \(width)×\(height) bitmap"
        case .sizeMismatch(let detail):
            return "rasters do not line up: \(detail)"
        case .inkInRemovedStrip(let pixels):
            return "the strip removed by A4 normalization contains \(pixels) inked pixel\(pixels == 1 ? "" : "s"); refusing to crop content"
        case .artifactWriteFailed(let detail):
            return "cannot write diff artifacts: \(detail)"
        }
    }
}
