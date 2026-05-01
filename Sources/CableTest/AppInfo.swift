import Foundation

enum AppInfo {
    static let name = "WhatCable"
    static let version = "0.2.1"
    static let credit = "Darryl Morley"
    static let tagline = "What can this USB-C cable actually do?"
    static let copyright = "© \(Calendar.current.component(.year, from: Date())) \(credit)"
    static let helpURL = URL(string: "https://github.com/darrylmorley/whatcable")!
}
