import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainWindowController!
    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = MainWindowController()
        buildMenu()
        controller.showWindow(nil)
        controller.window?.makeFirstResponder(controller.left.table)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if controller?.busy == true { NSSound.beep(); return .terminateCancel }
        return .terminateNow
    }
    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "TwinFiles")
        appMenu.addItem(withTitle: "关于 TwinFiles", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 TwinFiles", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 TwinFiles", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)
        let file = NSMenu(title: "文件")
        item("打开", #selector(MainWindowController.openSelection), "o", in: file)
        item("选择目录…", #selector(MainWindowController.chooseDirectory), "g", [.command, .shift], in: file)
        item("新建文件夹…", #selector(MainWindowController.createFolder), "n", [.command, .shift], in: file)
        item("重命名…", #selector(MainWindowController.renameSelection), "r", [.command, .shift], in: file)
        item("快速预览", #selector(MainWindowController.preview), "y", in: file)
        item("在 Finder 中显示", #selector(MainWindowController.reveal), "r", [.command, .option], in: file)
        file.addItem(.separator())
        item("复制到另一栏", #selector(MainWindowController.copyAcross), "c", [.command, .shift], in: file)
        item("移动到另一栏", #selector(MainWindowController.moveAcross), "m", [.command, .shift], in: file)
        item("移到废纸篓…", #selector(MainWindowController.trashSelection), "\u{8}", in: file)
        add(file, to: main)
        let edit = NSMenu(title: "编辑")
        // Keep standard responder-chain actions so path fields retain native text editing.
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        item("将剪贴板文件移动到此处", #selector(MainWindowController.movePasteSelection), "v", [.command, .option], in: edit)
        add(edit, to: main)
        let view = NSMenu(title: "显示")
        item("筛选当前目录", #selector(MainWindowController.focusSearch), "f", in: view)
        item("输入路径", #selector(MainWindowController.focusPath), "l", in: view)
        item("刷新", #selector(MainWindowController.reload), "r", in: view)
        item("显示隐藏文件与文件夹", #selector(MainWindowController.toggleHidden), ".", [.command, .shift], in: view)
        item("当前栏打开另一栏目录", #selector(MainWindowController.matchOtherPane), "=", in: view)
        add(view, to: main)
        let go = NSMenu(title: "前往")
        item("上级目录", #selector(MainWindowController.goUp), String(UnicodeScalar(NSUpArrowFunctionKey)!), in: go)
        item("后退", #selector(MainWindowController.back), "[", in: go)
        item("前进", #selector(MainWindowController.forward), "]", in: go)
        item("切换分栏", #selector(MainWindowController.switchPane), "\t", [.control], in: go)
        add(go, to: main)
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, to: main); NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
    private func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = [.command], in menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = controller; item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
    }
    private func add(_ menu: NSMenu, to parent: NSMenu) { let item = NSMenuItem(); item.submenu = menu; parent.addItem(item) }
}

extension FileTable {
    @objc func copy(_ sender: Any?) { pane?.owner?.copySelection() }
    @objc func cut(_ sender: Any?) { pane?.owner?.cutSelection() }
    @objc func paste(_ sender: Any?) { pane?.owner?.pasteSelection() }
}
