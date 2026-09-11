import Foundation
import Testing
@testable import WhatCableCore

/// Tests for `AppleAccessoryIdentity.displayName`: the one place a raw UVDM
/// accessory-identity string becomes a displayable name. Corpus figures
/// backing each case live as comments on the property itself.
@Suite("Apple Accessory Identity")
struct AppleAccessoryIdentityTests {

    @Test("userString wins over product, trimmed of a trailing space")
    func userStringWinsTrimmed() {
        let identity = makeIdentity(userString: "70W USB-C Power Adapter ")
        #expect(identity.displayName == "70W USB-C Power Adapter")
    }

    @Test("product is used when there is no userString")
    func productUsedWithNoUserString() {
        let identity = makeIdentity(product: "iPhone")
        #expect(identity.displayName == "iPhone")
    }

    @Test("product \"0\" gives nil")
    func productZeroGivesNil() {
        let identity = makeIdentity(product: "0")
        #expect(identity.displayName == nil)
    }

    @Test("product \"EV\" gives nil")
    func productEVGivesNil() {
        let identity = makeIdentity(product: "EV")
        #expect(identity.displayName == nil)
    }

    @Test("productID 0x1657 with product \"EV\" gives nil (the engineering-validation accessory)")
    func engineeringValidationAccessoryGivesNil() {
        let identity = makeIdentity(product: "EV", productID: 0x1657, serialNumber: "1234567890")
        #expect(identity.displayName == nil)
    }

    @Test("product \"Vision Pro Battery\" is used as-is")
    func visionProBatteryUsed() {
        let identity = makeIdentity(product: "Vision Pro Battery")
        #expect(identity.displayName == "Vision Pro Battery")
    }

    @Test("control bytes in serialNumber leave displayName unaffected and serialNumber untouched")
    func controlBytesInSerialNumberDoNotAffectDisplayName() {
        let rawSerial = "\u{0C}g~\u{06}\u{2030}af\u{1E}Q\u{01}"
        let identity = makeIdentity(product: "iPhone", serialNumber: rawSerial)
        #expect(identity.displayName == "iPhone")
        #expect(identity.serialNumber == rawSerial)
    }

    @Test("a 200-character userString gives nil")
    func tooLongUserStringGivesNil() {
        let long = String(repeating: "A", count: 200)
        let identity = makeIdentity(userString: long)
        #expect(identity.displayName == nil)
    }

    @Test("a userString containing a control character gives nil")
    func controlCharacterInUserStringGivesNil() {
        let identity = makeIdentity(userString: "Studio Display\u{01}")
        #expect(identity.displayName == nil)
    }

    @Test("empty userString falls through to product")
    func emptyUserStringFallsThroughToProduct() {
        let identity = makeIdentity(userString: "", product: "iPhone")
        #expect(identity.displayName == "iPhone")
    }

    @Test("whitespace-only userString falls through to product")
    func whitespaceOnlyUserStringFallsThroughToProduct() {
        let identity = makeIdentity(userString: "  \n  ", product: "iPad")
        #expect(identity.displayName == "iPad")
    }

    // MARK: - Helpers

    private func makeIdentity(
        userString: String? = nil,
        product: String? = nil,
        productID: Int? = nil,
        serialNumber: String? = nil
    ) -> AppleAccessoryIdentity {
        AppleAccessoryIdentity(
            id: 1,
            portKey: "2/1",
            manufacturer: nil,
            vendor: nil,
            product: product,
            userString: userString,
            model: nil,
            serialNumber: serialNumber,
            hardwareVersion: nil,
            vendorID: nil,
            productID: productID
        )
    }

    @Test("A one-grapheme string of thousands of combining marks is rejected")
    func zalgoSingleGraphemeRejected() {
        // Combining marks fold into one grapheme, so a grapheme count says
        // "1 character" for a string that is kilobytes long and unrenderable.
        // The scalar count is what bounds the payload.
        let zalgo = "a" + String(repeating: "\u{0301}", count: 2000)
        #expect(zalgo.count == 1, "fixture check: this really is one grapheme")
        let identity = makeIdentity(product: zalgo)
        #expect(identity.displayName == nil)
    }

    @Test("U+2028 and U+2029 are rejected even though they are not control characters")
    func unicodeLineSeparatorsRejected() {
        // Zl and Zp, not Cc, so the control-character check never sees them.
        // They are still line breaks and would split the card's bullet.
        #expect(makeIdentity(product: "iPhone\u{2028}15").displayName == nil)
        #expect(makeIdentity(product: "iPhone\u{2029}15").displayName == nil)
    }
}
