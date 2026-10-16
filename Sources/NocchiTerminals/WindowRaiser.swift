import AppKit
import ApplicationServices

/// The window server ID (`CGWindowID`) of an Accessibility window. Private, but stable for years
/// and widely used; there is no public equivalent.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Raises the exact terminal window (and tab) an agent lives in, through Accessibility: an app's
/// windows and tab-bar tabs are listed with their titles, and the one whose title best matches
/// the agent (its session title, its folder, its Herdr workspace) is raised. Needs the user to
/// allow nocchi under Privacy & Security ▸ Accessibility; without it, "open" brings the app
/// forward as before.
@MainActor
public enum WindowRaiser {
    public nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS to show its Accessibility prompt (once; later it's System Settings).
    public static func requestAccess() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read as a global var.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Raises `app`'s window or tab whose title best matches `hints` (most specific first).
    /// Returns false when not allowed or nothing matched.
    @discardableResult
    public static func raise(in app: NSRunningApplication, matching hints: [String]) -> Bool {
        guard isTrusted, !hints.isEmpty else { return false }
        guard let match = bestCandidate(candidates(in: AXUIElementCreateApplication(app.processIdentifier)), hints: hints) else {
            return false
        }
        if match.isTab { AXUIElementPerformAction(match.element, kAXPressAction as CFString) }
        AXUIElementSetAttributeValue(match.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(match.window, kAXRaiseAction as CFString)
        return true
    }

    /// The window server ID of the window (or the window holding the tab) in app `pid` whose
    /// title best matches `hints`, as `raise(in:matching:)` would pick it. Changes nothing. Nil
    /// when Accessibility isn't allowed or nothing matches. Runs on any thread.
    public nonisolated static func windowID(in pid: pid_t, matching hints: [String]) -> CGWindowID? {
        windowIDs(in: pid, matching: [hints])[0]
    }

    /// `windowID(in:matching:)` for several agents in the same app, one result per hints list in
    /// the same order, walking the app's windows and tabs once. A slow or hung app gives up
    /// quickly, so it's fine to call every few seconds (see `AgentInfo.host`). Runs on any thread.
    public nonisolated static func windowIDs(in pid: pid_t, matching hints: [[String]]) -> [CGWindowID?] {
        guard isTrusted, hints.contains(where: { !$0.isEmpty }) else { return hints.map { _ in nil } }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return bestCandidates(candidates(in: app), hints: hints).map { match in
            var id: CGWindowID = 0
            guard let match, _AXUIElementGetWindow(match.window, &id) == .success, id != 0 else { return nil }
            return id
        }
    }

    /// A window or a tab-bar tab, and the window it's in (itself, for a window).
    struct Candidate<Element> {
        var element: Element
        var window: Element
        var title: String
        var isTab: Bool
    }

    /// Each window, then its tabs, with their titles.
    private nonisolated static func candidates(in app: AXUIElement) -> [Candidate<AXUIElement>] {
        var candidates: [Candidate<AXUIElement>] = []
        for window in elements(app, kAXWindowsAttribute) {
            candidates.append(Candidate(element: window, window: window, title: string(window, kAXTitleAttribute) ?? "", isTab: false))
            for tab in tabs(in: window, depth: 0) {
                candidates.append(Candidate(element: tab, window: window, title: string(tab, kAXTitleAttribute) ?? "", isTab: true))
            }
        }
        return candidates
    }

    /// The window or tab whose title best matches `hints` (see `bestMatch`).
    nonisolated static func bestCandidate<Element>(_ candidates: [Candidate<Element>], hints: [String]) -> Candidate<Element>? {
        bestMatch(titles: candidates.map(\.title), hints: hints).map { candidates[$0] }
    }

    /// `bestCandidate` for each hints list, in order.
    nonisolated static func bestCandidates<Element>(_ candidates: [Candidate<Element>], hints: [[String]]) -> [Candidate<Element>?] {
        let titles = candidates.map(\.title)
        return hints.map { hints in bestMatch(titles: titles, hints: hints).map { candidates[$0] } }
    }

    /// The title that matches the earliest hint, the longest such hint winning ties; nil if none
    /// matches. Case-insensitive; Claude's leading status glyph ("✳ ") doesn't matter.
    nonisolated static func bestMatch(titles: [String], hints: [String]) -> Int? {
        let hints = hints.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { $0.count >= 2 }
        var best: (index: Int, rank: Int, length: Int)?
        for (index, title) in titles.enumerated() {
            let title = title.lowercased()
            for (rank, hint) in hints.enumerated() where title.contains(hint) {
                if best == nil || rank < best!.rank || (rank == best!.rank && hint.count > best!.length) {
                    best = (index, rank, hint.count)
                }
                break
            }
        }
        return best?.index
    }

    /// Tab-bar tabs (radio buttons in a tab group), a few levels into the window.
    private nonisolated static func tabs(in element: AXUIElement, depth: Int) -> [AXUIElement] {
        guard depth < 4 else { return [] }
        var found: [AXUIElement] = []
        for child in elements(element, kAXChildrenAttribute) {
            let role = string(child, kAXRoleAttribute)
            if role == kAXTabGroupRole as String {
                found += elements(child, kAXChildrenAttribute).filter { string($0, kAXRoleAttribute) == kAXRadioButtonRole as String }
            } else if role == kAXGroupRole as String || role == kAXSplitGroupRole as String || role == kAXToolbarRole as String {
                found += tabs(in: child, depth: depth + 1)
            }
        }
        return found
    }

    private nonisolated static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

extension TerminalApps {
    /// Brings `app` forward with the window best matching `hints` on top (when Accessibility is
    /// allowed and one matches; otherwise just the app).
    @discardableResult
    public static func bringToFront(_ app: NSRunningApplication, raising hints: [String]) async -> Bool {
        WindowRaiser.raise(in: app, matching: hints)
        return await bringToFront(app)
    }
}
