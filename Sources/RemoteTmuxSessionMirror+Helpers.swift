import Foundation
import CmuxRemoteSession

extension RemoteTmuxSessionMirror {
    nonisolated static func shouldSeedSinglePaneDisplay(for window: RemoteTmuxWindow) -> Bool {
        window.paneIDsInOrder.count == 1
    }

    /// The tab title for a mirrored window: the tmux window name, or a localized
    /// placeholder when tmux hasn't reported one. tmux window names are
    /// content-derived (like every other cmux tab title) so the name itself is
    /// not translated; only the empty-name placeholder is localized.
    nonisolated static func tabTitle(for window: RemoteTmuxWindow) -> String {
        let trimmed = window.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? String(localized: "remoteTmux.tab.window", defaultValue: "tmux window")
            : trimmed
    }

    /// Computes the target tab order for a remote-tmux-driven reorder, or `nil`
    /// when no reorder is needed or safe. Non-mirror tabs keep their exact slots,
    /// allowing one session's transferred windows to reorder inside a mixed
    /// destination workspace.
    ///
    /// - Parameters:
    ///   - current: the workspace's complete current tab order (panel ids).
    ///   - requested: one session's tmux window order mapped to panel ids.
    /// - Returns: the merged order, or `nil` when the matching subset already
    ///   agrees or `requested` is not a permutation of that subset.
    nonisolated static func mirrorTabReorder(current: [UUID], requested: [UUID]) -> [UUID]? {
        let present = Set(current)
        let desired = requested.filter { present.contains($0) }
        let desiredSet = Set(desired)
        let currentSubset = current.filter { desiredSet.contains($0) }
        guard desired.count == desiredSet.count,
              currentSubset.count == desired.count,
              Set(currentSubset) == desiredSet,
              desired != currentSubset
        else {
            return nil
        }

        var iterator = desired.makeIterator()
        return current.map { desiredSet.contains($0) ? (iterator.next() ?? $0) : $0 }
    }
}
