import Foundation

extension AppState {
    /// Settings effects run in core, and core's refresh engine reports every
    /// status change through the observer; this only asks for a reconnect.
    func reconnectTor() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { self.torStatus = try await self.bridge.ready().reconnectTor() }
            catch { self.torStatus = .error(message: error.localizedDescription) }
        }
    }

    static func torCacheDirectory() -> String {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
    }
}
