import Foundation
import Testing
@testable import WhatCableCore
@testable import WhatCableDarwinBackend

// MARK: - AppleUVDMWatcher.makeAccessoryIdentity parse tests
//
// Fixtures are literal dictionaries rather than a corpus replay: the first
// carries the real `IOPortTransportProtocolAppleUVDM` node from
// research/customer-probes/a18pro_macos26.5.2/17_deep_property_dump.json,
// values transcribed exactly.

@Suite("AppleUVDMWatcher.makeAccessoryIdentity")
struct AppleUVDMWatcherMakeAccessoryIdentityTests {

    private func read(_ dict: [String: Any]) -> (String) -> Any? {
        { dict[$0] }
    }

    private let realNode: [String: Any] = [
        "ParentPortType": NSNumber(value: 2),
        "ParentPortNumber": NSNumber(value: 2),
        "ParentBuiltInPortType": NSNumber(value: 2),
        "ParentBuiltInPortNumber": NSNumber(value: 2),
        "Manufacturer": "0x05AC",
        "Vendor": "Apple Inc.",
        "Product": "0",
        "User String": "20W USB-C Power Adapter",
        "Model": "0x7010",
        "Serial Number": "C3D2103AQ67PDYNAM",
        "Hardware Version": "1.0",
        "Number of VDOs": NSNumber(value: 9),
        "Number of Data EPs": NSNumber(value: 2),
    ]

    @Test func realNodePortKeyAndFieldsAreByteIdentical() {
        let identity = AppleUVDMWatcher.makeAccessoryIdentity(
            entryID: 1, read: read(realNode), hpmControllerUUID: nil)

        #expect(identity != nil)
        #expect(identity?.portKey == "2/2")
        #expect(identity?.manufacturer == "0x05AC")
        #expect(identity?.vendor == "Apple Inc.")
        #expect(identity?.product == "0")
        #expect(identity?.userString == "20W USB-C Power Adapter")
        #expect(identity?.model == "0x7010")
        #expect(identity?.serialNumber == "C3D2103AQ67PDYNAM")
        #expect(identity?.hardwareVersion == "1.0")
    }

    @Test func realNodeDisplayNameIsUserString() {
        let identity = AppleUVDMWatcher.makeAccessoryIdentity(
            entryID: 1, read: read(realNode), hpmControllerUUID: nil)
        #expect(identity?.displayName == "20W USB-C Power Adapter")
    }

    @Test func realNodeSerialNumberIsKeptNotDropped() {
        let identity = AppleUVDMWatcher.makeAccessoryIdentity(
            entryID: 1, read: read(realNode), hpmControllerUUID: nil)
        #expect(identity?.serialNumber == "C3D2103AQ67PDYNAM")
    }

    /// A node carrying only `Product` and a `Serial Number` with an embedded
    /// control byte: the serial is stored exactly as read (never touched by
    /// `displayName`'s validation), while `Product` still has to pass the
    /// displayable check on its own to surface as a name.
    @Test func productOnlyNodeWithControlByteInSerialStillProducesIdentity() {
        let dict: [String: Any] = [
            "Product": "iPhone",
            "Serial Number": "ABC\u{0007}DEF",
        ]
        let identity = AppleUVDMWatcher.makeAccessoryIdentity(
            entryID: 2, read: read(dict), hpmControllerUUID: nil)

        #expect(identity != nil)
        #expect(identity?.displayName == "iPhone")
        #expect(identity?.serialNumber == "ABC\u{0007}DEF")
    }

    /// None of the four identity keys (Manufacturer, Vendor, Product, User
    /// String) present: the node carries no identity, so the presence gate
    /// returns nil rather than an all-nil struct.
    @Test func nodeWithNoneOfTheFourIdentityKeysReturnsNil() {
        let dict: [String: Any] = [
            "Model": "0x7010",
            "Serial Number": "SOMESERIAL",
        ]
        let identity = AppleUVDMWatcher.makeAccessoryIdentity(
            entryID: 3, read: read(dict), hpmControllerUUID: nil)
        #expect(identity == nil)
    }
}
