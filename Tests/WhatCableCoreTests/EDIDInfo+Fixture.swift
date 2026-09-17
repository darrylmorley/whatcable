import Foundation
@testable import WhatCableCore

/// Test-only convenience for building an `EDIDInfo` without a raw byte blob.
extension EDIDInfo {
    static func fixture(
        name: String? = nil,
        version: (Int, Int) = (1, 4),
        preferred: EDIDMode,
        modes: [EDIDMode] = [],
        rangeLimits: RangeLimits? = nil,
        continuousFrequency: Bool? = false,
        tiledTopology: TiledTopology? = nil
    ) -> EDIDInfo {
        // `preferred` is prepended only when absent, so `topMode` and
        // `preferredMode` always agree with the caller's own list.
        var allModes = modes
        if !allModes.contains(preferred) {
            allModes.insert(preferred, at: 0)
        }
        return EDIDInfo(
            monitorName: name,
            versionMajor: version.0,
            versionMinor: version.1,
            continuousFrequency: continuousFrequency,
            preferredMode: preferred,
            modes: allModes,
            undecodedStandardTimings: [],
            rangeLimits: rangeLimits,
            displayIDRangeLimits: nil,
            dynamicRangeLimits: nil,
            blocks: [],
            declaredExtensionCount: 0,
            tiledTopology: tiledTopology,
            ctaPreferredVICs: []
        )
    }

    static func mode(
        _ width: Int, _ height: Int, hTotal: Int, vTotal: Int, pixelClockHz: Int,
        interlaced: Bool = false, source: EDIDMode.Source = .detailedTiming(block: 0, index: 0)
    ) -> EDIDMode {
        EDIDMode(
            width: width, height: height, hTotal: hTotal, vTotal: vTotal,
            pixelClockHz: pixelClockHz, interlaced: interlaced, source: source
        )
    }
}
