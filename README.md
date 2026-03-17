# Ghostlight

A Spotlight-like floating terminal for macOS, powered by [libghostty](https://github.com/ghostty-org/ghostty).

Press **Option+Space** to summon a terminal by default. Press it again to dismiss. Each invocation starts a fresh shell.

## Features

- Configurable global hotkey toggles a floating terminal
- Powered by libghostty — uses your existing [Ghostty](https://ghostty.org) config and theme
- Configurable fresh or persistent sessions (`fresh` pre-spawns the next shell for instant launch)
- Runs as a menu bar app (no dock icon)
- Configurable window size, padding, corner radius, colors, font size, and working directory
- Cmd+C / Cmd+V clipboard support

## Requirements

- macOS 13+
- [Xcode](https://developer.apple.com/xcode/) (full install, not just Command Line Tools — needed for Metal shader compiler)
- [Zig](https://ziglang.org/) (`brew install zig`)

## Quick Start

```bash
git clone https://github.com/drdator/ghostlight.git
cd ghostlight

# Clone Ghostty and build libghostty (first time only, takes a few minutes)
./scripts/setup.sh

# Build and run
make run
```

By default, setup.sh clones Ghostty to `~/ghostty`. Override with:

```bash
GHOSTTY_DIR=/path/to/ghostty ./scripts/setup.sh
make run GHOSTTY_DIR=/path/to/ghostty
```

## Configuration

Ghostlight creates a config file at `~/.ghostlight/settings.json` on first run:

```json
{
  "window_width": 720,
  "window_height": 300,
  "window_padding": 16,
  "corner_radius": 12,
  "inner_corner_radius": 0,
  "font_size": 0,
  "working_directory": "",
  "session_mode": "fresh",
  "hotkey": "opt+space",
  "border_color": "",
  "padding_color": ""
}
```

| Setting | Description |
|---|---|
| `window_width` / `window_height` | Panel dimensions in points |
| `window_padding` | Space between panel edge and terminal |
| `corner_radius` | Outer corner radius of the panel |
| `inner_corner_radius` | Corner radius of the terminal view inside the padding |
| `font_size` | Terminal font size (`0` = use Ghostty default) |
| `working_directory` | Shell starting directory (`""` = home, supports `~`) |
| `session_mode` | `"fresh"` starts a new shell on every open, `"persistent"` reuses the same shell until it exits |
| `hotkey` | Global shortcut string such as `opt+space`, `ctrl+grave`, or `cmd+shift+t` |
| `border_color` | Panel border color as `#rrggbb` or `#rrggbbaa` (`""` = no border) |
| `padding_color` | Padding area color, blended over Ghostty theme background (`""` = theme color, `#00000033` = slightly darker) |

Config is reloaded every time you open the panel. You can also reload via **GL menu > Reload Config** in the menu bar.
If you already have `~/.ghostlight/config.json`, Ghostlight will keep reading it as a legacy fallback.

## Building an App Bundle

```bash
make bundle GHOSTTY_DIR=~/ghostty
# Creates Ghostlight.app in the project directory
```

## How It Works

Ghostlight embeds [libghostty](https://github.com/ghostty-org/ghostty) — the same terminal engine that powers the Ghostty terminal emulator. It renders via Metal into a floating NSPanel and forwards keyboard/mouse events to the ghostty surface. Your Ghostty config (`~/.config/ghostty/config`) is loaded automatically, so themes, fonts, and keybindings carry over.

## License

MIT
