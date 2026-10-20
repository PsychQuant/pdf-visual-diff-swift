import CoreGraphics
import Foundation
import ImageIO
import PDFVisualDiff
import Testing

struct DiffArtifactsTests {

    private func squareDiff() throws -> OverlayVerification {
        let original = try PageRaster.render(url: SyntheticPDF.make(size: SyntheticPDF.a4, []), pageIndex: 0, dpi: 72)
        let output = try PageRaster.render(
            url: SyntheticPDF.make(size: SyntheticPDF.a4, [.fill(CGRect(x: 10, y: 10, width: 20, height: 20))]),
            pageIndex: 0, dpi: 72)
        return try OverlayVerifier.verify(original: original, output: output, overlay: output)
    }

    private func newDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("diff-artifacts-\(UUID().uuidString)", isDirectory: true)
    }

    private func pngPixel(_ url: URL, x: Int, y: Int) throws -> [UInt8] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let i = (y * image.width + x) * 4
        return [data[i], data[i + 1], data[i + 2]]
    }

    @Test("diff.bin reads back to the in-memory D using the dimensions in report.json")
    func rawRoundTrip() throws {
        let verification = try squareDiff()
        let dir = newDirectory()
        try DiffArtifacts.write(diff: verification.diff, checks: verification.report.checks, to: dir)

        let report = try JSONDecoder().decode(DiffArtifactReport.self, from: Data(contentsOf: dir.appendingPathComponent("report.json")))
        #expect(report.width == verification.diff.width)
        #expect(report.height == verification.diff.height)
        #expect(report.dpi == 72)
        #expect(report.changedPixelCount == 20 * 20)
        #expect(report.overlayChecks?.count == OverlayCheck.allCases.count)

        let raw = try Data(contentsOf: dir.appendingPathComponent("diff.bin"))
        #expect(raw.count == report.width * report.height * 3 * 2)
        let decoded: [Int16] = stride(from: 0, to: raw.count, by: 2).map { i in
            Int16(bitPattern: UInt16(raw[i]) | UInt16(raw[i + 1]) << 8)
        }
        #expect(decoded == verification.diff.values)
    }

    @Test("the two PNG views map D to 128 + D/2 and 255 - |D|")
    func pngViews() throws {
        let verification = try squareDiff()
        let dir = newDirectory()
        try DiffArtifacts.write(diff: verification.diff, checks: verification.report.checks, to: dir)
        let signed = dir.appendingPathComponent("diff_signed.png")
        let absolute = dir.appendingPathComponent("diff_abs.png")
        // Inside the square D = -255: floor(128 - 127.5) = 0 and 255 - 255 = 0.
        #expect(try pngPixel(signed, x: 20, y: 20) == [0, 0, 0])
        #expect(try pngPixel(absolute, x: 20, y: 20) == [0, 0, 0])
        // Outside it D = 0: 128 and 255.
        #expect(try pngPixel(signed, x: 100, y: 100) == [128, 128, 128])
        #expect(try pngPixel(absolute, x: 100, y: 100) == [255, 255, 255])
    }

    @Test("writing into a path that is a file fails with an error naming it")
    func unwritable() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-dir-\(UUID().uuidString)")
        try Data("x".utf8).write(to: file)
        let verification = try squareDiff()
        #expect(throws: PDFVisualDiffError.self) {
            try DiffArtifacts.write(diff: verification.diff, checks: verification.report.checks, to: file)
        }
    }
}
