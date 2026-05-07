// Self-hosted update checker for the OSS build. Compiled out of the
// Mac App Store build (`WHATCABLE_MAS`) because App Review rejects apps
// that ship their own updater — the App Store handles updates itself.
#if !WHATCABLE_MAS
import Foundation
import AppKit
import UserNotifications
import os.log
import WhatCableCore

struct AvailableUpdate: Equatable {
    let version: String
    let url: URL
    let downloadURL: URL?
    let notes: String?
}

/// Polls the GitHub releases API for newer versions of WhatCable.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    private nonisolated static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "updates")
    private static let endpoint = URL(string: "https://api.github.com/repos/darrylmorley/whatcable/releases/latest")!
    private static let pollInterval: TimeInterval = 6 * 60 * 60 // 6h

    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: Date?

    private var timer: Timer?
    private var notifiedVersion: String?
    /// When a manual "Check for Updates" click arrives while a silent
    /// background check is in flight, we set this so the in-flight result
    /// surfaces a visible alert instead of being silently swallowed.
    private var pendingVisibleCheck = false

    private init() {}

    func start() {
        check(silent: true)
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check(silent: true) }
        }
    }

    /// Manually trigger a check. When `silent` is false, surfaces an alert
    /// for the "no update" case so the user gets feedback from the menu item.
    func check(silent: Bool) {
        if isChecking {
            // A check is already in flight. If the user explicitly asked for
            // one, upgrade the in-flight result to non-silent so they still
            // get feedback. Multiple manual clicks coalesce into one alert.
            if !silent { pendingVisibleCheck = true }
            return
        }
        isChecking = true
        pendingVisibleCheck = !silent

        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("WhatCable/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isChecking = false
                self.lastCheck = Date()
                // If a manual click arrived during the in-flight check, this
                // gets surfaced. Reset for the next run.
                let visible = self.pendingVisibleCheck
                self.pendingVisibleCheck = false

                if let error {
                    Self.log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
                    if visible { self.showAlert(title: "Couldn't check for updates", message: error.localizedDescription) }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let urlString = json["html_url"] as? String,
                      let url = URL(string: urlString) else {
                    if visible { self.showAlert(title: "Couldn't check for updates", message: "Unexpected response from GitHub.") }
                    return
                }

                let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let notes = json["body"] as? String
                let downloadURL = (json["assets"] as? [[String: Any]])?
                    .first(where: { ($0["name"] as? String) == "WhatCable.zip" })
                    .flatMap { $0["browser_download_url"] as? String }
                    .flatMap { URL(string: $0) }
                    .flatMap { Self.isTrustedDownloadURL($0) ? $0 : nil }

                if Self.isNewer(remote: remote, current: AppInfo.version) {
                    let update = AvailableUpdate(version: remote, url: url, downloadURL: downloadURL, notes: notes)
                    self.available = update
                    if self.notifiedVersion != remote {
                        self.notifiedVersion = remote
                        self.postNotification(update)
                    }
                    if visible {
                        // Manual "Check for Updates" click: surface a modal
                        // alert so the user gets the same feedback they get
                        // when already up-to-date, with a button to open the
                        // release page directly.
                        self.showUpdateAlert(update)
                    }
                } else {
                    self.available = nil
                    if visible {
                        self.showAlert(
                            title: "You're up to date",
                            message: "WhatCable \(AppInfo.version) is the latest version."
                        )
                    }
                }
            }
        }.resume()
    }

    private func postNotification(_ update: AvailableUpdate) {
        guard AppSettings.shared.notifyOnChanges else { return }
        let content = UNMutableNotificationContent()
        content.title = "WhatCable \(update.version) available"
        content.body = "You're on \(AppInfo.version). Click to view release notes."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "update-\(update.version)", content: content, trigger: nil)
        )
    }

    private func showAlert(title: String, message: String) {
        // LSUIElement apps can't reliably bring a modal alert to the front.
        // Briefly promote to a regular app so the alert takes focus, then
        // restore accessory policy after dismissal.
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.window.level = .floating
        alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)
    }

    private func showUpdateAlert(_ update: AvailableUpdate) {
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "WhatCable \(update.version) is available"
        alert.informativeText = "You're on \(AppInfo.version). Open the release page to read the notes and download."
        alert.window.level = .floating
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)

        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(update.url)
        }
    }

    /// Compare dot-separated numeric versions. Non-numeric segments compare lexically.
    nonisolated static func isNewer(remote: String, current: String) -> Bool {
        AppInfo.isNewer(remote: remote, current: current)
    }

    /// Only accept download URLs from GitHub's release asset CDN.
    nonisolated static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https",
              let host = url.host else { return false }
        let trusted = ["objects.githubusercontent.com", "github.com", "releases.githubusercontent.com"]
        return trusted.contains(host)
    }
}

#endif // !WHATCABLE_MAS

