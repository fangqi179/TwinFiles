import Foundation

/// Shared by both panes. Store paths without requiring the volume to be mounted.
enum DirectoryFavorites {
    private static let key = "favoriteDirectories"

    static var directories: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
    }

    static func contains(_ directory: URL) -> Bool {
        directories.contains { $0.standardizedFileURL.path == directory.standardizedFileURL.path }
    }

    static func toggle(_ directory: URL) {
        if contains(directory) { remove(directory); return }
        var paths = directories.map(\.path)
        paths.append(directory.standardizedFileURL.path)
        UserDefaults.standard.set(paths, forKey: key)
    }

    static func remove(_ directory: URL) {
        let paths = directories.filter {
            $0.standardizedFileURL.path != directory.standardizedFileURL.path
        }.map(\.path)
        UserDefaults.standard.set(paths, forKey: key)
    }
}
