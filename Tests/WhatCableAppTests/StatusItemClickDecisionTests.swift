import AppKit
import XCTest
@testable import WhatCable

/// `StatusItemClickAction.decide` maps the status item's action event to
/// what it does. Issue #632: an Accessibility press (`AXPress`, VoiceOver's
/// VO-Space) fires the action with no current event, and must open the
/// popover like a plain left click instead of doing nothing.
final class StatusItemClickDecisionTests: XCTestCase {
    func testNoEventIsAPlainPrimaryClick() {
        XCTAssertEqual(
            StatusItemClickAction.decide(eventType: nil, modifierFlags: []),
            .togglePopover(optionHeld: false)
        )
    }

    func testLeftClickTogglesPopover() {
        XCTAssertEqual(
            StatusItemClickAction.decide(eventType: .leftMouseUp, modifierFlags: []),
            .togglePopover(optionHeld: false)
        )
    }

    func testOptionLeftClickRevealsDetails() {
        XCTAssertEqual(
            StatusItemClickAction.decide(eventType: .leftMouseUp, modifierFlags: [.option]),
            .togglePopover(optionHeld: true)
        )
    }

    func testRightClickShowsMenu() {
        XCTAssertEqual(
            StatusItemClickAction.decide(eventType: .rightMouseUp, modifierFlags: []),
            .showMenu
        )
    }

    func testNonMouseEventIsAPlainPrimaryClick() {
        // A non-mouse current event (e.g. a key event still being handled)
        // is not a right click, and its modifiers say nothing about a click.
        XCTAssertEqual(
            StatusItemClickAction.decide(eventType: .keyDown, modifierFlags: [.option]),
            .togglePopover(optionHeld: false)
        )
    }
}
