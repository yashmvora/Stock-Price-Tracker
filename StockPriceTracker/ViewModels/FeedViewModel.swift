//
//  FeedViewModel.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 18/11/2025.
//

import Foundation
import Combine

@MainActor
final class FeedViewModel: ObservableObject {
    @Published private(set) var stocks: [Stock] = []

    private let service: WebSocketServicing
    private var cancellables = Set<AnyCancellable>()
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "FeedViewModel.timer.queue", qos: .background)

    init(service: WebSocketServicing, initialSymbols: [String]) {
        self.service = service
        self.stocks = initialSymbols.map { Stock(symbol: $0, price: Self.initialPrice()) }
        bind()
        service.connect()
        startPriceGenerationTimer()
    }

    deinit {
        timer?.setEventHandler(handler: nil)
        timer?.cancel()
        timer = nil
        service.disconnect()
    }

    private func bind() {
        service.incomingMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.applyEchoedUpdate(msg)
            }
            .store(in: &cancellables)
    }
    
    private func startPriceGenerationTimer() {
        // Create a background timer that fires every 2 seconds
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: .seconds(2))
        t.setEventHandler { [weak self] in
            // This runs on timerQueue (background)
            self?.generateAndSendRandomUpdate()
        }
        timer = t
        t.resume()
    }

    private func generateAndSendRandomUpdate() {
        // Access to stocks is on @MainActor; hop to main to read safely
        Task { @MainActor [weak self] in
            guard let self = self, !self.stocks.isEmpty else { return }
            var stockPriceMessage: [StockPriceMessage] = []
            self.stocks.forEach { stk in
                let newPrice = Self.perturb(price: stk.price)
                let message = StockPriceMessage(symbol: stk.symbol, price: newPrice, timestamp: Date())
                stockPriceMessage.append(message)
            }
            // Send can occur off-main; dispatch to background to avoid blocking main
            DispatchQueue.global(qos: .background).async { [stockPriceMessage, service = self.service] in
                service.send(message: stockPriceMessage)
            }
        }
    }

    private func applyEchoedUpdate(_ msgs: [StockPriceMessage]) {
        guard !msgs.isEmpty else { return }
        var updatedStocks = stocks
        for msg in msgs {
            if let idx = updatedStocks.firstIndex(where: { $0.symbol == msg.symbol }) {
                updatedStocks[idx] = updatedStocks[idx].updating(price: msg.price, at: msg.timestamp)
            }
        }
        if updatedStocks != stocks {
            stocks = updatedStocks.sorted(by: { $0.price > $1.price })
        }
    }

    private static func initialPrice() -> Double {
        Double.random(in: 50...500)
            .rounded(toPlaces: 2)
    }

    private static func perturb(price: Double) -> Double {
        let delta = Double.random(in: -2.0...2.0)
        return max(0.01, (price + delta)).rounded(toPlaces: 2)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        guard places >= 0 else { return self }
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
