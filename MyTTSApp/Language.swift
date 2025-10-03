//
//  Language.swift
//  MyTTSApp
//
//  Created by Adarsh Ranjan on 03/10/25.
//


enum Language: String, CaseIterable, Identifiable {
    case english = "English"
    case french = "French"
    case arabic = "Arabic"
    case chinese = "Chinese"

    var id: String { self.rawValue }

    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .french: return "🇫🇷"
        case .arabic: return "🇸🇦"
        case .chinese: return "🇨🇳"
        }
    }
}
