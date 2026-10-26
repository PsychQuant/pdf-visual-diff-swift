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

    /// Throws when the size is not positive, the buffer does not hold
    /// width × height × 3 bytes, the resolution is not a positive finite
    /// number, or the page size is not positive and finite.
    public init(width: Int, height: Int, dpi: Double, pageSize: CGSize, pixels: [UInt8]) throws {
        guard dpi.isFinite, dpi >= Self.minDPI, dpi <= Self.maxDPI else { throw PDFVisualDiffError.invalidResolution(dpi) }
        guard pageSize.width.isFinite, pageSize.height.isFinite, pageSize.width > 0, pageSize.height > 0 else {
            throw PDFVisualDiffError.invalidPageSize(width: Double(pageSize.width), height: Double(pageSize.height))
        }
        let (area, areaOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, bytesOverflow) = area.multipliedReportingOverflow(by: 3)
        guard width > 0, height > 0, !areaOverflow, !bytesOverflow, pixels.count == bytes else {
            throw PDFVisualDiffError.invalidRaster(width: width, height: height, bytes: pixels.count)
        }
        self.width = width
        self.height = height
        self.dpi = dpi
        self.pageSize = pageSize
        self.pixels = pixels
    }

    /// Bitmap pixels per bp.
    public var scale: Double { dpi / 72 }

    /// The lowest resolution accepted; far below it the scale can vanish.
    public static let minDPI = 1.0
    /// The highest resolution accepted.
    public static let maxDPI = 2400.0
    /// The largest bitmap accepted, in pixels. One render needs about 7 bytes
    /// per pixel while it runs (RGBA bitmap plus the RGB copy) and keeps 3. A
    /// verification holds three renders and D (6 bytes per pixel), about 15
    /// bytes per pixel, so this keeps one verification under roughly 1.5 GB.
    public static let maxPixelCount = 100_000_000

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

    public static func render(url: URL, pageIndex: Int = 0, dpi: Double = 144, canvasHeight: Int? = nil) throws -> PageRaster {
        try render(page: page(url: url, index: pageIndex), dpi: dpi, canvasHeight: canvasHeight)
    }

    /// The bitmap height that pages of these heights (in bp) share when they
    /// are to be compared: CoreGraphics' anti-aliasing is not invariant under
    /// the bitmap height, so renders compared pixel by pixel use one height
    /// and are cropped to their own afterwards.
    ///
    /// A resolution or height that no render accepts contributes 1, which
    /// never raises the canvas, so the render that follows reports the error
    /// instead of this function trapping on the conversion to `Int`.
    public static func canvasHeight(heights: [CGFloat], dpi: Double) -> Int {
        guard dpi.isFinite, dpi > 0 else { return 1 }
        let scale = dpi / 72
        return heights.map { height -> Int in
            let rows = (Double(height) * scale).rounded(.up)
            guard rows.isFinite, rows >= 1 else { return 1 }
            return Int(min(Double(maxPixelCount), rows))
        }.max() ?? 1
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

    /// `canvasHeight`, when larger than the page's own bitmap height, is the
    /// height the page is drawn into (top-aligned) before the bitmap is cropped
    /// to the page; see `canvasHeight(heights:dpi:)`.
    public static func render(page: CGPDFPage, dpi: Double = 144, canvasHeight: Int? = nil) throws -> PageRaster {
        try render(page: page, dpi: dpi, clip: nil, canvasHeight: canvasHeight)
    }

    /// Renders `page`; when `clip` is given (rectangles in PDF page
    /// coordinates), only the part of the page inside their union is drawn.
    /// The transform is the same as for a full render, so pixels line up
    /// with a full render.
    static func render(page: CGPDFPage, dpi: Double, clip: [CGRect]?, canvasHeight: Int? = nil) throws -> PageRaster {
        guard dpi.isFinite, dpi >= minDPI, dpi <= maxDPI else { throw PDFVisualDiffError.invalidResolution(dpi) }
        let rotation = ((Int(page.rotationAngle) % 360) + 360) % 360
        guard rotation == 0 else { throw PDFVisualDiffError.unsupportedRotation(degrees: rotation) }

        let box = page.getBoxRect(.cropBox)
        let scale = dpi / 72
        let w = (box.width * scale).rounded(.up), h = (box.height * scale).rounded(.up)
        guard w.isFinite, h.isFinite, w >= 1, h >= 1, w * h <= Double(maxPixelCount) else {
            throw PDFVisualDiffError.bitmapTooLarge(width: w, height: h, limit: maxPixelCount)
        }
        let width = Int(w), height = Int(h)
        let canvas = max(height, canvasHeight ?? height)
        guard Double(width) * Double(canvas) <= Double(maxPixelCount) else {
            throw PDFVisualDiffError.bitmapTooLarge(width: w, height: Double(canvas), limit: maxPixelCount)
        }
        guard
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: canvas, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw PDFVisualDiffError.bitmapContextUnavailable(width: width, height: canvas)
        }

        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: canvas))
        // Put the box's top-left corner at the bitmap's top-left corner; the
        // first `height` rows in memory are the page.
        context.translateBy(x: 0, y: CGFloat(canvas))
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
        return try PageRaster(width: width, height: height, dpi: dpi, pageSize: box.size, pixels: rgb)
    }
}
