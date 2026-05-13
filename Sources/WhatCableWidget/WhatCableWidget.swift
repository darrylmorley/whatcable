import SwiftUI
import WidgetKit
import WhatCableCore

/// Entry point for the WhatCable desktop widget. Provides three size
/// families: small (single most interesting port), medium (all ports
/// compact), and large (all ports with detail).
@main
struct WhatCableWidgetBundle: WidgetBundle {
    var body: some Widget {
        CableStatusWidget()
    }
}

struct CableStatusWidget: Widget {
    let kind = "uk.whatcable.whatcable.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CableTimelineProvider()) { entry in
            CableWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cable Status")
        .description("See what your USB-C cables can do at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
