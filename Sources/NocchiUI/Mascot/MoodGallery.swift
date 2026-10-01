import AppKit
import NocchiCore
import SwiftUI

/// Debug view: every mood at several sizes and colors, plus one big face to watch transitions.
public struct MoodGallery: View {
    /// Sizes the faces appear at: gallery, expanded card, expanded cluster, collapsed primary, collapsed cluster.
    static let sizes: [(label: String, points: CGFloat)] = [("large", 64), ("card", 40), ("chip", 30), ("notch", 18), ("cluster", 10)]

    static func colorName(_ mood: Mood) -> String {
        switch mood {
        case .idle: "white"
        case .thinking: "purple"
        case .working: "blue"
        case .waiting: "amber"
        case .done: "green"
        case .error: "red"
        case .sleep: "gray"
        }
    }

    @State private var mood: Mood = .idle
    @State private var cycling = false

    private let cycle = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 28) {
                FaceView(mood: mood, size: 120, seed: 0.37)
                    .frame(width: 200, height: 200)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transitions").font(.headline)
                    Picker("Mood", selection: $mood) {
                        ForEach(Mood.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Toggle("Cycle every 2 s", isOn: $cycling)
                }
            }

            Grid(alignment: .center, horizontalSpacing: 26, verticalSpacing: 18) {
                GridRow {
                    Text("")
                    ForEach(Self.sizes, id: \.label) { Text($0.label) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(Array(Mood.allCases.enumerated()), id: \.element) { row, mood in
                    GridRow {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(mood.rawValue).font(.callout.monospaced())
                            Text(Self.colorName(mood)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .gridColumnAlignment(.trailing)
                        ForEach(Array(Self.sizes.enumerated()), id: \.element.label) { column, size in
                            FaceView(mood: mood, size: size.points, seed: Double(row * 5 + column) * 0.17)
                                .frame(width: max(size.points * 1.5, 24), height: max(size.points * 1.4, 24))
                        }
                    }
                }
            }
        }
        .padding(28)
        .background(Color(white: 0.06))
        .environment(\.colorScheme, .dark)
        .onReceive(cycle) { _ in
            guard cycling else { return }
            let all = Mood.allCases
            mood = all[(all.firstIndex(of: mood)! + 1) % all.count]
        }
    }
}

/// Window hosting the gallery. Faces follow the pointer inside it.
@MainActor
public final class MoodGalleryWindow {
    private var window: NSWindow?

    public init() {}

    public func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 760, height: 900),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "nocchi — Mood Gallery"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MoodGallery().resolvesReduceMotion())
            window.center()
            self.window = window
        }
        // nocchi is a background (accessory) app, so plain activation can leave the window
        // behind the frontmost app's windows. Order it front regardless, then make it key.
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate()
    }
}
