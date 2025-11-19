//
//  WebSocketServiceMock.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//


import Foundation
import Combine
@testable import StockPriceTracker

final class TestWebSocketService: WebSocketServicing {
    private let subject = PassthroughSubject<[StockPriceMessage], Never>()
    var incomingMessages: AnyPublisher<[StockPriceMessage], Never> { subject.eraseToAnyPublisher() }

    private(set) var didConnectCount = 0
    private(set) var didDisconnectCount = 0
    private(set) var sentBatches: [[StockPriceMessage]] = []
    var isConnected: Bool = false

    func connect() {
        guard !isConnected else { return }
        isConnected = true
        didConnectCount += 1
    }

    func disconnect() {
        guard isConnected else { return }
        isConnected = false
        didDisconnectCount += 1
    }

    func send(message: [StockPriceMessage]) {
        sentBatches.append(message)
        // In production, an echo server would send the same payload back.
        // Tests can choose to either simulate echo here or manually push via sendIncoming.
        // We'll not auto-echo to allow explicit control in tests.
    }

    // Test helper to simulate server push/echo
    func sendIncoming(_ messages: [StockPriceMessage]) {
        subject.send(messages)
    }
}

