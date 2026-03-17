#!/usr/bin/env bash
set -euo pipefail

GHOSTTY_DIR="${GHOSTTY_DIR:-$HOME/ghostty}"
ZIG_OPTIMIZE="${ZIG_OPTIMIZE:-ReleaseFast}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
DIM='\033[0;90m'
RESET='\033[0m'

info() { echo -e "${GREEN}==>${RESET} $*"; }
warn() { echo -e "${RED}==>${RESET} $*"; }
dim()  { echo -e "${DIM}    $*${RESET}"; }

# --- Check prerequisites ---

if ! command -v zig &>/dev/null; then
    warn "Zig is required but not installed."
    dim  "Install via: brew install zig"
    exit 1
fi

if ! command -v swift &>/dev/null; then
    warn "Swift toolchain is required but not found."
    dim  "Install Xcode or Xcode Command Line Tools."
    exit 1
fi

# Ensure DEVELOPER_DIR points to full Xcode (needed for Metal shader compiler)
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ ! -d "$DEVELOPER_DIR" ]; then
    warn "Xcode not found at $DEVELOPER_DIR"
    dim  "Install Xcode from the App Store or set DEVELOPER_DIR."
    exit 1
fi
export DEVELOPER_DIR

if ! xcrun -f metal &>/dev/null; then
    warn "Metal shader compiler not found."
    dim  "Make sure Xcode is installed (not just Command Line Tools)."
    exit 1
fi

# --- Clone Ghostty ---

if [ -d "$GHOSTTY_DIR" ]; then
    info "Ghostty source found at $GHOSTTY_DIR"
    dim  "Pulling latest changes..."
    git -C "$GHOSTTY_DIR" pull --ff-only 2>/dev/null || true
else
    info "Cloning Ghostty into $GHOSTTY_DIR..."
    git clone https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
fi

# --- Patch build.zig to skip XCFramework (requires iOS SDK / full Xcode) ---

BUILDZIG="$GHOSTTY_DIR/build.zig"
if ! grep -q "emit_xcframework or config.emit_macos_app" "$BUILDZIG" 2>/dev/null; then
    info "Patching build.zig to skip XCFramework when not requested..."

    # Patch 1: Guard XCFramework init behind emit_xcframework flag
    sed -i.bak '
    /macOS only artifacts/,/^    }/ {
        s/if (config\.target\.result\.os\.tag\.isDarwin()) {/if (config.target.result.os.tag.isDarwin()) {\
        if (config.emit_xcframework or config.emit_macos_app) {/
        /if (config\.emit_macos_app) {/{
            N
            s/}$/}\
        }\
\
        \/\/ Install libghostty for Darwin when not building xcframework\
        libghostty_shared.installHeader();\
        libghostty_static.install("libghostty.a");/
        }
    }' "$BUILDZIG"

    # Patch 2: Guard the run-step XCFramework behind emit_xcframework
    sed -i.bak '
    /On macOS we can run the macOS app/,/^        }/ {
        s/if (config\.target\.result\.os\.tag\.isDarwin()) {/if (config.target.result.os.tag.isDarwin() and config.emit_xcframework) {/
    }' "$BUILDZIG"

    rm -f "$BUILDZIG.bak"
    dim  "Patched."
else
    dim  "build.zig already patched."
fi

# --- Build libghostty ---

info "Building libghostty ($ZIG_OPTIMIZE)..."
dim  "This may take a few minutes on first build."

cd "$GHOSTTY_DIR"
zig build \
    -Doptimize="$ZIG_OPTIMIZE" \
    -Dapp-runtime=none \
    -Demit-xcframework=false \
    2>&1 | tail -5

LIBPATH="$GHOSTTY_DIR/zig-out/lib/libghostty.a"
if [ ! -f "$LIBPATH" ]; then
    warn "Build failed — libghostty.a not found."
    exit 1
fi

LIBSIZE=$(du -h "$LIBPATH" | cut -f1)
info "libghostty built successfully ($LIBSIZE)"
dim  "$LIBPATH"

# --- Done ---

echo ""
info "Setup complete. Build Ghostlight with:"
dim  "make build GHOSTTY_DIR=$GHOSTTY_DIR"
echo ""
dim  "Or run directly:"
dim  "make run GHOSTTY_DIR=$GHOSTTY_DIR"
