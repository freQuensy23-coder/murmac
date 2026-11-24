import CoreGraphics
import CoreML
import Foundation
import ImageIO
import MurmacCore
import Vision

/// Native macOS screen OCR powered by Apple Vision (`VNRecognizeTextRequest` on Apple Neural Engine,
/// with automatic CPU fallback on headless/virtualized runners).
public final class VisionOcrEngine: ScreenOcrEngine, Sendable {
    public init() {}

    public func recognize(image: ScreenImageData) async throws -> ScreenText {
        let cgImage: CGImage
        if let boxed = image.cgImageBox?(), CFGetTypeID(boxed) == CGImage.typeID {
            cgImage = (boxed as! CGImage)
        } else if let png = image.pngData,
                  let src = CGImageSourceCreateWithData(png as CFData, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            cgImage = img
        } else {
            throw MurmurError.ocrFailed("missing_image")
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else {
            return ScreenText(size: [0, 0], lines: [])
        }

        return try await Task.detached(priority: .userInitiated) {
            let observations = try Self.runVision(cgImage: cgImage)
            var lines: [OcrLine] = []
            lines.reserveCapacity(observations.count)

            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }
                let bb = obs.boundingBox
                let x0 = max(0, min(width, Int(round(bb.minX * Double(width)))))
                let x1 = max(x0, min(width, Int(round(bb.maxX * Double(width)))))
                let y0 = max(0, min(height, Int(round((1.0 - bb.maxY) * Double(height)))))
                let y1 = max(y0, min(height, Int(round((1.0 - bb.minY) * Double(height)))))
                lines.append(OcrLine(text: text, conf: Double(top.confidence), box: [x0, y0, x1, y1]))
            }

            // Strict weak ordering: first sort deterministically by (y0, x0), then cluster lines within 10 px
            // vertically into rows and sort each row strictly by x0.
            let sortedByY = lines.sorted { a, b in
                a.box[1] != b.box[1] ? a.box[1] < b.box[1] : a.box[0] < b.box[0]
            }
            var ordered: [OcrLine] = []
            ordered.reserveCapacity(sortedByY.count)
            var row: [OcrLine] = []
            var rowY: Int = 0
            for line in sortedByY {
                if row.isEmpty {
                    row = [line]
                    rowY = line.box[1]
                } else if abs(line.box[1] - rowY) <= 10 {
                    row.append(line)
                } else {
                    ordered.append(contentsOf: row.sorted { $0.box[0] < $1.box[0] })
                    row = [line]
                    rowY = line.box[1]
                }
            }
            if !row.isEmpty {
                ordered.append(contentsOf: row.sorted { $0.box[0] < $1.box[0] })
            }
            return ScreenText(size: [width, height], lines: ordered)
        }.value
    }

    private static func runVision(cgImage: CGImage) throws -> [VNRecognizedTextObservation] {
        func perform(cpuOnly: Bool) throws -> [VNRecognizedTextObservation] {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            if cpuOnly,
               let cpu = MLComputeDevice.allComputeDevices.first(where: {
                   if case .cpu = $0 { return true }
                   return false
               }) {
                request.setComputeDevice(cpu, for: .main)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return request.results ?? []
        }
        do {
            return try perform(cpuOnly: false)
        } catch {
            // Headless macOS VMs (e.g. GitHub Actions macos-15) lack Metal/ANE; fall back to Vision CPU path.
            return try perform(cpuOnly: true)
        }
    }
}
