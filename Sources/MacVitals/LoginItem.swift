import Foundation
import ServiceManagement

/// Launch at Login, through the app registering itself as a login item. No helper
/// and no privileged step: `SMAppService.mainApp` adds the app to the user's Login
/// Items, macOS shows its own notice, and the user can revoke it in System
/// Settings. Off until the user turns it on, and the app never starts itself
/// without that choice.
@MainActor
enum LoginItem {
    /// Whether the app is currently set to launch at login.
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turn Launch at Login on or off. Returns whether the request went through,
    /// so the caller can tell when the system refused (an unsigned dev build can,
    /// until the app is notarized). Guards the status so a redundant call is a
    /// no-op rather than an error.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            switch (on, SMAppService.mainApp.status) {
            case (true, .enabled): break
            case (true, _): try SMAppService.mainApp.register()
            case (false, .enabled), (false, .requiresApproval): try SMAppService.mainApp.unregister()
            case (false, _): break
            }
            return true
        } catch {
            NSLog("LoginItem: could not \(on ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            return false
        }
    }
}
