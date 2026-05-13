public struct PluginMenuItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let action: @MainActor @Sendable () -> Void

    public init(id: String, title: String, action: @MainActor @Sendable @escaping () -> Void) {
        self.id = id
        self.title = title
        self.action = action
    }
}
