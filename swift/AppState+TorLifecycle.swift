import Foundation

// File-scope forwarder so the `torStatus()` UniFFI free function can be called
// from inside the AppState extension without colliding with the `torStatus`
// observable property.
private func fetchTorStatusFromRust() -> TorStatus { torStatus() }

extension AppState {

    // MARK: - Entry points

    /// Start or stop the client to match core's Tor settings. Called when
    /// either Tor switch changes, whether the change was made here or arrived
    /// with core's state at launch.
    func handleTorEnabledChange() {
        if committedAppSettings.torEnabled {
            startTorEngine()
        } else {
            stopTorEngine()
        }
    }

    /// Restart Tor after a failure or a manual reconnect request.
    func reconnectTor() {
        stopTorEngine()
        guard committedAppSettings.torEnabled else { return }
        startTorEngine()
    }

    // MARK: - Engine start / stop

    private func startTorEngine() {
        torStatusPollingTask?.cancel()

        if committedAppSettings.torUseCustomProxy {
            let addr = committedAppSettings.torCustomProxyAddress.trimmingCharacters(in: .whitespaces)
            let result = Result { try torActivateCustomProxy(socks5Url: addr) }
            switch result {
            case .success:
                torStatus = .ready
            case .failure(let err):
                torStatus = .error(message: err.localizedDescription)
            }
        } else {
            let dataDir = Self.torCacheDirectory()
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await torStart(dataDir: dataDir)
                } catch {
                    self.torStatus = .error(message: error.localizedDescription)
                    return
                }
                self.beginStatusPolling()
            }
            torStatus = .bootstrapping(percent: 0)
            beginStatusPolling()
        }
    }

    private func stopTorEngine() {
        torStatusPollingTask?.cancel()
        torStatusPollingTask = nil
        torStop()
        torStatus = .stopped
    }

    // MARK: - Status polling

    private func beginStatusPolling() {
        torStatusPollingTask?.cancel()
        torStatusPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let latest = fetchTorStatusFromRust()
                self.torStatus = latest
                // Stop polling once terminal states are reached.
                switch latest {
                case .ready:
                    // Keep polling so we detect if Tor drops.
                    break
                case .error:
                    // Stay in error state; user must tap Reconnect.
                    return
                case .stopped:
                    return
                case .bootstrapping:
                    break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Cache directory

    static func torCacheDirectory() -> String {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls.first?.path ?? NSTemporaryDirectory()
    }
}
