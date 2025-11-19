//
//  FeedViewModelTests.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//

import XCTest
import Combine
@testable import StockPriceTracker

@MainActor
final class FeedViewModelTests: XCTestCase {

    private var service: TestWebSocketService!
    private var viewModel: FeedViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        service = TestWebSocketService()
        cancellables = []
        viewModel = FeedViewModel(service: service, initialSymbols: ["AAPL", "GOOG", "TSLA"])
        // FeedViewModel.connect() is called in init
        XCTAssertTrue(service.isConnected)
    }

    override func tearDown() {
        viewModel = nil
        service = nil
        cancellables = nil
        super.tearDown()
    }

    func testInitialStocksExist() {
        XCTAssertEqual(viewModel.stocks.count, 3)
        XCTAssertEqual(Set(viewModel.stocks.map(\.symbol)), ["AAPL","GOOG","TSLA"])
    }

    func testApplyEchoedUpdateSortsAndUpdates() {
        let exp = expectation(description: "stocks updated")
        viewModel.$stocks
            .dropFirst()
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        let messages = [
            StockPriceMessage(symbol: "GOOG", price: 200, timestamp: Date()),
            StockPriceMessage(symbol: "AAPL", price: 300, timestamp: Date()),
            StockPriceMessage(symbol: "TSLA", price: 100, timestamp: Date())
        ]
        service.sendIncoming(messages)

        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(viewModel.stocks.map(\.symbol), ["AAPL","GOOG","TSLA"])
    }

    func testDeinitDisconnectsAndCancelsTimer() async {
        weak var weakVM: FeedViewModel?
        autoreleasepool {
            let vm = FeedViewModel(service: service, initialSymbols: ["AAPL"])
            weakVM = vm
        }
        // Allow deinit to run
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertNil(weakVM)
        XCTAssertEqual(service.didDisconnectCount, 1)
    }
}
