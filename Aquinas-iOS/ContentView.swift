//  Aquinas-iOS
//
//  Created by Ryan on 4/11/26.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

// MARK: - Shared Models

/// File/image selected before submitting a question.
struct UploadedFile: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let name: String
    let imageData: Data?
    let rotationDegrees: Double

    init(id: UUID = UUID(), name: String, imageData: Data?, rotationDegrees: Double) {
        self.id = id
        self.name = name
        self.imageData = imageData
        self.rotationDegrees = rotationDegrees
    }

    static func == (lhs: UploadedFile, rhs: UploadedFile) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ConceptDefinition: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    let word: String
    let partOfSpeech: String
    let pronunciation: String
    let meaning: String
    let example: String

    init(
        id: UUID = UUID(),
        word: String,
        partOfSpeech: String,
        pronunciation: String,
        meaning: String,
        example: String
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.pronunciation = pronunciation
        self.meaning = meaning
        self.example = example
    }
}

enum AppPage: Equatable {
    case conversation
    case insights
}

// MARK: - App Shell

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var questionText: String = ""
    @State private var isAtBottom: Bool = false
    @State private var sheetOffset: CGFloat = 0
    @State private var isAtTop: Bool = true
    @FocusState private var isKeyboardVisible: Bool
    @State private var uploadedFiles: [UploadedFile] = []
    @State private var showFilePicker: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera: Bool = false
    @State private var collectedDefinitions: [ConceptDefinition] = []
    @State private var activePage: AppPage = .conversation
    @State private var isGlobalSideMenuOpen: Bool = false
    @State private var sideMenuConversations: [InquiryConversation] = []
    @State private var sideMenuActiveConversationID: UUID? = nil
    @State private var sideMenuCurrentTitle: String = "New Conversation"
    @State private var requestedConversationID: UUID? = nil
    @State private var newConversationRequest: Int = 0
    @State private var colorSchemeOverride: ColorScheme? = nil


    let canvasColor = AquinasTheme.Colors.canvas

    var body: some View {
        GeometryReader { geo in
            let snapUpPosition = -geo.size.height + 75

            // Root stack: bookshelf sits behind the active inquiry surface.
            ZStack(alignment: .top) {

                // Layer 1: saved insights, history, and the current topic overview.
                BookshelfView(
                    isAtTop: $isAtTop,
                    showFilePicker: $showFilePicker,
                    collectedDefinitions: $collectedDefinitions
                )
                .background(canvasColor)
                .ignoresSafeArea()

                // Layer 2: routed app pages.
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        switch activePage {
                        case .conversation:
                            ActiveInquiryView(
                                activePage: $activePage,
                                sideMenuConversations: $sideMenuConversations,
                                sideMenuActiveConversationID: $sideMenuActiveConversationID,
                                sideMenuCurrentTitle: $sideMenuCurrentTitle,
                                requestedConversationID: $requestedConversationID,
                                newConversationRequest: $newConversationRequest,
                                colorSchemeOverride: $colorSchemeOverride,
                                isAtBottom: $isAtBottom,
                                showFilePicker: $showFilePicker,
                                showPhotoPicker: $showPhotoPicker,
                                showCamera: $showCamera,
                                questionText: $questionText,
                                uploadedFiles: $uploadedFiles,
                                collectedDefinitions: $collectedDefinitions
                            )
                        case .insights:
                            InsightTreeView(insights: collectedDefinitions)
                                .background(canvasColor)
                                .ignoresSafeArea()
                        }
                    }
                    .background(AquinasTheme.Colors.activeInquiryChrome)
                }
                .overlay(alignment: .topLeading) {
                    if activePage == .insights && !isGlobalSideMenuOpen {
                        SideMenuTriggerButton {
                            isKeyboardVisible = false
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                isGlobalSideMenuOpen = true
                            }
                        }
                        .padding(.leading, 24)
                        .padding(.top, 24)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
                .overlay {
                    if activePage == .insights && isGlobalSideMenuOpen {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            }
                            .transition(.opacity)
                            .zIndex(3)
                    }
                }
                .overlay(alignment: .leading) {
                    if activePage == .insights {
                        AquinasSideMenu(
                            currentTitle: sideMenuCurrentTitle,
                            conversations: sideMenuConversations,
                            activeConversationID: sideMenuActiveConversationID,
                            selectedPersonality: "Friendly",
                            isPresented: isGlobalSideMenuOpen,
                            isDarkMode: colorSchemeOverride.map { $0 == .dark } ?? (colorScheme == .dark),
                            onNewChat: {
                                newConversationRequest += 1
                                activePage = .conversation
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onSelectConversation: { conversation in
                                requestedConversationID = conversation.id
                                activePage = .conversation
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onRenameConversation: { _ in },
                            onPinConversation: { _ in },
                            onDeleteConversation: { _ in },
                            onOpenInsights: {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            },
                            onToggleColorScheme: toggleColorScheme,
                            onClose: {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                                    isGlobalSideMenuOpen = false
                                }
                            }
                        )
                        .frame(width: 325)
                        .offset(x: isGlobalSideMenuOpen ? 0 : -345)
                        .opacity(isGlobalSideMenuOpen ? 1 : 0.96)
                        .zIndex(4)
                        .animation(.spring(response: 0.42, dampingFraction: 0.84), value: isGlobalSideMenuOpen)
                    }
                }

                // Shared document picker used by the bottom plus button.
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.image, .pdf, .audio, .plainText],
                    allowsMultipleSelection: true
                ) { result in
                    switch result {
                    case .success(let urls):
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            for url in urls {
                                let hasAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if hasAccess {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }

                                let data = try? Data(contentsOf: url)
                                let imageData = data.flatMap { UIImage(data: $0) == nil ? nil : $0 }

                                uploadedFiles.append(
                                    UploadedFile(
                                        name: url.lastPathComponent,
                                        imageData: imageData,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    case .failure(let error):
                        print("Failed to select file: \(error.localizedDescription)")
                    }
                }
                // Shared photo picker used by the attachment menu.
                .photosPicker(
                    isPresented: $showPhotoPicker,
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 8,
                    matching: .images
                )
                .onChange(of: selectedPhotoItems) { oldValue, newValue in
                    guard !newValue.isEmpty else { return }

                    Task {
                        for item in newValue {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               UIImage(data: data) != nil {
                                await MainActor.run {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        uploadedFiles.append(
                                            UploadedFile(
                                                name: "Photo",
                                                imageData: data,
                                                rotationDegrees: Double.random(in: -5...5)
                                            )
                                        )
                                    }
                                }
                            }
                        }

                        await MainActor.run {
                            selectedPhotoItems.removeAll()
                        }
                    }
                }
                // Camera capture flow. Falls back gracefully if a camera is unavailable.
                .fullScreenCover(isPresented: $showCamera) {
                    CameraCaptureView { image in
                        if let data = image.jpegData(compressionQuality: 0.86) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                uploadedFiles.append(
                                    UploadedFile(
                                        name: "Camera Photo",
                                        imageData: data,
                                        rotationDegrees: Double.random(in: -5...5)
                                    )
                                )
                            }
                        }
                    }
                    .ignoresSafeArea()
                }

                // Bookshelf sheet physics. Drag from the bottom handle to open; drag from the top handle to close.
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            let grabbedTopHandle = sheetOffset < 0 && value.startLocation.y < 150
                            let grabbedBottomHandle = sheetOffset == 0 && value.startLocation.y > (geo.size.height - 150)

                            if grabbedBottomHandle && sheetOffset == 0 && value.translation.height < 0 {
                                sheetOffset = value.translation.height * 0.85
                            }
                            else if grabbedTopHandle && sheetOffset < 0 && value.translation.height > 0 {
                                let newOffset = snapUpPosition + (value.translation.height * 0.85)
                                sheetOffset = min(newOffset, 0)
                            }
                        }
                        .onEnded { value in
                            let startedNearTopHandle = value.startLocation.y < 150
                            let startedNearBottomHandle = value.startLocation.y > (geo.size.height - 150)
                            let startedOnSheetHandle = startedNearTopHandle || startedNearBottomHandle
                            guard startedOnSheetHandle || sheetOffset != 0 else { return }

                            let isSwipingUp = startedNearBottomHandle && value.translation.height < -50
                            let isSwipingDown = startedNearTopHandle && value.translation.height > 50

                            if isSwipingUp {
                                isKeyboardVisible = false
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + (isSwipingUp ? 0.05 : 0)) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    if isSwipingUp {
                                        sheetOffset = snapUpPosition
                                    } else if isSwipingDown {
                                        sheetOffset = 0
                                    } else {
                                        sheetOffset = sheetOffset < (snapUpPosition / 2) ? snapUpPosition : 0
                                    }
                                }
                            }
                        }
                )

            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .preferredColorScheme(colorSchemeOverride)
        .onAppear {
            let savedInsights = InsightLibraryStore.load()
            if !savedInsights.isEmpty {
                collectedDefinitions = savedInsights
            }
        }
        .onChange(of: collectedDefinitions) { oldValue, newValue in
            InsightLibraryStore.save(newValue)
        }
    }

    private func toggleColorScheme() {
        let currentIsDark = colorSchemeOverride.map { $0 == .dark } ?? (colorScheme == .dark)
        colorSchemeOverride = currentIsDark ? .light : .dark
    }
}

// MARK: - Camera Capture

struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

// MARK: - Legacy Floating Model Controls

/// Older standalone toolbar kept for reference. The active dock now lives in ActiveInquiry.swift.
struct ModelControlsToolbar: View {
    @Binding var showFilePicker: Bool
    @Binding var isThinking: Bool
    @Binding var personality: String

    // Controls the visibility of the jump-to-bottom button.
    @Binding var isAtBottom: Bool
    var onScrollToBottom: () -> Void

    let brandGreen = AquinasTheme.Colors.secondaryMuted

    var body: some View {
        HStack(spacing: 12) {

            // Attachment button.
            Button(action: { showFilePicker = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .sfSymbolDrawOn()
                    .aquinasIconControl()
            }

            // Thinking toggle.
            Button(action: { isThinking.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .sfSymbolDrawOn()
                    Text("Thinking")
                        .font(.system(size: 15, weight: .medium))
                }
                .padding(.horizontal, 16)
                .aquinasCapsuleControl(isSelected: isThinking)
            }

            // Personality toggle.
            Button(action: {
                personality = personality == "Friendly" ? "Scholarly" : "Friendly"
            }) {
                HStack(spacing: 8) {
                    Image(systemName: personality == "Friendly" ? "brain.head.profile.fill" : "book.pages.fill")
                        .sfSymbolDrawOn()
                    Text(personality)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .sfSymbolDrawOn()
                }
                .padding(.horizontal, 16)
                .aquinasCapsuleControl()
            }

            Spacer()

            // Scroll-to-bottom appears only when needed.
            if !isAtBottom {
                Button(action: {
                    onScrollToBottom()
                }) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .bold))
                        .sfSymbolDrawOn()
                        .aquinasIconControl(isPrimary: true)
                        .shadow(color: AquinasTheme.Colors.floatingShadow, radius: 4, y: 2)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isAtBottom)
    }
}

#Preview {
    ContentView()
}
