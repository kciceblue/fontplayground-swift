import FPAppUI
import Foundation

/// Runs the self-test before NSApplication exists, without a window, Dock icon, or activation.
@main
enum Launcher {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") {
            let environment = ProcessInfo.processInfo.environment
            Task.detached {
                exit(await SelfTest.run(arguments: arguments, environment: environment))
            }
            dispatchMain()
        }
        FontPlaygroundApp.main()
    }
}
