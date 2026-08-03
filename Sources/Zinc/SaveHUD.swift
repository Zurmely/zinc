import AppKit

enum SaveHUD {
    private static var hudWindow: NSWindow?

    static func show(text: String, source: String) {
        present(title: "Saved to Zinc", body: text, detail: source, playSound: true)
    }

    static func showFailure() {
        present(
            title: "Nothing to save",
            body: "Select some text, then double-tap Shift",
            detail: nil,
            playSound: false
        )
    }

    static func showMonitorActive() {
        present(
            title: "Shift monitor active",
            body: "Double-tap Shift to save a selection",
            detail: nil,
            playSound: true
        )
    }

    private static func present(title: String, body: String, detail: String?, playSound: Bool) {
        DispatchQueue.main.async {
            dismiss()

            let screen = NSScreen.main ?? NSScreen.screens.first!
            let width: CGFloat = 320
            let height: CGFloat = detail == nil ? 56 : 72

            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

            let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            container.autoresizingMask = [.width, .height]
            container.material = .hudWindow
            container.state = .active
            container.wantsLayer = true
            container.layer?.cornerRadius = 12
            container.layer?.masksToBounds = true

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false

            let titleLabel = NSTextField(labelWithString: title)
            titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            titleLabel.textColor = .labelColor

            let textLabel = NSTextField(labelWithString: body)
            textLabel.font = .systemFont(ofSize: 11)
            textLabel.textColor = .secondaryLabelColor
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.maximumNumberOfLines = 1

            stack.addArrangedSubview(titleLabel)
            stack.addArrangedSubview(textLabel)

            if let detail {
                let sourceLabel = NSTextField(labelWithString: detail)
                sourceLabel.font = .systemFont(ofSize: 10)
                sourceLabel.textColor = .tertiaryLabelColor
                sourceLabel.lineBreakMode = .byTruncatingTail
                sourceLabel.maximumNumberOfLines = 1
                stack.addArrangedSubview(sourceLabel)
            }

            container.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
                stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
                stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            ])

            window.contentView = container

            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - width / 2
            let y = screenFrame.minY + 48
            window.setFrameOrigin(NSPoint(x: x, y: y))
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                window.animator().alphaValue = 1
            }

            if playSound {
                NSSound(named: "Tink")?.play()
            }

            hudWindow = window

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard hudWindow === window else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.25
                    window.animator().alphaValue = 0
                }, completionHandler: {
                    window.orderOut(nil)
                    if hudWindow === window {
                        hudWindow = nil
                    }
                })
            }
        }
    }

    private static func dismiss() {
        hudWindow?.orderOut(nil)
        hudWindow = nil
    }
}
