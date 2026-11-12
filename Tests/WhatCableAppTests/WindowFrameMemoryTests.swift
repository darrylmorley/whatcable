import XCTest
import AppKit
import SwiftUI
@testable import WhatCable

/// Window position and size memory (public issue #522).
final class WindowFrameMemoryTests: XCTestCase {

    private let main = NSRect(x: 0, y: 0, width: 1440, height: 875)
    /// A second display to the left of the main one: negative x.
    private let left = NSRect(x: -1920, y: 0, width: 1920, height: 1055)

    // MARK: - Usable-frame decision

    func testFrameOnConnectedScreenIsUsable() {
        let frame = NSRect(x: 100, y: 100, width: 760, height: 540)
        XCTAssertTrue(WindowFrameMemory.isUsable(frame, on: [main]))
    }

    func testFrameOnSecondaryDisplayAtNegativeXIsUsable() {
        let frame = NSRect(x: -1500, y: 200, width: 760, height: 540)
        XCTAssertTrue(WindowFrameMemory.isUsable(frame, on: [main, left]))
    }

    func testFrameOnUnpluggedDisplayIsNotUsable() {
        // Saved on the left display, which is no longer connected.
        let frame = NSRect(x: -1500, y: 200, width: 760, height: 540)
        XCTAssertFalse(WindowFrameMemory.isUsable(frame, on: [main]))
    }

    func testOnlyASliverOfTitleBarOnScreenIsNotUsable() {
        // 20pt of the window pokes onto the main screen from the left.
        let frame = NSRect(x: -740, y: 200, width: 760, height: 540)
        XCTAssertFalse(WindowFrameMemory.isUsable(frame, on: [main]))
    }

    func testTitleBarAboveTheScreenIsNotUsable() {
        // The body overlaps the screen but the title bar sits above its top,
        // so the window can't be grabbed.
        let frame = NSRect(x: 100, y: 500, width: 760, height: 540)
        XCTAssertFalse(WindowFrameMemory.isUsable(frame, on: [main]))
    }

    func testTitleBarOnScreenWithBodyBelowIsUsable() {
        // A tall window whose bottom hangs below the screen is still reachable.
        let frame = NSRect(x: 100, y: -400, width: 760, height: 1200)
        XCTAssertTrue(WindowFrameMemory.isUsable(frame, on: [main]))
    }

    func testNoScreensIsNotUsable() {
        let frame = NSRect(x: 100, y: 100, width: 760, height: 540)
        XCTAssertFalse(WindowFrameMemory.isUsable(frame, on: []))
    }

    func testEmptyFrameIsNotUsable() {
        XCTAssertFalse(WindowFrameMemory.isUsable(NSRect(x: 100, y: 100, width: 0, height: 0), on: [main]))
    }

    // MARK: - Saved-frame string

    func testSavedWindowFrameReadsFirstFourNumbers() {
        XCTAssertEqual(
            WindowFrameMemory.savedWindowFrame(from: "-1500 200 760 540 -1920 0 1920 1080 "),
            NSRect(x: -1500, y: 200, width: 760, height: 540)
        )
    }

    func testSavedWindowFrameRejectsGarbage() {
        XCTAssertNil(WindowFrameMemory.savedWindowFrame(from: ""))
        XCTAssertNil(WindowFrameMemory.savedWindowFrame(from: "10 20 abc 40"))
    }

    // MARK: - Restore round trip and name release

    @MainActor
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        w.isReleasedWhenClosed = false
        return w
    }

    private func uniqueName() -> String { "uk.whatcable.test.\(UUID().uuidString)" }

    @MainActor
    func testSavedFrameIsRestoredOnNextWindow() {
        let name = uniqueName()
        defer { NSWindow.removeFrame(usingName: name) }
        let screens = [NSRect(x: 0, y: 0, width: 4000, height: 3000)]

        let first = makeWindow()
        XCTAssertTrue(WindowFrameMemory.apply(to: first, autosaveName: name, visibleFrames: screens))
        let moved = NSRect(x: 300, y: 250, width: 900, height: 1100)
        first.setFrame(moved, display: false)
        WindowFrameMemory.release(first)

        let second = makeWindow()
        XCTAssertTrue(WindowFrameMemory.apply(to: second, autosaveName: name, visibleFrames: screens),
                      "the released name should be claimable again")
        XCTAssertEqual(second.frame, moved)
        WindowFrameMemory.release(second)
    }

    @MainActor
    func testUnusableSavedFrameFallsBackToDefault() {
        let name = uniqueName()
        defer { NSWindow.removeFrame(usingName: name) }

        let first = makeWindow()
        WindowFrameMemory.apply(to: first, autosaveName: name, visibleFrames: [main, left])
        first.setFrame(NSRect(x: -1500, y: 200, width: 900, height: 600), display: false)
        WindowFrameMemory.release(first)

        // The left display is gone; the second window keeps its default.
        let second = makeWindow()
        let defaultFrame = NSRect(x: 340, y: 160, width: 760, height: 540)
        second.setFrame(defaultFrame, display: false)
        WindowFrameMemory.apply(to: second, autosaveName: name, visibleFrames: [main])
        XCTAssertEqual(second.frame, defaultFrame)
        WindowFrameMemory.release(second)
    }

    @MainActor
    func testNameHeldByAnOpenWindowIsNotClaimedTwice() {
        let name = uniqueName()
        defer { NSWindow.removeFrame(usingName: name) }

        let first = makeWindow()
        XCTAssertTrue(WindowFrameMemory.apply(to: first, autosaveName: name, visibleFrames: [main]))
        let second = makeWindow()
        XCTAssertFalse(WindowFrameMemory.apply(to: second, autosaveName: name, visibleFrames: [main]))
        WindowFrameMemory.release(first)
    }
}
