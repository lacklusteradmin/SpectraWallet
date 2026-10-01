import SwiftUI

/// One derivation path the scan found funds on.
struct FundsFinderHit: Identifiable {
    let id = UUID()
    let candidate: FundsFinderCandidate
    let balanceDisplay: String
    let smallestUnit: String
}

/// Scan a seed's derivation paths for funded addresses.
///
/// The scan's state is this screen's: nothing else reads it, and leaving the
/// screen cancels it. It sat on `AppState` as six underscore-prefixed
/// properties behind six forwarding ones, with a comment claiming
/// `@Observable` required that shape.
struct FundsFinderView: View {
    let bridge: WalletServiceBridge
    @State private var seedPhrase: String = ""
    @State private var passphrase: String = ""
    @State private var showPassphrase: Bool = false
    @State private var hasStarted: Bool = false
    @State private var wordSlots: [String] = Array(repeating: "", count: 24)
    @State private var showAll24: Bool = false
    @FocusState private var focusedSlot: Int?
    @ScaledMetric(relativeTo: .caption2) private var wordIndexWidth: CGFloat = 16
    @State private var isScanning = false
    @State private var progress: Double = 0
    @State private var hits: [FundsFinderHit] = []
    @State private var checkedCount = 0
    @State private var totalCount = 0
    @State private var scanError: String?
    @State private var scanTask: Task<Void, Never>?

    private var canStart: Bool {
        let words = seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count >= 12 && !isScanning
    }

    var body: some View {
        ZStack {
            SpectraBackdrop().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: SpectraLayout.Space.m) {
                    if !hasStarted {
                        inputSection
                    } else {
                        scanProgressSection
                        if !hits.isEmpty {
                            hitsSection
                        }
                        if let error = scanError {
                            errorBanner(error)
                        }
                        if !isScanning && hits.isEmpty && scanError == nil {
                            emptyResultsSection
                        }
                    }
                }
                .padding(.horizontal, SpectraLayout.Space.l)
                .padding(.top, SpectraLayout.Space.l)
                .padding(.bottom, SpectraLayout.Space.xxl)
            }
        }
        .navigationTitle(AppLocalization.string("Funds Finder"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasStarted && !isScanning {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalization.string("New Scan")) {
                        resetScan()
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
            resetScan()
        }
    }

    // MARK: - Scan

    private func startScan(seedPhrase: String, passphrase: String?) {
        guard !isScanning else { return }
        resetScan()
        isScanning = true
        scanTask = Task { @MainActor in
            do {
                let service = try bridge.service()
                let request = FundsFinderRequest(seedPhrase: seedPhrase, passphrase: passphrase)
                // Deriving every candidate address from the seed is synchronous
                // work; keep it off the main actor.
                let scan = try await Task.detached {
                    try service.beginFundsScan(request: request, chainId: nil)
                }.value
                guard !Task.isCancelled else { return }
                repeat {
                    let batch = await scan.nextBatch()
                    guard !Task.isCancelled else { return }
                    totalCount = Int(batch.total)
                    checkedCount = Int(batch.checked)
                    progress = batch.total == 0 ? 1 : Double(batch.checked) / Double(batch.total)
                    for read in batch.reads {
                        if let error = read.error { scanError = error }
                        if read.funded, let balance = read.balance {
                            hits.append(FundsFinderHit(
                                candidate: read.candidate, balanceDisplay: balance.amountDisplay,
                                smallestUnit: balance.smallestUnit))
                        }
                    }
                    if batch.complete { break }
                } while !Task.isCancelled
            } catch {
                if !Task.isCancelled { scanError = error.localizedDescription }
            }
            isScanning = false
        }
    }

    private func resetScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progress = 0
        hits = []
        checkedCount = 0
        totalCount = 0
        scanError = nil
    }

    // MARK: - Input section

    private var inputSection: some View {
        VStack(spacing: SpectraLayout.Space.m) {
            headerCard
            seedPhraseCard
            passphraseCard
            disclaimerCard
            startButton
        }
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: SpectraLayout.Space.m) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
                Text(AppLocalization.string("Scan All Derivation Paths"))
                    .font(.headline)
                Text(AppLocalization.string("Enter your seed phrase to scan 150+ derivation paths across Bitcoin, Ethereum, Solana, and 10+ more chains — instantly revealing which paths hold funds."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    private var seedPhraseCard: some View {
        let slotCount = showAll24 ? 24 : 12
        let count = filledWordCount
        return VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack {
                Text(AppLocalization.string("Seed Phrase")).font(.subheadline.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text(AppLocalization.format("%lld words", count: count, count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(count >= 12 ? Color.green : Color.spectraWarning)
                        .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.xxs)
                        .background(Capsule().fill(count >= 12 ? Color.green.opacity(0.14) : Color.spectraWarning.opacity(0.14)))
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: SpectraLayout.Space.xs) {
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
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    private func wordSlotView(index: Int, slotCount: Int) -> some View {
        HStack(spacing: SpectraLayout.Space.xs) {
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: wordIndexWidth, alignment: .trailing)
            TextField("", text: Binding(
                get: { wordSlots[index] },
                set: { newVal in
                    let parts = newVal.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
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
        .padding(.horizontal, SpectraLayout.Space.s).padding(.vertical, SpectraLayout.Space.s)
        .spectraInsetFill(cornerRadius: SpectraLayout.Radius.control)
        .overlay(RoundedRectangle(cornerRadius: SpectraLayout.Radius.control, style: .continuous)
            .stroke(focusedSlot == index ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: focusedSlot == index)
    }

    private var filledWordCount: Int { wordSlots.filter { !$0.isEmpty }.count }
    private func syncSeedPhrase() { seedPhrase = wordSlots.filter { !$0.isEmpty }.joined(separator: " ") }

    private var passphraseCard: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.s) {
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
            .padding(SpectraLayout.Space.m)
            .spectraInputFieldStyle(cornerRadius: SpectraLayout.Radius.inner)
            Text(AppLocalization.string("A passphrase creates a different wallet. Leave blank unless you set one up."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: SpectraLayout.Space.s) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
            Text(AppLocalization.string("Your seed phrase never leaves this device. Derivation and balance checks happen locally and via your configured RPC endpoints."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding(SpectraLayout.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    private var startButton: some View {
        Button {
            guard canStart else { return }
            hasStarted = true
            startScan(
                seedPhrase: seedPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
                passphrase: passphrase.isEmpty ? nil : passphrase
            )
        } label: {
            Label(AppLocalization.string("Start Scan"), systemImage: "magnifyingglass")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, SpectraLayout.Space.l)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canStart)
        .clipShape(RoundedRectangle(cornerRadius: SpectraLayout.Radius.inner, style: .continuous))
    }

    // MARK: - Progress section

    private var scanProgressSection: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.m) {
            HStack {
                if isScanning {
                    SpectraLoadingGlyph(size: 26, tint: .accentColor)
                    Text(AppLocalization.string("Scanning…"))
                        .font(.headline)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(AppLocalization.string("Scan Complete"))
                        .font(.headline)
                }
                Spacer()
                if totalCount > 0 {
                    Text(AppLocalization.format("%lld / %lld",
                        checkedCount, totalCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if totalCount > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            if isScanning {
                Text(AppLocalization.string("Checking addresses across all derivation paths…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if hits.isEmpty {
                Text(AppLocalization.format("Checked %lld paths — no funds found", count: checkedCount, checkedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(AppLocalization.format("Found %lld paths with funds across %lld checked",
                    count: hits.count, hits.count, checkedCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }

    // MARK: - Hits section

    private var hitsSection: some View {
        SpectraRowGroup(
            title: AppLocalization.format("%lld paths with funds found", count: hits.count, hits.count),
            data: hits, dividerInset: SpectraLayout.rowHorizontal
        ) { hit in
            FundsFinderHitRow(hit: hit)
        }
    }

    private var emptyResultsSection: some View {
        VStack(spacing: SpectraLayout.Space.s) {
            Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(.secondary)
            Text(AppLocalization.string("No funds found")).font(.headline)
            Text(AppLocalization.string("No balance was detected at any of the scanned derivation paths. Double-check your seed phrase and try with a BIP-39 passphrase if you set one."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(SpectraLayout.Space.l)
        .frame(maxWidth: .infinity)
        .spectraCardFill()
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: SpectraLayout.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.spectraWarning)
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding(SpectraLayout.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spectraCardFill()
    }
}

// MARK: - Hit row

private struct FundsFinderHitRow: View {
    let hit: FundsFinderHit
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: SpectraLayout.Space.xs) {
            HStack {
                VStack(alignment: .leading, spacing: SpectraLayout.Space.xxs) {
                    Text(hit.candidate.chainName)
                        .font(.subheadline.weight(.semibold))
                    Text(hit.candidate.pathLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(hit.balanceDisplay)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
            }
            HStack(spacing: SpectraLayout.Space.xs) {
                Text(hit.candidate.derivationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: SpectraLayout.Space.xs)
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
        .spectraRowPadding()
    }
}
