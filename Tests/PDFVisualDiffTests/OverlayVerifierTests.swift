import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

struct OverlayVerifierTests {

    // The spec example: a near-A4 blank form with one line and the label 年.
    static let form: [SyntheticPDF.Item] = [
        .line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1),
        .text("年", at: CGPoint(x: 207, y: 227.5), size: 12, font: "PingFang TC"),
    ]

    private func raster(_ size: CGSize, _ items: [SyntheticPDF.Item]) throws -> PageRaster {
        try PageRaster.render(url: SyntheticPDF.make(size: size, items), pageIndex: 0, dpi: 144)
    }

    private func count(_ report: OverlayReport, _ check: OverlayCheck) -> Int {
        report.result(for: check).count
    }

    @Test("a clean overlay on a near-A4 form passes all four checks")
    func cleanOverlay() throws {
        let typed = SyntheticPDF.Item.text("115", at: CGPoint(x: 180, y: 237.5), size: 12, font: "Helvetica")
        let original = try raster(SyntheticPDF.pdfMakerA4, Self.form)
        let output = try raster(SyntheticPDF.a4, Self.form + [typed])
        let overlay = try raster(SyntheticPDF.a4, [typed])
        let result = try OverlayVerifier.verify(original: original, output: output, overlay: overlay)
        for check in OverlayCheck.allCases {
            #expect(count(result.report, check) == 0, "\(check)")
        }
        #expect(result.report.passed)
        #expect(result.diff.changedPixelCount > 0)
    }

    @Test("typed text over a printed label is located inside the label's box")
    func collisionIsLocated() throws {
        // Same baseline as 年, starting 2 bp to its left: the digits run into the glyph.
        let typed = SyntheticPDF.Item.text("115", at: CGPoint(x: 205, y: 227.5), size: 12, font: "Helvetica")
        let original = try raster(SyntheticPDF.pdfMakerA4, Self.form)
        let output = try raster(SyntheticPDF.a4, Self.form + [typed])
        let overlay = try raster(SyntheticPDF.a4, [typed])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        let overlap = report.result(for: .overlayInkOnOriginalInk)
        #expect(overlap.count > 0)
        #expect(!report.passed)
        // 年 at 12 pt with its baseline at y = 227.5 starting at x = 207 occupies
        // roughly x 207…219 and y 216…229 bp.
        let band = try #require(overlap.bands.first)
        #expect(band.left >= 205 && band.right <= 220)
        #expect(band.top >= 214 && band.bottom <= 230)
    }

    @Test("overlay ink exactly on original ink is reported even though D is zero there")
    func inkOnInk() throws {
        let square = SyntheticPDF.Item.fill(CGRect(x: 50, y: 50, width: 10, height: 10))
        let original = try raster(SyntheticPDF.a4, [square])
        let output = try raster(SyntheticPDF.a4, [square])
        let overlay = try raster(SyntheticPDF.a4, [square])
        let result = try OverlayVerifier.verify(original: original, output: output, overlay: overlay)
        #expect(result.diff.changedPixelCount == 0)
        #expect(count(result.report, .overlayInkOnOriginalInk) == 20 * 20)
        #expect(count(result.report, .differenceOutsideOverlay) == 0)
    }

    @Test("ink removed from the original is reported as made lighter")
    func madeLighter() throws {
        let square = SyntheticPDF.Item.fill(CGRect(x: 50, y: 50, width: 10, height: 10))
        let original = try raster(SyntheticPDF.a4, [square])
        let output = try raster(SyntheticPDF.a4, [])
        let overlay = try raster(SyntheticPDF.a4, [])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        #expect(count(report, .originalMadeLighter) == 20 * 20)
        // The lightened pixels are also outside the (empty) overlay.
        #expect(count(report, .differenceOutsideOverlay) == 20 * 20)
    }

    @Test("a change the overlay does not account for is reported outside the overlay")
    func outsideOverlay() throws {
        let stray = SyntheticPDF.Item.fill(CGRect(x: 400, y: 600, width: 5, height: 5))
        let original = try raster(SyntheticPDF.a4, [])
        let output = try raster(SyntheticPDF.a4, [stray])
        let overlay = try raster(SyntheticPDF.a4, [])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        let outside = report.result(for: .differenceOutsideOverlay)
        #expect(outside.count == 10 * 10)
        let band = try #require(outside.bands.first)
        #expect(band.top == 600 && band.bottom == 605)
        #expect(band.left == 400 && band.right == 405)
    }

    @Test("ink of the original beyond the output's size is reported as cropped")
    func croppedStrip() throws {
        let tall = CGSize(width: SyntheticPDF.a4.width, height: 850)
        let original = try raster(tall, [.fill(CGRect(x: 100, y: 845, width: 50, height: 3))])
        let output = try raster(SyntheticPDF.a4, [])
        let overlay = try raster(SyntheticPDF.a4, [])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        #expect(count(report, .inkInCroppedStrip) == 100 * 6)
        #expect(!report.passed)
    }

    @Test("the report encodes to JSON with every check")
    func reportIsCodable() throws {
        let original = try raster(SyntheticPDF.a4, [])
        let report = try OverlayVerifier.verify(original: original, output: original, overlay: original).report
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(OverlayReport.self, from: data)
        #expect(decoded == report)
        #expect(decoded.checks.map(\.check) == OverlayCheck.allCases)
    }
}
