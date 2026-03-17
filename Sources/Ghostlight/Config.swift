import AppKit

struct GhostlightConfig: Codable {
    var windowWidth: CGFloat = 720
    var windowHeight: CGFloat = 300
    var windowPadding: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var fontSize: Float = 0 // 0 = use Ghostty default
    var borderColor: String = "" // empty = no border, hex like "#3a3f4b"
    var paddingColor: String = "" // empty = use ghostty background

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ghostlight")
    static let configFile = configDir.appendingPathComponent("config.json")

    static func load() -> GhostlightConfig {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            let config = GhostlightConfig()
            config.save()
            return config
        }

        do {
            let data = try Data(contentsOf: configFile)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return GhostlightConfig()
            }
            // Merge with defaults so missing keys use default values
            var cfg = GhostlightConfig()
            if let v = json["window_width"] as? CGFloat { cfg.windowWidth = v }
            if let v = json["window_height"] as? CGFloat { cfg.windowHeight = v }
            if let v = json["window_padding"] as? CGFloat { cfg.windowPadding = v }
            if let v = json["corner_radius"] as? CGFloat { cfg.cornerRadius = v }
            if let v = json["font_size"] as? Double { cfg.fontSize = Float(v) }
            if let v = json["border_color"] as? String { cfg.borderColor = v }
            if let v = json["padding_color"] as? String { cfg.paddingColor = v }
            return cfg
        } catch {
            fputs("ghostlight: failed to read config: \(error)\n", stderr)
            return GhostlightConfig()
        }
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

    func save() {
        do {
            try FileManager.default.createDirectory(
                at: Self.configDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: Self.configFile)
        } catch {
            fputs("ghostlight: failed to write config: \(error)\n", stderr)
        }
    }
}
