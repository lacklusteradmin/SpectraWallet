import SwiftUI

struct AddCustomEndpointView: View {
    let store: AppState
    let directory: [EndpointDirectoryEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var chainId = ""
    @State private var api = ""
    @State private var url = ""
    @State private var capabilities: Set<String> = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let copy = EndpointsContentCopy.current
    private var availableEntries: [EndpointDirectoryEntry] {
        directory.filter { entry in
            guard let type = entry.record.api else { return false }
            return !endpointCapabilityOptions(chainId: entry.record.chainId, api: type).isEmpty
        }
    }
    private var networks: [String] {
        Array(Set(availableEntries.map(\.record.chainId))).sorted()
    }
    private var types: [String] {
        Array(Set(availableEntries.filter { $0.record.chainId == chainId }.map(\.apiName))).sorted()
    }
    private var capabilityOptions: [String] {
        guard let type = directory.first(where: { $0.record.chainId == chainId && $0.apiName == api })?.record.api else { return [] }
        return endpointCapabilityOptions(chainId: chainId, api: type)
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
            Section {
                ForEach(capabilityOptions, id: \.self) { capability in
                    Toggle(isOn: Binding(
                        get: { capabilities.contains(capability) },
                        set: { if $0 { capabilities.insert(capability) } else { capabilities.remove(capability) } }
                    )) {
                        VStack(alignment: .leading) {
                            Text(AppLocalization.string("endpointCapability.\(capability)"))
                            Text(AppLocalization.string("endpointCapabilityDescription.\(capability)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(AppLocalization.string("Endpoint capabilities"))
            } footer: {
                Text(AppLocalization.string(capabilityOptions.isEmpty
                    ? "This API has no supported custom endpoint operations."
                    : "Select the operations enabled on this endpoint. These are your declarations, not verified probe results."))
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
            capabilities.removeAll()
            if !types.contains(api) { api = types.first ?? "" }
        }
        .onChange(of: api) { _, _ in capabilities.removeAll() }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Save")) {
                    isSaving = true
                    Task { @MainActor in
                        do {
                            let transition = try await store.applyStateCommand(.setAppSetting(
                                update: .addCustomEndpoint(capabilities: capabilities.sorted(), chainId: chainId, api: api, endpoint: url)))
                            if transition.events.contains(where: { if case .appSettingRejected = $0 { return true }; return false }) {
                                errorMessage = copy.invalidEndpointMessage
                            } else {
                                dismiss()
                            }
                        } catch { errorMessage = error.localizedDescription }
                        isSaving = false
                    }
                }.disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || api.isEmpty || capabilities.isEmpty || isSaving)
            }
        }
    }
}
