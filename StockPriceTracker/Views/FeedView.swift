//
//  FeedView.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 18/11/2025.
//

import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: StockPricesStore

    var body: some View {
        NavigationStack {
            List(store.stocks) { stock in
                NavigationLink(value: stock.symbol) {
                    StockRow(stock: stock)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(stock.symbol) price \(stock.price)")
                }
            }
            .navigationTitle("Stocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Text(store.isConnected ? "🟢" : "🔴")
                            .accessibilityHidden(true)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if store.isConnected {
                            store.stop()
                        } else {
                            store.start()
                        }
                    } label: {
                        Text(store.isConnected ? "Stop" : "Start")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(store.isConnected ? "Stop price feed" : "Start price feed")
                }
            }
            .navigationDestination(for: String.self) { symbol in
                DetailStockView(symbol: symbol)
            }
        }
    }
}

private struct StockRow: View {
    let stock: Stock

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
        HStack {
            VStack(alignment: .leading) {
                Text(stock.symbol)
                    .font(.headline)
            }
            Spacer()
            HStack(spacing: 6) {
                if direction != .none {
                    Text(direction.arrow)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(flashColor ?? .primary)
                        .animation(.easeInOut(duration: 0.2), value: flashID)
                        .accessibilityHidden(true)
                }
                Text(stock.price, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .font(.headline)
                    .foregroundStyle(flashColor ?? .primary)
                    .animation(.easeInOut(duration: 0.2), value: flashID)
            }
        }
        .onAppear {
            lastPrice = stock.price
        }
        .onChange(of: stock.price) { newPrice in
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
    }

    private func triggerFlash(_ color: Color) {
        flashID &+= 1
        withAnimation(.easeInOut(duration: 0.2)) {
            flashColor = color
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                flashColor = nil
            }
        }
    }
}

#Preview {
    let url = URL(string: "wss://ws.postman-echo.com/raw")!
    let service = WebSocketService(url: url)
    let symbols = [
        "AAPL","GOOG","TSLA","NVDA","MSFT","AMZN","META","NFLX","ADBE","AVGO",
        "ORCL","INTC","AMD","SHOP","UBER","ABNB","SNOW","CRM","SQ","PLTR",
        "SPOT","PYPL","COIN","BABA","NIO"
    ]
    let store = StockPricesStore(service: service, initialSymbols: symbols)
    return FeedView()
        .environmentObject(store)
}
