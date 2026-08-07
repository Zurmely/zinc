import AppKit

enum SystemSounds {
    private static let trashURL = URL(fileURLWithPath:
        "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif")

    static func playTrash() {
        NSSound(contentsOf: trashURL, byReference: true)?.play()
    }
}
