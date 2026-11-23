import Foundation
import WidgetKit
import os.log
import WhatCableCore

struct PowerTimelineProvider: TimelineProvider {
    private let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "power-widget-timeline"
    )
    typealias Entry = PowerMonitorEntry

    func placeholder(in context: Context) -> PowerMonitorEntry {
        WidgetLanguageSetup.apply("power placeholder")
        return PowerMonitorEntry.placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (PowerMonitorEntry) -> Void) {
        WidgetLanguageSetup.apply("power snapshot")
        if context.isPreview {
            completion(.placeholder)
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PowerMonitorEntry>) -> Void) {
        // Strings follow the language picked in WhatCable, not the Mac's.
        WidgetLanguageSetup.apply("power timeline")
        let entry = currentEntry()
        // Always request a refresh in ~60s. The OS may honour this later or
        // earlier depending on budget. Power data only comes from the main app's
        // Pro plugin contributors, so the timeline relies on the cached snapshot.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func currentEntry() -> PowerMonitorEntry {
        guard let url = WidgetSnapshot.sharedFileURL else {
            return PowerMonitorEntry(date: Date(), snapshot: nil)
        }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return PowerMonitorEntry(date: Date(), snapshot: nil)
        }
        // No staleness blanking: an old snapshot is shown as-is.
        // The "as of" caption tells the user when the data was captured.
        return PowerMonitorEntry(date: snapshot.timestamp, snapshot: snapshot)
    }
}

struct PowerMonitorEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static let placeholder = PowerMonitorEntry(
        date: Date(),
        snapshot: WidgetSnapshot(
            ports: [],
            powerState: .init(
                batteryPercent: 78,
                isCharging: true,
                fullyCharged: false,
                isDesktopMac: false,
                adapterWatts: 96,
                adapterDescription: "pd charger"
            )
        )
    )
}
