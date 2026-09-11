import Foundation
import Testing
@testable import WhatCable

/// Every hub watcher the widget writer READS must also be one it SUBSCRIBES
/// to.
///
/// The writer pushes a fresh App Group cache when a watcher publishes. A
/// watcher it reads but never subscribes to still reaches the snapshot, so
/// nothing looks broken: the value is simply carried by whichever OTHER
/// watcher happens to publish next, or by the 60 second heartbeat
/// (`heartbeatInterval`) when nothing else changes. A change confined to that
/// one watcher is then invisible on the widget for up to a minute.
///
/// That is not hypothetical. `uvdmWatcher` was added to the writer's snapshot
/// build and not to its subscriptions, so an iPhone plugged into a port whose
/// other signals were already settled left the widget showing the link-speed
/// line where the device name belonged.
///
/// Parsed from the writer's own source, so there is one source of truth
/// rather than a hand-maintained list to keep in step. Same technique as
/// `SharedWatcherOwnershipTests`, and for the same reason: a list nobody
/// updates is a tripwire that has stopped watching.
@Suite("Widget writer watcher subscriptions")
struct WidgetDataWriterSubscriptionTests {

    private static let writerSource: String = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableAppTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/WhatCable/Services/WidgetDataWriter.swift")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }()

    /// Watchers the writer reads, from its own `WatcherHub.shared.<name>`
    /// accessor properties (`private var trmWatcher: ... { WatcherHub.shared.trmWatcher }`).
    private static func watchersRead(_ text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("private var "), t.contains("{ WatcherHub.shared.") else { continue }
            guard let range = t.range(of: "{ WatcherHub.shared.") else { continue }
            let rest = t[range.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber }
            if !name.isEmpty { found.insert(String(name)) }
        }
        return found
    }

    /// Watchers the writer subscribes to, from the `WatcherHub.shared.<name>.$publisher`
    /// chains in `start()`.
    private static func watchersSubscribed(_ text: String) -> Set<String> {
        var found: Set<String> = []
        for line in text.split(separator: "\n") {
            guard let range = line.range(of: "WatcherHub.shared.") else { continue }
            let rest = line[range.upperBound...]
            let name = rest.prefix { $0.isLetter || $0.isNumber }
            let after = rest.dropFirst(name.count)
            guard after.hasPrefix(".$") else { continue }
            if !name.isEmpty { found.insert(String(name)) }
        }
        return found
    }

    @Test("Every watcher the writer reads is one it also subscribes to")
    func everyReadWatcherIsSubscribed() {
        #expect(!Self.writerSource.isEmpty, "Could not read WidgetDataWriter.swift; the path has drifted")

        let read = Self.watchersRead(Self.writerSource)
        let subscribed = Self.watchersSubscribed(Self.writerSource)

        #expect(read.count >= 8, "Parsed \(read.count) watcher accessors; the parser has drifted from the file's shape")
        #expect(!subscribed.isEmpty, "Parsed no subscriptions; the parser has drifted from the file's shape")
        #expect(read.subtracting(subscribed).isEmpty,
            "Read but never subscribed, so a change confined to it waits for the heartbeat: \(read.subtracting(subscribed).sorted())")
    }

    @Test("The accessory identity watcher is one of them")
    func accessoryWatcherIsSubscribed() {
        // Named explicitly as well as covered by the sweep above: this is the
        // feature's own delivery path, and the sweep would go quiet if the
        // accessor were ever inlined at the call site.
        #expect(Self.watchersSubscribed(Self.writerSource).contains("uvdmWatcher"),
            "A change confined to the accessory name must push a write, not wait for the heartbeat")
    }
}
