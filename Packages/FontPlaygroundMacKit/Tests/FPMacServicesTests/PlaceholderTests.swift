import Testing

@testable import FPMacServices

@Test func moduleIsLinked() {
    #expect(FPMacServicesInfo.moduleName == "FPMacServices")
}
