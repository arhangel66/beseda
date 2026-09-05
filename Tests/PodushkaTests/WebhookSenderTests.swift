import Foundation
import Testing

@testable import Podushka

/// Remembers the request it was handed and answers with a canned status.
private actor SpyTransport {
    private(set) var request: URLRequest?
    private let status: Int
    private let failure: Error?

    init(status: Int = 200, failure: Error? = nil) {
        self.status = status
        self.failure = failure
    }

    func handle(_ request: URLRequest) throws -> (Data, URLResponse) {
        self.request = request
        if let failure {
            throw failure
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data("{\"action\":\"ingested\"}".utf8), response)
    }
}

private let endpoint = URL(string: "https://kushetka.example/api/webhooks/krisp")!

@Test func aTwoHundredWithAnActionIsDelivered() {
    let outcome = WebhookSender.classify(data: Data("{\"action\":\"ingested\"}".utf8), status: 200)

    #expect(outcome == .delivered(status: 200, action: "ingested", body: "{\"action\":\"ingested\"}"))
    #expect(outcome.isRetryable == false)
    #expect(outcome.state == "delivered")
}

@Test func aFourOhOneIsRejectedWithoutRetry() {
    let outcome = WebhookSender.classify(data: Data("{\"detail\":\"invalid authorization\"}".utf8), status: 401)

    #expect(outcome == .rejected(status: 401, body: "{\"detail\":\"invalid authorization\"}"))
    #expect(outcome.isRetryable == false)
    #expect(outcome.error == "HTTP 401")
}

@Test func aFiveOhThreeIsAFailureWorthRetrying() {
    let outcome = WebhookSender.classify(data: Data(), status: 503)

    #expect(outcome == .failed(status: 503, body: "", error: "HTTP 503"))
    #expect(outcome.isRetryable == true)
}

@Test func theResponseBodyIsCutAtTwoKilobytes() {
    let long = String(repeating: "x", count: 2049)

    let outcome = WebhookSender.classify(data: Data(long.utf8), status: 200)

    #expect(outcome.responseBody?.count == 2048)
}

@Test func theRequestCarriesTheSecretAndDeliveryHeaders() {
    let request = WebhookSender.request(
        url: endpoint, body: Data("{}".utf8), secret: "s3cret", event: "transcript_created",
        deliveryID: "d-1", timeout: 150
    )

    #expect(request.httpMethod == "POST")
    #expect(request.timeoutInterval == 150)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "s3cret")
    #expect(request.value(forHTTPHeaderField: "X-Podushka-Secret") == "s3cret")
    #expect(request.value(forHTTPHeaderField: "X-Podushka-Event") == "transcript_created")
    #expect(request.value(forHTTPHeaderField: "X-Podushka-Delivery") == "d-1")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Podushka")
}

@Test func sendGoesThroughTheInjectedTransport() async {
    let spy = SpyTransport()
    let sender = WebhookSender(transport: { try await spy.handle($0) })

    let outcome = await sender.send(
        Data("{\"event\":\"x\"}".utf8), to: endpoint, secret: "s", event: "transcript_created", deliveryID: "d-1"
    )

    #expect(outcome.responseAction == "ingested")
    #expect(await spy.request?.httpBody == Data("{\"event\":\"x\"}".utf8))
    #expect(await spy.request?.url == endpoint)
}

@Test func aTimedOutTransportBecomesARetryableFailure() async {
    let spy = SpyTransport(failure: URLError(.timedOut))
    let sender = WebhookSender(transport: { try await spy.handle($0) }, timeout: 150)

    let outcome = await sender.send(Data(), to: endpoint, secret: "s", event: "test", deliveryID: "d-1")

    #expect(outcome == .failed(status: nil, body: nil, error: "Сервис не ответил за 150 с"))
    #expect(outcome.isRetryable == true)
}

@Test func endpointAcceptsOnlyHttpAddressesWithAHost() {
    #expect(WebhookSender.endpoint(from: "ftp://kushetka.example/x") == nil)
    #expect(WebhookSender.endpoint(from: "kushetka") == nil)
    #expect(WebhookSender.endpoint(from: "") == nil)
    #expect(WebhookSender.endpoint(from: "  https://kushetka.example/api/webhooks/krisp \n") == endpoint)
    #expect(WebhookSender.endpoint(from: "http://127.0.0.1:8090/api/webhooks/krisp")?.port == 8090)
}
