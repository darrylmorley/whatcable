import AppKit

/// What a press on the menu bar status item should do.
///
/// Pure so the mapping is testable without a status bar (issue #632).
enum StatusItemClickAction: Equatable {
    /// Open or close the popover. `optionHeld` reveals the technical
    /// details for this open only (the ⌥-click convention).
    case togglePopover(optionHeld: Bool)
    /// Show the right-click context menu.
    case showMenu

    /// Maps the event behind the button's action to what it should do.
    ///
    /// `eventType` is `NSApp.currentEvent?.type`. It is nil when the action
    /// arrives without a mouse event: an Accessibility press (`AXPress`,
    /// which VoiceOver's VO-Space and menu bar managers send). That, and any
    /// other non-mouse event, is a plain primary click: only a right mouse-up
    /// opens the menu, and only a left mouse-up's ⌥ counts as ⌥-click.
    static func decide(
        eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> StatusItemClickAction {
        switch eventType {
        case .rightMouseUp:
            return .showMenu
        case .leftMouseUp:
            return .togglePopover(optionHeld: modifierFlags.contains(.option))
        default:
            return .togglePopover(optionHeld: false)
        }
    }
}
