import NocchiCore
import SwiftUI

/// Writing to an agent, across the whole expanded notch: Return sends, Shift-Return starts a new
/// line, Escape closes.
struct Composer: View {
    let model: NotchModel
    let entry: AgentEntry
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let sending = model.prompt == .sending(entry.ref)
        let mood = model.store.mood(of: entry)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                FaceView(mood: mood, size: 30, seed: entry.faceSeed)
                    .frame(width: 34, height: 34)
                TextField("Ask \(entry.info.displayName) something…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($focused)
                    .disabled(sending)
                    .padding(.top, 7)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            text.append("\n")
                        } else {
                            model.sendPrompt(text)
                        }
                        return .handled
                    }
                    .onExitCommand { model.prompt = .none }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                ContextChip(entry: entry)
                Spacer(minLength: 8)
                if case .failed(_, let message) = model.prompt {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(FacePalette.body(for: .error).lighter(0.2).color)
                        .lineLimit(1)
                } else {
                    Text("Return to send · Shift-Return for a new line · Esc to close")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Button {
                    model.sendPrompt(text)
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(text.isEmpty ? .white.opacity(0.35) : .black)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(text.isEmpty ? .white.opacity(0.1) : .white))
                }
                .buttonStyle(PressScale())
                .disabled(text.isEmpty || sending)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.07)))
        .foregroundStyle(.white)
        .task {
            // The panel becomes key as composing starts; focus once it has.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }
}

/// Where the message goes: the agent's folder.
private struct ContextChip: View {
    let entry: AgentEntry

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .semibold))
            Text(folder)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(.white.opacity(0.08)))
        .help(entry.info.cwd?.path ?? entry.info.displayName)
    }

    private var folder: String {
        guard let cwd = entry.info.cwd else { return entry.info.displayName }
        return (cwd.path as NSString).abbreviatingWithTildeInPath
    }
}
