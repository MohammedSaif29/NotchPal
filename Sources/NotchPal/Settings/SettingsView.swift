// NotchPal, the notch that's alive.
// Copyright (C) 2026 Mohammed Saif (https://github.com/MohammedSaif29/NotchPal)
// SPDX-License-Identifier: GPL-3.0-only

import AVFoundation
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case appearance
    case size
    case widgets
    case battery
    case music
    case calendar
    case notifications
    case privacy
    case games
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Look & Glass"
        case .size: "Size"
        case .widgets: "Widgets"
        case .battery: "Battery"
        case .music: "Music"
        case .calendar: "Calendar"
        case .notifications: "Notifications"
        case .privacy: "Privacy & Camera"
        case .games: "Games"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .size: "arrow.up.left.and.arrow.down.right"
        case .widgets: "square.grid.2x2.fill"
        case .battery: "battery.75percent"
        case .music: "music.note"
        case .calendar: "calendar"
        case .notifications: "bell.badge.fill"
        case .privacy: "hand.raised.fill"
        case .games: "gamecontroller.fill"
        case .about: "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .appearance: .purple
        case .size: .indigo
        case .widgets: .blue
        case .battery: .green
        case .music: .pink
        case .calendar: .red
        case .notifications: .orange
        case .privacy: .teal
        case .games: .mint
        case .about: .cyan
        }
    }
}

/// Which Settings page is showing, so the menu bar's "About NotchPal" can jump straight to About.
@MainActor
@Observable
final class SettingsNavigation {
    var page: SettingsPage? = .appearance
}

struct SettingsView: View {
    let app: AppModel
    @Bindable private var navigation: SettingsNavigation

    init(app: AppModel) {
        self.app = app
        _navigation = Bindable(wrappedValue: app.settingsNavigation)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $navigation.page) { item in
                Label {
                    Text(item.title)
                } icon: {
                    SettingsIcon(symbol: item.symbol, color: item.color)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            let current = navigation.page ?? .general
            detail(for: current)
                .navigationTitle(current.title)
        }
        .frame(minWidth: 760, minHeight: 540)
    }

    @ViewBuilder
    private func detail(for page: SettingsPage) -> some View {
        switch page {
        case .general: GeneralSettings(app: app)
        case .appearance: AppearanceSettings(app: app)
        case .size: SizeSettings(app: app)
        case .widgets: WidgetSettings(app: app)
        case .battery: BatterySettings(app: app)
        case .music: MusicSettings(app: app)
        case .calendar: CalendarSettings(app: app)
        case .notifications: NotificationSettings(app: app)
        case .privacy: PrivacySettings(app: app)
        case .games: GamesSettings(app: app)
        case .about: AboutSettings(app: app)
        }
    }
}

private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.gradient))
    }
}

/// A labelled slider with its value shown on the right.
private struct SliderRow: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { "\(Int($0)) pt" }

    var body: some View {
        // No `step:` on the Slider itself: macOS would draw a tick mark for every step.
        let snapped = Binding<Double>(
            get: { value.wrappedValue },
            set: { newValue in
                let rounded = (newValue / step).rounded() * step
                let clamped = min(range.upperBound, max(range.lowerBound, rounded))
                if clamped != value.wrappedValue {
                    value.wrappedValue = clamped
                }
            }
        )
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: snapped, in: range)
                    .frame(maxWidth: 280)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// A Color binding stored as "#RRGGBB" text.
@MainActor
private func hexBinding(_ get: @escaping () -> String, _ set: @escaping (String) -> Void, fallback: Color) -> Binding<Color> {
    Binding(
        get: { Color(hex: get()) ?? fallback },
        set: { set($0.hexString) }
    )
}

// MARK: General

private struct GeneralSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore
    private let launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open NotchPal at login", isOn: launchAtLogin.projectedValue)
                    .onChange(of: launchAtLogin.wrappedValue) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("NotchPal: login item change failed: \(error.localizedDescription)")
                        }
                        // macOS sometimes wants you to approve login items in System Settings first.
                        if enabled && SMAppService.mainApp.status == .requiresApproval {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        let actual = SMAppService.mainApp.status == .enabled
                        if !enabled || SMAppService.mainApp.status != .requiresApproval,
                           actual != launchAtLogin.wrappedValue {
                            launchAtLogin.wrappedValue = actual
                        }
                    }
                Toggle("Say hi when NotchPal starts", isOn: $settings.sayHello)
            }

            Section("Opening the island") {
                Picker("Open when", selection: $settings.openOnHover) {
                    Text("Hovering").tag(true)
                    Text("Clicking").tag(false)
                }
                .pickerStyle(.segmented)
                if settings.openOnHover {
                    SliderRow(title: "Hover delay", value: $settings.hoverDelay, range: 0...1, step: 0.1) {
                        String(format: "%.1fs", $0)
                    }
                }
                Picker("Open to", selection: $settings.openTo) {
                    Text("The last tab I used").tag("last")
                    ForEach(IslandTab.allCases) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }
                Toggle("Haptic feedback on the trackpad", isOn: $settings.haptics)
                Toggle("Swipe sideways on the island to change songs", isOn: $settings.swipeGestures)
            }

            Section("Live alerts") {
                Toggle("Charging and low battery", isOn: $settings.batteryAlerts)
                Toggle("AirPods and headphones connecting", isOn: $settings.deviceAlerts)
                Toggle("A new song starts", isOn: $settings.songAlerts)
                Toggle("Meetings about to start", isOn: $settings.calendarAlerts)
                Toggle("New messages (needs Notifications turned on)", isOn: $settings.messageAlerts)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Look & Glass

private struct AppearanceSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section {
                IslandPreview(app: app)
                    .frame(height: 170)
            }

            Section("Style") {
                Picker("Island style", selection: $settings.style) {
                    ForEach(IslandStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(styleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.style.isGlass {
                Section("Glass") {
                    SliderRow(title: "Darkness", value: $settings.glassDarkness, range: 0...0.8, step: 0.02) {
                        "\(Int(($0 * 100).rounded()))%"
                    }
                    Picker("Tint", selection: $settings.glassTint) {
                        ForEach(GlassTint.allCases) { tint in
                            Text(tint.label).tag(tint)
                        }
                    }
                    .pickerStyle(.segmented)
                    if settings.glassTint == .custom {
                        ColorPicker("Tint color",
                                    selection: hexBinding({ settings.glassTintHex }, { settings.glassTintHex = $0 }, fallback: .blue),
                                    supportsOpacity: false)
                    }
                    Toggle("Blend the top into the notch", isOn: $settings.glassBlendTop)
                    Toggle("Shiny edge", isOn: $settings.glassBorder)
                    Toggle("Use glass for the closed island too", isOn: $settings.glassWhenClosed)
                }
            }

            Section("Motion") {
                Picker("Animation", selection: $settings.motion) {
                    ForEach(MotionStyle.allCases) { motion in
                        Text(motion.label).tag(motion)
                    }
                }
                .pickerStyle(.segmented)
                SliderRow(title: "Shadow", value: $settings.shadowStrength, range: 0...1, step: 0.05) {
                    "\(Int(($0 * 100).rounded()))%"
                }
                HStack {
                    Spacer()
                    Button("Try it on the notch") { app.openIsland(tab: .home, hold: 4) }
                }
            }

            Section("Accent color") {
                AccentPicker(selection: $settings.accent)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset look") { settings.resetAppearance() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var styleNote: String {
        switch settings.style {
        case .black:
            return "Solid black, so the island blends perfectly with the camera."
        case .glass:
            return hasLiquidGlass
                ? "Apple's Liquid Glass: it bends and reflects whatever is behind it."
                : "Liquid Glass needs macOS 26, so this Mac shows frosted glass instead."
        case .frosted:
            return "A soft, blurry glass, like Control Center."
        case .clear:
            return "Very see-through glass. Turn up Darkness if text is hard to read."
        }
    }
}

/// A live mini island on a colourful wallpaper, so you can see style, size and accent.
private struct IslandPreview: View {
    let app: AppModel

    var body: some View {
        let settings = app.settings
        let look = IslandLook.current(app, expanded: true)
        let scale = 0.42
        let width = CGFloat(settings.openWidth * scale)
        let height = CGFloat((settings.openHeight + 32) * scale)
        let shape = NotchShape(topRadius: 6, bottomRadius: CGFloat(settings.cornerRadius * scale * 1.2))
        let accent = app.accent

        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.22, blue: 0.78),
                                    Color(red: 0.95, green: 0.45, blue: 0.42),
                                    Color(red: 1.0, green: 0.76, blue: 0.36)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 120)
                .blur(radius: 26)
                .offset(x: -80, y: 60)

            ZStack(alignment: .top) {
                IslandBackground(look: look, shape: shape)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LinearGradient(colors: [accent, accent.opacity(0.45)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(Color.white.opacity(0.85)).frame(width: 80, height: 6)
                        Capsule().fill(Color.white.opacity(0.4)).frame(width: 54, height: 5)
                    }
                    Spacer(minLength: 0)
                    VisualizerBars(playing: true, tint: accent, height: 13)
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .shadow(color: .black.opacity(look.style == .black ? 0.5 * settings.shadowStrength : 0.3 * settings.shadowStrength),
                    radius: 10, y: 5)
            .environment(\.colorScheme, .dark)
            .animation(settings.motion.spring, value: settings.openWidth)
            .animation(settings.motion.spring, value: settings.openHeight)
            .animation(.easeInOut(duration: 0.25), value: look)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AccentPicker: View {
    @Binding var selection: AccentChoice

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AccentChoice.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    Circle()
                        .fill(swatch(for: choice))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(selection == choice ? 0.85 : 0), lineWidth: 2)
                                .padding(-4)
                        )
                }
                .buttonStyle(.plain)
                .help(choice.label)
            }
            Spacer()
            Text(selection.label)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func swatch(for choice: AccentChoice) -> AnyShapeStyle {
        if let color = choice.fixedColor {
            return AnyShapeStyle(color)
        }
        return AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                             center: .center))
    }
}

// MARK: Size

private struct SizeSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section {
                IslandPreview(app: app)
                    .frame(height: 170)
            }

            Section("Quick sizes") {
                HStack(spacing: 10) {
                    ForEach(SizePreset.allCases) { preset in
                        Button(preset.label) { settings.apply(preset) }
                    }
                    Spacer()
                    Button("Try it on the notch") { app.openIsland(tab: .home, hold: 4) }
                }
            }

            Section("Open island") {
                SliderRow(title: "Width", value: $settings.openWidth, range: 480...800, step: 10)
                SliderRow(title: "Length", value: $settings.openHeight, range: 150...320, step: 5)
                SliderRow(title: "Corner roundness", value: $settings.cornerRadius, range: 12...56, step: 1)
            }

            Section("Closed island") {
                SliderRow(title: "Wing width", value: $settings.wingWidth, range: 44...120, step: 2)
                SliderRow(title: "Extra height", value: $settings.closedExtraHeight, range: 0...14, step: 1)
                Text("Wings are the parts either side of the camera that show music, timers, the battery and your pet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset size") { settings.resetSize() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Widgets

private struct WidgetSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section {
                ForEach(settings.tabOrder) { tab in
                    WidgetRow(
                        tab: tab,
                        isOn: Binding(
                            get: { !settings.hiddenTabs.contains(tab) },
                            set: { settings.setTab(tab, visible: $0) }
                        ),
                        canMoveUp: settings.tabOrder.first != tab,
                        canMoveDown: settings.tabOrder.last != tab,
                        move: { settings.moveTab(tab, by: $0) }
                    )
                }
            } header: {
                Text("Widgets in the open island")
            } footer: {
                Text("Turn widgets on or off and change their order. The first ones sit left of the camera, the rest on the right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if app.shelf.items.isEmpty {
                    Text("No apps yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(app.shelf.items) { item in
                    HStack(spacing: 10) {
                        Image(nsImage: app.shelf.icon(for: item))
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(item.name)
                        Spacer()
                        Button { app.shelf.move(item, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless)
                            .disabled(app.shelf.items.first == item)
                            .help("Move up")
                        Button { app.shelf.move(item, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless)
                            .disabled(app.shelf.items.last == item)
                            .help("Move down")
                        Button { app.shelf.remove(item) } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from the notch")
                    }
                }
                HStack {
                    Spacer()
                    Button("Add Apps…") { app.shelf.pickApps() }
                }
            } header: {
                Text("Apps in the notch")
            } footer: {
                Text("These are the apps in the Apps tab. You can also right-click an app in the notch to move or remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In the closed notch") {
                Toggle(isOn: $settings.pet) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notch pet")
                        Text("Pal dances to music, eats while charging, sweats when the battery is low and naps late at night.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $settings.privacyDots) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy dots")
                        Text("A green dot while any app uses the camera, orange for the microphone. Just like iPhone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Battery options are on the Battery page.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetRow: View {
    let tab: IslandTab
    let isOn: Binding<Bool>
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.symbol)
                .frame(width: 22)
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                Text(tab.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move up")
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move down")
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: Battery

private struct BatterySettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section {
                BatteryPreview(app: app)
                    .frame(height: 86)
            }

            Section("Style") {
                BatteryStylePicker(app: app)
                if settings.batteryStyle == .emoji {
                    ForEach(EmojiPack.allCases) { pack in
                        Button {
                            settings.emojiPack = pack
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: settings.emojiPack == pack ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(settings.emojiPack == pack ? Color.accentColor : Color.secondary)
                                Text(pack.label)
                                    .frame(width: 70, alignment: .leading)
                                Text(pack.levels.joined(separator: " "))
                                    .font(.system(size: 17))
                                Spacer()
                                Text("⚡ \(pack.chargingEmoji)")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("From full to empty. The last one shows while charging.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.batteryStyle != .pill {
                    Toggle("Show the % sign", isOn: $settings.batteryPercentSign)
                }
            }

            Section("In the closed notch") {
                Picker("Show battery", selection: $settings.batteryDisplay) {
                    ForEach(BatteryDisplay.allCases) { display in
                        Text(display.label).tag(display)
                    }
                }
            }

            Section("Color") {
                Picker("Color", selection: $settings.batteryColorMode) {
                    ForEach(BatteryColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if settings.batteryColorMode == .custom {
                    ColorPicker("Custom color",
                                selection: hexBinding({ settings.batteryColorHex }, { settings.batteryColorHex = $0 }, fallback: .green),
                                supportsOpacity: false)
                }
                if settings.batteryColorMode == .auto {
                    Text("White, green while charging, yellow in Low Power Mode, and red at 20% or less.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Alerts") {
                Toggle("Alert when charging starts and when the battery gets low", isOn: $settings.batteryAlerts)
            }
        }
        .formStyle(.grouped)
    }
}

/// The battery styles side by side, each drawn with your real battery level.
private struct BatteryStylePicker: View {
    let app: AppModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(BatteryStyle.allCases) { style in
                let selected = app.settings.batteryStyle == style
                Button {
                    withAnimation(.snappy) { app.settings.batteryStyle = style }
                } label: {
                    VStack(spacing: 6) {
                        BatteryBadge(reading: BatteryReading.current(app, style: style), size: 14)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.1),
                                                  lineWidth: selected ? 2 : 1)
                            )
                            .environment(\.colorScheme, .dark)
                        Text(style.label)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(style.label)
            }
        }
        .padding(.vertical, 4)
    }
}

/// What the battery will look like in your closed notch, using the real battery level.
private struct BatteryPreview: View {
    let app: AppModel

    var body: some View {
        let power = app.power
        ZStack {
            LinearGradient(colors: [Color(white: 0.85), Color(white: 0.7)], startPoint: .top, endPoint: .bottom)
            HStack(spacing: 0) {
                Group {
                    if app.settings.pet {
                        NotchPet(app: app)
                    } else {
                        BatteryWing(app: app, side: .leading)
                    }
                }
                .frame(width: 70)
                Color.clear.frame(width: 90)
                BatteryWing(app: app, side: .trailing)
                    .frame(width: 70)
            }
            .frame(height: 34)
            .foregroundStyle(.white)
            .background(NotchShape(topRadius: 6, bottomRadius: 12).fill(Color.black))
            .frame(maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
            Text(power.hasBattery ? power.timeDescription : "This Mac has no battery")
                .font(.caption)
                .foregroundStyle(.black.opacity(0.6))
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: Music

private struct MusicSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section("Now Playing") {
                LabeledContent("Status") {
                    Label(status.text, systemImage: status.symbol)
                        .foregroundStyle(status.color)
                }
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("In the closed notch") {
                Toggle("Show album art", isOn: $settings.showArtworkInNotch)
                Toggle("Show the music visualizer", isOn: $settings.showVisualizer)
                Toggle("Swipe sideways on the island to change songs", isOn: $settings.swipeGestures)
                Toggle("Pop up when a new song starts", isOn: $settings.songAlerts)
            }

            Section("Music apps") {
                ForEach(MusicAppCatalog.entries(seen: settings.seenMusicApps)) { entry in
                    HStack(spacing: 10) {
                        Image(nsImage: entry.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                        Text(entry.name)
                        Spacer()
                        Toggle("", isOn: showsBinding(entry.id))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
                Toggle("Show the app's icon on the album art", isOn: $settings.showSourceBadge)
                Text("Every app gets the same player in the notch, with artwork, seek bar and controls. Turn an app off to keep its sound out of the notch, like videos in your browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let track = app.nowPlaying.track {
                Section("Playing now") {
                    LabeledContent("Song", value: track.title)
                    if !track.artist.isEmpty {
                        LabeledContent("Artist", value: track.artist)
                    }
                    if let appName = track.appName {
                        LabeledContent("App", value: appName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func showsBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenMusicApps.contains(bundleID) },
            set: { show in
                var hidden = settings.hiddenMusicApps.filter { $0 != bundleID }
                if !show {
                    hidden.append(bundleID)
                }
                settings.hiddenMusicApps = hidden
                app.nowPlaying.refilter()
            }
        )
    }

    private var status: (text: String, symbol: String, color: Color, detail: String) {
        switch app.nowPlaying.source {
        case .mediaRemote:
            return ("Works with every app", "checkmark.circle.fill", .green,
                    "Music, Spotify, YouTube in your browser, VLC and anything else that shows up in Control Center.")
        case .scripting:
            return ("Spotify and Apple Music only", "exclamationmark.circle.fill", .orange,
                    "macOS didn't allow the full Now Playing helper, so NotchPal is using a simpler method.")
        case .waiting:
            return ("Waiting for music", "clock", .secondary,
                    "Play something and it will show up in the notch.")
        }
    }
}

/// Music apps on this Mac: the ones NotchPal has seen playing, plus well-known players and browsers.
@MainActor
private enum MusicAppCatalog {
    struct Entry: Identifiable {
        let id: String
        let name: String
        let icon: NSImage
    }

    static let known = [
        "com.apple.Music", "com.spotify.client", "com.apple.podcasts", "com.apple.TV",
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "org.mozilla.firefox", "com.microsoft.edgemac", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "org.videolan.vlc", "com.colliderli.iina", "com.tidal.desktop", "com.deezer.deezer-desktop",
        "com.amazon.music", "com.github.th-ch.youtube-music", "tv.plex.plexamp",
    ]

    /// Looking apps up is slow, so each is only looked up once.
    private static var cache: [String: Entry?] = [:]

    static func entries(seen: [String]) -> [Entry] {
        var ids: [String] = []
        for id in seen + known where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap(entry(for:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func entry(for bundleID: String) -> Entry? {
        if let cached = cache[bundleID] {
            return cached
        }
        var found: Entry?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                name = String(name.dropLast(4))
            }
            found = Entry(id: bundleID, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        }
        cache.updateValue(found, forKey: bundleID)
        return found
    }
}

// MARK: Calendar

private struct CalendarSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        let calendar = app.calendar
        Form {
            Section("Access") {
                switch calendar.access {
                case .granted:
                    Label("NotchPal can see your calendars", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unknown:
                    HStack {
                        Text("Show your events in the notch")
                        Spacer()
                        Button("Allow Access") { calendar.requestAccess() }
                    }
                case .denied:
                    HStack {
                        Label("Calendar access is off", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Open Settings") { calendar.openPrivacySettings() }
                    }
                }
                Text("Includes every calendar in the Calendar app, like iCloud, Google and Outlook. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Toggle("Pop up before a meeting starts", isOn: $settings.calendarAlerts)
                Picker("How early", selection: $settings.calendarLeadMinutes) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
                .disabled(!settings.calendarAlerts)
                Toggle("Show all-day events", isOn: $settings.showAllDayEvents)
                    .onChange(of: settings.showAllDayEvents) {
                        calendar.reload()
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Notifications

private struct NotificationSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        let badges = app.badges
        Form {
            Section {
                Toggle("Show unread counts from Dock apps", isOn: $settings.badgesEnabled)
                    .onChange(of: settings.badgesEnabled) { _, enabled in
                        badges.setEnabled(enabled)
                        if enabled && !badges.trusted {
                            badges.requestAccess()
                        }
                    }
                Toggle("Pop up when a new message arrives", isOn: $settings.messageAlerts)
                    .disabled(!settings.badgesEnabled)
            } footer: {
                Text("macOS doesn't let apps read your notifications. Instead, NotchPal reads the red unread counts on your Dock icons, so it works with any app in your Dock: Messages, WhatsApp, Mail, Slack, Telegram and more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if settings.badgesEnabled {
                Section("Permission") {
                    if badges.trusted {
                        Label("Accessibility access is on", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack {
                            Label("Needs Accessibility access", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Allow") { badges.requestAccess() }
                            Button("Open Settings") { badges.openAccessibilitySettings() }
                        }
                        Text("Turn on NotchPal in Privacy & Security → Accessibility. While you're developing NotchPal, every rebuild counts as a new app, so you may need to switch it off and on again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Unread right now") {
                    if badges.badges.isEmpty {
                        Text(badges.trusted ? "All caught up." : "Waiting for permission.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(badges.badges) { badge in
                            LabeledContent {
                                Text(badge.count)
                                    .monospacedDigit()
                            } label: {
                                Label {
                                    Text(badge.name)
                                } icon: {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: badge.path))
                                        .resizable()
                                        .frame(width: 18, height: 18)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Privacy & Camera

private struct PrivacySettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section("Privacy dots") {
                Toggle("Show green and orange dots when the camera or microphone is in use", isOn: $settings.privacyDots)
                LabeledContent("Right now") {
                    HStack(spacing: 14) {
                        Label(app.privacy.cameraInUse ? "Camera on" : "Camera off", systemImage: "video.fill")
                            .foregroundStyle(app.privacy.cameraInUse ? Color.green : Color.secondary)
                        Label(app.privacy.micInUse ? "Mic on" : "Mic off", systemImage: "mic.fill")
                            .foregroundStyle(app.privacy.micInUse ? Color.orange : Color.secondary)
                    }
                }
                Text("NotchPal only checks whether they're in use. It never sees or hears anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Mirror") {
                Picker("Shape", selection: $settings.mirrorShape) {
                    ForEach(MirrorShape.allCases) { shape in
                        Label(shape.label, systemImage: shape.symbol).tag(shape)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Flip the picture like a real mirror", isOn: $settings.mirrorFlip)
                LabeledContent("Camera access") {
                    Text(cameraStatus)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Open Camera Settings") { app.camera.openPrivacySettings() }
                    Button("Open Mirror") { app.openIsland(tab: .camera, hold: 4) }
                }
                Text("The camera only turns on while the Mirror tab is open. Nothing is recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("What NotchPal never does") {
                Label("Go online or send anything anywhere", systemImage: "wifi.slash")
                Label("Record your camera, microphone or screen", systemImage: "record.circle")
                Label("Read your messages or notification text", systemImage: "eye.slash")
            }
        }
        .formStyle(.grouped)
    }

    private var cameraStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "Allowed"
        case .notDetermined: return "Not asked yet"
        case .denied, .restricted: return "Off"
        @unknown default: return "Unknown"
        }
    }
}

// MARK: Games

private struct GamesSettings: View {
    let app: AppModel
    @Bindable private var settings: SettingsStore

    init(app: AppModel) {
        self.app = app
        _settings = Bindable(wrappedValue: app.settings)
    }

    var body: some View {
        Form {
            Section("Play") {
                Picker("Difficulty", selection: $settings.difficulty) {
                    ForEach(Difficulty.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Game sounds", isOn: $settings.gameSounds)
                HStack {
                    Spacer()
                    Button("Play now") { app.openIsland(tab: .play, hold: 4) }
                }
            }

            Section("Best scores") {
                ForEach(GameKind.allCases) { kind in
                    LabeledContent {
                        Text("\(app.games.game(for: kind).best)")
                            .monospacedDigit()
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
                HStack {
                    Spacer()
                    Button("Reset scores", role: .destructive) { app.games.clearScores() }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.difficulty) {
            app.games.resetAll()
        }
    }
}

// MARK: About

private struct AboutSettings: View {
    let app: AppModel

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.2), .black], startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 88)
                Capsule()
                    .fill(Color.black)
                    .frame(width: 52, height: 18)
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .offset(y: -22)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .top, endPoint: .bottom))
                    .offset(y: 10)
            }
            VStack(spacing: 4) {
                Text("NotchPal")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Version \(version) · The notch that's alive.")
                    .foregroundStyle(.secondary)
                Text("Made by **\(Credits.author)**")
                    .font(.system(size: 14))
                    .padding(.top, 4)
            }

            HStack(spacing: 10) {
                LinkButton(title: "LinkedIn", symbol: "person.crop.circle.fill", url: Credits.linkedIn)
                LinkButton(title: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: Credits.github)
                LinkButton(title: "Report a Problem", symbol: "ladybug.fill", url: Credits.reportProblem)
                LinkButton(title: "Updates", symbol: "arrow.down.circle.fill", url: Credits.releases)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Free and open source (GNU GPLv3)", systemImage: "heart.fill")
                Label("Never goes online by itself, and collects nothing", systemImage: "lock.shield.fill")
                Label("No account, no ads, no tracking", systemImage: "hand.raised.fill")
            }
            .font(.callout)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))

            Text("The official NotchPal is only at github.com/MohammedSaif29/NotchPal.\nCopies made by others must use a different name and icon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// A button that opens a web page in your browser. NotchPal itself never connects anywhere.
private struct LinkButton: View {
    let title: String
    let symbol: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
        }
        .controlSize(.large)
        .help(url.absoluteString)
    }
}
