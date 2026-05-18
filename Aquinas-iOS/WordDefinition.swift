//
//  WordDefinition.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/17/26.
//

import Foundation

// MARK: - Legacy Word Definition

/// Older definition model. Newer insight sheets use ConceptDefinition in ContentView.swift.
struct WordDefinition: Identifiable {
    let id = UUID()
    let formattedWord: String
    let partOfSpeech: String
    let pronunciation: String
    let definition: String
    let example: String?
}
