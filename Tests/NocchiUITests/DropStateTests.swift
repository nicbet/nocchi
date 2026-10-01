import Foundation
import Testing
@testable import NocchiUI

@Suite struct DropStateTests {
    @Test func foldersStartInThemselvesFilesInTheirFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nocchi-drop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "notes.md")
        try Data().write(to: file)
        #expect(DropState.folder(for: dir).standardizedFileURL == dir.standardizedFileURL)
        #expect(DropState.folder(for: file).standardizedFileURL == dir.standardizedFileURL)
    }

    @Test func progressEasesTowardNinetyPercentAndWaits() {
        #expect(DropState.progress(after: 0) == 0)
        #expect(DropState.progress(after: -1) == 0)
        #expect(DropState.progress(after: 1) < DropState.progress(after: 2))
        #expect(DropState.progress(after: 60) <= 0.9)
        #expect(DropState.progress(after: 60) > 0.89)
    }
}
