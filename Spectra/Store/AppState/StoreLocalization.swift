import Foundation

func localizedStoreString(_ key: String) -> String {
    AppLocalization.string(key)
}

func localizedStoreFormat(_ key: String, _ arguments: CVarArg...) -> String {
    let format = AppLocalization.string(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
