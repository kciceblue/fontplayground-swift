import FPCore
import FPEngineClient
import FPMacServices
import Foundation

@MainActor public struct AppServices {
    public var engine: any EngineRunning
    public var catalog: any FontCataloging
    public var renderer: any FontRendering
    public var installer: any FontInstalling
    public var system: any SystemActions
    public var panels: any FilePanels
    public var fileProbe: any FileSystemProbe
    public var paths: AppPaths
    public var defaults: UserDefaults
    public var now: @Sendable () -> Date
    public var writeFile: @Sendable (Data, URL) throws -> Void
    public var sweepHelperLeftovers: @Sendable (URL, [URL], Date) -> Int
    public var helpURL: URL?
    public var acknowledgements: String?
    /// The donation page (Info.plist `FPDonateURL`). Nil hides the one-time offer and disables Donate….
    public var donateURL: URL?
    public init(
        engine: any EngineRunning, catalog: any FontCataloging, renderer: any FontRendering,
        installer: any FontInstalling, system: any SystemActions, panels: any FilePanels,
        fileProbe: any FileSystemProbe, paths: AppPaths, defaults: UserDefaults, now: @escaping @Sendable () -> Date,
        writeFile: @escaping @Sendable (Data, URL) throws -> Void,
        sweepHelperLeftovers: @escaping @Sendable (URL, [URL], Date) -> Int, helpURL: URL? = nil,
        acknowledgements: String? = nil, donateURL: URL? = nil
    ) {
        self.engine = engine; self.catalog = catalog; self.renderer = renderer; self.installer = installer;
        self.system = system; self.panels = panels; self.fileProbe = fileProbe; self.paths = paths;
        self.defaults = defaults; self.now = now; self.writeFile = writeFile;
        self.sweepHelperLeftovers = sweepHelperLeftovers; self.helpURL = helpURL;
        self.acknowledgements = acknowledgements; self.donateURL = donateURL
    }
}
