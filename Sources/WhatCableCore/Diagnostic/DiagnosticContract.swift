import Foundation

#if DEBUG
/// The diagnostic contract: a faithful decode of the JSON that a separate
/// diagnostic engine emits for this app to render.
///
/// WhatCable renders this. It never recomputes confidence, reclassifies a hop, or
/// re-derives provenance. If a view needs meaning that is not present here, the
/// fix is to refine the contract upstream, not to infer it in Swift.
///
/// Decoded with `.convertFromSnakeCase`, so `schema_version` becomes
/// `schemaVersion`, `capability_in` becomes `capabilityIn`, and so on.
public struct DiagnosticContract: Codable, Sendable, Equatable {
    /// The contract shape this app understands. A contract with any other version
    /// is refused, not partially interpreted (see `DiagnosticFixtures`).
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let pattern: String
    public let endpoint: String
    public let synthetic: Bool
    public let diagnosis: Diagnosis

    public struct Diagnosis: Codable, Sendable, Equatable {
        public let matched: Bool
        public let conclusion: String?
        public let confidence: Double?
        public let eliminated: [Eliminated]
        public let suspects: [Suspect]
        public let evidence: [Evidence]
        public let provenance: [Provenance]
        public let trace: Trace
        public let rejection: Rejection?
    }

    public struct Eliminated: Codable, Sendable, Equatable {
        public let name: String
        public let reason: String
    }

    /// A path hop the reasoning could not rule out. `status` is authoritative:
    /// `"unknown"` (capability not known) or `"localised_drop"` (a measured drop).
    /// A preserved hop is never here, it appears under `eliminated`.
    public struct Suspect: Codable, Sendable, Equatable {
        public let name: String
        public let visibility: String
        public let capabilityIn: Double?
        public let capabilityOut: Double?
        public let status: String
        public let localisedDrop: Bool
    }

    public struct Evidence: Codable, Sendable, Equatable {
        public let kind: String
        public let detail: String
    }

    public struct Provenance: Codable, Sendable, Equatable {
        public let layer: String        // "measured" | "demonstrated" | "inferred"
        public let detail: String
    }

    public struct Trace: Codable, Sendable, Equatable {
        public let preconditions: [Precondition]
        public let claims: [Claim]
    }

    public struct Precondition: Codable, Sendable, Equatable {
        public let name: String
        public let passed: Bool
        public let evidence: String
    }

    public struct Claim: Codable, Sendable, Equatable {
        public let claim: String
        public let support: [String]
        public let confidence: Double
    }

    public struct Rejection: Codable, Sendable, Equatable {
        public let precondition: String
        public let explanation: String
    }
}
#endif
