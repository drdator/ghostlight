import AppKit
import Carbon

enum GhostlightSessionMode: String, Codable {
    case fresh
    case persistent
}

struct GhostlightProfile {
    var name: String = ""
    var windowWidth: CGFloat?
    var windowHeight: CGFloat?
    var windowPadding: CGFloat?
    var cornerRadius: CGFloat?
    var innerCornerRadius: CGFloat?
    var fontSize: Float?
    var workingDirectory: String?
    var sessionMode: String?
    var hotkey: String?
    var command: String?
    var prewarm: Bool?
    var borderColor: String?
    var paddingColor: String?

    static func parse(_ dict: [String: Any]) -> GhostlightProfile {
        var p = GhostlightProfile()
        if let v = dict["name"] as? String { p.name = v }
        if let v = dict["window_width"] as? CGFloat { p.windowWidth = v }
        if let v = dict["window_height"] as? CGFloat { p.windowHeight = v }
        if let v = dict["window_padding"] as? CGFloat { p.windowPadding = v }
        if let v = dict["corner_radius"] as? CGFloat { p.cornerRadius = v }
        if let v = dict["inner_corner_radius"] as? CGFloat { p.innerCornerRadius = v }
        if let v = dict["font_size"] as? Double { p.fontSize = Float(v) }
        if let v = dict["working_directory"] as? String { p.workingDirectory = v }
        if let v = dict["session_mode"] as? String { p.sessionMode = v }
        if let v = dict["hotkey"] as? String { p.hotkey = v }
        if let v = dict["command"] as? String { p.command = v }
        if let v = dict["prewarm"] as? Bool { p.prewarm = v }
        if let v = dict["border_color"] as? String { p.borderColor = v }
        if let v = dict["padding_color"] as? String { p.paddingColor = v }
        return p
    }
}

struct GhostlightConfig: Codable {
    var windowWidth: CGFloat = 720
    var windowHeight: CGFloat = 300
    var windowPadding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var innerCornerRadius: CGFloat = 0 // 0 = no rounding on terminal view
    var fontSize: Float = 0 // 0 = use Ghostty default
    var workingDirectory: String = "" // empty = user home directory
    var sessionMode: GhostlightSessionMode = .fresh
    var hotkey: String = "opt+space" // e.g. "opt+space", "ctrl+`", "cmd+shift+t"
    var command: String = "" // command to run in the shell, e.g. "claude"
    var prewarm: Bool = true // prewarm shell + command in background so it's ready instantly
    var borderColor: String = "" // empty = no border, hex like "#3a3f4b"
    var paddingColor: String = "" // empty = use ghostty background

    // Not serialized — populated during load
    var profiles: [GhostlightProfile] = []

    enum CodingKeys: String, CodingKey {
        case windowWidth, windowHeight, windowPadding, cornerRadius, innerCornerRadius
        case fontSize, workingDirectory, sessionMode, hotkey, command, prewarm
        case borderColor, paddingColor
    }

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghostlight")
    static let settingsFile = configDir.appendingPathComponent("settings.json")
    static let legacyConfigFile = configDir.appendingPathComponent("config.json")

    private static func loadFile() -> URL? {
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            return settingsFile
        }
        if FileManager.default.fileExists(atPath: legacyConfigFile.path) {
            return legacyConfigFile
        }
        return nil
    }

    static func load() -> GhostlightConfig {
        guard let configFile = loadFile() else {
            let config = GhostlightConfig()
            config.save()
            return config
        }

        do {
            let data = try Data(contentsOf: configFile)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return GhostlightConfig()
            }
            var cfg = GhostlightConfig()
            cfg.applyJSON(json)

            if let profilesArray = json["profiles"] as? [[String: Any]] {
                cfg.profiles = profilesArray.map { GhostlightProfile.parse($0) }
            }

            return cfg
        } catch {
            fputs("ghostlight: failed to read config: \(error)\n", stderr)
            return GhostlightConfig()
        }
    }

    mutating func applyJSON(_ json: [String: Any]) {
        if let v = json["window_width"] as? CGFloat { windowWidth = v }
        if let v = json["window_height"] as? CGFloat { windowHeight = v }
        if let v = json["window_padding"] as? CGFloat { windowPadding = v }
        if let v = json["corner_radius"] as? CGFloat { cornerRadius = v }
        if let v = json["inner_corner_radius"] as? CGFloat { innerCornerRadius = v }
        if let v = json["font_size"] as? Double { fontSize = Float(v) }
        if let v = json["working_directory"] as? String { workingDirectory = v }
        if let v = json["session_mode"] as? String {
            sessionMode = GhostlightSessionMode(rawValue: v.lowercased()) ?? .fresh
        }
        if let v = json["hotkey"] as? String { hotkey = v }
        if let v = json["command"] as? String { command = v }
        if let v = json["prewarm"] as? Bool { prewarm = v }
        if let v = json["border_color"] as? String { borderColor = v }
        if let v = json["padding_color"] as? String { paddingColor = v }
    }

    func resolved(with profile: GhostlightProfile) -> GhostlightConfig {
        var cfg = self
        cfg.profiles = []
        if let v = profile.windowWidth { cfg.windowWidth = v }
        if let v = profile.windowHeight { cfg.windowHeight = v }
        if let v = profile.windowPadding { cfg.windowPadding = v }
        if let v = profile.cornerRadius { cfg.cornerRadius = v }
        if let v = profile.innerCornerRadius { cfg.innerCornerRadius = v }
        if let v = profile.fontSize { cfg.fontSize = v }
        if let v = profile.workingDirectory { cfg.workingDirectory = v }
        if let v = profile.sessionMode {
            cfg.sessionMode = GhostlightSessionMode(rawValue: v.lowercased()) ?? cfg.sessionMode
        }
        if let v = profile.hotkey { cfg.hotkey = v }
        if let v = profile.command { cfg.command = v }
        if let v = profile.prewarm { cfg.prewarm = v }
        if let v = profile.borderColor { cfg.borderColor = v }
        if let v = profile.paddingColor { cfg.paddingColor = v }
        return cfg
    }

    static func parseHex(_ str: String) -> NSColor? {
        var hex = str.trimmingCharacters(in: .whitespaces)
        guard !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard (hex.count == 6 || hex.count == 8), let val = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 8 {
            return NSColor(
                red: CGFloat((val >> 24) & 0xFF) / 255.0,
                green: CGFloat((val >> 16) & 0xFF) / 255.0,
                blue: CGFloat((val >> 8) & 0xFF) / 255.0,
                alpha: CGFloat(val & 0xFF) / 255.0
            )
        }
        return NSColor(
            red: CGFloat((val >> 16) & 0xFF) / 255.0,
            green: CGFloat((val >> 8) & 0xFF) / 255.0,
            blue: CGFloat(val & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    func parsedBorderColor() -> NSColor? { Self.parseHex(borderColor) }
    func parsedPaddingColor() -> NSColor? { Self.parseHex(paddingColor) }

    func requiresSurfaceRecreation(comparedTo other: GhostlightConfig) -> Bool {
        fontSize != other.fontSize || resolvedWorkingDirectory() != other.resolvedWorkingDirectory()
    }

    private func resolvedWorkingDirectory() -> String {
        guard workingDirectory.hasPrefix("~") else { return workingDirectory }
        return NSString(string: workingDirectory).expandingTildeInPath
    }

    func hotkeyDisplayString() -> String {
        hotkey
            .split(separator: "+")
            .map {
                let token = $0.lowercased().trimmingCharacters(in: .whitespaces)
                switch token {
                case "opt", "option", "alt":
                    return "Opt"
                case "cmd", "command":
                    return "Cmd"
                case "ctrl", "control":
                    return "Ctrl"
                case "shift":
                    return "Shift"
                case "space":
                    return "Space"
                case "return", "enter":
                    return "Enter"
                case "escape", "esc":
                    return "Esc"
                case "backtick", "grave":
                    return "`"
                default:
                    let part = String($0).trimmingCharacters(in: .whitespaces)
                    return part.count == 1 ? part.uppercased() : part.capitalized
                }
            }
            .joined(separator: "+")
    }

    func parsedHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var mods: UInt32 = 0
        var key: String = ""

        for part in parts {
            switch part {
            case "opt", "option", "alt": mods |= UInt32(optionKey)
            case "cmd", "command":       mods |= UInt32(cmdKey)
            case "ctrl", "control":      mods |= UInt32(controlKey)
            case "shift":                mods |= UInt32(shiftKey)
            default:                     key = part
            }
        }

        let keyCode: UInt32 = switch key {
        case "space":                    UInt32(kVK_Space)
        case "`", "backtick", "grave":   UInt32(kVK_ANSI_Grave)
        case "tab":                      UInt32(kVK_Tab)
        case "return", "enter":          UInt32(kVK_Return)
        case "escape", "esc":            UInt32(kVK_Escape)
        case "a": UInt32(kVK_ANSI_A)
        case "b": UInt32(kVK_ANSI_B)
        case "c": UInt32(kVK_ANSI_C)
        case "d": UInt32(kVK_ANSI_D)
        case "e": UInt32(kVK_ANSI_E)
        case "f": UInt32(kVK_ANSI_F)
        case "g": UInt32(kVK_ANSI_G)
        case "h": UInt32(kVK_ANSI_H)
        case "i": UInt32(kVK_ANSI_I)
        case "j": UInt32(kVK_ANSI_J)
        case "k": UInt32(kVK_ANSI_K)
        case "l": UInt32(kVK_ANSI_L)
        case "m": UInt32(kVK_ANSI_M)
        case "n": UInt32(kVK_ANSI_N)
        case "o": UInt32(kVK_ANSI_O)
        case "p": UInt32(kVK_ANSI_P)
        case "q": UInt32(kVK_ANSI_Q)
        case "r": UInt32(kVK_ANSI_R)
        case "s": UInt32(kVK_ANSI_S)
        case "t": UInt32(kVK_ANSI_T)
        case "u": UInt32(kVK_ANSI_U)
        case "v": UInt32(kVK_ANSI_V)
        case "w": UInt32(kVK_ANSI_W)
        case "x": UInt32(kVK_ANSI_X)
        case "y": UInt32(kVK_ANSI_Y)
        case "z": UInt32(kVK_ANSI_Z)
        case "0": UInt32(kVK_ANSI_0)
        case "1": UInt32(kVK_ANSI_1)
        case "2": UInt32(kVK_ANSI_2)
        case "3": UInt32(kVK_ANSI_3)
        case "4": UInt32(kVK_ANSI_4)
        case "5": UInt32(kVK_ANSI_5)
        case "6": UInt32(kVK_ANSI_6)
        case "7": UInt32(kVK_ANSI_7)
        case "8": UInt32(kVK_ANSI_8)
        case "9": UInt32(kVK_ANSI_9)
        case "-", "minus":       UInt32(kVK_ANSI_Minus)
        case "=", "equal":       UInt32(kVK_ANSI_Equal)
        case "[":                UInt32(kVK_ANSI_LeftBracket)
        case "]":                UInt32(kVK_ANSI_RightBracket)
        case ";", "semicolon":   UInt32(kVK_ANSI_Semicolon)
        case "'", "quote":       UInt32(kVK_ANSI_Quote)
        case ",", "comma":       UInt32(kVK_ANSI_Comma)
        case ".", "period":      UInt32(kVK_ANSI_Period)
        case "/", "slash":       UInt32(kVK_ANSI_Slash)
        case "\\", "backslash":  UInt32(kVK_ANSI_Backslash)
        case "f1":  UInt32(kVK_F1)
        case "f2":  UInt32(kVK_F2)
        case "f3":  UInt32(kVK_F3)
        case "f4":  UInt32(kVK_F4)
        case "f5":  UInt32(kVK_F5)
        case "f6":  UInt32(kVK_F6)
        case "f7":  UInt32(kVK_F7)
        case "f8":  UInt32(kVK_F8)
        case "f9":  UInt32(kVK_F9)
        case "f10": UInt32(kVK_F10)
        case "f11": UInt32(kVK_F11)
        case "f12": UInt32(kVK_F12)
        default:     UInt32(kVK_Space) // fallback
        }

        return (keyCode, mods)
    }

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.settingsFile)
        } catch {
            fputs("ghostlight: failed to write config: \(error)\n", stderr)
        }
    }
}
