import Foundation

/// The five checks that decide whether an overlay was added without touching
/// the original, and was added in full.
public enum OverlayCheck: String, Codable, CaseIterable, Sendable {
    /// The overlay render is pure white at a pixel, yet the output differs
    /// from the original there. Where the output is larger than the original,
    /// any output ink the overlay does not account for counts.
    case differenceOutsideOverlay
    /// D > 0 in some channel: ink of the original was covered or removed.
    case originalMadeLighter
    /// Overlay and original both have ink at the same pixel. D is near 0
    /// at such pixels (black on black), so the difference alone hides them.
    case overlayInkOnOriginalInk
    /// The original has ink outside the output's size (cropped away).
    case inkInCroppedStrip
    /// The overlay has ink at a pixel that lies outside the output, or where
    /// the original is white or absent and the output does not show exactly
    /// the overlay's colour: the typed text did not reach the output, or
    /// reached it faint or in another colour.
    case overlayMissingFromOutput
}

public struct CheckResult: Codable, Equatable, Sendable {
    public let check: OverlayCheck
    public let count: Int
    public let bands: [Band]
}

public struct OverlayReport: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let dpi: Double
    public let changedPixelCount: Int
    public let channelMin: [Int16]
    public let channelMax: [Int16]
    public let checks: [CheckResult]

    /// True only when every check counts 0 pixels.
    public var passed: Bool { checks.allSatisfy { $0.count == 0 } }

    public func result(for check: OverlayCheck) -> CheckResult {
        checks.first { $0.check == check } ?? CheckResult(check: check, count: 0, bands: [])
    }
}

public struct OverlayVerification: Sendable {
    public let diff: SignedDiff
    public let report: OverlayReport
}

public enum OverlayVerifier {
    /// Compares `output` with `original`, using `overlay` (the overlay
    /// rendered alone on white, same resolution) to tell intended changes
    /// from everything else. All three are aligned at their top-left corner.
    public static func verify(original: PageRaster, output: PageRaster, overlay: PageRaster) throws -> OverlayVerification {
        guard overlay.dpi == original.dpi else {
            throw PDFVisualDiffError.sizeMismatch("overlay rendered at \(overlay.dpi) dpi, original at \(original.dpi) dpi")
        }
        let diff = try SignedDiff(original: original, output: output)
        let w = diff.width, h = diff.height, scale = diff.scale

        func overlayInk(_ x: Int, _ y: Int) -> Bool {
            x < overlay.width && y < overlay.height && !overlay.isWhite(x: x, y: y)
        }
        // Over the output's whole area: inside the common region D decides,
        // beyond it (output larger than the original) any output ink does.
        let outside: (Int, Int) -> Bool = { x, y in
            guard !overlayInk(x, y) else { return false }
            return x < w && y < h ? diff.isChanged(x: x, y: y) : !output.isWhite(x: x, y: y)
        }
        let lighter: (Int, Int) -> Bool = { x, y in
            let i = (y * w + x) * 3
            return diff.values[i] > 0 || diff.values[i + 1] > 0 || diff.values[i + 2] > 0
        }
        let inkOnInk: (Int, Int) -> Bool = { x, y in overlayInk(x, y) && !original.isWhite(x: x, y: y) }

        func result(_ check: OverlayCheck, width: Int, height: Int, _ flagged: (Int, Int) -> Bool) -> CheckResult {
            let bands = Band.bands(width: width, height: height, scale: scale, flagged: flagged)
            return CheckResult(check: check, count: bands.reduce(0) { $0 + $1.pixels }, bands: bands)
        }

        // Original ink that falls outside the common region.
        let cropped = result(.inkInCroppedStrip, width: original.width, height: original.height) { x, y in
            (x >= w || y >= h) && !original.isWhite(x: x, y: y)
        }

        // Over the overlay's whole area. Where the original is blank, the
        // overlay composited onto it is the overlay's own render, so the
        // output has to match it exactly.
        let missing: (Int, Int) -> Bool = { x, y in
            guard !overlay.isWhite(x: x, y: y) else { return false }
            guard x < output.width, y < output.height else { return true }
            let originalWhite = x >= original.width || y >= original.height || original.isWhite(x: x, y: y)
            return originalWhite && output.rgb(x: x, y: y) != overlay.rgb(x: x, y: y)
        }

        let checks = [
            result(.differenceOutsideOverlay, width: output.width, height: output.height, outside),
            result(.originalMadeLighter, width: w, height: h, lighter),
            result(.overlayInkOnOriginalInk, width: w, height: h, inkOnInk),
            cropped,
            result(.overlayMissingFromOutput, width: overlay.width, height: overlay.height, missing),
        ]
        let report = OverlayReport(width: w, height: h, dpi: diff.dpi, changedPixelCount: diff.changedPixelCount,
                                   channelMin: diff.channelMin, channelMax: diff.channelMax, checks: checks)
        return OverlayVerification(diff: diff, report: report)
    }
}
