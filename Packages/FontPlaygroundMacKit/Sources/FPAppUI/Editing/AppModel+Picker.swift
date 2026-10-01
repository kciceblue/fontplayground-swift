import AppKit
import FPCore
import FPMacServices

extension AppModel {
    public func openPicker(_ request: PickRequest) {
        guard !isBuilding else { return }
        let language = Languages.language(rawID: request.languageID) ?? Languages.language(.any)
        edit { $0.setSampleText(Languages.withLanguageLine($0.sampleText, language)) }
        if platformPreferredNames.isEmpty, let lookup = platformFontLookup {
            // Taking the closure marks the lookup started, even if it returns an empty result.
            platformFontLookup = nil
            let probes = Dictionary(
                uniqueKeysWithValues: Languages.all.compactMap { language -> (String, String)? in
                    guard PlatformFontPreferences.languageTags[language.id.rawValue] != nil,
                        let scalar = language.textSample.unicodeScalars.first(where: {
                            language.groups.contains(ScriptGroup.of($0))
                        })
                    else { return nil }
                    return (language.id.rawValue, String(scalar))
                })
            Task { [weak self] in
                let names = await lookup(probes); self?.platformPreferredNames = names
            }
        }
        let names = platformPreferredNames.values.filter { name in catalogFaces.contains { $0.postscriptName == name } }
        let preferences = PlatformPreferences([language.id: names.map { .postscriptName($0) }]).appending(.macOS)
        let suggestions =
            request.replaceKey == nil && !recipe.materials.isEmpty
            ? recipe.suggestions(for: language.id, in: FaceCatalog(catalogFaces), limit: 3, preferences: preferences)
            : []
        let preferred = platformPreferredNames.compactMapValues { name in
            catalogFaces.first { $0.postscriptName == name }?.family
        }
        let request = PickRequest(languageID: language.id.rawValue, replaceKey: request.replaceKey)
        if pickRequest == nil { rememberPickerFocus() }
        pickRequest = request
        picker.onCandidate = { [weak self] face in
            guard let self else { return }
            guard let request = self.pickRequest, !self.isBuilding else { self.picker.cancel(); return }
            guard let face else { self.trial = nil; return }
            let language: LanguageID? =
                self.recipe.materials.isEmpty || request.replaceKey != nil || self.picker.languageID == "any"
                ? nil : LanguageID(rawValue: self.picker.languageID)
            let replaced = request.replaceKey.flatMap { key in
                self.recipe.materials.first { $0.key == key }?.face.family
            }
            self.trial = PreviewTrial(
                mix: self.recipe.mix(trying: face, replacing: request.replaceKey, for: language),
                banner: PickerText.trialBanner(
                    family: face.family, languageID: language?.rawValue,
                    replacedFamily: replaced, first: self.recipe.materials.isEmpty))
        }
        picker.onUse = { [weak self] in self?.usePickedFace($0) }
        picker.onCancel = { [weak self] in self?.cancelPicker() }
        picker.open(
            .init(
                request: request, main: recipe.main, recipeKeys: Set(recipe.keys), suggestions: suggestions,
                preferredFamilies: preferred), catalog: catalogFaces, status: catalogStatus)
    }
    public func usePickedFace(_ face: FaceRecord) {
        guard let request = pickRequest, !isBuilding else { cancelPicker(); return }
        let catalog = FaceCatalog(catalogFaces), language = picker.languageID
        edit { recipe in
            if let key = request.replaceKey {
                recipe.replace(key, with: face, keepAdjustments: false)
            } else {
                recipe.add(
                    face, for: recipe.materials.isEmpty || language == "any" ? nil : LanguageID(rawValue: language))
            }
            if recipe.defaultWeight != nil { recipe.applyRealWeights(in: catalog) }
        }
        cancelPicker()
    }
    public func cancelPicker() {
        picker.cancel(); pickRequest = nil; trial = nil
        picker.restoreFocus()
    }
    public func findFont() {
        if pickRequest != nil {
            picker.focusSearch(true)
        } else {
            openPicker(.init(languageID: recipe.materials.isEmpty ? "latin" : "any"))
        }
    }
    private func rememberPickerFocus() {
        let window = NSApp?.keyWindow
        let responder = window?.firstResponder
        picker.restoreFocus = { [weak window, weak responder] in
            Task { @MainActor in
                if let view = responder as? NSView, view.window === window { window?.makeFirstResponder(view); return }
                @MainActor func preview(in view: NSView) -> NSView? {
                    if view.identifier?.rawValue == "FPPreviewTextView" { return view }
                    return view.subviews.lazy.compactMap { preview(in: $0) }.first
                }
                if let content = window?.contentView, let view = preview(in: content) {
                    window?.makeFirstResponder(view)
                }
            }
        }
    }
}
