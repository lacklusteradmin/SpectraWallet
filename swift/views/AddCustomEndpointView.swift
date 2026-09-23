import SwiftUI

struct AddCustomEndpointView: View {
    let store: AppState
    let directory: [EndpointDirectoryEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var chainId = ""
    @State private var api = ""
    @State private var url = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let copy = EndpointsContentCopy.current
    private var networks: [String] {
        Array(Set(directory.filter { !$0.apiName.isEmpty }.map(\.record.chainId))).sorted()
    }
    private var types: [String] {
        Array(Set(directory.filter { $0.record.chainId == chainId && !$0.apiName.isEmpty }.map(\.apiName))).sorted()
    }
    var body: some View {
        Form {
            Section {
                Picker(AppLocalization.string("Network"), selection: $chainId) {
                    ForEach(networks, id: \.self) { id in
                        Text(Chain(id: id)?.displayName ?? id).tag(id)
                    }
                }
                Picker(copy.typeTitle, selection: $api) {
                    ForEach(types, id: \.self) { Text($0).tag($0) }
                }
                TextField(copy.urlPlaceholder, text: $url)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(copy.addEndpointTitle)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .onAppear {
            if chainId.isEmpty { chainId = networks.first ?? ""; api = types.first ?? "" }
        }
        .onChange(of: chainId) { _, _ in
            if !types.contains(api) { api = types.first ?? "" }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Save")) {
                    isSaving = true
                    Task { @MainActor in
                        do {
                            let transition = try await store.bridge.applyStateCommand(.setAppSetting(
                                update: .addCustomEndpoint(chainId: chainId, api: api, endpoint: url)))
                            if transition.events.contains(where: { if case .appSettingRejected = $0 { return true }; return false }) {
                                errorMessage = copy.invalidEndpointMessage
                            } else {
                                store.applyCoreState(transition.state, refreshPortfolio: false)
                                dismiss()
                            }
                        } catch { errorMessage = error.localizedDescription }
                        isSaving = false
                    }
                }.disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || api.isEmpty || isSaving)
            }
        }
    }
}
