import SwiftUI
import UIKit

@main
struct SpectraApp: App {
    @State private var store = AppState()

    init() {
        // The asset catalog's AccentColor (system orange) is the app's one
        // theme colour, and most controls read it on their own. A switch's
        // on state does not — it stays system green — so it is set here once
        // rather than with a `.tint` on every toggle. A root `.tint` would do
        // it too but also colours the toolbar glyphs, which stay monochrome.
        // The colour is named, not loaded: `UIColor(named: "AccentColor")`
        // this early resets the app's global accent to system blue.
        UISwitch.appearance().onTintColor = .systemOrange
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
