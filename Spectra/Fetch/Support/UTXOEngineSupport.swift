import Foundation

enum UTXOEngineSupport {
    static func performSynchronousRequest(
        _ request: URLRequest,
        timeout: TimeInterval,
        retries: Int
    ) throws -> Data {
        var lastError: String = "Unknown network error."

        for attempt in 0 ... retries {
            let semaphore = DispatchSemaphore(value: 0)
            var capturedData: Data?
            var capturedResponse: URLResponse?
            var capturedError: Error?

            var configuredRequest = request
            configuredRequest.timeoutInterval = timeout

            ProviderHTTP.sessionDataTask(with: configuredRequest) { data, response, error in
                capturedData = data
                capturedResponse = response
                capturedError = error
                semaphore.signal()
            }.resume()

            semaphore.wait()

            if let capturedError {
                lastError = capturedError.localizedDescription
            } else if let httpResponse = capturedResponse as? HTTPURLResponse {
                if (200 ..< 300).contains(httpResponse.statusCode), let capturedData {
                    return capturedData
                }
                lastError = "HTTP \(httpResponse.statusCode)"
            } else {
                lastError = "Network response was invalid."
            }

            if attempt < retries {
                let delay = UInt32(200_000 * (attempt + 1))
                usleep(delay)
            }
        }

        throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: lastError])
    }

}

extension Data {
    init?(hexEncoded string: String) {
        let evenLengthString = string.count.isMultiple(of: 2) ? string : "0" + string
        var data = Data(capacity: evenLengthString.count / 2)
        var index = evenLengthString.startIndex

        for _ in 0 ..< evenLengthString.count / 2 {
            let nextIndex = evenLengthString.index(index, offsetBy: 2)
            let byteString = evenLengthString[index ..< nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
