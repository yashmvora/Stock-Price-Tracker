//
//  DetailStockView.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 19/11/2025.
//

import SwiftUI

struct DetailStockView: View {
    let symbol: String

    @EnvironmentObject private var store: StockPricesStore

    // Indicator state (mirrors StockRow)
    @State private var lastPrice: Double?
    @State private var flashColor: Color? = nil
    @State private var direction: Direction = .none
    @State private var flashID = 0

    enum Direction {
        case up, down, none

        var arrow: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            case .none: return ""
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Top-center price with indicator
            if let stock = store.stock(for: symbol) {
                HStack(spacing: 8) {
                    if direction != .none {
                        Text(direction.arrow)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(flashColor ?? .primary)
                            .animation(.easeInOut(duration: 0.2), value: flashID)
                            .accessibilityHidden(true)
                    }
                    Text(stock.price, format: .currency(code: "USD"))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(flashColor ?? .primary)
                        .animation(.easeInOut(duration: 0.2), value: flashID)
                        .accessibilityLabel("\(symbol) price \(stock.price)")
                }
                .onAppear {
                    // Initialize lastPrice on first render
                    lastPrice = stock.price
                }
                .onChange(of: stock.price) { newPrice in
                    handlePriceChange(newPrice)
                }
            } else {
                ProgressView()
            }

            // Description
            Text(description(for: symbol))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle(symbol)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func handlePriceChange(_ newPrice: Double) {
        guard let old = lastPrice else {
            lastPrice = newPrice
            direction = .none
            flashColor = nil
            return
        }

        if newPrice > old {
            direction = .up
            triggerFlash(.green)
        } else if newPrice < old {
            direction = .down
            triggerFlash(.red)
        } else {
            direction = .none
            flashColor = nil
        }
        lastPrice = newPrice
    }

    private func triggerFlash(_ color: Color) {
        flashID &+= 1
        withAnimation(.easeInOut(duration: 0.2)) {
            flashColor = color
        }
        // Reset after 1 second
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                flashColor = nil
            }
        }
    }

    private func description(for symbol: String) -> String {
        // Placeholder description — replace with real data source if available.
        "\(symbol) is a popular publicly traded company. This screen shows a live price updated via the shared websocket/deeplink connection."
    }
}

#Preview {
    let url = URL(string: "wss://ws.postman-echo.com/raw")!
    let service = WebSocketService(url: url)
    let symbols = ["AAPL","GOOG","TSLA"]
    let store = StockPricesStore(service: service, initialSymbols: symbols)
    return NavigationStack {
        DetailStockView(symbol: "AAPL")
            .environmentObject(store)
    }
}
