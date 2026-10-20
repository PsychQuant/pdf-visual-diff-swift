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
///
/// Every file is written to a temporary name and renamed into place, so an
/// existing file or symbolic link of the same name is replaced, never
/// written through.
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
        try write(png(signed, width: diff.width, height: diff.height), to: directory.appendingPathComponent("diff_signed.png"))
        try write(png(absolute, width: diff.width, height: diff.height), to: directory.appendingPathComponent("diff_abs.png"))

        let report = DiffArtifactReport(width: diff.width, height: diff.height, dpi: diff.dpi,
                                        changedPixelCount: diff.changedPixelCount, channelMin: diff.channelMin,
                                        channelMax: diff.channelMax, identical: identical, overlayChecks: checks,
                                        preservedRegions: preserved, rawFormat: rawFormat)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(raw, to: directory.appendingPathComponent("diff.bin"))
        let json: Data
        do {
            json = try encoder.encode(report)
        } catch {
            throw PDFVisualDiffError.artifactWriteFailed("report.json: \(error.localizedDescription)")
        }
        try write(json, to: directory.appendingPathComponent("report.json"))
    }

    /// Atomic write: a temporary file in the same directory renamed over
    /// `url`, which replaces a symbolic link instead of following it.
    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PDFVisualDiffError.artifactWriteFailed("\(url.path): \(error.localizedDescription)")
        }
    }

    private static func png(_ rgb: [UInt8], width: Int, height: Int) throws -> Data {
        let data = NSMutableData()
        guard let provider = CGDataProvider(data: Data(rgb) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                                  bytesPerRow: width * 3, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else {
            throw PDFVisualDiffError.artifactWriteFailed("cannot encode a \(width)×\(height) PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PDFVisualDiffError.artifactWriteFailed("cannot encode a \(width)×\(height) PNG")
        }
        return data as Data
    }
}
