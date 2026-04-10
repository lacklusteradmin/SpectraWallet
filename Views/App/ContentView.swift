import SwiftUI

private struct SpectraInputFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let borderColor: Color?

    private var resolvedBackground: Color {
        colorScheme == .light ? Color.black.opacity(0.045) : Color.white.opacity(0.08)
    }

    private var resolvedBorderColor: Color {
        borderColor ?? (colorScheme == .light ? Color.black.opacity(0.18) : Color.white.opacity(0.14))
    }

    func body(content: Content) -> some View {
        content
            .background(resolvedBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(resolvedBorderColor, lineWidth: 1)
            )
    }
}

extension View {
    func spectraBubbleFill(alignment: Alignment = .leading) -> some View {
        frame(maxWidth: .infinity, alignment: alignment)
    }

    func spectraInputFieldStyle(cornerRadius: CGFloat = 18, borderColor: Color? = nil) -> some View {
        modifier(SpectraInputFieldChrome(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}

struct ContentView: View {
    @StateObject private var store: WalletStore
    @ObservedObject private var runtimeState: WalletRuntimeState
    @Environment(\.scenePhase) private var scenePhase

    @MainActor
    init() {
        let store = WalletStore()
        _store = StateObject(wrappedValue: store)
        _runtimeState = ObservedObject(wrappedValue: store.runtimeState)
    }

    @MainActor
    init(store: WalletStore) {
        _store = StateObject(wrappedValue: store)
        _runtimeState = ObservedObject(wrappedValue: store.runtimeState)
    }

    private func refreshAppStateForActivePhase() {
        store.setAppIsActive(true)
        Task {
            await store.refreshForForegroundIfNeeded()
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key)
    }

    var body: some View {
        ZStack {
            MainTabView(store: store)
                .blur(radius: runtimeState.isAppLocked ? 8 : 0)
                .disabled(runtimeState.isAppLocked)

            if runtimeState.isAppLocked {
                VStack(spacing: 14) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(localized("content.locked.title"))
                        .font(.headline)
                    Text(localized("content.locked.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let appLockError = runtimeState.appLockError {
                        Text(appLockError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Button {
                        Task {
                            await store.unlockApp()
                        }
                    } label: {
                        Label(localized("content.locked.unlock"), systemImage: "faceid")
                            .frame(maxWidth: 220)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(28)
            }
        }
        .onAppear {
            store.setAppIsActive(scenePhase == .active)
            if scenePhase == .active {
                refreshAppStateForActivePhase()
            }
        }
        .environment(\.locale, AppLocalization.locale)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                refreshAppStateForActivePhase()
            case .background:
                store.setAppIsActive(false)
            case .inactive:
                store.setAppIsActive(false)
            default:
                break
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

@main
struct SpectraApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
