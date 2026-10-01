import Foundation

public struct WeightChoice: Equatable {
    public var weight: Int?
    public var title: String
    public init(weight: Int?, title: String) { self.weight = weight; self.title = title }
    public static var standard: [WeightChoice] {
        let choices: [WeightChoice] = [
            .init(weight: nil, title: ShellText.asIs), .init(weight: 300, title: ShellText.weightLight),
            .init(weight: 400, title: ShellText.regular), .init(weight: 500, title: ShellText.medium),
            .init(weight: 600, title: ShellText.semibold), .init(weight: 700, title: ShellText.bold),
            .init(weight: 900, title: ShellText.heavy),
        ]
        return choices.map { choice in
            guard let weight = choice.weight else { return choice }
            let number = weight.formatted(.number)
            return WeightChoice(
                weight: weight,
                title: String(
                    localized: "\(choice.title) (\(number))", bundle: .module, comment: "recipe.weight.choice"))
        }
    }
}
