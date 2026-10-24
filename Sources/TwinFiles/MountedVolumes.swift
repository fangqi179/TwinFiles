import AppKit

struct MountedVolume {
    let url: URL
    let name: String
    let isInternal: Bool

    func contains(_ directory: URL) -> Bool {
        let root = url.standardizedFileURL.path
        let path = directory.standardizedFileURL.path
        return root == "/" || path == root || path.hasPrefix(root + "/")
    }

    static func sorted(_ volumes: [MountedVolume]) -> [MountedVolume] {
        volumes.sorted {
            if $0.isInternal != $1.isInternal { return !$0.isInternal }
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }
}

/// Enumerate once for both panes, away from the AppKit thread.
final class MountedVolumes {
    static let shared = MountedVolumes()
    static let didChange = Notification.Name("TwinFiles.MountedVolumesDidChange")
    private(set) var volumes: [MountedVolume] = []
    private let queue = DispatchQueue(label: "dev.local.TwinFiles.volumes", qos: .userInitiated)
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }
        refresh()
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func refresh() {
        queue.async {
            let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsBrowsableKey]
            let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
            let volumes = MountedVolume.sorted(urls.compactMap { url -> MountedVolume? in
                guard let values = try? url.resourceValues(forKeys: keys), values.volumeIsBrowsable != false else { return nil }
                return MountedVolume(url: url, name: values.volumeName ?? url.lastPathComponent,
                                     isInternal: values.volumeIsInternal ?? true)
            })
            DispatchQueue.main.async {
                self.volumes = volumes
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }
}
