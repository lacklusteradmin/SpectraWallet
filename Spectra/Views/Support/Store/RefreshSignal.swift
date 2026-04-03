import Foundation
import Combine

@MainActor
final class ViewRefreshSignal: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    private var cancellables: Set<AnyCancellable> = []

    init(_ publishers: [AnyPublisher<Void, Never>]) {
        for publisher in publishers {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] in
                    self?.revision &+= 1
                }
                .store(in: &cancellables)
        }
    }
}

extension Publisher where Failure == Never {
    func asVoidSignal() -> AnyPublisher<Void, Never> {
        map { _ in () }.eraseToAnyPublisher()
    }
}
