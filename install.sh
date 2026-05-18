#!/usr/bin/env bash
# One-shot installer for ClaudeHotkeys.spoon.
#   curl -sSL https://raw.githubusercontent.com/<you>/ClaudeHotkeys.spoon/main/install.sh | bash
set -euo pipefail

SPOON_DIR="$HOME/.hammerspoon/Spoons/ClaudeHotkeys.spoon"
REPO_RAW="${CLAUDEHK_REPO_RAW:-https://raw.githubusercontent.com/tomellsworth/ClaudeHotkeys.spoon/main}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }

# Sanity checks
if ! command -v swiftc >/dev/null 2>&1; then
    warn "swiftc not found. The OCR hotkey needs Xcode CLT."
    warn "Install with: xcode-select --install"
fi

if ! [ -d "/Applications/Hammerspoon.app" ] && ! [ -d "$HOME/Applications/Hammerspoon.app" ]; then
    warn "Hammerspoon not found in /Applications. Install with:"
    warn "    brew install --cask hammerspoon"
fi

mkdir -p "$SPOON_DIR"
bold "Fetching ClaudeHotkeys.spoon → $SPOON_DIR"
for file in init.lua ocr.swift README.md LICENSE; do
    curl -fsSL "$REPO_RAW/$file" -o "$SPOON_DIR/$file"
    printf '  ✓ %s\n' "$file"
done

INIT="$HOME/.hammerspoon/init.lua"
SNIPPET='hs.loadSpoon("ClaudeHotkeys"); spoon.ClaudeHotkeys:start()'

if [ -f "$INIT" ] && grep -q "ClaudeHotkeys" "$INIT"; then
    bold "$INIT already references ClaudeHotkeys — skipping config edit."
else
    bold "Adding load line to $INIT"
    touch "$INIT"
    printf '\n-- ClaudeHotkeys: keyboard namespace for Claude-aware actions\n%s\n' "$SNIPPET" >> "$INIT"
fi

bold "Done."
echo
echo "Next steps:"
echo "  1. Open Hammerspoon (Applications → Hammerspoon)."
echo "  2. Click the Hammerspoon menu bar icon → Reload Config."
echo "  3. Grant Accessibility + Screen Recording permissions when prompted."
echo
echo "Try it: ⌃⌥⇧ + 4 to capture a region; check ~/.claude/scratchpad/screenshots/"
