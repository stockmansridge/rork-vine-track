import SwiftUI

/// Gates content behind a permission check from `AccessControl`.
///
/// Use this wrapper everywhere instead of one-off `if accessControl?.xxx ?? true` checks,
/// so role enforcement is consistent and fail-closed (no access by default).
///
/// ```swift
/// PermissionGate(\.canViewFinancials) {
///     Text(total, format: .currency(code: "USD"))
/// }
/// ```
struct PermissionGate<Content: View, Fallback: View>: View {
    @Environment(\.accessControl) private var accessControl

    let check: (AccessControl) -> Bool
    let content: () -> Content
    let fallback: () -> Fallback

    init(
        _ keyPath: KeyPath<AccessControl, Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.check = { $0[keyPath: keyPath] }
        self.content = content
        self.fallback = fallback
    }

    init(
        check: @escaping (AccessControl) -> Bool,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.check = check
        self.content = content
        self.fallback = fallback
    }

    var body: some View {
        if let ac = accessControl, check(ac) {
            content()
        } else {
            fallback()
        }
    }
}

extension PermissionGate where Fallback == EmptyView {
    init(
        _ keyPath: KeyPath<AccessControl, Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(keyPath, content: content, fallback: { EmptyView() })
    }

    init(
        check: @escaping (AccessControl) -> Bool,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(check: check, content: content, fallback: { EmptyView() })
    }
}

extension AccessControl {
    /// Fail-closed permission check. If `accessControl` is nil, returns false.
    static func isAllowed(_ ac: AccessControl?, _ keyPath: KeyPath<AccessControl, Bool>) -> Bool {
        guard let ac else { return false }
        return ac[keyPath: keyPath]
    }
}

/// Convenience view-modifier alternative:
/// `.visibleIf(\.canViewFinancials)`
extension View {
    @ViewBuilder
    func visibleIf(_ keyPath: KeyPath<AccessControl, Bool>) -> some View {
        PermissionGate(keyPath) { self }
    }
}
