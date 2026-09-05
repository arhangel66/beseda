import Foundation

/// What one delivery attempt came back with. Only `failed` is worth another try:
/// a 4xx means the address or the secret is wrong and will stay wrong.
enum WebhookOutcome: Equatable {
    case delivered(status: Int, action: String?, body: String)
    case rejected(status: Int, body: String)
    case failed(status: Int?, body: String?, error: String)

    var isRetryable: Bool {
        if case .failed = self {
            return true
        }
        return false
    }

    var state: String {
        if case .delivered = self {
            return "delivered"
        }
        return "failed"
    }

    var httpStatus: Int? {
        switch self {
        case .delivered(let status, _, _), .rejected(let status, _):
            status
        case .failed(let status, _, _):
            status
        }
    }

    var responseAction: String? {
        if case .delivered(_, let action, _) = self {
            return action
        }
        return nil
    }

    var responseBody: String? {
        switch self {
        case .delivered(_, _, let body), .rejected(_, let body):
            body
        case .failed(_, let body, _):
            body
        }
    }

    var error: String? {
        switch self {
        case .delivered:
            nil
        case .rejected(let status, _):
            "HTTP \(status)"
        case .failed(_, _, let error):
            error
        }
    }
}

/// One POST of a prepared body. The transport is injectable so tests never touch the network.
final class WebhookSender: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// kushetka runs its language model inside the request behind a 120 s nginx read timeout
    static let defaultTimeout: TimeInterval = 150
    static let responseBodyLimit = 2048

    private let transport: Transport
    private let timeout: TimeInterval

    init(
        transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
        timeout: TimeInterval = WebhookSender.defaultTimeout
    ) {
        self.transport = transport
        self.timeout = timeout
    }

    /// never throws: every way a request can go wrong is an outcome the journal keeps
    func send(_ body: Data, to url: URL, secret: String, event: String, deliveryID: String) async -> WebhookOutcome {
        let request = Self.request(
            url: url, body: body, secret: secret, event: event, deliveryID: deliveryID, timeout: timeout
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code == .timedOut {
            return .failed(status: nil, body: nil, error: "Сервис не ответил за \(Int(timeout)) с")
        } catch {
            return .failed(status: nil, body: nil, error: error.localizedDescription)
        }
        return Self.classify(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    static func request(
        url: URL, body: Data, secret: String, event: String, deliveryID: String, timeout: TimeInterval
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // kushetka compares the whole Authorization value with the secret, so no scheme prefix
        request.setValue(secret, forHTTPHeaderField: "Authorization")
        request.setValue(secret, forHTTPHeaderField: "X-Podushka-Secret")
        request.setValue(event, forHTTPHeaderField: "X-Podushka-Event")
        request.setValue(deliveryID, forHTTPHeaderField: "X-Podushka-Delivery")
        request.setValue("Podushka", forHTTPHeaderField: "User-Agent")
        return request
    }

    static func classify(data: Data, status: Int) -> WebhookOutcome {
        let body = String(String(decoding: data, as: UTF8.self).prefix(responseBodyLimit))
        switch status {
        case 200..<300:
            let action = (try? JSONDecoder().decode(ActionResponse.self, from: data))?.action
            return .delivered(status: status, action: action, body: body)
        case 400..<500:
            return .rejected(status: status, body: body)
        default:
            return .failed(status: status, body: body, error: "HTTP \(status)")
        }
    }

    static func endpoint(from string: String) -> URL? {
        guard let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}

private struct ActionResponse: Decodable {
    let action: String?
}
