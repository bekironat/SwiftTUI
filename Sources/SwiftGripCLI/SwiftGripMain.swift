import Foundation
import SwiftTUI
import SwiftGrip

@main
@MainActor
struct SwiftGripCLI {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            print("""
            SwiftGrip — Terminal SQLite IDE built with SwiftTUI (Ratatui + SwiftUI)

            Usage:
              swift run SwiftGrip                  Launch with in-memory demo database
              swift run SwiftGrip --demo           Launch with in-memory demo database
              swift run SwiftGrip <path.sqlite>    Open or create a SQLite database file
              swift run SwiftGrip --snapshot       Render a single 120x34 frame to stdout and exit
            """)
            return
        }

        let dbPath: String
        if let firstFileArg = args.first(where: { !$0.hasPrefix("-") }) {
            dbPath = firstFileArg
        } else {
            dbPath = ":memory:"
        }

        let db = try SQLiteDatabase(path: dbPath, seedDemoIfEmpty: true)
        let viewModel = SwiftGripViewModel(database: db)
        let rootView = SwiftGripMainView(viewModel: viewModel)

        if args.contains("--snapshot") {
            let headless = HeadlessBackend(width: 120, height: 34)
            let app = TerminalApplication(rootView: rootView, backend: headless)
            let buf = app.renderFrame()
            print(buf.snapshot(trimTrailingSpaces: true))
            return
        }

        let backend = POSIXTerminalBackend(enableMouse: true)
        let app = TerminalApplication(rootView: rootView, backend: backend)
        try app.run()
    }
}
