import AppKit
import Quartz

final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let left = PaneController(side: "left")
    let right = PaneController(side: "right")
    private(set) var activePane: PaneController!
    private let operationLabel = NSTextField(labelWithString: "")
    private let operationBar = NSStackView()
    private var statusDismiss: DispatchWorkItem?
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "停止后续项目", target: nil, action: nil)
    private var keyMonitor: Any?
    private(set) var busy = false
    private let cancellation = CancellationFlag()
    private var clipboardMove = false
    private var clipboardChangeCount = -1
    private var hiddenFilesToolbarItem: NSToolbarItem?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1220, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "TwinFiles · 双栏文件管理"
        window.minSize = NSSize(width: 860, height: 440)
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("TwinFiles.Main")
        if !window.setFrameUsingName("TwinFiles.Main") { window.center() }
        activePane = left
        left.owner = self; right.owner = self
        let content = NSView()
        window.contentView = content

        let toolbar = NSToolbar(identifier: "TwinFiles.CompactToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unifiedCompact; window.toolbar = toolbar
        let separator = divider()
        let panes = NSStackView(views: [left.view, separator, right.view])
        panes.orientation = .horizontal; panes.spacing = 0; panes.alignment = .top; panes.distribution = .fill
        left.view.widthAnchor.constraint(equalTo: right.view.widthAnchor).isActive = true
        left.view.heightAnchor.constraint(equalTo: panes.heightAnchor).isActive = true
        right.view.heightAnchor.constraint(equalTo: panes.heightAnchor).isActive = true
        separator.heightAnchor.constraint(equalTo: panes.heightAnchor).isActive = true

        operationLabel.font = .systemFont(ofSize: 11); operationLabel.textColor = .secondaryLabelColor
        operationLabel.lineBreakMode = .byTruncatingMiddle
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        cancelButton.target = self; cancelButton.action = #selector(stopPendingOperations); cancelButton.isHidden = true; cancelButton.controlSize = .small
        for item in [spinner, operationLabel, NSView(), cancelButton] { operationBar.addArrangedSubview(item) }
        operationBar.spacing = 8; operationBar.distribution = .fill
        operationBar.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        operationBar.heightAnchor.constraint(equalToConstant: 24).isActive = true
        operationBar.isHidden = true
        let layout = NSStackView(views: [panes, operationBar])
        layout.orientation = .vertical; layout.alignment = .leading; layout.distribution = .fill; layout.spacing = 0
        layout.detachesHiddenViews = true
        content.addSubview(layout); layout.translatesAutoresizingMaskIntoConstraints = false
        for item in [panes, operationBar] { item.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor), layout.leadingAnchor.constraint(equalTo: content.leadingAnchor), layout.trailingAnchor.constraint(equalTo: content.trailingAnchor), layout.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        setActive(left)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.window, self.window?.attachedSheet == nil else { return event }
            if event.keyCode == 48, self.window?.firstResponder is FileTable {
                self.switchPane(); return nil
            }
            if event.keyCode == 96 { self.copyAcross(); return nil }
            if event.keyCode == 97 { self.moveAcross(); return nil }
            return event
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + ["toggleHidden", "copyAcross", "moveAcross", "newFolder", "trash"].map { NSToolbarItem.Identifier($0) }
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "toggleHidden" {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self; item.action = #selector(toggleHidden)
            hiddenFilesToolbarItem = item; updateHiddenFilesButton()
            return item
        }
        let actions: [String: (String, String, Selector, String)] = [
            "copyAcross": ("复制到对栏", "doc.on.doc", #selector(copyAcross), "⌘⇧C · F5"),
            "moveAcross": ("移动到对栏", "arrow.left.arrow.right", #selector(moveAcross), "⌘⇧M · F6"),
            "newFolder": ("新建文件夹", "folder.badge.plus", #selector(createFolder), "⌘⇧N"),
            "trash": ("移到废纸篓", "trash", #selector(trashSelection), "⌘⌫")
        ]
        guard let (title, symbol, action, shortcut) = actions[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self; item.action = action; item.toolTip = "\(title)（\(shortcut)）"
        return item
    }
    private func showOperationStatus(_ message: String) {
        operationLabel.stringValue = message; operationLabel.toolTip = message
        operationBar.isHidden = false
        statusDismiss?.cancel()
        guard !busy else { return }
        let dismiss = DispatchWorkItem { [weak self] in
            guard let self, !self.busy else { return }
            self.operationBar.isHidden = true
        }
        statusDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: dismiss)
    }
    private func divider() -> NSView {
        let line = NSBox(); line.boxType = .separator
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
    func setActive(_ pane: PaneController) {
        activePane = pane
        left.setActiveAppearance(pane === left); right.setActiveAppearance(pane === right)
    }
    var otherPane: PaneController { activePane === left ? right : left }
    @objc func switchPane() { setActive(otherPane); window?.makeFirstResponder(activePane.table) }
    @objc func copyAcross() { transferAcross(mode: .copy) }
    @objc func moveAcross() { transferAcross(mode: .move) }
    func transferAcross(mode: TransferMode) { transfer(activePane.selectedURLs, to: otherPane.directory, mode: mode) }

    func transfer(_ urls: [URL], to destination: URL, mode: TransferMode) {
        guard !urls.isEmpty else { return }
        runOperation(title: mode == .copy ? "复制" : "移动", urls: urls) { source in
            try FileActions.transfer(source, to: destination, mode: mode)
        }
    }
    @objc func copySelection() {
        guard !activePane.selectedURLs.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(activePane.selectedURLs as [NSURL])
        clipboardMove = false; clipboardChangeCount = NSPasteboard.general.changeCount
        showOperationStatus("已复制 \(activePane.selectedURLs.count) 个项目；⌘V 粘贴，⌘⌥V 移动到当前栏")
    }
    func copyPaths(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        clipboardMove = false; clipboardChangeCount = NSPasteboard.general.changeCount
        if !busy { showOperationStatus("已复制 \(urls.count) 个完整路径") }
    }
    @objc func cutSelection() { copySelection(); clipboardMove = true; showOperationStatus("已标记移动；在目标目录按 ⌘V 完成移动") }
    @objc func pasteSelection() { paste(forceMove: false) }
    @objc func movePasteSelection() { paste(forceMove: true) }
    private func paste(forceMove: Bool) {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let move = forceMove || (clipboardMove && clipboardChangeCount == NSPasteboard.general.changeCount)
        transfer(urls, to: activePane.directory, mode: move ? .move : .copy)
        clipboardMove = false
    }
    @objc func createFolder() {
        guard !busy else { return }
        let directory = activePane.directory
        prompt(title: "新建文件夹", message: "位置：\(directory.path)", initial: "未命名文件夹") { [weak self] name in
            do {
                try FileActions.validateName(name)
                let url = directory.appendingPathComponent(name, isDirectory: true)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
                self?.refreshBoth()
            } catch { self?.showError(error) }
        }
    }
    @objc func renameSelection() {
        guard !busy, let source = activePane.selectedURLs.first, activePane.selectedURLs.count == 1 else { return }
        prompt(title: "重命名", message: "输入新的文件名称（包含扩展名）。", initial: source.lastPathComponent) { [weak self] name in
            do {
                try FileActions.validateName(name)
                if name == source.lastPathComponent { return }
                try FileManager.default.moveItem(at: source, to: source.deletingLastPathComponent().appendingPathComponent(name))
                self?.refreshBoth()
            } catch { self?.showError(error) }
        }
    }
    @objc func trashSelection() {
        guard !busy else { return }
        let urls = activePane.selectedURLs
        guard !urls.isEmpty, let window else { return }
        let alert = NSAlert(); alert.messageText = "将 \(urls.count) 个项目移到废纸篓？"
        alert.informativeText = "可以在 Finder 的废纸篓中找回。"; alert.alertStyle = .warning
        alert.addButton(withTitle: "移到废纸篓"); alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.runOperation(title: "移到废纸篓", urls: urls) { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        }
    }
    private func runOperation(title: String, urls: [URL], action: @escaping (URL) throws -> Void) {
        guard !busy else { NSSound.beep(); return }
        busy = true; cancellation.reset(); spinner.startAnimation(nil); cancelButton.isHidden = false
        showOperationStatus("\(title)：准备中…（同名项目自动保留两份）")
        let cancellation = cancellation
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failures: [String] = []; var completed = 0
            for (index, url) in urls.enumerated() {
                if cancellation.isCancelled { break }
                DispatchQueue.main.async { [weak self] in self?.showOperationStatus("\(title) \(index + 1)/\(urls.count)  ·  \(url.lastPathComponent)") }
                do { try action(url); completed += 1 } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            let count = completed; let errors = failures
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false; self.spinner.stopAnimation(nil); self.cancelButton.isHidden = true
                self.showOperationStatus("\(title)\(cancellation.isCancelled ? "已停止" : "完成")  ·  成功 \(count)/\(urls.count)" + (errors.isEmpty ? "" : "  ·  失败 \(errors.count)"))
                self.refreshBoth()
                if !errors.isEmpty {
                    let alert = NSAlert(); alert.messageText = "部分项目未能完成\(title)"
                    alert.informativeText = errors.prefix(8).joined(separator: "\n") + (errors.count > 8 ? "\n另有 \(errors.count - 8) 个错误" : "")
                    if let window = self.window { alert.beginSheetModal(for: window) }
                }
            }
        }
    }
    @objc private func stopPendingOperations() { cancellation.cancel(); showOperationStatus("正在完成当前项目，随后停止…") }
    func refreshBoth() { left.reload(); right.reload() }
    func showError(_ error: Error) {
        guard let window, window.attachedSheet == nil else { showOperationStatus(error.localizedDescription); return }
        let alert = NSAlert(error: error); alert.beginSheetModal(for: window)
    }
    private func prompt(title: String, message: String, initial: String, completion: @escaping (String) -> Void) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { completion(field.stringValue) } }
    }
    @objc func toggleHidden() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showHidden"), forKey: "showHidden")
        updateHiddenFilesButton(); refreshBoth()
    }
    private func updateHiddenFilesButton() {
        let shown = UserDefaults.standard.bool(forKey: "showHidden")
        let title = shown ? "不显示隐藏文件与文件夹" : "显示隐藏文件与文件夹"
        hiddenFilesToolbarItem?.label = title
        hiddenFilesToolbarItem?.image = NSImage(systemSymbolName: shown ? "eye.slash" : "eye", accessibilityDescription: title)
        hiddenFilesToolbarItem?.toolTip = "\(title)（⌘⇧.），同时应用于左右两栏"
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleHidden) {
            menuItem.state = UserDefaults.standard.bool(forKey: "showHidden") ? .on : .off
        }
        return true
    }
    @objc func openSelection() { activePane.openSelection() }
    @objc func preview() { activePane.preview() }
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = activePane }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
    @objc func goUp() { activePane.goUp() }
    @objc func back() { activePane.back() }
    @objc func forward() { activePane.forward() }
    @objc func reload() { activePane.reload() }
    @objc func focusPath() { activePane.focusPath() }
    @objc func focusSearch() { activePane.focusSearch() }
    @objc func reveal() { activePane.reveal() }
    @objc func matchOtherPane() { activePane.navigate(to: otherPane.directory) }
    @objc func chooseDirectory() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = activePane.directory
        guard let window else { return }
        let pane = activePane!
        panel.beginSheetModal(for: window) { response in if response == .OK, let url = panel.url { pane.navigate(to: url) } }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if busy { showOperationStatus("文件操作进行中，请等待完成，或停止后续项目后再关闭窗口。"); NSSound.beep(); return false }
        return true
    }
}

final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func reset() { lock.lock(); value = false; lock.unlock() }
}
