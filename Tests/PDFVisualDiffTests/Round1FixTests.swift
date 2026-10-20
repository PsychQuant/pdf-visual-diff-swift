import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

/// Fixes from the first verification round of PsychQuant/macdoc#240.
struct Round1FixTests {

    private func raster(_ size: CGSize, _ items: [SyntheticPDF.Item], dpi: Double = 144) throws -> PageRaster {
        try PageRaster.render(url: SyntheticPDF.make(size: size, items), pageIndex: 0, dpi: dpi)
    }

    // MARK: extremes

    @Test("extremes are the true minimum and maximum, not clamped at 0")
    func trueExtremes() throws {
        let page = CGSize(width: 100, height: 100)
        let original = try raster(page, [], dpi: 72)
        let output = try raster(page, [.fill(CGRect(x: 0, y: 0, width: 100, height: 100))], dpi: 72)
        let diff = try SignedDiff(original: original, output: output)
        #expect(diff.changedPixelCount == 100 * 100)
        #expect(diff.channelMin == [-255, -255, -255])
        #expect(diff.channelMax == [-255, -255, -255])
    }

    // MARK: numeric limits

    @Test("resolutions outside the supported range are refused instead of crashing", arguments: [
        1e308, 2401, Double.infinity, -1, 0,
    ])
    func resolutionLimits(dpi: Double) throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [])
        #expect(throws: PDFVisualDiffError.self) {
            try PageRaster.render(url: url, pageIndex: 0, dpi: dpi)
        }
    }

    @Test("a non-finite preserved region is refused")
    func nonFiniteRegion() throws {
        let a = try raster(SyntheticPDF.a4, [])
        let diff = try SignedDiff(original: a, output: a)
        #expect(throws: PDFVisualDiffError.invalidRegion(index: 0)) {
            try PreservedRegions.check([CGRect(x: 0, y: 0, width: Double.infinity, height: 10)], diff: diff)
        }
    }

    // MARK: overlay checks

    @Test("ink in the part of the output beyond the original is reported outside the overlay")
    func outputBeyondOriginal() throws {
        let original = try raster(SyntheticPDF.a4, [])
        let output = try raster(CGSize(width: 600, height: 850), [.fill(CGRect(x: 597, y: 100, width: 2, height: 2))])
        let overlay = try raster(SyntheticPDF.a4, [])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        // 2 × 2 bp at 144 dpi = 4 × 4 pixels, all beyond the original's 1191 columns.
        #expect(report.result(for: .differenceOutsideOverlay).count == 16)
        #expect(!report.passed)
    }

    @Test("typed text missing from the output is reported")
    func overlayMissing() throws {
        let form: [SyntheticPDF.Item] = [.line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1)]
        let typed = SyntheticPDF.Item.text("42", at: CGPoint(x: 123, y: 310), size: 12, font: "Helvetica")
        let original = try raster(SyntheticPDF.nearA4, form)
        let unfilled = try raster(SyntheticPDF.a4, form)
        let overlay = try raster(SyntheticPDF.a4, [typed])
        let report = try OverlayVerifier.verify(original: original, output: unfilled, overlay: overlay).report
        #expect(report.result(for: .overlayMissingFromOutput).count > 0)
        #expect(!report.passed)
    }

    @Test("a correctly filled output has nothing missing")
    func overlayPresent() throws {
        let form: [SyntheticPDF.Item] = [.line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1)]
        let typed = SyntheticPDF.Item.text("42", at: CGPoint(x: 123, y: 310), size: 12, font: "Helvetica")
        let original = try raster(SyntheticPDF.nearA4, form)
        let output = try raster(SyntheticPDF.a4, form + [typed])
        let overlay = try raster(SyntheticPDF.a4, [typed])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        #expect(report.result(for: .overlayMissingFromOutput).count == 0)
        #expect(report.passed)
    }

    // MARK: geometry

    @Test("ink in the corner shared by both removed strips is counted once")
    func cornerCountedOnce() throws {
        // 595.5…596.5 × 842.0…842.5 bp = columns 1191–1192, row 1684 at 144 dpi: 2 pixels.
        let url = try SyntheticPDF.make(size: CGSize(width: 597, height: 843), [
            .fill(CGRect(x: 595.5, y: 842.0, width: 1, height: 0.5)),
        ])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) == 2)
    }

    // MARK: artifacts

    @Test("report.json records the identity check when it ran")
    func identityInReport() throws {
        let a = try raster(SyntheticPDF.a4, [], dpi: 72)
        let diff = try SignedDiff(original: a, output: a)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("identity-\(UUID().uuidString)")
        try DiffArtifacts.write(diff: diff, identical: true, to: dir)
        let report = try JSONDecoder().decode(DiffArtifactReport.self, from: Data(contentsOf: dir.appendingPathComponent("report.json")))
        #expect(report.identical == true)
        #expect(report.overlayChecks == nil)
    }
}
