//
//  StockPricesStoreTests.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//

import XCTest
import Combine
@testable import StockPriceTracker

final class StockPricesStoreTests: XCTestCase {

    private var service: TestWebSocketService!
    private var store: StockPricesStore!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        service = TestWebSocketService()
        cancellables = []
        // Provide deterministic initial symbols
        store = await MainActor.run {
            StockPricesStore(service: service, initialSymbols: ["AAPL", "GOOG", "TSLA"])
        }
        // StockPricesStore.start() is called in init by default
    }

    override func tearDown() async throws {
        cancellables = nil
        store = nil
        service = nil
        try await super.tearDown()
    }

    func testStartsConnectedOnInit() async throws {
        let isConnected = await MainActor.run { store.isConnected }
        XCTAssertTrue(isConnected)
        XCTAssertEqual(service.didConnectCount, 1)
    }

    func testStopDisconnectsAndStopsTimer() async throws {
        await MainActor.run {
            store.stop()
        }
        let isConnected = await MainActor.run { store.isConnected }
        XCTAssertFalse(isConnected)
        XCTAssertEqual(service.didDisconnectCount, 1)
    }

    func testStartIsIdempotent() async throws {
        await MainActor.run {
            store.start()
            store.start()
        }
        XCTAssertEqual(service.didConnectCount, 1, "start should not connect twice")
    }

    func testStopIsIdempotent() async throws {
        await MainActor.run {
            store.stop()
            store.stop()
        }
        XCTAssertEqual(service.didDisconnectCount, 1, "stop should not disconnect twice")
    }

    func testApplyEchoedUpdateUpdatesPricesAndSortsDescending() async throws {
        // Capture initial order and create updates that will change sort
        let initialStocks = await MainActor.run { store.stocks }
        XCTAssertEqual(initialStocks.map(\.symbol), ["AAPL", "GOOG", "TSLA"])

        // Push updates: set TSLA highest price, AAPL middle, GOOG lowest
        let messages = [
            StockPriceMessage(symbol: "TSLA", price: 999.99, timestamp: Date()),
            StockPriceMessage(symbol: "AAPL", price: 500.00, timestamp: Date()),
            StockPriceMessage(symbol: "GOOG", price: 100.00, timestamp: Date())
        ]

        let exp = expectation(description: "stocks updated and sorted")
        var observedUpdates = 0
        await MainActor.run {
            store.$stocks
                .dropFirst() // skip initial
                .sink { _ in
                    observedUpdates += 1
                    exp.fulfill()
                }
                .store(in: &cancellables)
        }

        service.sendIncoming(messages)

        await fulfillment(of: [exp], timeout: 1.0)
        let updated = await MainActor.run { store.stocks }
        XCTAssertEqual(updated.map(\.symbol), ["TSLA", "AAPL", "GOOG"])
        XCTAssertGreaterThan(observedUpdates, 0)
    }

    func testStockLookupBySymbol() async throws {
        let stock = await MainActor.run { store.stock(for: "GOOG") }
        XCTAssertNotNil(stock)
        XCTAssertEqual(stock?.symbol, "GOOG")
    }

    func testNoDuplicateTimerOnMultipleStartCalls() async throws {
        // We can't directly access timer, but we can infer by ensuring only one connection attempt
        await MainActor.run {
            store.start()
            store.start()
            store.start()
        }
        XCTAssertEqual(service.didConnectCount, 1)
    }
}
