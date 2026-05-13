import Foundation

/// Per-port federated identity from the AppleSmartBattery's FedDetails array.
/// Each entry describes the PD partner connected to a physical port, using
/// data the battery controller collects independently of the HPM/TC services.
/// Available on laptops only (the array is absent or all-zeros on desktops).
public struct FederatedIdentity: Hashable {
    /// 1-based port index (offset in the FedDetails array + 1).
    public let portIndex: Int
    public let vendorID: Int
    public let productID: Int
    public let pdSpecRevision: Int
    /// 0 = sink, 1 = source.
    public let powerRole: Int
    public let dualRolePower: Bool
    public let externalConnected: Bool

    public init(
        portIndex: Int,
        vendorID: Int,
        productID: Int,
        pdSpecRevision: Int,
        powerRole: Int,
        dualRolePower: Bool,
        externalConnected: Bool
    ) {
        self.portIndex = portIndex
        self.vendorID = vendorID
        self.productID = productID
        self.pdSpecRevision = pdSpecRevision
        self.powerRole = powerRole
        self.dualRolePower = dualRolePower
        self.externalConnected = externalConnected
    }

    /// True when this entry represents an actual connected device (VID != 0).
    public var hasDevice: Bool { vendorID != 0 }
}
