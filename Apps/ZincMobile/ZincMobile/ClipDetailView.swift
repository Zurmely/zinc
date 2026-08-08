import SwiftUI
import UIKit
import ZincCore

struct ClipDetailView: View {
    let clip: Clip

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.contextLabel)
                        .font(.headline)
                    Text(clip.savedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let pageURL = clip.pageURL, let url = URL(string: pageURL) {
                        Link(pageURL, destination: url)
                            .font(.caption)
                    }
                }

                Text(clip.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Clip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") {
                    UIPasteboard.general.string = clip.text
                }
            }
        }
    }
}
