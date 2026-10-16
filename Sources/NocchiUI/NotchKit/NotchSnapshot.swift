import NocchiCore
import NocchiMascot
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
            try render(previewStore(.showcase), mode: mode, geometry: geometry, scale: scale, to: directory.appendingPathComponent("notch-\(mode).png"))
        }
        // The middle of a notch-less screen: a ticker message.
        do {
            var plain = geometry
            plain.hasHardwareNotch = false
            let store = previewStore(.crowd)
            let model = NotchModel(geometry: plain, store: store)
            model.ticker.announce(Ticker.Message(ref: AgentRef(adapter: "mock", localID: "x"), name: "Atlas", mood: .waiting))
            urls.append(try render(model, mode: .collapsed, scale: scale, to: directory.appendingPathComponent("notch-ticker.png")))
            model.ticker.stop()
            model.ticker.announce(Ticker.Message(ref: AgentRef(adapter: "mock", localID: "x"), name: "Servaint-backend-migration", mood: .done))
            urls.append(try render(model, mode: .collapsed, scale: scale, to: directory.appendingPathComponent("notch-ticker-long.png")))
            model.ticker.stop()
        }
        // Dropping a folder: the zone, hovering it, starting (face as the bar's handle), failing.
        let folder = URL(fileURLWithPath: "/Users/me/Projects/nocchi")
        let drops: [(String, DropState)] = [
            ("offering", .offering(isTargeted: false)), ("targeted", .offering(isTargeted: true)),
            ("starting", .starting(folder: folder, since: Date().addingTimeInterval(-2))),
            ("failed", .failed(folder: folder, message: "Herdr error agent_pane_busy: pane is busy")),
        ]
        for (name, drop) in drops {
            let model = NotchModel(geometry: geometry, store: previewStore(.quiet))
            model.drop = drop
            urls.append(try render(model, mode: .expanded, scale: scale, to: directory.appendingPathComponent("notch-drop-\(name).png")))
        }
        // Writing to the primary agent.
        do {
            let store = previewStore(.showcase)
            let model = NotchModel(geometry: geometry, store: store)
            if var primary = store.primary?.info {
                primary.cwd = URL(fileURLWithPath: "/Users/me/code/acme/nocchi")
                store.apply(.upserted(primary), from: "mock")
                model.prompt = .composing(.agent(primary.ref))
            }
            urls.append(try render(model, mode: .expanded, scale: scale, to: directory.appendingPathComponent("notch-prompt.png")))
        }
        // The top bar beside a laptop's notch, and a new chat (a draft, the folder it starts in).
        do {
            let laptop = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                            topLeftArea: CGRect(x: 0, y: 0, width: 663, height: 32),
                                            topRightArea: CGRect(x: 0, y: 0, width: 663, height: 32), menuBarHeight: 32)
            let store = previewStore(.showcase)
            store.apply(.connection(.connected(version: "0.9.3")), from: "herdr")
            store.apply(.connection(.unavailable(reason: "off")), from: "claude")
            let model = NotchModel(geometry: laptop, store: store)
            urls.append(try render(model, mode: .expanded, scale: scale, to: directory.appendingPathComponent("notch-topbar.png")))
            model.newChatFolder = URL(fileURLWithPath: "/Users/me/Projects/nocchi")
            model.newChatDraft = "Book me an apartment in New York for the last week of September"
            model.prompt = .composing(.newAgent)
            urls.append(try render(model, mode: .expanded, scale: scale, to: directory.appendingPathComponent("notch-newchat.png")))
            model.prompt = .failed(.newAgent, message: "Herdr error agent_pane_busy: pane is busy")
            urls.append(try render(model, mode: .expanded, scale: scale, to: directory.appendingPathComponent("notch-newchat-failed.png")))
        }
        // An idle primary shows its task instead of its last tool call.
        do {
            let store = previewStore(.calm)
            store.select(AgentRef(adapter: "mock", localID: "docs"))
            urls.append(try render(store, mode: .expanded, geometry: geometry, scale: scale,
                                   to: directory.appendingPathComponent("notch-idle-expanded.png")))
        }
        // Everyone else calm: the cluster folds into a pill.
        urls.append(try render(previewStore(.calm), mode: .collapsed, geometry: geometry, scale: scale,
                               to: directory.appendingPathComponent("notch-calm-collapsed.png")))
        // The mini peek under a laptop's notch: a single finish, then a mixed burst.
        do {
            let laptop = NotchGeometry.make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                                            topLeftArea: CGRect(x: 0, y: 0, width: 663, height: 32),
                                            topRightArea: CGRect(x: 0, y: 0, width: 663, height: 32), menuBarHeight: 32)
            let model = NotchModel(geometry: laptop, store: previewStore(.showcase))
            let one = AgentRef(adapter: "mock", localID: "research")
            model.banner = PeekBanner(ref: one, name: "Research", mood: .done)
            urls.append(try render(model, mode: .collapsed, scale: scale, to: directory.appendingPathComponent("notch-banner.png")))
            model.banner = model.banner?.adding(AgentRef(adapter: "mock", localID: "travel"), mood: .done)
                .adding(AgentRef(adapter: "mock", localID: "comms"), mood: .error)
            urls.append(try render(model, mode: .collapsed, scale: scale, to: directory.appendingPathComponent("notch-banner-burst.png")))
        }
        // The chips card adapts to how many others there are (1 agent: no chips card).
        for count in [1, 2, 4, 5, 7, 9] {
            let scenario = MockScenario(name: "\(count)", agents: (0..<count).map { i in
                MockAgent("a\(i)", name: "agent \(i)", status: [.working, .idle, .thinking, .idle, .working, .idle, .idle, .working, .idle][i % 9],
                          title: "Task \(i)", focused: i == 0)
            })
            urls.append(try render(previewStore(scenario), mode: .expanded, geometry: geometry, scale: scale,
                                   to: directory.appendingPathComponent("notch-chips-\(count).png")))
        }
        // More agents than spots: the overflow badge and chip.
        for mode in [NotchMode.collapsed, .expanded] {
            urls.append(try render(previewStore(.crowd), mode: mode, geometry: geometry, scale: scale,
                                   to: directory.appendingPathComponent("notch-crowd-\(mode).png")))
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
            // Filmstrip of the greeting's choreography, in the notch. From `duration` on the notch
            // collapses: the shape follows the collapse spring and the greeting crossfades into the
            // collapsed view, as the live transition does.
            let times = [0.15, 0.6, 1.15, 1.6, 2.2, 2.55, 2.85, 2.98, 3.04, 3.1, 3.18, 3.26, 3.4]
            let model = NotchModel(geometry: geometry, store: previewStore(.quiet))
            let expanded = model.shapeSize(for: .expanded), collapsed = model.shapeSize(for: .collapsed)
            let strip = VStack(spacing: 6) {
                ForEach(times, id: \.self) { t in
                    // How much of the way back to expanded the collapse spring still is (critically damped).
                    let w = 2 * Double.pi / 0.35, tau = max(0, t - GreetingTimeline.duration)
                    let open = CGFloat((1 + w * tau) * exp(-w * tau))
                    let size = CGSize(width: collapsed.width + (expanded.width - collapsed.width) * open,
                                      height: collapsed.height + (expanded.height - collapsed.height) * open)
                    let shape = NotchShape(topRadius: 6 + 8 * open, bottomRadius: 12 + 20 * open)
                    HStack {
                        Text(String(format: "%.2f s", t)).font(.caption.monospaced()).foregroundStyle(.white).frame(width: 56)
                        ZStack(alignment: .top) {
                            shape.fill(.black).frame(width: size.width, height: size.height)
                            ZStack(alignment: .top) {
                                GreetingView(model: model, frozenAt: t).opacity(GreetingView.opacity(shown: Double(open)))
                                CollapsedView(model: model).opacity(Double(1 - open))
                            }
                            .frame(width: size.width, height: size.height, alignment: .top)
                            .clipShape(shape)
                        }
                        .frame(width: expanded.width + 20, height: expanded.height, alignment: .top)
                        .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
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

    /// Writes `live-<mode>.png` for `store`, e.g. one fed by the real Herdr (`--snapshot <dir> --live`).
    public static func writeLive(_ store: AgentStore, to directory: URL, geometry: NotchGeometry, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try [NotchMode.collapsed, .expanded].map { mode in
            try render(store, mode: mode, geometry: geometry, scale: scale, to: directory.appendingPathComponent("live-\(mode).png"))
        }
    }

    private static func render(_ store: AgentStore, mode: NotchMode, geometry: NotchGeometry, scale: CGFloat, to url: URL) throws -> URL {
        try render(NotchModel(geometry: geometry, store: store), mode: mode, scale: scale, to: url)
    }

    private static func render(_ model: NotchModel, mode: NotchMode, scale: CGFloat, to url: URL) throws -> URL {
        model.mode = mode
        let size = model.panelSize
        let view = NotchView(model: model)
            .frame(width: size.width, height: size.height)
            .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
            .facesRenderStill()

        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw SnapshotError.renderFailed(mode) }
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
