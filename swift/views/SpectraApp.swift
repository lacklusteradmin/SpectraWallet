import SwiftUI

@main
struct SpectraApp: App {
    @State private var store = AppState()
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
