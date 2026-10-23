import Foundation

struct FileEntry {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date

    static func contents(of directory: URL, showHidden: Bool) throws -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: showHidden ? [] : [.skipsHiddenFiles])
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            var isDirectory = values?.isDirectory == true
            if values?.isSymbolicLink == true {
                var targetIsDirectory: ObjCBool = false
                _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &targetIsDirectory)
                isDirectory = targetIsDirectory.boolValue
            }
            // Package lookup can fail independently (for example when Launch Services
            // is unavailable). Never discard the basic file metadata with it.
            let package = isDirectory ? (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) : false
            let knownPackages = ["app", "bundle", "framework", "plugin", "xcodeproj", "xcworkspace", "photoslibrary", "pages", "numbers", "key", "rtfd", "playground"]
            let isPackage = package ?? knownPackages.contains(url.pathExtension.lowercased())
            return FileEntry(url: url, name: url.lastPathComponent,
                             isDirectory: isDirectory && !isPackage,
                             size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate ?? .distantPast)
        }
    }
}

enum TransferMode { case copy, move }

enum FileActionError: LocalizedError {
    case invalidDestination, invalidName
    var errorDescription: String? {
        switch self {
        case .invalidDestination: return "不能将文件夹放入自身或其子文件夹中。"
        case .invalidName: return "名称不能为空，不能包含斜杠，也不能是 . 或 ..。"
        }
    }
}

enum FileActions {
    static func validateName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw FileActionError.invalidName }
    }

    static func availableURL(in directory: URL, name: String) -> URL {
        let original = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let ext = original.pathExtension
        let stem = ext.isEmpty ? name : original.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) 副本 \(index)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    @discardableResult
    static func transfer(_ source: URL, to directory: URL, mode: TransferMode) throws -> URL {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard sourcePath != "/", destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else { throw FileActionError.invalidDestination }
        if mode == .move && source.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL { return source }
        let target = availableURL(in: directory, name: source.lastPathComponent)
        switch mode {
        case .copy: try FileManager.default.copyItem(at: source, to: target)
        case .move: try FileManager.default.moveItem(at: source, to: target)
        }
        return target
    }
}
