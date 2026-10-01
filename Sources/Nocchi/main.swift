import AppKit
import NocchiUI

// Dev tool: `nocchi --snapshot <dir>` renders the notch to PNGs and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let dir = CommandLine.arguments.dropFirst(flag + 1).first ?? "."
    MainActor.assumeIsolated {
        let geometry = NotchGeometry.preferredScreen().map(NotchGeometry.init(screen:))
            ?? .make(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                     topLeftArea: CGRect(x: 0, y: 0, width: 663, height: 32),
                     topRightArea: CGRect(x: 0, y: 0, width: 663, height: 32), menuBarHeight: 32)
        do {
            for url in try NotchSnapshot.write(to: URL(fileURLWithPath: dir), geometry: geometry) { print(url.path) }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
