import AppKit
import NocchiCore
import SwiftUI

/// Debug view: every mood at several sizes and colors, plus one big face to watch transitions.
public struct MoodGallery: View {
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

            Grid(alignment: .center, horizontalSpacing: 22, verticalSpacing: 18) {
                GridRow {
                    Text("")
                    Text("primary").gridColumnAlignment(.center)
                    ForEach(0..<4, id: \.self) { Text("slot \($0)") }
                    Text("notch size")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(Array(Mood.allCases.enumerated()), id: \.element) { row, mood in
                    GridRow {
                        Text(mood.rawValue).font(.callout.monospaced()).gridColumnAlignment(.trailing)
                        FaceView(mood: mood, size: 64, seed: Double(row) * 0.31).frame(width: 96, height: 84)
                        ForEach(0..<4, id: \.self) { slot in
                            FaceView(mood: mood, color: FacePalette.bot(slot), size: 40, seed: Double(row * 4 + slot) * 0.17)
                                .frame(width: 64, height: 64)
                        }
                        HStack(spacing: 6) {
                            FaceView(mood: mood, size: 20, seed: Double(row) * 0.53)
                            FaceView(mood: mood, color: FacePalette.bot(row), size: 10, seed: Double(row) * 0.71)
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
