//
//  ContentView.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 18/11/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store: StockPricesStore

    init() {
        let url = URL(string: "wss://ws.postman-echo.com/raw")!
        let service = WebSocketService(url: url)
        let symbols = [
            "AAPL","GOOG","TSLA","NVDA","MSFT","AMZN","META","NFLX","ADBE","AVGO",
            "ORCL","INTC","AMD","SHOP","UBER","ABNB","SNOW","CRM","SQ","PLTR",
            "SPOT","PYPL","COIN","BABA","NIO"
        ]
        _store = StateObject(wrappedValue: StockPricesStore(service: service, initialSymbols: symbols))
    }

    var body: some View {
        FeedView()
            .environmentObject(store)
    }
}

#Preview {
    ContentView()
}
