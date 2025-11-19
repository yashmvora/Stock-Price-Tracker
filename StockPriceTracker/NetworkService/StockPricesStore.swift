//
//  StockPricesStore.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//

import Foundation
import Combine

@MainActor
final class StockPricesStore: ObservableObject {
    @Published private(set) var stocks: [Stock] = []
    @Published private(set) var isConnected: Bool = false

    private let service: WebSocketServicing
    private var cancellables = Set<AnyCancellable>()
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "StockPricesStore.timer.queue", qos: .background)

    init(service: WebSocketServicing, initialSymbols: [String]) {
        self.service = service
        self.stocks = initialSymbols.map { Stock(symbol: $0, price: Self.initialPrice()) }
        bind()
        // Start connected by default. If you want manual control at app launch, comment the next line.
        start()
    }

    deinit {
        // deinit is nonisolated; hop to the main actor to call main-actor methods safely.
        Task { @MainActor [weak self, service] in
            guard let self else { return }
            stop()
            // Also clear Combine subscriptions on main to match the store's actor.
            cancellables.removeAll()
            // Ensure timer is torn down if any remains (defensive)
            timer?.setEventHandler(handler: nil)
            timer?.cancel()
            timer = nil
            // If stop() didn't already call disconnect due to state, ensure socket is closed.
            service.disconnect()
        }
    }

    func stock(for symbol: String) -> Stock? {
        stocks.first(where: { $0.symbol == symbol })
    }

    // MARK: - Connection Control

    func start() {
        guard !isConnected else { return }
        service.connect()
        isConnected = true
        startPriceGenerationTimer()
    }

    func stop() {
        guard isConnected else { return }
        // stop timer
        timer?.setEventHandler(handler: nil)
        timer?.cancel()
        timer = nil

        // disconnect websocket
        service.disconnect()
        isConnected = false
    }

    // MARK: - Bind incoming

    private func bind() {
        service.incomingMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msgs in
                self?.applyEchoedUpdate(msgs)
            }
            .store(in: &cancellables)
    }

    // MARK: - Price generation

    private func startPriceGenerationTimer() {
        // Ensure not to create duplicates
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: timerQueue)
        t.schedule(deadline: .now(), repeating: .seconds(2))
        t.setEventHandler { [weak self] in
            self?.generateAndSendRandomUpdate()
        }
        timer = t
        t.resume()
    }

    private func generateAndSendRandomUpdate() {
        Task { @MainActor [weak self] in
            guard let self = self, self.isConnected, !self.stocks.isEmpty else { return }
            var messages: [StockPriceMessage] = []
            self.stocks.forEach { stk in
                let newPrice = Self.perturb(price: stk.price)
                let message = StockPriceMessage(symbol: stk.symbol, price: newPrice, timestamp: Date())
                messages.append(message)
            }
            DispatchQueue.global(qos: .background).async { [messages, service = self.service] in
                service.send(message: messages)
            }
        }
    }

    // MARK: - Apply updates

    private func applyEchoedUpdate(_ msgs: [StockPriceMessage]) {
        guard !msgs.isEmpty else { return }
        var updated = stocks
        for msg in msgs {
            if let idx = updated.firstIndex(where: { $0.symbol == msg.symbol }) {
                updated[idx] = updated[idx].updating(price: msg.price, at: msg.timestamp)
            }
        }
        if updated != stocks {
            stocks = updated.sorted(by: { $0.price > $1.price })
        }
    }

    // MARK: - Helpers

    private static func initialPrice() -> Double {
        Double.random(in: 50...500).rounded(toPlaces: 2)
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
