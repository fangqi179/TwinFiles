import AppKit
import Quartz

final class FileTable: NSTableView {
    weak var pane: PaneController?
    override func becomeFirstResponder() -> Bool {
        pane?.activate()
        return super.becomeFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            pane?.preview(); return
        }
        if event.keyCode == 36 { pane?.openSelection(); return }
        if event.keyCode == 51 && !event.modifierFlags.contains(.command) { pane?.goUp(); return }
        super.keyDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        pane?.activate()
        return pane?.contextMenu()
    }
}

final class PaneController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSComboBoxDelegate, QLPreviewPanelDataSource {
    let side: String
    weak var owner: MainWindowController?
    private(set) var directory: URL
    private var entries: [FileEntry] = []
    private var visible: [FileEntry] = []
    private var history: [URL] = []
    private var historyIndex = -1
    private var generation = 0
    private let filterQueue = DispatchQueue(label: "dev.local.TwinFiles.filter", qos: .userInitiated)
    private var filterCancellation = CancellationFlag()
    private var monitor: DispatchSourceFileSystemObject?
    private var refreshWork: DispatchWorkItem?
    private var icons: [URL: NSImage] = [:]
    private var previewURLs: [URL] = []
    private var isLoading = false
    private var lastError: String?
    let table = FileTable()
    private let pathButton = NSButton()
    private let pathField = NSTextField()
    private let search = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let typeFilter = NSPopUpButton()
    private let extensionFilter = NSComboBox()
    private let heading = NSTextField(labelWithString: "")
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let refreshIndicator = NSProgressIndicator()
    private let header = NSView()
    private let formatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; return f
    }()

    var selectedURLs: [URL] { table.selectedRowIndexes.compactMap { $0 < visible.count ? visible[$0].url : nil } }
    var showHidden: Bool { UserDefaults.standard.bool(forKey: "showHidden") }

    init(side: String) {
        self.side = side
        let home = FileManager.default.homeDirectoryForCurrentUser
        let saved = UserDefaults.standard.string(forKey: "directory.\(side)")
        let candidate = saved.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? home
        var isDirectory: ObjCBool = false
        directory = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) && isDirectory.boolValue ? candidate : home
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { monitor?.cancel() }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        header.wantsLayer = true
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let places = makeButton("folder", "常用位置与收藏", #selector(showPlaces(_:)))
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "后退")
        backButton.target = self; backButton.action = #selector(back)
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "前进")
        forwardButton.target = self; forwardButton.action = #selector(forward)
        for button in [backButton, forwardButton] { button.bezelStyle = .texturedRounded; button.isBordered = false; button.widthAnchor.constraint(equalToConstant: 24).isActive = true }
        backButton.toolTip = "后退 ⌘["; forwardButton.toolTip = "前进 ⌘]"
        let up = makeButton("arrow.up", "上级目录 ⌘↑", #selector(goUp))
        let refresh = makeButton("arrow.clockwise", "刷新 ⌘R", #selector(reload))
        refreshIndicator.style = .spinning; refreshIndicator.controlSize = .small; refreshIndicator.isDisplayedWhenStopped = false
        pathField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathField.controlSize = .small
        pathField.placeholderString = "输入目录路径并回车（⌘L）"
        pathField.isHidden = true
        pathField.target = self; pathField.action = #selector(pathEntered); pathField.delegate = self
        pathField.lineBreakMode = .byTruncatingMiddle
        pathButton.title = directory.path
        pathButton.font = pathField.font; pathButton.controlSize = .small
        pathButton.bezelStyle = .texturedRounded; pathButton.alignment = .left
        pathButton.lineBreakMode = .byTruncatingMiddle
        pathButton.toolTip = "点击复制当前目录完整路径并编辑；回车前往目录（⌘L）"
        pathButton.setAccessibilityLabel("复制并编辑当前目录路径")
        pathButton.target = self; pathButton.action = #selector(copyAndEditDirectoryPath)
        search.placeholderString = "筛选当前目录"; search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self; search.action = #selector(filterChanged)
        search.controlSize = .small; search.font = .systemFont(ofSize: 11)
        let top = NSStackView(views: [heading, places, backButton, forwardButton, up, pathButton, pathField, refreshIndicator, refresh])
        top.spacing = 3; top.distribution = .fill
        top.detachesHiddenViews = true
        pathButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let headerStack = NSStackView(views: [top, search])
        headerStack.orientation = .vertical; headerStack.alignment = .leading; headerStack.spacing = 4; headerStack.distribution = .fill
        header.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        for child in [top, search] { child.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            top.heightAnchor.constraint(equalToConstant: 24), search.heightAnchor.constraint(equalToConstant: 22),
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8), headerStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            headerStack.topAnchor.constraint(equalTo: header.topAnchor, constant: 5), headerStack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -5)
        ])
        table.pane = self; table.dataSource = self; table.delegate = self
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.rowHeight = 26; table.intercellSpacing = NSSize(width: 8, height: 0)
        table.style = .fullWidth; table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("name", "名称", 260.0), ("size", "大小", 84.0), ("modified", "修改日期", 144.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title; column.width = width; column.minWidth = id == "name" ? 120 : 65
            column.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            if id == "name" { column.resizingMask = .autoresizingMask }
            table.addTableColumn(column)
        }
        table.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        table.target = self; table.doubleAction = #selector(openSelection)
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        typeFilter.addItems(withTitles: FileKind.allCases.map(\.rawValue))
        typeFilter.controlSize = .small; typeFilter.font = .systemFont(ofSize: 11)
        typeFilter.target = self; typeFilter.action = #selector(filterChanged)
        typeFilter.setAccessibilityLabel("文件类型筛选")
        typeFilter.toolTip = "筛选文件类型，文件夹始终保留在上方"
        extensionFilter.controlSize = .small; extensionFilter.font = .systemFont(ofSize: 11)
        extensionFilter.placeholderString = "后缀：jpg, png"
        extensionFilter.completes = false; extensionFilter.delegate = self
        extensionFilter.target = self; extensionFilter.action = #selector(filterChanged)
        extensionFilter.setAccessibilityLabel("文件后缀筛选")
        extensionFilter.toolTip = "选择当前目录的后缀，或输入多个后缀（逗号分隔，不区分大小写）"
        let clear = NSButton(image: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "重置筛选")!, target: self, action: #selector(resetFileFilters))
        clear.controlSize = .small; clear.isBordered = false
        clear.toolTip = "清除类型和后缀筛选"
        let filters = NSStackView(views: [typeFilter, extensionFilter, clear, status])
        filters.spacing = 6; filters.distribution = .fill
        typeFilter.widthAnchor.constraint(equalToConstant: 104).isActive = true
        extensionFilter.widthAnchor.constraint(greaterThanOrEqualToConstant: 96).isActive = true
        extensionFilter.setContentHuggingPriority(.defaultLow, for: .horizontal)
        extensionFilter.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        clear.widthAnchor.constraint(equalToConstant: 22).isActive = true
        status.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        status.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
        let footer = NSView()
        footer.addSubview(filters); filters.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            filters.centerYAnchor.constraint(equalTo: footer.centerYAnchor), filters.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 8), filters.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -8), filters.heightAnchor.constraint(equalToConstant: 24), footer.heightAnchor.constraint(equalToConstant: 32)
        ])
        for child in [header, scroll, footer] { view.addSubview(child); child.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor), header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor), footer.leadingAnchor.constraint(equalTo: view.leadingAnchor), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigate(to: directory)
    }

    private func makeButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)!, target: self, action: action)
        button.bezelStyle = .texturedRounded; button.isBordered = false; button.toolTip = tooltip
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }
    func activate() { owner?.setActive(self) }
    func setActiveAppearance(_ active: Bool) {
        header.layer?.backgroundColor = (active ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.controlBackgroundColor).cgColor
        heading.textColor = active ? .controlAccentColor : .labelColor
        heading.stringValue = side == "left" ? "左栏" : "右栏"
        heading.toolTip = directory.path
    }
    func focusPath() {
        activate()
        if pathField.isHidden { pathField.stringValue = directory.path }
        pathButton.isHidden = true; pathField.isHidden = false
        view.window?.makeFirstResponder(pathField); pathField.selectText(nil)
    }
    @objc func copyDirectoryPath() { activate(); owner?.copyPaths([directory]) }
    @objc private func copyAndEditDirectoryPath() {
        copyDirectoryPath()
        focusPath()
    }
    func focusSearch() { activate(); view.window?.makeFirstResponder(search) }
    @objc private func pathEntered() {
        activate()
        let path = (pathField.stringValue as NSString).expandingTildeInPath
        view.window?.makeFirstResponder(table)
        navigate(to: URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL)
    }
    func navigate(to url: URL, record: Bool = true) {
        let url = url.standardizedFileURL
        generation += 1
        let token = generation
        isLoading = true; lastError = nil; refreshIndicator.startAnimation(nil); updateStatus()
        let hidden = showHidden
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try FileEntry.contents(of: url, showHidden: hidden) }
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.isLoading = false; self.refreshIndicator.stopAnimation(nil)
                switch result {
                case .success(let entries):
                    let selection = self.directory == url ? Set(self.selectedURLs) : []
                    if self.directory != url { self.search.stringValue = ""; self.visible = []; self.table.reloadData() }
                    self.directory = url; self.entries = entries; self.icons.removeAll(keepingCapacity: true)
                    self.updateExtensionChoices()
                    if record && (self.historyIndex < 0 || self.history[self.historyIndex] != url) {
                        self.history = Array(self.history.prefix(self.historyIndex + 1)); self.history.append(url); self.historyIndex = self.history.count - 1
                    }
                    self.pathField.stringValue = url.path
                    self.pathButton.title = url.path
                    UserDefaults.standard.set(url.path, forKey: "directory.\(self.side)")
                    self.applyFilter(selection: selection); self.watchDirectory()
                    self.setActiveAppearance(self.owner?.activePane === self)
                case .failure(let error):
                    self.lastError = error.localizedDescription; self.pathField.stringValue = self.directory.path
                    self.owner?.showError(error)
                }
                self.backButton.isEnabled = self.historyIndex > 0
                self.forwardButton.isEnabled = self.historyIndex + 1 < self.history.count
                self.updateStatus()
            }
        }
    }
    @objc func reload() { navigate(to: directory, record: false) }
    @objc func back() { activate(); guard historyIndex > 0 else { return }; historyIndex -= 1; navigate(to: history[historyIndex], record: false) }
    @objc func forward() { activate(); guard historyIndex + 1 < history.count else { return }; historyIndex += 1; navigate(to: history[historyIndex], record: false) }
    @objc func goUp() { activate(); navigate(to: directory.deletingLastPathComponent()) }
    @objc private func filterChanged() { activate(); applyFilter(selection: Set(selectedURLs)) }
    func controlTextDidBeginEditing(_ obj: Notification) { activate() }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === pathField else { return }
        // AppKit can end and restart field editing while focus is being assigned.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let editor = self.pathField.currentEditor(), self.view.window?.firstResponder === editor { return }
            self.pathField.isHidden = true; self.pathButton.isHidden = false
        }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === pathField, commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        view.window?.makeFirstResponder(table)
        return true
    }
    func controlTextDidChange(_ obj: Notification) {
        if obj.object as? NSComboBox === extensionFilter { filterChanged() }
    }
    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let value = extensionFilter.objectValueOfSelectedItem as? String else { return }
        extensionFilter.stringValue = value == FileListing.allExtensions ? "" : value
        filterChanged()
    }
    @objc private func resetFileFilters() {
        typeFilter.selectItem(at: 0); extensionFilter.stringValue = ""
        if extensionFilter.indexOfSelectedItem >= 0 { extensionFilter.deselectItem(at: extensionFilter.indexOfSelectedItem) }
        filterChanged()
    }
    private func updateExtensionChoices() {
        let value = extensionFilter.stringValue
        let files = entries.filter { !$0.isDirectory }
        let suffixes = Set(files.map { $0.url.pathExtension.lowercased() }.filter { !$0.isEmpty }).sorted()
        extensionFilter.removeAllItems()
        extensionFilter.addItems(withObjectValues: [FileListing.allExtensions] + (files.contains { $0.url.pathExtension.isEmpty } ? [FileListing.noExtension] : []) + suffixes.map { "." + $0 })
        extensionFilter.stringValue = value
    }
    private func applyFilter(selection: Set<URL>) {
        let query = search.stringValue
        let key = table.sortDescriptors.first?.key
        let ascending = table.sortDescriptors.first?.ascending ?? true
        // NSTableView sends an initial sort notification while loadView is
        // still configuring the filter controls.
        let kind = typeFilter.titleOfSelectedItem.flatMap(FileKind.init(rawValue:)) ?? .all
        let suffixes = extensionFilter.stringValue
        let snapshot = entries
        filterCancellation.cancel(); filterCancellation = CancellationFlag()
        let cancellation = filterCancellation
        filterQueue.async { [weak self] in
            guard !cancellation.isCancelled else { return }
            let sorted = FileListing.filterAndSort(snapshot, query: query, kind: kind, extensions: suffixes, sortKey: key, ascending: ascending)
            DispatchQueue.main.async {
                guard let self, !cancellation.isCancelled else { return }
                self.visible = sorted; self.table.reloadData()
                self.table.selectRowIndexes(IndexSet(sorted.indices.filter { selection.contains(sorted[$0].url) }), byExtendingSelection: false)
                self.updateStatus()
            }
        }
    }
    private func updateStatus() {
        defer { status.toolTip = status.stringValue }
        if isLoading { status.stringValue = "正在读取…"; return }
        if let lastError { status.stringValue = lastError; return }
        let selected = selectedURLs.count
        let size = table.selectedRowIndexes.reduce(Int64(0)) { $0 + ($1 < visible.count && !visible[$1].isDirectory ? visible[$1].size : 0) }
        status.stringValue = "\(visible.count) 个项目" + (visible.count != entries.count ? "（共 \(entries.count) 个）" : "") + (selected > 0 ? "  ·  已选 \(selected) 个  ·  \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))" : "")
    }
    private func watchDirectory() {
        monitor?.cancel(); monitor = nil
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reload() }
            self.refreshWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        source.setCancelHandler { close(descriptor) }
        monitor = source; source.resume()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = visible[row]
        let id = tableColumn!.identifier
        if id.rawValue == "name" {
            let cell: NSTableCellView
            if let existing = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView { cell = existing }
            else {
                cell = NSTableCellView(); cell.identifier = id
                let icon = NSImageView(); let label = NSTextField(labelWithString: "")
                label.font = .systemFont(ofSize: 13); label.lineBreakMode = .byTruncatingMiddle
                cell.addSubview(icon); cell.addSubview(label); icon.translatesAutoresizingMaskIntoConstraints = false; label.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = icon; cell.textField = label
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            }
            cell.textField?.stringValue = entry.name
            if icons[entry.url] == nil { icons[entry.url] = NSWorkspace.shared.icon(forFile: entry.url.path) }
            cell.imageView?.image = icons[entry.url]; cell.toolTip = entry.name
            return cell
        }
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView { cell = existing }
        else {
            cell = NSTableCellView(); cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.alignment = id.rawValue == "size" ? .right : .left
            cell.addSubview(label); cell.textField = label; label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        cell.textField?.stringValue = id.rawValue == "size" ? (entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)) : formatter.string(from: entry.modified)
        return cell
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { applyFilter(selection: Set(selectedURLs)) }
    func tableViewSelectionDidChange(_ notification: Notification) { updateStatus(); if owner?.activePane === self, QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared()?.isVisible == true { preview() } }
    @objc func openSelection() {
        activate()
        for url in selectedURLs {
            if let entry = visible.first(where: { $0.url == url }), entry.isDirectory { navigate(to: url); return }
            NSWorkspace.shared.open(url)
        }
    }
    @objc func preview() {
        previewURLs = selectedURLs
        guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURLs[index] as NSURL }
    @objc private func showPlaces(_ sender: NSButton) {
        activate()
        let menu = NSMenu()
        let isFavorite = DirectoryFavorites.contains(directory)
        let toggle = NSMenuItem(title: isFavorite ? "取消收藏当前目录" : "收藏当前目录", action: #selector(toggleFavorite), keyEquivalent: "")
        toggle.target = self
        toggle.image = NSImage(systemSymbolName: isFavorite ? "star.fill" : "star", accessibilityDescription: nil)
        menu.addItem(toggle)
        let favorites = DirectoryFavorites.directories
        if !favorites.isEmpty {
            menu.addItem(.separator())
            let heading = NSMenuItem(title: "我的收藏", action: nil, keyEquivalent: "")
            heading.isEnabled = false; menu.addItem(heading)
            let removalMenu = NSMenu(title: "移除收藏")
            for url in favorites {
                // Show the parent path as well so equally named folders are distinct.
                let parent = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                let title = url.path == "/" ? "磁盘根目录 /" : "\(url.lastPathComponent)  —  \(parent)"
                let item = NSMenuItem(title: title, action: #selector(placeChosen(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = url; item.toolTip = url.path
                item.state = url.standardizedFileURL.path == directory.standardizedFileURL.path ? .on : .off
                menu.addItem(item)
                let remove = NSMenuItem(title: title, action: #selector(removeFavorite(_:)), keyEquivalent: "")
                remove.target = self; remove.representedObject = url; remove.toolTip = url.path
                removalMenu.addItem(remove)
            }
            let removalItem = NSMenuItem(title: "移除收藏", action: nil, keyEquivalent: "")
            removalItem.submenu = removalMenu; menu.addItem(removalItem)
        }
        menu.addItem(.separator())
        let home = FileManager.default.homeDirectoryForCurrentUser
        var places: [(String, URL)] = [("个人目录", home), ("桌面", home.appendingPathComponent("Desktop")), ("下载", home.appendingPathComponent("Downloads")), ("文稿", home.appendingPathComponent("Documents")), ("应用程序", URL(fileURLWithPath: "/Applications")), ("磁盘根目录", URL(fileURLWithPath: "/"))]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsBrowsableKey], options: [.skipHiddenVolumes]) ?? []
        places += volumes.filter { $0.path != "/" }.map { ($0.lastPathComponent, $0) }
        for (name, url) in places {
            let item = NSMenuItem(title: name, action: #selector(placeChosen(_:)), keyEquivalent: ""); item.target = self; item.representedObject = url; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }
    @objc private func toggleFavorite() { DirectoryFavorites.toggle(directory) }
    @objc private func removeFavorite(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        DirectoryFavorites.remove(url)
    }
    @objc private func placeChosen(_ sender: NSMenuItem) { activate(); navigate(to: sender.representedObject as! URL) }
    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("打开", #selector(openSelection)), ("快速预览", #selector(preview)), ("在 Finder 中显示", #selector(reveal)), ("复制到另一栏", #selector(copyAcross)), ("移动到另一栏", #selector(moveAcross)), ("复制", #selector(copyFiles)), ("复制文件名（含扩展名）", #selector(copyFileNames)), ("复制完整路径", #selector(copyFilePaths)), ("粘贴", #selector(pasteFiles)), ("重命名…", #selector(rename)), ("新建文件夹…", #selector(newFolder)), ("移到废纸篓…", #selector(trash))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self
            item.isEnabled = action == #selector(newFolder) || action == #selector(pasteFiles) || !selectedURLs.isEmpty
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        return menu
    }
    @objc func reveal() { NSWorkspace.shared.activateFileViewerSelecting(selectedURLs.isEmpty ? [directory] : selectedURLs) }
    @objc func copyAcross() { owner?.transferAcross(mode: .copy) }
    @objc func moveAcross() { owner?.transferAcross(mode: .move) }
    @objc func copyFiles() { owner?.copySelection() }
    @objc func copyFilePaths() { activate(); owner?.copyPaths(selectedURLs) }
    @objc func copyFileNames() { activate(); owner?.copyNames(selectedURLs) }
    @objc func pasteFiles() { owner?.pasteSelection() }
    @objc func rename() { owner?.renameSelection() }
    @objc func newFolder() { owner?.createFolder() }
    @objc func trash() { owner?.trashSelection() }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { visible[row].url as NSURL }
    private func dropDirectory(_ row: Int, _ operation: NSTableView.DropOperation) -> URL {
        if operation == .on && row >= 0 && row < visible.count && visible[row].isDirectory { return visible[row].url }
        return directory
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        if !(operation == .on && row >= 0 && row < visible.count && visible[row].isDirectory) { tableView.setDropRow(-1, dropOperation: .on) }
        return NSApp.currentEvent?.modifierFlags.contains(.command) == true && info.draggingSource != nil ? .move : .copy
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        let move = NSApp.currentEvent?.modifierFlags.contains(.command) == true && info.draggingSource != nil
        owner?.transfer(urls, to: dropDirectory(row, operation), mode: move ? .move : .copy)
        return true
    }
}
