import CoreGraphics
import Foundation

/// Page sizes in bp (1/72 inch, the PDF unit).
public enum PageGeometry {
    /// 210 × 297 mm. Deliberately not 595 × 842: that rounded size, which some
    /// libraries return for "A4", is 0.28 bp too wide and 0.11 bp too tall.
    public static let a4 = CGSize(width: 210 / 25.4 * 72, height: 297 / 25.4 * 72)

    /// A page within this many bp of A4 in both dimensions is "near A4".
    /// Some PDF producers round the page size to a device grid, which leaves
    /// a page meant to be A4 a fraction of a bp larger or smaller.
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
    /// shares a pixel row with the strip. The two strips are drawn as one
    /// clip, so no pixel is counted twice.
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
        guard !strips.isEmpty else { return 0 }
        let raster = try PageRaster.render(page: page, dpi: dpi, clip: strips)
        var inked = 0
        for y in 0..<raster.height {
            for x in 0..<raster.width where !raster.isWhite(x: x, y: y) { inked += 1 }
        }
        return inked
    }

    /// Counts the pixels with ink drawn outside the page's crop box, up to
    /// one page width or height beyond each edge. A render of the page clips
    /// such ink away, so it is invisible to the overlay checks; text that
    /// runs past the page edge shows up here. Only the area outside the box
    /// is drawn, at x and y scales adjusted so the box edges fall exactly on
    /// pixel boundaries: every pixel is wholly inside or wholly outside the
    /// box, so ink on the box never reaches an outside pixel and any ink past
    /// the edge does. The resolution is lowered when the 3 × 3 page area
    /// would exceed the bitmap limit.
    public static func inkOutsideCropBox(page: CGPDFPage, dpi: Double = 72) throws -> Int {
        guard dpi.isFinite, dpi >= PageRaster.minDPI, dpi <= PageRaster.maxDPI else { throw PDFVisualDiffError.invalidResolution(dpi) }
        let box = page.getBoxRect(.cropBox)
        let area = Double(box.width) * 3 * Double(box.height) * 3
        var scale = min(dpi, 72 * (Double(PageRaster.maxPixelCount) / area).squareRoot()) / 72
        // Whole pixels per box side, and the scales that make them exact.
        // Each side is at least one pixel, which for an extreme aspect ratio
        // can still exceed the limit; keep lowering the scale until it fits.
        var boxW = 1.0, boxH = 1.0
        repeat {
            boxW = max(1, (box.width * scale).rounded())
            boxH = max(1, (box.height * scale).rounded())
            scale /= 2
        } while boxW * boxH * 9 > Double(PageRaster.maxPixelCount) && scale > 0
        let w = boxW * 3, h = boxH * 3
        guard w.isFinite, h.isFinite, w * h <= Double(PageRaster.maxPixelCount) else {
            throw PDFVisualDiffError.bitmapTooLarge(width: w, height: h, limit: PageRaster.maxPixelCount)
        }
        let width = Int(w), height = Int(h)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw PDFVisualDiffError.bitmapContextUnavailable(width: width, height: height) }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The crop box sits in the middle of a 3 × 3 page area; only the
        // eight pages around it are drawn.
        context.scaleBy(x: boxW / box.width, y: boxH / box.height)
        context.translateBy(x: box.width - box.minX, y: box.height - box.minY)
        context.clip(to: [
            CGRect(x: box.minX - box.width, y: box.minY - box.height, width: box.width, height: box.height * 3),
            CGRect(x: box.maxX, y: box.minY - box.height, width: box.width, height: box.height * 3),
            CGRect(x: box.minX, y: box.minY - box.height, width: box.width, height: box.height),
            CGRect(x: box.minX, y: box.maxY, width: box.width, height: box.height),
        ])
        context.drawPDFPage(page)
        guard let data = context.data else {
            throw PDFVisualDiffError.bitmapContextUnavailable(width: width, height: height)
        }
        let rgba = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var inked = 0
        for i in stride(from: 0, to: width * height * 4, by: 4)
        where rgba[i] != 255 || rgba[i + 1] != 255 || rgba[i + 2] != 255 { inked += 1 }
        return inked
    }
}
