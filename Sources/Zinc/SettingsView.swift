import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var settings = ShiftFilterSettings.shared
    @ObservedObject private var shortcutSettings = ShortcutSettings.shared
    @ObservedObject private var exportSettings = ExportSettings.shared
    @State private var selectedExcludedIDs = Set<String>()
    @State private var holdDurationText = ""
    @State private var doubleTapWindowText = ""
    @FocusState private var holdDurationFocused: Bool
    @FocusState private var doubleTapWindowFocused: Bool

    var body: some View {
        Form {
            shortcutsSection
            doubleTapSection
            mouseSection
            holdDurationSection
            excludedAppsSection
            exportSection
            debugSection
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 480, height: 680)
        .onAppear {
            holdDurationText = "\(settings.maxHoldDurationMs)"
            doubleTapWindowText = "\(settings.doubleTapWindowMs)"
        }
        .onDisappear {
            commitHoldDurationText()
            commitDoubleTapWindowText()
        }
        .onChange(of: settings.doubleShiftEnabled) { _, _ in
            NotificationCenter.default.post(name: .zincShiftFilterSettingsDidChange, object: nil)
        }
        .onChange(of: settings.triggerKey) { _, _ in
            NotificationCenter.default.post(name: .zincShiftFilterSettingsDidChange, object: nil)
        }
    }

    private var shortcutsSection: some View {
        Section {
            HStack {
                Text("Show clip panel")
                Spacer()
                HotkeyRecorderButton()
            }
            Text("Opens the saved-clips panel from anywhere. If registration fails, another app may already use this shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Shortcuts")
        }
    }

    private var doubleTapSection: some View {
        Section {
            Toggle("Enable double-tap capture", isOn: $settings.doubleShiftEnabled)
            Text("Quickly tap a modifier key twice to capture the current selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.doubleShiftEnabled {
                Picker("Trigger key", selection: $settings.triggerKey) {
                    ForEach(DoubleTapTriggerKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                HStack(spacing: 6) {
                    Text("Double-tap window")
                    Spacer()
                    TextField("", text: $doubleTapWindowText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 72)
                        .focused($doubleTapWindowFocused)
                        .onSubmit { commitDoubleTapWindowText() }
                        .onChange(of: doubleTapWindowText) { _, newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue {
                                doubleTapWindowText = filtered
                            }
                        }
                        .onChange(of: doubleTapWindowFocused) { _, focused in
                            if !focused {
                                commitDoubleTapWindowText()
                            }
                        }
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.doubleTapWindowMs) },
                        set: { newValue in
                            settings.doubleTapWindowMs = Int(newValue.rounded())
                            doubleTapWindowText = "\(settings.doubleTapWindowMs)"
                        }
                    ),
                    in: Double(ShiftFilterSettings.minDoubleTapWindowMs)...Double(ShiftFilterSettings.maxDoubleTapWindowMs),
                    step: 25
                )
                Text("Maximum time between the two taps. Zinc's own windows always ignore this trigger.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Double-Tap Capture")
        }
    }

    private var mouseSection: some View {
        Section {
            Toggle("Ignore Shift while a mouse button is held", isOn: $settings.ignoreMouseDown)
            Text("Prevents false captures during Shift+drag resize in design tools like Figma.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Mouse")
        }
    }

    private var holdDurationSection: some View {
        Section {
            Toggle("Require short modifier taps", isOn: $settings.requireShortTaps)
            Text("Longer holds (for example constraining proportions) will not arm double-tap capture.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.requireShortTaps {
                HStack(spacing: 6) {
                    Text("Max hold")
                    Spacer()
                    TextField("", text: $holdDurationText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 72)
                        .focused($holdDurationFocused)
                        .onSubmit { commitHoldDurationText() }
                        .onChange(of: holdDurationText) { _, newValue in
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue {
                                holdDurationText = filtered
                            }
                        }
                        .onChange(of: holdDurationFocused) { _, focused in
                            if !focused {
                                commitHoldDurationText()
                            }
                        }
                    Text("ms")
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(settings.maxHoldDurationMs) },
                        set: { newValue in
                            settings.maxHoldDurationMs = Int(newValue.rounded())
                            holdDurationText = "\(settings.maxHoldDurationMs)"
                        }
                    ),
                    in: Double(ShiftFilterSettings.minHoldDurationMs)...Double(ShiftFilterSettings.maxHoldDurationMs),
                    step: 10
                )
            }
        } header: {
            Text("Hold Duration")
        }
    }

    private var excludedAppsSection: some View {
        Section {
            if settings.excludedBundleIDs.isEmpty {
                Text("No apps excluded")
                    .foregroundStyle(.secondary)
            } else {
                List(selection: $selectedExcludedIDs) {
                    ForEach(settings.excludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 10) {
                            Image(nsImage: settings.appIcon(for: bundleID))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.displayName(for: bundleID))
                                Text(bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(bundleID)
                    }
                }
                .frame(minHeight: 120, maxHeight: 180)
                .listStyle(.bordered(alternatesRowBackgrounds: true))
            }

            HStack {
                Button("Add Application…") {
                    addApplication()
                }
                Button("Remove") {
                    settings.removeExcludedBundleIDs(selectedExcludedIDs)
                    selectedExcludedIDs.removeAll()
                }
                .disabled(selectedExcludedIDs.isEmpty)
                Spacer()
            }

            Text("Double-tap capture is disabled in these apps. \(shortcutSettings.panelHotKey.displayString) still works.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Excluded Apps")
        }
    }

    private var exportSection: some View {
        Section {
            Toggle("Download remote images", isOn: $exportSettings.downloadRemoteImages)
            Text("When enabled, Zinc fetches HTTP(S) images referenced in captured HTML and saves them locally. Off by default for privacy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Export")
        }
    }

    private var debugSection: some View {
        Section {
            Toggle("Write debug log to disk", isOn: Binding(
                get: { ZincLogger.fileLoggingEnabled },
                set: { ZincLogger.fileLoggingEnabled = $0 }
            ))
            Text("Off by default. When enabled, logs are written asynchronously with rotation (~1 MB).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Diagnostics")
        }
    }

    private func commitHoldDurationText() {
        guard let value = Int(holdDurationText) else {
            holdDurationText = "\(settings.maxHoldDurationMs)"
            return
        }
        settings.maxHoldDurationMs = value
        holdDurationText = "\(settings.maxHoldDurationMs)"
    }

    private func commitDoubleTapWindowText() {
        guard let value = Int(doubleTapWindowText) else {
            doubleTapWindowText = "\(settings.doubleTapWindowMs)"
            return
        }
        settings.doubleTapWindowMs = value
        doubleTapWindowText = "\(settings.doubleTapWindowMs)"
    }

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        panel.message = "Choose apps where double-tap capture should be disabled."

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !bundleID.isEmpty else { continue }
            if bundleID == Bundle.main.bundleIdentifier { continue }
            settings.addExcludedBundleID(bundleID)
        }
    }
}

private struct HotkeyRecorderButton: View {
    @ObservedObject private var shortcutSettings = ShortcutSettings.shared
    @StateObject private var recorder = HotkeyRecorderModel()

    var body: some View {
        Button(recorder.isRecording ? "Press shortcut…" : shortcutSettings.panelHotKey.displayString) {
            if recorder.isRecording {
                recorder.stopRecording()
            } else {
                recorder.startRecording { keyCode, carbonMods in
                    shortcutSettings.panelHotKey = HotKeyCombination(
                        keyCode: keyCode,
                        carbonModifiers: carbonMods
                    )
                }
            }
        }
        .buttonStyle(.bordered)
        .onDisappear {
            recorder.stopRecording()
        }
    }
}

@MainActor
private final class HotkeyRecorderModel: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func startRecording(onCapture: @escaping (UInt32, UInt32) -> Void) {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let carbonMods = Self.carbonModifiers(from: event.modifierFlags)
            guard carbonMods != 0 else { return event }

            Task { @MainActor in
                onCapture(UInt32(event.keyCode), carbonMods)
                self?.stopRecording()
            }
            return nil
        }
    }

    func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let mask = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if mask.contains(.control) { result |= UInt32(controlKey) }
        if mask.contains(.option) { result |= UInt32(optionKey) }
        if mask.contains(.shift) { result |= UInt32(shiftKey) }
        if mask.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zinc Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }
}

extension Notification.Name {
    static let zincShiftFilterSettingsDidChange = Notification.Name("ZincShiftFilterSettingsDidChange")
}
