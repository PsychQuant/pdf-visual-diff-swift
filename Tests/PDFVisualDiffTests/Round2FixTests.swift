import CoreGraphics
import Foundation
import PDFKit
import PDFVisualDiff
import Testing

/// Fixes from the second verification round of PsychQuant/macdoc#240.
struct Round2FixTests {

    private func raster(_ size: CGSize, _ items: [SyntheticPDF.Item], dpi: Double = 144) throws -> PageRaster {
        try PageRaster.render(url: SyntheticPDF.make(size: size, items), pageIndex: 0, dpi: dpi)
    }

    // MARK: preserved regions

    @Test("a preserved region far outside the page cannot pass")
    func regionFarOffPage() throws {
        let a = try raster(SyntheticPDF.a4, [])
        let diff = try SignedDiff(original: a, output: a)
        let result = try #require(try PreservedRegions.check(
            [CGRect(x: 1_000_000_000, y: 10, width: 10, height: 10)], diff: diff).first)
        #expect(result.uncheckedPixels == 20 * 20)
        #expect(!result.passed)
    }

    // MARK: artifacts

    @Test("artifacts replace a symbolic link in the diff directory instead of writing through it")
    func artifactsDoNotFollowLinks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("links-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let victim = dir.appendingPathComponent("victim.pdf")
        try Data("keep".utf8).write(to: victim)
        let names = ["diff_signed.png", "diff_abs.png", "diff.bin", "report.json"]
        for name in names {
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent(name), withDestinationURL: victim)
        }
        let a = try raster(SyntheticPDF.a4, [], dpi: 72)
        try DiffArtifacts.write(diff: SignedDiff(original: a, output: a), identical: true, to: dir)
        #expect(try Data(contentsOf: victim) == Data("keep".utf8))
        for name in names {
            let values = try dir.appendingPathComponent(name).resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            #expect(values.isSymbolicLink == false && values.isRegularFile == true, "\(name)")
        }
    }

    // MARK: removed strip

    @Test("a pixel straddling the right-strip cut is counted once")
    func seamPixelCountedOnce() throws {
        // 595.0…596.0 × 842.5…843.0 bp: columns 1190 (cut at 1190.56) and 1191, row 1685 at 144 dpi.
        let url = try SyntheticPDF.make(size: CGSize(width: 597, height: 843), [
            .fill(CGRect(x: 595.0, y: 842.5, width: 1, height: 0.5)),
        ])
        #expect(try PageGeometry.inkInRemovedStrip(url: url, pageIndex: 0, target: PageGeometry.a4, dpi: 144) == 2)
    }

    // MARK: ink off the page

    @Test("ink drawn past the crop box is found")
    func inkPastCropBox() throws {
        let off = try SyntheticPDF.make(size: SyntheticPDF.a4, [.text("WWWW", at: CGPoint(x: 580, y: 400), size: 12, font: "Helvetica")])
        let on = try SyntheticPDF.make(size: SyntheticPDF.a4, [.text("WWWW", at: CGPoint(x: 100, y: 400), size: 12, font: "Helvetica")])
        #expect(try PageGeometry.inkOutsideCropBox(page: PageRaster.page(url: off, index: 0)) > 0)
        #expect(try PageGeometry.inkOutsideCropBox(page: PageRaster.page(url: on, index: 0)) == 0)
    }

    // MARK: overlay checks

    @Test("a faint stamp of the overlay is reported as missing")
    func faintStamp() throws {
        let original = try raster(SyntheticPDF.a4, [])
        let output = try raster(SyntheticPDF.a4, [.greyText("42", at: CGPoint(x: 123, y: 310), size: 12, font: "Helvetica", grey: 0.6)])
        let overlay = try raster(SyntheticPDF.a4, [.text("42", at: CGPoint(x: 123, y: 310), size: 12, font: "Helvetica")])
        let report = try OverlayVerifier.verify(original: original, output: output, overlay: overlay).report
        #expect(report.result(for: .overlayMissingFromOutput).count > 0)
        #expect(!report.passed)
    }

    // MARK: sizes

    @Test("identical documents have matching sizes")
    func identicalSizesMatch() throws {
        let a = try raster(SyntheticPDF.a4, [])
        #expect(try SignedDiff(original: a, output: a).sizesMatch)
    }

    @Test("pages that differ by less than a pixel do not have matching sizes")
    func subPixelSizeDifference() throws {
        let a = try raster(SyntheticPDF.a4, [], dpi: 72)
        let b = try raster(CGSize(width: 595.28, height: 841.89), [], dpi: 72)
        #expect(a.width == b.width && a.height == b.height)
        #expect(try !SignedDiff(original: a, output: b).sizesMatch)
    }

    // MARK: limits

    @Test("a bitmap above the pixel limit is refused")
    func bitmapLimit() throws {
        let url = try SyntheticPDF.make(size: CGSize(width: 10_000, height: 10_000), [])
        let error = #expect(throws: PDFVisualDiffError.self) {
            try PageRaster.render(url: url, pageIndex: 0, dpi: 144)
        }
        guard case .bitmapTooLarge? = error else {
            Issue.record("expected bitmapTooLarge, got \(String(describing: error))")
            return
        }
    }

    @Test("a rotated page is refused")
    func rotationRefused() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [])
        let document = try #require(PDFDocument(url: url))
        document.page(at: 0)?.rotation = 90
        #expect(document.write(to: url))
        #expect(throws: PDFVisualDiffError.unsupportedRotation(degrees: 90)) {
            try PageRaster.render(url: url, pageIndex: 0, dpi: 72)
        }
    }

    @Test("a raster of no size is refused", arguments: [(0, 1), (1, 0), (-1, -1)])
    func emptyRaster(size: (Int, Int)) {
        #expect(throws: PDFVisualDiffError.self) {
            try PageRaster(width: size.0, height: size.1, dpi: 72, pageSize: CGSize(width: 1, height: 1), pixels: [0, 0, 0])
        }
    }
}
