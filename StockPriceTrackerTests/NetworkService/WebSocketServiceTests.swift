//
//  WebSocketServiceTests.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//

import XCTest
import Combine
@testable import StockPriceTracker

private final class FakeWebSocketTask: WebSocketTasking {
    enum FakeState: Equatable {
        case running, cancelled
    }

    private(set) var fakeState: FakeState = .running
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    var receiveQueue: [URLSessionWebSocketTask.Message] = []
    var sendError: Error?
    var receiveError: Error?

    func resume() {
        fakeState = .running
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        fakeState = .cancelled
    }

    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void) {
        sentMessages.append(message)
        completionHandler(sendError)
    }

    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        if let error = receiveError {
            completionHandler(.failure(error))
            return
        }
        if receiveQueue.isEmpty {
            completionHandler(.failure(NSError(domain: "Fake", code: -1)))
        } else {
            completionHandler(.success(receiveQueue.removeFirst()))
        }
    }
}

private struct FakeFactory: WebSocketTaskFactory {
    let task: FakeWebSocketTask
    func webSocketTask(with url: URL) -> WebSocketTasking {
        task
    }
}

final class WebSocketServiceTests: XCTestCase {

    func testConnectIsIdempotentAndStartsReceiveLoop() {
        let fakeTask = FakeWebSocketTask()
        let factory = FakeFactory(task: fakeTask)
        let svc = WebSocketService(url: URL(string: "wss://example.test")!, factory: factory)

        svc.connect()
        svc.connect() // idempotent

        XCTAssertEqual(fakeTask.fakeState, .running)
    }

    func testDisconnectCancelsTask() {
        let fakeTask = FakeWebSocketTask()
        let factory = FakeFactory(task: fakeTask)
        let svc = WebSocketService(url: URL(string: "wss://example.test")!, factory: factory)

        svc.connect()
        svc.disconnect()

        XCTAssertEqual(fakeTask.fakeState, .cancelled)
    }

    func testSendEncodesArrayAsJSONString() throws {
        let fakeTask = FakeWebSocketTask()
        let factory = FakeFactory(task: fakeTask)
        let svc = WebSocketService(url: URL(string: "wss://example.test")!, factory: factory)

        svc.connect()
        let msgs = [
            StockPriceMessage(symbol: "AAPL", price: 123.45, timestamp: ISO8601DateFormatter().date(from: "2024-01-01T12:00:00Z")!),
            StockPriceMessage(symbol: "GOOG", price: 222.22, timestamp: ISO8601DateFormatter().date(from: "2024-01-01T12:01:00Z")!)
        ]
        svc.send(message: msgs)

        guard case let .string(text)? = fakeTask.sentMessages.first else {
            return XCTFail("Expected string message to be sent")
        }

        XCTAssertTrue(text.contains("\"symbol\":\"AAPL\""))
        XCTAssertTrue(text.contains("\"price\":123.45"))
        XCTAssertTrue(text.contains("\"symbol\":\"GOOG\""))
        XCTAssertTrue(text.contains("\"price\":222.22"))
    }

    func testReceiveStringDecodesAndPublishes() throws {
        let fakeTask = FakeWebSocketTask()
        let factory = FakeFactory(task: fakeTask)
        let svc = WebSocketService(url: URL(string: "wss://example.test")!, factory: factory)

        let messages = [
            StockPriceMessage(symbol: "TSLA", price: 321.0, timestamp: Date())
        ]
        let data = try JSONEncoder.iso8601().encode(messages)
        let text = String(data: data, encoding: .utf8)!
        fakeTask.receiveQueue = [.string(text)]

        let exp = expectation(description: "received decoded messages")
        var received: [StockPriceMessage] = []
        let cancellable = svc.incomingMessages.sink { msgs in
            received = msgs
            exp.fulfill()
        }

        svc.connect()
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, messages)
        withExtendedLifetime(cancellable) {}
    }

    func testReceiveDataDecodesAndPublishes() throws {
        let fakeTask = FakeWebSocketTask()
        let factory = FakeFactory(task: fakeTask)
        let svc = WebSocketService(url: URL(string: "wss://example.test")!, factory: factory)

        let messages = [
            StockPriceMessage(symbol: "NVDA", price: 999.0, timestamp: Date())
        ]
        let data = try JSONEncoder.iso8601().encode(messages)
        fakeTask.receiveQueue = [.data(data)]

        let exp = expectation(description: "received decoded data messages")
        var received: [StockPriceMessage] = []
        let cancellable = svc.incomingMessages.sink { msgs in
            received = msgs
            exp.fulfill()
        }

        svc.connect()
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(received, messages)
        withExtendedLifetime(cancellable) {}
    }
}

private extension JSONEncoder {
    static func iso8601() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

