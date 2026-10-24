// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// Calendar: today's date and your next events, with Join for online meetings.
struct CalendarTab: View {
    let app: AppModel

    var body: some View {
        let calendar = app.calendar
        let scale = IslandLayout.contentScale(app)
        HStack(spacing: 12 * scale) {
            TodayCard(scale: scale)
                .frame(width: 104 * scale)
                .onTapGesture { calendar.openCalendarApp() }
            Group {
                switch calendar.access {
                case .granted:
                    if calendar.events.isEmpty {
                        EmptyCalendar()
                    } else {
                        EventList(app: app)
                    }
                case .unknown:
                    CalendarPermission(
                        message: "See your next meetings here, with a Join button for Zoom, Meet and Teams.",
                        button: "Allow Calendar Access"
                    ) {
                        calendar.requestAccess()
                    }
                case .denied:
                    CalendarPermission(
                        message: "Calendar access is off. Turn on NotchPal in Privacy & Security → Calendars.",
                        button: "Open Settings"
                    ) {
                        calendar.openPrivacySettings()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { calendar.reload() }
    }
}

private struct TodayCard: View {
    let scale: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2 * scale) {
                Text(context.date, format: .dateTime.weekday(.wide))
                    .font(.system(size: max(9.5, 11 * scale), weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
                    .textCase(.uppercase)
                Text(context.date, format: .dateTime.day())
                    .font(.system(size: 40 * scale, weight: .bold, design: .rounded))
                Text(context.date, format: .dateTime.month(.wide))
                    .font(.system(size: max(9.5, 11 * scale), weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.07)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .help("Open Calendar")
    }
}

private struct EventList: View {
    let app: AppModel

    var body: some View {
        GeometryReader { proxy in
            // Each row is about 40 points tall plus 6 points of spacing.
            let fits = max(1, Int((proxy.size.height + 6) / 46))
            let events = Array(app.calendar.events.prefix(fits))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(events) { event in
                    EventRow(event: event) { app.calendar.join(event) }
                }
                if app.calendar.events.count > fits {
                    Text("+\(app.calendar.events.count - fits) more today and tomorrow")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct EventRow: View {
    let event: CalendarItem
    let join: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = event.isHappening(at: context.date)
            HStack(spacing: 10) {
                Capsule()
                    .fill(event.color)
                    .frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(timeText(now: context.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(now ? event.color : .white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if event.meetingURL != nil {
                    Button(action: join) {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(now ? Color.green : Color.white.opacity(0.14)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(now ? 0.1 : 0.05)))
        }
    }

    private func timeText(now: Date) -> String {
        if event.isAllDay { return "All day" }
        if event.isHappening(at: now) {
            let left = max(1, Int(event.end.timeIntervalSince(now) / 60))
            return "Now · \(left) min left"
        }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        let time = event.start.formatted(date: .omitted, time: .shortened)
        if minutes < 60 {
            return "In \(max(1, minutes)) min · \(time)"
        }
        let dayPrefix = Calendar.current.isDateInTomorrow(event.start) ? "Tomorrow " : ""
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(dayPrefix)\(time) – \(end)"
    }
}

private struct EmptyCalendar: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
            Text("Nothing else today")
                .font(.system(size: 13, weight: .semibold))
            Text("Enjoy the free time")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct CalendarPermission: View {
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(showIcon: true)
            content(showIcon: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(showIcon: Bool) -> some View {
        VStack(spacing: 8) {
            if showIcon {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button(action: action) {
                Text(button)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white.opacity(0.16)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// A tiny calendar-page icon showing today's date, used in alerts.
struct CalendarGlyph: View {
    let date: Date
    var size: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(red: 1, green: 0.3, blue: 0.3))
                .frame(height: size * 0.28)
            Text(date, format: .dateTime.day())
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxHeight: .infinity)
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
