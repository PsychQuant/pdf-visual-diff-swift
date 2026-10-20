/// Threshold-free pixel verification for PDFs produced from other PDFs.
///
/// Both documents are rendered by the same renderer (CoreGraphics), compared
/// pixel by pixel and channel by channel, and every differing pixel has to be
/// explained by the caller's intent: an overlay that was added on purpose, or
/// a region that is allowed to change. Nothing is filtered or thresholded.
public enum PDFVisualDiff {}
