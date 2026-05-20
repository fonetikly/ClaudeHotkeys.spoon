// markup.swift — image markup window for the ClaudeHotkeys.spoon screenshot
// hotkeys. Receives an input PNG, lets the user redact (filled black rect)
// or highlight (red outlined rect) regions, then bakes annotations into the
// image and writes the result. Used as a privacy gate before screenshots
// land in Claude's scratchpad.
//
// Usage:  markup <input.png> <output.png>
// Exit:   0 = sent, 1 = cancelled, 64 = bad usage, 65 = could not load image.
//
// Keys:   Cmd-Z = undo, Cmd-Return = send, Escape = cancel.

import AppKit

// ──────────────────────────────────────────────────────────────────────────
// Model

enum Tool: String { case redact, highlight }

struct Annotation {
    let tool: Tool
    var start: NSPoint   // in view space (flipped, top-left origin)
    var end: NSPoint

    func rect(flipHeight h: CGFloat? = nil) -> NSRect {
        let r = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        guard let h = h else { return r }
        return NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}

// ──────────────────────────────────────────────────────────────────────────
// Canvas — draws the image + annotations + in-progress drag.

final class MarkupCanvas: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    var currentTool: Tool = .highlight

    private var dragStart: NSPoint?
    private var dragEnd: NSPoint?

    override var isFlipped: Bool { true }  // top-left origin for drawing math
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        if let image = image {
            let r = imageRect(in: bounds, imageSize: image.size)
            image.draw(in: r)
        }

        for a in annotations { drawAnnotation(a) }
        if let s = dragStart, let e = dragEnd, s != e {
            drawAnnotation(Annotation(tool: currentTool, start: s, end: e))
        }
    }

    private func drawAnnotation(_ a: Annotation) {
        let r = a.rect()
        switch a.tool {
        case .redact:
            NSColor.black.setFill()
            r.fill()
        case .highlight:
            NSColor.systemRed.setStroke()
            let p = NSBezierPath(rect: r)
            p.lineWidth = 3.0
            p.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = p; dragEnd = p
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let s = dragStart, let e = dragEnd, s != e {
            annotations.append(Annotation(tool: currentTool, start: s, end: e))
        }
        dragStart = nil; dragEnd = nil
        needsDisplay = true
    }

    /// The on-screen rect occupied by the image inside `bounds` (with
    /// letterboxing / pillarboxing if aspect ratios differ).
    func imageRect(in container: NSRect, imageSize: NSSize) -> NSRect {
        let scale = min(container.width / imageSize.width,
                        container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return NSRect(
            x: container.midX - w / 2,
            y: container.midY - h / 2,
            width: w, height: h
        )
    }

    func undo() { if !annotations.isEmpty { annotations.removeLast() } }
}

// ──────────────────────────────────────────────────────────────────────────
// Window controller

final class MarkupController: NSObject, NSWindowDelegate {
    let inputPath: String
    let outputPath: String
    let originalImage: NSImage
    let window: NSWindow
    let canvas: MarkupCanvas
    let redactButton = NSButton(title: "Redact", target: nil, action: nil)
    let highlightButton = NSButton(title: "Highlight", target: nil, action: nil)

    static var didSend = false  // captured before NSApp.terminate

    init(inputPath: String, outputPath: String, image: NSImage) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.originalImage = image

        let contentSize = preferredContentSize(for: image.size)
        self.window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        self.canvas = MarkupCanvas()
        self.canvas.image = image
        super.init()
        buildUI()
        window.delegate = self
    }

    private func buildUI() {
        window.title = "Mark up before sending to Claude"

        let toolbar = makeToolbar()
        let bottomBar = makeBottomBar()

        let stack = NSStackView(views: [toolbar, canvas, bottomBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor),
        ])
        window.center()
        updateToolButtons()
    }

    private func makeToolbar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        let label = NSTextField(labelWithString: "Tool:")
        label.font = .systemFont(ofSize: 12, weight: .semibold)

        redactButton.bezelStyle = .rounded
        redactButton.target = self
        redactButton.action = #selector(selectRedact)
        redactButton.toolTip = "Drag a rectangle to redact (filled black). Keyboard: 1"

        highlightButton.bezelStyle = .rounded
        highlightButton.target = self
        highlightButton.action = #selector(selectHighlight)
        highlightButton.toolTip = "Drag a rectangle to highlight (red outline). Keyboard: 2"

        let undo = NSButton(title: "Undo", target: self, action: #selector(undoLast))
        undo.bezelStyle = .rounded
        undo.toolTip = "Remove last annotation (⌘Z)"

        let help = NSTextField(labelWithString: "Drag to mark a region. Send when ready.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 11)

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(redactButton)
        stack.addArrangedSubview(highlightButton)
        stack.addArrangedSubview(undo)
        stack.addArrangedSubview(help)
        return stack
    }

    private func makeBottomBar() -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"  // Escape

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let send = NSButton(title: "Send to Claude", target: self, action: #selector(send))
        send.bezelStyle = .rounded
        send.keyEquivalent = "\r"  // Return
        send.keyEquivalentModifierMask = .command
        send.toolTip = "Bake annotations into the image and save (⌘Return)"

        stack.addArrangedSubview(cancel)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(send)
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        return stack
    }

    private func updateToolButtons() {
        redactButton.state = canvas.currentTool == .redact ? .on : .off
        highlightButton.state = canvas.currentTool == .highlight ? .on : .off
    }

    @objc private func selectRedact() {
        canvas.currentTool = .redact
        updateToolButtons()
    }
    @objc private func selectHighlight() {
        canvas.currentTool = .highlight
        updateToolButtons()
    }
    @objc private func undoLast() { canvas.undo() }

    @objc private func cancel() {
        MarkupController.didSend = false
        NSApp.stop(nil)
    }

    @objc private func send() {
        guard let baked = bakeAnnotations() else {
            MarkupController.didSend = false
            NSApp.stop(nil); return
        }
        if writePNG(baked, to: outputPath) {
            MarkupController.didSend = true
        }
        NSApp.stop(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return true
    }

    // MARK: bake annotations into the image at original resolution

    private func bakeAnnotations() -> NSImage? {
        let canvasBounds = canvas.bounds
        let imageRect = canvas.imageRect(in: canvasBounds, imageSize: originalImage.size)
        if imageRect.width <= 0 || imageRect.height <= 0 { return nil }

        let viewToImageScaleX = originalImage.size.width / imageRect.width
        let viewToImageScaleY = originalImage.size.height / imageRect.height

        let out = NSImage(size: originalImage.size)
        out.lockFocus()
        defer { out.unlockFocus() }

        originalImage.draw(in: NSRect(origin: .zero, size: originalImage.size))

        let ctx = NSGraphicsContext.current?.cgContext
        // Flip the y-axis once so we can keep using top-left-origin math
        // (the canvas uses isFlipped=true; NSImage drawing context does not).
        ctx?.saveGState()
        ctx?.translateBy(x: 0, y: originalImage.size.height)
        ctx?.scaleBy(x: 1, y: -1)

        for a in canvas.annotations {
            let r = a.rect()
            // From view-space to image-space:
            let inImage = NSRect(
                x: (r.minX - imageRect.minX) * viewToImageScaleX,
                y: (r.minY - imageRect.minY) * viewToImageScaleY,
                width: r.width * viewToImageScaleX,
                height: r.height * viewToImageScaleY
            )
            switch a.tool {
            case .redact:
                NSColor.black.setFill()
                inImage.fill()
            case .highlight:
                NSColor.systemRed.setStroke()
                let p = NSBezierPath(rect: inImage)
                p.lineWidth = max(3.0, originalImage.size.width / 300)
                p.stroke()
            }
        }

        ctx?.restoreGState()
        return out
    }

    private func writePNG(_ image: NSImage, to path: String) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch { return false }
    }
}

private func preferredContentSize(for imageSize: NSSize) -> NSSize {
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let toolbarHeight: CGFloat = 80  // top + bottom bars
    let maxW = screen.width * 0.85
    let maxH = (screen.height * 0.85) - toolbarHeight
    let scale = min(1.0, min(maxW / imageSize.width, maxH / imageSize.height))
    let w = max(640, imageSize.width * scale)
    let h = max(480, imageSize.height * scale + toolbarHeight)
    return NSSize(width: w, height: h)
}

// ──────────────────────────────────────────────────────────────────────────
// Entry point

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("Usage: markup <input.png> <output.png>\n".utf8))
    exit(64)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: inputPath) else {
    FileHandle.standardError.write(Data("Cannot load image at \(inputPath)\n".utf8))
    exit(65)
}

let app = NSApplication.shared
NSApp.setActivationPolicy(.regular)

let controller = MarkupController(inputPath: inputPath, outputPath: outputPath, image: image)
controller.window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
NSApp.run()

exit(MarkupController.didSend ? 0 : 1)
