import Testing

@testable import FPCore

@Test func moduleIsLinked() {
    #expect(FPCoreInfo.moduleName == "FPCore")
}
