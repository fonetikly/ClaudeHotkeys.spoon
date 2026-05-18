import AppKit
import Foundation
import Vision

// Tiny OCR helper for the Hammerspoon `⌃⌥⇧-T` hotkey.
// Usage: ocr <image-path>   →   prints recognized text to stdout, line per region.

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("Usage: ocr <image-path>\n".utf8))
    exit(64)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)

guard let nsImage = NSImage(contentsOf: url),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write(Data("Cannot load image at \(path)\n".utf8))
    exit(65)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
// Auto-language detect by default; bias toward English-then-others.
if #available(macOS 13.0, *) {
    request.automaticallyDetectsLanguage = true
}

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
do {
    try handler.perform([request])
} catch {
    FileHandle.standardError.write(Data("OCR perform failed: \(error.localizedDescription)\n".utf8))
    exit(70)
}

guard let observations = request.results else { exit(0) }

for observation in observations {
    if let candidate = observation.topCandidates(1).first {
        print(candidate.string)
    }
}
