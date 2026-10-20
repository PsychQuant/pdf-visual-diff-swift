import CoreGraphics
import Foundation

/// Page sizes in bp (1/72 inch, the PDF unit).
public enum PageGeometry {
    /// 210 × 297 mm. Deliberately not 595 × 842: that rounded size, which some
    /// libraries return for "A4", is 0.28 bp too wide and 0.11 bp too tall.
    public static let a4 = CGSize(width: 210 / 25.4 * 72, height: 297 / 25.4 * 72)

    /// A page within this many bp of A4 in both dimensions is "near A4".
    /// PDFs exported through Acrobat PDFMaker are A4 rounded to a 600 dpi
    /// dot grid: 4960.63 × 7015.75 dots become 4961 × 7016 = 595.32 × 841.92 bp.
    public static let nearA4Tolerance = 1.5

    /// Sizes that differ from A4 by at most this much (bp) are exact A4;
    /// TeX's a4paper, for one, comes out 595.28 × 841.89.
    public static let exactTolerance = 0.01

    public enum Classification: String, Codable, Sendable {
        case exactA4
        case nearA4
        case other
    }

    public static func classify(_ size: CGSize) -> Classification {
        let dw = abs(size.width - a4.width), dh = abs(size.height - a4.height)
        if dw <= exactTolerance && dh <= exactTolerance { return .exactA4 }
        if dw <= nearA4Tolerance && dh <= nearA4Tolerance { return .nearA4 }
        return .other
    }

    /// Counts the pixels with ink in the part of the page that a top-left
    /// anchored crop to `target` would remove (the strip right of
    /// `target.width` and the strip below `target.height`). Only that strip is
    /// drawn, so ink just above or left of the cut is not counted even when it
    /// shares a pixel row with the strip.
    public static func inkInRemovedStrip(url: URL, pageIndex: Int = 0, target: CGSize, dpi: Double = 144) throws -> Int {
        try inkInRemovedStrip(page: PageRaster.page(url: url, index: pageIndex), target: target, dpi: dpi)
    }

    public static func inkInRemovedStrip(page: CGPDFPage, target: CGSize, dpi: Double = 144) throws -> Int {
        let box = page.getBoxRect(.cropBox)
        var strips: [CGRect] = []
        if box.width > target.width {
            strips.append(CGRect(x: box.minX + target.width, y: box.minY, width: box.width - target.width, height: box.height))
        }
        if box.height > target.height {
            // PDF coordinates: the bottom of the page is minY.
            strips.append(CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height - target.height))
        }
        var inked = 0
        for strip in strips {
            let raster = try PageRaster.render(page: page, dpi: dpi, clip: strip)
            for y in 0..<raster.height {
                for x in 0..<raster.width where !raster.isWhite(x: x, y: y) { inked += 1 }
            }
        }
        return inked
    }
}
