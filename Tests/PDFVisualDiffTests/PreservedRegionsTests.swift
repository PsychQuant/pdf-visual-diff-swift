import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

struct PreservedRegionsTests {

    private func diff(_ original: [SyntheticPDF.Item], _ output: [SyntheticPDF.Item]) throws -> SignedDiff {
        let a = try PageRaster.render(url: SyntheticPDF.make(size: SyntheticPDF.a4, original), pageIndex: 0, dpi: 144)
        let b = try PageRaster.render(url: SyntheticPDF.make(size: SyntheticPDF.a4, output), pageIndex: 0, dpi: 144)
        return try SignedDiff(original: a, output: b)
    }

    @Test("one changed mark inside a preserved region fails that region")
    func markInsideFails() throws {
        // A 2×2 bp mark at (100,100): 4×4 pixels at 144 dpi.
        let d = try diff([], [.fill(CGRect(x: 100, y: 100, width: 2, height: 2))])
        let results = try PreservedRegions.check([
            CGRect(x: 50, y: 50, width: 100, height: 100),
            CGRect(x: 300, y: 300, width: 100, height: 100),
        ], diff: d)
        #expect(results.count == 2)
        #expect(results[0].index == 0)
        #expect(results[0].changedPixels == 16)
        #expect(!results[0].passed)
        #expect(results[1].changedPixels == 0)
        #expect(results[1].passed)
    }

    @Test("a pixel only partly inside the region still counts")
    func partialPixelCounts() throws {
        // The mark covers 100…102 bp; the region ends at 100.25 bp, which cuts
        // through the first pixel column (100…100.5 bp).
        let d = try diff([], [.fill(CGRect(x: 100, y: 100, width: 2, height: 2))])
        let result = try #require(try PreservedRegions.check([CGRect(x: 90, y: 90, width: 10.25, height: 20)], diff: d).first)
        #expect(result.changedPixels == 4)
    }

    @Test("a region reaching beyond the raster is not an error, but its unchecked part keeps it from passing")
    func clippedRegion() throws {
        let d = try diff([], [])
        let result = try #require(try PreservedRegions.check([CGRect(x: 590, y: 830, width: 100, height: 100)], diff: d).first)
        #expect(result.changedPixels == 0)
        // 200 × 200 pixels at 144 dpi, of which 11 × 24 lie on the A4 raster.
        #expect(result.uncheckedPixels == 200 * 200 - 11 * 24)
        #expect(!result.passed)
    }
}
