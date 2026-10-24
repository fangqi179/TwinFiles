import XCTest
@testable import TwinFiles

final class MountedVolumesTests: XCTestCase {
    func testExternalVolumesSortBeforeInternalVolumesWithNaturalNames() {
        let volumes = [volume("Macintosh HD", internalDisk: true), volume("USB 10"), volume("USB 2")]
        XCTAssertEqual(MountedVolume.sorted(volumes).map(\.name), ["USB 2", "USB 10", "Macintosh HD"])
    }

    func testVolumeContainsItsRootAndChildrenButNotSimilarlyNamedVolumes() {
        let disk = volume("备份 磁盘")
        XCTAssertTrue(disk.contains(disk.url))
        XCTAssertTrue(disk.contains(disk.url.appendingPathComponent("资料/报告")))
        XCTAssertFalse(disk.contains(URL(fileURLWithPath: "/Volumes/备份 磁盘 2/资料")))
        XCTAssertFalse(disk.contains(URL(fileURLWithPath: "/Users/test")))
        XCTAssertTrue(disk.contains(disk.url.appendingPathComponent("资料/..")))
    }

    func testRootVolumeContainsHomeAndDuplicateNamesHaveStableOrder() {
        let root = MountedVolume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isInternal: true)
        XCTAssertTrue(root.contains(URL(fileURLWithPath: "/Users/test")))
        let first = MountedVolume(url: URL(fileURLWithPath: "/Volumes/A"), name: "USB", isInternal: false)
        let second = MountedVolume(url: URL(fileURLWithPath: "/Volumes/B"), name: "USB", isInternal: false)
        XCTAssertEqual(MountedVolume.sorted([second, first]).map(\.url), [first.url, second.url])
    }

    private func volume(_ name: String, internalDisk: Bool = false) -> MountedVolume {
        MountedVolume(url: URL(fileURLWithPath: "/Volumes/" + name, isDirectory: true), name: name, isInternal: internalDisk)
    }
}
