import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZincCore

struct SettingsView: View {
    @ObservedObject private var settings = ShiftFilterSettings.shared
    @ObservedObject private var syncController = ClipSyncController.shared
    @State private var selectedExcludedIDs = Set<String>()
    @State private var holdDurationText = ""
    @FocusState private var holdDurationFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Ignore Shift while a mouse button is held", isOn: $settings.ignoreMouseDown)
                Text("Prevents false captures during Shift+drag resize in design tools like Figma.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Mouse")
            }

            Section {
                Toggle("Require short Shift taps", isOn: $settings.requireShortTaps)
                Text("Longer holds (for example constraining proportions) will not arm double-Shift.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if settings.requireShortTaps {
                    HStack(spacing: 6) {
                        Text("Max hold")
                        Spacer()
                        TextField(
                            "",
                            text: $holdDurationText
                        )
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

                Text("Double-Shift is disabled in these apps. Option+Shift+V still works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Excluded Apps")
            }

            Section {
                Toggle("Sync clips with iCloud", isOn: Binding(
                    get: { syncController.settings.iCloudSyncEnabled },
                    set: { syncController.setEnabled($0) }
                ))
                Text("Optional. Your Markdown vault stays on this Mac; only clip text and metadata sync to Zinc on iPhone and iPad.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text("Status")
                    Spacer()
                    Text(syncController.status.label)
                        .foregroundStyle(.secondary)
                }

                if let lastSyncedAt = syncController.lastSyncedAt {
                    HStack {
                        Text("Last synced")
                        Spacer()
                        Text(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("iCloud")
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 460, height: 600)
        .onAppear {
            holdDurationText = "\(settings.maxHoldDurationMs)"
        }
        .onDisappear {
            commitHoldDurationText()
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

    private func addApplication() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "Add"
        panel.message = "Choose apps where double-Shift should be disabled."

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier,
                  !bundleID.isEmpty else { continue }
            // Don't exclude Zinc itself — settings wouldn't be reachable via double-Shift anyway,
            // but keeping the list clean.
            if bundleID == Bundle.main.bundleIdentifier { continue }
            settings.addExcludedBundleID(bundleID)
        }
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
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
