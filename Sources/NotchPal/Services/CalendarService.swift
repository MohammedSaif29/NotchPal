// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import EventKit
import Observation
import SwiftUI

/// One event from the Calendar app.
struct CalendarItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    /// Zoom, Google Meet, Teams, FaceTime or Webex link, if the event has one.
    let meetingURL: URL?

    func isHappening(at now: Date = .now) -> Bool {
        start <= now && now < end
    }
}

/// Today's and tomorrow's events from Apple Calendar (which includes Google and Outlook
/// calendars added in System Settings), plus a heads-up before each one starts.
@MainActor
@Observable
final class CalendarService {
    enum Access {
        case unknown
        case granted
        case denied
    }

    private(set) var access: Access = .unknown
    private(set) var events: [CalendarItem] = []

    @ObservationIgnored var onUpcoming: (@MainActor (CalendarItem, Int) -> Void)?

    private let settings: SettingsStore
    private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var announced: Set<String> = []

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reload()
                self?.checkUpcoming()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
        reload()
    }

    /// Shows macOS's calendar permission prompt.
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = granted ? .granted : .denied
                    self.reload()
                }
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func join(_ event: CalendarItem) {
        if let url = event.meetingURL {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        updateAccess()
        guard access == .granted else {
            if !events.isEmpty { events = [] }
            return
        }
        let now = Date()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: dayStart) else { return }

        let includeAllDay = settings.showAllDayEvents
        let predicate = store.predicateForEvents(withStart: dayStart, end: end, calendars: nil)
        let matching = store.events(matching: predicate)
            .filter { $0.endDate > now && (includeAllDay || !$0.isAllDay) }
            .sorted { $0.startDate < $1.startDate }
        var items: [CalendarItem] = []
        for event in matching.prefix(12) {
            items.append(Self.item(from: event))
        }
        if items != events { events = items }
    }

    private func updateAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let next: Access
        switch status {
        case .fullAccess:
            next = .granted
        case .notDetermined:
            next = .unknown
        default:
            next = .denied
        }
        if next != access { access = next }
    }

    private func checkUpcoming() {
        guard settings.calendarAlerts else { return }
        let now = Date()
        let lead = Double(settings.calendarLeadMinutes)
        for event in events where !event.isAllDay && !announced.contains(event.id) {
            let minutes = event.start.timeIntervalSince(now) / 60
            if minutes > 0 && minutes <= lead {
                announced.insert(event.id)
                onUpcoming?(event, max(1, Int(minutes.rounded())))
            }
        }
    }

    private static func item(from event: EKEvent) -> CalendarItem {
        let start: Date = event.startDate ?? Date()
        let end: Date = event.endDate ?? start
        let identifier = event.eventIdentifier ?? UUID().uuidString
        let tint = event.calendar?.cgColor.map { Color(cgColor: $0) } ?? Color.blue
        return CalendarItem(
            id: identifier + "-\(Int(start.timeIntervalSince1970))",
            title: (event.title ?? "").isEmpty ? "Untitled event" : (event.title ?? ""),
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            color: tint,
            location: event.location,
            meetingURL: meetingLink(in: event)
        )
    }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "facetime.apple.com", "whereby.com", "meet.jit.si",
    ]

    private static func meetingLink(in event: EKEvent) -> URL? {
        var texts: [String] = []
        if let url = event.url { texts.append(url.absoluteString) }
        if let location = event.location { texts.append(location) }
        if let notes = event.notes { texts.append(notes) }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, options: [], range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host.contains($0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
