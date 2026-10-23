import Foundation
import UniformTypeIdentifiers

enum FileKind: String, CaseIterable {
    case all = "全部类型", image = "图片", audio = "音频", video = "视频"
    case document = "文档", archive = "压缩包与镜像", code = "代码", other = "其他"

    static func classify(extension suffix: String) -> FileKind {
        let suffix = suffix.lowercased()
        // Common formats also work when the Launch Services database is unavailable.
        if ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "tif", "tiff", "bmp", "svg", "ico", "icns", "raw", "dng", "cr2", "nef", "arw", "psd"].contains(suffix) { return .image }
        if ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "ogg", "opus", "amr", "mid", "midi"].contains(suffix) { return .audio }
        if ["mp4", "mov", "m4v", "mkv", "avi", "webm", "wmv", "mpg", "mpeg", "m2ts", "mts", "flv", "3gp"].contains(suffix) { return .video }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "zst", "dmg", "iso", "pkg"].contains(suffix) { return .archive }
        if ["swift", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs", "c", "h", "cpp", "hpp", "java", "kt", "sh", "zsh", "css", "html", "json", "yaml", "yml", "xml", "sql", "toml"].contains(suffix) { return .code }
        if ["pdf", "txt", "md", "rtf", "rtfd", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "pages", "numbers", "key", "epub"].contains(suffix) { return .document }
        guard let type = UTType(filenameExtension: suffix) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .document }
        return .other
    }
}

enum FileListing {
    static let noExtension = "无后缀"
    static let allExtensions = "全部后缀"

    static func filterAndSort(_ entries: [FileEntry], query: String, kind: FileKind,
                              extensions text: String, sortKey: String?, ascending: Bool) -> [FileEntry] {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = Set(input.lowercased().components(separatedBy: CharacterSet(charactersIn: ",，;； \t\n"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*.")) }.filter { !$0.isEmpty })
        let anySuffix = input.isEmpty || input == allExtensions
        var kinds: [String: FileKind] = [:]
        return entries.filter { entry in
            guard query.isEmpty || entry.name.localizedStandardContains(query) else { return false }
            // Keep folders available for navigation regardless of file filters.
            if entry.isDirectory { return true }
            let suffix = entry.url.pathExtension.lowercased()
            if !anySuffix {
                if input == noExtension { if !suffix.isEmpty { return false } }
                else if !suffixes.contains(where: { entry.name.lowercased().hasSuffix("." + $0) }) { return false }
            }
            if kind != .all {
                let classified = kinds[suffix] ?? FileKind.classify(extension: suffix)
                kinds[suffix] = classified
                if classified != kind { return false }
            }
            return true
        }.sorted {
            // This comparison must precede the sort direction for every column.
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            switch sortKey {
            case "size" where $0.size != $1.size: return ascending ? $0.size < $1.size : $0.size > $1.size
            case "modified" where $0.modified != $1.modified: return ascending ? $0.modified < $1.modified : $0.modified > $1.modified
            default:
                let order = $0.name.localizedStandardCompare($1.name)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
    }
}
