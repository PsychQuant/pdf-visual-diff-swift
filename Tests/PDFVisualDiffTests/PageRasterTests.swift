import CoreGraphics
import Foundation
import PDFVisualDiff
import Testing

struct PageRasterTests {

    @Test("same page renders to identical bytes twice")
    func sameBytesTwice() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [
            .line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 100), width: 1),
            .text("Form 115", at: CGPoint(x: 120, y: 200), size: 12, font: "Helvetica"),
        ])
        let first = try PageRaster.render(url: url, pageIndex: 0, dpi: 144)
        let second = try PageRaster.render(url: url, pageIndex: 0, dpi: 144)
        #expect(first.width == second.width)
        #expect(first.height == second.height)
        #expect(first.pixels == second.pixels)
    }

    @Test("buffer size is the ceiling of page size times dpi/72", arguments: [
        (SyntheticPDF.a4, 144.0, 1191, 1684),
        (SyntheticPDF.pdfMakerA4, 144.0, 1191, 1685),
        (CGSize(width: 612, height: 792), 72.0, 612, 792),
    ])
    func bufferSize(size: CGSize, dpi: Double, width: Int, height: Int) throws {
        let url = try SyntheticPDF.make(size: size, [])
        let raster = try PageRaster.render(url: url, pageIndex: 0, dpi: dpi)
        #expect(raster.width == width)
        #expect(raster.height == height)
        #expect(raster.pixels.count == width * height * 3)
    }

    @Test("blank page renders pure white")
    func blankIsWhite() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [])
        let raster = try PageRaster.render(url: url, pageIndex: 0, dpi: 72)
        #expect(raster.pixels.allSatisfy { $0 == 255 })
    }

    @Test("ink is placed relative to the page's top-left corner")
    func topLeftAlignment() throws {
        // A solid square from (10,10) to (30,30) bp; at 144 dpi that is pixels 20..<60.
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [.fill(CGRect(x: 10, y: 10, width: 20, height: 20))])
        let raster = try PageRaster.render(url: url, pageIndex: 0, dpi: 144)
        #expect(raster.rgb(x: 40, y: 40) == [0, 0, 0])
        #expect(raster.rgb(x: 10, y: 10) == [255, 255, 255])
        #expect(raster.rgb(x: 40, y: 100) == [255, 255, 255])
        #expect(!raster.isWhite(x: 40, y: 40))
        #expect(raster.isWhite(x: 70, y: 40))
    }

    @Test("a page index outside the document throws")
    func missingPage() throws {
        let url = try SyntheticPDF.make(size: SyntheticPDF.a4, [])
        #expect(throws: PDFVisualDiffError.pageOutOfRange(index: 3, pageCount: 1)) {
            try PageRaster.render(url: url, pageIndex: 3, dpi: 144)
        }
    }

    @Test("an unreadable file throws")
    func unreadable() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).pdf")
        #expect(throws: PDFVisualDiffError.unreadablePDF(url.path)) {
            try PageRaster.render(url: url, pageIndex: 0, dpi: 144)
        }
    }
}
