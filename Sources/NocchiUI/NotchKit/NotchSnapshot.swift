import AppKit
import SwiftUI

/// Renders the notch offscreen to PNG. A dev tool for checking drawing without Screen Recording
/// permission (`nocchi --snapshot <dir>`).
@MainActor
public enum NotchSnapshot {
    /// Writes `notch-<mode>.png` for every mode into `directory`, on a wallpaper-like backdrop.
    public static func write(to directory: URL, geometry: NotchGeometry, scale: CGFloat = 2) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try [NotchMode.collapsed, .expanded].map { mode in
            let model = NotchModel(geometry: geometry)
            model.mode = mode
            let size = model.panelSize
            let view = NotchView(model: model)
                .frame(width: size.width, height: size.height)
                .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))

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
    }

    enum SnapshotError: Error { case renderFailed(NotchMode) }
}
