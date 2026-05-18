//
//  BookshelfView.swift
//  Aquinas-iOS
//
//  Created by Ryan on 4/14/26.
//

import Foundation
import SwiftUI

// MARK: - Bookshelf

/// Background library view for saved insights, current topic, and conversation history.
struct BookshelfView: View {
    @Binding var isAtTop: Bool
    @Binding var showFilePicker: Bool

    @State private var activeWordLookup: ConceptDefinition? = nil
    @State private var isThinkingEnabled: Bool = false
    @State private var selectedPersonality: String = "Friendly"
    @State private var isDropdownOpen: Bool = false
    @State private var personalityIconDrawID = UUID()

    // Saved insight cards shared with the active inquiry screen.
    @Binding var collectedDefinitions: [ConceptDefinition]

    let brandGreen = AquinasTheme.Colors.secondaryMuted
    let brandRed = AquinasTheme.Colors.accent

    let mutedText = AquinasTheme.Colors.placeholderText
    let cardBackground = AquinasTheme.Colors.componentBackground

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {

                // Top buffer protects content from the overlaid active inquiry handle.
                Spacer()
                    .frame(height: 160)

                // Current topic header and bookshelf controls.
                VStack(alignment: .leading, spacing: 12) {
                    Text("CURRENT TOPIC:")
                        .font(.figtreeHeading3)
                        .foregroundColor(brandGreen)

                    Text(createEditorialTitle(
                        fullText: "What Is The Didache?",
                        keyword: "The Didache?",
                        fontSize: 34,
                        baseColor: .brandBrown,
                        keywordColor: .brandLightGreen
                    ))

                    // Bookshelf controls. These mirror the active inquiry controls visually.
                    HStack(spacing: 12) {

                        // Attachment button.
                        Button(action: { showFilePicker = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .medium))
                                .sfSymbolDrawOn()
                                .aquinasIconControl()
                        }

                        // Thinking toggle.
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isThinkingEnabled.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .sfSymbolDrawOn()
                                Text("Thinking")
                                    .font(.figtreeParagraph)
                            }
                            .padding(.horizontal, 16)
                            .aquinasCapsuleControl(isSelected: isThinkingEnabled)
                        }

                        // Personality menu.
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                isDropdownOpen.toggle()
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedPersonality == "Friendly" ? "brain.head.profile.fill" : "book.pages.fill")
                                    .frame(width: 20, height: 20)
                                    .id(personalityIconDrawID)
                                    .sfSymbolDrawOn()
                                Text(selectedPersonality)
                                    .font(.figtreeParagraph)
                                    .fixedSize()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.leading, 2)
                                    .sfSymbolDrawOn()
                            }
                            .padding(.horizontal, 16)
                            .aquinasCapsuleControl()
                        }
                        .overlay(alignment: .topLeading) {
                            if isDropdownOpen {
                                VStack(alignment: .leading, spacing: 18) {
                                    // Current personality row closes the menu.
                                    Button(action: {
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            isDropdownOpen.toggle()
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: selectedPersonality == "Friendly" ? "brain.head.profile.fill" : "book.pages.fill")
                                                .frame(width: 20, height: 20)
                                                .sfSymbolDrawOn()
                                            Text(selectedPersonality)
                                                .font(.figtreeParagraph)
                                            Image(systemName: "chevron.up")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.leading, 2)
                                                .sfSymbolDrawOn()
                                        }
                                    }

                                    // Alternate personality row.
                                    Button(action: {
                                        selectedPersonality = (selectedPersonality == "Friendly") ? "Scholarly" : "Friendly"
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                            isDropdownOpen = false
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: selectedPersonality == "Friendly" ? "book.pages.fill" : "brain.head.profile.fill")
                                                .frame(width: 20, height: 20)
                                                .sfSymbolDrawOn()
                                            Text(selectedPersonality == "Friendly" ? "Scholarly" : "Friendly")
                                                .font(.figtreeParagraph)
                                        }
                                    }
                                }
                                .fixedSize()
                                .foregroundColor(brandGreen)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(AquinasTheme.Colors.surface)

                                )

                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(AquinasTheme.Colors.controlBorder, lineWidth: 1)
                                )
                                .shadow(color: AquinasTheme.Colors.dropShadow, radius: 12, x: 0, y: 12)
                                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                            }
                        }
                        Spacer()
                    }
                    .zIndex(2)


                    // Pinned insight chips saved from generated insight sheets.
                    if !collectedDefinitions.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("PINNED INSIGHTS:")
                                .font(.figtreeHeading3)
                                .foregroundColor(AquinasTheme.Colors.darkGreen)

                            // Horizontal scroll lets the saved insight shelf grow.
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 40) {

                                    ForEach(collectedDefinitions) { concept in
                                        Button(action: {
                                            activeWordLookup = concept
                                        }) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(concept.word)
                                                    .font(.figtreeHeading2)
                                                    .foregroundColor(brandDarkText)

                                                if !concept.pronunciation.isEmpty {
                                                    Text(concept.pronunciation)
                                                        .font(.baskervilleHeading3)
                                                        .foregroundColor(mutedText)
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.trailing, 24)
                            }
                        }
                    }
                }
                .padding(.top, 10)

                // Decorative divider between topic overview and conversation history.
                HStack {
                    Rectangle().fill(AquinasTheme.Colors.brownBorder).frame(height: 1)
                    Image("cross-1")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundColor(AquinasTheme.Colors.accent)
                    Rectangle().fill(AquinasTheme.Colors.brownBorder).frame(height: 1)
                }
                .padding(.vertical, 20)

                // Open conversation history. Replace dummy cards when real persistence arrives.
                VStack(spacing: 16) {
                    HStack {
                        Text("Open Conversations:")
                            .font(.figtreeHeading1)
                            .foregroundColor(brandDarkText)

                        Spacer()

                        Button(action: {}) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .sfSymbolDrawOn()
                                Text("New Conversation")
                            }
                            .font(.figtreeHeading2)
                            .foregroundColor(brandGreen)
                        }
                    }
                    .padding(.bottom, 8)

                    HistoryCard(
                        title: "The Ethics of Deception",
                        time: "5 Minutes Ago",
                        preview: "In some cases, people argue that lies can serve a greater good, especially when they protect someone's feelings. T..."
                    )

                    HistoryCard(
                        title: "Truth vs. White Lies",
                        time: "10 Minutes Ago",
                        preview: "I say, any lie no matter how seemingly insignificant is inherently avirtuous. The act itself, regardless of intention..."
                    )

                    HistoryCard(
                        title: "The Role of Honesty in Relation...",
                        time: "20 Minutes Ago",
                        preview: "Honesty is paramount in relationships, yet many struggle with the balance between truth and tact. The main indica..."
                    )
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 100)
        }
        .sheet(item: $activeWordLookup) { concept in
            ConceptSheetContent(concept: concept, collectedDefinitions: $collectedDefinitions)
                .presentationDetents([.fraction(0.45)])
                .presentationDragIndicator(.visible)
        }
        .scrollIndicators(.hidden)
        .onChange(of: selectedPersonality) { oldValue, newValue in
            personalityIconDrawID = UUID()
        }
    }

    // Shared bookshelf heading/body brown.
    var brandDarkText: Color {
        AquinasTheme.Colors.primaryReadable
    }
}

// MARK: - Conversation History Card

struct HistoryCard: View {
    let title: String
    let time: String
    let preview: String

    let brandDarkText = AquinasTheme.Colors.primaryReadable
    let mutedText = AquinasTheme.Colors.paragraphText

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.figtreeHeading2)
                    .foregroundColor(brandDarkText)
                    .lineLimit(1)

                Spacer()

                Text(time)
                    .font(.figtreeParagraph)
                    .foregroundColor(AquinasTheme.Colors.paragraphText)
            }

            Text(preview)
                .font(.figtreeParagraph)
                .foregroundColor(mutedText)
                .lineSpacing(4)
                .lineLimit(2)
        }
        .padding(20)
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: AquinasTheme.Spacing.smallCardRadius))
    }
}
