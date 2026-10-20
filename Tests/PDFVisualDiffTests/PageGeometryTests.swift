import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

struct PageGeometryTests {

    @Test("A4 is 210 × 297 mm in bp, not the rounded 595 × 842")
    func exactA4() {
        #expect(abs(PageGeometry.a4.width - 595.2755905511812) < 1e-9)
        #expect(abs(PageGeometry.a4.height - 841.8897637795276) < 1e-9)
        #expect(PageGeometry.a4 != CGSize(width: 595, height: 842))
    }

    @Test("page sizes are classified as exact A4, near A4 or other", arguments: [
        (CGSize(width: 595.2756, height: 841.8898), PageGeometry.Classification.exactA4),
        (CGSize(width: 595.28, height: 841.89), .exactA4),
        (CGSize(width: 595.32, height: 842.04), .nearA4),
        (CGSize(width: 595.38, height: 841.98), .nearA4),
        (CGSize(width: 595, height: 842), .nearA4),
        (CGSize(width: 612, height: 792), .other),
        (CGSize(width: 841.89, height: 595.28), .other),
    ])
    func classify(size: CGSize, expected: PageGeometry.Classification) {
        #expect(PageGeometry.classify(size) == expected)
    }

    @Test("a PDFMaker-sized page with blank margins has no ink in the removed strip")
    func cleanStrip() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.pdfMakerA4, [
            .line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1),
        ])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) == 0)
    }

    @Test("a line crossing the bottom strip is found")
    func inkedBottomStrip() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.pdfMakerA4, [
            .line(from: CGPoint(x: 10, y: 841.95), to: CGPoint(x: 300, y: 841.95), width: 1),
        ])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) > 0)
    }

    @Test("a mark in the right strip is found")
    func inkedRightStrip() throws {
        let url = try SyntheticPDF.make(size: CGSize(width: 597, height: 841.8898), [
            .fill(CGRect(x: 595.5, y: 400, width: 1, height: 20)),
        ])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) > 0)
    }

    @Test("a page no larger than the target has nothing to remove")
    func nothingToRemove() throws {
        let url = try SyntheticPDF.make(size: CGSize(width: 500, height: 700), [.fill(CGRect(x: 0, y: 0, width: 500, height: 700))])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) == 0)
    }
}
