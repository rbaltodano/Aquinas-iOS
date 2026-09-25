//
//  SideMenuStudyTopicPicker.swift
//  Aquinas-iOS
//

import SwiftUI

struct SideMenuStudyTopicPickerSheet: View {
    let conversation: InquiryConversation
    var onSelectTopic: (StudyTopic) -> Void
    var onRemoveTopic: () -> Void = {}

    @State private var searchText = ""
    @State private var topics: [StudyTopic] = []
    @State private var selectedTopicID: UUID?
    @State private var isShowingNewTopicSheet = false

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredTopics: [StudyTopic] {
        topics.filter { topic in
            guard !normalizedSearchText.isEmpty else { return true }
            return [displayTitle(for: topic), topic.description]
                .joined(separator: " ")
                .lowercased()
                .contains(normalizedSearchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Add to Study Topic")
                    .font(.custom("LibreBaskerville-Regular", size: 24))
                    .foregroundColor(AquinasTheme.Colors.primaryReadable)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 56)

                Text(conversation.title)
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)

                StudyTopicsSearchField(searchText: $searchText)
                    .padding(.top, 24)

                if topics.isEmpty {
                    // No topics exist at all — the dashed "Add New Study Topic" button below covers it.
                    Text("No study topics yet.")
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if filteredTopics.isEmpty {
                    Text("No matching study topics.")
                        .font(.custom("Figtree-Regular", size: 14))
                        .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredTopics) { topic in
                            SideMenuStudyTopicPickerCard(
                                topic: topic,
                                isSelected: topic.id == selectedTopicID,
                                onSelect: { toggleSelection(of: topic) }
                            )
                        }
                    }
                    .padding(.top, 32)
                }

                Button(action: { isShowingNewTopicSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .sfSymbolDrawOn()
                        Text("Add New Study Topic")
                            .font(.custom("Figtree-Regular", size: 14))
                    }
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                AquinasTheme.Colors.darkText.opacity(0.15),
                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 24)

                Color.clear.frame(height: 32)
            }
            .padding(.horizontal, 24)
        }
        .background(AquinasTheme.Colors.canvas)
        .onAppear {
            topics = StudyTopicStore.load()
            selectedTopicID = conversation.studyTopicID
        }
        .sheet(isPresented: $isShowingNewTopicSheet) {
            NewStudyTopicSheet(onCreate: createAndSelectStudyTopic)
        }
    }

    private func toggleSelection(of topic: StudyTopic) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            if selectedTopicID == topic.id {
                selectedTopicID = nil
                onRemoveTopic()
            } else {
                selectedTopicID = topic.id
                onSelectTopic(topic)
            }
        }
    }

    private func createAndSelectStudyTopic(title: String, description: String) {
        let topic = StudyTopic(title: title, description: description)
        topics.insert(topic, at: 0)
        StudyTopicStore.save(topics)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            selectedTopicID = topic.id
        }
        onSelectTopic(topic)
    }

    private func displayTitle(for topic: StudyTopic) -> String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }
}

private struct SideMenuStudyTopicPickerCard: View {
    let topic: StudyTopic
    var isSelected: Bool = false
    var onSelect: () -> Void

    private var displayTitle: String {
        let trimmed = topic.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Study Topic" : trimmed
    }

    private var displayDescription: String {
        topic.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(displayTitle)
                .font(.custom("LibreBaskerville-Regular", size: 18))
                .foregroundColor(AquinasTheme.Colors.primaryReadable)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !displayDescription.isEmpty {
                Text(displayDescription)
                    .font(.custom("Figtree-Regular", size: 14))
                    .foregroundColor(AquinasTheme.Colors.paragraphText.opacity(0.75))
                    .lineSpacing(4)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquinasTheme.Colors.componentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? AquinasTheme.Colors.lightGreen : AquinasTheme.Colors.controlBorder, lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AquinasTheme.Colors.lightGreen)
                    .background(AquinasTheme.Colors.componentBackground, in: Circle())
                    .padding(12)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}
