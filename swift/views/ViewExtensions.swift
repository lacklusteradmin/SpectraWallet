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
    func spectraPressable(scale: CGFloat = 0.985, opacity: CGFloat = 0.92) -> some View {
        modifier(SpectraPressableModifier(scale: scale, opacity: opacity))
    }
}

private struct SpectraPressableModifier: ViewModifier {
    let scale: CGFloat
    let opacity: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || !isPressed ? 1 : scale)
            .opacity(isPressed ? opacity : 1)
            .animation(.snappy(duration: 0.16), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
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

struct SpectraLoadingGlyph: View {
    var size: CGFloat = 28
    var tint: Color = .orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false
    @State private var isSpinning = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.14))
            Circle()
                .trim(from: 0.18, to: 0.84)
                .stroke(tint.opacity(0.82), style: StrokeStyle(lineWidth: max(2, size * 0.09), lineCap: .round))
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
            Text("S")
                .font(.system(size: size * 0.44, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (isPulsing ? 1.06 : 0.94))
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
    }
}

struct SpectraLoadingRow: View {
    let title: String
    var subtitle: String? = nil
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 12) {
            SpectraLoadingGlyph(size: 30, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string(title))
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(AppLocalization.string(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct SpectraLoadingCard: View {
    let title: String
    var subtitle: String? = nil
    var lineCount: Int = 3
    var tint: Color = .orange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SpectraLoadingRow(title: title, subtitle: subtitle, tint: tint)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<max(1, lineCount), id: \.self) { index in
                    SpectraShimmer(cornerRadius: 6, height: index == lineCount - 1 ? 12 : 14)
                        .frame(maxWidth: index == lineCount - 1 ? 190 : .infinity, alignment: .leading)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
}

struct SpectraEmptyStateCard: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var actionSystemImage: String = "arrow.right"
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SpectraEmptyStateContent(title: title, message: message, systemImage: systemImage)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(AppLocalization.string(actionTitle), systemImage: actionSystemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .spectraPressable()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.03)), in: .rect(cornerRadius: 24))
    }
}

struct SpectraEmptyStateContent: View {
    let title: String
    let message: String
    var systemImage: String = "tray"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.white.opacity(0.04)), in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string(title))
                    .font(.headline)
                Text(AppLocalization.string(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
