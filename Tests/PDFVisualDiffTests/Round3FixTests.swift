import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

/// Fixes from the third verification round of PsychQuant/macdoc#240.
struct Round3FixTests {

    private func diff() throws -> SignedDiff {
        let a = try PageRaster.render(url: SyntheticPDF.make(size: SyntheticPDF.a4, []), pageIndex: 0, dpi: 72)
        return try SignedDiff(original: a, output: a)
    }

    @Test("a huge finite preserved region fails without trapping")
    func hugeRegion() throws {
        let result = try #require(try PreservedRegions.check([CGRect(x: 0, y: 0, width: 1e20, height: 1e20)], diff: diff()).first)
        #expect(result.uncheckedPixels > 0)
        #expect(!result.passed)
    }

    @Test("a region whose far edge overflows to infinity is refused")
    func overflowingRegion() throws {
        #expect(throws: PDFVisualDiffError.invalidRegion(index: 0)) {
            try PreservedRegions.check([CGRect(x: 1e308, y: 0, width: 1e308, height: 10)], diff: diff())
        }
    }

    @Test("ink just past the right or bottom edge is found, ink just inside is not", arguments: [
        (CGRect(x: 595.28, y: 400, width: 0.6, height: 5), true),
        (CGRect(x: 300, y: 841.9, width: 5, height: 0.6), true),
        (CGRect(x: 590, y: 400, width: 5.27, height: 5), false),
        (CGRect(x: 300, y: 836, width: 5, height: 5.88), false),
    ])
    func edgeInk(rect: CGRect, outside: Bool) throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [.fill(rect)])
        let count = try PageGeometry.inkOutsideCropBox(page: PageRaster.page(url: url, index: 0))
        #expect((count > 0) == outside, "count \(count)")
    }

    @Test("a page too large for the default resolution is still checked")
    func largePageOffPageCheck() throws {
        let url = try SyntheticPDF.make(size: CGSize(width: 4000, height: 4000), [.fill(CGRect(x: 3999.5, y: 10, width: 2, height: 2))])
        #expect(try PageGeometry.inkOutsideCropBox(page: PageRaster.page(url: url, index: 0)) > 0)
    }

    @Test("a raster with a resolution or page size that is not positive and finite is refused", arguments: [
        (0.0, CGSize(width: 1, height: 1)), (-72.0, CGSize(width: 1, height: 1)), (Double.infinity, CGSize(width: 1, height: 1)),
        (72.0, CGSize(width: Double.nan, height: 1)), (72.0, CGSize(width: 0, height: 1)),
    ])
    func rasterGeometry(dpi: Double, pageSize: CGSize) {
        #expect(throws: PDFVisualDiffError.self) {
            try PageRaster(width: 1, height: 1, dpi: dpi, pageSize: pageSize, pixels: [255, 255, 255])
        }
    }

    @Test("the artifact file names are published so callers can check them")
    func artifactNames() {
        let dir = URL(fileURLWithPath: "/tmp/x")
        #expect(DiffArtifacts.fileNames == ["diff_signed.png", "diff_abs.png", "diff.bin", "report.json"])
        #expect(DiffArtifacts.paths(in: dir).map(\.lastPathComponent) == DiffArtifacts.fileNames)
    }
}
