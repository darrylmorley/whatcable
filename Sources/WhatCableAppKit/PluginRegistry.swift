import SwiftUI
import AppKit
import Combine

@MainActor
public final class PluginRegistry {
    public static let shared = PluginRegistry()
    private init() {}

    public private(set) var launchHooks: [() async -> Void] = []
    public func register(launchHook: @escaping () async -> Void) {
        launchHooks.append(launchHook)
    }

    public private(set) var menuItems: [MenuPlacement: [PluginMenuItem]] = [:]
    public func register(menuItem: PluginMenuItem, at placement: MenuPlacement) {
        menuItems[placement, default: []].append(menuItem)
    }

    public private(set) var nsMenuItemBuilders: [MenuPlacement: [() -> NSMenuItem]] = [:]
    public func register(nsMenuItemBuilder: @escaping () -> NSMenuItem, at placement: MenuPlacement) {
        nsMenuItemBuilders[placement, default: []].append(nsMenuItemBuilder)
    }

    public private(set) var portCardTrailingBuilders: [(PortCardContext) -> AnyView?] = []
    public func register(portCardTrailing: @escaping (PortCardContext) -> AnyView?) {
        portCardTrailingBuilders.append(portCardTrailing)
    }

    public private(set) var widgetDataContributors: [any WidgetDataContributor] = []
    public func register(widgetDataContributor: any WidgetDataContributor) {
        widgetDataContributors.append(widgetDataContributor)
    }

    public private(set) var cliCommands: [CLICommand] = []
    public func register(cliCommand: CLICommand) {
        cliCommands.append(cliCommand)
    }
}
