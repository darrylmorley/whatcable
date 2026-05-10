import Foundation
import WidgetKit
import os.log
import WhatCableCore

/// Reads the latest WidgetSnapshot from the macOS team-prefixed App Group
/// shared container and builds a single-entry timeline. The main app pushes
/// reloads via WidgetCenter.reloadAllTimelines() whenever cable state changes.
///
/// The widget stays data-only instead of probing IOKit itself. That keeps the
/// sandboxed extension small and avoids duplicating the live watcher graph;
/// the only IPC is this JSON file in the shared container authorized by the
/// `M4RUJ7W6MP.uk.whatcable.whatcable` entitlement.
///
/// A fallback 60-second refresh policy catches the case where the main
/// app quits or crashes and stops pushing reloads. If the snapshot is
/// older than 5 minutes, we treat it as stale and show the empty state.
struct CableTimelineProvider: TimelineProvider {
    /// Snapshots older than this are treated as stale (main app not running).
    private let staleAfter: TimeInterval = 5 * 60
    private let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "widget-timeline"
    )
    typealias Entry = CableWidgetEntry

    /// Shown briefly while the widget loads for the first time.
    func placeholder(in context: Context) -> CableWidgetEntry {
        CableWidgetEntry.placeholder(language: WhatCableLanguage.persistedForWidget())
    }

    /// Quick snapshot for the widget gallery preview.
    func getSnapshot(in context: Context, completion: @escaping (CableWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder(language: WhatCableLanguage.persistedForWidget()))
        } else {
            completion(currentEntry())
        }
    }

    /// The real timeline. Primary updates come from the main app calling
    /// reloadAllTimelines(). The 60-second fallback catches the case where
    /// the app stops running, so stale data eventually falls to empty state.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CableWidgetEntry>) -> Void) {
        let entry = currentEntry()
        let timeline = Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(60))
        )
        completion(timeline)
    }

    // MARK: - Read from App Group

    private func currentEntry() -> CableWidgetEntry {
        guard let url = WidgetSnapshot.sharedFileURL else {
            log.error("Failed to resolve App Group container URL for \(WidgetSnapshot.appGroupID, privacy: .public)")
            return CableWidgetEntry(date: Date(), snapshot: nil)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("Failed to read widget snapshot: \(error.localizedDescription, privacy: .public)")
            return CableWidgetEntry(date: Date(), snapshot: nil)
        }

        let snapshot: WidgetSnapshot
        do {
            snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        } catch {
            log.error("Failed to decode widget snapshot (\(data.count) bytes): \(error.localizedDescription, privacy: .public)")
            return CableWidgetEntry(date: Date(), snapshot: nil)
        }

        let age = Date().timeIntervalSince(snapshot.timestamp)
        guard age <= staleAfter else {
            log.error("Widget snapshot is stale (\(Int(age))s old), showing empty state")
            return CableWidgetEntry(date: Date(), snapshot: nil)
        }

        return CableWidgetEntry(date: snapshot.timestamp, snapshot: snapshot)
    }
}

/// Timeline entry wrapping a WidgetSnapshot. A nil snapshot means the
/// main app hasn't written any data yet (first launch, or app not running).
struct CableWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?

    static func placeholder(language: WhatCableLanguage = WhatCableLanguage.persistedForWidget()) -> CableWidgetEntry {
        func tr(_ key: String.LocalizationValue) -> String {
            LocalizedCopy.string(key, language: language)
        }
        let capabilities = [
            tr("high-speed data"),
            tr("video"),
            tr("smart cable")
        ].joined(separator: language == .simplifiedChinese ? "、" : ", ")
        let linkSpeed = tr("Up to \(40) Gb/s \("x 2")")

        return CableWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                ports: [
                    .init(
                        id: 1,
                        portName: "USB-C Port 1",
                        status: .thunderboltCable,
                        headline: tr("Thunderbolt / USB4"),
                        subtitle: tr("Supports \(capabilities)."),
                        topBullet: tr("Linked at \(linkSpeed)"),
                        iconName: "bolt.horizontal.fill",
                        deviceCount: 2
                    ),
                    .init(
                        id: 2,
                        portName: "USB-C Port 2",
                        status: .charging,
                        headline: tr("Charging · \(96)W charger"),
                        subtitle: tr("Power is flowing. No data connection."),
                        topBullet: tr("Charger advertises up to \(96)W"),
                        iconName: "bolt.fill",
                        deviceCount: 0
                    ),
                    .init(
                        id: 3,
                        portName: "USB-C Port 3",
                        status: .empty,
                        headline: tr("Nothing connected"),
                        subtitle: tr("Plug a cable in to see what it can do."),
                        topBullet: nil,
                        iconName: "powerplug",
                        deviceCount: 0
                    ),
                ],
                languageCode: language.code
            )
        )
    }
}
