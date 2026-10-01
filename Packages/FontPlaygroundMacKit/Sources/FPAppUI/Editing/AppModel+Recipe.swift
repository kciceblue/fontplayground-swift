import FPCore

extension AppModel {
    @discardableResult func perform(_ action: RecipeAction) -> [WeightSwap] {
        guard !isBuilding || action.isAllowedWhileBuilding else { return [] }
        switch action {
        case .chooseMain: openPicker(PickRequest(languageID: "latin")); return []
        case .pick(let request):
            if let key = request.replaceKey, !recipe.keys.contains(key) { return [] }
            openPicker(request); return []
        case .showAdvanced: showAdvanced(); return []
        default: break
        }
        var swaps: [WeightSwap] = []
        edit { recipe in
            switch action {
            case .chooseStyle(let key, let face): recipe.replace(key, with: face, keepAdjustments: true)
            case .setWeight(let key, let weight):
                guard let material = recipe.materials.first(where: { $0.key == key }) else { return }
                let oldResolved = material.weight ?? recipe.defaultWeight
                recipe.setAdjustments(for: key, weight: weight, scale: material.scale)
                if oldResolved != (weight ?? recipe.defaultWeight) {
                    swaps = recipe.applyRealWeights(in: FaceCatalog(catalogFaces))
                }
            case .setSizePercent(let key, let percent):
                guard let material = recipe.materials.first(where: { $0.key == key }) else { return }
                recipe.setAdjustments(
                    for: key, weight: material.weight, scale: RecipeText.percentScale(min(1000, max(10, percent))))
            case .makeMain(let key): recipe.move(key, to: 0)
            case .moveUp(let key):
                if let index = recipe.keys.firstIndex(of: key), index > 0 { recipe.move(key, to: index - 1) }
            case .moveDown(let key):
                if let index = recipe.keys.firstIndex(of: key), index + 1 < recipe.materials.count {
                    recipe.move(key, to: index + 1)
                }
            case .remove(let key): recipe.remove(key)
            default: break
            }
        }
        return swaps
    }
}
