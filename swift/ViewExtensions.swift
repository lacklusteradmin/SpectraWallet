import SwiftUI
import UIKit
private struct SpectraInputFieldChrome: ViewModifier {
    let cornerRadius: CGFloat
    let borderColor: Color?
    func body(content: Content) -> some View {
        content.glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: cornerRadius))
    }
}
extension View {
    func spectraBubbleFill(alignment: Alignment = .leading) -> some View { frame(maxWidth: .infinity, alignment: alignment) }
    func spectraInputFieldStyle(cornerRadius: CGFloat = 18, borderColor: Color? = nil) -> some View {
        modifier(SpectraInputFieldChrome(cornerRadius: cornerRadius, borderColor: borderColor))
    }
}
extension Binding {
    static func isPresent<Wrapped: Sendable>(_ source: Binding<Wrapped?>) -> Binding<Bool> where Value == Bool {
        Binding<Bool>(
            get: { source.wrappedValue != nil },
            set: { if !$0 { source.wrappedValue = nil } }
        )
    }
}
@MainActor @ViewBuilder
func spectraDetailCard(title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        if let title { Text(AppLocalization.string(title)).font(.headline) }
        VStack(alignment: .leading, spacing: 12) { content() }
    }.padding(20).spectraBubbleFill().glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
}
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
                }.padding(28).glassEffect(.regular.tint(.white.opacity(0.05)), in: .rect(cornerRadius: 28)).padding(28)
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
// MARK: — Typography helpers
extension View {
    func spectraHintText() -> some View { font(.caption).foregroundStyle(.secondary) }
    func spectraSectionCaption() -> some View {
        font(.caption2.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

// MARK: — Semantic status colors
extension Color {
    static func spectraTransactionStatusColor(_ status: TransactionStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .confirmed: return .mint
        case .failed: return .red
        }
    }
    static func spectraTransactionAmountColor(isReceive: Bool) -> Color { isReceive ? .mint : .red }
    static func spectraPriceAlertStatusColor(isEnabled: Bool, hasTriggered: Bool) -> Color {
        if !isEnabled { return .gray }
        return hasTriggered ? .green : .orange
    }
}

// MARK: — Haptic helpers
@MainActor func spectraHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}
@MainActor func spectraNotificationHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType = .success) {
    UINotificationFeedbackGenerator().notificationOccurred(type)
}

// MARK: — Shimmer loading placeholder
struct SpectraShimmer: View {
    var cornerRadius: CGFloat = 8
    var height: CGFloat = 16
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.primary.opacity(0.08))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(
                    LinearGradient(colors: [.clear, Color.white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                ).offset(x: geo.size.width * (phase + 1))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

#Preview {
    ContentView(store: AppState())
}
@main
struct SpectraApp: App {
    @State private var store = AppState()
    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
