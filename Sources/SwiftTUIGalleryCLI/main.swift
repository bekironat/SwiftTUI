import Foundation
import SwiftTUI
import SwiftTUIGallery
import SwiftTUITesting

@main
@MainActor
struct SwiftTUIGalleryMain {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            print("""
            SwiftTUIGallery — Component Showcase for SwiftTUI

            Usage:
              swift run SwiftTUIGallery                  Interactive component preview
              swift run SwiftTUIGallery [category]       Open directly to category (e.g. typography, layout, charts)
              swift run SwiftTUIGallery --snapshot       Render a 120x36 snapshot to stdout and exit
              swift run SwiftTUIGallery --screenshot <f> Save high-resolution PNG screenshot to file
            """)
            return
        }

        let viewModel = GalleryViewModel()

        if let catArg = args.first(where: { !$0.hasPrefix("-") && !$0.hasSuffix(".png") }),
           let match = GalleryCategory.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveContains(catArg) }) {
            viewModel.selectedCategory = match
        }

        let rootView = GalleryMainView(viewModel: viewModel)

        if let shotIdx = args.firstIndex(of: "--screenshot"), shotIdx + 1 < args.count {
            let outPath = args[shotIdx + 1]
            let headless = HeadlessBackend(width: 120, height: 36)
            let app = TerminalApplication(rootView: rootView, backend: headless)
            let buf = app.renderFrame()
            #if canImport(AppKit)
            try TerminalScreenshotRenderer.saveScreenshot(buffer: buf, to: URL(fileURLWithPath: outPath), title: "SwiftTUIGallery — Component Showcase")
            print("Saved screenshot to \(outPath)")
            #else
            let svg = TerminalScreenshotRenderer.renderToSVG(buffer: buf, title: "SwiftTUIGallery — Component Showcase")
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
