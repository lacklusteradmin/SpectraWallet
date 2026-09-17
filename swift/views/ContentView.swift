import SwiftUI

struct ContentView: View {
    @State private var store: AppState
    @Environment(\.scenePhase) private var scenePhase
    @MainActor
    init(store: AppState) {
        _store = State(wrappedValue: store)
    }
    private func refreshAppStateForActivePhase() {
        store.setAppIsActive(true)
        Task {
            await store.refreshForForegroundIfNeeded()
        }
    }
    var body: some View {
        ZStack {
            // Apply the blur modifier only when actually locked; a zero-radius
            // `.blur` still forces an off-screen compositing pass each frame,
            // which keeps the GPU busier than it needs to be when unlocked.
            if store.isAppLocked {
                MainTabView(store: store).blur(radius: 8).disabled(true)
            } else {
                MainTabView(store: store)
            }
            if store.isAppLocked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 40, weight: .semibold)).foregroundStyle(.secondary)
                    Text(AppLocalization.string("content.locked.title")).font(.title3.weight(.semibold))
                    Text(AppLocalization.string("content.locked.subtitle")).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let appLockError = store.appLockError { Text(appLockError).font(.caption).foregroundStyle(.red) }
                    Button {
                        Task { await store.unlockApp() }
                    } label: {
                        Label(AppLocalization.string("content.locked.unlock"), systemImage: "faceid")
                            .font(.body.weight(.semibold)).frame(maxWidth: 220).padding(.vertical, 6)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                }.padding(28).spectraElevatedFill().padding(28)
            }
        }.preferredColorScheme(store.preferences.appearanceMode == .dark ? .dark : store.preferences.appearanceMode == .light ? .light : nil)
        .onAppear {
            store.setAppIsActive(scenePhase == .active)
            if scenePhase == .active { refreshAppStateForActivePhase() }
        }.environment(\.locale, AppLocalization.locale).onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: refreshAppStateForActivePhase()
            case .background: store.setAppIsActive(false)
            case .inactive: store.setAppIsActive(false)
            default: break
            }
        }
    }
}

#Preview {
    ContentView(store: AppState())
}
