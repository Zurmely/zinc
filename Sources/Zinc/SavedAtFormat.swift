import Foundation
import SwiftUI
import ZincCore

struct SavedAtText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(SavedAtFormat.string(for: date, relativeTo: context.date))
        }
    }
}
