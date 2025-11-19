//
//  WebSocketService.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 18/11/2025.
//

import Foundation
import Combine

protocol WebSocketServicing {
    var incomingMessages: AnyPublisher<[StockPriceMessage], Never> { get }
    
    func connect()
    func disconnect()
    func send(message: [StockPriceMessage])
}

// Abstractions to avoid subclassing Foundation types in tests
protocol WebSocketTasking {
    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void)
    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
}

protocol WebSocketTaskFactory {
    func webSocketTask(with url: URL) -> WebSocketTasking
}

// Production adapter wrapping URLSessionWebSocketTask
private final class URLSessionWebSocketTaskAdapter: WebSocketTasking {
    private let underlying: URLSessionWebSocketTask

    init(underlying: URLSessionWebSocketTask) {
        self.underlying = underlying
    }

    func resume() {
        underlying.resume()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        underlying.cancel(with: closeCode, reason: reason)
    }

    func send(_ message: URLSessionWebSocketTask.Message, completionHandler: @escaping (Error?) -> Void) {
        underlying.send(message, completionHandler: completionHandler)
    }

    func receive(completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void) {
        underlying.receive(completionHandler: completionHandler)
    }
}

// Production factory using URLSession
struct URLSessionWebSocketFactory: WebSocketTaskFactory {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func webSocketTask(with url: URL) -> WebSocketTasking {
        URLSessionWebSocketTaskAdapter(underlying: session.webSocketTask(with: url))
    }
}

final class WebSocketService: WebSocketServicing {
    private let url: URL
    private let factory: WebSocketTaskFactory
    private var task: WebSocketTasking?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let incomingSubject = PassthroughSubject<[StockPriceMessage], Never>()
    var incomingMessages: AnyPublisher<[StockPriceMessage], Never> {
        incomingSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "WebSocketService.queue")

    // Updated initializer to accept a factory. Keep a convenience init for existing call sites.
    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.factory = URLSessionWebSocketFactory(session: session)
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    // Additional initializer for tests to inject a custom factory
    init(url: URL, factory: WebSocketTaskFactory) {
        self.url = url
        self.factory = factory
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func connect() {
        guard task == nil else { return }
        let task = factory.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(message: [StockPriceMessage]) {
        guard let task = task else { return }
        do {
            let data = try encoder.encode(message)
            let string = String(data: data, encoding: .utf8) ?? ""
            task.send(.string(string)) { error in
                if let error = error {
                    print("WebSocket send error: \(error)")
                }
            }
        } catch {
            print("Encoding error: \(error)")
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                print("WebSocket receive error: \(error)")
                if self.task != nil {
                    self.scheduleNextReceive()
                }
            case .success(let message):
                self.handle(message)
                self.scheduleNextReceive()
            }
        }
    }

    private func scheduleNextReceive() {
        receiveLoop()
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let decoded = try? decoder.decode([StockPriceMessage].self, from: data) {
                incomingSubject.send(decoded)
            }
        case .data(let data):
            if let decoded = try? decoder.decode([StockPriceMessage].self, from: data) {
                incomingSubject.send(decoded)
            }
        @unknown default:
            break
        }
    }
}

