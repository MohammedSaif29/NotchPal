// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One line in the search results.
struct SearchResult: Identifiable, Equatable {
    enum Kind: Equatable {
        case ai, command, math, app, setting, file, siri, web, claude, chatgpt
    }

    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    /// An SF Symbol, when there's no app or file icon.
    var symbol: String?
    /// An app or file, for its icon.
    var path: String?
    let action: SearchAction
}

enum SearchAction: Equatable {
    case askAI(String)
    case openURL(URL)
    case openPath(String)
    case startTimer(minutes: Double)
    case addNote(String)
    case playPause
    case nextTrack
    case previousTrack
    case copy(String)
    case siri
}

/// Search in the notch, like Spotlight in Apple's Dynamic Island: apps, files, System Settings,
/// a calculator, quick commands, the web, and questions for Apple Intelligence, Siri, Claude or
/// ChatGPT.
@MainActor
@Observable
final class SearchService {
    var query = "" {
        didSet { if query != oldValue { update() } }
    }
    private(set) var results: [SearchResult] = []
    private(set) var selection = 0

    /// Apple Intelligence's answer, shown in place of the results.
    private(set) var question: String?
    private(set) var shownAnswer = ""
    private(set) var answering = false
    private(set) var answerError: String?

    var showingAnswer: Bool { question != nil }

    @ObservationIgnored weak var app: AppModel?
    @ObservationIgnored private var apps: [(name: String, path: String)] = []
    @ObservationIgnored private var loadingApps = false
    @ObservationIgnored private var files: [String] = []
    @ObservationIgnored private var fileQuery: NSMetadataQuery?
    @ObservationIgnored private var fileObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var fileWork: DispatchWorkItem?
    @ObservationIgnored private var fullAnswer = ""
    @ObservationIgnored private var revealTask: Task<Void, Never>?
    @ObservationIgnored private var session: AnyObject?

    /// Rows shown at once before the list scrolls.
    static let visibleRows = 6
    static let rowHeight: CGFloat = 34
    static let barHeight: CGFloat = 44

    /// How tall the island's search area is right now.
    var bodyHeight: CGFloat {
        if showingAnswer { return Self.barHeight + 168 }
        let rows = min(results.count, Self.visibleRows)
        return Self.barHeight + (rows > 0 ? CGFloat(rows) * Self.rowHeight + 10 : 0)
    }

    // MARK: Opening and closing

    func reset() {
        query = ""
        results = []
        selection = 0
        clearAnswer()
        loadAppsIfNeeded()
    }

    func clearAnswer() {
        revealTask?.cancel()
        question = nil
        shownAnswer = ""
        fullAnswer = ""
        answering = false
        answerError = nil
        session = nil
    }

    /// Esc: back from an answer to the results, or close search.
    func escape() {
        if showingAnswer {
            clearAnswer()
            update()
        } else {
            app?.closeSearch()
        }
    }

    // MARK: Results

    func move(_ step: Int) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    func select(_ result: SearchResult) {
        if let index = results.firstIndex(of: result) { selection = index }
    }

    /// Return: open the selected result. While an answer is showing, Return asks a follow-up.
    func activateSelection() {
        if showingAnswer {
            let followUp = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !followUp.isEmpty, !answering { ask(followUp, followUp: true) }
            return
        }
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    func run(_ result: SearchResult) {
        guard let app else { return }
        switch result.action {
        case .askAI(let text):
            ask(text, followUp: false)
            return
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .openPath(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .startTimer(let minutes):
            app.timer.start(minutes: minutes)
        case .addNote(let text):
            let notes = app.notes.text
            app.notes.text = notes.isEmpty ? text : notes + "\n" + text
        case .playPause:
            app.nowPlaying.togglePlayPause()
        case .nextTrack:
            app.nowPlaying.next()
        case .previousTrack:
            app.nowPlaying.previous()
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .siri:
            app.closeSearch()
            app.askSiri()
            return
        }
        app.closeSearch()
    }

    private func update() {
        if showingAnswer { return } // Typing under an answer is a follow-up question.
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleFileSearch(text)
        guard !text.isEmpty else {
            results = []
            selection = 0
            return
        }
        var list: [SearchResult] = []
        let aiReady = (app?.settings.aiAnswers ?? true) && AppleIntelligence.isAvailable
        let question = Self.looksLikeQuestion(text)

        list += commands(for: text)
        if let value = Calculator.evaluate(text) {
            let shown = Calculator.format(value)
            list.append(SearchResult(id: "math", kind: .math, title: "= \(shown)", subtitle: "Press Return to copy",
                                     symbol: "plusminus", action: .copy(shown)))
        }
        if aiReady && question { list.append(aiRow(text)) }
        list += matchingApps(text).prefix(question ? 2 : 5)
        list += matchingSettings(text).prefix(2)
        list += files.prefix(question ? 2 : 4).map { path in
            SearchResult(id: "file-\(path)", kind: .file, title: FileManager.default.displayName(atPath: path),
                         subtitle: Self.shortPath(path), path: path, action: .openPath(path))
        }
        if aiReady && !question && text.count >= 3 { list.append(aiRow(text)) }
        list.append(SearchResult(id: "siri", kind: .siri, title: "Ask Siri", subtitle: "Opens Siri",
                                 action: .siri))
        list.append(SearchResult(id: "web", kind: .web, title: "Search the web for “\(text)”", subtitle: "Google",
                                 symbol: "globe", action: .openURL(Self.url("https://www.google.com/search", "q", text))))
        list.append(SearchResult(id: "claude", kind: .claude, title: "Ask Claude", subtitle: text,
                                 symbol: "sparkle", action: .openURL(Self.url("https://claude.ai/new", "q", text))))
        list.append(SearchResult(id: "chatgpt", kind: .chatgpt, title: "Ask ChatGPT", subtitle: text,
                                 symbol: "bubble.left.and.text.bubble.right", action: .openURL(Self.url("https://chatgpt.com/", "q", text))))

        let previous = results.indices.contains(selection) ? results[selection].id : nil
        results = list
        selection = list.firstIndex { $0.id == previous } ?? 0
        if previous == nil || list.first?.kind == .command || list.first?.kind == .math { selection = 0 }
    }

    private func aiRow(_ text: String) -> SearchResult {
        SearchResult(id: "ai", kind: .ai, title: "Ask Apple Intelligence", subtitle: text, action: .askAI(text))
    }

    /// "timer 10m", "note buy milk", "pause", "next".
    private func commands(for text: String) -> [SearchResult] {
        let lower = text.lowercased()
        var list: [SearchResult] = []
        if let minutes = Self.timerMinutes(lower) {
            let label = minutes < 1 ? "\(Int(minutes * 60)) seconds" : (minutes == 1 ? "1 minute" : "\(Self.trim(minutes)) minutes")
            list.append(SearchResult(id: "cmd-timer", kind: .command, title: "Start a \(label) timer",
                                     subtitle: "Timer", symbol: "timer", action: .startTimer(minutes: minutes)))
        }
        if lower.hasPrefix("note "), text.count > 5 {
            let note = String(text.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            list.append(SearchResult(id: "cmd-note", kind: .command, title: "Add to Notes: \(note)",
                                     subtitle: "Notes", symbol: "note.text.badge.plus", action: .addNote(note)))
        }
        if app?.nowPlaying.track != nil {
            switch lower {
            case "pause", "play", "play pause", "resume":
                list.append(SearchResult(id: "cmd-play", kind: .command, title: app?.nowPlaying.isPlaying == true ? "Pause music" : "Play music",
                                         subtitle: app?.nowPlaying.track?.title ?? "", symbol: "playpause.fill", action: .playPause))
            case "next", "skip", "next song":
                list.append(SearchResult(id: "cmd-next", kind: .command, title: "Next song", subtitle: "Music",
                                         symbol: "forward.fill", action: .nextTrack))
            case "previous", "prev", "back", "last song":
                list.append(SearchResult(id: "cmd-prev", kind: .command, title: "Previous song", subtitle: "Music",
                                         symbol: "backward.fill", action: .previousTrack))
            default:
                break
            }
        }
        return list
    }

    static func timerMinutes(_ text: String) -> Double? {
        let pattern = #"^(?:timer|t)\s+(\d+(?:\.\d+)?)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let number = Double(text[numberRange]), number > 0
        else { return nil }
        var unit = "m"
        if let unitRange = Range(match.range(at: 2), in: text) { unit = String(text[unitRange]) }
        switch unit.first {
        case "s": return number / 60
        case "h": return number * 60
        default: return number
        }
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: Apps

    private func loadAppsIfNeeded() {
        guard apps.isEmpty, !loadingApps else { return }
        loadingApps = true
        Task.detached(priority: .userInitiated) {
            let found = Self.findApps()
            await MainActor.run { [weak self] in
                self?.apps = found
                self?.loadingApps = false
                self?.update()
            }
        }
    }

    nonisolated private static func findApps() -> [(name: String, path: String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                       "/System/Applications/Utilities", home + "/Applications"]
        var seen: Set<String> = []
        var list: [(name: String, path: String)] = []
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for entry in names where entry.hasSuffix(".app") {
                let name = String(entry.dropLast(4))
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                list.append((name, folder + "/" + entry))
            }
        }
        return list
    }

    private func matchingApps(_ text: String) -> [SearchResult] {
        apps.compactMap { app -> (Double, SearchResult)? in
            guard let score = Self.score(app.name, text) else { return nil }
            return (score, SearchResult(id: "app-\(app.path)", kind: .app, title: app.name, subtitle: "Application",
                                        path: app.path, action: .openPath(app.path)))
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
    }

    /// How well a name matches what's typed: the start of the name beats the start of a word,
    /// which beats the initials ("vsc"), which beats anywhere in the name.
    static func score(_ name: String, _ text: String) -> Double? {
        let name = name.lowercased()
        let text = text.lowercased()
        let shortness = 1 / Double(max(name.count, 1))
        if name.hasPrefix(text) { return 100 + shortness }
        let words = name.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "." })
        if words.contains(where: { $0.hasPrefix(text) }) { return 80 + shortness }
        if text.count >= 2, String(words.compactMap(\.first)).hasPrefix(text) { return 70 + shortness }
        if text.count >= 2, name.contains(text) { return 50 + shortness }
        return nil
    }

    // MARK: System Settings

    private static let settingsPanes: [(name: String, keywords: String, id: String, symbol: String)] = [
        ("Wi-Fi", "wifi internet wireless", "com.apple.wifi-settings-extension", "wifi"),
        ("Bluetooth", "bluetooth airpods headphones", "com.apple.BluetoothSettings", "dot.radiowaves.left.and.right"),
        ("Network", "network ethernet vpn", "com.apple.Network-Settings.extension", "network"),
        ("Battery", "battery power energy charging", "com.apple.Battery-Settings.extension", "battery.100"),
        ("Displays", "display screen brightness resolution night shift", "com.apple.Displays-Settings.extension", "display"),
        ("Sound", "sound volume audio output input", "com.apple.Sound-Settings.extension", "speaker.wave.2.fill"),
        ("Focus", "focus do not disturb dnd", "com.apple.Focus-Settings.extension", "moon.fill"),
        ("Notifications", "notifications alerts", "com.apple.Notifications-Settings.extension", "bell.badge.fill"),
        ("Wallpaper", "wallpaper background desktop picture", "com.apple.Wallpaper-Settings.extension", "photo"),
        ("Appearance", "appearance dark mode light mode accent", "com.apple.Appearance-Settings.extension", "circle.lefthalf.filled"),
        ("Control Center", "control center menu bar", "com.apple.ControlCenter-Settings.extension", "switch.2"),
        ("Desktop & Dock", "dock desktop stage manager hot corners", "com.apple.Desktop-Settings.extension", "dock.rectangle"),
        ("Keyboard", "keyboard shortcuts input", "com.apple.Keyboard-Settings.extension", "keyboard"),
        ("Trackpad", "trackpad gestures", "com.apple.Trackpad-Settings.extension", "rectangle.and.hand.point.up.left"),
        ("Privacy & Security", "privacy security permissions accessibility camera microphone", "com.apple.settings.PrivacySecurity.extension", "hand.raised.fill"),
        ("Software Update", "software update upgrade macos", "com.apple.Software-Update-Settings.extension", "arrow.triangle.2.circlepath"),
        ("Apple Intelligence & Siri", "siri apple intelligence ai", "com.apple.Siri-Settings.extension", "sparkles"),
        ("Accessibility", "accessibility zoom voiceover reduce motion", "com.apple.Accessibility-Settings.extension", "accessibility"),
        ("Screen Time", "screen time limits", "com.apple.Screen-Time-Settings.extension", "hourglass"),
        ("Lock Screen", "lock screen screensaver sleep", "com.apple.Lock-Screen-Settings.extension", "lock.fill"),
    ]

    private func matchingSettings(_ text: String) -> [SearchResult] {
        let lower = text.lowercased()
        guard lower.count >= 2 else { return [] }
        return Self.settingsPanes.compactMap { pane in
            let hit = Self.score(pane.name, lower) != nil
                || pane.keywords.split(separator: " ").contains { $0.hasPrefix(lower) }
            guard hit, let url = URL(string: "x-apple.systempreferences:\(pane.id)") else { return nil }
            return SearchResult(id: "set-\(pane.id)", kind: .setting, title: pane.name, subtitle: "System Settings",
                                symbol: pane.symbol, action: .openURL(url))
        }
    }

    // MARK: Files

    /// Spotlight's own index, so it's quick. Waits a moment after typing stops.
    private func scheduleFileSearch(_ text: String) {
        fileWork?.cancel()
        guard text.count >= 2, Calculator.evaluate(text) == nil else {
            stopFileQuery()
            files = []
            return
        }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.startFileQuery(text) }
        }
        fileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func startFileQuery(_ text: String) {
        stopFileQuery()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@ AND NOT (%K == %@)",
                                      NSMetadataItemFSNameKey, text,
                                      "kMDItemContentType", "com.apple.application-bundle")
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        let center = NotificationCenter.default
        fileObservers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.filesFound(query) }
        })
        fileQuery = query
        query.start()
    }

    private func filesFound(_ query: NSMetadataQuery) {
        query.disableUpdates()
        var paths: [String] = []
        for index in 0..<min(query.resultCount, 12) {
            if let item = query.result(at: index) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
               !path.contains("/Library/"), !path.contains("/."), !path.hasSuffix(".app") {
                paths.append(path)
            }
        }
        stopFileQuery()
        files = paths
        update()
    }

    private func stopFileQuery() {
        fileQuery?.stop()
        fileQuery = nil
        fileObservers.forEach { NotificationCenter.default.removeObserver($0) }
        fileObservers = []
    }

    private static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folder = (path as NSString).deletingLastPathComponent
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }

    // MARK: Apple Intelligence

    /// Asks Apple Intelligence on this Mac. Follow-ups continue the same conversation.
    func ask(_ text: String, followUp: Bool) {
        if !followUp { session = nil }
        question = text
        query = ""
        shownAnswer = ""
        fullAnswer = ""
        answerError = nil
        answering = true
        revealTask?.cancel()
        Task { @MainActor in
            do {
                let (reply, newSession) = try await AppleIntelligence.ask(text, session: session)
                guard question == text else { return }
                session = newSession
                fullAnswer = reply
                answering = false
                reveal()
            } catch {
                guard question == text else { return }
                answering = false
                answerError = (error as? AppleIntelligence.Failure)?.message
                    ?? "Apple Intelligence couldn't answer that. Try asking another way."
            }
        }
    }

    /// The answer types itself out, a few characters at a time.
    private func reveal() {
        revealTask?.cancel()
        let full = fullAnswer
        revealTask = Task { @MainActor in
            var count = 0
            while count < full.count {
                count = min(full.count, count + 4)
                shownAnswer = String(full.prefix(count))
                try? await Task.sleep(nanoseconds: 12_000_000)
                if Task.isCancelled { return }
            }
        }
    }

    func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullAnswer, forType: .string)
    }

    func askClaudeInstead() {
        guard let question else { return }
        NSWorkspace.shared.open(Self.url("https://claude.ai/new", "q", question))
        app?.closeSearch()
    }

    // MARK: Helpers

    static func url(_ base: String, _ name: String, _ value: String) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: name, value: value)]
        return components.url!
    }

    static func looksLikeQuestion(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.hasSuffix("?") { return true }
        guard lower.split(separator: " ").count >= 3 else { return false }
        let starters = ["what", "why", "how", "who", "when", "where", "which", "explain", "write", "tell me",
                        "can you", "could you", "should", "is ", "are ", "do ", "does ", "summarize", "summarise",
                        "translate", "define", "give me", "help me", "create", "make a", "list ", "suggest"]
        return starters.contains { lower.hasPrefix($0) }
    }
}

/// Apple Intelligence on this Mac (macOS 26 and later, Apple silicon, turned on in Settings).
@MainActor
enum AppleIntelligence {
    struct Failure: Error {
        let message: String
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    static let instructions = """
    You are a helpful assistant that lives in the Mac's notch. Answer clearly and briefly: one to \
    four short sentences, or a short list when that's clearer. Plain text only, no Markdown headings or tables.
    """

    /// Returns the answer, and the conversation to pass back in for a follow-up.
    static func ask(_ text: String, session: AnyObject?) async throws -> (String, AnyObject?) {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { throw Failure(message: "Apple Intelligence needs macOS 26 or newer.") }
        guard case .available = SystemLanguageModel.default.availability else {
            throw Failure(message: "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri.")
        }
        let current = (session as? LanguageModelSession) ?? LanguageModelSession(instructions: instructions)
        let response = try await current.respond(to: text)
        return (response.content.trimmingCharacters(in: .whitespacesAndNewlines), current)
        #else
        throw Failure(message: "Apple Intelligence needs macOS 26 or newer.")
        #endif
    }
}

/// A small, safe calculator for the search bar: + − × ÷ ^ % and brackets.
enum Calculator {
    static func evaluate(_ input: String) -> Double? {
        let cleaned = input.lowercased()
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")
        guard cleaned.count >= 3, cleaned.contains(where: \.isNumber),
              cleaned.allSatisfy({ "0123456789.+-*/^%()".contains($0) }),
              cleaned.dropFirst().contains(where: { "+-*/^%".contains($0) })
        else { return nil }
        var parser = Parser(chars: Array(cleaned))
        guard let value = parser.expression(), parser.index == parser.chars.count, value.isFinite else { return nil }
        return value
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.10g", value)
    }

    private struct Parser {
        let chars: [Character]
        var index = 0

        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < chars.count, chars[index] == "+" || chars[index] == "-" {
                let op = chars[index]
                index += 1
                guard let rhs = term() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func term() -> Double? {
            guard var value = power() else { return nil }
            while index < chars.count, chars[index] == "*" || chars[index] == "/" || chars[index] == "%" {
                let op = chars[index]
                index += 1
                guard let rhs = power() else { return nil }
                switch op {
                case "*": value *= rhs
                case "/": value /= rhs
                default: value = value.truncatingRemainder(dividingBy: rhs)
                }
            }
            return value
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if index < chars.count, chars[index] == "^" {
                index += 1
                guard let exponent = power() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        mutating func unary() -> Double? {
            if index < chars.count, chars[index] == "-" {
                index += 1
                return unary().map { -$0 }
            }
            if index < chars.count, chars[index] == "+" {
                index += 1
                return unary()
            }
            return primary()
        }

        mutating func primary() -> Double? {
            if index < chars.count, chars[index] == "(" {
                index += 1
                let value = expression()
                guard index < chars.count, chars[index] == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while index < chars.count, chars[index].isNumber || chars[index] == "." {
                index += 1
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }
    }
}
