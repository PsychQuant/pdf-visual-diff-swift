import CoreGraphics
import Foundation
import Testing
@testable import PDFVisualDiff

@Suite("Verification round 7 fixes")
struct Round7FixTests {

    /// A blank raster of an exact A4 page at 144 dpi: 1191 × 1684 pixels
    /// cover 595.5 × 842 bp, a little past the page's 595.2756 × 841.8898 bp.
    static func blankA4() throws -> PageRaster {
        let size = CGSize(width: 210 / 25.4 * 72, height: 297 / 25.4 * 72)
        let width = Int((size.width * 2).rounded(.up)), height = Int((size.height * 2).rounded(.up))
        return try PageRaster(width: width, height: height, dpi: 144, pageSize: size,
                              pixels: [UInt8](repeating: 255, count: width * height * 3))
    }

    @Test("a region past the page edge but inside the rounded-up raster fails")
    func regionPastPageEdge() throws {
        let page = try Self.blankA4()
        let diff = try SignedDiff(original: page, output: page)
        let result = try PreservedRegions.check([CGRect(x: 595.3, y: 10, width: 0.1, height: 10)], diff: diff)
        // 0.1 × 10 bp at 144 dpi is 0.2 × 20 = 4 pixels, all past the page.
        #expect(result[0].uncheckedPixels == 4)
        #expect(!result[0].passed)
    }

    @Test("a region wholly on the page still passes")
    func regionOnPage() throws {
        let page = try Self.blankA4()
        let diff = try SignedDiff(original: page, output: page)
        let result = try PreservedRegions.check([CGRect(x: 500, y: 10, width: 95, height: 10)], diff: diff)
        #expect(result[0].passed)
    }

    @Test("a region typed with the page size printed to two decimals passes", arguments: [
        CGRect(x: 0, y: 0, width: 595.28, height: 841.89),
        CGRect(x: 0, y: 800, width: 595.28, height: 41.89),
    ])
    func regionAtPrintedPageSize(rect: CGRect) throws {
        let page = try Self.blankA4()
        let diff = try SignedDiff(original: page, output: page)
        #expect(try PreservedRegions.check([rect], diff: diff)[0].passed)
    }

    @Test("the slack holds on a page whose size is a whole number of pixels")
    func slackOnWholePixelPage() throws {
        let page = try PageRaster(width: 100, height: 100, dpi: 72, pageSize: CGSize(width: 100, height: 100),
                                  pixels: [UInt8](repeating: 255, count: 100 * 100 * 3))
        let diff = try SignedDiff(original: page, output: page)
        #expect(try PreservedRegions.check([CGRect(x: 0, y: 0, width: 100.004, height: 10)], diff: diff)[0].passed)
        #expect(try PreservedRegions.check([CGRect(x: 0, y: 0, width: 10, height: 100.004)], diff: diff)[0].passed)
        #expect(try !PreservedRegions.check([CGRect(x: 0, y: 0, width: 100.01, height: 10)], diff: diff)[0].passed)
        #expect(try !PreservedRegions.check([CGRect(x: 100.001, y: 0, width: 0.003, height: 10)], diff: diff)[0].passed)
    }

    @Test("the shared page area is the smaller of the two pages")
    func sharedPageSize() throws {
        let a = try Self.blankA4()
        let b = try PageRaster(width: a.width, height: a.height, dpi: 144,
                               pageSize: CGSize(width: 595, height: 841), pixels: a.pixels)
        #expect(try SignedDiff(original: a, output: b).pageSize == CGSize(width: 595, height: 841))
    }
}
