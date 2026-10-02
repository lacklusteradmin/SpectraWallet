import Foundation

/// Native scan controls and progress; each run has its own lifetime.
@MainActor
@Observable
final class MoneroSyncViewModel {
    var status: MoneroSyncStatus?
    var password = ""
    var restoreHeight = ""
    var error: String?
    private(set) var requestId: UUID?
    var isRunning: Bool { requestId != nil }

    func begin() {
        guard requestId == nil else { return }
        requestId = UUID()
    }

    func cancel() {
        requestId = nil
        password = ""
    }

    private func isCurrent(_ request: UUID) -> Bool {
        requestId == request && !Task.isCancelled
    }

    func sync(request: UUID,
              operation: @MainActor (String?, UInt64?, (MoneroSyncStatus) -> Void) async -> String?) async {
        guard isCurrent(request) else { return }
        defer {
            if requestId == request {
                password = ""
                requestId = nil
            }
        }
        var height: UInt64?
        if status?.targetHeight == 0 && !restoreHeight.isEmpty {
            guard let parsed = UInt64(restoreHeight) else {
                error = AppLocalization.string("Invalid restore height")
                return
            }
            height = parsed
        }
        error = nil
        let failure = await operation(password.isEmpty ? nil : password, height) { status in
            guard self.isCurrent(request) else { return }
            self.status = status
        }
        guard isCurrent(request) else { return }
        error = failure
    }
}
