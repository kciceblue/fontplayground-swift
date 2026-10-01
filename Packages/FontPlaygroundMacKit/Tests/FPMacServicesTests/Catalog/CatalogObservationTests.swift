import CoreText
import FPCore
import FPEngineClient
import Foundation
import Testing

@testable import FPMacServices

extension InstallationIntegration {
    struct CatalogObservationTests {
        @Test func catalog6RefreshesOnceAfterDebounce() async throws {
            let f = try CatalogFixture(); defer { f.cleanup() }
            var configuration = f.configuration; configuration.changeDebounce = .milliseconds(100)
            let center = NotificationCenter(),
                name = Notification.Name(kCTFontManagerRegisteredFontsChangedNotification as String)
            let store = CatalogStore(
                engine: f.engine, registry: f.registry, configuration: configuration, notificationCenters: [center])
            _ = try await store.refresh(.incremental); await store.startObservingSystemChanges();
            await store.startObservingSystemChanges()
            let new = try f.stub("A.ttf"); f.registry.files = [.init(path: new.path, postscriptNames: ["Stub-A"])]
            center.post(name: name, object: nil); try await Task.sleep(for: .milliseconds(50));
            center.post(name: name, object: nil)
            try await eventually(timeout: .seconds(2)) { await store.currentSnapshot().faces.count == 1 }
            #expect(await store.refreshCount == 2)
            center.post(name: name, object: nil); try await Task.sleep(for: .seconds(1))
            #expect(await store.refreshCount == 2)
            f.registry.faces = [.init(postscriptName: "Stub-A", path: new.path, priority: 1, enabled: false)]
            center.post(name: name, object: nil)
            try await eventually { await store.currentSnapshot().counts.disabledFaces == 1 }
            #expect(await store.refreshCount == 3)
            await store.stopObservingSystemChanges(); f.registry.files = []
            center.post(name: name, object: nil); try await Task.sleep(for: .milliseconds(200))
            #expect(await store.refreshCount == 3)
        }
        @Test func processScopeRegistrationTriggersRefresh() async throws {
            let f = try CatalogFixture(); defer { f.cleanup() }
            let family = "Catalog Notification " + TestEnv.tag()
            let url = try #require(
                FixtureFonts.build([FontSpec(file: "Observe.ttf", family: family)], in: f.fonts).first)
            var configuration = f.configuration; configuration.changeDebounce = .milliseconds(200)
            let engine: any EngineRunning
            if TestEnv.enginePython != nil {
                engine = try realCatalogEngine(temporary: f.root.appendingPathComponent("helper"))
            } else {
                var face = FakeEngine.face(url.path); face.family = family
                await f.engine.script([face], path: url.path); engine = f.engine
            }
            let store = CatalogStore(
                engine: engine, registry: PrefixFilteredRegistry(folder: f.fonts), configuration: configuration,
                notificationCenters: [NotificationCenter.default])
            await store.startObservingSystemChanges(); _ = try await store.refresh(.incremental)
            #expect(await store.currentSnapshot().faces.isEmpty)
            try ProcessScopeFonts.register(url); defer { ProcessScopeFonts.unregister(url) }
            try await eventually(timeout: .seconds(3)) {
                await store.currentSnapshot().faces.contains { $0.family == family }
            }
            await store.stopObservingSystemChanges()
        }
        @Test func urlFontsRegisterNothing() throws {
            let f = try CatalogFixture(); defer { f.cleanup() }
            let tag = TestEnv.tag()
            let urls = try FixtureFonts.build(
                (0..<20).map {
                    FontSpec(
                        file: "\($0).ttf", family: "Catalog Unregistered \(tag) \($0)",
                        postscriptName: "CatalogNone-\(tag)-\($0)")
                }, in: f.fonts)
            var fonts: [CTFont] = []
            for url in urls {
                let descriptors = try #require(
                    CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
                for descriptor in descriptors { fonts.append(CTFontCreateWithFontDescriptor(descriptor, 16, nil)) }
                #expect(CTFontManagerGetScopeForURL(url as CFURL) == .none)
            }
            #expect(fonts.count == 20)
            let names = Set(CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? [])
            for i in 0..<20 { #expect(!names.contains("CatalogNone-\(tag)-\(i)")) }
            let identities = Set(urls.compactMap { DiscoveredFileStamp($0.path)?.identity })
            #expect(
                CoreTextFontRegistry().registeredFontFiles().allSatisfy {
                    !identities.contains(DiscoveredFileStamp($0.path)!.identity)
                })
        }
    }
}
