import XCTest
@testable import TwinFiles

final class FileListingTests: XCTestCase {
    private func entry(_ name: String, folder: Bool = false, size: Int64 = 0, time: TimeInterval = 0) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/fixture/" + name), name: name, isDirectory: folder,
                  size: size, modified: Date(timeIntervalSince1970: time))
    }

    func testFoldersStayAboveFilesForEveryColumnAndDirection() {
        let entries = [entry("a.txt", size: 1, time: 1), entry("z-folder", folder: true, size: 100, time: 100),
                       entry("z.txt", size: 200, time: 200), entry("a-folder", folder: true)]
        for key in ["name", "size", "modified"] {
            for ascending in [true, false] {
                let result = FileListing.filterAndSort(entries, query: "", kind: .all, extensions: "", sortKey: key, ascending: ascending)
                XCTAssertEqual(result.map(\.isDirectory), [true, true, false, false], "\(key) ascending=\(ascending)")
                XCTAssertEqual(result.suffix(2).map(\.name), ascending ? ["a.txt", "z.txt"] : ["z.txt", "a.txt"])
            }
        }
    }

    func testCombinedFiltersKeepNavigableFolders() {
        let entries = [entry("Folder", folder: true), entry("report.PDF"), entry("report.txt"), entry("photo.png")]
        let result = FileListing.filterAndSort(entries, query: "", kind: .document, extensions: ".pdf, PNG", sortKey: "name", ascending: false)
        XCTAssertEqual(result.map(\.name), ["Folder", "report.PDF"])
        let named = FileListing.filterAndSort(entries, query: "report", kind: .all, extensions: "pdf", sortKey: "name", ascending: true)
        XCTAssertEqual(named.map(\.name), ["report.PDF"])
    }

    func testSuffixSyntaxCompoundExtensionsAndNoExtension() {
        let entries = [entry("a.JPG"), entry("b.png"), entry("c.tar.gz"), entry("d.notpng"), entry("README")]
        let result = FileListing.filterAndSort(entries, query: "", kind: .all, extensions: "*.jpg； .PNG，tar.gz", sortKey: "name", ascending: true)
        XCTAssertEqual(result.map(\.name), ["a.JPG", "b.png", "c.tar.gz"])
        let plain = FileListing.filterAndSort(entries, query: "", kind: .all, extensions: FileListing.noExtension, sortKey: nil, ascending: true)
        XCTAssertEqual(plain.map(\.name), ["README"])
        let all = FileListing.filterAndSort(entries, query: "", kind: .all, extensions: FileListing.allExtensions, sortKey: nil, ascending: true)
        XCTAssertEqual(all.count, entries.count)
    }

    func testCommonFileTypes() {
        for (suffix, kind): (String, FileKind) in [("PNG", .image), ("mp3", .audio), ("mp4", .video), ("docx", .document), ("swift", .code), ("dmg", .archive), ("", .other)] {
            XCTAssertEqual(FileKind.classify(extension: suffix), kind, suffix)
        }
    }
}
