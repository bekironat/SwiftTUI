import Foundation
import SwiftTUI
import SwiftTUIGallery

@main
@MainActor
struct SwiftTUIGalleryMain {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.contains("--help") || args.contains("-h") {
            print("""
            SwiftTUIGallery — Component Showcase for SwiftTUI

            Usage:
              swift run SwiftTUIGallery              Interactive component preview
              swift run SwiftTUIGallery --snapshot   Render a 120x34 snapshot to stdout and exit
            """)
            return
        }

        let viewModel = GalleryViewModel()

        if let catArg = args.first(where: { !$0.hasPrefix("-") }),
           let match = GalleryCategory.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveContains(catArg) }) {
            viewModel.selectedCategory = match
        }

        let rootView = GalleryMainView(viewModel: viewModel)

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
