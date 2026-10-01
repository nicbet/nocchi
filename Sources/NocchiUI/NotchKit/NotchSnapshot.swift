import NocchiCore
import AppKit
import SwiftUI

/// Renders the notch offscreen to PNG. A dev tool for checking drawing without Screen Recording
/// permission (`nocchi --snapshot <dir>`).
@MainActor
public enum NotchSnapshot {
    /// Writes `notch-<mode>.png` for every mode into `directory`, on a wallpaper-like backdrop.
    public static func write(to directory: URL, geometry: NotchGeometry, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var urls = try [NotchMode.collapsed, .expanded].map { mode in
            let model = NotchModel(geometry: geometry, store: previewStore(.showcase))
            model.mode = mode
            let size = model.panelSize
            let view = NotchView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                .facesRenderStill()

            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage else { throw SnapshotError.renderFailed(mode) }
            let url = directory.appendingPathComponent("notch-\(mode).png")
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw SnapshotError.renderFailed(mode)
            }
            try data.write(to: url)
            return url
        }
        do {
            let model = NotchModel(geometry: geometry, store: previewStore(.quiet))
            model.isGreeting = true
            model.mode = .expanded
            let size = model.panelSize
            let renderer = ImageRenderer(content: NotchView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                .facesRenderStill())
            renderer.scale = scale
            if let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                let url = directory.appendingPathComponent("notch-greeting.png")
                try data.write(to: url)
                urls.append(url)
            }
        }
        do {
            // Filmstrip of the greeting's choreography.
            let times = [0.15, 0.6, 1.15, 1.6, 2.2, 2.6, 2.95, 3.5]
            let strip = VStack(spacing: 8) {
                ForEach(times, id: \.self) { t in
                    HStack {
                        Text(String(format: "%.1f s", t)).font(.caption.monospaced()).foregroundStyle(.white).frame(width: 50)
                        GreetingScene(t: t, homeX: OverviewView.focusFaceX(bodyWidth: 640))
                            .frame(width: 604, height: 144)
                    }
                }
            }
            .padding(12)
            .background(.black)
            .facesRenderStill()
            let renderer = ImageRenderer(content: strip)
            renderer.scale = scale
            if let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                let url = directory.appendingPathComponent("greeting-filmstrip.png")
                try data.write(to: url)
                urls.append(url)
            }
        }
        for scenario in [MockScenario.needsYou, .failure] {
            let model = NotchModel(geometry: geometry, store: previewStore(scenario))
            model.mode = .expanded
            let size = model.panelSize
            let view = NotchView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                .facesRenderStill()
            let renderer = ImageRenderer(content: view)
            renderer.scale = scale
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw SnapshotError.renderFailed(.expanded) }
            let url = directory.appendingPathComponent("notch-alert-\(scenario.name.lowercased().replacingOccurrences(of: " ", with: "-")).png")
            try data.write(to: url)
            urls.append(url)
        }
        urls.append(try writeGallery(to: directory, scale: scale))
        return urls
    }

    static func writeGallery(to directory: URL, scale: CGFloat) throws -> URL {
        let renderer = ImageRenderer(content: MoodGallery().frame(width: 760).facesRenderStill())
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw SnapshotError.renderFailed(.expanded) }
        let url = directory.appendingPathComponent("mood-gallery.png")
        try data.write(to: url)
        return url
    }

    /// A store holding a scenario's starting agents, with a couple of steps for the carousel.
    static func previewStore(_ scenario: MockScenario) -> AgentStore {
        let store = AgentStore()
        let infos = scenario.agents.map { agent in
            AgentInfo(ref: AgentRef(adapter: "mock", localID: agent.id), kind: agent.kind, status: agent.status,
                      name: agent.name, title: agent.title, isFocused: agent.focused, changedAt: Date())
        }
        store.apply(.connection(.connected(version: "preview")), from: "mock")
        store.apply(.snapshot(infos), from: "mock")
        if scenario.name == MockScenario.showcase.name, let first = infos.first {
            store.apply(.step(first.ref, "Prep workspace"), from: "mock")
            store.apply(.step(first.ref, "Copy final outputs"), from: "mock")
        }
        return store
    }

    enum SnapshotError: Error { case renderFailed(NotchMode) }
}
