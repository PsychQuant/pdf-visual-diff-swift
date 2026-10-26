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
        #expect(result[0].uncheckedPixels > 0)
        #expect(!result[0].passed)
    }

    @Test("a region wholly on the page still passes")
    func regionOnPage() throws {
        let page = try Self.blankA4()
        let diff = try SignedDiff(original: page, output: page)
        let result = try PreservedRegions.check([CGRect(x: 500, y: 10, width: 95, height: 10)], diff: diff)
        #expect(result[0].passed)
    }

    @Test("the shared page area is the smaller of the two pages")
    func sharedPageSize() throws {
        let a = try Self.blankA4()
        let b = try PageRaster(width: a.width, height: a.height, dpi: 144,
                               pageSize: CGSize(width: 595, height: 841), pixels: a.pixels)
        #expect(try SignedDiff(original: a, output: b).pageSize == CGSize(width: 595, height: 841))
    }
}
