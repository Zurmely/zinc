import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let shiftMonitor = ShiftShiftMonitor()
    private let hotKeyCenter = HotKeyCenter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        setupMonitors()
        updateStatusTooltip()
        // Ask for Accessibility after monitors are wired (alert is async, single dialog).
        Permissions.requestAccessibilityIfNeeded()
        // Offer recovery if clips.json was corrupt (quarantined on load).
        ClipIndexRecoveryAlert.presentIfNeeded()
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
            withTitle: "Settings…",
            action: #selector(showSettings),
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
            button.image = Self.menuBarImage()
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Saved Clips", action: #selector(showPanel), keyEquivalent: "v")
            .keyEquivalentModifierMask = [.option, .shift]
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Zinc Folder", action: #selector(openVaultFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Choose Zinc Folder…", action: #selector(chooseVaultFolder), keyEquivalent: "")
        menu.addItem(withTitle: "Reindex from Vault…", action: #selector(reindexFromVault), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear All Clips", action: #selector(clearClips), keyEquivalent: "")
        menu.addItem(withTitle: "Open Accessibility Settings", action: #selector(openAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Zinc", action: #selector(quit), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    private func setupMonitors() {
        shiftMonitor.onDoubleShift = { [weak self] in
            self?.updateStatusTooltip()
        }
        shiftMonitor.onMonitoringBecameActive = {
            SaveHUD.showMonitorActive()
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
    }

    @objc private func showPanel() {
        ClipPanelController.shared.openPanel()
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.showSettings()
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

    @objc private func reindexFromVault() {
        let alert = NSAlert()
        alert.messageText = "Reindex from Vault?"
        alert.informativeText = "Zinc will scan your Markdown vault and rebuild the clip index from front matter. Existing index entries are kept when they share an id with a vault file."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Reindex")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            let count = ClipStore.shared.reindexFromVault()
            updateStatusTooltip()
            let done = NSAlert()
            done.messageText = count == 1 ? "1 clip indexed" : "\(count) clips indexed"
            done.alertStyle = .informational
            done.addButton(withTitle: "OK")
            done.runModal()
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

    private static func menuBarImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "MenubarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 16, height: 16)
            image.isTemplate = true
            image.accessibilityDescription = "Zinc"
            return image
        }

        let fallback = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Zinc") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
