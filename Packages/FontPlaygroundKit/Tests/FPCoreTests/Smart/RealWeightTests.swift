import FPCore
import Foundation
import Testing

struct RealWeightTests {
    private func weightFace(
        _ weight: Int, coverage: CodepointSet = SmartFaces.han.union(cps("abc")), style: String = "Regular"
    ) -> FaceRecord {
        fakeFace(coverage, path: "weight-\(weight)-\(style).ttf", family: "PingFang SC", style: style, weight: weight)
    }

    @Test("ENGINE-4: real semibold replaces expensive synthetic bold")
    func engine4RealSemiboldFaceReplacesSyntheticBold() throws {
        let regular = weightFace(400), medium = weightFace(500, style: "Medium"),
            semibold = weightFace(600, style: "Semibold")
        let catalog = FaceCatalog([regular, medium, semibold])
        for requested in [700, 600] {
            var recipe = Recipe(); recipe.add(TestFaces.a); recipe.add(regular)
            recipe.setPin(.han, to: regular.key); recipe.setBase(regular.key)
            recipe.setAdjustments(for: regular.key, weight: requested, scale: 1.2)
            let swaps = recipe.applyRealWeights(in: catalog)
            let swap = try #require(swaps.first)
            #expect(swaps.count == 1 && swap.index == 1 && swap.from == regular && swap.to == semibold)
            #expect(swap.requestedWeight == requested && swap.remainingSyntheticBold == requested - 600)
            #expect(recipe.pins[.han] == semibold.key && recipe.baseKey == semibold.key)
            #expect(recipe.materials[1].weight == requested && recipe.materials[1].scale == 1.2)
            #expect(recipe.weightNotes() == (requested == 700 ? [.syntheticBold(index: 1, delta: 100)] : []))
            #expect(
                EnglishText.weightSwap(swap)
                    == "Using PingFang SC Semibold instead of making PingFang SC Regular bolder.")
        }
    }

    @Test("ENGINE-4: replacement never loses a planned character") func engine4SwapNeverLosesPlannedCharacters() throws
    {
        let full = CodepointSet(ranges: [0x4E00...UInt32(0x4E00 + 13860)])
        let subset = CodepointSet(ranges: [0x4E00...UInt32(0x4E00 + 8346)])
        let w3 = weightFace(300, coverage: full, style: "W3")
        let w6 = weightFace(600, coverage: full, style: "W6")
        let w7 = weightFace(700, coverage: subset, style: "W7")
        let catalog = FaceCatalog([w3, w6, w7])
        var recipe = Recipe(); recipe.add(TestFaces.a); recipe.add(w3)
        recipe.setAdjustments(for: w3.key, weight: 700, scale: nil)
        let before = recipe.plan().assignments[1]
        #expect(before.count == 13861)
        let swap = try #require(recipe.applyRealWeights(in: catalog).first)
        #expect(swap.to == w6 && swap.remainingSyntheticBold == 100)
        #expect(recipe.plan().assignments[1].isSuperset(of: before))
        var subsetRecipe = Recipe()
        subsetRecipe.add(fakeFace(full.subtracting(subset), path: "rest.ttf", family: "Rest"))
        subsetRecipe.add(w3); subsetRecipe.setAdjustments(for: w3.key, weight: 700, scale: nil)
        #expect(subsetRecipe.plan().assignments[1] == subset)
        let subsetSwap = try #require(subsetRecipe.applyRealWeights(in: catalog).first)
        #expect(subsetSwap.to == w7 && subsetSwap.remainingSyntheticBold == 0)
        var unshapedW7 = w7; unshapedW7.unshaped = subset
        #expect(
            Smart.nearestRealWeight(
                for: w3, requested: 700, mustCover: subset,
                in: FaceCatalog([unshapedW7, w6]), excluding: []) == w6)
    }

    @Test func noSwapCases() {
        let regular = weightFace(400), heavy = weightFace(700)
        var nilWeight = Recipe(); nilWeight.add(regular)
        var near = nilWeight; near.setDefaults(weight: 449, scale: 1)
        var variable = regular; variable.axes = [.init(tag: "wght", min: 100, default: 400, max: 900)]
        var variableRecipe = Recipe(); variableRecipe.add(variable); variableRecipe.setDefaults(weight: 700, scale: 1)
        var italic = heavy; italic.italic = true
        var wantsHeavy = nilWeight; wantsHeavy.setDefaults(weight: 700, scale: 1)
        var used = wantsHeavy; used.add(heavy)
        var emptyDrawn = Recipe(); emptyDrawn.add(fakeFace(regular.coverage, path: "main.ttf", family: "Other"));
        emptyDrawn.add(regular)
        emptyDrawn.setAdjustments(for: regular.key, weight: 700, scale: nil)
        var mislabeled = regular; mislabeled.path = "bold.ttf"; mislabeled.style = "Bold"
        var unavailable = wantsHeavy; _ = unavailable.refreshFileAvailability(using: FakeFileSystem(files: []))
        for (initial, faces) in [
            (nilWeight, [regular, heavy]), (near, [regular, heavy]), (variableRecipe, [variable, heavy]),
            (wantsHeavy, [regular, italic]), (used, [regular, heavy]), (emptyDrawn, [regular, heavy]),
            (wantsHeavy, [regular, mislabeled]), (unavailable, [regular, heavy]),
        ] {
            var recipe = initial
            #expect(recipe.applyRealWeights(in: FaceCatalog(faces)).isEmpty)
            #expect(recipe == initial)
        }
    }

    @Test func lighterRequestSwapsToLighterFace() throws {
        let medium = weightFace(500, style: "Medium"), light = weightFace(300, style: "Light")
        var recipe = Recipe(); recipe.add(medium); recipe.setDefaults(weight: 300, scale: 1)
        let swap = try #require(recipe.applyRealWeights(in: FaceCatalog([medium, light])).first)
        #expect(swap.to == light && swap.remainingSyntheticBold == 0)
        #expect(recipe.names.style == "Light" && recipe.defaultWeight == 300)
        #expect(EnglishText.weightSwap(swap) == "Using PingFang SC Light instead of making PingFang SC Medium lighter.")
    }

    @Test func weightNotesMirrorEngineThresholds() {
        for (base, requested, expected) in [
            (400, 449, [WeightNote]()), (400, 450, [.syntheticBold(index: 0, delta: 50)]),
            (100, 700, [.syntheticBold(index: 0, delta: 500)]), (400, 350, [.cannotMakeLighter(index: 0)]),
        ] {
            var recipe = Recipe(); recipe.add(weightFace(base)); recipe.setDefaults(weight: requested, scale: 1)
            #expect(recipe.weightNotes() == expected)
        }
        #expect(EnglishText.weightNote(.syntheticBold(index: 1, delta: 100)) == "Made bolder synthetically (+100)")
        #expect(EnglishText.weightNote(.cannotMakeLighter(index: 1)) == "Can't be made lighter; weight left as is")
        var variable = weightFace(400); variable.axes = [.init(tag: "wght", min: 100, default: 400, max: 900)]
        var recipe = Recipe(); recipe.add(variable); recipe.setDefaults(weight: 900, scale: 1)
        #expect(recipe.weightNotes().isEmpty)
    }

    @Test func variableCandidatesAndDistanceTies() {
        let regular = weightFace(400), below = weightFace(600), above = weightFace(800)
        let drawn = cps("一")
        #expect(
            Smart.nearestRealWeight(
                for: regular, requested: 700, mustCover: drawn,
                in: FaceCatalog([below, above]), excluding: []) == above)
        var variable = regular; variable.path = "variable.ttf";
        variable.axes = [.init(tag: "wght", min: 100, default: 400, max: 900)]
        #expect(
            Smart.nearestRealWeight(
                for: regular, requested: 700, mustCover: drawn,
                in: FaceCatalog([above, variable]), excluding: []) == variable)
        var hidden = weightFace(700); hidden.hidden = true
        var suspicious = hidden; suspicious.path = "suspect.ttf"; suspicious.hidden = false;
        suspicious.suspiciousCoverage = true
        var color = hidden; color.path = "color.ttf"; color.hidden = false; color.hasColor = true;
        color.supported = false
        #expect(
            Smart.nearestRealWeight(
                for: regular, requested: 700, mustCover: drawn,
                in: FaceCatalog([hidden, suspicious, color]), excluding: []) == nil)
    }
}
