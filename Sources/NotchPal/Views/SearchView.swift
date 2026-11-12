// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// Apple Intelligence's colours, used for Siri and AI answers.
enum IntelligenceColors {
    static let all: [Color] = [
        Color(red: 0.35, green: 0.78, blue: 1.0),
        Color(red: 0.55, green: 0.45, blue: 1.0),
        Color(red: 1.0, green: 0.42, blue: 0.75),
        Color(red: 1.0, green: 0.6, blue: 0.3),
        Color(red: 0.35, green: 0.78, blue: 1.0),
    ]
}

/// A small Siri-style orb.
struct SiriOrb: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: IntelligenceColors.all, center: .center))
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: size * 0.42))
                .blendMode(.plusLighter)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.6, green: 0.45, blue: 1).opacity(0.6), radius: 3)
    }
}

/// The notch opened into a search bar, like Spotlight in Apple's island.
struct SearchView: View {
    let app: AppModel
    /// Floating below the notch, so it starts at the top instead of under the camera.
    var floating = false

    var body: some View {
        let search = app.search
        VStack(spacing: 8) {
            Color.clear.frame(height: floating ? 2 : max(app.state.notch.height - 4, 18))
            bar(search)
            if search.showingAnswer {
                AnswerView(app: app)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else if !search.results.isEmpty {
                ResultsList(app: app)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: search.showingAnswer)
    }

    private func bar(_ search: SearchService) -> some View {
        HStack(spacing: 10) {
            Image(systemName: search.showingAnswer ? "sparkles" : "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(search.showingAnswer
                    ? AnyShapeStyle(LinearGradient(colors: IntelligenceColors.all, startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.white.opacity(0.6)))
                .frame(width: 20)
            SearchField(search: search)
                .frame(height: 24)
            Button {
                app.closeSearch()
                app.askSiri()
            } label: {
                SiriOrb(size: 20)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("Ask Siri")
        }
        .padding(.horizontal, 12)
        .frame(height: SearchService.barHeight - 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.09)))
    }
}

/// The text box. A plain AppKit field, so arrow keys, Return and Esc can drive the results.
struct SearchField: NSViewRepresentable {
    let search: SearchService

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16, weight: .medium)
        field.textColor = .white
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != search.query {
            field.stringValue = search.query
        }
        let placeholder = search.showingAnswer ? "Ask a follow-up…" : "Search apps, files and settings, or ask anything"
        if context.coordinator.placeholder != placeholder {
            context.coordinator.placeholder = placeholder
            field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.38),
                .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            ])
        }
        if field.window != nil, field.currentEditor() == nil {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(search: search)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let search: SearchService
        var placeholder = ""

        init(search: SearchService) {
            self.search = search
        }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            search.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                search.move(-1)
            case #selector(NSResponder.moveDown(_:)):
                search.move(1)
            case #selector(NSResponder.insertNewline(_:)):
                search.activateSelection()
            case #selector(NSResponder.cancelOperation(_:)):
                search.escape()
            default:
                return false
            }
            return true
        }
    }
}

private struct ResultsList: View {
    let app: AppModel

    var body: some View {
        let search = app.search
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(search.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, selected: index == search.selection, accent: app.accent)
                            .id(result.id)
                            .onTapGesture { search.run(result) }
                            .onHover { inside in
                                if inside { search.select(result) }
                            }
                    }
                }
            }
            .frame(height: CGFloat(min(search.results.count, SearchService.visibleRows)) * SearchService.rowHeight)
            .onChange(of: search.selection) { _, newValue in
                guard search.results.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(search.results[newValue].id)
                }
            }
        }
    }
}

private struct ResultRow: View {
    let result: SearchResult
    let selected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SearchService.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? accent.opacity(0.32) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        switch result.kind {
        case .app, .file:
            if let path = result.path {
                Image(nsImage: FileIcons.icon(for: path))
                    .resizable()
                    .interpolation(.high)
            }
        case .ai:
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: IntelligenceColors.all, startPoint: .topLeading, endPoint: .bottomTrailing))
        case .siri:
            SiriOrb(size: 20)
        default:
            Image(systemName: result.symbol ?? "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white.opacity(0.1)))
        }
    }
}

/// File and app icons, remembered so scrolling stays smooth.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        if cache.count > 300 { cache.removeAll() }
        cache[path] = icon
        return icon
    }
}

/// Apple Intelligence's answer, typed out inside the notch.
private struct AnswerView: View {
    let app: AppModel

    var body: some View {
        let search = app.search
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Apple Intelligence")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: IntelligenceColors.all, startPoint: .leading, endPoint: .trailing))
                Text(search.question ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if !search.answering && search.answerError == nil {
                    small("Copy", "doc.on.doc") { search.copyAnswer() }
                }
                small("Claude", "arrow.up.right") { search.askClaudeInstead() }
            }
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    if let error = search.answerError {
                        Text(error).foregroundStyle(.orange)
                    } else if search.answering && search.shownAnswer.isEmpty {
                        ThinkingDots()
                    } else {
                        Text(search.shownAnswer)
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 112)
            Text("Type a follow-up and press Return. Esc goes back.")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
    }

    private func small(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Three dots in Apple Intelligence's colours while it thinks.
private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(IntelligenceColors.all[index + 1])
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.6 + 0.4 * (0.5 + 0.5 * sin(t * 6 - Double(index) * 0.9)))
                }
                Text("Thinking…")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
