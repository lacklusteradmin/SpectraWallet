import Foundation

struct WalletChainRefreshDescriptor {
    let chainID: WalletChainID
    let executeRefresh: (WalletStore, Bool) async -> Void
    let executeBalancesOnly: (WalletStore) async -> Void
    let executeHistoryOnly: ((WalletStore) async -> Void)?

    var chainName: String { chainID.displayName }
}

extension WalletStore {
    var lastHistoryRefreshAtByChainID: [WalletChainID: Date] {
        get {
            Dictionary(
                uniqueKeysWithValues: lastHistoryRefreshAtByChain.compactMap { key, value in
                    WalletChainID(key).map { ($0, value) }
                }
            )
        }
        set {
            lastHistoryRefreshAtByChain = Dictionary(
                uniqueKeysWithValues: newValue.map { ($0.key.displayName, $0.value) }
            )
        }
    }

    var plannedChainRefreshDescriptors: [WalletChainRefreshDescriptor] {
        [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBitcoinBalances()
                    if refreshHistory {
                        await store.refreshBitcoinTransactions(limit: 20, loadMore: false)
                    }
                    await store.refreshPendingBitcoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin Cash")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin Cash")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin Cash")
                    await store.refreshBitcoinCashBalances()
                    if refreshHistory {
                        await store.refreshBitcoinCashTransactions(limit: 20, loadMore: false)
                    }
                    await store.refreshPendingBitcoinCashTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinCashBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Bitcoin SV")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Bitcoin SV")
                    await store.refreshUTXOReceiveReservationState(chainName: "Bitcoin SV")
                    await store.refreshBitcoinSVBalances()
                    if refreshHistory {
                        await store.refreshBitcoinSVTransactions(limit: 20, loadMore: false)
                    }
                    await store.refreshPendingBitcoinSVTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBitcoinSVBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Litecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshUTXOAddressDiscovery(chainName: "Litecoin")
                    await store.refreshUTXOReceiveReservationState(chainName: "Litecoin")
                    await store.refreshLitecoinBalances()
                    if refreshHistory {
                        await store.refreshLitecoinTransactions(limit: 20, loadMore: false)
                    }
                    await store.refreshPendingLitecoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshLitecoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Dogecoin")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshDogecoinAddressDiscovery()
                    await store.refreshDogecoinReceiveReservationState()
                    await store.refreshDogecoinBalances()
                    if refreshHistory {
                        await store.refreshDogecoinTransactions(loadMore: false)
                    }
                    await store.refreshPendingDogecoinTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshDogecoinBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshEthereumBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Ethereum", loadMore: false)
                    }
                    await store.refreshPendingEthereumTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshEthereumBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Ethereum")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Arbitrum")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshArbitrumBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Arbitrum", loadMore: false)
                    }
                    await store.refreshPendingArbitrumTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshArbitrumBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Arbitrum")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Optimism")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshOptimismBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Optimism", loadMore: false)
                    }
                    await store.refreshPendingOptimismTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshOptimismBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Optimism")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Ethereum Classic")!,
                executeRefresh: { store, _ in
                    await store.refreshETCBalances()
                    await store.refreshPendingETCTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshETCBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("BNB Chain")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshBNBBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "BNB Chain", loadMore: false)
                    }
                    await store.refreshPendingBNBTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshBNBBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "BNB Chain")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Avalanche")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshAvalancheBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Avalanche", loadMore: false)
                    }
                    await store.refreshPendingAvalancheTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshAvalancheBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Hyperliquid")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshHyperliquidBalances()
                    if refreshHistory {
                        await store.refreshEVMTokenTransactions(chainName: "Hyperliquid", loadMore: false)
                    }
                    await store.refreshPendingHyperliquidTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshHyperliquidBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshEVMTokenTransactions(chainName: "Hyperliquid")
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Tron")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshTronBalances()
                    if refreshHistory {
                        await store.refreshTronTransactions(loadMore: false)
                    }
                    await store.refreshPendingTronTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshTronBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshTronTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Solana")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshSolanaBalances()
                    if refreshHistory {
                        await store.refreshSolanaTransactions(loadMore: false)
                    }
                    await store.refreshPendingSolanaTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshSolanaBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshSolanaTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Cardano")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshCardanoBalances()
                    if refreshHistory {
                        await store.refreshCardanoTransactions(loadMore: false)
                    }
                    await store.refreshPendingCardanoTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshCardanoBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshCardanoTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("XRP Ledger")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshXRPBalances()
                    if refreshHistory {
                        await store.refreshXRPTransactions(loadMore: false)
                    }
                    await store.refreshPendingXRPTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshXRPBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshXRPTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Stellar")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshStellarBalances()
                    if refreshHistory {
                        await store.refreshStellarTransactions(loadMore: false)
                    }
                    await store.refreshPendingStellarTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshStellarBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshStellarTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Monero")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshMoneroBalances()
                    if refreshHistory {
                        await store.refreshMoneroTransactions(loadMore: false)
                    }
                    await store.refreshPendingMoneroTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshMoneroBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshMoneroTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Sui")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshSuiBalances()
                    if refreshHistory {
                        await store.refreshSuiTransactions(loadMore: false)
                    }
                    await store.refreshPendingSuiTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshSuiBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshSuiTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("NEAR")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshNearBalances()
                    if refreshHistory {
                        await store.refreshNearTransactions(loadMore: false)
                    }
                    await store.refreshPendingNearTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshNearBalances()
                },
                executeHistoryOnly: { store in
                    await store.refreshNearTransactions(loadMore: false)
                }
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Polkadot")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshPolkadotBalances()
                    if refreshHistory {
                        await store.refreshPolkadotTransactions(loadMore: false)
                    }
                    await store.refreshPendingPolkadotTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshPolkadotBalances()
                },
                executeHistoryOnly: nil
            )
        ]
    }

    var importedWalletRefreshDescriptors: [WalletChainRefreshDescriptor] {
        plannedChainRefreshDescriptors + [
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Aptos")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshAptosBalances()
                    if refreshHistory {
                        await store.refreshAptosTransactions(loadMore: false)
                    }
                    await store.refreshPendingAptosTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshAptosBalances()
                },
                executeHistoryOnly: nil
            ),
            WalletChainRefreshDescriptor(
                chainID: WalletChainID("Internet Computer")!,
                executeRefresh: { store, refreshHistory in
                    await store.refreshICPBalances()
                    if refreshHistory {
                        await store.refreshICPTransactions(loadMore: false)
                    }
                    await store.refreshPendingICPTransactions()
                },
                executeBalancesOnly: { store in
                    await store.refreshICPBalances()
                },
                executeHistoryOnly: nil
            )
        ]
    }
}
