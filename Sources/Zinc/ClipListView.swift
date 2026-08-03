import AppKit
import SwiftUI

struct ClipListView: View {
    @ObservedObject var viewModel: ClipPanelViewModel
    @ObservedObject private var store = ClipStore.shared
    @ObservedObject private var previewStore = MarkdownPreviewStore.shared
    @FocusState private var searchFocused: Bool

    private var filteredClips: [Clip] {
        viewModel.filteredClips(from: store.clips)
    }

    private var focusedClip: Clip? {
        viewModel.clipAtFocusedIndex(in: filteredClips)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if filteredClips.isEmpty {
                emptyState
            } else if viewModel.isDetailExpanded, let focusedClip {
                ClipDetailView(clip: focusedClip)
            } else {
                splitContent
            }
            Divider()
            footer
        }
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onChange(of: viewModel.focusSearchToken) { _, _ in
            searchFocused = true
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.focusedIndex = 0
        }
        .onChange(of: viewModel.focusedIndex) { _, _ in
            if let clip = focusedClip {
                previewStore.loadIfNeeded(for: clip)
            }
        }
        .onAppear {
            searchFocused = true
            if let clip = focusedClip {
                previewStore.loadIfNeeded(for: clip)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search saved clips...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                .onSubmit {
                    viewModel.copySelectedAndClose(from: store, clips: filteredClips)
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(store.clips.isEmpty ? "No clips saved yet" : "No matching clips")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Double-tap Shift to save a selection")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            searchFocused = true
        }
    }

    private var splitContent: some View {
        HStack(spacing: 0) {
            clipList
                .frame(width: 320)
            Divider()
            if let focusedClip {
                ClipDetailView(clip: focusedClip)
            } else {
                Text("Select a clip")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clipList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredClips.enumerated()), id: \.element.id) { index, clip in
                        ClipRowView(
                            clip: clip,
                            document: previewStore.document(for: clip),
                            isFocused: index == viewModel.focusedIndex,
                            isSelected: viewModel.selectedIDs.contains(clip.id)
                        )
                        .id(clip.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            viewModel.selectOnly(index: index, in: filteredClips)
                            viewModel.copySelectedAndClose(from: store, clips: filteredClips)
                        }
                        .onTapGesture(count: 1) {
                            handleRowTap(clip: clip, index: index)
                        }
                    }
                }
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
                guard filteredClips.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.1)) {
                    proxy.scrollTo(filteredClips[newIndex].id, anchor: .center)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(footerLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.selectedIDs.count > 1 {
                Text("\(viewModel.selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footerLabel: String {
        if viewModel.isDetailExpanded {
            return "esc collapse  ·  ↵ copy  ·  ⌘⌫ delete"
        }
        return "↑↓  ·  ⇥ expand  ·  ↵ copy  ·  ⌘⌫ delete  ·  esc"
    }

    private func handleRowTap(clip: Clip, index: Int) {
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift) {
            viewModel.shiftClick(index: index, in: filteredClips)
        } else if modifiers.contains(.command) {
            viewModel.cmdClick(index: index, in: filteredClips)
        } else {
            viewModel.selectOnly(index: index, in: filteredClips)
        }
    }
}

private struct ClipRowView: View {
    let clip: Clip
    let document: MarkdownDocument
    let isFocused: Bool
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            thumbnail
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(document.contentTypeLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(rowPreviewText)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Image(nsImage: appIcon(for: clip.bundleID))
                        .resizable()
                        .frame(width: 12, height: 12)
                    Text(clip.contextLabel)
                        .lineLimit(1)
                    Text("·")
                    Text(clip.savedAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(rowBackground)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imagePath = document.firstImagePath,
           let path = clip.markdownPath,
           let image = loadThumbnail(relativePath: imagePath, markdownPath: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(nsImage: appIcon(for: clip.bundleID))
                .resizable()
                .scaledToFit()
                .padding(6)
                .background(Color.primary.opacity(0.06))
        }
    }

    private var rowPreviewText: AttributedString {
        for block in document.blocks {
            switch block {
            case .heading(_, let text):
                return attributedInline(text)
            case .paragraph(let text):
                return attributedInline(text)
            case .bullet(let items):
                if let first = items.first {
                    return attributedInline(first)
                }
            case .numbered(let items):
                if let first = items.first {
                    return attributedInline(first)
                }
            case .quote(let text):
                return attributedInline(text)
            case .code(let text):
                return AttributedString(String(text.prefix(120)))
            case .image(_, let alt):
                return AttributedString(alt.isEmpty ? "[Image]" : alt)
            default:
                continue
            }
        }
        return AttributedString(clip.preview)
    }

    private func attributedInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    private var rowBackground: some View {
        Group {
            if isSelected {
                Color.accentColor.opacity(0.15)
            } else if isFocused {
                Color.primary.opacity(0.08)
            } else {
                Color.clear
            }
        }
    }

    private func appIcon(for bundleID: String) -> NSImage {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func loadThumbnail(relativePath: String, markdownPath: String) -> NSImage? {
        let baseURL = URL(fileURLWithPath: markdownPath).deletingLastPathComponent()
        let imageURL = baseURL.appendingPathComponent(relativePath)
        guard let image = NSImage(contentsOf: imageURL) else { return nil }
        image.size = NSSize(width: 72, height: 72)
        return image
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
