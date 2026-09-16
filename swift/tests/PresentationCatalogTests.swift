import SwiftUI
import XCTest
@testable import Spectra

final class PresentationCatalogTests: XCTestCase {
    func testCoinColorsUseCatalogAndNormalizeSymbols() {
        XCTAssertEqual(Coin.displayColor(for: "  usdt \n"), .green)
        XCTAssertEqual(Coin.displayColor(for: "AAVE"), .indigo)
        XCTAssertEqual(Coin.displayColor(for: "not-a-catalog-asset"), .gray)
        for token in listTokens(chainId: "") where !token.coingeckoId.isEmpty {
            XCTAssertEqual(Coin.displayColor(for: token.symbol), RegistryColorLookup.color(named: token.color))
        }
    }

    /// Every localized content file decodes in every locale the manifest
    /// declares — read from the manifest rather than listed here, so adding a
    /// locale cannot leave a file silently untested.
    func testBundledCopyDecodesInEveryDeclaredLocale() throws {
        let locales = try declaredLocales()
        XCTAssertTrue(locales.contains("en"), "the source language must ship")
        for locale in locales {
            try decode("CommonContent", locale: locale, as: CommonLocalizationContent.self)
            try decode("DiagnosticsContent", locale: locale, as: DiagnosticsContentCopy.self)
            try decode("DonationsContent", locale: locale, as: DonationsContentCopy.self)
            try decode("EndpointsContent", locale: locale, as: EndpointsContentCopy.self)
            try decode("ImportFlowContent", locale: locale, as: ImportFlowContent.self)
            try decode("SettingsContent", locale: locale, as: SettingsContentCopy.self)
        }
    }

    /// A localized file ships per locale and nothing else; a locale-independent
    /// one ships unsuffixed and nothing else.
    ///
    /// `StaticContentCatalog` tries `<name>.<locale>.json` first and falls back
    /// to `<name>.json`, which is how `AppLinks` and `BuyProviders` — URLs and
    /// provider lists, the same in every language — are found. The fallback
    /// also meant six localized files could ship an unsuffixed byte-identical
    /// copy of their `.en` twin without anything reading it: `en` always
    /// resolves first, because `preferredLocalizationIdentifiers` appends the
    /// manifest's `sourceLanguage` before it ever reaches `Base`. Two copies of
    /// one string, one of them unreachable, is the drift `resources/` is flat
    /// to avoid — so the absence is asserted rather than left to be noticed.
    func testLocalizedCopyShipsPerLocaleAndNothingElse() throws {
        for name in ["CommonContent", "DiagnosticsContent", "DonationsContent",
                     "EndpointsContent", "ImportFlowContent", "SettingsContent"] {
            XCTAssertNil(
                Bundle.main.url(forResource: name, withExtension: "json"),
                "\(name).json shadows \(name).en.json and is never read"
            )
        }
        for name in ["AppLinks", "BuyProviders"] {
            XCTAssertNotNil(Bundle.main.url(forResource: name, withExtension: "json"), name)
        }
    }

    private struct Manifest: Decodable {
        let availableLocales: [String]
    }

    private func declaredLocales() throws -> [String] {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "RuntimeStrings.manifest", withExtension: "json"),
            "RuntimeStrings.manifest.json"
        )
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).availableLocales
    }

    private func decode<T: Decodable>(_ name: String, locale: String, as type: T.Type) throws {
        let filename = "\(name).\(locale)"
        let url = try XCTUnwrap(Bundle.main.url(forResource: filename, withExtension: "json"), filename)
        _ = try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
