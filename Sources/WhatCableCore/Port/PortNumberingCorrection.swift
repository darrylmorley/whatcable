import Foundation

/// Per-model corrections for built-in sockets that macOS names the wrong way
/// round.
///
/// On the M5 Max Mac Studio (`Mac17,14`) macOS swaps two sockets on the
/// Mac's internal USB hub. Hub port 4 is the front USB-C socket next to the
/// card reader, but macOS names it `Port-USB-A@2`. Hub port 2 is the rear
/// USB-A socket next to the power cable, but macOS names it `Port-USB-C@6`.
/// Two owners checked the sockets by hand (public issue #627;
/// format-1 run `397cf7be-d888-4b06-b64d-d5adac29f7ba`, and the older
/// `m5max_macos27.0.1` submission). A third run,
/// `305e3a4f-8992-487e-8d8e-2124b87c2b89`, has the same registry map but no
/// physical check.
///
/// Nothing in the registry contradicts the wrong names: the hub port's
/// `UsbIOPort`, the IOAccessoryManager port node and its transport children
/// all agree with each other. So the fix is a table keyed by exact `hw.model`.
/// Only the two confirmed sockets are listed. `Port-USB-C@5` and
/// `Port-USB-A@1` stay as macOS names them.
///
/// Pure: no IOKit. The Darwin backend resolves the model and applies these
/// functions at each reader that names these sockets.
///
/// If Apple fixes the names: this table would then swap correct names back
/// to wrong ones, so the entry must come out. The tripwire is
/// `PortNumberingCorrectionCorpusTests` ("Mac17,14 still names hub port 2
/// C@6 and hub port 4 A@2"): it fails as soon as an ingested Mac17,14 run
/// shows the internal hub ports carrying different socket names, and says
/// which run and macOS version. Before removing anything, have an owner on
/// that macOS version confirm which physical socket each device is in. To
/// roll back for every macOS version, delete the `"Mac17,14"` entry and the
/// tests that expect the swap (PortNumberingCorrectionTests,
/// PortNumberingCorrectionReplayTests, and T4 in the corpus tests). If only
/// newer macOS versions are fixed, the table needs a macOS version bound
/// instead, which is a design change.
public enum PortNumberingCorrection {

    /// One socket as a `PortType` code and an `@N` number.
    public struct Socket: Hashable, Sendable {
        public let type: Int
        public let number: Int

        public init(type: Int, number: Int) {
            self.type = type
            self.number = number
        }
    }

    /// `PortType` code for USB-C, the code `PortIdentity` and the transport
    /// keys already use.
    static let usbCType = PortIdentity.usbCTypeCode
    /// `PortType` code for USB-A.
    static let usbAType = 0x3

    /// Exact `hw.model` -> socket swaps. Each swap is listed both ways.
    static let table: [String: [Socket: Socket]] = [
        "Mac17,14": [
            Socket(type: usbCType, number: 6): Socket(type: usbAType, number: 2),
            Socket(type: usbAType, number: 2): Socket(type: usbCType, number: 6),
        ],
    ]

    /// The connector names macOS uses in node names and `*TypeDescription`
    /// keys, for the type codes the table uses.
    private static let typeDescriptions: [Int: String] = [
        usbCType: "USB-C",
        usbAType: "USB-A",
    ]

    private static func swaps(for model: String?) -> [Socket: Socket]? {
        guard let model, let swaps = table[model], !swaps.isEmpty else { return nil }
        return swaps
    }

    /// The socket this Mac model really means by `type` / `number`. A nil or
    /// unlisted model returns the input unchanged.
    public static func corrected(type: Int, number: Int, model: String?) -> (type: Int, number: Int) {
        guard let target = swaps(for: model)?[Socket(type: type, number: number)] else {
            return (type, number)
        }
        return (target.type, target.number)
    }

    /// The node name this Mac model really means, e.g. `Port-USB-A@2` ->
    /// `Port-USB-C@6` on `Mac17,14`. Every other name, and every name on any
    /// other model, is returned unchanged.
    public static func corrected(portNodeName: String, model: String?) -> String {
        guard let swaps = swaps(for: model),
              let socket = socket(fromPortNodeName: portNodeName),
              let target = swaps[socket],
              let name = Self.portNodeName(for: target) else {
            return portNodeName
        }
        return name
    }

    /// Runs `body` with a per-key read that returns corrected values for the
    /// keys that name a port, and macOS's own values for every other key.
    ///
    /// Rewritten keys, on `Mac17,14` and only for the two swapped sockets:
    /// - the port node's own `PortType`, `PortNumber`, `PortTypeDescription`,
    ///   `PortDescription` and `Description`;
    /// - a transport node's `ParentPortType` / `ParentPortNumber`, the
    ///   `ParentBuiltIn*` variants, both `*TypeDescription` keys, and
    ///   `TransportDescription`.
    ///
    /// Each type key is judged with its own number key (and each number key
    /// with its own type key), both as macOS reported them. On any other
    /// model `body` receives `read` itself.
    ///
    /// Takes a body closure, not a returned closure, so it works with the
    /// non-escaping `read` parameters the watchers' parse functions take.
    public static func correctingRead<R>(
        _ read: (String) -> Any?,
        model: String?,
        _ body: ((String) -> Any?) throws -> R
    ) rethrows -> R {
        try withoutActuallyEscaping(read) { read in
            guard let swaps = swaps(for: model) else { return try body(read) }
            func target(typeKey: String, numberKey: String) -> Socket? {
                guard let type = (read(typeKey) as? NSNumber)?.intValue,
                      let number = (read(numberKey) as? NSNumber)?.intValue else { return nil }
                return swaps[Socket(type: type, number: number)]
            }
            func correctedName(_ value: Any?) -> Any? {
                guard let name = value as? String else { return value }
                return Self.corrected(portNodeName: name, model: model)
            }
            let correctedRead: (String) -> Any? = { key in
                switch key {
                case "PortType":
                    return target(typeKey: key, numberKey: "PortNumber").map { NSNumber(value: $0.type) } ?? read(key)
                case "PortNumber":
                    return target(typeKey: "PortType", numberKey: key).map { NSNumber(value: $0.number) } ?? read(key)
                case "PortTypeDescription":
                    return target(typeKey: "PortType", numberKey: "PortNumber")
                        .flatMap { typeDescriptions[$0.type] } ?? read(key)
                case "ParentPortType":
                    return target(typeKey: key, numberKey: "ParentPortNumber").map { NSNumber(value: $0.type) } ?? read(key)
                case "ParentPortNumber":
                    return target(typeKey: "ParentPortType", numberKey: key).map { NSNumber(value: $0.number) } ?? read(key)
                case "ParentPortTypeDescription":
                    return target(typeKey: "ParentPortType", numberKey: "ParentPortNumber")
                        .flatMap { typeDescriptions[$0.type] } ?? read(key)
                case "ParentBuiltInPortType":
                    return target(typeKey: key, numberKey: "ParentBuiltInPortNumber")
                        .map { NSNumber(value: $0.type) } ?? read(key)
                case "ParentBuiltInPortNumber":
                    return target(typeKey: "ParentBuiltInPortType", numberKey: key)
                        .map { NSNumber(value: $0.number) } ?? read(key)
                case "ParentBuiltInPortTypeDescription":
                    return target(typeKey: "ParentBuiltInPortType", numberKey: "ParentBuiltInPortNumber")
                        .flatMap { typeDescriptions[$0.type] } ?? read(key)
                case "PortDescription", "Description":
                    return correctedName(read(key))
                case "TransportDescription":
                    // "Port-USB-A@2/USB3": correct the node name before the slash.
                    guard let text = read(key) as? String else { return read(key) }
                    let parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    let head = Self.corrected(portNodeName: String(parts[0]), model: model)
                    return parts.count == 2 ? head + "/" + parts[1] : head
                default:
                    return read(key)
                }
            }
            return try body(correctedRead)
        }
    }

    /// Parses `Port-USB-C@6` into its socket. Nil for any other connector or
    /// shape.
    private static func socket(fromPortNodeName name: String) -> Socket? {
        guard name.hasPrefix("Port-") else { return nil }
        let parts = name.dropFirst("Port-".count).split(separator: "@", maxSplits: 1)
        guard parts.count == 2,
              let number = Int(parts[1]),
              let type = typeDescriptions.first(where: { $0.value == String(parts[0]) })?.key else {
            return nil
        }
        return Socket(type: type, number: number)
    }

    private static func portNodeName(for socket: Socket) -> String? {
        typeDescriptions[socket.type].map { "Port-\($0)@\(socket.number)" }
    }
}
