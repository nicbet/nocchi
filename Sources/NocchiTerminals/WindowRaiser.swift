import AppKit
import ApplicationServices

/// Raises the exact terminal window (and tab) an agent lives in, through Accessibility: an app's
/// windows and tab-bar tabs are listed with their titles, and the one whose title best matches
/// the agent (its session title, its folder, its Herdr workspace) is raised. Needs the user to
/// allow nocchi under Privacy & Security ▸ Accessibility; without it, "open" brings the app
/// forward as before.
@MainActor
public enum WindowRaiser {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

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
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var candidates: [(element: AXUIElement, window: AXUIElement, title: String, isTab: Bool)] = []
        for window in elements(root, kAXWindowsAttribute) {
            let title = string(window, kAXTitleAttribute) ?? ""
            candidates.append((window, window, title, false))
            for tab in tabs(in: window, depth: 0) {
                candidates.append((tab, window, string(tab, kAXTitleAttribute) ?? "", true))
            }
        }
        guard let index = bestMatch(titles: candidates.map(\.title), hints: hints) else { return false }
        let match = candidates[index]
        if match.isTab { AXUIElementPerformAction(match.element, kAXPressAction as CFString) }
        AXUIElementSetAttributeValue(match.window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(match.window, kAXRaiseAction as CFString)
        return true
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
    private static func tabs(in element: AXUIElement, depth: Int) -> [AXUIElement] {
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

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
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
