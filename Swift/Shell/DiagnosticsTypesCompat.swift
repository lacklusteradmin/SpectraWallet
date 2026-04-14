import Foundation

// UniFFI converts acronym-prefixed Rust struct names into Swift using
// UpperCamelCase (e.g. `XRPHistoryDiagnostics` -> `XrpHistoryDiagnostics`).
// Preserve the historical Swift names via typealiases so existing call
// sites keep compiling.
typealias XRPHistoryDiagnostics = XrpHistoryDiagnostics
typealias TONHistoryDiagnostics = TonHistoryDiagnostics
typealias ICPHistoryDiagnostics = IcpHistoryDiagnostics
