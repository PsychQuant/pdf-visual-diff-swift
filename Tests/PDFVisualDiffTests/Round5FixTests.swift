import Foundation
import Testing
@testable import PDFVisualDiff

@Suite("Verification round 5 fixes")
struct Round5FixTests {

    @Test("a failed artifact write names the path and carries the Foundation error code")
    func artifactWriteFailureIsStructured() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pvd-r5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blocker)
        let raster = try PageRaster(width: 1, height: 1, dpi: 72, pageSize: CGSize(width: 1, height: 1),
                                    pixels: [255, 255, 255])
        let diff = try SignedDiff(original: raster, output: raster)
        let error = #expect(throws: PDFVisualDiffError.self) {
            try DiffArtifacts.write(diff: diff, identical: true, to: blocker)
        }
        guard case let .artifactWriteFailed(path, code) = try #require(error) else {
            Issue.record("expected artifactWriteFailed, got \(String(describing: error))")
            return
        }
        #expect(path == blocker.path)
        #expect(code != nil)
        #expect(!String(describing: error!).contains("couldn’t"))
    }
}
