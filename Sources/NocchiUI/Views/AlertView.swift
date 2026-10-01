import NocchiCore
import SwiftUI

/// Expanded, when the primary agent needs you, failed or just finished: one wide card with a glow
/// in the mood's color, what happened, and a way to jump to the agent.
struct AlertView: View {
    let store: AgentStore
    let entry: AgentEntry
    let mood: Mood

    var body: some View {
        HStack(spacing: 18) {
            FaceView(mood: mood, size: 60, seed: entry.faceSeed)
                .frame(width: 84, height: 84)
                .background {
                    RadialGradient(colors: [mood.tint.opacity(0.4), .clear], center: .center, startRadius: 8, endRadius: 64)
                        .frame(width: 140, height: 140)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(mood == .error ? FacePalette.body(for: .error).lighter(0.2).color : .white.opacity(0.6))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { Task { try? await store.perform(.open(entry.ref)) } }

            if store.capabilities(of: entry.ref).contains(.focus) {
                Button {
                    Task { try? await store.perform(.open(entry.ref)) }
                } label: {
                    Image(systemName: mood == .error ? "arrow.clockwise" : "arrow.up.forward.app")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Open \(entry.info.displayName)")
            }
            FaceColumn(store: store, excluding: entry.ref)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.05))
                AlertGlow(color: FacePalette.body(for: mood))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .foregroundStyle(.white)
    }

    private var title: String {
        let name = entry.info.displayName
        switch mood {
        case .waiting: return "\(name) needs you"
        case .error: return "\(name) couldn't finish"
        case .done: return "\(name) is done"
        default: return name
        }
    }

    private var detail: String? {
        if case .error(let message) = entry.info.status, let message { return message }
        return entry.currentStep
    }
}

/// A glow rising from the bottom corners of the card. Static on purpose: animating a mesh would
/// re-render the panel every frame.
private struct AlertGlow: View {
    let color: RGBA

    var body: some View {
        let clear = color.opacity(0).color
        let soft = color.opacity(0.22).color
        let strong = color.opacity(0.55).color
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.5, 0.75], [1, 0.55],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                clear, clear, clear,
                soft, clear, soft,
                strong, soft, strong,
            ]
        )
    }
}
