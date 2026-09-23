import Foundation

/// Transient native workflow identity. Core owns every transaction and signature.
@MainActor
@Observable
final class SendSession {
    enum Operation: Equatable { case build, resume, sign, broadcast }
    private(set) var id = UUID()
    private(set) var operation: Operation?
    var artifact: SendArtifact?
    var endpoints: [String] = []
    var selectedEndpoints: Set<String> = []
    var error: String?

    func reset() {
        id = UUID()
        operation = nil
        artifact = nil
        endpoints = []
        selectedEndpoints = []
        error = nil
    }

    func isCurrent(_ request: UUID) -> Bool { id == request && !Task.isCancelled }

    private func finish(_ request: UUID) {
        if id == request { operation = nil }
    }

    /// Adopt a complete artifact/endpoint pair together, never half of either request.
    @discardableResult
    func load(operation: Operation, prepare: () async throws -> SendArtifact,
              endpoints loadEndpoints: (String) async throws -> [String]) async -> Bool {
        guard self.operation == nil else { return false }
        let request = id
        self.operation = operation
        defer { finish(request) }
        do {
            let prepared = try await prepare()
            guard isCurrent(request) else { return false }
            let choices = try await loadEndpoints(prepared.chainId)
            guard isCurrent(request) else { return false }
            artifact = prepared
            endpoints = choices
            selectedEndpoints = Set(prepared.selectedEndpoints).intersection(choices)
            error = nil
            return true
        } catch {
            if isCurrent(request) { self.error = error.localizedDescription }
            return false
        }
    }

    func sign(password: String?, authenticate: () async -> Bool,
              sign: (String, String, String?) async throws -> SendArtifact) async {
        guard operation == nil, let artifact, artifact.stage == .prepared else { return }
        let request = id
        operation = .sign
        defer { finish(request) }
        guard await authenticate(), isCurrent(request), self.artifact?.id == artifact.id else { return }
        do {
            let signed = try await sign(artifact.id, artifact.reviewDigest, password)
            guard isCurrent(request), self.artifact?.id == artifact.id else { return }
            self.artifact = signed
            error = nil
        } catch {
            if isCurrent(request) { self.error = error.localizedDescription }
        }
    }

    func broadcast(submit: (String, [String]) async throws -> SendArtifact) async -> SendArtifact? {
        guard operation == nil, let artifact, artifact.stage == .signed else { return nil }
        let request = id
        operation = .broadcast
        defer { finish(request) }
        do {
            let result = try await submit(artifact.id, endpoints.filter(selectedEndpoints.contains))
            guard isCurrent(request), self.artifact?.id == artifact.id else { return nil }
            self.artifact = result
            error = nil
            return result
        } catch {
            if isCurrent(request) { self.error = error.localizedDescription }
            return nil
        }
    }
}
