import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MurmacCore
@testable import MurmacInfer

@Suite("MurmacInfer Native & Vision Tests")
struct InferTests {
    @Test("Apple Vision OCR reads Russian and English text from rendered image")
    func visionOcrReadsBilingualText() async throws {
        let width = 800
        let height = 200
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        ("Привет ClickHouse Murmac" as NSString).draw(at: NSPoint(x: 40, y: 80), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let cgImg = try #require(rep.cgImage)
        let ocr = VisionOcrEngine()
        let result = try await ocr.recognize(image: ScreenImageData(width: width, height: height, cgImageBox: { cgImg }))

        #expect(result.size == [width, height])
        let joined = result.lines.map(\.text).joined(separator: " ")
        #expect(joined.localizedCaseInsensitiveContains("ClickHouse"), "Vision OCR output: \(joined)")
        #expect(joined.contains("Привет"), "Vision OCR output: \(joined)")
        for line in result.lines {
            #expect(line.box.count == 4)
            #expect(line.box[0] < line.box[2])
            #expect(line.box[1] < line.box[3])
        }
    }

    @Test("LlamaLlmEngine probes Metal GPU when native libs are present")
    func llamaEngineProbe() async {
        let engine = LlamaLlmEngine()
        let probe = await engine.probe()
        if NativeLibraryLocator.locate(filename: "libmurmur_llm.dylib") != nil {
            #expect(probe.runtimes.contains(RuntimeKeys.llamaGguf))
            #expect(probe.availableUnits.contains(.cpu))
            #expect(probe.facts["native.build"]?.contains("llama.cpp") == true)
        } else {
            #expect(probe.facts["native"] == "missing")
        }
    }

    @Test("SherpaAsrEngine probes v2.0.1 and all supported runtimes when native libs are present")
    func sherpaEngineProbe() async {
        let engine = SherpaAsrEngine()
        let probe = await engine.probe()
        if NativeLibraryLocator.locate(filename: "libsherpa-onnx-c-api.dylib") != nil {
            #expect(probe.facts["sherpa.version"] == "2.0.1")
            #expect(probe.runtimes.contains(RuntimeKeys.sherpaOfflineTransducer))
            #expect(probe.runtimes.contains(RuntimeKeys.ortSileroVadV5))
            #expect(probe.availableUnits.contains(.cpu))
        } else {
            #expect(probe.facts["native"] == "missing")
        }
    }
}
