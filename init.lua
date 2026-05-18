--- === ClaudeHotkeys ===
---
--- A reserved keyboard "namespace" for Claude-aware actions.
---
--- Bind a chord (⌃⌥⇧ by default) plus a letter/number to capture screenshots,
--- text, or OCR'd regions directly into `~/.claude/scratchpad/` — where the
--- Claude CLI / Claude Code can read them — without polluting the system
--- clipboard. Plus a hotkey that saves your current clipboard as a properly-
--- frontmattered note in your Claude memory directory.
---
--- Install: drop this folder into ~/.hammerspoon/Spoons/, then in your
--- Hammerspoon init.lua:
---     hs.loadSpoon("ClaudeHotkeys")
---     spoon.ClaudeHotkeys:start()
---
--- Optional config before :start():
---     spoon.ClaudeHotkeys.scratchpadPath = "/path/of/your/choice"
---     spoon.ClaudeHotkeys.modifier = {"cmd", "shift"}
---     spoon.ClaudeHotkeys:bindHotkeys({
---         screenshot = {{"ctrl","alt","shift"}, "4"},
---         fullscreen = {{"ctrl","alt","shift"}, "5"},
---         text       = {{"ctrl","alt","shift"}, "C"},
---         ocr        = {{"ctrl","alt","shift"}, "T"},
---         memory     = {{"ctrl","alt","shift"}, "M"},
---         reveal     = {{"ctrl","alt","shift"}, "F"},
---     })

local obj = {}
obj.__index = obj

obj.name = "ClaudeHotkeys"
obj.version = "0.2.0"
obj.author = "Tom Ellsworth"
obj.homepage = "https://github.com/tomellsworth/ClaudeHotkeys.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- Configuration (override before :start())
obj.scratchpadPath = nil      -- defaults to ~/.claude/scratchpad
obj.projectsPath = nil        -- defaults to ~/.claude/projects (for memory hotkey)
obj.activeProjectFile = nil   -- defaults to ~/.claude/active-project (one project slug per line)
obj.ocrBinPath = nil          -- defaults to ~/.claude/bin/ocr (compiled on first start)
obj.modifier = {"ctrl", "alt", "shift"}
obj.notifications = true      -- show banner notifications on each capture
obj.hotkeyMap = nil           -- user-provided override map

-- Internal state
obj._hotkeys = {}
obj._spoonPath = hs.spoons.scriptPath()  -- absolute path to this Spoon dir

-- ──────────────────────────────────────────────────────────────────────
-- helpers

local function home() return os.getenv("HOME") end

local function expandTilde(path)
    if not path then return nil end
    return path:gsub("^~", home())
end

local function timestamp()
    return os.date("!%Y-%m-%dT%H-%M-%SZ")
end

local function notify(self, title, info)
    if not self.notifications then return end
    hs.notify.new({title = title, informativeText = info or "", withdrawAfter = 4}):send()
end

local function writeFile(path, content)
    local f, err = io.open(path, "w")
    if not f then return false, err end
    f:write(content)
    f:close()
    return true
end

local function ensureDir(path)
    hs.fs.mkdir(path)
end

-- Compile the OCR helper if its source ships next to the Spoon and the
-- compiled binary doesn't exist (or is older than the source).
local function ensureOCRCompiled(self)
    local bin = self.ocrBinPath
    local source = self._spoonPath .. "/ocr.swift"
    local sourceAttrs = hs.fs.attributes(source)
    if not sourceAttrs then return false end  -- no source, can't help

    local binAttrs = hs.fs.attributes(bin)
    if binAttrs and binAttrs.modification >= sourceAttrs.modification then
        return true  -- already up to date
    end

    ensureDir(bin:match("(.*)/[^/]+$"))
    local cmd = string.format("swiftc %q -o %q", source, bin)
    local ok = hs.execute(cmd)
    if ok then
        return true
    else
        hs.alert("ClaudeHotkeys: OCR compile failed — install Xcode CLT (xcode-select --install)")
        return false
    end
end

-- ──────────────────────────────────────────────────────────────────────
-- hotkey actions

function obj:_screenshotRegion()
    local path = self.scratchpadPath .. "/screenshots/" .. timestamp() .. ".png"
    hs.task.new("/usr/sbin/screencapture", function(rc)
        if rc == 0 and hs.fs.attributes(path) then
            hs.pasteboard.setContents(path)
            notify(self, "Screenshot → Claude", "Path on clipboard")
        end
    end, {"-i", "-t", "png", path}):start()
end

function obj:_screenshotFull()
    local path = self.scratchpadPath .. "/screenshots/" .. timestamp() .. ".png"
    hs.task.new("/usr/sbin/screencapture", function(rc)
        if rc == 0 and hs.fs.attributes(path) then
            hs.pasteboard.setContents(path)
            notify(self, "Full screenshot → Claude", path)
        end
    end, {"-m", "-t", "png", path}):start()
end

function obj:_captureText()
    hs.eventtap.keyStroke({"cmd"}, "c", 50000)
    hs.timer.doAfter(0.18, function()
        local text = hs.pasteboard.getContents() or ""
        if #text == 0 then
            notify(self, "Capture failed", "Clipboard was empty")
            return
        end
        local path = self.scratchpadPath .. "/text/" .. timestamp() .. ".txt"
        if writeFile(path, text) then
            notify(self, "Text → Claude", string.format("%d chars saved", #text))
        end
    end)
end

function obj:_ocrRegion()
    if not ensureOCRCompiled(self) then return end
    local ts = timestamp()
    local tmpImg = "/tmp/claude_ocr_" .. ts .. ".png"
    hs.task.new("/usr/sbin/screencapture", function(rc)
        if rc ~= 0 or not hs.fs.attributes(tmpImg) then return end
        local t = hs.task.new(self.ocrBinPath, function(rcOcr, stdout, stderr)
            if rcOcr ~= 0 then
                notify(self, "OCR failed", stderr or "")
                return
            end
            local path = self.scratchpadPath .. "/ocr/" .. ts .. ".txt"
            writeFile(path, stdout)
            hs.pasteboard.setContents(stdout)
            os.remove(tmpImg)
            local lines = select(2, string.gsub(stdout, "\n", "")) + 1
            notify(self, "OCR → Claude", string.format("%d lines, text on clipboard", lines))
        end, {tmpImg})
        t:start()
    end, {"-i", "-t", "png", tmpImg}):start()
end

-- Resolve which project's memory directory we should write to.
-- Priority: (1) sentinel file ~/.claude/active-project, (2) most-recently-
-- touched MEMORY.md, (3) most-recently-touched memory directory.
function obj:_resolveMemoryDir()
    -- (1) Sentinel file
    local sentinel = self.activeProjectFile
    local sentinelAttrs = hs.fs.attributes(sentinel)
    if sentinelAttrs and sentinelAttrs.mode == "file" then
        local f = io.open(sentinel, "r")
        if f then
            local slug = (f:read("*l") or ""):gsub("^%s+", ""):gsub("%s+$", "")
            f:close()
            if #slug > 0 then
                local memDir = self.projectsPath .. "/" .. slug .. "/memory"
                local attrs = hs.fs.attributes(memDir)
                if attrs and attrs.mode == "directory" then
                    return memDir, "sentinel"
                end
            end
        end
    end

    -- (2) Most-recently-modified MEMORY.md
    local bestByIdx, latestIdx = nil, 0
    -- (3) Fallback: most-recently-modified directory
    local bestByDir, latestDir = nil, 0
    for proj in hs.fs.dir(self.projectsPath) do
        if proj:sub(1, 1) ~= "." then
            local memDir = self.projectsPath .. "/" .. proj .. "/memory"
            local memAttrs = hs.fs.attributes(memDir)
            if memAttrs and memAttrs.mode == "directory" then
                local idx = memDir .. "/MEMORY.md"
                local idxAttrs = hs.fs.attributes(idx)
                if idxAttrs and idxAttrs.modification > latestIdx then
                    latestIdx = idxAttrs.modification
                    bestByIdx = memDir
                end
                if memAttrs.modification > latestDir then
                    latestDir = memAttrs.modification
                    bestByDir = memDir
                end
            end
        end
    end
    if bestByIdx then return bestByIdx, "newest-MEMORY.md" end
    if bestByDir then return bestByDir, "newest-dir" end
    return nil, "none"
end

-- Write a memory file + append index line. Shared by both `_saveToMemory`
-- (clipboard) and `_saveNote` (free-form input).
function obj:_writeMemoryNote(target, name, mtype, body)
    local slug = name:gsub("[^%w_]", "_"):lower()
    local filename = mtype .. "_" .. slug .. ".md"
    local path = target .. "/" .. filename

    local firstLine = body:match("^[^\n]+") or name
    if #firstLine > 120 then firstLine = firstLine:sub(1, 117) .. "..." end

    local fileBody = string.format(
        "---\nname: %s\ndescription: %s\ntype: %s\n---\n\n%s\n",
        name, firstLine, mtype, body
    )
    writeFile(path, fileBody)

    local idx = target .. "/MEMORY.md"
    if hs.fs.attributes(idx) then
        local f = io.open(idx, "a")
        if f then
            f:write(string.format("- [%s](%s) — %s\n", name, filename, firstLine))
            f:close()
        end
    end
    return filename
end

local function chooseTypeAndCommit(self, target, name, body)
    local chooser
    chooser = hs.chooser.new(function(choice)
        if not choice then return end
        local filename = self:_writeMemoryNote(target, name, choice.text, body)
        notify(self, "Memory saved", target:match("[^/]+/memory$") .. "/" .. filename)
    end)
    chooser:choices({
        {text = "user",      subText = "Who the user is, their role, preferences"},
        {text = "feedback",  subText = "Guidance on how to approach work"},
        {text = "project",   subText = "Facts about ongoing work / decisions"},
        {text = "reference", subText = "Pointers to external resources"},
    })
    chooser:show()
end

function obj:_saveToMemory()
    local text = hs.pasteboard.getContents()
    if not text or #text == 0 then
        notify(self, "No memory saved", "Clipboard is empty")
        return
    end

    -- Soft warning: if clipboard is just a short file path, that's almost
    -- certainly not what the user meant to save as a memory.
    local stripped = text:gsub("^%s+", ""):gsub("%s+$", "")
    if not stripped:find("\n") and #stripped < 300 and (stripped:match("^/") or stripped:match("^~")) then
        local attrs = hs.fs.attributes(stripped:gsub("^~", os.getenv("HOME")))
        if attrs then
            local proceed = hs.dialog.blockAlert(
                "Clipboard looks like a file path",
                "The clipboard contains just a path — probably not what you want as a memory.\n\nPath: " .. stripped,
                "Save anyway", "Cancel"
            )
            if proceed ~= "Save anyway" then return end
        end
    end

    local target, source = self:_resolveMemoryDir()
    if not target then
        notify(self, "No memory dir", "Couldn't find a Claude project's memory folder")
        return
    end

    local btn, name = hs.dialog.textPrompt(
        "Save to Claude memory",
        string.format("Memory file name (no extension)\nProject: %s [%s]",
            target:match("projects/([^/]+)/memory$") or "?", source),
        "", "Next…", "Cancel"
    )
    if btn ~= "Next…" or not name or #name == 0 then return end

    chooseTypeAndCommit(self, target, name, text)
end

-- ⌃⌥⇧-N: free-form note. Multi-line text dialog → memory file.
function obj:_saveNote()
    local target, source = self:_resolveMemoryDir()
    if not target then
        notify(self, "No memory dir", "Couldn't find a Claude project's memory folder")
        return
    end

    -- hs.dialog.textPrompt is single-line. For multi-line we use osascript
    -- via a quick AppleScript dialog. Returns the body, then prompts for
    -- name and type the same way.
    local script = [[
        try
            tell application "System Events"
                activate
                set dlg to display dialog "Note body (will become the memory's content):" ¬
                    default answer "" with title "Claude memory note" ¬
                    buttons {"Cancel", "Next…"} default button "Next…"
                return text returned of dlg
            end tell
        on error
            return ""
        end try
    ]]
    local ok, body = hs.osascript.applescript(script)
    if not ok or not body or #body == 0 then return end

    local btn, name = hs.dialog.textPrompt(
        "Save to Claude memory",
        string.format("File name (no extension)\nProject: %s [%s]",
            target:match("projects/([^/]+)/memory$") or "?", source),
        "", "Next…", "Cancel"
    )
    if btn ~= "Next…" or not name or #name == 0 then return end

    chooseTypeAndCommit(self, target, name, body)
end

function obj:_revealScratchpad()
    hs.execute("open " .. self.scratchpadPath)
end

-- ──────────────────────────────────────────────────────────────────────
-- public API

function obj:init()
    self.scratchpadPath = expandTilde(self.scratchpadPath) or (home() .. "/.claude/scratchpad")
    self.projectsPath = expandTilde(self.projectsPath) or (home() .. "/.claude/projects")
    self.activeProjectFile = expandTilde(self.activeProjectFile) or (home() .. "/.claude/active-project")
    self.ocrBinPath = expandTilde(self.ocrBinPath) or (home() .. "/.claude/bin/ocr")
    return self
end

--- ClaudeHotkeys:bindHotkeys(mapping)
--- Method
--- Override the hotkey assignments. `mapping` keys: screenshot, fullscreen,
--- text, ocr, memory, reveal. Each value is `{ {modifiers}, key }`.
function obj:bindHotkeys(mapping)
    self.hotkeyMap = mapping
    return self
end

function obj:_defaultMap()
    local m = self.modifier
    return {
        screenshot = {m, "4"},
        fullscreen = {m, "5"},
        text       = {m, "C"},
        ocr        = {m, "T"},
        memory     = {m, "M"},
        note       = {m, "N"},
        reveal     = {m, "F"},
    }
end

function obj:start()
    -- Ensure paths exist
    ensureDir(self.scratchpadPath)
    for _, sub in ipairs({"screenshots", "text", "ocr"}) do
        ensureDir(self.scratchpadPath .. "/" .. sub)
    end
    ensureDir(self.ocrBinPath:match("(.*)/[^/]+$"))

    -- Compile OCR helper if needed (silent — we'll lazy-compile on first use too)
    ensureOCRCompiled(self)

    local map = self.hotkeyMap or self:_defaultMap()
    local actions = {
        screenshot = function() self:_screenshotRegion() end,
        fullscreen = function() self:_screenshotFull() end,
        text       = function() self:_captureText() end,
        ocr        = function() self:_ocrRegion() end,
        memory     = function() self:_saveToMemory() end,
        note       = function() self:_saveNote() end,
        reveal     = function() self:_revealScratchpad() end,
    }
    for key, binding in pairs(map) do
        if actions[key] then
            table.insert(self._hotkeys, hs.hotkey.bind(binding[1], binding[2], actions[key]))
        end
    end

    if self.notifications then
        hs.alert.show("Claude hotkeys loaded\n" .. table.concat(self.modifier, "+") .. " + 4/5/C/T/M/N/F")
    end
    return self
end

function obj:stop()
    for _, hk in ipairs(self._hotkeys) do hk:delete() end
    self._hotkeys = {}
    return self
end

return obj
