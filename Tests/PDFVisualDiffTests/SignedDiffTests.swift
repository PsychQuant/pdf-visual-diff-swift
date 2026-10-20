import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

struct SignedDiffTests {

    private func render(_ size: CGSize, _ items: [SyntheticPDF.Item], dpi: Double = 144) throws -> PageRaster {
        try PageRaster.render(url: SyntheticPDF.make(size: size, items), pageIndex: 0, dpi: dpi)
    }

    @Test("identical documents give an all-zero difference")
    func identical() throws {
        let items: [SyntheticPDF.Item] = [
            .line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1),
            .text("115", at: CGPoint(x: 180, y: 237.5), size: 12, font: "Helvetica"),
        ]
        let original = try render(SyntheticPDF.a4, items)
        let copy = try render(SyntheticPDF.a4, items)
        let diff = try SignedDiff(original: original, output: copy)
        #expect(diff.changedPixelCount == 0)
        #expect(diff.channelMin == [0, 0, 0])
        #expect(diff.channelMax == [0, 0, 0])
    }

    @Test("black text added on white darkens every changed channel")
    func blackTextDarkens() throws {
        let original = try render(SyntheticPDF.a4, [])
        let output = try render(SyntheticPDF.a4, [.text("115", at: CGPoint(x: 180, y: 237.5), size: 12, font: "Helvetica")])
        let diff = try SignedDiff(original: original, output: output)
        #expect(diff.changedPixelCount > 0)
        #expect(diff.channelMax == [0, 0, 0])
        #expect(diff.values.allSatisfy { $0 <= 0 })
    }

    @Test("a solid black square gives D = -255 inside it")
    func knownValue() throws {
        let original = try render(SyntheticPDF.a4, [])
        let output = try render(SyntheticPDF.a4, [.fill(CGRect(x: 10, y: 10, width: 20, height: 20))])
        let diff = try SignedDiff(original: original, output: output)
        #expect(diff.d(x: 40, y: 40) == [-255, -255, -255])
        #expect(diff.d(x: 5, y: 5) == [0, 0, 0])
        #expect(diff.channelMin == [-255, -255, -255])
        // 20 bp × 2 px/bp = 40 px a side.
        #expect(diff.changedPixelCount == 40 * 40)
    }

    @Test("removing ink gives positive D")
    func removedInkIsPositive() throws {
        let original = try render(SyntheticPDF.a4, [.fill(CGRect(x: 10, y: 10, width: 20, height: 20))])
        let output = try render(SyntheticPDF.a4, [])
        let diff = try SignedDiff(original: original, output: output)
        #expect(diff.d(x: 40, y: 40) == [255, 255, 255])
        #expect(diff.channelMax == [255, 255, 255])
    }

    @Test("rasters are compared over their common top-left region")
    func commonRegion() throws {
        let original = try render(SyntheticPDF.pdfMakerA4, [])
        let output = try render(SyntheticPDF.a4, [])
        let diff = try SignedDiff(original: original, output: output)
        #expect(diff.width == 1191)
        #expect(diff.height == 1684)
        #expect(diff.changedPixelCount == 0)
    }

    @Test("different resolutions are refused")
    func differentDPI() throws {
        let a = try render(SyntheticPDF.a4, [], dpi: 144)
        let b = try render(SyntheticPDF.a4, [], dpi: 72)
        #expect(throws: PDFVisualDiffError.self) {
            try SignedDiff(original: a, output: b)
        }
    }
}
