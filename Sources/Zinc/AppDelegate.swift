import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let shiftMonitor = ShiftShiftMonitor()
    private let hotKeyCenter = HotKeyCenter()
    private var statusMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupMonitors()
        updateStatusTooltip()
        refreshMenuStatus()
        // Ask for Accessibility after monitors are wired (alert is async, single dialog).
        Permissions.requestAccessibilityIfNeeded()
    }

    /// Accessory apps need an explicit main menu for Cmd+Q to work.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Zinc")
        appMenu.addItem(
            withTitle: "About Zinc",
            action: nil,
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Zinc",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        shiftMonitor.stop()
        hotKeyCenter.unregister()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Zinc")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Saved Clips", action: #selector(showPanel), keyEquivalent: "v")
            .keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(withTitle: "Test Save Selection", action: #selector(testCapture), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Zinc Folder", action: #selector(openVaultFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Choose Zinc Folder…", action: #selector(chooseVaultFolder), keyEquivalent: "")
        menu.addItem(.separator())

        let status = NSMenuItem(title: "Shift monitor: …", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.tag = 100
        menu.addItem(status)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear All Clips", action: #selector(clearClips), keyEquivalent: "")
        menu.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Zinc", action: #selector(quit), keyEquivalent: "q")

        statusItem?.menu = menu
        statusMenu = menu
    }

    private func setupMonitors() {
        shiftMonitor.onDoubleShift = { [weak self] in
            self?.updateStatusTooltip()
            self?.refreshMenuStatus()
        }
        shiftMonitor.onMonitoringBecameActive = { [weak self] in
            SaveHUD.showMonitorActive()
            self?.refreshMenuStatus()
        }
        shiftMonitor.start()

        hotKeyCenter.onHotKey = {
            ClipPanelController.shared.toggle()
        }
        hotKeyCenter.register()

        NotificationCenter.default.addObserver(
            forName: .clipsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusTooltip()
        }

        // Keep the menu status line accurate.
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshMenuStatus()
        }
    }

    private func refreshMenuStatus() {
        guard let item = statusMenu?.item(withTag: 100) else { return }
        if !Permissions.isAccessibilityTrusted {
            item.title = "Shift monitor: needs Accessibility"
        } else if shiftMonitor.isMonitoring {
            item.title = "Shift monitor: active"
        } else {
            item.title = "Shift monitor: inactive"
        }
    }

    @objc private func showPanel() {
        ClipPanelController.shared.openPanel()
    }

    @objc private func testCapture() {
        // Lets you verify selection capture independently of the Shift shortcut.
        if let selection = SelectionCapture.captureSelection() {
            let context = ContextResolver.resolve()
            let clip = Clip(
                text: selection.clipText,
                appName: context.appName,
                bundleID: context.bundleID,
                pageURL: context.pageURL,
                pageTitle: context.pageTitle
            )
            ClipStore.shared.add(clip)
            MarkdownExporter.shared.export(selection: selection, clip: clip)
            SaveHUD.show(text: clip.preview, source: clip.contextLabel)
            updateStatusTooltip()
        } else {
            SaveHUD.showFailure()
        }
    }

    @objc private func openVaultFolder() {
        _ = VaultSettings.ensureVaultExists()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: VaultSettings.vaultURL.path)
    }

    @objc private func chooseVaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where Zinc saves Markdown captures."
        panel.directoryURL = VaultSettings.vaultURL

        if panel.runModal() == .OK, let url = panel.url {
            VaultSettings.setVaultURL(url)
            openVaultFolder()
        }
    }

    @objc private func clearClips() {
        let alert = NSAlert()
        alert.messageText = "Clear all saved clips?"
        alert.informativeText = "This cannot be undone. Exported Markdown files will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            ClipStore.shared.clear()
            updateStatusTooltip()
        }
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateStatusTooltip() {
        let count = ClipStore.shared.clips.count
        statusItem?.button?.toolTip = count == 1 ? "Zinc — 1 clip saved" : "Zinc — \(count) clips saved"
    }
}
