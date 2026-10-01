import NocchiCore
import SwiftUI

/// Expanded while a folder is dragged near the notch, and while the agent it starts comes up:
/// a dashed drop zone, then a progress bar with the face riding it as the handle.
struct DropView: View {
    let model: NotchModel

    var body: some View {
        let body = model.bodySize(for: .expanded)
        VStack(spacing: 0) {
            Color.clear.frame(height: model.geometry.notchSize.height)
            content
                .padding(EdgeInsets(top: 8, leading: OverviewView.gutter, bottom: 16, trailing: OverviewView.gutter))
        }
        .frame(width: body.width, height: body.height)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var content: some View {
        switch model.drop {
        case .none:
            Color.clear
        case .offering(let isTargeted):
            DropZone(isTargeted: isTargeted)
        case .starting(let folder, let since):
            TimelineView(.animation) { context in
                ProgressCard(title: "Starting Claude in \(folder.lastPathComponent)", detail: folder.path,
                             mood: .working, progress: DropState.progress(after: context.date.timeIntervalSince(since)))
            }
        case .started(let folder):
            ProgressCard(title: "Claude is running in \(folder.lastPathComponent)", detail: "New Herdr workspace",
                         mood: .done, progress: 1)
        case .failed(let folder, let message):
            ProgressCard(title: "Couldn't start Claude in \(folder.lastPathComponent)", detail: message,
                         mood: .error, progress: nil)
        }
    }
}

private struct DropZone: View {
    let isTargeted: Bool

    var body: some View {
        let tint = isTargeted ? Mood.done.tint : Color.white
        HStack(spacing: 16) {
            FaceView(mood: isTargeted ? .done : .idle, size: 52, seed: 0.37)
                .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                Text(isTargeted ? "Let go to start Claude here" : "Drop a folder to start Claude")
                    .font(.system(size: 15, weight: .semibold))
                Text("It opens in a new Herdr workspace.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tint.opacity(isTargeted ? 0.12 : 0.04))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(isTargeted ? 0.8 : 0.35), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: isTargeted)
    }
}

private struct ProgressCard: View {
    let title: String
    let detail: String
    let mood: Mood
    /// nil hides the bar (failure).
    let progress: Double?

    static let faceSize: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if progress == nil {
                    FaceView(mood: mood, size: Self.faceSize, seed: 0.37)
                        .frame(width: Self.faceSize + 8, height: Self.faceSize + 8)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2).truncationMode(.middle)
                }
            }
            if let progress {
                ProgressTrack(progress: progress, mood: mood)
                    .frame(height: Self.faceSize + 8)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.06)))
    }
}

/// A bar whose handle is the face.
private struct ProgressTrack: View {
    let progress: Double
    let mood: Mood

    var body: some View {
        GeometryReader { proxy in
            let size = ProgressCard.faceSize
            let width = proxy.size.width
            let x = size / 2 + (width - size) * progress
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1)).frame(height: 8)
                Capsule().fill(mood.tint.opacity(0.85)).frame(width: max(8, x), height: 8)
                FaceView(mood: mood, size: size, seed: 0.37)
                    .frame(width: size, height: size)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
