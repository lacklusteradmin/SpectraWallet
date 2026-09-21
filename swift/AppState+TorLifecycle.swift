import Foundation

private func fetchTorStatusFromRust() -> TorStatus { torStatus() }

extension AppState {
    /// Settings effects run in core; the shell only observes status.
    func observeTorStatus() {
        torStatusPollingTask?.cancel()
        torStatusPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.torStatus = fetchTorStatusFromRust()
                guard self != nil else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func reconnectTor() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do { self.torStatus = try await self.bridge.reconnectTor() }
            catch { self.torStatus = .error(message: error.localizedDescription) }
        }
    }

    static func torCacheDirectory() -> String {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.path ?? NSTemporaryDirectory()
    }
}
