import Foundation
import ZincCore

final class MarkdownPreviewStore: ObservableObject {
    static let shared = MarkdownPreviewStore()

    @Published private(set) var documents: [UUID: MarkdownDocument] = [:]

    private let cache = NSCache<NSString, MarkdownDocumentBox>()
    private let queue = DispatchQueue(label: "com.zurmely.zinc.preview-load")
    private var loadGeneration: [UUID: Int] = [:]

    private init() {
        cache.countLimit = 100
    }

    func document(for clip: Clip) -> MarkdownDocument {
        if let cached = documents[clip.id] {
            return cached
        }

        if let box = cache.object(forKey: clip.id.uuidString as NSString) {
            documents[clip.id] = box.document
            return box.document
        }

        let fallback = MarkdownDocument.fallback(from: clip.text)
        documents[clip.id] = fallback
        loadIfNeeded(for: clip)
        return fallback
    }

    func loadIfNeeded(for clip: Clip) {
        let clipID = clip.id
        // Prefer the store's current clip so we see markdownPath after export.
        let latest = ClipStore.shared.clips.first(where: { $0.id == clipID }) ?? clip
        let generation = nextGeneration(for: clipID)

        let markdownPath = latest.markdownPath
        let fallbackText = latest.text

        queue.async { [weak self] in
            guard let self else { return }
            let document: MarkdownDocument

            if let path = markdownPath,
               FileManager.default.fileExists(atPath: path),
               let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                document = MarkdownDocument.parse(fileContents: contents)
            } else {
                document = MarkdownDocument.fallback(from: fallbackText)
            }

            DispatchQueue.main.async {
                guard self.loadGeneration[clipID] == generation else { return }
                self.cache.setObject(MarkdownDocumentBox(document), forKey: clipID.uuidString as NSString)
                self.documents[clipID] = document
            }
        }
    }

    func invalidate(ids: Set<UUID>) {
        for id in ids {
            cache.removeObject(forKey: id.uuidString as NSString)
            documents.removeValue(forKey: id)
            loadGeneration[id] = (loadGeneration[id] ?? 0) + 1
        }
    }

    func clear() {
        cache.removeAllObjects()
        documents.removeAll()
        loadGeneration.removeAll()
    }

    private func nextGeneration(for id: UUID) -> Int {
        let value = (loadGeneration[id] ?? 0) + 1
        loadGeneration[id] = value
        return value
    }
}

private final class MarkdownDocumentBox: NSObject {
    let document: MarkdownDocument

    init(_ document: MarkdownDocument) {
        self.document = document
    }
}
