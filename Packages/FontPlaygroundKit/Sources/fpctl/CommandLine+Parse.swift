import Foundation

struct Invocation: Equatable, Sendable {
    var enginePath: String?
    var verbose: Bool
    var command: Command
}
enum Command: Equatable, Sendable {
    case help, version
    case hello(json: Bool)
    case scan(paths: [String], json: Bool)
    case forge(recipe: String, out: String, fontDirectories: [String], allowMissing: Bool, json: Bool, quiet: Bool)
}
enum UsageError: Error, Equatable {
    case missingCommand, unknownCommand(String), unknownOption(String), missingValue(String)
    case missingArgument(String), unexpectedArgument(String), optionNotAllowed(option: String, command: String)
    var message: String {
        switch self {
        case .missingCommand: "a command is required"
        case .unknownCommand(let value): "unknown command '\(value)'"
        case .unknownOption(let value): "unknown option '\(value)'"
        case .missingValue(let value): "\(value) needs a value"
        case .missingArgument(let value): "missing \(value)"
        case .unexpectedArgument(let value): "unexpected argument '\(value)'"
        case .optionNotAllowed(let option, let command): "\(option) is not allowed for \(command)"
        }
    }
}

extension FPCTL {
    static func parse(_ args: [String], currentDirectory: String) throws(UsageError) -> Invocation {
        let optionArguments = args.prefix { $0 != "--" }
        if optionArguments.contains("-h") || optionArguments.contains("--help") {
            return .init(enginePath: nil, verbose: false, command: .help)
        }
        if optionArguments.contains("--version") { return .init(enginePath: nil, verbose: false, command: .version) }
        var engine: String?, command: String?, out: String?
        var verbose = false, json = false, allowMissing = false, quiet = false, options = true
        var paths: [String] = [], directories: [String] = [], localOptions: [String] = []
        var i = 0
        func absolute(_ path: String) -> String {
            URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: currentDirectory, isDirectory: true))
                .standardizedFileURL.path
        }
        while i < args.count {
            let arg = args[i]
            i += 1
            if options && arg == "--" { options = false; continue }
            if options && arg.hasPrefix("-") {
                let parts = arg.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let option = String(parts[0])
                if parts.count == 1 && (option == "-h" || option == "--help") {
                    return .init(enginePath: nil, verbose: false, command: .help)
                }
                if parts.count == 1 && option == "--version" {
                    return .init(enginePath: nil, verbose: false, command: .version)
                }
                if ["--engine", "--out", "--font-dir"].contains(option) {
                    let value: String
                    if parts.count == 2 {
                        value = String(parts[1])
                    } else {
                        guard i < args.count, !args[i].hasPrefix("--") else { throw .missingValue(option) }
                        value = args[i]; i += 1
                    }
                    guard !value.isEmpty else { throw .missingValue(option) }
                    switch option {
                    case "--engine": engine = absolute(value)
                    case "--out": out = absolute(value); localOptions.append(option)
                    default: directories.append(absolute(value)); localOptions.append(option)
                    }
                } else {
                    guard parts.count == 1 else { throw .unknownOption(arg) }
                    switch option {
                    case "--verbose": verbose = true
                    case "--json": json = true
                    case "--allow-missing": allowMissing = true; localOptions.append(option)
                    case "--quiet": quiet = true; localOptions.append(option)
                    default: throw .unknownOption(option)
                    }
                }
            } else if command == nil {
                command = arg
            } else {
                paths.append(absolute(arg))
            }
        }
        guard let command else { throw .missingCommand }
        guard ["hello", "scan", "forge"].contains(command) else { throw .unknownCommand(command) }
        if command != "forge", let option = localOptions.first {
            throw .optionNotAllowed(option: option, command: command)
        }
        let result: Command
        switch command {
        case "hello":
            if let first = paths.first { throw .unexpectedArgument(first) }
            result = .hello(json: json)
        case "scan":
            guard !paths.isEmpty else { throw .missingArgument("a font file or folder") }
            result = .scan(paths: paths, json: json)
        default:
            guard let recipe = paths.first else { throw .missingArgument("a recipe file") }
            guard paths.count == 1 else { throw .unexpectedArgument(paths[1]) }
            guard let out else { throw .missingArgument("--out") }
            result = .forge(
                recipe: recipe, out: out, fontDirectories: directories, allowMissing: allowMissing, json: json,
                quiet: quiet)
        }
        return Invocation(enginePath: engine, verbose: verbose, command: result)
    }
}
