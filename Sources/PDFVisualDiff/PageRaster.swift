import CoreGraphics
import Foundation

/// One PDF page rendered by CoreGraphics into 8-bit sRGB RGB on white.
///
/// The page's top-left corner (of its crop box) sits at pixel (0, 0); rows run
/// top to bottom. Width and height are the ceiling of the page size times
/// `dpi / 72`. Rendering the same page twice gives the same bytes, which is
/// what lets two renders be subtracted without any noise filtering.
public struct PageRaster: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let dpi: Double
    /// The rendered box in bp (crop box, which defaults to the media box).
    public let pageSize: CGSize
    /// RGB bytes, row-major, top row first: `pixels[(y * width + x) * 3 + c]`.
    public let pixels: [UInt8]

    public init(width: Int, height: Int, dpi: Double, pageSize: CGSize, pixels: [UInt8]) {
        precondition(pixels.count == width * height * 3, "pixel buffer does not match width × height × 3")
        self.width = width
        self.height = height
        self.dpi = dpi
        self.pageSize = pageSize
        self.pixels = pixels
    }

    /// Bitmap pixels per bp.
    public var scale: Double { dpi / 72 }

    /// The highest resolution accepted.
    public static let maxDPI = 2400.0
    /// The largest bitmap accepted, in pixels. Rendering needs about 7 bytes
    /// per pixel (RGBA bitmap plus the RGB copy), so this caps one render at
    /// roughly 1.4 GB.
    public static let maxPixelCount = 200_000_000

    public func rgb(x: Int, y: Int) -> [UInt8] {
        let i = (y * width + x) * 3
        return [pixels[i], pixels[i + 1], pixels[i + 2]]
    }

    /// True when all three channels are 255. Any other value counts as ink,
    /// including the faintest antialiasing.
    public func isWhite(x: Int, y: Int) -> Bool {
        let i = (y * width + x) * 3
        return pixels[i] == 255 && pixels[i + 1] == 255 && pixels[i + 2] == 255
    }

    public static func render(url: URL, pageIndex: Int = 0, dpi: Double = 144) throws -> PageRaster {
        try render(page: page(url: url, index: pageIndex), dpi: dpi)
    }

    /// Opens `url` and returns the page at the 0-based `index`.
    public static func page(url: URL, index: Int) throws -> CGPDFPage {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw PDFVisualDiffError.unreadablePDF(url.path)
        }
        // CGPDFDocument pages are 1-based.
        guard index >= 0, index < document.numberOfPages, let page = document.page(at: index + 1) else {
            throw PDFVisualDiffError.pageOutOfRange(index: index, pageCount: document.numberOfPages)
        }
        return page
    }

    public static func render(page: CGPDFPage, dpi: Double = 144) throws -> PageRaster {
        try render(page: page, dpi: dpi, clip: nil)
    }

    /// Renders `page`; when `clip` is given (in PDF page coordinates), only
    /// the part of the page inside it is drawn. The transform is the same as
    /// for a full render, so pixels line up with a full render.
    static func render(page: CGPDFPage, dpi: Double, clip: CGRect?) throws -> PageRaster {
        guard dpi.isFinite, dpi > 0, dpi <= maxDPI else { throw PDFVisualDiffError.invalidResolution(dpi) }
        let rotation = ((Int(page.rotationAngle) % 360) + 360) % 360
        guard rotation == 0 else { throw PDFVisualDiffError.unsupportedRotation(degrees: rotation) }

        let box = page.getBoxRect(.cropBox)
        let scale = dpi / 72
        let w = (box.width * scale).rounded(.up), h = (box.height * scale).rounded(.up)
        guard w.isFinite, h.isFinite, w >= 1, h >= 1, w * h <= Double(maxPixelCount) else {
            throw PDFVisualDiffError.bitmapTooLarge(width: w, height: h, limit: maxPixelCount)
        }
        let width = Int(w), height = Int(h)
        guard
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw PDFVisualDiffError.bitmapContextUnavailable(width: width, height: height)
        }

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // Put the box's top-left corner at the bitmap's top-left corner.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.maxY)
        context.clip(to: box)
        if let clip { context.clip(to: clip) }
        context.drawPDFPage(page)

        guard let data = context.data else {
            throw PDFVisualDiffError.bitmapContextUnavailable(width: width, height: height)
        }
        let rgba = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        // The background is opaque white, so alpha is always 255 and the
        // premultiplied values are the colour values.
        for p in 0..<(width * height) {
            rgb[p * 3] = rgba[p * 4]
            rgb[p * 3 + 1] = rgba[p * 4 + 1]
            rgb[p * 3 + 2] = rgba[p * 4 + 2]
        }
        return PageRaster(width: width, height: height, dpi: dpi, pageSize: box.size, pixels: rgb)
    }
}
