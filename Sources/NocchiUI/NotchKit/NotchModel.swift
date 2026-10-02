import Foundation
import NocchiCore
import Observation
import SwiftUI

public enum NotchMode: Sendable, Equatable {
    case collapsed
    case expanded
}

/// Observable state of the notch: mode, hover, and the sizes derived from the screen geometry.
@MainActor
@Observable
public final class NotchModel {
    public var geometry: NotchGeometry
    public var mode: NotchMode = .collapsed {
        didSet {
            guard mode != oldValue else { return }
            notchLog.info("mode: \(String(describing: self.mode), privacy: .public)")
            if mode == .collapsed { isPeeking = false }
            beginMorph()
        }
    }
    /// True while the shape animates between modes. Live faces are AppKit views, which SwiftUI
    /// can't clip to the notch shape or transition, so faces draw as still frames meanwhile.
    public private(set) var isMorphing = false
    @ObservationIgnored private var morphEnd: Task<Void, Never>?
    static let morphDuration: Duration = .milliseconds(550)
    public var isHovering = false
    /// Debug: stay expanded regardless of hover.
    public var isPinned = false
    /// Debug: outline the interactive area.
    public var showsHitArea = false

    public let store: AgentStore
    /// Short messages for the middle of the collapsed notch on screens without a hardware notch.
    public let ticker = Ticker()
    /// The launch greeting is showing.
    public var isGreeting = false
    public var drop: DropState = .none
    /// The mini peek: a line under the collapsed notch for finished or failed agents.
    public var banner: PeekBanner?
    /// Opened by a peek rather than the pointer: opens without the playful bounce.
    public var isPeeking = false
    /// Writing a message to an agent, or to a new one, from the notch.
    public var prompt: PromptState = .none {
        didSet {
            guard prompt != oldValue else { return }
            if oldValue.target != nil && prompt.target == nil { composerClosedAt = Date() }
            onPromptChange?(prompt)
        }
    }
    /// When the composer last closed. Set before the views update, so the chips coming back can
    /// wait for the focus card to shrink into place.
    @ObservationIgnored var composerClosedAt: Date?
    var composerJustClosed: Bool { composerClosedAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false }
    @ObservationIgnored var onPromptChange: ((PromptState) -> Void)?
    /// Called with the folder when one is dropped on the notch.
    @ObservationIgnored var onDropFolder: ((URL) -> Void)?

    /// The new chat's message, kept when the field closes so a stray click doesn't lose it.
    var newChatDraft = ""
    /// Where the new chat's agent starts; nil until a chat opens (then `defaultChatFolder`).
    public var newChatFolder: URL?
    /// The folder picker is up: the panel isn't key meanwhile, but the chat stays open.
    var isChoosingFolder = false
    @ObservationIgnored var onChooseFolder: (() -> Void)?
    /// Shows the settings menu (the status item's) at the pointer.
    @ObservationIgnored public var onOpenSettings: (() -> Void)?

    /// Stay open regardless of hover.
    var holdsOpen: Bool { isPinned || drop != .none || prompt != .none || isChoosingFolder }

    /// Opens the field that starts a new agent.
    func startNewChat() {
        if newChatFolder == nil { newChatFolder = defaultChatFolder }
        prompt = .composing(.newAgent)
    }

    /// The last folder a chat started in, else the primary agent's, else home.
    var defaultChatFolder: URL {
        let fileManager = FileManager.default
        if let last = NocchiSettings.shared.recentChatFolders.first, fileManager.fileExists(atPath: last) {
            return URL(fileURLWithPath: last)
        }
        return store.primary?.info.cwd ?? fileManager.homeDirectoryForCurrentUser
    }

    /// Folders to offer for a new chat: the chosen one, recent ones, then the agents' folders.
    var chatFolders: [URL] {
        let agents = store.state.agents.values.sorted { $0.info.changedAt > $1.info.changedAt }.compactMap(\.info.cwd)
        let candidates = [newChatFolder].compactMap { $0 }
            + NocchiSettings.shared.recentChatFolders.map { URL(fileURLWithPath: $0) } + agents
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }.prefix(8).map { $0 }
    }

    /// Sends `text` to the agent being written to, or starts a new agent with it. On failure the
    /// message stays a few seconds.
    func sendPrompt(_ text: String) {
        guard case .composing(let target) = prompt else { return }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let action: AgentAction
        switch target {
        case .agent(let ref):
            action = .prompt(ref, text)
        case .newAgent:
            let folder = newChatFolder ?? defaultChatFolder
            action = .start(kind: .claude, cwd: folder, prompt: text)
        }
        prompt = .sending(target)
        Task {
            do {
                try await store.perform(action)
                if case .start(_, let folder, _) = action {
                    NocchiSettings.shared.rememberChatFolder(folder)
                    newChatDraft = ""
                }
                if prompt == .sending(target) { prompt = .none }
            } catch {
                let message = switch error {
                case AgentActionError.failed(let why): why
                case AgentActionError.unsupported: "Turn on Herdr or Claude Code under Sources to start agents."
                default: "\(error)"
                }
                guard prompt == .sending(target) else { return }
                prompt = .failed(target, message: message)
                try? await Task.sleep(for: .seconds(4))
                if prompt == .failed(target, message: message) { prompt = .composing(target) }
            }
        }
    }

    /// Faces stop animating while the displays sleep. (Window occlusion isn't used: for a
    /// transparent, always-on-top panel it can report "not visible" while the notch is on screen.)
    public var screensAsleep = false
    var facesPaused: Bool { screensAsleep }

    public init(geometry: NotchGeometry, store: AgentStore) {
        self.geometry = geometry
        self.store = store
    }

    private func beginMorph() {
        isMorphing = true
        morphEnd?.cancel()
        morphEnd = Task { [weak self] in
            try? await Task.sleep(for: Self.morphDuration)
            guard !Task.isCancelled else { return }
            self?.isMorphing = false
        }
    }

    // MARK: Metrics

    /// Width of each side slot next to the notch (left face, right cluster) when collapsed.
    var earWidth: CGFloat { (geometry.notchSize.height * 1.3).rounded() }

    var topRadius: CGFloat { mode == .expanded ? 14 : 6 }
    var bottomRadius: CGFloat { mode == .expanded ? 32 : 12 }

    /// Size of the body (excluding the shoulders) for a mode.
    func bodySize(for mode: NotchMode) -> CGSize {
        let notch = geometry.notchSize
        switch mode {
        case .collapsed:
            return CGSize(width: notch.width + 2 * earWidth, height: notch.height + (banner == nil ? 0 : Self.bannerHeight))
        case .expanded:
            return CGSize(width: max(notch.width + 2 * earWidth, 640), height: notch.height + 168)
        }
    }

    /// Full shape size for a mode, shoulders included.
    func shapeSize(for mode: NotchMode) -> CGSize {
        let body = bodySize(for: mode)
        let top: CGFloat = mode == .expanded ? 14 : 6
        return CGSize(width: body.width + 2 * top, height: body.height)
    }

    /// Screen rect that receives the mouse in the current mode.
    public var hitRect: CGRect {
        geometry.rectHanging(shapeSize(for: mode))
    }

    /// Size the panel must have so every mode (plus its shadow) fits.
    public var panelSize: CGSize {
        let expanded = shapeSize(for: .expanded)
        return CGSize(width: expanded.width + 2 * Self.shadowMargin, height: expanded.height + Self.shadowMargin)
    }

    static let shadowMargin: CGFloat = 40
    static let bannerHeight: CGFloat = 24
}

/// Dragging a folder onto the notch starts an agent there.
public enum DropState: Equatable, Sendable {
    case none
    /// A file drag is near the notch; `isTargeted` while it's over it.
    case offering(isTargeted: Bool)
    case starting(folder: URL, since: Date)
    case started(folder: URL)
    case failed(folder: URL, message: String)

    /// The folder to start in for a dropped item: itself if it's a folder, else its parent.
    static func folder(for url: URL) -> URL {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        return isDirectory ? url : url.deletingLastPathComponent()
    }

    /// The bar's position while an agent starts: eases toward 90 % and waits there for Herdr.
    static func progress(after seconds: TimeInterval) -> Double {
        0.9 * (1 - exp(-max(0, seconds) / 2.5))
    }
}

/// Who a message goes to.
public enum ComposeTarget: Hashable, Sendable {
    case agent(AgentRef)
    /// Starts a new agent with the message.
    case newAgent
}

public enum PromptState: Equatable, Sendable {
    case none
    case composing(ComposeTarget)
    case sending(ComposeTarget)
    case failed(ComposeTarget, message: String)

    /// Who is being written to.
    var target: ComposeTarget? {
        switch self {
        case .none: nil
        case .composing(let target), .sending(let target), .failed(let target, _): target
        }
    }
}
