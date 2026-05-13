public struct PortCardContext: Sendable {
    public let portKey: String?
    public let portNumber: Int?
    public let serviceName: String
    public let portTypeDescription: String?

    public init(portKey: String?, portNumber: Int?, serviceName: String, portTypeDescription: String?) {
        self.portKey = portKey
        self.portNumber = portNumber
        self.serviceName = serviceName
        self.portTypeDescription = portTypeDescription
    }
}
