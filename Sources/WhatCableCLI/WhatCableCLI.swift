import Foundation
import WhatCableCore
import WhatCableDarwinBackend

@main
struct WhatCableCLI {
    static func main() async {
        // Hand-rolled flag parsing. We only have a handful of flags; pulling
        // in swift-argument-parser would be heavier than the rest of the CLI.
        let parsedLanguage: (language: WhatCableLanguage, args: [String])
        do {
            parsedLanguage = try parseLanguage(Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            FileHandle.standardError.write(Data(error.message(language: WhatCableLanguage.persistedForApp()).utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("whatcable: invalid arguments\n".utf8))
            exit(2)
        }
        let language = parsedLanguage.language
        let args = parsedLanguage.args

        if args.contains("-h") || args.contains("--help") {
            print(helpText(language: language))
            return
        }
        if args.contains("--version") {
            print(AppInfo.version)
            return
        }

        if args.contains("--tb-debug") {
            print(ThunderboltProbe.dump(), terminator: "")
            return
        }

        let showRaw = args.contains("--raw")
        let asJSON = args.contains("--json")
        let watch = args.contains("--watch")
        let report = args.contains("--report")

        // Reject unknown flags so typos don't silently produce default output.
        let knownFlags: Set<String> = ["--raw", "--json", "--watch", "--report", "--tb-debug", "-h", "--help", "--version"]
        for arg in args where arg.hasPrefix("-") && !knownFlags.contains(arg) {
            FileHandle.standardError.write(Data(cliString("whatcable: unknown option \(arg)\n", language: language).utf8))
            FileHandle.standardError.write(Data(helpText(language: language).utf8))
            exit(2)
        }

        let provider = makeDefaultSnapshotProvider()

        if watch {
            await runWatch(provider: provider, asJSON: asJSON, showRaw: showRaw, language: language)
            return
        }

        do {
            let snapshot = try await provider.snapshot()

            if report {
                printCableReports(identities: snapshot.identities, language: language)
                return
            }

            try printSnapshot(snapshot, asJSON: asJSON, showRaw: showRaw, language: language)
        } catch {
            FileHandle.standardError.write(Data("whatcable: \(error)\n".utf8))
            exit(1)
        }
    }

    static func helpText(language: WhatCableLanguage = .default) -> String {
        switch language {
        case .english:
            return """
            whatcable \(AppInfo.version) — \(AppInfo.tagline(language: language))

            Usage: whatcable [options]

            Options:
              --watch              Continuously monitor for changes (Ctrl+C to exit)
              --json               Output as JSON instead of human-readable text
              --raw                Include raw IOKit properties for each port
              --report             Print a cable report (markdown + GitHub URL) and exit
              --language <code>    Output language for human-readable text: en, zh-Hans
              --tb-debug           Dump the IOThunderboltSwitch tree (for contributors helping
                                   us design the Thunderbolt fabric feature). See issue tracker.
              --version            Print version and exit
              -h, --help           Show this help and exit

            """
        case .simplifiedChinese:
            return """
            whatcable \(AppInfo.version) — \(AppInfo.tagline(language: language))

            用法：whatcable [选项]

            选项：
              --watch              持续监测变化（按 Ctrl+C 退出）
              --json               输出 JSON，而不是人类可读文本
              --raw                为每个端口包含原始 IOKit 属性
              --report             打印线缆报告（Markdown + GitHub URL）并退出
              --language <code>    人类可读文本的输出语言：en、zh-Hans
              --tb-debug           转储 IOThunderboltSwitch 树（供协助设计
                                   Thunderbolt 拓扑功能的贡献者使用）。参见 issue tracker。
              --version            打印版本并退出
              -h, --help           显示此帮助并退出

            """
        }
    }
}

private enum CLIError: Error {
    case message(String)
    case missingLanguageValue
    case unsupportedLanguage(String)

    func message(language: WhatCableLanguage) -> String {
        switch self {
        case .message(let value): return value
        case .missingLanguageValue:
            return LocalizedCopy.string("whatcable: --language requires one of: en, zh-Hans\n", language: language)
        case .unsupportedLanguage(let value):
            return LocalizedCopy.string("whatcable: unsupported language \(value). Use one of: en, zh-Hans\n", language: language)
        }
    }
}

private func parseLanguage(_ rawArgs: [String]) throws -> (language: WhatCableLanguage, args: [String]) {
    var args: [String] = []
    var language: WhatCableLanguage?
    var index = 0

    while index < rawArgs.count {
        let arg = rawArgs[index]
        if arg == "--language" {
            let valueIndex = index + 1
            guard valueIndex < rawArgs.count else {
                throw CLIError.missingLanguageValue
            }
            let value = rawArgs[valueIndex]
            guard let parsed = WhatCableLanguage(rawValue: value) else {
                throw CLIError.unsupportedLanguage(value)
            }
            language = parsed
            index += 2
        } else {
            args.append(arg)
            index += 1
        }
    }

    return (language ?? WhatCableLanguage.persistedForApp(), args)
}

private func cliString(_ english: String.LocalizationValue, language: WhatCableLanguage) -> String {
    LocalizedCopy.string(english, language: language)
}

private func printSnapshot(_ snapshot: CableSnapshot, asJSON: Bool, showRaw: Bool, language: WhatCableLanguage) throws {
    if asJSON {
        let json = try JSONFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: showRaw,
            adapter: snapshot.adapter,
            thunderboltSwitches: snapshot.thunderboltSwitches
        )
        print(json)
    } else {
        let output = TextFormatter.render(
            ports: snapshot.ports,
            sources: snapshot.powerSources,
            identities: snapshot.identities,
            showRaw: showRaw,
            adapter: snapshot.adapter,
            thunderboltSwitches: snapshot.thunderboltSwitches,
            language: language
        )
        print(output, terminator: "")
    }
}

private func runWatch(provider: any CableSnapshotProvider, asJSON: Bool, showRaw: Bool, language: WhatCableLanguage) async {
    let watchTask = Task {
        await consumeWatchStream(provider: provider, asJSON: asJSON, showRaw: showRaw, language: language)
    }

    // Default SIGINT / SIGTERM kill the process abruptly. Take them over so
    // the watch task can cancel cleanly, the provider's onTermination tears
    // down its internal task, and stdout flushes before exit.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    intSrc.setEventHandler { watchTask.cancel() }
    intSrc.resume()

    let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termSrc.setEventHandler { watchTask.cancel() }
    termSrc.resume()

    await watchTask.value

    intSrc.cancel()
    termSrc.cancel()
    fflush(stdout)
}

private func consumeWatchStream(provider: any CableSnapshotProvider, asJSON: Bool, showRaw: Bool, language: WhatCableLanguage) async {
    var lastOutput = ""
    do {
        for try await snapshot in provider.watch() {
            if Task.isCancelled { return }

            let output: String
            if asJSON {
                do {
                    output = try JSONFormatter.render(
                        ports: snapshot.ports,
                        sources: snapshot.powerSources,
                        identities: snapshot.identities,
                        showRaw: showRaw,
                        adapter: snapshot.adapter,
                        thunderboltSwitches: snapshot.thunderboltSwitches
                    )
                } catch {
                    FileHandle.standardError.write(Data("whatcable: json encoding failed: \(error)\n".utf8))
                    continue
                }
            } else {
                output = TextFormatter.render(
                    ports: snapshot.ports,
                    sources: snapshot.powerSources,
                    identities: snapshot.identities,
                    showRaw: showRaw,
                    adapter: snapshot.adapter,
                    thunderboltSwitches: snapshot.thunderboltSwitches,
                    language: language
                )
            }

            guard output != lastOutput else { continue }
            lastOutput = output

            if asJSON {
                // Newline-delimited JSON: one self-contained object per change.
                print(output)
            } else {
                // Clear screen + home cursor, then redraw.
                print("\u{1B}[2J\u{1B}[H", terminator: "")
                print(timestampHeader())
                print(output, terminator: "")
            }
            fflush(stdout)
        }
    } catch is CancellationError {
        return
    } catch {
        FileHandle.standardError.write(Data("whatcable: \(error)\n".utf8))
        exit(1)
    }
}

private func timestampHeader() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return "whatcable --watch · \(formatter.string(from: Date()))\n\n"
}

private func printCableReports(identities: [PDIdentity], language: WhatCableLanguage) {
    let cables = identities.filter {
        $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
    }
    if cables.isEmpty {
        print(cliString("No cable e-markers detected. Plug in an e-marked USB-C cable and try again.", language: language))
        print(cliString("(Most cables under 60W don't carry an e-marker, so there's nothing to report on those.)", language: language))
        return
    }
    for (i, identity) in cables.enumerated() {
        if cables.count > 1 {
            print("=== \(cliString("Cable \(i + 1) of \(cables.count)", language: language)) ===")
            print("")
        }
        guard let payload = CableReport.payload(
            for: identity,
            includeSystemInfo: true
        ) else { continue }
        print(payload.markdown)
        print("")
        print(cliString("Open in GitHub to file a report:", language: language))
        print(payload.githubURL.absoluteString)
        print("")
    }
}
