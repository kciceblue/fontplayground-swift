import AppKit
import FPCore
import Testing

@testable import FPAppUI

@MainActor @Suite struct PreviewPerformanceTests {
    private var factor: Double {
        max(0.1, Double(ProcessInfo.processInfo.environment["FP_PERF_FACTOR"] ?? "1") ?? 1)
    }
    private func milliseconds(_ operation: () -> Void) -> Double {
        let start = ContinuousClock.now
        operation()
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    }
    @Test func restyleWithinBudget() async throws {
        let fixtures = try PreviewFixtureFonts()
        let text = String(repeating: "a漢한", count: 666) + "ab"
        let model = fixtures.model([fixtures.a, fixtures.b], text: text)
        let editor = PreviewTextEditor.makeEditor(model: model, recordHistory: true)
        let storage = try #require(editor.textView.textStorage)
        var samples: [Double] = []
        for index in 0..<21 {
            samples.append(
                milliseconds {
                    storage.replaceCharacters(
                        in: NSRange(location: index * 73, length: 1), with: index.isMultiple(of: 2) ? "a" : "漢")
                })
            await Task.yield()
        }
        let median = samples.sorted()[samples.count / 2]
        let colour = milliseconds {
            model.recipe.setSampleText(String(repeating: "ab漢", count: 1000))
            model.colourByFont = true
            editor.coordinator.refresh()
        }
        var runs = 0
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { _, _, _ in runs += 1 }
        print("WP-504 restyle median=\(median)ms; 3,000-unit colour change=\(colour)ms; runs=\(runs); factor=\(factor)")
        #expect(median <= 25 * factor && colour <= 250 * factor)
        #expect(runs == 2000 && editor.textView.textLayoutManager != nil)
        withExtendedLifetime(editor.scrollView) {}
    }
    @Test func typingStaysInteractive() async throws {
        let fixtures = try PreviewFixtureFonts()
        var percentiles: [Double] = []
        for text in [
            String(repeating: String(repeating: "a漢한", count: 13) + "\n", count: 50),
            String(repeating: "a漢한", count: 666) + "ab",
        ] {
            let model = fixtures.model([fixtures.a, fixtures.b], text: text)
            let editor = PreviewTextEditor.makeEditor(model: model, recordHistory: true)
            let view = editor.textView
            let layout = try #require(view.textLayoutManager)
            layout.textViewportLayoutController.layoutViewport()
            var samples: [Double] = []
            for index in 0..<300 {
                let position = (index * 137) % (view.string as NSString).length
                samples.append(
                    milliseconds {
                        view.insertText("a", replacementRange: NSRange(location: position, length: 0))
                        layout.textViewportLayoutController.layoutViewport()
                    })
                // Let other native UI tests service their debounce timers outside the measured keystroke.
                await Task.yield()
            }
            percentiles.append(samples.sorted()[284])
            #expect(view.textLayoutManager != nil && editor.coordinator.recipeUpdates.count == 300)
            withExtendedLifetime(editor.scrollView) {}
        }
        let model = fixtures.model([fixtures.a, fixtures.b], text: String(repeating: "ab漢", count: 733) + "a")
        let editor = PreviewTextEditor.makeEditor(model: model, recordHistory: true)
        let layout = try #require(editor.textView.textLayoutManager)
        layout.textViewportLayoutController.layoutViewport()
        let mode = milliseconds {
            model.colourByFont = true
            editor.coordinator.refresh()
            layout.textViewportLayoutController.layoutViewport()
        }
        print(
            "WP-504 typing p95: 50 lines=\(percentiles[0])ms; one paragraph=\(percentiles[1])ms; 2,200-unit mode change=\(mode)ms; factor=\(factor)"
        )
        #expect(percentiles[0] <= 16 * factor && percentiles[1] <= 60 * factor && mode <= 50 * factor)
        #expect(editor.textView.textLayoutManager != nil)
        withExtendedLifetime(editor.scrollView) {}
    }
}
