import XCTest
import Combine
@testable import WhatCable

final class RefreshSignalTests: XCTestCase {
    private var signal: RefreshSignal!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        signal = RefreshSignal()
        cancellables = []
    }

    func testInitialState() {
        XCTAssertEqual(signal.tick, 0)
        XCTAssertFalse(signal.optionHeld)
        XCTAssertFalse(signal.showSettings)
    }

    func testBumpIncrementsTick() {
        signal.bump()
        XCTAssertEqual(signal.tick, 1)
        signal.bump()
        XCTAssertEqual(signal.tick, 2)
    }

    func testShowSettingsToggle() {
        var observedValue = false
        let expectation = expectation(description: "showSettings published")

        signal.$showSettings
            .dropFirst()
            .sink { value in
                observedValue = value
                expectation.fulfill()
            }
            .store(in: &cancellables)

        signal.showSettings = true
        XCTAssertTrue(signal.showSettings)

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(observedValue)
    }

    func testOptionHeldToggle() {
        signal.optionHeld = true
        XCTAssertTrue(signal.optionHeld)
        signal.optionHeld = false
        XCTAssertFalse(signal.optionHeld)
    }
}
