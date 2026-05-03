import SwiftUI

// MARK: - TorStatusBadge

/// Compact pill shown in the Settings row and the dashboard toolbar.
struct TorStatusBadge: View {
    let status: TorStatus
    var body: some View {
        HStack(spacing: 4) {
            statusDot
            Text(statusLabel).font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12), in: Capsule())
    }
    @ViewBuilder private var statusDot: some View {
        switch status {
        case .bootstrapping:
            ProgressView().scaleEffect(0.55).frame(width: 8, height: 8)
        default:
            Circle().fill(statusColor).frame(width: 6, height: 6)
        }
    }
    private var statusLabel: String {
        switch status {
        case .stopped:          return "Off"
        case .bootstrapping(let p): return p > 0 ? "\(p)%" : "Starting"
        case .ready:            return "On"
        case .error:            return "Error"
        }
    }
    private var statusColor: Color {
        switch status {
        case .stopped:          return .secondary
        case .bootstrapping:    return .orange
        case .ready:            return .green
        case .error:            return .red
        }
    }
}

// MARK: - TorSettingsView

struct TorSettingsView: View {
    @Bindable var store: AppState
    @State private var editingProxyAddress: String = ""
    @FocusState private var proxyFieldFocused: Bool
    var body: some View {
        Form {
            torMainSection
            if store.torEnabled {
                connectionModeSection
                if !store.torUseCustomProxy { privacySection }
            }
            aboutSection
        }
        .navigationTitle(AppLocalization.string("Tor Network"))
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear { editingProxyAddress = store.torCustomProxyAddress }
    }

    // MARK: Sections

    private var torMainSection: some View {
        Section {
            Toggle(isOn: $store.torEnabled) {
                Label(AppLocalization.string("Enable Tor"), systemImage: "network.badge.shield.half.filled")
            }
            statusRow
            if case .error = store.torStatus {
                reconnectButton
            }
        } header: {
            Text(AppLocalization.string("Tor Network"))
        } footer: {
            Text(AppLocalization.string("Routes all blockchain requests through the Tor network so your IP address is never sent to any RPC provider or block explorer."))
        }
    }

    @ViewBuilder private var statusRow: some View {
        HStack {
            Text(AppLocalization.string("Status"))
            Spacer()
            TorStatusBadge(status: store.torStatus)
        }
        if case .bootstrapping(let pct) = store.torStatus {
            ProgressView(value: Double(pct), total: 100)
                .tint(.orange)
                .animation(.easeInOut, value: pct)
        }
        if case .error(let msg) = store.torStatus {
            Text(msg).font(.caption).foregroundStyle(.red).lineLimit(3)
        }
    }

    private var reconnectButton: some View {
        Button {
            store.reconnectTor()
        } label: {
            Label(AppLocalization.string("Reconnect"), systemImage: "arrow.trianglehead.2.clockwise")
        }
    }

    private var connectionModeSection: some View {
        Section {
            Toggle(isOn: $store.torUseCustomProxy) {
                Label(AppLocalization.string("Use Custom SOCKS5 Proxy"), systemImage: "person.2.wave.2")
            }
            if store.torUseCustomProxy {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalization.string("SOCKS5 Address")).font(.footnote).foregroundStyle(.secondary)
                    TextField("socks5://127.0.0.1:9150", text: $editingProxyAddress)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($proxyFieldFocused)
                        .onSubmit { applyProxyAddress() }
                    if editingProxyAddress != store.torCustomProxyAddress {
                        Button(AppLocalization.string("Apply")) { applyProxyAddress() }
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        } header: {
            Text(AppLocalization.string("Connection Mode"))
        } footer: {
            Text(
                store.torUseCustomProxy
                    ? AppLocalization.string("Points all traffic at your own SOCKS5 proxy (e.g. Orbot on port 9150). Arti is not started.")
                    : AppLocalization.string("Uses the built-in Arti Tor client. No external app required.")
            )
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: $store.torKillSwitch) {
                Label(AppLocalization.string("Kill Switch"), systemImage: "shield.lefthalf.filled.slash")
            }
        } header: {
            Text(AppLocalization.string("Privacy"))
        } footer: {
            Text(AppLocalization.string("When enabled, network requests are paused if the Tor circuit drops instead of falling back to a direct connection."))
        }
    }

    private var aboutSection: some View {
        Section(AppLocalization.string("About")) {
            LabeledContent(AppLocalization.string("Tor client"), value: "Arti (embedded)")
            LabeledContent(AppLocalization.string("SOCKS5 port"), value: store.torUseCustomProxy ? store.torCustomProxyAddress : "127.0.0.1:19050")
            LabeledContent(AppLocalization.string("Stream isolation"), value: AppLocalization.string("Per connection"))
            LabeledContent(AppLocalization.string("Onion routing hops"), value: "3")
        }
    }

    // MARK: Helpers

    private func applyProxyAddress() {
        proxyFieldFocused = false
        let trimmed = editingProxyAddress.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.torCustomProxyAddress = trimmed
        if store.torEnabled && store.torUseCustomProxy {
            store.reconnectTor()
        }
    }
}
