import FPCore
import Foundation
import Testing

@testable import FPAppUI

extension BuildFlowIntegration {
    @MainActor struct BuildOutputsTests {
        @Test func atMostOneResultFileAndOnlyInBuilds() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge()
            let first = try #require(r.build.result?.url), builds = r.model.services.paths.builds
            let keep = builds.appendingPathComponent("keep.ttf"),
                outside = r.temp.url.appendingPathComponent("other/forged-x.ttf")
            try AtomicFile.write(Data([1]), to: keep.path); try AtomicFile.write(Data([2]), to: outside.path)
            try await r.forge(); let second = try #require(r.build.result?.url)
            #expect(first != second && !FileManager.default.fileExists(atPath: first.path))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: builds.path).sorted()
                    == ["keep.ttf", second.lastPathComponent].sorted())
            r.build.build(); await shellEventually { r.engine.forgeRequests.count == 3 }
            let failedPath = try #require(r.engine.forgeRequests.last?.outputPath);
            try AtomicFile.write(Data([3]), to: failedPath)
            r.engine.endWithoutResult(); await r.failed(); #expect(!FileManager.default.fileExists(atPath: failedPath))
            r.build.build(); await shellEventually { r.engine.forgeRequests.count == 4 }
            let cancelledPath = try #require(r.engine.forgeRequests.last?.outputPath);
            try AtomicFile.write(Data([3]), to: cancelledPath)
            await r.build.cancelAndWait(); #expect(!FileManager.default.fileExists(atPath: cancelledPath))
            r.build.discardResultFiles(); #expect(r.build.result == nil && r.model.builtFont == nil)
            try await r.forge(); r.build.reset(); #expect(r.build.result == nil && r.model.builtFont == nil)
            BuildOutputs.delete(keep, builds: builds); BuildOutputs.delete(outside, builds: builds)
            let folder = builds.appendingPathComponent("forged-folder.ttf")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            BuildOutputs.delete(folder, builds: builds)
            #expect(FileManager.default.fileExists(atPath: folder.path))
            #expect(
                FileManager.default.fileExists(atPath: keep.path)
                    && FileManager.default.fileExists(atPath: outside.path))
        }
        @Test func undoRestoresFreshnessAndASweptFileRebuilds() async throws {
            let r = try BuildTestRig(); defer { r.cleanup() }; try await r.forge(); let original = r.model.recipe
            r.model.edit { $0.setStyle("Bold", byUser: true) }; #expect(r.build.isStale)
            r.model.edit { $0 = original }; #expect(r.build.isFresh)
            try FileManager.default.removeItem(at: try #require(r.build.result?.url)); #expect(r.build.isStale)
            await r.startInstall(); try await r.finishInstall(); #expect(r.engine.forgeRequests.count == 2)
        }
    }

}
