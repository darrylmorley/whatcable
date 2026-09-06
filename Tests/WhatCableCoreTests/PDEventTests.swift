import Foundation
import Testing
@testable import WhatCableCore

// Fixtures S1 to S7 are the byte-exact appended runs from the verified decode
// of PortControllerEvtBuffer (m1max and m2max multi-scenario captures, 2026-09-05).
// Each one was produced by aligning two consecutive 120-byte ring snapshots and
// isolating the new bytes, then checking the token counts against the deltas of
// the PortController* counters. Expected tokens come straight from that brief.
@Suite("PD Event Trace")
struct PDEventTests {
    /// Builds the expected record list from (opcode, argument) pairs.
    ///
    /// `seamAffectedFirst` marks the first record the way `parse` does whenever
    /// the buffer starts mid-ring: with no leading zeros the alignment at index
    /// 0 is a guess, so the first record that comes out of it is flagged and
    /// the view never shows it. Pass false for a buffer whose alignment is
    /// known (an unfilled ring, or one whose leftover byte was found).
    private func expected(_ pairs: [(UInt8, UInt8?)], seamAffectedFirst: Bool = true) -> [PDEventRecord] {
        pairs.enumerated().map { index, pair in
            PDEventRecord(
                event: PDEvent(rawValue: pair.0),
                argument: pair.1,
                isSeamAffected: seamAffectedFirst && index == 0
            )
        }
    }

    private func parse(_ bytes: [UInt8]) -> [PDEventRecord] {
        PDEventTrace.parse(Data(bytes)).events
    }

    @Test("S1 m1max snap1 port3")
    func fixtureS1() {
        let bytes: [UInt8] = [
            0x03, 0x01, 0x1a, 0x01, 0x3f, 0xf1, 0x40, 0x00, 0x5f, 0xf1, 0x81, 0x30, 0x04,
            0xf0, 0x19, 0xf1, 0x01, 0x1a, 0x30, 0x3f, 0x01, 0x5f, 0x48, 0x40, 0x01, 0x48,
            0x5f, 0x30, 0x04, 0xf2, 0x03, 0xf0, 0x39, 0xf1, 0x01, 0x5e, 0x01, 0x5f,
        ]
        let want = expected([
            (0x03, 0x01), (0x1a, 0x01), (0x3f, 0xf1), (0x40, 0x00), (0x5f, nil),
            (0xf1, 0x81), (0x30, 0x04), (0xf0, 0x19), (0xf1, 0x01), (0x1a, 0x30),
            (0x3f, 0x01), (0x5f, nil), (0x48, nil), (0x40, 0x01), (0x48, nil),
            (0x5f, nil), (0x30, 0x04), (0xf2, 0x03), (0xf0, 0x39), (0xf1, 0x01),
            (0x5e, 0x01), (0x5f, nil),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("S2 m1max snap2 port0")
    func fixtureS2() {
        let bytes: [UInt8] = [0x03, 0x01, 0x1a, 0x03, 0x40, 0x00, 0x5f, 0xf8, 0x00]
        let want = expected([
            (0x03, 0x01), (0x1a, 0x03), (0x40, 0x00), (0x5f, nil), (0xf8, 0x00),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("S3 m1max snap3 port0")
    func fixtureS3() {
        let bytes: [UInt8] = [
            0xf8, 0x00, 0x03, 0x02, 0x1a, 0x03, 0x3f, 0x02, 0x5f, 0x03, 0x01, 0x1a, 0x03,
            0x40, 0x00, 0x5f, 0xf8, 0x00, 0x37, 0x02, 0xf8, 0x00, 0x1a, 0x01, 0x3f, 0x01,
            0x3f, 0x03, 0x30, 0x01, 0xf0, 0x04, 0x3f, 0x01, 0x48, 0x5f, 0x5f, 0x5f, 0x30,
            0x01, 0xf0, 0x02, 0x30, 0x01, 0xf0, 0x02, 0x30, 0x01, 0xf0, 0x02, 0x48, 0x5f,
            0x40, 0x01, 0x5e, 0x01, 0x5f,
        ]
        let want = expected([
            (0xf8, 0x00), (0x03, 0x02), (0x1a, 0x03), (0x3f, 0x02), (0x5f, nil),
            (0x03, 0x01), (0x1a, 0x03), (0x40, 0x00), (0x5f, nil), (0xf8, 0x00),
            (0x37, 0x02), (0xf8, 0x00), (0x1a, 0x01), (0x3f, 0x01), (0x3f, 0x03),
            (0x30, 0x01), (0xf0, 0x04), (0x3f, 0x01), (0x48, nil), (0x5f, nil),
            (0x5f, nil), (0x5f, nil), (0x30, 0x01), (0xf0, 0x02), (0x30, 0x01),
            (0xf0, 0x02), (0x30, 0x01), (0xf0, 0x02), (0x48, nil), (0x5f, nil),
            (0x40, 0x01), (0x5e, 0x01), (0x5f, nil),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("S4 m2max snap1 port3")
    func fixtureS4() {
        let bytes: [UInt8] = [
            0x03, 0x01, 0x1a, 0x01, 0x3f, 0xf1, 0x40, 0x00, 0x5f, 0xf1, 0x81, 0x30, 0x04,
            0xf0, 0x19, 0xf1, 0x01, 0x1a, 0x30, 0x3f, 0x01, 0x5f, 0x48, 0x40, 0x01,
        ]
        let want = expected([
            (0x03, 0x01), (0x1a, 0x01), (0x3f, 0xf1), (0x40, 0x00), (0x5f, nil),
            (0xf1, 0x81), (0x30, 0x04), (0xf0, 0x19), (0xf1, 0x01), (0x1a, 0x30),
            (0x3f, 0x01), (0x5f, nil), (0x48, nil), (0x40, 0x01),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("S5 m2max snap2 port0")
    func fixtureS5() {
        let bytes: [UInt8] = [
            0x03, 0x01, 0x1a, 0x03, 0x40, 0x00, 0x5f, 0xf8, 0x00, 0x37, 0x02, 0xf8, 0x00,
            0x37, 0x02, 0x31, 0x10, 0x48, 0x5f, 0x40, 0x01, 0x1a, 0x01, 0x3f, 0x03, 0x3f,
            0xf1, 0x30, 0x04, 0xf0, 0x04, 0x3f, 0x01, 0x5e, 0x00, 0x5f,
        ]
        let want = expected([
            (0x03, 0x01), (0x1a, 0x03), (0x40, 0x00), (0x5f, nil), (0xf8, 0x00),
            (0x37, 0x02), (0xf8, 0x00), (0x37, 0x02), (0x31, 0x10), (0x48, nil),
            (0x5f, nil), (0x40, 0x01), (0x1a, 0x01), (0x3f, 0x03), (0x3f, 0xf1),
            (0x30, 0x04), (0xf0, 0x04), (0x3f, 0x01), (0x5e, 0x00), (0x5f, nil),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("S6 m2max snap2 port3")
    func fixtureS6() {
        let bytes: [UInt8] = [0x5e, 0x00, 0x5f]
        #expect(parse(bytes) == expected([(0x5e, 0x00), (0x5f, nil)]))
    }

    @Test("S7 m2max snap3 port1")
    func fixtureS7() {
        let bytes: [UInt8] = [0x03, 0x01, 0x1a, 0x03, 0x40, 0x00, 0x5f, 0xf8, 0x00]
        let want = expected([
            (0x03, 0x01), (0x1a, 0x03), (0x40, 0x00), (0x5f, nil), (0xf8, 0x00),
        ])
        #expect(parse(bytes) == want)
    }

    @Test("A leading run of zeros is stripped, the raw buffer is kept whole")
    func leadingZerosStripped() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x5e, 0x00, 0x5f]
        let trace = PDEventTrace.parse(Data(bytes))
        #expect(trace.rawBuffer == Data(bytes))
        #expect(trace.events == expected([(0x5e, 0x00), (0x5f, nil)], seamAffectedFirst: false))
    }

    @Test("Zero is a legitimate argument and is never dropped")
    func zeroArgumentPreserved() {
        // 40 00 and f8 00 both carry a real zero argument mid-buffer.
        let bytes: [UInt8] = [0x40, 0x00, 0x5f, 0xf8, 0x00]
        #expect(parse(bytes) == expected([(0x40, 0x00), (0x5f, nil), (0xf8, 0x00)]))
    }

    @Test("A trailing opcode whose argument is missing yields a nil argument")
    func trailingOpcodeMissingArgument() {
        let bytes: [UInt8] = [0x48, 0x30]
        #expect(parse(bytes) == expected([(0x48, nil), (0x30, nil)]))
    }

    @Test("An unrecognised byte becomes a standalone unknown record")
    func unknownStandalone() {
        // 0x99 is not in the argument-taking list, so the byte after it is its
        // own token. It is placed second here because the record at index 0 is
        // always seam-affected in a buffer with no leading zeros.
        let bytes: [UInt8] = [0x48, 0x99, 0x48]
        let records = parse(bytes)
        #expect(records == expected([(0x48, nil), (0x99, nil), (0x48, nil)]))
        #expect(records[1].event == .unknown(0x99))
        #expect(records.dropFirst().allSatisfy { !$0.isSeamAffected })
    }

    @Test("0xf3 carries an argument")
    func f3TakesAnArgument() {
        // 0xf3 is in the argument-taking set on the strength of the corpus, and
        // no S1 to S7 fixture happens to contain one, so without this test the
        // opcode could be dropped from the set with every other test still green.
        // Leading 0x48 keeps the first byte a valid opcode, so nothing here is
        // read as a ring-seam fragment.
        let bytes: [UInt8] = [0x48, 0xf3, 0x0c, 0xf3, 0x00, 0x5f]
        #expect(parse(bytes) == expected([
            (0x48, nil), (0xf3, 0x0c), (0xf3, 0x00), (0x5f, nil),
        ]))
    }

    @Test("A leading byte that is not an opcode is a ring-seam fragment")
    func leadingNonOpcodeIsASeamFragment() {
        // 0x81 is an f1 argument, never an opcode. Seeing one first means the
        // ring dropped the f1 that owned it. It must not eat the byte after it.
        let records = parse([0x81, 0x30, 0x04, 0xf0, 0x19, 0x5f])
        #expect(records.count == 4)
        #expect(records[0].isSeamAffected)
        #expect(records[0].event == .unknown(0x81))
        #expect(records[0].argument == nil)
        // Reading 0x81 as a record of its own (H1) puts the next boundary at
        // index 1 as well, so the two readings agree from 30(04) on and it is
        // shown. Only the leftover itself is flagged.
        #expect(Array(records.dropFirst()) == expected([
            (0x30, 0x04), (0xf0, 0x19), (0x5f, nil),
        ], seamAffectedFirst: false))
    }

    @Test("A forced leftover whose two readings agree at once flags only itself")
    func forcedLeftoverConvergesImmediately() {
        // 81 30 04 5f: H1 reads 81 | 30(04) | 5f, H2 reads 81(leftover) |
        // 30(04) | 5f. Both have a boundary at index 1, so 30(04) onward is
        // the same under either reading and is shown.
        let records = parse([0x81, 0x30, 0x04, 0x5f])
        #expect(records.map(\.isSeamAffected) == [true, false, false])
        #expect(records[0] == PDEventRecord(event: .unknown(0x81), argument: nil, isSeamAffected: true))
        #expect(Array(records.dropFirst()) == expected([(0x30, 0x04), (0x5f, nil)], seamAffectedFirst: false))
    }

    @Test("Every record the two readings disagree on is flagged, not just the first")
    func h1RecordsBeforeReconvergenceAreFlagged() {
        // 3f f1 03 01: H1 reads 3f(f1) | 03(01), and it is chosen because
        // 3f(f1) lands on the 0x03 opcode. But H2 reads a leftover 3f | f1(03)
        // | 01, which has no plug event in it and only meets H1 again at the
        // end of the buffer. So the plug event is an artefact of the guess and
        // must not be shown: both H1 records are flagged.
        let records = parse([0x3f, 0xf1, 0x03, 0x01])
        #expect(records == [
            PDEventRecord(event: .unknown(0x3f), argument: 0xf1, isSeamAffected: true),
            PDEventRecord(event: .plugEvent, argument: 0x01, isSeamAffected: true),
        ])
        #expect(!records.contains { !$0.isSeamAffected && $0.event == .plugEvent })
        #expect(records.filter { !$0.isSeamAffected }.isEmpty)
    }

    @Test("Once the two readings agree, nothing after that point is flagged")
    func flaggingStopsAtReconvergence() {
        // 03 01 1a 03 40 00 5f: H1 (chosen) reads 03(01) | 1a(03) | 40(00) |
        // 5f. H2 reads 03 | 01 | 1a(03) | 40(00) | 5f. Both have a boundary at
        // index 2, so only 03(01) is flagged and 1a(03) onward is shown.
        let records = parse([0x03, 0x01, 0x1a, 0x03, 0x40, 0x00, 0x5f])
        #expect(records == expected([(0x03, 0x01), (0x1a, 0x03), (0x40, 0x00), (0x5f, nil)]))
        #expect(records.map(\.isSeamAffected) == [true, false, false, false])
    }

    @Test("A leading byte that is a valid opcode keeps all its bytes")
    func leadingOpcodeIsNotDroppedAsALeftover() {
        // No leftover record is invented: 0x03 keeps its argument and the
        // record after it is untouched. The 0x03 is still flagged, because
        // with no leading zeros the alignment at index 0 is a guess whichever
        // reading wins, and a flagged record is one the view will not show.
        let records = parse([0x03, 0x01, 0x5f])
        #expect(records == expected([(0x03, 0x01), (0x5f, nil)]))
        #expect(records.filter { !$0.isSeamAffected } == [
            PDEventRecord(event: .uvdmStatusUpdate, argument: nil),
        ])
        // 0x48 and 0x5f are real events with no argument, so neither swallows
        // the byte after it.
        #expect(parse([0x48, 0x03, 0x01]).count == 2)
        #expect(parse([0x5f, 0x03, 0x01]).count == 2)
    }

    @Test("Three or more leading zeros mean an unfilled ring, so nothing is a fragment")
    func longZeroRunMeansNoSeam() {
        // A ring that has not wrapped yet has no seam, so its first byte is a
        // real record even when we do not recognise it. This case used to be
        // classified as a fragment, which hid it.
        let records = parse([0x00, 0x00, 0x00, 0x81, 0x30, 0x04])
        #expect(records.count == 2)
        #expect(records.allSatisfy { !$0.isSeamAffected })
        #expect(records[0].event == .unknown(0x81))
        #expect(records[1] == PDEventRecord(event: .sourceCapsReceived, argument: 0x04))
    }

    @Test("A padded buffer keeps its first unknown opcode")
    func paddedBufferKeepsItsFirstRecord() {
        // Seven zeros then 01 01 03 01, a shape the corpus really has. All
        // three records must survive: 0x01 is unknown, not a leftover.
        let bytes = [UInt8](repeating: 0x00, count: 7) + [0x01, 0x01, 0x03, 0x01]
        let records = parse(bytes)
        #expect(records.allSatisfy { !$0.isSeamAffected })
        #expect(records == expected([(0x01, nil), (0x01, nil), (0x03, 0x01)], seamAffectedFirst: false))
    }

    @Test("A short zero run starts with the leftover argument")
    func shortZeroRunIsTheFragment() {
        // One or two leading zeros are too few to be an unfilled ring, so index
        // 0 is the argument byte of a record whose opcode the seam cut off. The
        // leftover being found, the alignment after it is known and nothing
        // else is flagged.
        let one = parse([0x00, 0x5f, 0x03, 0x01])
        #expect(one.count == 3)
        #expect(one.first == PDEventRecord(event: .unknown(0x00), argument: nil, isSeamAffected: true))
        #expect(Array(one.dropFirst()) == expected([(0x5f, nil), (0x03, 0x01)], seamAffectedFirst: false))

        // Only ONE byte can be left over, because every argument-taking opcode
        // consumes exactly one. So with two leading zeros the second is a real
        // record of its own, not a second leftover.
        let two = parse([0x00, 0x00, 0x03, 0x01])
        #expect(two.count == 3)
        #expect(two.first == PDEventRecord(event: .unknown(0x00), argument: nil, isSeamAffected: true))
        #expect(Array(two.dropFirst()) == expected([(0x00, nil), (0x03, 0x01)], seamAffectedFirst: false))
    }

    @Test("A seam byte that is itself a valid opcode is still caught")
    func opcodeValuedSeamFragment() {
        // 0x3f takes 0xf1 as an argument, so a seam just after a 3f leaves a
        // buffer starting with 0xf1. Reading that as an f1 record would eat the
        // 0x40 after it, losing a real record and inventing two.
        let records = parse([0xf1, 0x40, 0x00, 0x5f, 0xf1, 0x81, 0x30, 0x04])
        #expect(records[0].isSeamAffected)
        #expect(records[0].event == .sourceReady)
        #expect(records[0].argument == nil)
        #expect(Array(records.dropFirst()) == expected([
            (0x40, 0x00), (0x5f, nil), (0xf1, 0x81), (0x30, 0x04),
        ]))
        // 40(00) is the record the guess produced, so it is flagged too; the
        // rest are past the seam and are shown.
        #expect(records.filter { !$0.isSeamAffected } == expected([
            (0x5f, nil), (0xf1, 0x81), (0x30, 0x04),
        ], seamAffectedFirst: false))
    }

    @Test("A leading opcode whose record lands on another opcode keeps its bytes")
    func leadingOpcodeThatLinesUpIsKept() {
        // 03(01) leaves the next byte on 0x1a, a real opcode, so the reading
        // that treats 0x03 as a record is the one that fits. It is still the
        // record at the seam, so it is flagged and not shown: an alignment that
        // fits is not the same as an alignment that is known.
        let records = parse([0x03, 0x01, 0x1a, 0x03])
        #expect(records == expected([(0x03, 0x01), (0x1a, 0x03)]))
        #expect(records[0].isSeamAffected)
        #expect(records.dropFirst().allSatisfy { !$0.isSeamAffected })
    }

    @Test("An ambiguous seam never produces a shown record either way")
    func ambiguousSeamIsNeverShown() {
        // 3f f1 01 03 01 reads either as 3f(f1), unknown(01), 03(01) or as a
        // leftover 3f then f1(01), 03(01). Nothing in the buffer settles it,
        // and the second reading would invent an accepted source ready. So
        // whichever alignment is picked, every record the choice touched is
        // flagged and only 03(01) is shown.
        let records = parse([0x3f, 0xf1, 0x01, 0x03, 0x01])
        let shown = records.filter { !$0.isSeamAffected }
        #expect(shown == [PDEventRecord(event: .plugEvent, argument: 0x01)])
        #expect(records.first?.isSeamAffected == true)
    }

    @Test("Source ready reports accepted, rejected or unknown, never a guess")
    func sourceReadyOutcomes() {
        #expect(PDEventRecord(event: .sourceReady, argument: 0x01).sourceReadyOutcome == .accepted)
        #expect(PDEventRecord(event: .sourceReady, argument: 0x81).sourceReadyOutcome == .rejected)
        // A record the ring cut short has no argument. That is not a success.
        #expect(PDEventRecord(event: .sourceReady, argument: nil).sourceReadyOutcome == .unknown)
        #expect(PDEventRecord(event: .sourceReady, argument: 0x40).sourceReadyOutcome == .unknown)
        // Every other opcode has no source ready outcome at all.
        #expect(PDEventRecord(event: .plugEvent, argument: 0x01).sourceReadyOutcome == nil)
        #expect(PDEventRecord(event: .unknown(0x1a), argument: 0x01).sourceReadyOutcome == nil)
    }

    @Test("Empty buffer and all-zero buffer produce no events")
    func emptyBuffers() {
        #expect(PDEventTrace.parse(Data()).events.isEmpty)
        #expect(PDEventTrace.parse(Data([0x00, 0x00, 0x00])).events.isEmpty)
    }

    @Test("Round trip: rawValue matches init input for the eight known codes")
    func roundTrip() {
        let codes: [UInt8] = [0x03, 0x30, 0xf0, 0xf1, 0x48, 0x5e, 0x5f, 0x37]
        for code in codes {
            let event = PDEvent(rawValue: code)
            #expect(event.rawValue == code, "Round trip failed for 0x\(String(code, radix: 16))")
            if case .unknown = event {
                Issue.record("0x\(String(code, radix: 16)) should be a known case")
            }
        }
    }

    @Test("Known codes map to the verified Apple HPM meanings")
    func knownCodeMapping() {
        #expect(PDEvent(rawValue: 0x03) == .plugEvent)
        #expect(PDEvent(rawValue: 0x30) == .sourceCapsReceived)
        #expect(PDEvent(rawValue: 0xf0) == .requestSent)
        #expect(PDEvent(rawValue: 0xf1) == .sourceReady)
        #expect(PDEvent(rawValue: 0x48) == .identityReceived)
        #expect(PDEvent(rawValue: 0x5e) == .uvdmEnum)
        #expect(PDEvent(rawValue: 0x5f) == .uvdmStatusUpdate)
        #expect(PDEvent(rawValue: 0x37) == .becameSource)
        #expect(PDEvent(rawValue: 0x1a) == .unknown(0x1a))
    }

    @Test("Record accessors read the argument byte")
    func recordAccessors() {
        let attach = PDEventRecord(event: .plugEvent, argument: 0x01)
        let detach = PDEventRecord(event: .plugEvent, argument: 0x02)
        #expect(attach.isAttach)
        #expect(!attach.isDetach)
        #expect(detach.isDetach)
        #expect(!detach.isAttach)

        let rejected = PDEventRecord(event: .sourceReady, argument: 0x81)
        let ok = PDEventRecord(event: .sourceReady, argument: 0x01)
        #expect(rejected.isSourceReadyRejected)
        #expect(!ok.isSourceReadyRejected)

        #expect(PDEventRecord(event: .sourceCapsReceived, argument: 0x04).pdoCount == 4)
        #expect(PDEventRecord(event: .sourceCapsReceived, argument: nil).pdoCount == nil)
        #expect(PDEventRecord(event: .identityReceived, argument: nil).pdoCount == nil)
    }
}
