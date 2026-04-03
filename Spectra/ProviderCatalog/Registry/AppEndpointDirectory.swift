import Foundation

enum AppEndpointRole: String, Hashable, CaseIterable {
    case read
    case balance
    case history
    case utxo
    case fee
    case broadcast
    case verification
    case rpc
    case explorer
    case backend
}

struct AppEndpointRecord: Hashable {
    let id: String
    let chainName: String
    let groupTitle: String
    let providerID: String
    let endpoint: String
    let roles: Set<AppEndpointRole>
    let probeURL: String?
    let settingsVisible: Bool
    let explorerLabel: String?

    init(
        id: String,
        chainName: String,
        groupTitle: String? = nil,
        providerID: String,
        endpoint: String,
        roles: Set<AppEndpointRole>,
        probeURL: String? = nil,
        settingsVisible: Bool = true,
        explorerLabel: String? = nil
    ) {
        self.id = id
        self.chainName = chainName
        self.groupTitle = groupTitle ?? chainName
        self.providerID = providerID
        self.endpoint = endpoint
        self.roles = roles
        self.probeURL = probeURL
        self.settingsVisible = settingsVisible
        self.explorerLabel = explorerLabel
    }
}

enum AppEndpointDirectory {
    static let records: [AppEndpointRecord] = [
        AppEndpointRecord(id: "bitcoin.blockchain_info.multiaddr", chainName: "Bitcoin", providerID: "blockchain-info", endpoint: "https://blockchain.info/multiaddr", roles: [.read, .balance, .history], settingsVisible: false),
        AppEndpointRecord(id: "bitcoin.blockchair.xpub", chainName: "Bitcoin", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin/dashboards/xpub/", roles: [.read, .balance, .history], settingsVisible: false),
        AppEndpointRecord(id: "bitcoin.mainnet.blockstream", chainName: "Bitcoin", providerID: "esplora", endpoint: "https://blockstream.info/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://blockstream.info/api"),
        AppEndpointRecord(id: "bitcoin.mainnet.mempool", chainName: "Bitcoin", providerID: "esplora", endpoint: "https://mempool.space/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://mempool.space/api"),
        AppEndpointRecord(id: "bitcoin.mainnet.mempool_emzy", chainName: "Bitcoin", providerID: "esplora", endpoint: "https://mempool.emzy.de/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://mempool.emzy.de/api"),
        AppEndpointRecord(id: "bitcoin.mainnet.maestro", chainName: "Bitcoin", providerID: "maestro-esplora", endpoint: "https://xbt-mainnet.gomaestro-api.org/v0/esplora", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://xbt-mainnet.gomaestro-api.org/v0/esplora"),
        AppEndpointRecord(id: "bitcoin.explorer.tx", chainName: "Bitcoin", providerID: "mempool", endpoint: "https://mempool.space/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Mempool"),
        AppEndpointRecord(id: "bitcoin.testnet.blockstream", chainName: "Bitcoin", groupTitle: "Bitcoin Testnet", providerID: "esplora", endpoint: "https://blockstream.info/testnet/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://blockstream.info/testnet/api"),
        AppEndpointRecord(id: "bitcoin.testnet.mempool", chainName: "Bitcoin", groupTitle: "Bitcoin Testnet", providerID: "esplora", endpoint: "https://mempool.space/testnet/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://mempool.space/testnet/api"),
        AppEndpointRecord(id: "bitcoin.testnet4.mempool", chainName: "Bitcoin", groupTitle: "Bitcoin Testnet4", providerID: "esplora", endpoint: "https://mempool.space/testnet4/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://mempool.space/testnet4/api"),
        AppEndpointRecord(id: "bitcoin.signet.blockstream", chainName: "Bitcoin", groupTitle: "Bitcoin Signet", providerID: "esplora", endpoint: "https://blockstream.info/signet/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://blockstream.info/signet/api"),
        AppEndpointRecord(id: "bitcoin.signet.mempool", chainName: "Bitcoin", groupTitle: "Bitcoin Signet", providerID: "esplora", endpoint: "https://mempool.space/signet/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://mempool.space/signet/api"),

        AppEndpointRecord(id: "bitcoincash.blockchair.api", chainName: "Bitcoin Cash", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-cash", roles: [.read, .balance, .history, .utxo, .fee, .verification], probeURL: "https://api.blockchair.com/bitcoin-cash/stats"),
        AppEndpointRecord(id: "bitcoincash.blockchair.push", chainName: "Bitcoin Cash", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-cash/push/transaction", roles: [.broadcast], probeURL: "https://api.blockchair.com/bitcoin-cash/stats", settingsVisible: false),
        AppEndpointRecord(id: "bitcoincash.blockchair.txprefix", chainName: "Bitcoin Cash", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-cash/dashboards/transaction/", roles: [.verification], probeURL: "https://api.blockchair.com/bitcoin-cash/stats", settingsVisible: false),
        AppEndpointRecord(id: "bitcoincash.actorforth.api", chainName: "Bitcoin Cash", providerID: "actorforth", endpoint: "https://rest.bch.actorforth.org/v2", roles: [.read, .balance, .history, .utxo, .verification], probeURL: "https://rest.bch.actorforth.org/v2/blockchain/getBlockchainInfo"),
        AppEndpointRecord(id: "bitcoincash.actorforth.broadcast", chainName: "Bitcoin Cash", providerID: "actorforth", endpoint: "https://rest.bch.actorforth.org/v2/rawtransactions/sendRawTransaction/", roles: [.broadcast], probeURL: "https://rest.bch.actorforth.org/v2/blockchain/getBlockchainInfo", settingsVisible: false),
        AppEndpointRecord(id: "bitcoincash.actorforth.txprefix", chainName: "Bitcoin Cash", providerID: "actorforth", endpoint: "https://rest.bch.actorforth.org/v2/transaction/details/", roles: [.verification], probeURL: "https://rest.bch.actorforth.org/v2/blockchain/getBlockchainInfo", settingsVisible: false),
        AppEndpointRecord(id: "bitcoincash.explorer.tx", chainName: "Bitcoin Cash", providerID: "blockchair", endpoint: "https://blockchair.com/bitcoin-cash/transaction/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Blockchair"),

        AppEndpointRecord(id: "bitcoinsv.whatsonchain.api", chainName: "Bitcoin SV", providerID: "whatsonchain", endpoint: "https://api.whatsonchain.com/v1/bsv/main", roles: [.read, .balance, .history, .utxo, .verification], probeURL: "https://api.whatsonchain.com/v1/bsv/main/chain/info"),
        AppEndpointRecord(id: "bitcoinsv.whatsonchain.chaininfo", chainName: "Bitcoin SV", providerID: "whatsonchain", endpoint: "https://api.whatsonchain.com/v1/bsv/main/chain/info", roles: [.verification], probeURL: "https://api.whatsonchain.com/v1/bsv/main/chain/info", settingsVisible: false),
        AppEndpointRecord(id: "bitcoinsv.whatsonchain.broadcast", chainName: "Bitcoin SV", providerID: "whatsonchain", endpoint: "https://api.whatsonchain.com/v1/bsv/main/tx/raw", roles: [.broadcast], probeURL: "https://api.whatsonchain.com/v1/bsv/main/chain/info", settingsVisible: false),
        AppEndpointRecord(id: "bitcoinsv.whatsonchain.txprefix", chainName: "Bitcoin SV", providerID: "whatsonchain", endpoint: "https://api.whatsonchain.com/v1/bsv/main/tx/hash/", roles: [.verification], probeURL: "https://api.whatsonchain.com/v1/bsv/main/chain/info", settingsVisible: false),
        AppEndpointRecord(id: "bitcoinsv.blockchair.api", chainName: "Bitcoin SV", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-sv", roles: [.read, .balance, .history, .utxo, .fee, .verification], probeURL: "https://api.blockchair.com/bitcoin-sv/stats"),
        AppEndpointRecord(id: "bitcoinsv.blockchair.push", chainName: "Bitcoin SV", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-sv/push/transaction", roles: [.broadcast], probeURL: "https://api.blockchair.com/bitcoin-sv/stats", settingsVisible: false),
        AppEndpointRecord(id: "bitcoinsv.blockchair.txprefix", chainName: "Bitcoin SV", providerID: "blockchair", endpoint: "https://api.blockchair.com/bitcoin-sv/dashboards/transaction/", roles: [.verification], probeURL: "https://api.blockchair.com/bitcoin-sv/stats", settingsVisible: false),
        AppEndpointRecord(id: "bitcoinsv.explorer.tx", chainName: "Bitcoin SV", providerID: "whatsonchain", endpoint: "https://whatsonchain.com/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In WhatsOnChain"),

        AppEndpointRecord(id: "litecoin.litecoinspace.api", chainName: "Litecoin", providerID: "litecoinspace", endpoint: "https://litecoinspace.org/api", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://litecoinspace.org/api"),
        AppEndpointRecord(id: "litecoin.blockcypher.api", chainName: "Litecoin", providerID: "blockcypher", endpoint: "https://api.blockcypher.com/v1/ltc/main", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://api.blockcypher.com/v1/ltc/main"),
        AppEndpointRecord(id: "litecoin.sochain.api", chainName: "Litecoin", providerID: "sochain", endpoint: "https://sochain.com/api/v2", roles: [.read, .balance, .history, .utxo, .verification], probeURL: "https://sochain.com/api/v2"),
        AppEndpointRecord(id: "litecoin.explorer.tx", chainName: "Litecoin", providerID: "litecoinspace", endpoint: "https://litecoinspace.org/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In LitecoinSpace"),

        AppEndpointRecord(id: "dogecoin.mainnet.blockcypher", chainName: "Dogecoin", providerID: "blockcypher", endpoint: "https://api.blockcypher.com/v1/doge/main", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://api.blockcypher.com/v1/doge/main"),
        AppEndpointRecord(id: "dogecoin.testnet.blockcypher", chainName: "Dogecoin", groupTitle: "Dogecoin Testnet", providerID: "blockcypher", endpoint: "https://api.blockcypher.com/v1/doge/test3", roles: [.read, .balance, .history, .utxo, .fee, .broadcast, .verification], probeURL: "https://api.blockcypher.com/v1/doge/test3"),
        AppEndpointRecord(id: "dogecoin.explorer.tx", chainName: "Dogecoin", providerID: "dogechain", endpoint: "https://dogechain.info/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Dogechain"),

        AppEndpointRecord(id: "tron.tronscan.account", chainName: "Tron", providerID: "tronscan", endpoint: "https://apilist.tronscanapi.com/api/accountv2", roles: [.read, .balance, .history], probeURL: "https://apilist.tronscanapi.com/api/system/status"),
        AppEndpointRecord(id: "tron.trongrid.accounts.io", chainName: "Tron", providerID: "trongrid-accounts", endpoint: "https://api.trongrid.io/v1/accounts", roles: [.read, .balance, .history], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.trongrid.accounts.pro", chainName: "Tron", providerID: "trongrid-accounts", endpoint: "https://api.trongrid.pro/v1/accounts", roles: [.read, .balance, .history], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.trongrid.accounts.network", chainName: "Tron", providerID: "trongrid-accounts", endpoint: "https://api.trongrid.network/v1/accounts", roles: [.read, .balance, .history], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.trongrid.rpc.io", chainName: "Tron", providerID: "trongrid-rpc", endpoint: "https://api.trongrid.io", roles: [.rpc, .broadcast, .fee, .verification], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.trongrid.rpc.pro", chainName: "Tron", providerID: "trongrid-rpc", endpoint: "https://api.trongrid.pro", roles: [.rpc, .broadcast, .fee, .verification], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.trongrid.rpc.network", chainName: "Tron", providerID: "trongrid-rpc", endpoint: "https://api.trongrid.network", roles: [.rpc, .broadcast, .fee, .verification], probeURL: "https://api.trongrid.io/wallet/getnowblock"),
        AppEndpointRecord(id: "tron.explorer.tx", chainName: "Tron", providerID: "tronscan", endpoint: "https://tronscan.org/#/transaction/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In TronScan"),

        AppEndpointRecord(id: "solana.rpc.mainnet", chainName: "Solana", providerID: "solana-mainnet-beta", endpoint: "https://api.mainnet-beta.solana.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://api.mainnet-beta.solana.com"),
        AppEndpointRecord(id: "solana.rpc.ankr", chainName: "Solana", providerID: "solana-ankr", endpoint: "https://rpc.ankr.com/solana", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://rpc.ankr.com/solana"),
        AppEndpointRecord(id: "solana.rpc.publicnode", chainName: "Solana", providerID: "solana-publicnode", endpoint: "https://solana-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .fee], probeURL: "https://solana-rpc.publicnode.com"),

        AppEndpointRecord(id: "xrp.history.xrpscan_api", chainName: "XRP Ledger", providerID: "xrpscan", endpoint: "https://api.xrpscan.com/api/v1/account", roles: [.read, .balance, .history]),
        AppEndpointRecord(id: "xrp.history.xrpscan", chainName: "XRP Ledger", providerID: "xrpscan", endpoint: "https://xrpscan.com/api/v1/account", roles: [.read, .history]),
        AppEndpointRecord(id: "xrp.rpc.s1", chainName: "XRP Ledger", providerID: "ripple-s1", endpoint: "https://s1.ripple.com:51234/", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://s1.ripple.com:51234/"),
        AppEndpointRecord(id: "xrp.rpc.s2", chainName: "XRP Ledger", providerID: "ripple-s2", endpoint: "https://s2.ripple.com:51234/", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://s2.ripple.com:51234/"),
        AppEndpointRecord(id: "xrp.rpc.cluster", chainName: "XRP Ledger", providerID: "xrpl-cluster", endpoint: "https://xrplcluster.com/", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://xrplcluster.com/"),
        AppEndpointRecord(id: "xrp.explorer.tx", chainName: "XRP Ledger", providerID: "xrpscan", endpoint: "https://livenet.xrpl.org/transactions/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In XRP Explorer"),

        AppEndpointRecord(id: "cardano.koios.primary", chainName: "Cardano", providerID: "koios", endpoint: "https://api.koios.rest/api/v1", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://api.koios.rest/api/v1/tip"),
        AppEndpointRecord(id: "cardano.koios.xray", chainName: "Cardano", providerID: "koios", endpoint: "https://graph.xray.app/output/services/koios/mainnet/api/v1", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://graph.xray.app/output/services/koios/mainnet/api/v1/tip"),
        AppEndpointRecord(id: "cardano.koios.happystaking", chainName: "Cardano", providerID: "koios", endpoint: "https://koios.happystaking.io:8453/api/v1", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://koios.happystaking.io:8453/api/v1/tip"),
        AppEndpointRecord(id: "cardano.explorer.tx", chainName: "Cardano", providerID: "cexplorer", endpoint: "https://cexplorer.io/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Cardano Explorer"),

        AppEndpointRecord(id: "aptos.rpc.aptoslabs", chainName: "Aptos", providerID: "aptos-mainnet-rpc", endpoint: "https://api.mainnet.aptoslabs.com/v1", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://api.mainnet.aptoslabs.com/v1/spec"),
        AppEndpointRecord(id: "aptos.rpc.blastapi", chainName: "Aptos", providerID: "blastapi", endpoint: "https://aptos-mainnet.public.blastapi.io/v1", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://aptos-mainnet.public.blastapi.io/v1/spec"),
        AppEndpointRecord(id: "aptos.rpc.mainnet", chainName: "Aptos", providerID: "aptoslabs-mainnet", endpoint: "https://mainnet.aptoslabs.com/v1", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://mainnet.aptoslabs.com/v1/spec"),
        AppEndpointRecord(id: "aptos.explorer.tx", chainName: "Aptos", providerID: "aptoslabs-explorer", endpoint: "https://explorer.aptoslabs.com/txn/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Aptos Explorer"),

        AppEndpointRecord(id: "ton.api.v2", chainName: "TON", providerID: "toncenter-v2", endpoint: "https://toncenter.com/api/v2", roles: [.read, .balance, .history, .broadcast, .fee, .verification], probeURL: "https://toncenter.com/api/v2/getMasterchainInfo"),
        AppEndpointRecord(id: "ton.api.v3", chainName: "TON", providerID: "toncenter-v3", endpoint: "https://toncenter.com/api/v3", roles: [.read, .balance, .history], probeURL: "https://toncenter.com/api/v3/jetton/wallets"),
        AppEndpointRecord(id: "ton.explorer.tx", chainName: "TON", providerID: "tonviewer", endpoint: "https://tonviewer.com/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Tonviewer"),

        AppEndpointRecord(id: "sui.rpc.mainnet", chainName: "Sui", providerID: "sui-mainnet", endpoint: "https://fullnode.mainnet.sui.io:443", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://fullnode.mainnet.sui.io:443"),
        AppEndpointRecord(id: "sui.rpc.publicnode", chainName: "Sui", providerID: "sui-publicnode", endpoint: "https://sui-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://sui-rpc.publicnode.com"),
        AppEndpointRecord(id: "sui.rpc.blockvision", chainName: "Sui", providerID: "sui-blockvision", endpoint: "https://sui-mainnet-endpoint.blockvision.org", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://sui-mainnet-endpoint.blockvision.org"),
        AppEndpointRecord(id: "sui.rpc.blockpi", chainName: "Sui", providerID: "sui-blockpi", endpoint: "https://sui.blockpi.network/v1/rpc/public", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://sui.blockpi.network/v1/rpc/public"),
        AppEndpointRecord(id: "sui.rpc.suiscan", chainName: "Sui", providerID: "sui-suiscan", endpoint: "https://rpc-mainnet.suiscan.xyz", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://rpc-mainnet.suiscan.xyz"),

        AppEndpointRecord(id: "near.rpc.mainnet", chainName: "NEAR", providerID: "near-mainnet-rpc", endpoint: "https://rpc.mainnet.near.org", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://rpc.mainnet.near.org"),
        AppEndpointRecord(id: "near.rpc.fastnear", chainName: "NEAR", providerID: "fastnear-rpc", endpoint: "https://free.rpc.fastnear.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://free.rpc.fastnear.com"),
        AppEndpointRecord(id: "near.rpc.lava", chainName: "NEAR", providerID: "lava-near-rpc", endpoint: "https://near.lava.build", roles: [.rpc, .read, .balance, .history, .broadcast, .fee], probeURL: "https://near.lava.build"),
        AppEndpointRecord(id: "near.history.nearblocks", chainName: "NEAR", providerID: "nearblocks", endpoint: "https://api.nearblocks.io/v1", roles: [.read, .history], probeURL: "https://api.nearblocks.io/v1/stats"),
        AppEndpointRecord(id: "near.explorer.tx", chainName: "NEAR", providerID: "nearblocks", endpoint: "https://nearblocks.io/txns/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In NearBlocks"),

        AppEndpointRecord(id: "polkadot.sidecar.parity", chainName: "Polkadot", providerID: "sidecar", endpoint: "https://polkadot-public-sidecar.parity-chains.parity.io", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://polkadot-public-sidecar.parity-chains.parity.io/transaction/material"),
        AppEndpointRecord(id: "polkadot.rpc.onfinality", chainName: "Polkadot", providerID: "rpc", endpoint: "https://polkadot.api.onfinality.io/public", roles: [.rpc, .read, .balance, .broadcast, .fee], probeURL: "https://polkadot.api.onfinality.io/public"),
        AppEndpointRecord(id: "polkadot.rpc.dotters", chainName: "Polkadot", providerID: "rpc", endpoint: "https://polkadot.dotters.network", roles: [.rpc, .read, .balance, .broadcast, .fee], probeURL: "https://polkadot.dotters.network"),
        AppEndpointRecord(id: "polkadot.rpc.ibp", chainName: "Polkadot", providerID: "rpc", endpoint: "https://rpc.ibp.network/polkadot", roles: [.rpc, .read, .balance, .broadcast, .fee], probeURL: "https://rpc.ibp.network/polkadot"),
        AppEndpointRecord(id: "polkadot.explorer.tx", chainName: "Polkadot", providerID: "subscan", endpoint: "https://polkadot.subscan.io/extrinsic/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Subscan"),

        AppEndpointRecord(id: "stellar.horizon.primary", chainName: "Stellar", providerID: "horizon", endpoint: "https://horizon.stellar.org", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://horizon.stellar.org/fee_stats"),
        AppEndpointRecord(id: "stellar.horizon.lobstr", chainName: "Stellar", providerID: "horizon", endpoint: "https://horizon.stellar.lobstr.co", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://horizon.stellar.lobstr.co/fee_stats"),
        AppEndpointRecord(id: "stellar.explorer.tx", chainName: "Stellar", providerID: "stellar-expert", endpoint: "https://stellar.expert/explorer/public/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Stellar Expert"),

        AppEndpointRecord(id: "monero.backend.1", chainName: "Monero", providerID: "trusted-backend", endpoint: "https://monerolws1.edge.app", roles: [.backend, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "monero.backend.2", chainName: "Monero", providerID: "trusted-backend", endpoint: "https://monerolws2.edge.app", roles: [.backend, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "monero.backend.3", chainName: "Monero", providerID: "trusted-backend", endpoint: "https://monerolws3.edge.app", roles: [.backend, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "monero.explorer.tx", chainName: "Monero", providerID: "xmrchain", endpoint: "https://xmrchain.net/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Monero Explorer"),

        AppEndpointRecord(id: "icp.rosetta", chainName: "Internet Computer", providerID: "rosetta", endpoint: "https://rosetta-api.internetcomputer.org", roles: [.read, .balance, .history, .broadcast, .fee], probeURL: "https://rosetta-api.internetcomputer.org/network/list"),
        AppEndpointRecord(id: "icp.explorer.tx", chainName: "Internet Computer", providerID: "dashboard", endpoint: "https://dashboard.internetcomputer.org/transaction/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In ICP Dashboard"),

        AppEndpointRecord(id: "ethereum.rpc.publicnode", chainName: "Ethereum", providerID: "rpc", endpoint: "https://ethereum-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.rpc.llamarpc", chainName: "Ethereum", providerID: "rpc", endpoint: "https://eth.llamarpc.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.rpc.cloudflare", chainName: "Ethereum", providerID: "rpc", endpoint: "https://cloudflare-eth.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.rpc.ankr", chainName: "Ethereum", providerID: "rpc", endpoint: "https://rpc.ankr.com/eth", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.rpc.1rpc", chainName: "Ethereum", providerID: "rpc", endpoint: "https://1rpc.io/eth", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.explorer.etherscan", chainName: "Ethereum", providerID: "etherscan", endpoint: "https://api.etherscan.io/api", roles: [.explorer, .read, .history], probeURL: "https://api.etherscan.io/api?module=stats&action=ethprice"),
        AppEndpointRecord(id: "ethereum.explorer.ethplorer", chainName: "Ethereum", providerID: "ethplorer", endpoint: "https://api.ethplorer.io", roles: [.explorer, .read, .history], probeURL: "https://api.ethplorer.io/getAddressInfo/0x0000000000000000000000000000000000000000?apiKey=freekey"),
        AppEndpointRecord(id: "ethereum.explorer.blockscout", chainName: "Ethereum", providerID: "blockscout", endpoint: "https://eth.blockscout.com", roles: [.explorer, .read, .history], settingsVisible: false),
        AppEndpointRecord(id: "ethereum.explorer.tx", chainName: "Ethereum", providerID: "etherscan-web", endpoint: "https://etherscan.io/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Etherscan"),

        AppEndpointRecord(id: "ethereum.sepolia.rpc.publicnode", chainName: "Ethereum", groupTitle: "Ethereum Sepolia", providerID: "rpc", endpoint: "https://ethereum-sepolia-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereum.hoodi.rpc.publicnode", chainName: "Ethereum", groupTitle: "Ethereum Hoodi", providerID: "rpc", endpoint: "https://ethereum-hoodi-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereumclassic.rpc.rivet", chainName: "Ethereum Classic", providerID: "rpc", endpoint: "https://etc.rivet.link", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereumclassic.rpc.geth", chainName: "Ethereum Classic", providerID: "rpc", endpoint: "https://geth-at.etc-network.info", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereumclassic.rpc.besu", chainName: "Ethereum Classic", providerID: "rpc", endpoint: "https://besu-at.etc-network.info", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "ethereumclassic.explorer.blockscout", chainName: "Ethereum Classic", providerID: "blockscout", endpoint: "https://blockscout.com/etc/mainnet", roles: [.explorer, .read, .history], settingsVisible: false),
        AppEndpointRecord(id: "ethereumclassic.explorer.tx", chainName: "Ethereum Classic", providerID: "blockscout-web", endpoint: "https://blockscout.com/etc/mainnet/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Blockscout"),
        AppEndpointRecord(id: "arbitrum.rpc.publicnode", chainName: "Arbitrum", providerID: "rpc", endpoint: "https://arbitrum-one-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "arbitrum.rpc.arb1", chainName: "Arbitrum", providerID: "rpc", endpoint: "https://arb1.arbitrum.io/rpc", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "arbitrum.rpc.1rpc", chainName: "Arbitrum", providerID: "rpc", endpoint: "https://1rpc.io/arb", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "arbitrum.explorer.tx", chainName: "Arbitrum", providerID: "arbiscan", endpoint: "https://arbiscan.io/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Arbiscan"),
        AppEndpointRecord(id: "optimism.rpc.mainnet", chainName: "Optimism", providerID: "rpc", endpoint: "https://mainnet.optimism.io", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "optimism.rpc.publicnode", chainName: "Optimism", providerID: "rpc", endpoint: "https://optimism-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "optimism.rpc.1rpc", chainName: "Optimism", providerID: "rpc", endpoint: "https://1rpc.io/op", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "optimism.explorer.tx", chainName: "Optimism", providerID: "optimistic-etherscan", endpoint: "https://optimistic.etherscan.io/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Optimism Etherscan"),
        AppEndpointRecord(id: "bnb.rpc.primary", chainName: "BNB Chain", providerID: "rpc", endpoint: "https://bsc-dataseed.bnbchain.org", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "bnb.rpc.binance", chainName: "BNB Chain", providerID: "rpc", endpoint: "https://bsc-dataseed1.binance.org", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "bnb.rpc.defibit", chainName: "BNB Chain", providerID: "rpc", endpoint: "https://bsc-dataseed1.defibit.io", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "bnb.rpc.ninicoin", chainName: "BNB Chain", providerID: "rpc", endpoint: "https://bsc-dataseed1.ninicoin.io", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "bnb.explorer.bscscan", chainName: "BNB Chain", providerID: "bscscan", endpoint: "https://api.bscscan.com/api", roles: [.explorer, .read, .history], probeURL: "https://api.bscscan.com/api?module=stats&action=bnbprice"),
        AppEndpointRecord(id: "bnb.explorer.tx", chainName: "BNB Chain", providerID: "bscscan-web", endpoint: "https://bscscan.com/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In BscScan"),
        AppEndpointRecord(id: "avalanche.rpc.primary", chainName: "Avalanche", providerID: "rpc", endpoint: "https://api.avax.network/ext/bc/C/rpc", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "avalanche.rpc.publicnode", chainName: "Avalanche", providerID: "rpc", endpoint: "https://avalanche-c-chain-rpc.publicnode.com", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "avalanche.rpc.1rpc", chainName: "Avalanche", providerID: "rpc", endpoint: "https://1rpc.io/avax/c", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "avalanche.explorer.tx", chainName: "Avalanche", providerID: "snowtrace-web", endpoint: "https://snowtrace.io/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Snowtrace"),
        AppEndpointRecord(id: "hyperliquid.rpc.primary", chainName: "Hyperliquid", providerID: "rpc", endpoint: "https://rpc.hyperliquid.xyz/evm", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "hyperliquid.rpc.onfinality", chainName: "Hyperliquid", providerID: "rpc", endpoint: "https://hyperliquid.api.onfinality.io/evm/public", roles: [.rpc, .read, .balance, .history, .broadcast, .fee]),
        AppEndpointRecord(id: "hyperliquid.explorer.api", chainName: "Hyperliquid", providerID: "hyperevmscan", endpoint: "https://api.hyperevmscan.io/api", roles: [.explorer, .read, .history]),
        AppEndpointRecord(id: "hyperliquid.explorer.web", chainName: "Hyperliquid", providerID: "hyperevmscan", endpoint: "https://hyperevmscan.io", roles: [.explorer, .read, .history], settingsVisible: false),
        AppEndpointRecord(id: "hyperliquid.explorer.tx", chainName: "Hyperliquid", providerID: "hyperliquid-web", endpoint: "https://app.hyperliquid.xyz/explorer/tx/", roles: [.explorer], settingsVisible: false, explorerLabel: "Open In Hyperliquid Explorer"),
    ]

    static func endpoint(_ id: String) -> String {
        guard let endpoint = records.first(where: { $0.id == id })?.endpoint else {
            preconditionFailure("Missing endpoint record for id: \(id)")
        }
        return endpoint
    }

    static func endpoints(for ids: [String]) -> [String] {
        ids.map { endpoint($0) }
    }

    static func endpointRecords(
        for chainName: String,
        roles: Set<AppEndpointRole>? = nil,
        settingsVisibleOnly: Bool = false
    ) -> [AppEndpointRecord] {
        records.filter { record in
            guard record.chainName == chainName else { return false }
            if settingsVisibleOnly, !record.settingsVisible {
                return false
            }
            guard let roles else { return true }
            return !record.roles.isDisjoint(with: roles)
        }
    }

    static func groupedSettingsEntries(for chainName: String) -> [(title: String, endpoints: [String])] {
        let visibleRecords = endpointRecords(for: chainName, settingsVisibleOnly: true)
        let titles = visibleRecords.reduce(into: [String]()) { partialResult, record in
            if !partialResult.contains(record.groupTitle) {
                partialResult.append(record.groupTitle)
            }
        }
        let grouped = Dictionary(grouping: visibleRecords, by: \.groupTitle)
        return titles.compactMap { title in
            guard let records = grouped[title] else { return nil }
            var endpoints: [String] = []
            for record in records {
                if !endpoints.contains(record.endpoint) {
                    endpoints.append(record.endpoint)
                }
            }
            return endpoints.isEmpty ? nil : (title, endpoints)
        }
    }

    static func settingsEndpoints(for chainName: String) -> [String] {
        groupedSettingsEntries(for: chainName).flatMap(\.endpoints)
    }

    static func diagnosticsChecks(for chainName: String) -> [(endpoint: String, probeURL: String)] {
        endpointRecords(for: chainName).compactMap { record in
            guard let probeURL = record.probeURL else { return nil }
            return (endpoint: record.endpoint, probeURL: probeURL)
        }
    }

    static func evmRPCEndpoints(for chainName: String) -> [String] {
        endpointRecords(for: chainName, roles: [.rpc], settingsVisibleOnly: true).map(\.endpoint)
    }

    static func explorerSupplementalEndpoints(for chainName: String) -> [String] {
        endpointRecords(for: chainName, roles: [.explorer], settingsVisibleOnly: true).map(\.endpoint)
    }

    static func transactionExplorerBaseURL(for chainName: String) -> String? {
        endpointRecords(for: chainName, roles: [.explorer])
            .first(where: { $0.explorerLabel != nil })?
            .endpoint
    }

    static func transactionExplorerLabel(for chainName: String) -> String? {
        endpointRecords(for: chainName, roles: [.explorer])
            .first(where: { $0.explorerLabel != nil })?
            .explorerLabel
    }

    static func bitcoinEsploraBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        switch networkMode {
        case .mainnet:
            return endpoints(for: [
                "bitcoin.mainnet.blockstream",
                "bitcoin.mainnet.mempool",
                "bitcoin.mainnet.mempool_emzy",
                "bitcoin.mainnet.maestro"
            ])
        case .testnet:
            return endpoints(for: [
                "bitcoin.testnet.blockstream",
                "bitcoin.testnet.mempool"
            ])
        case .testnet4:
            return endpoints(for: [
                "bitcoin.testnet4.mempool"
            ])
        case .signet:
            return endpoints(for: [
                "bitcoin.signet.blockstream",
                "bitcoin.signet.mempool"
            ])
        }
    }

    static func bitcoinWalletStoreDefaultBaseURLs(for networkMode: BitcoinNetworkMode) -> [String] {
        switch networkMode {
        case .mainnet:
            return endpoints(for: [
                "bitcoin.mainnet.blockstream",
                "bitcoin.mainnet.mempool",
                "bitcoin.mainnet.maestro"
            ])
        case .testnet:
            return endpoints(for: [
                "bitcoin.testnet.blockstream",
                "bitcoin.testnet.mempool"
            ])
        case .testnet4:
            return endpoints(for: [
                "bitcoin.testnet4.mempool"
            ])
        case .signet:
            return endpoints(for: [
                "bitcoin.signet.mempool"
            ])
        }
    }
}
