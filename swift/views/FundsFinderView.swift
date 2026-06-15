import SwiftUI

// MARK: - FundsFinderView

struct FundsFinderView: View {
    let store: AppState
    @State private var seedPhrase: String = ""
    @State private var passphrase: String = ""
    @State private var showPassphrase: Bool = false
    @State private var hasStarted: Bool = false
    @State private var wordSlots: [String] = Array(repeating: "", count: 24)
    @State private var showAll24: Bool = false
    @FocusState private var focusedSlot: Int?

    private var canStart: Bool {
        let words = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return words.count >= 12 && !store.isFundsFinderScanning
    }

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if !hasStarted {
                        inputSection
                    } else {
                        scanProgressSection
                        if !store.fundsFinderHits.isEmpty {
                            hitsSection
                        }
                        if let error = store.fundsFinderScanError {
                            errorBanner(error)
                        }
                        if !store.isFundsFinderScanning && store.fundsFinderHits.isEmpty && store.fundsFinderScanError == nil {
                            emptyResultsSection
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(AppLocalization.string("Funds Finder"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasStarted && !store.isFundsFinderScanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("New Scan")) {
                        store.resetFundsFinder()
                        hasStarted = false
                        seedPhrase = ""
                        passphrase = ""
                        wordSlots = Array(repeating: "", count: 24)
                        showAll24 = false
                    }
                }
            }
        }
        .onDisappear {
            store.resetFundsFinder()
        }
    }

    // MARK: - Input section

    private var inputSection: some View {
        VStack(spacing: 16) {
            headerCard
            seedPhraseCard
            passphraseCard
            disclaimerCard
            startButton
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.string("Scan All Derivation Paths"))
                    .font(.headline)
                Text(AppLocalization.string("Enter your seed phrase to scan 150+ derivation paths across Bitcoin, Ethereum, Solana, and 10+ more chains — instantly revealing which paths hold funds."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 22)
    }

    private var seedPhraseCard: some View {
        let slotCount = showAll24 ? 24 : 12
        let count = filledWordCount
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.string("Seed Phrase")).font(.subheadline.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text(AppLocalization.format("%lld words", count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(count >= 12 ? Color.green : Color.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(count >= 12 ? Color.green.opacity(0.14) : Color.orange.opacity(0.14)))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(0..<slotCount, id: \.self) { i in
                    wordSlotView(index: i, slotCount: slotCount)
                }
            }
            if !showAll24 {
                Button { showAll24 = true } label: {
                    Text(AppLocalization.string("Using 24 words?"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 22)
    }

    private func wordSlotView(index: Int, slotCount: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 14, alignment: .trailing)
            TextField("", text: Binding(
                get: { wordSlots[index] },
                set: { newVal in
                    let parts = newVal.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count > 1 {
                        for (offset, word) in parts.prefix(slotCount - index).enumerated() {
                            wordSlots[index + offset] = word.lowercased()
                        }
                        if parts.count > 12 { showAll24 = true }
                        focusedSlot = min(index + parts.count, slotCount - 1)
                    } else {
                        wordSlots[index] = newVal.lowercased()
                    }
                    syncSeedPhrase()
                }
            ))
            .font(.system(.footnote, design: .monospaced).weight(.medium))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .focused($focusedSlot, equals: index)
            .onSubmit { if index < slotCount - 1 { focusedSlot = index + 1 } }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(.white.opacity(focusedSlot == index ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(focusedSlot == index ? Color.yellow.opacity(0.5) : Color.clear, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: focusedSlot == index)
    }

    private var filledWordCount: Int { wordSlots.filter { !$0.isEmpty }.count }
    private func syncSeedPhrase() { seedPhrase = wordSlots.filter { !$0.isEmpty }.joined(separator: " ") }

    private var passphraseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(AppLocalization.string("BIP-39 Passphrase")).font(.subheadline.weight(.semibold))
                Spacer()
                Text(AppLocalization.string("Optional")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Group {
                    if showPassphrase {
                        TextField(AppLocalization.string("Leave blank if none"), text: $passphrase)
                    } else {
                        SecureField(AppLocalization.string("Leave blank if none"), text: $passphrase)
                    }
                }
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Button {
                    showPassphrase.toggle()
                } label: {
                    Image(systemName: showPassphrase ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
            .padding(12)
            .spectraInputFieldStyle(cornerRadius: 12)
            Text(AppLocalization.string("A passphrase creates a different wallet. Leave blank unless you set one up."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 22)
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
            Text(AppLocalization.string("Your seed phrase never leaves this device. Derivation and balance checks happen locally and via your configured RPC endpoints."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 18)
    }

    private var startButton: some View {
        Button {
            guard canStart else { return }
            hasStarted = true
            store.startFundsFinderScan(
                seedPhrase: seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
        } label: {
            Label(AppLocalization.string("Start Scan"), systemImage: "magnifyingglass")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canStart)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Progress section

    private var scanProgressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if store.isFundsFinderScanning {
                    SpectraLoadingGlyph(size: 26, tint: .orange)
                    Text(AppLocalization.string("Scanning…"))
                        .font(.headline)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(AppLocalization.string("Scan Complete"))
                        .font(.headline)
                }
                Spacer()
                if store.fundsFinderTotalCount > 0 {
                    Text(AppLocalization.format("%lld / %lld",
                        store.fundsFinderCheckedCount, store.fundsFinderTotalCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if store.fundsFinderTotalCount > 0 {
                ProgressView(value: store.fundsFinderProgress)
                    .progressViewStyle(.linear)
                    .tint(.yellow)
            }
            if store.isFundsFinderScanning {
                Text(AppLocalization.string("Checking addresses across all derivation paths…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if store.fundsFinderHits.isEmpty {
                Text(AppLocalization.format("Checked %lld paths — no funds found", store.fundsFinderCheckedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(AppLocalization.format("Found %lld path(s) with funds across %lld checked",
                    store.fundsFinderHits.count, store.fundsFinderCheckedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 22)
    }

    // MARK: - Hits section

    private var hitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(.yellow)
                Text(AppLocalization.format("%lld path(s) with funds found", store.fundsFinderHits.count))
                    .font(.headline)
            }
            .padding(.bottom, 2)
            ForEach(store.fundsFinderHits) { hit in
                FundsFinderHitRow(hit: hit)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 22)
    }

    // MARK: - Empty & error

    private var emptyResultsSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(AppLocalization.string("No funds found")).font(.headline)
            Text(AppLocalization.string("No balance was detected at any of the scanned derivation paths. Double-check your seed phrase and try with a BIP-39 passphrase if you set one."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .spectraCardFill(cornerRadius: 22)
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill(cornerRadius: 18)
    }
}

// MARK: - Hit row

private struct FundsFinderHitRow: View {
    let hit: FundsFinderHit
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.candidate.chainName)
                        .font(.subheadline.weight(.semibold))
                    Text(hit.candidate.pathLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(hit.balanceDisplay)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.yellow)
            }
            HStack(spacing: 6) {
                Text(hit.candidate.derivationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = hit.candidate.address
                    isCopied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        isCopied = false
                    }
                } label: {
                    Label(
                        isCopied ? AppLocalization.string("Copied") : AppLocalization.string("Copy Address"),
                        systemImage: isCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .animation(.spring(duration: 0.25), value: isCopied)
            }
            Text(hit.candidate.address)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
