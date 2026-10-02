import NocchiCore
import SwiftUI

/// Writing to an agent, or starting a new one with a message, across the whole expanded notch:
/// Return sends, Shift-Return starts a new line, Escape closes. Grows out of the focus card.
struct Composer: View {
    let model: NotchModel
    let target: ComposeTarget
    /// The agent written to; nil for a new chat.
    let entry: AgentEntry?
    /// Shared with the focus card, whose background grows into this one.
    let card: Namespace.ID
    @State private var agentText = ""
    /// The contents fade in once the card has mostly grown.
    @State private var shown = false
    @FocusState private var focused: Bool

    /// A new chat keeps its draft in the model, so closing the field doesn't lose it.
    private var text: Binding<String> {
        entry == nil ? Binding { model.newChatDraft } set: { model.newChatDraft = $0 } : $agentText
    }

    var body: some View {
        let sending = model.prompt == .sending(target)
        let mood = entry.map(model.store.mood(of:)) ?? .idle
        let isEmpty = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                FaceView(mood: sending && entry == nil ? .working : mood, size: 30, seed: entry?.faceSeed ?? 0.37)
                    .frame(width: 34, height: 34)
                TextField(entry.map { "Ask \($0.info.displayName) something…" } ?? "What should a new agent do?",
                          text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .lineLimit(1...3)
                    .focused($focused)
                    .disabled(sending)
                    .padding(.top, 7)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            text.wrappedValue.append("\n")
                        } else {
                            model.sendPrompt(text.wrappedValue)
                        }
                        return .handled
                    }
                    .onExitCommand { model.prompt = .none }
            }
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                if let entry {
                    ContextChip(entry: entry)
                } else {
                    FolderPicker(model: model)
                        .disabled(sending)
                }
                Spacer(minLength: 8)
                if case .failed(_, let message) = model.prompt {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(FacePalette.body(for: .error).lighter(0.2).color)
                        .lineLimit(1)
                } else if sending, entry == nil {
                    Text("Starting an agent…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Button {
                    model.sendPrompt(text.wrappedValue)
                } label: {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isEmpty ? .white.opacity(0.35) : .black)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(isEmpty ? .white.opacity(0.1) : .white))
                }
                .buttonStyle(PressScale())
                .disabled(isEmpty || sending)
            }
        }
        .padding(16)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(0.07))
                .matchedGeometryEffect(id: "card", in: card)
        }
        .foregroundStyle(.white)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2).delay(0.18)) { shown = true }
        }
        .task {
            // The panel becomes key as composing starts; focus once it has.
            try? await Task.sleep(for: .milliseconds(60))
            focused = true
        }
    }
}

/// Where a new chat's agent starts: recent folders and the agents' folders, or any other.
struct FolderPicker: View {
    let model: NotchModel

    var body: some View {
        Menu {
            ForEach(model.chatFolders, id: \.self) { folder in
                Button(Self.label(folder, among: model.chatFolders)) { model.newChatFolder = folder }
            }
            Divider()
            Button("Choose…") { model.onChooseFolder?() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.newChatFolder.map { Self.label($0) } ?? "~")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.7)
            }
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(.white.opacity(0.1)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.newChatFolder.map { "Where the new agent works: \(Self.abbreviated($0))" } ?? "Where the new agent works")
    }

    static func abbreviated(_ folder: URL) -> String {
        (folder.path as NSString).abbreviatingWithTildeInPath
    }

    /// The folder and its parent ("acme/webapp"); whole when that saves little ("~/Projects/nocchi").
    /// More parents when `others` has another folder that would read the same.
    static func label(_ folder: URL, among others: [URL] = []) -> String {
        let parts = abbreviated(folder).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 2 else { return abbreviated(folder) }
        var depth = 2
        func tail(_ path: [String], _ depth: Int) -> String { path.suffix(depth).joined(separator: "/") }
        let rivals = others.filter { $0.standardizedFileURL != folder.standardizedFileURL }
            .map { abbreviated($0).split(separator: "/", omittingEmptySubsequences: false).map(String.init) }
        while depth < parts.count, rivals.contains(where: { tail($0, depth) == tail(parts, depth) }) { depth += 1 }
        // Keep "~/x" rather than "x" for folders right under home; a leading "" means the root.
        if depth >= parts.count - 1 { return abbreviated(folder) }
        return tail(parts, depth)
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
