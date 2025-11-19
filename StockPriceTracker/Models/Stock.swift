//
//  Stock.swift
//  StockPriceTracker
//
//  Created by Yash Manish Vora on 18/11/2025.
//

import Foundation

struct Stock: Identifiable, Equatable, Hashable {
    let id: String
    let symbol: String
    let price: Double
    let lastUpdated: Date

    init(symbol: String, price: Double, lastUpdated: Date = Date()) {
        self.id = symbol
        self.symbol = symbol
        self.price = price
        self.lastUpdated = lastUpdated
    }

    func updating(price newPrice: Double, at date: Date = Date()) -> Stock {
        Stock(symbol: symbol, price: newPrice, lastUpdated: date)
    }
}

// To communicate with the deeplink message
struct StockPriceMessage: Codable, Equatable {
    let symbol: String
    let price: Double
    let timestamp: Date

    init(symbol: String, price: Double, timestamp: Date = Date()) {
        self.symbol = symbol
        self.price = price
        self.timestamp = timestamp
    }
}
