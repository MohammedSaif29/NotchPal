// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Notes: a scratchpad that's always one hover away. Saved automatically.
struct NotesTab: View {
    let app: AppModel
    @Bindable private var notes: NotesStore

    init(app: AppModel) {
        self.app = app
        _notes = Bindable(wrappedValue: app.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $notes.text)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down…")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            HStack(spacing: 8) {
                Text("\(notes.text.count) characters · saved automatically")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                SmallButton(title: "Copy", symbol: "doc.on.doc") { notes.copyAll() }
                SmallButton(title: "Clear", symbol: "trash") { notes.clear() }
            }
        }
    }
}

struct SmallButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}
