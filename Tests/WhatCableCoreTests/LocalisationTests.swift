import XCTest
import Foundation
@testable import WhatCableCore

final class LocalisationTests: XCTestCase {

    func testCoreStringCatalogIsValidJSON() throws {
        let bundle = Bundle.module
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: url)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 50, "Core catalog should have many string keys")
        XCTAssertEqual(catalog?["sourceLanguage"] as? String, "en")
    }

    func testEnglishSourceStringsResolveToThemselves() {
        let bundle = Bundle.module
        let sample = String(localized: "Nothing connected", bundle: bundle)
        XCTAssertEqual(sample, "Nothing connected")
    }

    func testInterpolatedStringsResolve() {
        let bundle = Bundle.module
        let result = String(localized: "Cable speed: \("USB 3.2 Gen 2 (10 Gbps)")", bundle: bundle)
        XCTAssertEqual(result, "Cable speed: USB 3.2 Gen 2 (10 Gbps)")
    }

    func testSupportedLanguagesHaveStableCodesAndFallback() {
        XCTAssertEqual(WhatCableLanguage.english.code, "en")
        XCTAssertEqual(WhatCableLanguage.simplifiedChinese.code, "zh-Hans")
        XCTAssertEqual(WhatCableLanguage.default, .english)
        XCTAssertEqual(WhatCableLanguage(code: "zh-Hans"), .simplifiedChinese)
        XCTAssertEqual(WhatCableLanguage(code: "bogus"), .english)
    }

    func testChineseCoreStringsResolveWithExplicitLanguage() {
        let summary = PortSummary(
            port: USBCPort(
                id: 1,
                serviceName: "Port-USB-C@1",
                className: "AppleHPMInterfaceType10",
                portDescription: "Port-USB-C@1",
                portTypeDescription: "USB-C",
                portNumber: 1,
                connectionActive: false,
                activeCable: nil,
                opticalCable: nil,
                usbActive: nil,
                superSpeedActive: nil,
                usbModeType: nil,
                usbConnectString: nil,
                transportsSupported: [],
                transportsActive: [],
                transportsProvisioned: [],
                plugOrientation: nil,
                plugEventCount: nil,
                connectionCount: nil,
                overcurrentCount: nil,
                pinConfiguration: [:],
                powerCurrentLimits: [],
                firmwareVersion: nil,
                bootFlagsHex: nil,
                rawProperties: [:]
            ),
            language: .simplifiedChinese
        )

        XCTAssertEqual(summary.headline, "未连接任何设备")
        XCTAssertTrue(summary.subtitle.contains("线缆接入"))
    }

    func testChineseTextFormatterUsesLanguageParameter() {
        let output = TextFormatter.render(
            ports: [],
            sources: [],
            identities: [],
            showRaw: false,
            language: .simplifiedChinese
        )

        XCTAssertTrue(output.contains("未找到 USB-C / MagSafe 端口"), output)
    }

    func testJSONFormatterKeepsDisplayTextEnglishByDefault() throws {
        let port = USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: false,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: [],
            transportsActive: [],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )

        let json = try JSONFormatter.render(
            ports: [port],
            sources: [],
            identities: [],
            showRaw: false
        )

        XCTAssertTrue(json.contains(#""headline" : "Nothing connected""#), json)
        XCTAssertFalse(json.contains("未连接任何设备"), json)
    }

    func testCoreCatalogIncludesSimplifiedChinese() throws {
        let bundle = Bundle.module
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "xcstrings"))
        let data = try Data(contentsOf: url)
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        let nothingConnected = try XCTUnwrap(strings["Nothing connected"] as? [String: Any])
        let localizations = try XCTUnwrap(nothingConnected["localizations"] as? [String: Any])
        XCTAssertNotNil(localizations["zh-Hans"])
    }

    func testCoreBundleIncludesExplicitEnglishLookupResources() throws {
        let bundle = Bundle.module
        XCTAssertNotNil(bundle.path(forResource: "en", ofType: "lproj"))
        XCTAssertEqual(LocalizedCopy.string("Nothing connected", language: .english), "Nothing connected")
        XCTAssertEqual(LocalizedCopy.string("Nothing connected", language: .simplifiedChinese), "未连接任何设备")
    }

    func testUSBDeviceSpeedLabelsUseLanguage() {
        let highSpeed = USBDevice(
            id: 1,
            locationID: 0,
            vendorID: 0,
            productID: 0,
            vendorName: nil,
            productName: nil,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: 2,
            busPowerMA: nil,
            currentMA: nil,
            rawProperties: [:]
        )
        let unknownSpeed = USBDevice(
            id: 2,
            locationID: 0,
            vendorID: 0,
            productID: 0,
            vendorName: nil,
            productName: nil,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: nil,
            busPowerMA: nil,
            currentMA: nil,
            rawProperties: [:]
        )

        XCTAssertEqual(highSpeed.speedLabel, "High Speed (480 Mbps)")
        XCTAssertEqual(highSpeed.speedLabel(language: .simplifiedChinese), "高速（480 Mbps）")
        XCTAssertEqual(unknownSpeed.speedLabel(language: .simplifiedChinese), "未知速度")
    }

    func testCoreLocalizedCLIReportWrapperAndLanguageErrors() {
        XCTAssertEqual(
            LocalizedCopy.string("Cable \(1) of \(2)", language: .simplifiedChinese),
            "第 1 / 2 条线缆"
        )
        XCTAssertEqual(
            LocalizedCopy.string("whatcable: unsupported language \("fr"). Use one of: en, zh-Hans\n", language: .simplifiedChinese),
            "whatcable：不支持语言 fr。请使用以下之一：en、zh-Hans\n"
        )
    }

    func testEnglishSourceCopyDocumentIncludesSemanticContext() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let url = root.appendingPathComponent("docs/localization/en-source-copy.md")
        let text = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(text.contains("| `Active` |"), "Document must explain the ambiguous Active label.")
        XCTAssertTrue(text.contains("connection state"))
        XCTAssertTrue(text.contains("Active cable"))
        XCTAssertTrue(text.contains("profiles"))
        XCTAssertTrue(text.contains("smart cable"))
    }
}
