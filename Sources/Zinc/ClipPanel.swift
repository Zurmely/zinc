import AppKit
import SwiftUI

final class ClipPanelController: NSWindowController, NSWindowDelegate {
    static let shared = ClipPanelController()

    private var previousApp: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var hostingView: NSHostingView<ClipListView>?
    private let viewModel = ClipPanelViewModel()
    private var openedAt: Date?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )

        // Keyable floating panel so the search field can accept typing.
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: panel)
        panel.delegate = self

        viewModel.onClose = { [weak self] in
            self?.closePanel()
        }

        let hosting = NSHostingView(rootView: ClipListView(viewModel: viewModel))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 560)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        hostingView = hosting
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func toggle() {
        if window?.isVisible == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    func openPanel() {
        guard let panel = window else { return }

        previousApp = NSWorkspace.shared.frontmostApplication

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let origin = NSPoint(
                x: screenFrame.midX - panelSize.width / 2,
                y: screenFrame.midY - panelSize.height / 2 + 40
            )
            panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        }

        viewModel.prepareForDisplay()
        let clips = viewModel.filteredClips(from: ClipStore.shared.clips)
        if !clips.isEmpty {
            viewModel.selectOnly(index: 0, in: clips)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        openedAt = Date()

        installKeyMonitor()

        // Focus the search field after the window is key.
        DispatchQueue.main.async {
            self.viewModel.focusSearchToken += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.viewModel.focusSearchToken += 1
        }
    }

    func closePanel() {
        removeKeyMonitor()
        openedAt = nil
        window?.orderOut(nil)
        viewModel.resetTransientState()

        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
        previousApp = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // Ignore resign events that happen while the panel is still opening.
        if let openedAt, Date().timeIntervalSince(openedAt) < 0.3 {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !window.isKeyWindow, window.isVisible else { return }
            self.closePanel()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.viewModel.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        localKeyMonitor = nil
    }
}

/// Shared state between the panel controller and SwiftUI view.
final class ClipPanelViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedIDs: Set<UUID> = []
    @Published var focusedIndex = 0
    @Published var focusSearchToken = 0
    @Published var isDetailExpanded = false

    /// Anchor index for Shift-click / Shift-arrow range selection.
    private var selectionAnchorIndex = 0

    var onClose: (() -> Void)?

    func prepareForDisplay() {
        searchText = ""
        selectedIDs = []
        focusedIndex = 0
        selectionAnchorIndex = 0
        isDetailExpanded = false
    }

    func resetTransientState() {
        searchText = ""
        selectedIDs = []
        focusedIndex = 0
        selectionAnchorIndex = 0
        isDetailExpanded = false
    }

    /// Returns true if the event was handled (and should be swallowed).
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+Q — quit.
        if mods.contains(.command), event.charactersIgnoringModifiers == "q" {
            NSApp.terminate(nil)
            return true
        }

        // Esc — collapse expanded detail first, then close panel.
        if event.keyCode == 53 {
            if isDetailExpanded {
                isDetailExpanded = false
                return true
            }
            onClose?()
            return true
        }

        let store = ClipStore.shared
        let clips = filteredClips(from: store.clips)

        // Tab — toggle expanded detail view.
        if event.keyCode == 48, !mods.contains(.shift) {
            if !clips.isEmpty {
                isDetailExpanded.toggle()
            }
            return true
        }

        switch event.keyCode {
        case 125: // Down
            moveFocus(by: 1, in: clips, extending: mods.contains(.shift))
            return true
        case 126: // Up
            moveFocus(by: -1, in: clips, extending: mods.contains(.shift))
            return true
        case 36, 76: // Return
            copySelectedAndClose(from: store, clips: clips)
            return true
        case 51, 117: // Delete / Forward Delete
            // macOS convention: Cmd+Delete removes items. Plain Delete edits search.
            if mods.contains(.command) {
                deleteSelected(from: store, clips: clips)
                return true
            }
            return false
        case 8: // C
            if mods.contains(.command) {
                copySelectedAndClose(from: store, clips: clips)
                return true
            }
            return false
        case 49: // Space — toggle multi-select on focused row when not typing a query space meaningfully
            // Allow Space to toggle selection when search is empty (Spotlight/Finder-like).
            if searchText.isEmpty, let clip = clipAtFocusedIndex(in: clips) {
                toggleSelection(clip.id)
                return true
            }
            return false
        default:
            return false
        }
    }

    func filteredClips(from clips: [Clip]) -> [Clip] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return clips }
        return clips.filter { clip in
            clip.text.lowercased().contains(query)
                || clip.appName.lowercased().contains(query)
                || (clip.pageTitle?.lowercased().contains(query) ?? false)
                || (clip.pageURL?.lowercased().contains(query) ?? false)
        }
    }

    func moveFocus(by delta: Int, in clips: [Clip], extending: Bool = false) {
        guard !clips.isEmpty else { return }
        focusedIndex = (focusedIndex + delta + clips.count) % clips.count

        if extending {
            selectRange(from: selectionAnchorIndex, to: focusedIndex, in: clips)
        } else {
            // Keep single-selection in sync with keyboard focus.
            let clip = clips[focusedIndex]
            selectedIDs = [clip.id]
            selectionAnchorIndex = focusedIndex
        }
    }

    func clipAtFocusedIndex(in clips: [Clip]) -> Clip? {
        guard clips.indices.contains(focusedIndex) else { return nil }
        return clips[focusedIndex]
    }

    func selectOnly(index: Int, in clips: [Clip]) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        selectionAnchorIndex = index
        selectedIDs = [clips[index].id]
    }

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func cmdClick(index: Int, in clips: [Clip]) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        selectionAnchorIndex = index
        toggleSelection(clips[index].id)
    }

    func shiftClick(index: Int, in clips: [Clip]) {
        guard clips.indices.contains(index) else { return }
        focusedIndex = index
        selectRange(from: selectionAnchorIndex, to: index, in: clips)
    }

    private func selectRange(from: Int, to: Int, in clips: [Clip]) {
        guard !clips.isEmpty else { return }
        let lo = max(0, min(from, to))
        let hi = min(clips.count - 1, max(from, to))
        selectedIDs = Set(clips[lo...hi].map(\.id))
    }

    func copySelectedAndClose(from store: ClipStore, clips: [Clip]) {
        let ids: [UUID]
        if !selectedIDs.isEmpty {
            ids = clips.filter { selectedIDs.contains($0.id) }.map(\.id)
        } else if let clip = clipAtFocusedIndex(in: clips) {
            ids = [clip.id]
        } else {
            return
        }

        let texts = clips.filter { ids.contains($0.id) }.map(\.text)
        guard !texts.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texts.joined(separator: "\n"), forType: .string)
        onClose?()
    }

    func deleteSelected(from store: ClipStore, clips: [Clip]) {
        let ids: Set<UUID>
        if !selectedIDs.isEmpty {
            ids = selectedIDs
        } else if let clip = clipAtFocusedIndex(in: clips) {
            ids = [clip.id]
        } else {
            return
        }

        let oldFocus = focusedIndex
        store.remove(ids: ids)
        selectedIDs.subtract(ids)

        let remaining = filteredClips(from: store.clips)
        if remaining.isEmpty {
            focusedIndex = 0
            selectionAnchorIndex = 0
        } else {
            focusedIndex = min(oldFocus, remaining.count - 1)
            selectionAnchorIndex = focusedIndex
            if selectedIDs.isEmpty {
                selectedIDs = [remaining[focusedIndex].id]
            }
        }
    }
}
