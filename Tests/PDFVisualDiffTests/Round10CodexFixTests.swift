import CoreGraphics
import Foundation
import Testing
@testable import PDFVisualDiff

/// Fixes from the cross-model (Codex) pass of the tenth verification round
/// of PsychQuant/macdoc#240.
@Suite("Verification round 10 (Codex) fixes")
struct Round10CodexFixTests {

    @Test("the shared canvas height does not trap on a resolution the render will refuse",
          arguments: [-Double.infinity, Double.infinity, Double.nan, 0, -1e300, -144])
    func canvasHeightWithInvalidResolution(dpi: Double) throws {
        let height = PageRaster.canvasHeight(heights: [841.8898], dpi: dpi)
        #expect(height >= 1)
        let page = try PageRaster.page(url: SyntheticPDF.make(size: CGSize(width: 595.2756, height: 841.8898), []), index: 0)
        #expect(throws: PDFVisualDiffError.self) {
            try PageRaster.render(page: page, dpi: dpi, canvasHeight: height)
        }
    }

    @Test("the shared canvas height does not trap on an unusable page height",
          arguments: [CGFloat.infinity, -CGFloat.infinity, CGFloat.nan, -841.8898, 0])
    func canvasHeightWithInvalidPageHeight(pageHeight: CGFloat) {
        #expect(PageRaster.canvasHeight(heights: [pageHeight, 841.8898], dpi: 144) == 1684)
    }

    @Test("a valid set of heights still gives the tallest render")
    func canvasHeightValid() {
        // Exact A4 at 127 dpi is 1485 rows; TeX's 841.89 bp is 1486.
        #expect(PageRaster.canvasHeight(heights: [841.8898, 841.89], dpi: 127) == 1486)
    }
}
