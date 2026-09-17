import Foundation

@MainActor
extension AppState {
    /// One chain's self-tests: the offline suite core keeps for every chain in
    /// the catalog, plus — on an EVM chain — a probe of the endpoint it is
    /// actually pointed at.
    ///
    /// `runEthereumSelfTests` stood beside this: the same bookkeeping wired to
    /// one chain, with three extra probes. Two of them are gone. The
    /// JSON-shape check tested core's own document builder, which core tests
    /// where it is built; the portfolio fetch was the balance refresh with a
    /// different error message, and it named Ethereum in four more places. The
    /// third says something the offline suite cannot — whether the node this
    /// chain is pointed at is that chain's node — so it runs for the whole EVM
    /// family rather than for the one chain that had a button.
    func runSelfTests(for chainName: String) async {
        guard !selfTests(for: chainName).isRunning else { return }
        selfTests[chainName, default: .init()].isRunning = true
        defer { selfTests[chainName, default: .init()].isRunning = false }
        var results = ChainSelfTests.run(chainName)
        // Core stores a custom RPC only once it is a valid URL.
        let customRPC = rpcEndpoint(forChain: chainName)
        if let chain = Chain(displayName: chainName), chain.isEVM,
            let rpc = customRPC.isEmpty ? AppEndpointDirectory.evmRPCEndpoints(for: chainName).first : customRPC
        {
            results += await selfTestsRunEvmRpc(chainId: chain.id, rpcUrl: rpc, rpcLabel: rpc)
        }
        selfTests[chainName] = .init(results: results, isRunning: true, lastRunAt: Date())

        let failedCount = results.filter { !$0.passed }.count
        let abbrev = Chain(displayName: chainName)?.gasTokenSymbol ?? chainName
        appendChainOperationalEvent(
            failedCount == 0 ? .info : .warning, chainName: chainName,
            message: failedCount == 0
                ? "\(abbrev) self-tests passed (\(results.count) checks)."
                : "\(abbrev) self-tests completed with \(failedCount) failure(s).")
    }
    func operationalEvents(for chainName: String) async -> [DiagnosticLog] {
        await WalletServiceBridge.shared.operationalEvents(chainName: chainName)
    }
    func runUTXORescan(chainName: String) async {
        guard let chain = Chain(displayName: chainName), !self[rescanFor: chainName].isRunning else { return }
        self[rescanFor: chainName].isRunning = true
        defer { self[rescanFor: chainName].isRunning = false }
        appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan started.")
        if await performCoreRefresh(.deepRescan(chainId: chain.id)) {
            self[rescanFor: chainName].lastRunAt = Date()
            appendChainOperationalEvent(.info, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan completed.")
        } else {
            appendChainOperationalEvent(.warning, chainName: chainName, message: "\(chain.gasTokenSymbol) rescan failed or completed partially. See refresh errors.")
        }
    }
}
