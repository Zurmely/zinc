import AppKit
import SwiftUI
import ZincCore

struct ClipDetailView: View {
    let clip: Clip
    @ObservedObject private var previewStore = MarkdownPreviewStore.shared

    private var document: MarkdownDocument {
        previewStore.document(for: clip)
    }

    private var markdownBaseURL: URL? {
        guard let path = clip.markdownPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                MarkdownPreviewView(document: document, markdownBaseURL: markdownBaseURL)
                    .padding(16)
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            previewStore.loadIfNeeded(for: clip)
        }
        .onChange(of: clip.id) { _, _ in
            previewStore.loadIfNeeded(for: clip)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: appIcon(for: clip.bundleID))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(clip.contextLabel)
                    .font(.headline)
                    .lineLimit(2)

                if let pageURL = clip.pageURL, let url = URL(string: pageURL) {
                    Link(pageURL, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }

                Text(clip.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(document.contentTypeLabel)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let path = clip.markdownPath {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(clip.text, forType: .string)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("c", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func appIcon(for bundleID: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}
