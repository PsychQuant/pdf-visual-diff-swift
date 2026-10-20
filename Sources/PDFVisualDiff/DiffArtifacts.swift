import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What report.json holds.
public struct DiffArtifactReport: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let dpi: Double
    public let changedPixelCount: Int
    public let channelMin: [Int16]
    public let channelMax: [Int16]
    /// The identity check's result, when it ran: the two pages have the same
    /// raster size and no pixel differs.
    public let identical: Bool?
    public let overlayChecks: [CheckResult]?
    public let preservedRegions: [PreservedRegionResult]?
    /// Layout of diff.bin.
    public let rawFormat: String
}

/// Writes a difference to disk in forms a person and a program can read:
///
/// - `diff_signed.png`: each channel is floor(128 + D/2) clamped to 0…255, so
///   mid-grey means unchanged, darker means that channel got darker.
/// - `diff_abs.png`: each channel is 255 − |D|, so white means unchanged.
/// - `diff.bin`: D as little-endian Int16, row-major height × width × 3, no header.
/// - `report.json`: dimensions, resolution, counts and the checks that ran.
public enum DiffArtifacts {
    public static let rawFormat = "int16-le, row-major height x width x 3 (R,G,B), D = output - original"

    /// Pass the results of the checks that ran: `checks` for an overlay,
    /// `preserved` for preserved regions, `identical` for the identity check.
    public static func write(diff: SignedDiff, checks: [CheckResult]? = nil,
                             preserved: [PreservedRegionResult]? = nil, identical: Bool? = nil,
                             to directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PDFVisualDiffError.artifactWriteFailed("\(directory.path): \(error.localizedDescription)")
        }
        let count = diff.width * diff.height
        var signed = [UInt8](repeating: 0, count: count * 3)
        var absolute = [UInt8](repeating: 0, count: count * 3)
        var raw = Data(capacity: count * 6)
        for (i, d) in diff.values.enumerated() {
            signed[i] = UInt8(max(0, min(255, (128.0 + Double(d) / 2).rounded(.down))))
            absolute[i] = UInt8(255 - Int(abs(Int(d))))
            let bits = UInt16(bitPattern: d)
            raw.append(UInt8(bits & 0xFF))
            raw.append(UInt8(bits >> 8))
        }
        try writePNG(signed, width: diff.width, height: diff.height, to: directory.appendingPathComponent("diff_signed.png"))
        try writePNG(absolute, width: diff.width, height: diff.height, to: directory.appendingPathComponent("diff_abs.png"))

        let report = DiffArtifactReport(width: diff.width, height: diff.height, dpi: diff.dpi,
                                        changedPixelCount: diff.changedPixelCount, channelMin: diff.channelMin,
                                        channelMax: diff.channelMax, identical: identical, overlayChecks: checks,
                                        preservedRegions: preserved, rawFormat: rawFormat)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try raw.write(to: directory.appendingPathComponent("diff.bin"))
            try encoder.encode(report).write(to: directory.appendingPathComponent("report.json"))
        } catch {
            throw PDFVisualDiffError.artifactWriteFailed("\(directory.path): \(error.localizedDescription)")
        }
    }

    private static func writePNG(_ rgb: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let provider = CGDataProvider(data: Data(rgb) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw PDFVisualDiffError.artifactWriteFailed(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PDFVisualDiffError.artifactWriteFailed(url.path)
        }
    }
}
