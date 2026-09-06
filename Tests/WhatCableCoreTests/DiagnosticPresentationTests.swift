import Foundation
import Testing
@testable import WhatCableCore

#if DEBUG
/// Acceptance criteria for the internal diagnostic surface, tested at the
/// presentation layer (what the view will display) rather than by pixel snapshot.
/// Everything here proves the render is faithful to the contract, never
/// invents certainty, and fails visibly on malformed input.
struct DiagnosticPresentationTests {

    private func fixtures() -> [DiagnosticContract] { DiagnosticFixtures.all() }

    // MARK: on-disk fixtures
    //
    // The fixtures live under the mirror-excluded `research/` tree, so they are
    // absent on the public clone and on a fresh checkout. These tests gate on the
    // `research/` tree existing (`DiagnosticFixtures.researchTreePresent`), NOT on
    // the fixtures subfolder: on the private tree they run and must pass exactly,
    // so a missing or broken fixture fails loudly (renaming the subfolder makes
    // `load()` report a failure, which `allSevenLoad` catches); only a genuinely
    // absent research tree skips them.

    /// Guards the `#filePath`-based locator against drift. Runs on every tree
    /// (public and private both carry `Package.swift`), so if this file is moved
    /// and the walk can no longer find its package, this fails loudly rather than
    /// silently disabling every fixture test above.
    @Test("The fixtures locator resolves a repository root")
    func locatorResolvesRepositoryRoot() {
        #expect(DiagnosticFixtures.repositoryRoot != nil)
    }

    @Test("All seven exported fixtures load with no failures",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func allSevenLoad() {
        let result = DiagnosticFixtures.load()
        #expect(result.contracts.count == 7)
        #expect(result.failures.isEmpty)
    }

    @Test("Every bundled fixture is internally valid",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func bundledFixturesAreValid() {
        for c in fixtures() {
            #expect(DiagnosticPresentation(c).isValid, "\(c.endpoint) should be valid")
        }
    }

    @Test("Confidence is the contract's value as a percentage, attached to its claim",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func confidenceMatchesContract() throws {
        let pssd = try #require(fixtures().first { $0.endpoint.contains("PSSD T7") })
        #expect(pssd.diagnosis.confidence == 0.87)
        #expect(DiagnosticPresentation(pssd).confidenceLabel
                == "Confidence the endpoint is not the limit: 87%")
    }

    @Test("A match renders its conclusion and outcome; a rejection renders neither",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func matchVsRejectionOutcome() throws {
        let matches = fixtures().filter { $0.diagnosis.matched }
        let rejects = fixtures().filter { !$0.diagnosis.matched }
        #expect(matches.count == 5 && rejects.count == 2)
        for c in matches {
            let p = DiagnosticPresentation(c)
            #expect(p.outcomeTitle == "Connection-path restriction detected")
            #expect(p.explanation == c.diagnosis.conclusion)
            #expect(p.confidenceLabel != nil)
        }
        for c in rejects {
            let p = DiagnosticPresentation(c)
            #expect(p.outcomeTitle == "No diagnosis produced")
            #expect(p.confidenceLabel == nil)
            #expect(p.isRejected)
        }
    }

    @Test("A rejection surfaces the supplied failed precondition and explanation",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func rejectionExplainsPrecondition() throws {
        let charging = try #require(fixtures().first {
            !$0.diagnosis.matched && ($0.diagnosis.rejection?.explanation.contains("demand-driven") ?? false)
        })
        let p = DiagnosticPresentation(charging)
        #expect(p.rejection?.precondition == "trained_observation")
        #expect(p.explanation.contains("demand-driven"))
    }

    @Test("Provenance layers are preserved in order with faithful labels",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func provenanceFaithful() throws {
        let match = try #require(fixtures().first { $0.diagnosis.matched })
        let rows = DiagnosticPresentation(match).provenanceRows
        #expect(rows.map(\.label) == ["Measured on this Mac", "Demonstrated in the corpus", "Inferred"])
        #expect(rows.allSatisfy { $0.known })
    }

    @Test("Suspect state comes from the authoritative status; unknown is never localised",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func suspectStateFromStatus() {
        for c in fixtures() {
            for row in DiagnosticPresentation(c).suspects where row.state == .unknown {
                #expect(row.capabilityLine == nil)
            }
        }
        let anyLocalised = fixtures().flatMap { DiagnosticPresentation($0).suspects }
            .contains { $0.state == .localisedDrop }
        #expect(anyLocalised == false)     // no per-hop data in the real fixtures
    }

    @Test("The synthetic fixture is the only one, and is unmistakably labelled",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func syntheticIsLabelled() throws {
        let synthetic = try #require(fixtures().first { $0.synthetic })
        let p = DiagnosticPresentation(synthetic)
        #expect(p.isSynthetic)
        #expect(p.syntheticBanner?.contains("SYNTHETIC") == true)
        #expect(fixtures().filter { $0.synthetic }.count == 1)
    }

    @Test("Evidence and trace claims are exposed for rendering",
          .enabled(if: DiagnosticFixtures.researchTreePresent))
    func evidenceAndClaimsExposed() throws {
        let match = try #require(fixtures().first { $0.diagnosis.matched })
        let p = DiagnosticPresentation(match)
        #expect(!p.evidence.isEmpty)
        #expect(!p.claims.isEmpty)
    }

    // MARK: adversarial contracts (fail visibly, never partial certainty)

    private func contract(matched: Bool = true, conclusion: String? = "c", confidence: Double? = 0.9,
                          suspects: [DiagnosticContract.Suspect] = [],
                          provenance: [DiagnosticContract.Provenance] = [],
                          claims: [DiagnosticContract.Claim] = [],
                          rejection: DiagnosticContract.Rejection? = nil,
                          schema: Int = DiagnosticContract.supportedSchemaVersion,
                          synthetic: Bool = false) -> DiagnosticContract {
        DiagnosticContract(
            schemaVersion: schema, pattern: "capability-elimination", endpoint: "test",
            synthetic: synthetic,
            diagnosis: .init(matched: matched, conclusion: conclusion, confidence: confidence,
                             eliminated: [], suspects: suspects, evidence: [],
                             provenance: provenance,
                             trace: .init(preconditions: [], claims: claims),
                             rejection: rejection))
    }

    @Test("Unsupported schema version is invalid")
    func unsupportedSchemaVersionInvalid() {
        #expect(!DiagnosticPresentation(contract(schema: 999)).isValid)
    }

    @Test("Matched-without-conclusion or bad confidence is invalid")
    func matchedInconsistenciesInvalid() {
        #expect(!DiagnosticPresentation(contract(conclusion: nil)).isValid)
        #expect(!DiagnosticPresentation(contract(confidence: nil)).isValid)
        #expect(!DiagnosticPresentation(contract(confidence: 1.5)).isValid)
        #expect(!DiagnosticPresentation(contract(confidence: .nan)).isValid)
    }

    @Test("Rejected-without-rejection is invalid")
    func rejectedWithoutRejectionInvalid() {
        #expect(!DiagnosticPresentation(contract(matched: false, conclusion: nil,
                                                 confidence: nil, rejection: nil)).isValid)
    }

    @Test("A drop claimed without capabilities is invalid and never renders localised")
    func dropWithoutCapabilitiesInvalidAndSafe() {
        let bad = DiagnosticContract.Suspect(name: "hub", visibility: "observed",
            capabilityIn: nil, capabilityOut: nil, status: "localised_drop", localisedDrop: true)
        let p = DiagnosticPresentation(contract(suspects: [bad]))
        #expect(!p.isValid)                                  // flagged
        #expect(p.suspects[0].state == .unknown)             // and rendered safely, not an empty drop
        #expect(p.suspects[0].capabilityLine == nil)
    }

    @Test("Status and localisedDrop disagreement is invalid")
    func statusFlagDisagreementInvalid() {
        let bad = DiagnosticContract.Suspect(name: "x", visibility: "observed",
            capabilityIn: 4, capabilityOut: 2, status: "unknown", localisedDrop: true)
        #expect(!DiagnosticPresentation(contract(suspects: [bad])).isValid)
    }

    @Test("Unrecognised suspect status is invalid")
    func unknownStatusInvalid() {
        let bad = DiagnosticContract.Suspect(name: "x", visibility: "observed",
            capabilityIn: nil, capabilityOut: nil, status: "future_kind", localisedDrop: false)
        #expect(!DiagnosticPresentation(contract(suspects: [bad])).isValid)
    }

    @Test("Unknown provenance layer is invalid but never dropped")
    func unknownProvenanceLayerInvalidButKept() {
        let p = DiagnosticPresentation(contract(
            provenance: [.init(layer: "future_layer", detail: "d")]))
        #expect(!p.isValid)
        #expect(p.provenanceRows.contains { !$0.known && $0.detail == "d" })   // kept, marked
    }

    @Test("A non-finite claim confidence is invalid and never traps the formatter")
    func claimConfidenceGuarded() {
        let nanClaim = DiagnosticContract.Claim(claim: "x", support: [], confidence: .nan)
        let hugeClaim = DiagnosticContract.Claim(claim: "y", support: [], confidence: 42)
        #expect(!DiagnosticPresentation(contract(claims: [nanClaim])).isValid)
        #expect(!DiagnosticPresentation(contract(claims: [hugeClaim])).isValid)
        // the formatter is safe regardless (clamped, never Int(NaN))
        #expect(DiagnosticPresentation(contract(claims: [nanClaim])).claims[0].confidencePercent == 0)
        #expect(DiagnosticPresentation(contract(claims: [hugeClaim])).claims[0].confidencePercent == 100)
    }

    @Test("A well-formed localised drop renders only when both capabilities are present")
    func localisationOnlyWhenSupplied() {
        let drop = DiagnosticContract.Suspect(name: "USB hub", visibility: "observed",
            capabilityIn: 10, capabilityOut: 5, status: "localised_drop", localisedDrop: true)
        let p = DiagnosticPresentation(contract(suspects: [drop]))
        #expect(p.isValid)
        #expect(p.suspects[0].state == .localisedDrop)
        #expect(p.suspects[0].capabilityLine == "10 to 5")
    }
}
#endif
