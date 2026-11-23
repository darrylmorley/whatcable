import SwiftUI
import WidgetKit
import AppIntents
import WhatCableCore

@main
struct WhatCableWidgetBundle: WidgetBundle {
    /// The widget gallery's name and description below are built when the
    /// extension starts, before any provider runs, so the app's chosen
    /// language is applied here too.
    init() {
        WidgetLanguageSetup.apply("bundle init")
    }

    var body: some Widget {
        CableStatusWidget()
        PowerMonitorWidget()
    }
}

struct CableStatusWidget: Widget {
    let kind = "uk.whatcable.whatcable.widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CableWidgetIntent.self, provider: CableTimelineProvider()) { entry in
            CableWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text(String(localized: "Cable Status", bundle: _coreLocalizedBundle)))
        .description(Text(String(localized: "See what your USB-C cables can do at a glance.", bundle: _coreLocalizedBundle)))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
