public struct CLICommand: Sendable {
    public let flagNames: Set<String>
    public let helpLines: String
    public let matches: @Sendable ([String]) -> Bool
    public let run: @MainActor @Sendable ([String]) async -> Void

    public init(
        flagNames: Set<String>,
        helpLines: String,
        matches: @Sendable @escaping ([String]) -> Bool,
        run: @MainActor @Sendable @escaping ([String]) async -> Void
    ) {
        self.flagNames = flagNames
        self.helpLines = helpLines
        self.matches = matches
        self.run = run
    }
}
