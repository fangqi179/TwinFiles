import XCTest
@testable import TwinFiles

final class FileActionsTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TwinFilesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func file(_ name: String, in directory: URL? = nil, text: String = "original") throws -> URL {
        let url = (directory ?? root).appendingPathComponent(name)
        try Data(text.utf8).write(to: url); return url
    }
    func testCopyPreservesSourceAndCollisionContents() throws {
        let source = try file("report.txt")
        let destination = try folder("target")
        let existing = try file("report.txt", in: destination, text: "keep me")
        let copy = try FileActions.transfer(source, to: destination, mode: .copy)
        XCTAssertNotEqual(copy, existing)
        XCTAssertEqual(try String(contentsOf: existing), "keep me")
        XCTAssertEqual(try String(contentsOf: copy), "original")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testMoveAndSameDirectoryNoOp() throws {
        let source = try file("move.txt")
        XCTAssertEqual(try FileActions.transfer(source, to: root, mode: .move), source)
        let target = try FileActions.transfer(source, to: folder("target"), mode: .move)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try String(contentsOf: target), "original")
    }
    func testRejectsRecursiveCopyIncludingSymlinkDestination() throws {
        let source = try folder("parent")
        let child = source.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        XCTAssertThrowsError(try FileActions.transfer(source, to: source, mode: .copy))
        XCTAssertThrowsError(try FileActions.transfer(source, to: child, mode: .move))
        let link = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: child)
        XCTAssertThrowsError(try FileActions.transfer(source, to: link, mode: .copy))
    }
    func testFolderCollisionNeverMergesOrOverwrites() throws {
        let source = try folder("source")
        _ = try file("nested.txt", in: source)
        let target = try folder("target")
        let existing = target.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        _ = try file("preserved.txt", in: existing)
        let copy = try FileActions.transfer(source, to: target, mode: .copy)
        XCTAssertNotEqual(copy, existing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.appendingPathComponent("preserved.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.appendingPathComponent("nested.txt").path))
    }
    func testHiddenFilesAndPackages() throws {
        _ = try file("visible.txt"); _ = try file(".hidden")
        _ = try folder("ordinary")
        _ = try folder("Demo.app")
        let entries = try FileEntry.contents(of: root, showHidden: false)
        XCTAssertFalse(entries.contains { $0.name == ".hidden" })
        XCTAssertTrue(entries.first { $0.name == "ordinary" }!.isDirectory)
        XCTAssertFalse(entries.first { $0.name == "Demo.app" }!.isDirectory)
        XCTAssertTrue(try FileEntry.contents(of: root, showHidden: true).contains { $0.name == ".hidden" })
    }
    func testNameValidation() throws {
        for name in ["", ".", "..", "a/b", "a\0b"] { XCTAssertThrowsError(try FileActions.validateName(name)) }
        try FileActions.validateName("正常 文件.txt")
    }
    func testDirectorySymlinkCanBeBrowsed() throws {
        let directory = try folder("actual")
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let entries = try FileEntry.contents(of: root, showHidden: true)
        XCTAssertTrue(entries.first { $0.name == "linked" }!.isDirectory)
    }
    func testRepeatedCollisionAndExtensionlessFile() throws {
        _ = try file("README")
        _ = try file("README 副本 2")
        XCTAssertEqual(FileActions.availableURL(in: root, name: "README").lastPathComponent, "README 副本 3")
    }
}
