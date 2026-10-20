# pdf-visual-diff-swift

Threshold-free pixel verification for PDFs that are produced from other PDFs.

Both documents are rendered by CoreGraphics at the same resolution, aligned at
the top-left corner, and compared pixel by pixel and channel by channel as a
signed difference `D = output − original`. Nothing is thresholded, binarized
or filtered: every differing pixel has to be explained by the caller's intent.

Part of the macdoc toolchain ([PsychQuant/macdoc#240](https://github.com/PsychQuant/macdoc/issues/240)).

## Usage

```swift
import PDFVisualDiff

let original = try PageRaster.render(url: blankForm, pageIndex: 0, dpi: 144)
let output   = try PageRaster.render(url: filledForm, pageIndex: 0, dpi: 144)
let overlay  = try PageRaster.render(url: overlayOnly, pageIndex: 0, dpi: 144)

let result = try OverlayVerifier.verify(original: original, output: output, overlay: overlay)
for check in result.report.checks {
    print(check.check, check.count, check.bands)
}
try DiffArtifacts.write(diff: result.diff, checks: result.report.checks, to: diffDirectory)
```

## What is checked

| Check | Fails when |
|---|---|
| `differenceOutsideOverlay` | D is non-zero where the overlay rendered alone is pure white |
| `originalMadeLighter` | D > 0 in any channel: ink of the original was covered or removed |
| `overlayInkOnOriginalInk` | overlay and original both have ink at a pixel (D is ~0 there, so the difference alone cannot show it) |
| `inkInCroppedStrip` | the original has ink outside the output's size |

`PreservedRegions.check(_:diff:)` requires D = 0 inside given rectangles (bp,
top-left origin) for workflows that redo most of a page but must keep some
regions identical.

`PageGeometry` defines A4 as 210 × 297 mm (595.2756 × 841.8898 bp, not the
rounded 595 × 842), classifies sizes as exact A4, near A4 (within 1.5 bp) or
other, and finds ink in the strip that a top-left crop to A4 would remove.

`DiffArtifacts.write` produces `diff_signed.png` (floor(128 + D/2)),
`diff_abs.png` (255 − |D|), `diff.bin` (D as little-endian Int16, height ×
width × 3) and `report.json`.

## Conventions

- Positions are reported in bp (1/72 inch) with a top-left origin.
- Only unrotated pages are supported.
- Results are only meaningful within one renderer; this package always uses CoreGraphics.

## License

MIT
