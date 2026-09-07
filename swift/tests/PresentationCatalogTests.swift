import SwiftUI
import XCTest
@testable import Spectra

final class PresentationCatalogTests: XCTestCase {
    func testCoinColorsUseCatalogAndNormalizeSymbols() {
        XCTAssertEqual(Coin.displayColor(for: "  usdt \n"), .green)
        XCTAssertEqual(Coin.displayColor(for: "AAVE"), .indigo)
        XCTAssertEqual(Coin.displayColor(for: "not-a-catalog-asset"), .gray)
        for descriptor in Coin.nativeChainIconDescriptors {
            XCTAssertEqual(Coin.displayColor(for: descriptor.symbol), descriptor.color)
        }
    }

    func testBundledCopyDecodesInEveryLocale() throws {
        for locale in ["base", "en", "zh-Hans", "zh-Hant"] {
            try decode("CommonContent", locale: locale, as: CommonLocalizationContent.self)
            try decode("DiagnosticsContent", locale: locale, as: DiagnosticsContentCopy.self)
            try decode("DonationsContent", locale: locale, as: DonationsContentCopy.self)
            try decode("ImportFlowContent", locale: locale, as: ImportFlowContent.self)
        }
    }

    private func decode<T: Decodable>(_ name: String, locale: String, as type: T.Type) throws {
        let filename = locale == "base" ? name : "\(name).\(locale)"
        let url = try XCTUnwrap(Bundle.main.url(forResource: filename, withExtension: "json"), filename)
        _ = try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}
