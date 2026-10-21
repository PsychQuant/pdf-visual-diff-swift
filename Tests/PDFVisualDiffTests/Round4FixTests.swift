import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

/// Fixes from the fourth verification round of PsychQuant/macdoc#240.
struct Round4FixTests {

    private func diff() throws -> SignedDiff {
        let a = try PageRaster.render(url: SyntheticPDF.make(size: SyntheticPDF.a4, []), pageIndex: 0, dpi: 72)
        return try SignedDiff(original: a, output: a)
    }

    @Test("a region so far away that its width vanishes in floating point still fails")
    func farRegionKeepsFailing() throws {
        let result = try #require(try PreservedRegions.check([CGRect(x: 1e17, y: 1e17, width: 1, height: 1)], diff: diff()).first)
        #expect(result.uncheckedPixels > 0)
        #expect(!result.passed)
    }

    @Test("a resolution below 1 dpi is refused by rendering and by the raster initializer", arguments: [1e-320, 0.5])
    func tinyResolution(dpi: Double) throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [])
        #expect(throws: PDFVisualDiffError.invalidResolution(dpi)) { try PageRaster.render(url: url, pageIndex: 0, dpi: dpi) }
        #expect(throws: PDFVisualDiffError.invalidResolution(dpi)) {
            try PageRaster(width: 1, height: 1, dpi: dpi, pageSize: CGSize(width: 1, height: 1), pixels: [255, 255, 255])
        }
    }

    @Test("a page with an extreme aspect ratio is still checked for off-page ink")
    func extremeAspectRatio() throws {
        let url = try SyntheticPDF.make(size: CGSize(width: 2, height: 14_000), [])
        #expect(try PageGeometry.inkOutsideCropBox(page: PageRaster.page(url: url, index: 0)) == 0)
    }

    @Test("an artifact path collides with a protected file by case or through a linked directory, even before it exists")
    func artifactCollision() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("collide-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let link = dir.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir)
        let output = dir.appendingPathComponent("REPORT.JSON")
        #expect(DiffArtifacts.collision(in: dir, with: [(output, "output")])?.role == "output")
        #expect(DiffArtifacts.collision(in: link, with: [(dir.appendingPathComponent("report.json"), "output")])?.role == "output")
        #expect(DiffArtifacts.collision(in: dir, with: [(dir.appendingPathComponent("other.pdf"), "output")]) == nil)
    }
}
