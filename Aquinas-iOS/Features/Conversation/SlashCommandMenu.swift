//
//  SlashCommandMenu.swift
//  Aquinas-iOS
//
//  Slash-command picker shown when the user types "/" in the chat input.
//  Mirrors the Figma "personality-selector-light-mode" card (node 553:599):
//  a "Commands" heading over a vertical list of command names on the
//  Canvas Secondary card, tappable to insert the command into the input.
//

import Combine
import SwiftUI

/// Live text the user is typing in the composer, mirrored into the picker's header so
/// "/usertext" tracks the field behind the popup. Held as a reference type and observed
/// only by the picker, so per-keystroke updates never re-render the conversation tree.
final class SlashCommandQuery: ObservableObject {
    @Published var text: String = ""
}

/// A single slash command. `name` includes the leading slash (e.g. "/compact").
/// `description` is supporting copy for accessibility / a future two-line layout —
/// the Figma design lists names only, so it isn't rendered in the default card.
struct SlashCommand: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var description: String = ""
}

enum SlashCommandInvocation: Equatable {
    case compact
    case clear
}

extension SlashCommand {
    /// Commands currently supported by the conversation runtime.
    static let all: [SlashCommand] = [
        SlashCommand(name: "/compact",    description: "Condense the conversation so far"),
        SlashCommand(name: "/clear",      description: "Clear the current conversation"),
    ]

    static func invocation(for text: String) -> SlashCommandInvocation? {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "/compact":
            return .compact
        case "/clear":
            return .clear
        default:
            return nil
        }
    }
}

/// The slash-command picker card. Matches the Figma card exactly (24pt padding,
/// 24pt corner radius, 16pt gap, Figtree Bold 18 heading / SemiBold 14 rows in the
/// paragraph-text color on the Canvas Secondary background with the brown border).
///
/// Pass `maxHeight` to cap the list and let it scroll when it has more commands than fit;
/// leave it `nil` to hug the content (as the Figma frame does).
struct SlashCommandMenu: View {
    @ObservedObject var query: SlashCommandQuery
    var commands: [SlashCommand] = SlashCommand.all
    var maxHeight: CGFloat? = nil
    var onSelect: (SlashCommand) -> Void

    /// 14pt row text at the design's 1.5 line-height → a 21pt line box per row.
    private var rowLineBox: CGFloat { 14 * 1.5 }

    /// Commands whose name matches the typed "/token" (prefix match). A bare "/" shows all.
    private var suggestions: [SlashCommand] {
        let q = query.text.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count > 1 else { return commands }
        return commands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    var body: some View {
        commandList
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxHeight)
        .background(AquinasTheme.Colors.canvasSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AquinasTheme.Colors.canvasSecondary, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var commandList: some View {
        if maxHeight != nil {
            ScrollView {
                rows
            }
            .scrollBounceBehavior(.basedOnSize)
            // Bottom fade hints there's more to scroll — fades into the card's canvas color.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        AquinasTheme.Colors.canvasSecondary.opacity(0),
                        AquinasTheme.Colors.canvasSecondary,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 36)
                .allowsHitTesting(false)
            }
        } else {
            rows
        }
    }

    private var rows: some View {
        // No inter-row spacing: the 1.5 line-height box already supplies the rhythm
        // the design shows (leading-[1.5], mb-0 between rows).
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { command in
                Button {
                    onSelect(command)
                } label: {
                    Text(command.name)
                        .font(.custom("Figtree-SemiBold", size: 14))
                        .foregroundColor(AquinasTheme.Colors.placeholderText)
                        .frame(maxWidth: .infinity, minHeight: rowLineBox, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(command.name)
                .accessibilityHint(command.description)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: suggestions)
    }
}

#Preview("Slash Command Menu") {
    ZStack {
        AquinasTheme.Colors.canvas.ignoresSafeArea()
        SlashCommandMenu(query: {
            let q = SlashCommandQuery()
            q.text = "/comp"
            return q
        }(), maxHeight: 186) { command in
            print("Selected \(command.name)")
        }
        .frame(width: 300)
        .padding()
    }
}
