# ClaudeHotkeys.spoon

A reserved keyboard "namespace" for Claude-aware actions on macOS.

Bind a single chord (`⌃⌥⇧` by default — control + option + shift) plus a letter or number to:

| Hotkey | Action | Result |
|---|---|---|
| `⌃⌥⇧-4` | Region screenshot | PNG saved to `~/.claude/scratchpad/screenshots/`, path on clipboard |
| `⌃⌥⇧-5` | Full-screen screenshot | PNG saved, path on clipboard |
| `⌃⌥⇧-C` | Selection / clipboard text | `.txt` saved to `~/.claude/scratchpad/text/` |
| `⌃⌥⇧-T` | Region → **OCR** (Vision framework) | Text saved + put on clipboard |
| `⌃⌥⇧-M` | Save clipboard as a Claude *memory* note | `.md` with proper frontmatter, indexed in `MEMORY.md` |
| `⌃⌥⇧-F` | Reveal scratchpad in Finder | — |

The point: a single keyboard pattern that doesn't fight with `⌘`-shortcuts in apps, doesn't pollute the system clipboard, and parks everything in a directory the Claude CLI / Claude Code can read directly.

## Install

### Prerequisites
- macOS 13+ (Vision OCR needs this)
- [Hammerspoon](https://www.hammerspoon.org/): `brew install --cask hammerspoon`
- Xcode Command Line Tools (for the OCR helper to compile): `xcode-select --install`

### Install the Spoon

```bash
git clone https://github.com/<you>/ClaudeHotkeys.spoon \
    ~/.hammerspoon/Spoons/ClaudeHotkeys.spoon
```

Then add to your `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("ClaudeHotkeys")
spoon.ClaudeHotkeys:start()
```

Reload Hammerspoon. First run will:
1. Compile the OCR helper (Swift one-file, uses Vision framework)
2. Create `~/.claude/scratchpad/{screenshots,text,ocr}/`
3. Show a banner confirming hotkeys are loaded

macOS will prompt for **Accessibility** (for the global hotkeys) and **Screen Recording** (for `screencapture`) permissions. Grant both.

## Configuration

All optional — override before `:start()`:

```lua
hs.loadSpoon("ClaudeHotkeys")

-- Customize paths
spoon.ClaudeHotkeys.scratchpadPath = "~/my-claude-scratchpad"
spoon.ClaudeHotkeys.projectsPath = "~/.claude/projects"  -- for memory hotkey

-- Different modifier (default is ⌃⌥⇧)
spoon.ClaudeHotkeys.modifier = {"cmd", "shift"}

-- Or rebind individual hotkeys
spoon.ClaudeHotkeys:bindHotkeys({
    screenshot = {{"ctrl", "alt", "shift"}, "4"},
    fullscreen = {{"ctrl", "alt", "shift"}, "5"},
    text       = {{"ctrl", "alt", "shift"}, "C"},
    ocr        = {{"ctrl", "alt", "shift"}, "T"},
    memory     = {{"ctrl", "alt", "shift"}, "M"},
    reveal     = {{"ctrl", "alt", "shift"}, "F"},
})

-- Silence banner notifications
spoon.ClaudeHotkeys.notifications = false

spoon.ClaudeHotkeys:start()
```

## How the memory hotkey decides where to save

`⌃⌥⇧-M` saves the current clipboard text as a Claude memory note. It picks the destination project by **most-recently-modified `MEMORY.md`** under `~/.claude/projects/*/memory/`. So whichever Claude project you've been working in most recently is where the new memory lands.

You'll get a prompt for:
1. A descriptive name (becomes the `name:` field and filename slug)
2. A type (`user` / `feedback` / `project` / `reference`)

The note is written with proper frontmatter and the file is added to that project's `MEMORY.md` index.

## Files saved

```
~/.claude/scratchpad/
├── screenshots/        ⌃⌥⇧-4, ⌃⌥⇧-5
├── text/               ⌃⌥⇧-C
└── ocr/                ⌃⌥⇧-T
```

Filenames are UTC timestamps (`2026-05-18T13-55-42Z.png`) so they sort chronologically.

## Why a "namespace" chord?

`⌃⌥⇧` is rarely used by macOS or third-party apps (most use `⌘` plus one or two other modifiers). Reserving it for Claude actions means:

- No conflicts with app shortcuts
- Single mental model: "if I'm doing a Claude thing, hold the chord"
- Easy to extend — add `⌃⌥⇧-G` for "summarize this and send to Claude" later

## License

MIT — see [LICENSE](LICENSE).
