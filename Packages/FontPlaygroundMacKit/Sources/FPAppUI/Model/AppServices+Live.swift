import FPCore
import FPEngineClient
import FPMacServices
import Foundation

extension AppServices {
    public static func live(bundle: Bundle = .main) -> AppServices {
        let paths = AppPaths.live()
        let engine: any EngineRunning
        do {
            engine = EngineClient(
                configuration: EngineConfiguration(
                    launch: try EngineLaunch.resolve(bundleURL: bundle.bundleURL), temporaryDirectory: paths.helperTemp,
                    logHandler: { AppLog.engine.debug("\($0, privacy: .public)") }))
        } catch { engine = UnavailableEngine(error: error) }
        var config = CatalogConfiguration.standard(); config.cacheDirectory = paths.caches
        let help =
            bundle.url(forResource: "UserGuide", withExtension: "html")
            ?? (bundle.object(forInfoDictionaryKey: "FPHelpURL") as? String).flatMap {
                $0.isEmpty ? nil : URL(string: $0)
            }
        let acknowledgements = bundle.url(forResource: "Acknowledgements", withExtension: "txt").flatMap {
            try? String(contentsOf: $0, encoding: .utf8)
        }
        let donate = (bundle.object(forInfoDictionaryKey: "FPDonateURL") as? String).flatMap {
            $0.isEmpty ? nil : URL(string: $0)
        }
        return AppServices(
            engine: engine, catalog: CatalogStore(engine: engine, configuration: config), renderer: FontRenderer(),
            installer: FontInstaller(fontsFolder: paths.userFonts, manifestURL: paths.installedManifest),
            system: LiveSystemActions(), panels: LiveFilePanels(), fileProbe: LocalFileSystem(), paths: paths,
            defaults: .standard, now: { Date() }, writeFile: { try AtomicFile.write($0, to: $1.path) },
            sweepHelperLeftovers: {
                EngineClient.sweepLeftovers(temporaryDirectory: $0, outputDirectories: $1, now: $2)
            }, helpURL: help, acknowledgements: acknowledgements, donateURL: donate)
    }
}
