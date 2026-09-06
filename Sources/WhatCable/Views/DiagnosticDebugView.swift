import SwiftUI
import WhatCableCore

#if DEBUG
/// Internal diagnostic screen. Renders a diagnostic contract, nothing more.
/// It reaches only for `DiagnosticFixtures` and `DiagnosticPresentation`; it does
/// no reasoning, computes no confidence, and classifies no hop. Reachable only via
/// a debug route (see App.swift, `#if DEBUG`).
struct DiagnosticDebugView: View {
    private let loaded = DiagnosticFixtures.load()
    @State private var index = 0

    private var contracts: [DiagnosticContract] { loaded.contracts }

    private var presentation: DiagnosticPresentation? {
        contracts.indices.contains(index) ? DiagnosticPresentation(contracts[index]) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !loaded.failures.isEmpty { loadFailureBanner }
            if contracts.isEmpty {
                Text("No diagnostic fixtures loaded.").padding()
                Spacer()
            } else {
                Picker("Fixture", selection: $index) {
                    ForEach(contracts.indices, id: \.self) { i in
                        Text(contracts[i].endpoint + (contracts[i].synthetic ? "  (synthetic)" : ""))
                            .tag(i)
                    }
                }
                .padding(12)
                Divider()
                ScrollView { content.padding(16) }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }

    private var loadFailureBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Fixtures that failed to load").font(.caption.bold())
            ForEach(loaded.failures, id: \.self) { Text($0).font(.caption) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fixture load failures: \(loaded.failures.joined(separator: "; "))")
    }

    @ViewBuilder private var content: some View {
        if let p = presentation {
            VStack(alignment: .leading, spacing: 18) {
                if let banner = p.syntheticBanner {
                    Text(banner)
                        .font(.caption.bold())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.25))
                        .cornerRadius(6)
                        .accessibilityLabel("Synthetic: a constructed counterexample, not real evidence.")
                }

                if !p.isValid {
                    malformed(p)                    // a bad contract renders as an error, not a diagnosis
                } else {
                    outcome(p)
                    if p.isRejected { rejectionBlock(p) } else { explanation(p) }
                    if !p.ruledOut.isEmpty { ruledOut(p) }
                    if !p.suspects.isEmpty { suspects(p) }
                    if !p.evidence.isEmpty || !p.provenanceRows.isEmpty { evidenceAndProvenance(p) }
                    trace(p)
                }
            }
        }
    }

    // A malformed / inconsistent contract: fail visibly, render no diagnosis content.
    private func malformed(_ p: DiagnosticPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Malformed diagnostic contract").font(.title3.bold()).foregroundStyle(Color.red)
            Text("This contract is internally inconsistent and is not rendered as a diagnosis.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(p.validationIssues, id: \.self) { Text("• \($0)").font(.callout) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Malformed diagnostic contract: \(p.validationIssues.joined(separator: "; "))")
    }

    // 1, Outcome
    private func outcome(_ p: DiagnosticPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.outcomeTitle).font(.title3.bold())
            if let c = p.confidenceLabel { Text(c).foregroundStyle(.secondary) }
        }
    }

    // Rejection, surfaced (not buried in the trace)
    private func rejectionBlock(_ p: DiagnosticPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Diagnosis rejected").font(.headline).foregroundStyle(Color.red)
            Text(p.explanation)
            if let r = p.rejection {
                Text("Failed precondition: \(r.precondition)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Diagnosis rejected. \(p.explanation)")
    }

    // 2, Explanation + honest limit (matched)
    private func explanation(_ p: DiagnosticPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(p.explanation)
            if let limit = p.limitNote {
                Text(limit).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // 3, Ruled out
    private func ruledOut(_ p: DiagnosticPresentation) -> some View {
        section("Ruled out") {
            ForEach(Array(p.ruledOut.enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).bold()
                    Text(e.reason).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    // 4, Remaining suspects
    private func suspects(_ p: DiagnosticPresentation) -> some View {
        section("Remaining suspects") {
            Text("Not ranked by likelihood").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(p.suspects.enumerated()), id: \.offset) { _, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).bold()
                    switch s.state {
                    case .unknown:
                        Text("Visibility: \(s.visibility) · Capability: unknown")
                            .font(.callout).foregroundStyle(.secondary)
                    case .localisedDrop:
                        Text("Measured drop: \(s.capabilityLine ?? "") · likely restriction localised here")
                            .font(.callout).foregroundStyle(Color.orange)
                            .accessibilityLabel("Likely restriction localised here. Measured drop \(s.capabilityLine ?? "").")
                    }
                }
            }
        }
    }

    // 5, Evidence and provenance
    private func evidenceAndProvenance(_ p: DiagnosticPresentation) -> some View {
        section("Evidence and provenance") {
            ForEach(Array(p.provenanceRows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label).font(.caption.bold())
                        .foregroundStyle(row.known ? Color.secondary : Color.red)
                    Text(row.detail).font(.callout)
                }
            }
            if !p.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(Array(p.evidence.enumerated()), id: \.offset) { _, e in
                        Text("(\(e.kind)) \(e.detail)").font(.callout)
                    }
                }
            }
        }
    }

    // 6, Reasoning trace (collapsed)
    private func trace(_ p: DiagnosticPresentation) -> some View {
        DisclosureGroup("Reasoning trace") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(p.preconditions.enumerated()), id: \.offset) { _, c in
                    Text("\(c.passed ? "PASS" : "FAIL")  \(c.name): \(c.evidence)")
                        .font(.callout.monospaced())
                        .foregroundStyle(c.passed ? Color.primary : Color.red)
                        .accessibilityLabel("Precondition \(c.name) \(c.passed ? "passed" : "failed"): \(c.evidence)")
                }
                ForEach(Array(p.claims.enumerated()), id: \.offset) { _, claim in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claim: \(claim.claim) (confidence \(claim.confidencePercent)%)")
                            .font(.callout.monospaced())
                        ForEach(claim.support, id: \.self) {
                            Text("  - \($0)").font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
#endif
