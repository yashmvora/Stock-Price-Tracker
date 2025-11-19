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

final class WebSocketService: WebSocketServicing {
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private let incomingSubject = PassthroughSubject<[StockPriceMessage], Never>()
    var incomingMessages: AnyPublisher<[StockPriceMessage], Never> {
        incomingSubject.eraseToAnyPublisher()
    }

    private var cancellables = Set<AnyCancellable>()
    private let queue = DispatchQueue(label: "WebSocketService.queue")

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func connect() {
        guard task == nil else { return }
        let task = session.webSocketTask(with: url)
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
                    // You might want to surface errors differently
                    print("WebSocket send error: \(error)")
                    // Optionally, emit nothing; echo server will not respond if send fails
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
                // Attempt to continue receiving if the task is still open
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
        // Continue the receive loop
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
