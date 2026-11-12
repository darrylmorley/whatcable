import Foundation
import Testing
@testable import WhatCableCore

/// Tests for the format 1 reader in Support/SnapshotCorpus.swift. Inline
/// fixtures, so they run on any checkout; the sweep at the end reads every
/// linked run when the local data folder is present.
@Suite("Format 1 snapshot reader")
struct SnapshotCorpusTests {
    private static let header = #"{"record":"header","format":1,"probe":"50_registry_snapshot","probe_source_sha256":"unstamped","app_version":null,"started_at":"2026-10-07T14:47:24Z"}"#
    private static let footer = #"{"record":"footer","status":"complete","reason":null,"step":null,"records":4,"failures":0,"withheld":1,"bytes_before_footer":0,"finished_at":"2026-10-07T14:47:25Z"}"#
    private static let body = [
        #"{"record":"entry","id":"0x1","class":"IORegistryEntry","props":{"t":"dict","v":[]}}"#,
        #"{"record":"entry","id":"0x2","class":"AppleHPMInterfaceType10","props":{"t":"dict","v":[["Priority",{"t":"int","bits":32,"hex":"fffffe0c"}],["UUID",{"t":"str","v":"port"}],["Blob",{"t":"data","len":4,"hex":"aa0000dd","withheld":[[1,2]]}]]}}"#,
        #"{"record":"link","plane":"IOService","id":"0x1","parent":null,"pos":0,"name":"Root","location":null,"path":"IOService:/"}"#,
        #"{"record":"link","plane":"IOService","id":"0x2","parent":"0x1","pos":0,"name":"Port-USB-C@1","location":"1","path":"IOService:/Port-USB-C@1"}"#,
    ]

    private static func file(_ lines: [String]) throws -> FormatOneFile {
        try FormatOneFile(data: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    @Test("A complete file: header, records in order, footer")
    func completeFile() throws {
        let f = try Self.file([Self.header] + Self.body + [Self.footer])
        #expect(f.probe == "50_registry_snapshot")
        #expect(f.isComplete)
        #expect(f.records.count == 4)
        #expect(f.records("link").count == 2)
    }

    @Test("A file with no footer was cut off and is never complete")
    func cutOffFile() throws {
        let f = try Self.file([Self.header] + Self.body)
        #expect(f.footer == nil)
        #expect(!f.isComplete)
        #expect(f.records.count == 4)
    }

    @Test("A last line cut mid-record (a watchdog kill) reads as cut off, the lines before it kept")
    func cutMidRecord() throws {
        let partial = String(Self.body[1].prefix(40))
        let f = try FormatOneFile(data: Data(([Self.header, Self.body[0]].joined(separator: "\n") + "\n" + partial).utf8))
        #expect(f.footer == nil)
        #expect(!f.isComplete)
        #expect(f.records.count == 1)
        // Only the last line can be cut: a bad line before it is still an error.
        #expect(throws: FormatOneFile.LoadError.notJSONLines(line: 2)) {
            try Self.file([Self.header, partial, Self.body[0]])
        }
    }

    @Test("A file that does not start with a format 1 header is refused")
    func refusesNonFormatOne() {
        #expect(throws: FormatOneFile.LoadError.noHeader) { try Self.file(Self.body) }
        #expect(throws: FormatOneFile.LoadError.unsupportedFormat(2)) {
            try Self.file([#"{"record":"header","format":2}"#])
        }
    }

    @Test("Integers keep width and bits; signed or unsigned is the reader's call")
    func integerWidths() throws {
        let v = try TypedValue(json: ["t": "int", "bits": 32, "hex": "fffffe0c"])
        #expect(v.unsigned == 0xFFFF_FE0C)
        #expect(v.signed == -500)
        #expect(try TypedValue(json: ["t": "int", "bits": 8, "hex": "80"]).signed == -128)
        #expect(try TypedValue(json: ["t": "int", "bits": 64, "hex": "ffffffffffffffff"]).signed == -1)
        #expect(throws: TypedValue.DecodeError.self) { try TypedValue(json: ["t": "int", "bits": 32, "hex": "fffe"]) }
    }

    @Test("Partly withheld data keeps its other bytes and says which were blanked")
    func partlyWithheldData() throws {
        let v = try TypedValue(json: ["t": "data", "len": 4, "hex": "aa0000dd", "withheld": [[1, 2]]])
        #expect(v == .data(Data([0xAA, 0x00, 0x00, 0xDD]), withheld: [1..<3]))
        #expect(throws: TypedValue.DecodeError.self) {
            try TypedValue(json: ["t": "data", "len": 2, "hex": "aa00", "withheld": [[1, 4]]])
        }
    }

    @Test("The snapshot view: entries by ID and class, children and parents per plane")
    func snapshotView() throws {
        let snapshot = try RegistrySnapshot(Self.file([Self.header] + Self.body + [Self.footer]))
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.children(of: 0x1, in: "IOService") == [0x2])
        #expect(snapshot.parents(of: 0x2, in: "IOService") == [0x1])
        let port = try #require(snapshot.entries(ofClass: "AppleHPMInterfaceType10").first)
        #expect(port.properties["Priority"]?.signed == -500)
        #expect(port.properties["UUID"] == .string("port"))
    }

    @Test("A process connection keeps its class and its place: skipped props, reachable from the root")
    func processConnectionKeepsItsPlace() throws {
        // The connection (0x3) has an entry with the skipped marker and a link, so the
        // virtual HID device beneath it (0x4) is reached by walking down from the root.
        let lines = [Self.header] + Self.body + [
            #"{"record":"entry","id":"0x3","class":"IOHIDResourceDeviceUserClient","props":{"t":"skipped"}}"#,
            #"{"record":"link","plane":"IOService","id":"0x3","parent":"0x1","pos":1,"name":"IOHIDResourceDeviceUserClient","location":null,"path":null}"#,
            #"{"record":"entry","id":"0x4","class":"IOHIDUserDevice","props":{"t":"dict","v":[["Transport",{"t":"str","v":"Bluetooth"}]]}}"#,
            #"{"record":"link","plane":"IOService","id":"0x4","parent":"0x3","pos":0,"name":"IOHIDUserDevice","location":null,"path":null}"#,
            #"{"record":"footer","status":"complete","reason":null,"step":null,"records":8,"failures":0,"withheld":1,"bytes_before_footer":0,"finished_at":"2026-10-07T14:47:25Z"}"#,
        ]
        let snapshot = try RegistrySnapshot(Self.file(lines))
        let connection = try #require(snapshot.entries[0x3])
        #expect(connection.className == "IOHIDResourceDeviceUserClient")
        #expect(connection.properties == .skipped)
        #expect(snapshot.children(of: 0x1, in: "IOService") == [0x2, 0x3])
        #expect(snapshot.children(of: 0x3, in: "IOService") == [0x4])
        #expect(snapshot.entries[0x4]?.properties["Transport"] == .string("Bluetooth"))
    }

    @Test("Another probe's file is not a registry snapshot")
    func refusesOtherProbes() throws {
        let other = #"{"record":"header","format":1,"probe":"54_power_sources"}"#
        #expect(throws: TypedValue.DecodeError.self) { try RegistrySnapshot(Self.file([other])) }
    }

    @Test("Every linked run's snapshot loads complete, or stopped or missing as the contract allows")
    func linkedRunsLoad() throws {
        // No research-data link (private; absent on a fresh clone or the public repo) is a legitimate skip. A
        // runs folder that exists but holds no runs is a broken link, and must
        // fail rather than pass on nothing.
        //
        // Two shapes are not complete snapshots and are still correct
        // (first met 2026-11-12):
        // - stopped with `identifiers_incomplete`: FORMAT.md lets any probe
        //   stop that way, header then footer, no records, `step` naming the
        //   lookup that failed. Every probe on an Intel Mac with Bluetooth
        //   does (an Intel iMac run, step `bluetooth`).
        // - no snapshot file in a run the worker never confirmed (`run.json`
        //   summary absent or not complete): the ingest writes such a run
        //   once it is over 24 hours old, with whatever probes reached KV.
        // A confirmed run without a snapshot, or any other stop, still fails.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: SnapshotCorpus.root.path, isDirectory: &isDir), isDir.boolValue else { return }
        let runs = SnapshotCorpus.allRuns()
        #expect(!runs.isEmpty, "\(SnapshotCorpus.root.path) exists but holds no runs")
        var complete = 0
        for run in runs {
            let name = run.lastPathComponent
            guard let file = try SnapshotCorpus.load(run: run, probe: "50_registry_snapshot") else {
                let meta = try? JSONSerialization.jsonObject(
                    with: Data(contentsOf: run.appendingPathComponent("run.json"))) as? [String: Any]
                let summary = meta?["summary"] as? [String: Any]
                #expect(meta != nil, "\(name) has no 50_registry_snapshot.jsonl and no readable run.json")
                #expect(summary?["complete"] as? Bool != true,
                        "\(name) has no 50_registry_snapshot.jsonl though the worker confirmed the run complete")
                continue
            }
            if file.footer?["status"] as? String == "stopped",
               file.footer?["reason"] as? String == "identifiers_incomplete" {
                #expect(file.records.isEmpty, "\(name): stopped for identifiers but holds records")
                let step = file.footer?["step"] as? String ?? ""
                #expect(step.count > 0, "\(name): stopped for identifiers with no step")
                continue
            }
            #expect(file.isComplete, "\(name): snapshot was cut off")
            #expect(try RegistrySnapshot(file).entries.count > 0, "\(name): no entries")
            complete += 1
        }
        #expect(runs.isEmpty || complete > 0, "no linked run has a complete snapshot: checked nothing")
    }
}
