import Foundation

final class MarkdownPreviewStore: ObservableObject {
    static let shared = MarkdownPreviewStore()

    @Published private(set) var documents: [UUID: MarkdownDocument] = [:]

    private let cache = NSCache<NSString, MarkdownDocumentBox>()
    private let queue = DispatchQueue(label: "com.zurmely.zinc.preview-load")

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
        queue.async { [weak self] in
            guard let self else { return }
            let document: MarkdownDocument

            if let path = clip.markdownPath,
               FileManager.default.fileExists(atPath: path),
               let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                document = MarkdownDocument.parse(fileContents: contents)
            } else {
                document = MarkdownDocument.fallback(from: clip.text)
            }

            self.cache.setObject(MarkdownDocumentBox(document), forKey: clip.id.uuidString as NSString)

            DispatchQueue.main.async {
                self.documents[clip.id] = document
            }
        }
    }

    func invalidate(ids: Set<UUID>) {
        for id in ids {
            cache.removeObject(forKey: id.uuidString as NSString)
            documents.removeValue(forKey: id)
        }
    }

    func clear() {
        cache.removeAllObjects()
        documents.removeAll()
    }
}

private final class MarkdownDocumentBox: NSObject {
    let document: MarkdownDocument

    init(_ document: MarkdownDocument) {
        self.document = document
    }
}
