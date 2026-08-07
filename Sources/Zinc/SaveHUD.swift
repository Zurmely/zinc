import AppKit

enum SaveHUD {
    private static var hudWindow: NSWindow?
    private static var dismissWorkItem: DispatchWorkItem?
    private static var clickMonitor: Any?

    static func show(text: String, source _: String, clipID: UUID? = nil) {
        present(
            title: "Saved to Zinc",
            preview: collapsedPreview(text),
            playSound: true,
            expands: true,
            clipID: clipID
        )
    }

    static func showFailure() {
        present(
            title: "Nothing to save",
            preview: nil,
            playSound: false,
            expands: false,
            clipID: nil
        )
    }

    static func showMonitorActive() {
        present(
            title: "Shift monitor active",
            preview: nil,
            playSound: true,
            expands: false,
            clipID: nil
        )
    }

    private static func present(
        title: String,
        preview: String?,
        playSound: Bool,
        expands: Bool,
        clipID: UUID?
    ) {
        DispatchQueue.main.async {
            dismiss()

            let screen = NSScreen.main ?? NSScreen.screens.first!
            let height: CGFloat = 36
            let horizontalPadding: CGFloat = 14
            let stackSpacing: CGFloat = 8
            let maxPreviewWidth: CGFloat = 280

            let titleLabel = makeLabel(title, weight: .semibold, size: 12, color: .labelColor)
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            let titleWidth = measuredWidth(titleLabel)

            let shouldExpand = expands && !(preview ?? "").isEmpty
            var previewLabel: NSTextField?
            var previewWidth: CGFloat = 0
            var separator: NSTextField?
            var separatorWidth: CGFloat = 0
            var previewWidthConstraint: NSLayoutConstraint?
            var separatorWidthConstraint: NSLayoutConstraint?
            var contentWidthConstraint: NSLayoutConstraint?

            if shouldExpand, let preview {
                let label = makeLabel(preview, weight: .regular, size: 12, color: .secondaryLabelColor)
                label.lineBreakMode = .byTruncatingTail
                label.cell?.truncatesLastVisibleLine = true
                label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                label.alphaValue = 0
                label.isHidden = true
                previewWidth = min(max(measuredWidth(label), 1), maxPreviewWidth)
                let widthConstraint = label.widthAnchor.constraint(equalToConstant: 0)
                widthConstraint.isActive = true
                previewWidthConstraint = widthConstraint
                previewLabel = label

                let dot = NSTextField(labelWithString: "·")
                dot.font = .systemFont(ofSize: 12, weight: .semibold)
                dot.textColor = .tertiaryLabelColor
                dot.setContentHuggingPriority(.required, for: .horizontal)
                dot.setContentCompressionResistancePriority(.required, for: .horizontal)
                dot.alphaValue = 0
                dot.isHidden = true
                separatorWidth = max(measuredWidth(dot), 6)
                let sepConstraint = dot.widthAnchor.constraint(equalToConstant: 0)
                sepConstraint.isActive = true
                separatorWidthConstraint = sepConstraint
                separator = dot
            }

            let compactWidth = horizontalPadding * 2 + titleWidth
            let expandedWidth: CGFloat = {
                guard shouldExpand else { return compactWidth }
                return compactWidth
                    + stackSpacing
                    + separatorWidth
                    + stackSpacing
                    + previewWidth
            }()

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: compactWidth, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.hasShadow = true
            window.isFloatingPanel = true
            window.ignoresMouseEvents = true

            let pill = makePillView(cornerRadius: height / 2)
            pill.translatesAutoresizingMaskIntoConstraints = false

            let content = NSView()
            content.translatesAutoresizingMaskIntoConstraints = false
            contentWidthConstraint = content.widthAnchor.constraint(equalToConstant: compactWidth)
            contentWidthConstraint?.priority = .required
            contentWidthConstraint?.isActive = true

            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.alignment = .centerY
            // No spacing while compact — preview views are hidden/zero-width.
            stack.spacing = 0
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(titleLabel)

            if let separator, let previewLabel {
                stack.addArrangedSubview(separator)
                stack.addArrangedSubview(previewLabel)
            }

            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: horizontalPadding),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
                content.heightAnchor.constraint(equalToConstant: height),
            ])

            installContent(content, in: pill)

            let root = NSView(frame: NSRect(x: 0, y: 0, width: compactWidth, height: height))
            root.addSubview(pill)
            pill.frame = root.bounds
            pill.autoresizingMask = [.width, .height]
            window.contentView = root

            let screenFrame = screen.visibleFrame
            let y = screenFrame.minY + 52
            func framed(_ width: CGFloat) -> NSRect {
                NSRect(x: screenFrame.midX - width / 2, y: y, width: width, height: height)
            }

            window.setFrame(framed(compactWidth), display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
            }

            if playSound {
                NSSound(named: "Tink")?.play()
            }

            hudWindow = window
            installClickMonitor(clipID: clipID)

            if shouldExpand,
               let separator,
               let previewLabel,
               let previewWidthConstraint,
               let separatorWidthConstraint,
               let contentWidthConstraint {
                // Hold on full "Saved to Zinc", then grow sideways into the preview.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    guard hudWindow === window else { return }

                    separator.isHidden = false
                    previewLabel.isHidden = false

                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.48
                        context.allowsImplicitAnimation = true
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        stack.animator().spacing = stackSpacing
                        separatorWidthConstraint.animator().constant = separatorWidth
                        previewWidthConstraint.animator().constant = previewWidth
                        contentWidthConstraint.animator().constant = expandedWidth
                        separator.animator().alphaValue = 1
                        previewLabel.animator().alphaValue = 1
                        window.animator().setFrame(framed(expandedWidth), display: true)
                    }
                }
            }

            let hold: TimeInterval = shouldExpand ? 2.4 : 1.5
            let work = DispatchWorkItem {
                guard hudWindow === window else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.28
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    if hudWindow === window {
                        hudWindow = nil
                    }
                })
            }
            dismissWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hold, execute: work)
        }
    }

    private static func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        removeClickMonitor()
        hudWindow?.orderOut(nil)
        hudWindow = nil
    }

    /// Pill stays click-through (`ignoresMouseEvents`); Cmd+Click is detected globally.
    private static func installClickMonitor(clipID: UUID?) {
        removeClickMonitor()
        guard let clipID else { return }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains(.command) else { return }
            guard let window = hudWindow, window.frame.contains(NSEvent.mouseLocation) else { return }

            DispatchQueue.main.async {
                guard hudWindow != nil else { return }
                dismiss()
                ClipPanelController.shared.openPanel(selecting: clipID)
            }
        }
    }

    private static func removeClickMonitor() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    private static func collapsedPreview(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func measuredWidth(_ label: NSTextField) -> CGFloat {
        let font = label.font ?? .systemFont(ofSize: 12)
        let string = label.stringValue as NSString
        let size = string.size(withAttributes: [.font: font])
        return ceil(size.width)
    }

    private static func makeLabel(
        _ string: String,
        weight: NSFont.Weight,
        size: CGFloat,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .vertical)
        return label
    }

    private static func makePillView(cornerRadius: CGFloat) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            return glass
        }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.masksToBounds = true
        return effect
    }

    private static func installContent(_ content: NSView, in pill: NSView) {
        if #available(macOS 26.0, *), let glass = pill as? NSGlassEffectView {
            glass.contentView = content
            return
        }

        pill.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            content.topAnchor.constraint(equalTo: pill.topAnchor),
            content.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
        ])
    }
}
