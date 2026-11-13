import Foundation
import SwiftTUI
import SwiftGrip
import SwiftTUITesting

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
              swift run SwiftGrip --snapshot       Render a single 120x36 frame to stdout and exit
              swift run SwiftGrip --screenshot <f> Save high-resolution PNG screenshot to file
            """)
            return
        }

        let dbPath: String
        if let firstFileArg = args.first(where: { !$0.hasPrefix("-") && !$0.hasSuffix(".png") }) {
            dbPath = firstFileArg
        } else {
            dbPath = ":memory:"
        }

        let db = try SQLiteDatabase(path: dbPath, seedDemoIfEmpty: true)
        let viewModel = SwiftGripViewModel(database: db)
        let rootView = SwiftGripMainView(viewModel: viewModel)

        if let shotIdx = args.firstIndex(of: "--screenshot"), shotIdx + 1 < args.count {
            let outPath = args[shotIdx + 1]
            let headless = HeadlessBackend(width: 120, height: 36)
            let app = TerminalApplication(rootView: rootView, backend: headless)
            let buf = app.renderFrame()
            #if canImport(AppKit)
            try TerminalScreenshotRenderer.saveScreenshot(buffer: buf, to: URL(fileURLWithPath: outPath), title: "SwiftGrip — Terminal SQLite IDE")
            print("Saved screenshot to \(outPath)")
            #else
            let svg = TerminalScreenshotRenderer.renderToSVG(buffer: buf, title: "SwiftGrip — Terminal SQLite IDE")
            try svg.write(to: URL(fileURLWithPath: outPath), atomically: true, encoding: .utf8)
            print("Saved SVG screenshot to \(outPath)")
            #endif
            return
        }

        if args.contains("--snapshot") {
            let headless = HeadlessBackend(width: 120, height: 36)
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
