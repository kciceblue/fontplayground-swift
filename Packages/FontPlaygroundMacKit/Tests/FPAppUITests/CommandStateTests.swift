import AppKit
import FPCore
import FPEngineClient
import FPMacServices
import Testing

@testable import FPAppUI

@MainActor struct CommandStateTests {
    @Test func everyCommandUsesItsEnabledRule() throws {
        let rig = try ShellRig(), m = AppModel(services: rig.services)
        for main in [false, true] {
            for building in [false, true] {
                for scanning in [false, true] {
                    for unavailable in [false, true] {
                        for size in [10, 30, 96] {
                            for help in [false, true] {
                                var r = Recipe(); if main { r.add(ShellFaces.make()) }
                                let build = BuildCommands(
                                    canSaveCopy: true, canInstall: false, canShowInFinder: true,
                                    canOpenInFontBook: false, canUninstall: true, installTitle: "Update Installed Font")
                                let state = CommandState(
                                    recipe: r, isBuilding: building, catalogIsEmpty: !main, isScanning: scanning,
                                    engineStatus: unavailable ? .unavailable("x") : .unknown, previewPointSize: size,
                                    colourByFont: true, inspectorPresented: main, helpAvailable: help,
                                    donateAvailable: !help, build: build)
                                for command in MenuCommand.allCases {
                                    let expected: Bool
                                    switch command {
                                    case .startOver: expected = main || building
                                    case .rescanFonts: expected = !scanning && !unavailable
                                    case .saveCopy, .showInFinder, .uninstall: expected = true
                                    case .install, .openInFontBook: expected = false
                                    case .findFont, .chooseMainFont, .addFontFor, .addFontForAnyLanguage:
                                        expected = main && !building
                                    case .bigger: expected = size < 96
                                    case .smaller: expected = size > 10
                                    case .actualSize: expected = size != 30
                                    case .help: expected = help
                                    case .donate: expected = !help
                                    default: expected = true
                                    }
                                    #expect(state.isEnabled(command) == expected)
                                }
                                #expect(
                                    state.title(.chooseMainFont) == (main ? "Change Main Font…" : "Choose Main Font…"))
                                #expect(state.title(.advanced) == (main ? "Hide Advanced" : "Show Advanced"))
                                #expect(state.title(.install) == "Update Installed Font" && state.isColourByFontOn)
                            }
                        }
                    }
                }
            }
        }
        let initial = m.commandState; m.pickRequest = PickRequest(languageID: "any"); #expect(m.commandState == initial)
        m.catalogFaces = [ShellFaces.make()]; #expect(m.commandState.canFindFont && !m.commandState.canAddFontFor)
    }
}
