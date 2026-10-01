import NocchiCore
import SwiftUI

/// The other agents as a narrow column of small faces, in a capsule. Used beside the alert card,
/// and in the overview, where it widens into the chips when the pointer comes over it.
struct FaceColumn<Background: View>: View {
    let store: AgentStore
    let excluding: AgentRef?
    /// The capsule behind the faces; the overview swaps in a matched-geometry one.
    let background: Background

    static var width: CGFloat { 34 }

    var body: some View {
        let (others, hidden) = store.others(fitting: 4)
        if !others.isEmpty {
            VStack(spacing: 4) {
                ForEach(others.filter { $0.ref != excluding }, id: \.ref) { other in
                    FaceView(mood: store.mood(of: other), size: 18, seed: other.faceSeed)
                        .frame(width: 22, height: 22)
                }
                if !hidden.isEmpty {
                    OverflowBadge(count: hidden.count, mood: store.summaryMood(of: hidden) ?? .idle, size: 18)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 10)
            .frame(width: Self.width)
            .background(background)
        }
    }
}

extension FaceColumn where Background == AnyView {
    init(store: AgentStore, excluding: AgentRef?) {
        self.init(store: store, excluding: excluding, background: AnyView(Capsule().fill(.black.opacity(0.35))))
    }
}
